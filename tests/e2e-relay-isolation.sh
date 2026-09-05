#!/bin/bash
# Proves the property this template exists for: the game server can only be
# reached through the relay, and cannot leak around it.
#
# The test builds a miniature of the real thing on one host: a WireGuard
# "VPS" container, a client sidecar dialling it, and a probe running inside
# the sidecar's namespace where the game server would be. No cloud account,
# no game download, nothing to clean up but containers.
#
#   ./tests/e2e-relay-isolation.sh
set -uo pipefail

NET=relay-test-net
VPS=relay-test-vps
SIDECAR=relay-test-wg
PROBE=relay-test-probe
WG_IMAGE="${WIREGUARD_IMAGE_TAG:-linuxserver/wireguard:1.0.20260223-r0-ls121@sha256:bf03578ef7318ccc7675b4a82beac4d35cd0da2253194f6b6ecf61656b40f0ee}"
BUSY="${BUSYBOX_IMAGE_TAG:-busybox:1.37@sha256:9db7b59979c38555a39def84a31fb98b5296952f9e3afd4f6f11f05b07adfab0}"
WORK="$(mktemp -d)"

pass=0; fail=0
ok()   { echo "  PASS: $1"; pass=$((pass + 1)); }
bad()  { echo "  FAIL: $1"; fail=$((fail + 1)); }
note() { echo "  $1"; }

cleanup() {
  docker rm -f "$PROBE" "$SIDECAR" "$VPS" > /dev/null 2>&1
  docker network rm "$NET" > /dev/null 2>&1
  rm -rf "$WORK"
}
trap cleanup EXIT

echo "=== a game server that cannot be reached around its relay"

# A free subnet, because a host that already runs other stacks will have taken
# the obvious ones. Failing to create the network used to be swallowed, and the
# run then reported "no handshake" for a tunnel that was never built.
SUBNET=""
for candidate in 10.199.99 10.198.99 10.197.99 172.30.99; do
  if docker network create --subnet "${candidate}.0/24" "$NET" > /dev/null 2>&1; then
    SUBNET="$candidate"; break
  fi
done
if [ -z "$SUBNET" ]; then
  bad "could not create a test network: every candidate subnet is taken"
  echo; echo "Passed: $pass  Failed: $fail"; exit 1
fi
VPS_IP="${SUBNET}.10"
note "test network on ${SUBNET}.0/24"

# --- the VPS side: a WireGuard server that hands out one peer -----------------
if ! docker run -d --name "$VPS" --network "$NET" --ip "$VPS_IP" \
  --cap-add NET_ADMIN --cap-add SYS_MODULE \
  -e PUID=1000 -e PGID=1000 -e TZ=Etc/UTC \
  -e SERVERURL="$VPS_IP" -e SERVERPORT=51820 -e PEERS=1 \
  -e PEERDNS="$VPS_IP" -e INTERNAL_SUBNET=10.13.13.0 -e ALLOWEDIPS=10.13.13.0/24 \
  -v /lib/modules:/lib/modules:ro "$WG_IMAGE" > /dev/null; then
  bad "the relay container did not start"
  echo; echo "Passed: $pass  Failed: $fail"; exit 1
fi

note "waiting for the relay to generate its peer configuration"
for _ in $(seq 1 60); do
  docker exec "$VPS" test -f /config/peer1/peer1.conf > /dev/null 2>&1 && break
  sleep 2
done
if ! docker exec "$VPS" test -f /config/peer1/peer1.conf > /dev/null 2>&1; then
  bad "the relay never produced a peer configuration"
  echo; echo "Passed: $pass  Failed: $fail"; exit 1
fi

mkdir -p "$WORK/wg_confs"
docker exec "$VPS" cat /config/peer1/peer1.conf > "$WORK/wg_confs/wg0.conf"
# The peer file points at the server by name; inside this test it is an address.
sed -i.bak "s|^Endpoint *=.*|Endpoint = ${VPS_IP}:51820|" "$WORK/wg_confs/wg0.conf"
rm -f "$WORK/wg_confs/wg0.conf.bak"

