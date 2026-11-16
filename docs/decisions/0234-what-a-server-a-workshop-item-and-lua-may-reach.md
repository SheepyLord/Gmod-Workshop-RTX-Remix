# 0234: What a server, a Workshop item and Lua may reach (the repository review of 2026-11-16)

- Status: Accepted 2026-11-16 (the user approved the fixes for the review's list of 30 findings; the checks in the
  report)
- Decided by: the user ("The user approved the fixes for the reported list. Please implement, test the fixes to make
  sure it does not break the game in other aspects and then push to GitHub and Workshop."); how each fix is built was
  the agents' choice. The loader (`winmm.dll`) is not changed: every fix ships in the RTX package.
- Supersedes in part: [0112](0112-fixes-lua-apis-stay-in-the-game-and-follow-the-player.md) (its refusal of fourteen
  path options by name, the only rule `RemixConfig.SetConfigVariable` had: now an allowlist, decision 1) and
  [0050](0050-startup-text-and-main-menu-diagnostics.md) (the startup text's folder, decision 3).
- Amends: [0197](0197-vr-is-single-player-only.md) (the single-player rule is also read natively, decision 5).
- Report: [review-fixes-report.md](../handover/review-fixes-report.md). The review itself:
  `out/review/repository-review.md` (local, not in the repository), summarised in the report.

## Context

A review of the whole repository (bugs, crashes, defensive security; the loader excluded from changes) found 30
problems, five of them high: any subscribed content-only Workshop item could set any Remix option through a Remix
Logic graph; any multiplayer server could make Remix write captures on every frame a key was held, load a texture from
anywhere on the drive or switch replacements off through `RemixConfig.SetConfigVariable`, whose only rule was a
denylist of fourteen path options; a player could make unlimited Model Hotloader characters through "replace" and mint
carriers without bound; a pasted Seamless Portals portal with a huge side count hung the server and every client. The
rest were crashes on crafted input (a manifest, a cached texture, a collision shape, a model with stacked triangles),
values sent to every RTX client unchecked (lights, the sky), tools and editors outside the server's limits and
ownership, absolute paths readable by any server's scripts, and gaps in the development publisher.

What every fix had to keep: everything the RTX package itself does (its Lua sets about 185 Remix options), single-player
and the listen host unchanged where the rule is a server's, the released loader 0.16.0.

## Decision

1. **`RemixConfig.SetConfigVariable` takes only the options the RTX package's own Lua sets** (the fixes' fifteenth
   patch, `lua-guards`, `remix_option_policy.h`): whole groups where the package sets many options from data (the sky,
   weather and fog, the tone curve, the content packs' looks, ReSTIR DI, RTX Water, the companion's `rtx.gmod.*`
   lists) and single options (the game's lights, the RTX Remix tab's settings, the physgun's glow, the texture lists).
   Refused by name whatever the list says: every path option (with `rtx.waterSim.rings.texture`), captures, the
   replacement switches, the sky probe's size, key bindings and crash or debugger hotkeys, the profiler, automation,
   the free camera, the splash and the menu's own settings, `rtx.gmod.fallbackMods`. A value may not name a drive, a
   root, a network path or a parent folder, a hash list holds only hashes, a value is at most 1 MiB. A refused call
   returns `false` and names the option and the reason in the console. Everything else stays with `rtx.conf` and the
   Remix menu; developers use the debug module's `RTXDebug.Remix.SetConfig` in a local single-player game. A gate test
   fails when a runtime patch declares a text, key or hash option without a verdict, or when the package's Lua sets an
   option the policy refuses.
2. **A Remix mod's option layer stays in its own folder and sets only how the scene looks** (runtime patch 0101): a
   Remix Logic graph in a mod's stage reads a config file only inside that mod's folder (a drive, root, share or scheme
   is refused before USD's resolver sees it), and its layer sets only the sky, weather, fog and volumetrics, exposure,
   tone mapping, bloom, post effects and eight single look options; never text, lists, keys, unbounded integers, debug
   options, the player's own settings or runtime state. A value that does not parse is refused instead of thrown, for
   every layer and through the Remix API. No mod the package ships uses graphs; a gate test keeps it so.
3. **The startup text lives in `rtx-remix/mods/nativeloader_ui`, create-only** (runtime patch 0103, the fixes'
   packager): GMod's Lua writes only under `garrysmod/data`, where any server's client Lua could replace the text the
   runtime draws. The released loader deploys root files only to a few places; add-on folders put a player's edits
   back and the runtime's folder is versioned, so a Remix mods folder without a `mod.usda` is the one place that keeps
   the player's edits and no Lua reaches. A copy edited in the old folder is not migrated: nothing tells a player's
   edit from a server's write there; the player copies it over once.
4. **The splash shows once per process, at most a minute**, and the welcome message is drawn as text (runtime patch
   0102): it can start only in the first two minutes and never comes back once closed.
5. **VR checks the single-player rule natively** (the VR module): Start asks `engine.dll`'s `VEngineClient015` (connected,
   a loopback channel, one player slot, no demo) before it loads anything, and the window, keyboard, binding-editor and
   capture calls ask again at each call. Each slot is called only when its function lies in `engine.dll`'s code. The
   companion's Lua checks stay as the first, translated refusal. An engine that cannot say refuses.
6. **A multiplayer RTX start gets `sv_cheats 0`**, as the New Game screen gives the games it starts; single-player
   keeps the session's `sv_cheats 1`. GMod blocks `sv_cheats` for `RunConsoleCommand` and `game.ConsoleCommand` in a
   game's realms (and an add-on's cfg is not found by `exec`), so the server realm of a game with more than one slot
   leaves a request with the time in `data/nativeloader_companion/cheats_off.txt`, and the companion's menu script
   `multiplayer_cheats.lua` runs `sv_cheats 0` from the menu realm once the game runs; a request older than five
   minutes is dropped. Any Lua can write that request, but a client cannot change a server's replicated value, and
   off is the safe direction.
7. **The Model Hotloader's server rules**: replace one at a time per player and character, under the gamemode's
   spawn rules; sizes on a 0.05 grid and masses in whole kilograms; a player model takes no mass from the client, waits
   ten seconds between carriers on a server (administrators and single-player do not wait) and asks
   `MMDHLCanSetPlayerModel` first; arms previews served for the session only, never saved; saved rigs pruned to the
   newest 16 per model, role and voice, the newest 4 registered at a map's start; the legacy dupe factory takes only
   look and place, under `PlayerSpawnRagdoll`, and spawns asynchronously; a reset at most once a second, its notice to
   the requester only; a Mesh Separator piece placed in place only within 64 units of its model.
8. **No absolute path for another server's scripts**: the poster status gives `screenshots/<name>`; on another server
   the Model Hotloader's installation info gives `<game>\...` paths, its export game-relative paths, its source list
   file names. Its source registries move out of `garrysmod/data` to
   `%LOCALAPPDATA%\ModelHotloader\sources\<hash of the cache path>\` (beside its file-access grants), once, entries kept.
9. **Entities' networked values within their controls' ranges** wherever they are read (lights and lamps, projected
   textures, RT lights, the sky editor, Seamless Portals' sides and size), and a value that is not a finite number never
   reaches the Remix API. The six RT light tools spawn under `sbox_maxsents` with creator, prop-protection owner, cleanup
   and undo; the sky editor is for administrators; the material editor's entity rules need a target the tool may edit.
10. **A development upload is a checked package**: the publisher covers every repository path a part names (an
    uncovered one stops the run), compares the inputs again after the build, and uploads only a package `nlctl.exe`
    validated; the combined manifest is compact and refused over the loader's 1 MiB cap. `packages/` holds no Windows
    account folder (`check_repo.py`).

## Consequences

- An add-on or map script that set other Remix options through `RemixConfig.SetConfigVariable` now gets `false`
  (the content packs and the map remasters in the fork's branches were surveyed and are allowed); the skill
  `remix-map-pbr` says so.
- A player who customised the startup text copies it into `rtx-remix\mods\nativeloader_ui` once.
- Single-player values typed beyond the stock controls (a light size above 1024, a lamp brightness above 8) are capped
  for the Remix light; the RT light editor keeps radii and sizes up to 2000 (it had capped them at 200 and 400).
- VR also refuses during demo playback and in a start where `engine.dll` cannot be read; a GMod update that moves the
  engine's slots stops VR until the module is updated (a gate test reads the installed `engine.dll`).
- The model reload after the hardware-skinning settings is skipped under queued rendering and runs at most twice a
  map; `cl_rtx.lua`'s final call switches queued rendering off first, as before.
- Not changed, recorded in the report: the maintainer's path stays in git history; `PollJob` still gives a picker's
  path to the server that opened the picker; the material editor's Shift+Reload strip has no target check of its own
  (the tool gun's `CanTool` still applies); a distant RT light sets each RTX client's archived
  `rtx_api_map_lights_env_brightness_mult` to 0 while it exists.
