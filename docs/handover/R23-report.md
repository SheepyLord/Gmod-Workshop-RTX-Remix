# R23: the user's report of 2026-11-08 (report)

The user's seven items, with standing instructions of the same day: no Codex (Claude, with Claude
subagents); no loader (`winmm.dll`) change without the user's approval; no questions for this task;
edits tested and reviewed; one GitHub action at the end; the Workshop item updated from the local build
first. Done on branch `r23` in `out/worktrees/r23`, by Claude with Claude subagents for the skills and an
independent code review. First, about 149 GiB of old worktrees, build trees and QA copies under `out\` were
removed (receipts in `out/receipts/`), leaving 379 GB free on H:.

| Item | Priority | Result |
|---|---|---|
| 6: weapon bases (ARC9, TFA) stop the start | High | Fixed for ARC9: an engine guard ([ADR 0130](../decisions/0130-an-engine-guard-for-lua-start-up.md)) cuts the material fallback loop; PoC A/B below. TFA: see below |
| 7: what stops a start at "Starting Lua" | High | Found (material fallback cycles under RTX), fixed (the guard), and for any other cause a start-up watchdog that names the stuck file and, at the next start, the add-on |
| 1: Wuthering Waves PBR barely shows | Low | Their `_N` map carries the game's roughness and metalness, now used; a family without its own masks pairs by name (the fixes' seventh native patch) |
| 2: the multiplayer notice | Low | New text and a highlighted "Don't show this again" button, on the local branch `r23-loader-mp-notice` for the user's approval (a loader change) |
| 3: a progress bar while imported PBR converts | Low | A top-right notice with a bar, then "ready" |
| 4: the material editor's tabs | Low | The edited material carries over between Material and Source / VMT |
| 5: the skills | Low | Brought up to date; recorded model names are the character's name only, enforced by the scripts |

## Items 6 and 7: "Starting Lua"

**What stopped the game.** Another session sampled the field game stuck at "Starting Lua" after the ARC9
subscriptions (`out/lua-hang/FINDINGS.md` in its worktree): the main thread at 100 % CPU, about 150,000
`NtCreateFile` a second, the stack holding ARC9's autorun, `sh_csgo_effects.lua` and
`materials/particle/warp5_explosion.vmt`. [ARC9] Gunsmith Reloaded (2910537020) calls
`game.AddParticles("particles/csgo_explosions_fx.pcf")`; its `particle/warp5_explosion` is `Refract` with
`"<dx90" { "$fallbackmaterial" "particle/warp5_explosion" }`. RTX sessions run Source's fixed-function paths,
so the `<dx90` block applies, and `CMaterial::InitializeShader` reloads the material forever (no pass
counter; details and addresses in [RESEARCH.md](../RESEARCH.md), R23). RTXLauncher's
`MaterialSystemFallbackPatch` capped this loop but never matched this build.

**The engine guard** ([`engine_guard/`](../../engine_guard/README.md), ADR 0130): a package module, not the
loader. It detours the one call in that loop that reads `$fallbackmaterial` (a unique 36-byte pattern, the
key string checked) through a 15-byte stub within a call's reach and answers "none" for a fallback that is the
material itself or that would close a cycle (the seventeenth hop for one material); the engine then goes on
with the shader's own fallback chain. Installed once per process (the client and server copies share it), the module
pinned, the call's displacement rewritten with one aligned store. The companion's
`!!!!nativeloader_engine_guard.lua` loads it before the add-ons' autoruns (any whose name does not itself start with
four `!`) in both realms of a local RTX start, and
the early view (`_nativeloader_guard.lua` in `includes/init.lua`) in the client realm, which also covers remote
servers.

**The start-up watchdog** (same module): from the module's load until the realm's `Initialize` (or first
tick; at the latest 150 s after the gamemode loaded) it samples the main thread every 3 s, suspended only to
copy its committed stack into a buffer allocated beforehand. When the nearest Lua chunk name has not changed for 90 s it writes
`garrysmod/data/native-loader/startup-stall.json` and shows one message per process, in the player's language
from the companion's own catalog (only the companion's first call sets it; a remote start keeps English). A start that goes
on after all removes the report; otherwise the next start shows a 30-second notice that names the file and the
add-on (a mounted Workshop add-on's title, or a legacy folder).

**PoC evidence** (`out/r23/poc_qa.py`; the PoC's loader, package and data moved aside and back, snapshot and
clean rollback every time):

| Run | Package | Result |
|---|---|---|
| `arc9-baseline` | the published package (no guard), ARC9 base + Gunsmith Reloaded as folders | stopped at Lua after `ARC9 Registered 505 attachments.`; window hung 300 s, ended |
| `arc9-guard` | this build, the same add-ons | gm_construct loaded, normal quit, 95 s; 6 fallbacks cut (logged); `ARC9` loaded |
| `stall` | this build, an add-on whose server autorun loops | the message at 98.5 s naming `@addons/nl_stall_test/lua/autorun/nl_stall_test.lua`; report: realm server, 90 s |
| `notice` | this build, next start | "The last start of Garry's Mod did not get past starting Lua. It stopped in addons/nl_stall_test/lua/autorun/nl_stall_test.lua, in the add-on nl_stall_test." |
| `tfa-guard` | this build, TFA Base (2840031720) as a folder | gm_construct loaded, normal quit, 91 s (the first start's unpack included); nothing cut |
| `tfa-baseline` | the published package, the same | normal quit, 52 s |

**TFA.** TFA Base was not installed; the game's own Workshop download (`steamworks.DownloadUGC` in a PoC
session) fetched it once (43,406,497 bytes, left in Steam's Workshop folder as the game leaves server
downloads; not subscribed, so neither the game nor the loader mounts it). Its 61 VMTs have no
`$fallbackmaterial`, and it starts under RTX with and without the guard. The user's TFA report therefore
involves something else (weapon packs, another add-on): a fallback cycle in any pack is cut the same way, and
any other stall is named by the watchdog, at once and at the next start.

GMod does not mount a loose `.gma` in `garrysmod/addons` (the first ARC9 run showed `ARC9` nil): the add-ons
were extracted with `tools/gmapack`. A read-only scan of the 738 installed Workshop items (23,820 VMTs) found
33 materials with a `$fallbackmaterial`, exactly one fallback to itself (Gunsmith Reloaded's) and no cycle.

**Review.** An independent reviewer (a Claude subagent, read only) confirmed the detour's ABI (`mov r9, r14`, the
jump keeps alignment, the hook's home slot inside the caller's shadow space), the address arithmetic, the one
aligned interlocked store and the two-copy handoff, and found:

| Finding | Fixed |
|---|---|
| Medium: a sample could copy the main thread's stack guard page (between a prologue's `sub rsp` and its first touch), taking the guard from its stack growth | The copy starts at `max(Rsp, StackLimit)`: committed memory only; SEH stays as a backstop |
| An add-on's failing `Initialize` hook skips ours, and the watch could run into a long map load | `OnGamemodeLoaded`/`PostGamemodeLoaded` bound it (`StartupDone(150)`: ends at the latest 150 s later, longer than the 90 s rule, so an `Initialize` stall is still reported); the first tick still ends it |
| One material re-initialized often could lose a valid fallback (the window slid) | An empty fallback read ends the material's chain; the cycle limit is 16 hops (a slow disk's loop still counts) |
| `SetMessage` was a global any server's Lua could call, and its words came from DATA, which any server's Lua can write | Words from the companion's own catalog (`nativeloader/engine_guard_words.lua`); only the first call counts and the function leaves the table |
| Other game builds: an unaligned displacement written with a plain copy; r14 not proven to be the material; the scan without SEH | An unaligned displacement is refused; the loop's `GetName` call on r14 is required near the call site (rva 0xfbb7/0xfc0c here); the scan runs under SEH |
| `!nativeloader...` sorts after `!!` names | Renamed `!!!!nativeloader_engine_guard.lua`, the claim corrected |
| A vacuous test; the JSON test's name; `install()` untested | `filter` checks the key (tested); the test renamed; an end-to-end test runs the real `install()` on a stand-in `materialsystem.dll` (MASM bytes) |
| The report flag set after the report | Set first |

The reviewed build was imported (`gmcl_` `66ede812...`, `gmsv_` `0913d30d...`) and the PoC plan run again on it
(below).

## Item 1: Wuthering Waves characters

Measured with the fixes' production matcher and converter on Shorekeeper and Chisa (`H:\...\PBR\鸣潮-守岸人`,
`鸣潮-千咲`): only Chisa's `Up` and `Down` paired, and only as normal maps.

- Every exported material instance names the `_N` texture `Normal_Roughness_Metallic`: alpha is roughness,
  blue metalness (with a dielectric baseline and leather at 0.4-0.55). R11 had taken it for a plain normal map,
  so roughness and metalness came from material-name classes. Now a WuWa family uses alpha as roughness and
  blue from 0.55 (all metal by 0.8) as metalness.
- Chisa's coat (`Alpha`: `_D` and `_N`, no `_ID`/`_HM`) and Shorekeeper's `Ahpla_N` (the game's spelling)
  were not recognised as families. A WuWa family is now known by its character (another family with the same
  `t_<...>md<5 digits>` prefix has an `_ID` or `_HM` map); such a family pairs by its exact name or by hand,
  never by UV evidence alone, because with UV matching it took a belly decal of Chisa's (0.386).
- Result: Chisa's `Alpha`, `Down` and `Up` pair by name, Shorekeeper's renamed `服.png` by UV as before;
  roughness means 0.53-0.84, metal only on buckles, rings and plates. Shorekeeper's other renamed textures still
  abstain (below R12's thresholds); the Imported game PBR panel assigns them by hand. WuWa hair has only a
  256 x 256 tiling `_HN` detail normal and keeps its class rules.
- [`wuwa-maps.patch`](../../packages/fixes/licenses/oversized-skinning/wuwa-maps/README.md), the fixes' seventh
  native patch (`tools/ci/pins.json` `fixes.patches`, patched tree `c7e8e29d...`); `gmcl_RTXFixesBinary_win64.dll`
  rebuilt with `tools/ci/build_modules.ps1 -Only fixes` (5,518,336 bytes, SHA-256 `45fc78ef...`) and imported.
  The recipe tag changed, so cached game maps convert again once.

## Item 3: progress while imported PBR converts

The fixes' ToPBR driver counts the submitted imported game materials whose native view still says `waiting`
(`RTXGamePBRProgress()`); the companion's `nativeloader_pbr_progress.lua` polls it four times a second and,
once a batch has lasted 1.5 s, shows "Preparing PBR materials for imported characters: 3 of 8." with a bar in the
top-right notice, then "PBR materials for imported characters are ready." for four seconds. A notice the player
closes stays closed for its batch. The notice is now one shared module (`nativeloader/notice.lua`), used by
R22's frame generation hint too.

## Item 4: the material editor's tabs

Derma's `DPropertySheet:SetActiveTab` calls `OnActiveTabChanged` before it records the new tab, and the
editor's workspace switch asked the sheet which tab was active: Material to Source / VMT kept the Source sheet's
earlier material, and Source / VMT back to Material reselected the old one. The switch now uses the tab it is
told about (`SwitchingTo`), and the action bar follows at once. `tools/tests/test_ame_tabs.py` loads the real
panel and fails on the file shipped before.

## Item 2: the multiplayer notice (loader branch, awaiting approval)

The notice is part of the loader's main-menu interface (`loader/proxy/ui`), so it is on the local branch
`r23-loader-mp-notice` (commit `b5fa00e`, from `main` 6ae29f4), not merged, not pushed, loader version
unchanged. The first paragraph has the user's text, lightly edited for English, in all seven languages:
"Some servers do not allow custom renderers and shaders such as RTX Remix and ReShade. A server likely won't
be able to detect that you use them, but posting photos of using RTX Remix on those servers might cause
concerns. Check a server's rules before you join." "Don't show this again" is a bold, green button of its own
that continues and remembers (it was a small checkbox under the text). The menu harness, the presentation
tests and the loader's 27 CTests pass on the branch. Releasing it means: merge, bump the loader to 0.16.1,
refresh the repository modules' records (ADR 0126), tag `v0.16.1`.

## Item 5: the skills

A Claude subagent updated `skills/` (only there) from R11-R23's reports and decisions, as agent instructions:

- **Facts brought up to date:** content packs deploy only from subscribed items (ADR 0111); imported game
  characters get their own maps through ToPBR first (R11/R12, the panel for manual choices, R23's WuWa maps and
  progress notice), authored replacements always win (runtime patch 0020); preloads at a material's first draw;
  memory profiles and characters loaded on first use; automatic and manual eye whites; painted shadows and solid
  hair; `python -I` works with `package_content.py`; the package workflow is started only by a person; tools that
  no longer exist removed.
- **Names:** a recorded model name (the Model Hotloader display name, package and folder names, Workshop titles the
  skills propose, names in records) is the character's own name. `model_names.py` (one canonical copy, mirrored in
  the PBR skill, `test_names.py` 20 tests) refuses game or franchise tags (鸣潮-, 星穹铁道-, HSR, WuWa, ...), versions
  (`2.0`, `v1.2`, `合体7`), author, rating and format tags, brackets and the `<game>-<name>` folder form, before any
  file is written, in `mmdhl_pack.py`, `pbr_mod.py`, `check_pack.py` (an error; `--keep-name` for a non-ASCII name),
  `hotloader_export.py`, `stage_pbr_mod.py` and `package_characters.py`. Existing work-folder keys such as
  `robin_r18_f9c3e4b4` stay identifiers, never names.
- **Drift:** the user's installed copy (`%USERPROFILE%\.claude\skills\mmd-remix-pbr`) had gained presets and tools
  since 2026-11-03 (rough and metal maps, full-size textures, `reveal_hashes.py`, `ue_toon_maps.py`, 12 presets)
  and lacked C-16's adaptive eye emission. Both sides are merged into the repository copy (three-way, no
  conflicts; account paths written as `%USERPROFILE%`). The installed copy was not touched: replacing it with a
  junction to the repository copy (`skills/README.md`) is the user's call.
- `check_pack.py` now reports the three published character packs' descriptions, which name "Honkai: Star Rail":
  their next update drops it.