# --- the home side: the sidecar, and the probe inside its namespace ----------
# The published port is the local door: bound to one address, not 0.0.0.0.
if ! docker run -d --name "$SIDECAR" --network "$NET" --ip "${SUBNET}.20" \
  --cap-add NET_ADMIN --cap-add SYS_MODULE \
  -e PUID=1000 -e PGID=1000 -e TZ=Etc/UTC \
  -p 127.0.0.1:25565:25565/tcp \
  -v "$WORK:/config" -v /lib/modules:/lib/modules:ro "$WG_IMAGE" > /dev/null; then
  bad "the sidecar container did not start"
  echo; echo "Passed: $pass  Failed: $fail"; exit 1
fi

note "waiting for the tunnel to carry a handshake"
handshake=0
for _ in $(seq 1 60); do
  # WireGuard handshakes when there is something to send. A tunnel nobody has
  # used shows no handshake and is indistinguishable from a broken one, which
  # is why a relay peer needs PersistentKeepalive in production: without it the
  # NAT mapping at home expires and inbound traffic stops arriving.
  docker exec "$SIDECAR" ping -c 1 -W 2 10.13.13.1 > /dev/null 2>&1
  hs=$(docker exec "$SIDECAR" wg show wg0 latest-handshakes 2>/dev/null | awk '{print $2}' | head -1)
  if [ -n "$hs" ] && [ "$hs" != "0" ]; then handshake=1; break; fi
  sleep 2
done
if [ "$handshake" = 1 ]; then ok "the tunnel completed a handshake"; else bad "no handshake within 120s"; fi

docker run -d --name "$PROBE" --network "container:$SIDECAR" "$BUSY" \
  sh -c 'while true; do printf "HTTP/1.1 200 OK\r\nContent-Length: 5\r\n\r\nalive" | nc -l -p 25565; done' > /dev/null

echo
echo "=== the game container has no network of its own"
own=$(docker inspect "$PROBE" --format '{{ .NetworkSettings.IPAddress }}{{ range $k, $v := .NetworkSettings.Networks }}{{ $k }}{{ end }}')
if [ -z "$own" ]; then
  ok "no address and no network attached to the game container"
else
  bad "the game container carries its own network: $own"
fi
mode=$(docker inspect "$PROBE" --format '{{ .HostConfig.NetworkMode }}')
case "$mode" in
  container:*|service:*) ok "it runs in the sidecar's namespace ($mode)" ;;
  *) bad "network mode is $mode, so it is not sharing the sidecar" ;;
esac

echo
echo "=== its traffic leaves through the tunnel, with the tunnel's address"
src=$(docker exec "$PROBE" sh -c 'ip route get 10.13.13.1 2>/dev/null' | sed -n 's/.*src \([0-9.]*\).*/\1/p')
if [ -n "$src" ] && [ "${src#10.13.13.}" != "$src" ]; then
  ok "packets to the relay leave with the tunnel address $src"
else
  bad "expected a 10.13.13.x source address, got '${src:-none}'"
fi
if docker exec "$PROBE" ping -c 2 -W 3 10.13.13.1 > /dev/null 2>&1; then
  ok "the relay answers through the tunnel"
else
  bad "the relay is unreachable through the tunnel"
fi

echo
echo "=== the local door answers on the LAN, and only there"
sleep 2
if curl -fsS --max-time 8 http://127.0.0.1:25565/ 2>/dev/null | grep -q alive; then
  ok "a player on the LAN reaches the server directly"
else
  bad "the local door did not answer"
fi
bound=$(docker port "$SIDECAR" 25565/tcp 2>/dev/null | head -1)
case "$bound" in
  0.0.0.0:*|"[::]":*) bad "the door is open to every interface: $bound" ;;
  "") bad "no published port found" ;;
  *) ok "the door is bound to one address only ($bound)" ;;
esac

echo
echo "=== with the relay gone, the server is unreachable rather than exposed"
docker stop "$SIDECAR" > /dev/null 2>&1
sleep 3
if curl -fsS --max-time 5 http://127.0.0.1:25565/ > /dev/null 2>&1; then
  bad "the server still answered after the relay stopped"
else
  ok "the server stopped answering when its relay went down"
fi
state=$(docker inspect "$PROBE" --format '{{ .State.Status }}' 2>/dev/null)
note "game container state after the relay stopped: $state"

echo
echo "Passed: $pass  Failed: $fail"
[ "$fail" -eq 0 ]
