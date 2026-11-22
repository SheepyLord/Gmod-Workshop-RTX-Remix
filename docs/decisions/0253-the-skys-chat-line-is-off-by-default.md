# 0253: The sky's chat line is off by default

- Status: Accepted 2026-11-21 (the user's request: "Make this notice hidden by default", with a screenshot of the line);
  supersedes in part [ADR 0249](0249-which-sky-a-map-shows.md) (decision 6: the line's default)
- Package only: the companion (`nativeloader_sky.lua`, `nativeloader_defaults.lua`).

## Context

ADR 0249 added one chat line at each map's start, on by default: "[RTX] This map shows the RTX sky. It also has a sky of
its own, with a 3D skybox: type nativeloader_sky_here map in the console, or use RTX Remix > Sky and weather in the
spawn menu." The user, seeing it in their game the day it shipped, asked for it hidden by default.

GMod saves a Lua client setting created with the archive flag in `cfg/client.vdf` even at its default: the PoC's file
holds `"nativeloader_sky_message" "1"` after the sessions of ADR 0249. A new default alone would leave the line on in
every game that ran the earlier one, the user's included.

## Decision

1. **`nativeloader_sky_message` defaults to 0**: no chat line at a map's start. "Say which sky shows" in RTX Remix >
   Sky and weather turns it on; the console still gets the English line at every map's start, and the panel still says
   which sky shows.
2. **A saved "on" goes off once**: `nativeloader_defaults.lua`'s `NativeLoaderSkyDefaults` hook (the one R20 added for
   the sky's earlier default change) sets it to 0 when it is on and writes the marker
   `data/nativeloader_companion/sky_message_client_v1.txt`; with the marker there it never touches the setting again,
   so a player who ticks it later keeps it.

## Consequences

- Nobody sees the line unless they tick "Say which sky shows". The line was on by default for one day (the upload of
  ADR 0249); a player who had turned it on on purpose in that day has it off once and ticks it again.
- A map's RTX version's own sky (gm_stelliferous RTX's space) is no longer named in chat at the map's start; the panel
  names it, and the sky shows as ADR 0249 decided.

## Rejected

- **Changing only the default**: the line would stay on in every game that ran ADR 0249's version.
- **Removing the line**: the user asked for it hidden by default, not gone; it helps a player who wants to know.
