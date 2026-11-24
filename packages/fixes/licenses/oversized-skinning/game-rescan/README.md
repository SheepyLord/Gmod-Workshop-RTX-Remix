# A character imported again has its game maps looked for again

GPL-2.0 changes to `gmcl_RTXFixesBinary_win64.dll`; the parent [COPYING](../COPYING) applies.
[game-rescan.patch](game-rescan.patch) is the seventeenth native patch, after [cleanup-drain](../cleanup-drain/README.md);
[pins.json](../../../../../tools/ci/pins.json) (`fixes.patches`) builds the module with it last and records the patched
native tree the seventeen give (`fixes.patched_tree.source` `41dc27fc...`; `public` and `premake5.lua` unchanged). The
complete changed files are [to_pbr.cpp](source/material_pipeline/to_pbr/to_pbr.cpp) and
[to_pbr.h](source/material_pipeline/to_pbr/to_pbr.h); the new ones
[game_rescan.h](source/material_pipeline/to_pbr/game_rescan.h) and the regression
[game_rescan_test.cpp](tests/game_rescan_test.cpp), as the work tree has them (CRLF). The build applies only the patch's
`source/` part. Made in a scratch `git clone --shared` of the user's fork clone, under the worktree's `out`, with the
sixteen earlier patches applied (their `source/` tree gave `c5f7ad05...`, the recorded one); nothing was committed to
the fork or pushed. The native loader's decision is ADR 0263; the driver's half is in
`cl_rtx_topbr_conversion.lua` (the hook `RTXToPBR_GameRescan`).

## Why

The user's report of 2026-11-24: a PMX imported with the Model Hotloader before its game rip's maps (`<stem>_N`,
`_MRA`, `_P`, `_E` ...) were copied beside it got no imported game PBR, and importing it again in the same game session
did not help; only a restart did. Three session caches kept the first answer:

- A character's asset id is a hash of its manifest, which names the PMX's own textures, not the maps beside it, so the
  import of an unchanged PMX keeps its id, and its material names (`mmd/<the id's first 16 hex digits>/...`).
- The driver (`cl_rtx_topbr_conversion.lua`, its `RTXToPBR_GameMaps` pass) submits each material name once a session,
  and `TextureProcessor::QueueGameMaterial` refuses a name already in `m_gameSubmitted`.
- The worker kept, for its life, each model folder's scan (`GamePBR::DiscoveryCache`: a `Discovery` lists the folder's
  images when it is made, never again) and each texture identity's resolution (`GameRegistry::Session::ResolveOnce`,
  a "no maps" result too).

`ToPBR.ClearCache()` forgets all of it, but also every world conversion and the published layer. The registry's
`Resolve` already converts again from a readable source, so once the session lets go, a fresh resolution finds maps
added or changed since.

## The change

[game_rescan.h](source/material_pipeline/to_pbr/game_rescan.h) (standard C++ only) decides what a rescan takes, forgets
and concerns: `Prefix` (`mmd/`, 16 hex digits, `/`), `Named`, `Source` (at most 2048 bytes, no control character,
`.pmx` in any case), `SameFile` (a lexical comparison: `/` and `\` alike, `.` and `..` resolved, no case; nothing is
opened), `Identities` (the texture identities of the live jobs whose name has the prefix or whose model is the same
file), `Forget` (the prefix's submitted names), `Wait` (the prefix's views say `waiting` again, errors cleared, families
kept), `FileName` and `Limit` (one call a second; a refused call does not move the second).

[to_pbr.cpp](source/material_pipeline/to_pbr/to_pbr.cpp):

- `TextureProcessor::RescanGameSource(source, prefix)`, on the game thread, behind the Lua function
  `ToPBR.RescanGameSource(source, prefix) -> bool` (registered beside `ClearCache`; both strings taken whole). Any
  server's client Lua reaches every ToPBR function (R19, the native loader's ADR 0112), so it refuses (`false`) unless
  the converter is initialized and the player's game maps are on (`m_gameEnabled`), the prefix is one character's, the
  source is a `.pmx` on a local drive (`LuaPathPolicy::LocalDrivePath`), the game-map queue has room (128) and a second
  has passed since the last call it took. It opens no file. Under `m_queueMutex` it forgets the prefix's names in
  `m_gameSubmitted`, sets their views to `waiting` (so the companion's progress notice counts them while they resolve
  again) and queues a `GameJob` with the internal action `rescan`. `GameMaterialAction` cannot queue that action: its
  list stays `""`, `options`, `automatic`, `none`, `maps`.
- The worker takes a `rescan` job before any live-job or identity work: it drops the folder scans
  (`discovery = GamePBR::DiscoveryCache()`, at most eight folders), erases the session's resolution and the identity
  view of every identity `Identities` names, notes them as let go, and prints one line:

```text
[MaterialPipeline::ToPBR] Game maps looked at again: <PMX file name> (<n> textures)
```

- The first resolution of a let-go identity since then (when the driver submits the materials again) replaces the maps
  registered for its live materials, or, finding none or failing, takes them back (`importedGame` entries only) and
  asks for a publication. A manual choice saved in the overrides store still comes first (`overrides.Select`). The
  registered maps are not taken back at the rescan itself: a material keeps its maps until its new ones are ready, and
  another character drawing the same texture is never left without maps nobody submits again.

[to_pbr.h](source/material_pipeline/to_pbr/to_pbr.h) declares `RescanGameSource`, says what a `GameJob`'s action may
be and holds the `GameRescan::Limit`.

## Tests

[game_rescan_test.cpp](tests/game_rescan_test.cpp) compiles alone with MSVC
(`cl /EHsc /std:c++17 /W4 /WX /UNDEBUG /utf-8`): prefixes (case of the hex digits, length, a NUL, a texture identity's
folder), names, sources (any case, a NUL, a control character, 2048 and 2049 bytes), one file's names (separators,
case, dot segments, a folder outside ASCII, another drive, a name that is not UTF-8), the identities a rescan lets go
(by prefix, by the same model under another asset id, none without an identity), forgotten submissions, waiting
views, the console line's name, and one rescan a second.

The loader's Release gate ([test_game_rescan.py](../../../../../tools/tests/test_game_rescan.py.md)) compiles and runs
it on the header as the patches leave it, checks the folder's files against the patch and the patch's place in
`pins.json`, the binding and its refusals, the worker's branch and the driver's hook; the driver's behaviour runs in
[topbr_harness.lua](../../../../../tools/tests/topbr_harness.lua.md).

Validated build: 5,682,176 bytes, SHA-256 `fc850271b02dd0d739c6ee293bb1baf6e3972d5aec55dc65c7ced51ddacc75d9`
(`build_modules.ps1 -Only fixes` with the user's fork clone, under a `subst` alias of the worktree's `out`,
garrysmod_common `a854f23`, premake 5.0.0-beta2; the patched tree matched). Not run in a game when this was written.
