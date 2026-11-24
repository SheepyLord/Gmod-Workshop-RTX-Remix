# The runtime and upstream dxvk-remix main of 2026-11-23; GitHub issue 14: report (2026-11-24)

The user's request of 2026-11-24: "Investigate and Address https://github.com/SheepyLord/Gmod-Workshop-RTX-Remix/issues/14
if this is a problem. The most recent dxvk carries a few useful fixes. Please up our package's remix version and test
carefully." Done by Claude on the branch `upstream-1123` ([ADR 0265](../decisions/0265-the-runtime-merges-upstream-main-of-2026-11-23.md),
runtime patch 0106, [runtime/README.md](../../runtime/README.md)).

## GitHub issue 14: not reproduced

The report: after the ToPBR update, custom RTX weapon mods (the reporter's own update of a moddb mod for MW weapons)
no longer apply. Its screenshots: Alt+X's texture info on the weapon's texture says **"Legacy material"** for hash
`C9D1E2847FA161BE` (2048x2048, BC3), and the mod's `mod.usda` has `over "mat_C9D1E2847FA161BE"` with an
`over "Shader"` that sets only `metallic_texture`, `normalmap_texture` and `reflectionroughness_texture`
(`./assets/ingested/*.a.rtex.dds`), no `info:mdl:sourceAsset`, no albedo. Package `0.0.0-dev.20261118205912+c15280c0`,
loader 0.16.0, performance tier Low (an 8 GB laptop GPU).

- **What the label means.** The texture info prints "Legacy material" when `getReplacementMaterial(hash)` finds no
  material in any loaded mod (RESEARCH.md, "Authored Remix mods and the Legacy material label"). Had ToPBR's
  `~gmod_topbr` taken the hash, it would say "Replaced material"; and runtime patch 0020 ranks `~gmod_topbr` after every
  authored mod. So the reporter's mod was not loaded, or its material not read; ToPBR did not override it.
- **The format loads.** The fork reads an untyped `over "Shader"` and takes the hash from the `mat_` name, so the
  issue's format registers its materials (code read, then measured).
- **Measured in the PoC** with the published package `0.0.0-dev.20261124082855+6b799cdf` (runtime patches 0001-0105, the
  runtime the reporter had): a mod in the issue's exact format for the crowbar's view model textures and an oil drum,
  and a control mod in rpai's format with a red albedo for a crate (evidence `out/issue14/run2`, `run3` of the main
  checkout). The Remix log: `[RTX Mod Load] mod=issue14_toolkit ... materials=3 ... textures=9` and
  `mod=issue14_control ... materials=1 ... textures=2`, no `USD mod worker failed`. The drum turns dark mirror metal
  with the mod, and stays so with ToPBR on at scope 2 for 90 s; ToPBR's `materials.usda` names none of the authored
  hashes.
- **The reply**, posted on the issue on 2026-11-24 at the user's word (the main checkout's
  `out/issue14/reply-posted.md`), explains the label and asks for the mod's folder layout, whether Alt+X lists the mod,
  and the Remix log's `[RTX Mod Load] mod=<folder>` and `USD mod worker failed` lines. Checked against the runtime's code
  before posting: a mod is a `mod.*` file directly in a folder of `rtx-remix\mods`, the first one found in that folder
  (`ModManager::enumerateModsInDir`, `modExists` in `rtx_mod_manager.cpp`); Alt+X > Enhancements > Loaded USD Files
  names every mod `mod.usda`, with the full path when its first line is hovered; the log line carries a timestamp and
  `info:` before `[RTX Mod Load]`, and the folder name with spaces as `_` (`UsdMod::Impl::logLoadStats`).
- The probe became [`authored_mod_session.py`](../../tools/qa/authored_mod_session.py.md).

## The merge

NVIDIA's `dxvk-remix` `main` moved from `2b46bed0c` (2026-11-14, patch 0093) to `58ac72412` (2026-11-23): 25 commits,
194 files. In the fork clone, branch `claude/upstream-main-1123` from 0105's `0165da89b`: a temporary
`git replace --graft 20e3553eb dd580bc21 2b46bed0c` (0093's squashed commit given upstream's commit as a second parent),
`git merge upstream/main` (merge base `2b46bed0c`), 49 conflicted files resolved with diff3, the merge squashed onto
`0165da89b` and the graft deleted. What each side kept is in [ADR 0265](../decisions/0265-the-runtime-merges-upstream-main-of-2026-11-23.md)
and the patch's message; the parts that needed a decision:

- **Remix API**: 0.1000.3, upstream's four GPU-resident scene functions at slots 43-46, the spawn mask struct type 34;
  `clientInterfaceSize` gains the 0.1000.2 branch (344 bytes); the fork's API test checks 328, 344 and 376 bytes.
- **Device loss**: upstream now ends the process on any failed submission or fence wait (a dropped command list never
  signals); the fork's `handleDeviceLost(reason)` keeps calling `onGpuCrash` once, then upstream's memory report.
- **Option reads**: both sides had made reads lock-free; upstream's published copy (`LockFreeSingleWriterValue`) is
  read inside the fork's `kLockFreeRead` branch, so a trivially copyable value cannot be read half written. Every
  write of a resolved value goes through `resolveValue`, which publishes it.
