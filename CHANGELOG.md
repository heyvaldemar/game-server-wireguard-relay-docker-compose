# Changelog

All notable changes to this project are documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

_(no unreleased changes yet)_

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

[Unreleased]: https://github.com/heyvaldemar/game-server-wireguard-relay-docker-compose/compare/v1.0.0...HEAD
[1.0.0]: https://github.com/heyvaldemar/game-server-wireguard-relay-docker-compose/releases/tag/v1.0.0
