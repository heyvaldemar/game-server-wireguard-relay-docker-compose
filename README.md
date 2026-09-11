# Game server behind a WireGuard relay

[![Deployment Verification](https://github.com/heyvaldemar/game-server-wireguard-relay-docker-compose/actions/workflows/deployment-verification.yml/badge.svg?branch=main)](https://github.com/heyvaldemar/game-server-wireguard-relay-docker-compose/actions/workflows/deployment-verification.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)

Run a game server at home and let friends connect to it, without your home IP address appearing in a server list, a query response, or a traceroute.

The game container has no network interface of its own. It runs inside the network namespace of a WireGuard sidecar that dials out to a cheap relay instance. The relay holds the public address, forwards the game port down the tunnel, and masquerades the return path. Players connect to the relay. Your router forwards nothing, because nothing at home listens on the internet.

## Getting started

```bash
# 1. Clone
git clone https://github.com/heyvaldemar/game-server-wireguard-relay-docker-compose
cd game-server-wireguard-relay-docker-compose

# 2. Set up the relay: four commands, in vps/README.md
#    It gives you a peer configuration; put it in ./config/wg_confs/wg0.conf

# 3. Point the local door at this host's LAN address
cp .env.example .env
$EDITOR .env          # LAN_BIND_ADDRESS is required and must not be 0.0.0.0

# 4. Start
docker compose -f game-server-wireguard-relay-docker-compose.yml -p game up -d
```

The reference game here is Minecraft, because it starts in a minute and needs no store account. Any dedicated server works: point `GAME_IMAGE_TAG` at it and set `GAME_PORT` and `GAME_PROTOCOL`.

### What success looks like

```bash
docker compose -p game exec relay-wg wg show wg0 latest-handshakes
# a timestamp within the last two minutes, not 0

docker compose -p game logs game | grep -m1 "Done"
# [Server thread/INFO]: Done (31.8s)! For help, type "help"
```

From a phone on mobile data, connect to the relay address. From a laptop on the same LAN, connect to this host's LAN address. Both reach the same server; only the first crosses the internet.

## What this file knows that a fresh one does not

Five things, each of which cost an evening.

**A player in the next room should not travel to another country.** Without a local door, everyone on your LAN reaches the server the same way the internet does: out to the relay and back. Measured at 90 ms of ping to a machine in the next room, where the LAN answers in under one. The published port in this template is bound to a single LAN address, so nothing is opened to the internet and local players go straight there.

**The query port must carry the same number inside and outside.** A server directory records the port the server binds, not the port you forwarded. Publish one number and bind another and the directory hands players an address where a different server answers: the game connection succeeds, the directory handshake fails against the wrong game, and every log line blames the client. If you move a query port, move it in the game's own configuration.

**Host networking hangs Source engine servers.** For CS2, TF2, Left 4 Dead 2 and Black Mesa, `network_mode: host` on a machine with more than one interface leaves srcds hanging at Steam initialisation with no error. The sidecar namespace used here is bridge-style, which is why these servers start at all.

**Memory limits are about who dies, not about thrift.** With no limit, the kernel's out-of-memory killer picks its victim by size, so a leak in a small process kills the largest innocent one. Every container here has a ceiling, and the game's swap is set to zero: a game server that swaps is one every player can feel.

**Failure should close the door, not open another one.** Because the game has no interface of its own, a tunnel that goes down makes the server unreachable. It never falls back to a direct path that would expose the address the tunnel exists to hide. The test suite asserts exactly this.

## Production checklist

- [ ] **Set `LAN_BIND_ADDRESS` to one address**, never `0.0.0.0`. That single value is the difference between a door for the house and a door for the internet.
- [ ] **Keep `AllowedIPs` on the relay narrow.** `10.13.13.2/32` lets the relay reach the sidecar and nothing else. A wider range turns a rented instance into a route into your home network.
- [ ] **Keep game data at home.** The relay should hold nothing but a tunnel key you can rotate in one command.
- [ ] **Watch the handshake, not the interface.** An interface with no handshake looks identical to a working one. The healthcheck here fails when the last handshake is older than five minutes.
- [ ] **Open the game port in the relay provider's firewall**, and only that port.

## Updating

`./update.sh` moves this checkout to the latest release tag — a combination this repository's CI has booted, upgraded from the previous release on the same volumes, and smoke-tested — and then runs `docker compose up -d`. It refuses to cross a major version unattended, refuses to run over local changes, and names any variable that became required since your version before anything has moved. `./update.sh --dry-run` says what would happen. Every release cut by fleet triage also carries what upstream changed, read from its release notes against this compose file.

It does not stop there, because `up -d` returning 0 says nothing about the tunnel. This sidecar is the game's only network, and it can come back as a running, healthy looking container carrying no tunnel at all: a key the relay no longer knows, a configuration the new image reads differently, a peer that never answers. On one host, eight `PostUp` lines sitting in the wrong block of a `wg0.conf` did exactly that. The zero exit code hid it and it stayed hidden for thirteen days, with the server unreachable the whole time. So the update waits for `verify-tunnel.sh` to say packets are moving, and if they are not it says so loudly and prints the command that puts the previous release back.

Run the same check any time:

```bash
./verify-tunnel.sh
```

It reads state, in the order a packet needs it: the container is running, judged by its state and never by an exit code; `wg0` carries an address, so the interface was configured rather than rejected; the peer handshaked inside the last three minutes, which `PersistentKeepalive` at 25 seconds makes a generous window; and the game port answers on the relay's public address, because everything above can pass while the relay is simply not forwarding it.

## Testing

`tests/e2e-relay-isolation.sh` builds a miniature of this on one machine: a WireGuard server, a client sidecar, and a probe in the sidecar's namespace. It asserts that the game container carries no network of its own, that its packets leave with the tunnel address, that the local door answers on one address only, that the server stops answering when the relay goes down, and that a sidecar still running with a dead tunnel is reported as broken rather than healthy. No cloud account and no game download.

The [Deployment Verification](https://github.com/heyvaldemar/game-server-wireguard-relay-docker-compose/actions/workflows/deployment-verification.yml?query=branch%3Amain) workflow runs it on every push, pull request, and daily, alongside shell and workflow linting and a Trivy scan of the pinned images.

---

## About the maintainer

<div align="center">

**Maintained by [Vladimir Mikhalev](https://github.com/heyvaldemar)** · Docker Captain · IBM Champion · AWS Community Builder

[YouTube](https://www.youtube.com/channel/UCf85kQ0u1sYTTTyKVpxrlyQ?sub_confirmation=1) · [Blog](https://heyvaldemar.com) · [LinkedIn](https://www.linkedin.com/in/heyvaldemar/)

</div>