- **The view-model material bit** collided with the MMD alpha cutoff (texture flag bits 19-30): bit 31.
- **RTX IO**: upstream's failure handling with the fork's upload generations.
- **Texture categories, tonemapping, light conversion, `RtInstance`, particle layouts, the memory tests**: see the ADR.
- **Found by the build** and fixed in the same commit: upstream's spawn mask rejection written for its own spawn
  function (`newParticle`), now the fork's `SpawnSample` rejection; `manageTextureVram()` called without the fork's
  context argument; `RtInstance` is 832 bytes; upstream's spawn mask test expected type 33; `RtxOptions.md` regenerated
  from the build (upstream's new options).
- Reviewed by hand where both sides changed the same logic without a conflict: the thread pool (upstream's lock-free
  empty-queue hint composes with the fork's sleep protocol, which counts tasks under its lock), DLSS frame generation
  (upstream's queue failure handling beside the fork's HUD-less colour and menu patches).
- **Found in the PoC** and fixed in the same commit: the first build (`d3d9.dll` `804b7da0`) crashed every PoC session at
  its first draws (the issue 14 session, release QA's first session, the character test: three minidumps, the same
  stack). The exception was `std::system_error` with EDEADLK (36), thrown from `D3D9DeviceEx::DrawIndexedPrimitive`
  (symbolized with the build's PDB: `out/up1123/crash1/analyze_dump.py` of the main checkout). Upstream now takes
  the option update mutex around the fixed-function stage loop in `d3d9_device.cpp`; inside it, the fork's
  `GetTextureCategories()` refreshed its category copies, which takes the same mutex when any option has changed, and
  `std::mutex` is not recursive. The copies now refresh before the lock is taken, and the loop reads only them. The merge
  added one other lock site, the stage loop in `d3d9_rtx.cpp`: it reads only the copies, and no helper it calls locks.
  No other lock site changed in the merge (every added or removed line naming the mutex listed from the commit).

## Tests

Details and evidence folders: [TESTING.md](../TESTING.md), "The runtime merges upstream dxvk-remix main of 2026-11-23".

- **The gate** (`tools\test.ps1 -Config Release`) passes: the conventions, 2,234 Python tests, 35 C++ tests. **The
  runtime's unit suite**: 78 of 80 under meson, the API test beside the DLL; `test_remix_categories` as before.
- **PoC with the fixed build** (`d3d9.dll` `74115025`): the issue 14 session PASS (the authored format loads and wins
  over ToPBR under the new runtime too), the character re-import PASS (6 materials `automatic`, as for ADR 0263), release
  QA's `session` and `spawnmenu` PASS. Its two glass sessions fail as the published package's do (today and on
  2026-11-14; open, see Open). The Remix logs show no new error.
- **Release QA's settings check** reported the spawn menu's Time of day slider writing `18.64` back as `18.639999`: the
  published package does the same. The check now compares numbers at the convar's single precision as well.
- **Performance** (A the published package, B this one, ABBA at 4K): the same frame times (12.0-12.4 ms means both),
  with about 15 % less CPU in the game process (A 227 % and 223 % of one core, B 183 % and 197 %). At 1280x720, one pair
  of sessions (A first): 152 against 178 frames a second, p99 23.4 against 9.8 ms.

## Published

Merged to `main` as `f0b2a3ec` (a fast-forward) and pushed; Workshop item 3829070317 updated as
`0.0.0-dev.20261124104734+42e4e1f8` (2026-11-24 10:47 UTC), its change note the CHANGELOG entries; the push's own
publish found the inputs unchanged.

**Field check** (`release_qa.py --field`, one session at a time, each under its own hold of the PoC lock; evidence
`out/qa-field/up1123`): Steam had not fetched the update, so the first start (release QA's `session`) deployed the
previous package and downloaded the new one. With the new package (`status.json`: runtime
`0.0.0-dev.20261124104734+42e4e1f8`, `d3d9.dll` `74115025` deployed): `session` and `spawnmenu` PASS; `map-glass` and
`spawned-glass` fail as on the PoC, no crash dump. The Remix logs hold the same error kinds, at the same rate, as the
previous package's start in the field. Release QA flagged `DXLevel_V1` 95 -> 90 in GMod's shared registry key with the
previous package too: the level an RTX start sets, after other sessions' tests in between had left 95.

## Open

- **Release QA's glass sessions** fail on the PoC and in the field with this package and the published one, in every
  retained run since 2026-11-14. In the field's `map-glass` session the glass module `gmcl_nlglass_win64.dll` loaded
  and the pane still left no `procedural_shard` entities, so the reading of 2026-11-14 (the module not loading) does not
  explain it. The probes count the Glass-Rewrite-Remix add-on's `procedural_shard` entities and spawn its
  `procedural_shard_4`: they may predate the G1 glass system, or glass may not break as it should. Not this change.
- GitHub issue 14 waits for the reporter's answer (the mod's folder, its Loaded USD Files entry, the Remix log's lines);
  the reply was posted on 2026-11-24.
