#!/bin/bash

# Prove the tunnel is carrying traffic, not merely that the container is up.
#
#     chmod +x verify-tunnel.sh
#     ./verify-tunnel.sh
#
# WHY THIS IS NOT `docker compose ps`. A WireGuard sidecar can run, report
# healthy to anything watching the process, and carry no tunnel at all: a key
# the relay no longer knows, a configuration the new image reads differently, a
# peer that never answers. `docker compose up -d` returns 0 over every one of
# those. On one host, eight PostUp lines sitting in the wrong block of a
# wg0.conf produced exactly that, the zero exit code hid it, and it stayed
# hidden for thirteen days while the server was unreachable from the internet.
#
# So this reads STATE, in the order a packet needs it:
#   the container is running, judged by its state and not by an exit code;
#   wg0 carries an address, so the interface was actually configured;
#   the peer handshaked recently, so packets are moving in both directions;
#   and the game port answers on the relay's public address, so the path a
#   player takes is intact, which is the only reason any of the above matters.
set -euo pipefail
cd "$(dirname "$0")"

COMPOSE_FILE="${DOCKER_COMPOSE_FILE:-game-server-wireguard-relay-docker-compose.yml}"
PROJECT="${COMPOSE_PROJECT_NAME:-game}"
# PersistentKeepalive is every 25 seconds, so a live tunnel has handshaked well
# inside three minutes. Older than that and packets are not moving.
HANDSHAKE_MAX="${HANDSHAKE_MAX:-180}"
# Set to skip the last check, for a game whose port cannot be tested from here.
SKIP_GAME_PORT="${SKIP_GAME_PORT:-false}"

fail() { echo "  $1" >&2; exit 1; }

CONTAINER="${WG_CONTAINER:-}"
if [ -z "$CONTAINER" ]; then
  CONTAINER="$(docker compose -f "$COMPOSE_FILE" -p "$PROJECT" ps -aq relay-wg | head -n 1)"
fi
[ -n "$CONTAINER" ] || fail "the relay-wg container was not found - is the stack up?"

# 1. Running, by state. `docker compose up -d` exiting 0 says a request was
# accepted, not that anything is alive now.
STATE="$(docker inspect -f '{{.State.Running}}' "$CONTAINER" 2>/dev/null || echo unknown)"
[ "$STATE" = "true" ] || fail "the sidecar is not running (state: $STATE)"
echo "  the sidecar is running"

# 2. An interface with an address. Without one the configuration was read and
# rejected, which looks from outside exactly like a working container.
docker exec "$CONTAINER" ip -4 addr show wg0 2>/dev/null | grep -q 'inet ' \
  || fail "wg0 has no address: the interface was never configured"
echo "  wg0 carries an address"

# 3. A handshake, and a recent one. An interface with no handshake is
# indistinguishable from a working one by every check except this.
TS="$(docker exec "$CONTAINER" wg show wg0 latest-handshakes 2>/dev/null | head -1 | awk '{print $2}')"
case "${TS:-}" in
  ''|*[!0-9]*) fail "no peer on wg0" ;;
esac
[ "$TS" -gt 0 ] || fail "the peer has never handshaked"
AGE=$(( $(date +%s) - TS ))
[ "$AGE" -le "$HANDSHAKE_MAX" ] \
  || fail "the last handshake was ${AGE}s ago, over the ${HANDSHAKE_MAX}s limit: packets are not moving"
echo "  the peer handshaked ${AGE}s ago"

if [ "$SKIP_GAME_PORT" = "true" ]; then
  echo "  the game port was not tested (SKIP_GAME_PORT=true)"
  exit 0
fi

# 4. The path a player takes. Everything above can pass while the relay is not
# forwarding the game port, which is a firewall rule on somebody else's machine
# and the single most common thing left undone.
PROTOCOL="${GAME_PROTOCOL:-tcp}"
if [ "$PROTOCOL" != "tcp" ]; then
  # A UDP port that is open and a UDP port that is dropped look the same from
  # here, and a check that cannot fail is worse than no check.
  echo "  the game speaks $PROTOCOL, which cannot be tested by connecting; check it from a client"
  exit 0
fi
PORT="${GAME_PORT:-25565}"
ENDPOINT="$(docker exec "$CONTAINER" wg show wg0 endpoints 2>/dev/null | head -1 | awk '{print $2}')"
RELAY="${ENDPOINT%%:*}"
[ -n "$RELAY" ] || fail "could not read the relay's address from wg0"
if docker exec "$CONTAINER" timeout 8 nc -z "$RELAY" "$PORT" 2>/dev/null; then
  echo "  $RELAY:$PORT answers, so the relay is forwarding the game port"
else
  fail "$RELAY:$PORT does not answer: the tunnel is up but the relay is not forwarding the game port, or the game is not listening"
fi
