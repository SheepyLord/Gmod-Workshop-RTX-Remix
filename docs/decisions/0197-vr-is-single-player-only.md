# 0197: VR is single-player only; V5 is skipped

- Status: Accepted 2026-11-13 (the user's decision).
- Decided by: the user: "Skip V5, currently make it single player only. Proceed directly to V6 and V7."
- Amends: the multiplayer row of the [VR plan's decisions](../handover/VR-plan.md#decisions-taken-with-the-user) and
  [ADR 0160](0160-the-servers-vr-switch-and-local-host.md)'s listen-server host.

## Context

The VR plan gave full VR to single-player and to the listen-server host, a limited mode on other servers, and left both
the multiplayer parts and the IK body to milestone V5 ("Body and multiplayer"). V2-V4 shipped with the single-player
player and the listen-server host's own player accepted, in the VR page's Start check, in the companion's server stub
and again in the add-on's server core. Nothing showed a VR player to anyone else, and no remote-server mode existed.

## Decision

- **V5 is skipped**: no IK body in shadows and reflections, no head and hands for other players, no limited mode on
  other servers. The next VR milestones are V6 (performance) and V7 (true stereo).
- **VR runs in single-player games only.** Start VR on the page and `nl_vr_start` refuse every other game, the
  listen-server host included, with "VR works in single-player games only. Start a single-player game to use VR."
  The companion's server stub (`nativeloader_vr_server.lua`) and the add-on's server core (`sv_core.lua`) accept the
  Start request and the per-tick sync only when `game.SinglePlayer()` is true.

## Consequences

- A player who used VR as a listen-server host now gets the page's server message instead; single-player is unchanged.
- The page's console help and the refusal message changed, with all six companion catalogs translated.
- Tests: the page harness's `host` case and the framework's server case now require the refusal; the V4 stubs run in
  single-player only.
- Multiplayer VR (V5's scope) comes back only when the user asks for it, with a new decision.
