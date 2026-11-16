# The repository review's fixes (2026-11-16)

By Claude, with five subagents in their own worktrees (runtime, the fixes module, the Model Hotloader's natives, the
fixes' Lua and the material editor, the VR module and the engine guard) and the parent's share (the Model Hotloader's
Lua, the session's cheats, the publisher). Integration branch `review-lua-tools` (worktree `out/worktrees/msep`),
merged into `main`. The loader (`winmm.dll`) is unchanged: every fix ships in the RTX package.
Decisions: [ADR 0234](../decisions/0234-what-a-server-a-workshop-item-and-lua-may-reach.md).

## The request

"The Repository bug and security review completed. Please read and verify if needed. The user approved the fixes for
the reported list. Please implement, test the fixes to make sure it does not break the game in other aspects and then
push to GitHub and Workshop." The review (a child session's, `out/review/repository-review.md` in the main checkout,
local) listed 30 findings in descending severity, each with evidence and a smallest fix.

## What was fixed, by finding

| # | Severity | Finding | Fix | Where |
|---|---|---|---|---|
| 1 | High | A subscribed content-only Workshop item set any Remix option through a Remix Logic graph's option layer, from any file, and a bad hash list ended the game | a mod's layer only from a file in its own folder, only scene-look options; an unparsable value refused for every layer and the API | runtime patch 0101 |
| 2 | High | `RemixConfig.SetConfigVariable`'s denylist let any server write captures every frame, load any local DDS, switch replacements off | an allowlist of what the package's Lua sets; paths, `..`, drive-relative values and bad hash lists refused | the fixes' 15th patch `lua-guards` |
| 3 | High | Hotloader "replace" skipped the spawn guard and the gamemode's limits | one at a time per player and character, under `PlayerSpawnRagdoll`/`PlayerSpawnNPC` | `mmdhl/server.lua` |
| 4 | High | Carriers minted per client-chosen number, persisted and replayed | sizes on a 0.05 grid, masses in kg, player-model waits, previews never saved, rigs pruned | `server.lua`, `actors.lua`, `sharing.lua` |
| 5 | High | A pasted Seamless Portals portal with a huge side count hung everyone | sides 3-100, sizes up to 2048, for every reader and after a paste | the portal's `sh_init.lua`, `init.lua`, `cl_init.lua` |
| 6 | Medium | A TGA cached as "PNG" leaked game heap into a `.vtf` | PNG-only, zero-filled decoding of cache textures | Hotloader natives (`cache_png.cpp`) |
| 7 | Medium | ToPBR's "options" listed any folder and told missing from existing | the source must be the character's own PMX drawing the texture; one refusal text | `lua-guards` (`game_source.h`) |
| 8 | Medium | Any client Lua could launch SteamVR and inject input | the VR module asks `engine.dll` for a local single-player game | `vr/native/single_player.cpp`, `session.cpp` |
| 9 | Medium | A crafted Hotloader manifest read out of bounds at every start | lists checked first, identity checks everywhere, `JSON_ASSERT` throws | Hotloader natives (`assets.cpp`) |
| 10 | Medium | The welcome message was a printf format any server could set; the splash came back | drawn as text; at most a minute, once | runtime patch 0102 |
| 11 | Medium | Back-face twin welding quadratic | bounded (16 coincident, 2 a triangle, 4,096 part pairs) | Hotloader natives (`backface_twins.hpp`) |
| 12 | Medium | The legacy dupe factory fed unchecked options into a synchronous fit | look and place only, gamemode's rule, asynchronous | `server.lua` |
| 13 | Medium | Lights took networked values unchecked (inf/NaN to every client) | every value within its controls' range, finite only | the light wrappers, `remix_rt_light` |
| 14 | Medium | The six RT light tools ignored limits, owner and cleanup | `RemixRTLight.Spawn`: `sbox_maxsents`, creator, CPPI owner, cleanup, undo | the six stools, `sv_rtx.lua` |
| 15 | Medium | The publisher missed the VR and load-accelerator sources | covered; an uncovered path stops the run | `tools/publish_workshop.py` |
| 16 | Low | Listen servers started outside the New Game screen kept `sv_cheats 1` | the server asks, the menu realm runs `sv_cheats 0` (GMod blocks it for a game's scripts) | the engine guard autorun, the menu script `multiplayer_cheats.lua` |
| 17 | Low | The splash text came from a folder any server could write | `rtx-remix/mods/nativeloader_ui`, create-only | runtime patch 0103, `tools/package_fixes.py` |
| 18 | Low | Absolute paths readable by any server | poster status relative; Hotloader paths relative or names on another server; registries in `%LOCALAPPDATA%` | engine guard `poster.cpp`; Hotloader natives |
| 19 | Low | A maintainer's local path shipped in every package | removed; `check_repo.py` refuses account folders under `packages/` | `rtx_agent/README.md`, `tools/check_repo.py` |
| 20 | Low | Hotloader reset: unthrottled broadcast with a notice everywhere | once a second; the notice to the requester | `server.lua`, `physics_reset.lua` |
| 21 | Low | Separator in-place placement anywhere within 4096 units | within 64 units of its model | `separator/server.lua` |
| 22 | Low | The sky editor spawnable by anyone, its modifier unclamped | `AdminOnly`, a non-admin's paste removed, values bounded | `remix_sky_editor` |
| 23 | Low | The material editor's entity edits ignored ownership with `advmat_adminonly 0` | `AdvMat.CanEditEntity` (own model, admins for players, `CanTool` for the rest) | `sh_00_config.lua`, `sv_30_store.lua` |
| 24 | Low | Any Lua could flush model data under the render thread | single-threaded only, twice a map | `lua-guards` (`model_reload_policy.h`) |
| 25 | Low | An empty remote Triangles shape crashed Bullet | empty and huge shapes refused; speeds capped | Hotloader natives (`scene_share.cpp`, `secondary.cpp`) |
| 26 | Low | `RegisterSourceShadow` took an unchecked index | 0-16,383 only | Hotloader natives (`renderer.hpp`) |
| 27 | Low | File-access grants keyed on a chunk name, listed with their keys | the list gives an id, the folder's name and dates | Hotloader natives (`file_access.cpp`) |
| 28 | Low | The Zstandard decoder wrote one byte past a stack array | more than 255 Huffman weights refused | Hotloader natives (`zstd_decode.cpp`) |
| 29 | Low | A development publish uploaded the live tree after one check | HEAD, status and fingerprint compared again after the build | `tools/publish_workshop.py` |
| 30 | Low | The hook publish skipped nlctl without a build; the 1 MiB cap a hard ceiling | an unvalidated package is not uploaded; compact manifest, cap enforced, the archive checked | `publish_workshop.py`, `package_workshop.py` |

## Found while testing and fixed here

- **Runtime patch 0104: an empty value through the Remix API is a success again.** Patch 0101 made
  `remixapi_SetConfigVariable` answer `INVALID_ARGUMENTS` whenever `readOption` read nothing; `Config::findOption`
  takes `""` for no value, and the companion sets its session lists and the eye-white aliases to `""` whenever they
  are empty. The first PoC run printed 902 "Failed to set ... ''" lines in four minutes (none in the morning's run with
  the old runtime). An empty value changes nothing, as it always did.
- **`test_lua_guards.py` read the runtime's unit tests' own options** (patch 0101's test declares two): the scan of
  runtime declarations leaves out the patches' test files.
- **`check_repo.py`'s new account-folder rule flagged the Hotloader's test fixtures** (`C:\Users\Someone`): `someone`
  is a placeholder.
- **The skill `remix-map-pbr`** told agents to switch replacements off through `RemixConfig.SetConfigVariable`, now
  refused: it points to the debug module's `RTXDebug.Remix.SetConfig`.
- **Finding 16's first fix did nothing in a game**: the server realm's `RunConsoleCommand("sv_cheats", "0")` is blocked
  by GMod ("Command is blocked!"), and so are `game.ConsoleCommand` and `exec` of an add-on's cfg (tried in the PoC).
  The server now leaves a request in the data folder and the companion's new menu script `multiplayer_cheats.lua`
  runs `sv_cheats 0` from the menu realm, as the New Game screen does; in the PoC's two-slot game the server reported
  "Server cvar 'sv_cheats' changed to 0" a few seconds in.

## Tests

- **The gate** (`tools\test.ps1 -Config Release` with `NL_FIXES_CLONE` set, on the integration branch): CTest 35 of 35,
  2,074 Python tests OK (one skipped, as before) after the five branches were merged; and again before the merge into main, with runtime patch 0104 and the menu-realm cheats fix: CTest 35 of 35, 2,082 Python tests OK (one skipped).
- **New tests, each failing on the code before its fix** (the agents' and the parent's checks against the old code):
  - `test_lua_guards.py` (the option policy, ToPBR's source check, the model reload's rule, every option the package's
    Lua sets allowed), `test_runtime_mod_option_layers.py`, `test_runtime_imgui_formats.py`, `test_runtime_splash.py`;
  - `test_portal_limits.py`, `test_remix_light_limits.py`, `test_editors.py`'s `adv_entity_owner`,
    `test_check_repo.py`'s account folders;
  - `test_hotloader_server.py`'s six scenarios, `test_engine_guard_lua.py`'s `cheats`, `test_multiplayer_cheats.py`,
    `test_publish_workshop.py`'s and `test_package_workshop.py`'s new cases;
  - C++: `nl_vr_tests` (the single-player gate, the engine reader against a stand-in `engine.dll`, the installed
    `engine.dll`'s slots; four mutations of the gate each caught), `nl_engine_guard_tests` (the poster's view); the Model
    Hotloader's own tests (36 of 37, the one failure also on the build before the fixes, below); the runtime's
    `test_mod_layer_policy` (338 checks) and `test_mod_option_layer` (62 checks, the real option manager).
- **In the PoC** (`out/msep/poc_review.py` with `out/msep/poc/review_probe.lua`, `review_mp_probe.lua` and the scratch
  server add-on `nl_review_qa`; evidence in `out/qa-poc/review-fixes`): single-player (`review-sp-02`, gm_construct, RTX on, 1920x1080): the session keeps `sv_cheats 1`; RemixConfig takes
  `rtx.skyBrightness` and refuses `rtx.captureHotKey`, `rtx.enableReplacementMaterials`, `rtx.waterSim.rings.texture`
  (`..\..\x.dds`), `rtx.ignoreTextures` (`zz`) and `rtx.welcomeMessage`, each with its reason in the console; a
  simulated VR start passes the native single-player gate and stops at the missing test root; `poster 1` reports
  `screenshots/poster-<date>.png`; a replace burst on a character makes one replacement ("A model is already being
  placed" for the second), two resets in a second show one notice, a Source dupe and a crafted legacy dupe both arrive;
  Imported game PBR names `mmdhl_pbr_linlong` on 11 of the character's 30 materials (the Remix mods load); the material
  editor allows the player's own NPC; the five RT light tools each make a light with its creator, cleanup and undo; the
  sky editor spawns for the host; a pair of portals given 2,147,483,647 sides reads 100 on the server and the client and
  nothing hangs; `gmod_cleanup` removes the lights, the sky editor, the portals and the characters (all but one the probe's own helper pasted without a cleanup entry); the startup text is in
  `rtx-remix\mods\nativeloader_ui`, `garrysmod\data\nativeloader_ui` is gone and Remix lists no such mod; no Lua error
  and no "Failed to set" line (the first run, `review-sp-01`, before runtime patch 0104, had 902). A two-slot listen
  game (`review-mp-02`): "Server cvar 'sv_cheats' changed to 0" from the menu script a few seconds in, cheats off at the
  start and the end; VR refused natively ("VR works in single-player games only: the game has 2 player slots"); the RT
  light tool at `sbox_maxsents 2` makes two lights and the third gets the stock limit notice. The same two-slot game again (`review-mp-03`): the sky editor spawns for the listen host (an administrator) and the cleanup takes it. The Mesh Separator's editor flow (`out/msep/poc_editor.py`, `review-editor-01`): a left click opens the editor on the ragdoll, a 224-triangle piece detaches and is placed in place (within the new 64-unit rule). A simulated VR session (`tools/vr_session.py --simulate`, `out/vr/q/review-sim-02`): its start passes the native single-player gate, 2,317 frames rendered at the simulated 90 Hz, none submitted, OpenVR never loaded, no Lua error, a normal quit.

## Not done, and follow-ups

- **A distant RT light set each RTX client's archived `rtx_api_map_lights_env_brightness_mult` to 0 while it existed**
  (put back when it went and at shutdown; a crash in between left 0 for later sessions). Found by the fixes' Lua
  agent, not in the review's list; fixed afterwards at the user's go-ahead (the last section).
- **`PollJob` still gives a picker's file path to the server that opened the picker** while the player is connected
  to it (its import needs the path); closing it needs opaque file references through the import flow.
- **The Model Hotloader's `animated_carriers_and_sharing` test fails at a deletion check with a cache path over 260
  characters**, on the build before the fixes too: a player with a very long cache path would see a deletion leave
  files behind.
- **The Sky Editor's sun disc and altitude never reach this runtime** (seen once the PoC spawned one): its
  `RemixAtmosphere` calls for `rtx.atmosphere.sunDisc` and `rtx.atmosphere.altitude` fail with code 1, as the runtime
  declares no such options. Unchanged by the review.
- **The material editor's Shift+Reload strip** calls `Store.Clear` without the player (it only removes overrides; the
  tool gun's `CanTool` still applies to the aimed entity).
- **`RTX_CleanupMapTextures`** can be called by any Lua and has no thread-mode guard (not verified whether it matters).
- **The maintainer's path stays in git history** (the repository is public): rewriting history is the user's call.
- **Not run in a game**: a VR start with SteamVR and a headset (the simulated session and the unit tests cover the
  gate), a second client on the listen server (the refusals for a non-admin are covered by the harnesses), a Hammer
  map with Seamless Portals, prop protection (CPPI) owning the RT lights.
- **`inputs.py import --file` with a relative source** records a modified file as not dirty (absolute sources were
  used here).

## Published

Merged into `main` as `8b46432e` and pushed (`51ab2ecf..8b46432e`, ten LFS objects). The merge's hook built the package
here and uploaded item 3829070317 as **`0.0.0-dev.20261116141607+791d3f2f`** (content digest `6746d885...`), its change
note the changelog's new section; the push's hook found the inputs unchanged.

## Follow-up: a distant RT light mutes the sun for the session only (2026-11-16)

The user's go-ahead after the publish ("Yes, fix it here"), on the branch `distant-light-env-mute`, package only (the
fixes' Lua).

- **Before:** `entities/remix_rt_light/cl_init.lua` muted the map's environment (sun) lights while a distant RT light
  existed by running `rtx_api_map_lights_env_brightness_mult 0` on every RTX client and putting the old value back
  when the last one went or at `ShutDown`. That ConVar is the map lights' saved Brightness for directional lights
  (archived): a crash in between left 0 for every later game, a player's change of the slider meanwhile was undone,
  and any server could spawn a distant light (now under `sbox_maxsents`, finding 14).
- **Now:** `cl_remix_api_map_lights.lua` keeps session-only mutes (`envMuters`, `Light2RTX.SetEnvMuted(key, muted)`,
  `Light2RTX.EnvMuted()`); its sun lights take their brightness from `envBrightnessMult()` (0 while a mute is held,
  else the saved setting), at creation, on each update and in `rtx_api_map_lights_info`, and are updated when the
  first mute comes or the last goes. The RT light asks for the mute (`remix_rt_light`) while at least one distant light
  exists and writes no setting; its `ShutDown` hook is gone. Without the map lights' API it changes nothing.
- **A player whose sun stayed dark after such a crash** sets Brightness under Directional back to 1 (or presses its
  Reset): the old 0 cannot be told from a choice, so it is not repaired automatically. The changelog says so.
- **Tests:** `test_remix_light_limits.py`: the harness's new `distant_sun` scenario (one mute, not one a frame; two
  distant lights keep it until both are gone; the saved setting, 1.7, never written, also without `Light2RTX`; no
  `ShutDown` hook), which fails on the file before the fix, and a source check of the map lights (only
  `envBrightnessMult` reads the setting; `SetEnvMuted` updates the sun lights and runs no command), which fails on the
  file before the fix too. In the PoC (`out/msep/poc_review.py` with `out/msep/poc/distant_probe.lua`, evidence
  `out/qa-poc/review-fixes/distant-01`): the saved setting read `1.000000` before, with a distant RT light out and after
  the cleanup; `Light2RTX.EnvMuted()` was false, true, false.
