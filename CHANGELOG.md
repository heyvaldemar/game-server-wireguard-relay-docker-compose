# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

_(no unreleased changes yet)_

## [1.3.0] - 2026-09-11

### Added

- **`verify-tunnel.sh`, and an update that will not call itself finished
  without it.** `docker compose up -d` returning 0 says a request was accepted.
  It says nothing about whether the tunnel carries traffic, and this sidecar is
  the game's only network: it can come back as a running, healthy looking
  container with no tunnel at all. A key the relay no longer knows, a
  configuration the new image reads differently, a peer that never answers.
  On one host, eight `PostUp` lines sitting in the wrong block of a `wg0.conf`
  produced exactly that, the zero exit code hid it, and it stayed hidden for
  thirteen days with the server unreachable from the internet the whole time.

  The script reads state in the order a packet needs it. The container is
  running, judged by its state and never by an exit code. `wg0` carries an
  address, so the interface was configured rather than read and rejected. The
  peer handshaked inside `HANDSHAKE_MAX`, three minutes by default, which
  `PersistentKeepalive` at 25 seconds makes generous. And the game port answers
  on the relay's public address, because everything above can pass while the
  relay is simply not forwarding it, which is a firewall rule on somebody else's
  machine and the single most common thing left undone.

  A UDP game is reported as untested rather than passed: an open UDP port and a
  dropped one look the same from here, and a check that cannot fail is worse
  than no check.

  `update.sh` now waits for it after `up -d`, and on failure prints the exact
  command that puts the previous release back, because somebody who has just
  lost their server should not have to go and look up what they were running an
  hour ago.

- A scenario in the isolation suite for the case this is all about: with the
  relay taken away, the sidecar is still running and still looks fine to
  anything watching the process, and `verify-tunnel.sh` refuses it.

## [1.2.2] - 2026-09-10

### Security

- **`itzg/minecraft-server:java25` was rebuilt upstream**; the pin moved from `sha256:d686c51f034d…` to `sha256:c1a267d9ed6d…`. Same version, same tag, a rebuilt base image — the usual shape of a security fix in a base layer.

## [1.2.1] - 2026-09-08

### Security

- **`itzg/minecraft-server:java25` was rebuilt upstream**; the pin moved from `sha256:8672e335dbef…` to `sha256:d686c51f034d…`. Same version, same tag, a rebuilt base image — the usual shape of a security fix in a base layer.

## [1.2.0] - 2026-09-07

### Added

- **`update.sh`: move between release tags on purpose.** It updates to the latest release (a combination this repository's CI has booted and smoke-tested), refuses to cross a major version unattended, refuses to run over local changes, and names any new required variable before anything has moved. `--dry-run` says what would happen.

not be started on a runner, because the sidecar needs a peer on a
  relay that is not there, but the file can be resolved and read: it parses
  with the shipped defaults, the game still has `network_mode:
  service:relay-wg` and therefore no network of its own, every published port
  carries a `host_ip` that is the LAN address rather than every interface, and
  swap is still off on the game container.
- The port check reads the resolved structure rather than grepping near it.
  Compose writes the binding as a `host_ip` key several lines from
  `published`, so a proximity grep answers about the wrong thing — and an
  absent `host_ip`, which is exactly what publishing on every interface looks
  like once resolved, would have passed it.

## [1.0.0] - 2026-09-04

### Added

- **A game server that cannot be reached around its relay.** The game
  container runs in the WireGuard sidecar's network namespace and has no
  interface of its own, so a tunnel that goes down makes the server
  unreachable rather than reachable by a path that exposes the home address.
- **A local door bound to one LAN address.** Without it, players in the same
  building reach their own server by way of the relay and back, measured at
  90 ms where the LAN answers in under one.
- **`tests/e2e-relay-isolation.sh`**, run by CI on every push. It builds a
  WireGuard server, a client sidecar and a probe on one machine and asserts
  the four properties that matter: the game carries no network of its own, its
  packets leave with the tunnel address, the local door is bound to a single
  address, and the server stops answering when the relay stops.
- **The relay side in four commands** (`vps/README.md`), including the two
  rules that turn a rented instance into a route into your house if you get
  them wrong: a narrow `AllowedIPs`, and the masquerade that makes replies
  reach the player who asked.
- Notes in the compose file on the query port that must carry the same number
  inside and outside, on host networking hanging Source engine servers, and on
  why every container has a memory ceiling.

[Unreleased]: https://github.com/heyvaldemar/game-server-wireguard-relay-docker-compose/compare/v1.3.0...HEAD
[1.3.0]: https://github.com/heyvaldemar/game-server-wireguard-relay-docker-compose/releases/tag/v1.3.0
[1.2.2]: https://github.com/heyvaldemar/game-server-wireguard-relay-docker-compose/compare/v1.2.1...v1.2.2
[1.2.1]: https://github.com/heyvaldemar/game-server-wireguard-relay-docker-compose/compare/v1.2.0...v1.2.1
[1.2.0]: https://github.com/heyvaldemar/game-server-wireguard-relay-docker-compose/compare/v1.1.0...v1.2.0
[1.1.0]: https://github.com/heyvaldemar/game-server-wireguard-relay-docker-compose/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/heyvaldemar/game-server-wireguard-relay-docker-compose/releases/tag/v1.0.0
