# The Enhanced sky: the plan for round 1

The user's request of 2026-11-25: keep today's sky as the default, and add an improved sky, cloud and sun-ray system
that players can switch to. This file is the plan for the first round and the brief for its two coding tasks.

`<repo>` below is the main checkout. Research notes are in its scratch folder `<repo>/out/sky2` (not tracked):
`research.md` (today's sky and the techniques), `numos-library.md` (the library and its integration) and `scratch/`
(the library's clone, the integration commit's files and patches, an apply test and its scripts).

## What the user decided

- Today's sky stays the default. The new sky is a choice the player switches to.
- SourcePT's own source, its local checkout and the OpenRemix runtime are off limits: never open, use or cite them.
- The sky library `Kim2091/numos-sky` (Apache-2.0) "may be used": merged or taken as a dependency, with its licence
  notices.
- The first version has four parts: dense, well-lit clouds; sun rays in the sky; lit mist on the map; extras (rain
  shafts, a rainbow, crossing cirrus, the cirrus' shadow).
- The Enhanced sky gets quality levels, tuned on an RTX 5090 and scaled down.
- Each weather gets its own Enhanced look. Darker overcast and a hazier horizon are accepted.
- VR stays on the Standard sky.
- One round on branches, shown to the user. Nothing is merged, pushed or published before the user decides.
- Codex agents write the code. Claude writes the briefs, reviews, and does every test in the game.
- Judged on four scenes: fair-weather noon; a low sun with rays; sunset and twilight; storms and night.

## What this round does (Claude's choices, for the user to confirm)

- **Route:** the library becomes the Enhanced sky, a second sky beside today's. Today's sky's sources stay as they
  are.
- **Pin:** the library at `41842c6` (its `main` of 2026-11-23), unmodified.
- **Night:** in Enhanced the library's own Moon and stars show. Our night sky editor, sun dogs and the sky without a
  horizon stay with Standard for now.
- **Mist:** in Enhanced the library's haze replaces Remix volumetrics.
- **Menu:** the library's own Remix menu pages are left out. The companion's Sky page is the control.
- **Later rounds:** rays across the far sky if the haze's range does not give them, rain shafts, a rainbow, and each
  weather's tuned look.

## The contract between the tasks

Both tasks code against these names. Change one only by telling Claude in your report.

| What | Value |
|---|---|
| Sky mode | `rtx.skyMode` 2 is the Enhanced sky. 1 stays today's sky, 0 the game's own |
| Option keys | Every library setting is registered as `rtx.atmosphere.numos.<library key name>` |
| Weather keys | The integration's `rtx.weather.<name>` options become `rtx.atmosphere.numos.weather.<name>`; `rtx.skyProvider.worldChangeCount` becomes `rtx.atmosphere.numos.worldChangeCount` |
| Quality | `rtx.atmosphere.numos.qualityLevel`: 0 High, 1 Medium, 2 Low, as the library defines it |
| Haze and Remix fog | As in the integration: while `rtx.volumetrics.enable` is on, the library's haze is off |
| Files beside `d3d9.dll` | A `numos` folder: the library's shaders if it loads them at run time, `nightsky/`, `LICENSE`, `NOTICE`, `THIRD_PARTY_NOTICES.md`, `licenses/` |
| VR | While a VR session runs, mode 2 renders as mode 1 |

## Task R: the runtime port

**Goal.** Our runtime builds with the library as sky mode 2, and with `rtx.skyMode` 0 or 1 it behaves exactly as it
does today.

**Where.**

- Code: the live runtime worktree `<repo>/out/worktrees/r17/out/runtime-src`, on the fork branch
  `claude/sky-enhanced` (already created, at patches 0001-0106). It belongs to the fork clone that
  `git rev-parse --git-common-dir` names there. Read that tree's own `CLAUDE.md` first and follow it.
- Patches and records: this repository, in the worktree `<repo>/out/worktrees/sky2r` on branch `sky-enhanced-r`.

**Steps.**

1. Add the library as a pinned clone at `41842c6`, recorded in `runtime/base.json` as DLSS and SHaRC are. Use it
   unmodified.
2. Port the integration commit, `Kim2091/dxvk-remix` `1532c782` ("Add the NUMOS sky as an optional sky provider"),
   onto our tree. Its files and per-file patches are in `<repo>/out/sky2/scratch/numos-upstream`, and
   `numos-library.md` section 3 has the apply test: 108 of 125 hunks apply as text, 17 need a hand.
3. Make it mode 2. `SkyMode` gains a third value. In mode 2 our `RtxAtmosphere` stays idle; in modes 0 and 1 the
   adapter creates nothing. `numos-library.md` section 4 lists the nine C++ files and six shader files that read the
   mode.
4. Keep the two skies' shader names apart. At least 57 top-level names clash (`AtmosphereArgs`, `evalSkyRadiance`).
   - The suggested way is a build step that writes a prefixed copy of the library's host headers, which the ray
     tracing passes include.
   - Whatever the way, three things hold: the library's clone stays unmodified; today's sky's shader sources are not
     edited; no ray tracing pass is compiled twice. The composite's sky variant, as the integration has it, is the
     one exception.
5. Register the library's settings under the contract's keys. Our existing `rtx.atmosphere.*` and `rtx.weather.*`
   options keep their names, defaults and meaning.
6. Leave the adapter's menu out of the build. A release build refuses a menu text without its six translations.
7. Write nothing into the game folder: no preset files, no marker file in `rtx-remix/weather`. The built-in weather
   presets stay in memory, chosen by option. Remove the preset directory option, or make it unreachable: it holds a
   path.
8. Install the `numos` folder beside `d3d9.dll` (`meson install --tags output`, as `build_runtime.ps1 -Install`
   uses), and add the library's notices to the runtime's `ThirdPartyLicenses.txt` as the integration does.
9. While a VR session runs, mode 2 renders as mode 1.
10. Build until `d3d9.dll` compiles and links with no error. Then run the runtime's unit suite, and add unit tests
    for what can be tested without a GPU: the key mapping, the mode gating, the preset selection.
11. Export the work as runtime patches from 0107 on (one patch per commit, `format-patch -1 --start-number <N>
    --zero-commit`), record them and the clone in `runtime/base.json` (`pending_patches`; no import), and make
    `runtime\build_runtime.ps1 -NoImport` pass on the tree.

**Deliver.**

- The fork branch `claude/sky-enhanced` with your commits, and the built tree.
- In `sky2r`: the patches, `base.json`, a section at the top of `runtime/README.md`, and your report,
  `docs/handover/sky-enhanced-R-report.md`:
  - what you ported as it was, and what you changed and why;
  - how the name prefix works;
  - every option key the adapter registers;
  - each rejected hunk and how you resolved it;
  - what you built and tested, with the commands and their output;
  - what you could not do;
  - what Claude should look at first in the game.

## Task C: the companion's switch and mapping

**Goal.** The player picks Standard or Enhanced on the companion's Sky page, and every sky control of that page drives
whichever sky is chosen.

**Where.** This repository, in the worktree `<repo>/out/worktrees/sky2c` on branch `sky-enhanced-c`. No runtime build
is needed: code against the contract above and the library's settings, which
`<repo>/out/sky2/scratch/list_settings.py` lists from `<repo>/out/sky2/scratch/numos-sky/include/numos/settings_fields.inl`.
Its weather presets are in `include/numos/weather.h` and `src/weather.cpp` of that clone.

**Steps.**

1. A saved client setting, off by default, and a "Sky quality: Standard / Enhanced" choice on the Sky page.
   - Mark Enhanced as experimental in its help text.
   - It applies only while the RTX sky shows (ADR 0249).
   - A map's own sky and a fixed sky (ADR 0248) are untouched.
2. In Enhanced, set `rtx.skyMode` 2 and drive the library's keys. In Standard, send exactly what the companion sends
   today: a test must prove that the Standard path's calls are unchanged.
3. Map every control of the Sky page onto the library:
   - the twelve weathers;
   - the time of day and the passing of time;
   - the Moon's options that have a counterpart;
   - wind;
   - fog and visibility.

   Keep the mapping as data: one table per weather, with the library keys and values it sets. Claude will tune the
   values in the game without touching code. Start each weather from the nearest of the library's eleven presets.
4. In Enhanced, turn Remix volumetrics off so the library's haze shows. Record the player's own value first, and
   put it back when Enhanced is left.
5. Map our performance tiers onto `rtx.atmosphere.numos.qualityLevel`, and add an Enhanced quality choice the player
   can override.
6. While VR is on, the page says Enhanced is not available in VR, and sends Standard.
7. Every new text in the six languages (`companion/i18n`), by the catalogs' own tools and glossaries.
8. Tests, in the pattern of the companion's existing sky tests. Then `tools\test.ps1 -Config Release` from `sky2c`.

**Deliver.** Commits on `sky-enhanced-c`, and your report, `docs/handover/sky-enhanced-C-report.md`:

- the setting and the page;
- the mapping tables and where each value came from;
- what has no counterpart in the library;
- the tests and their output;
- what Claude must check in the game.

## Task P: the package carries the Enhanced sky

Added on 2026-11-26, after tasks R and C were merged into `sky-enhanced`.

**Goal.** The RTX package built from this branch deploys the Enhanced sky's files, and the branch passes
`tools\test.ps1 -Config Release`. Nothing is uploaded.

**Where.** This repository, in the worktree `<repo>/out/worktrees/sky2p` on branch `sky-enhanced-p`. The runtime
tree and its finished build are as in task R; read `docs/handover/sky-enhanced-R-report.md` first.

**Steps.**

1. Make the runtime part carry the `numos` folder that `meson install --tags output` puts beside `d3d9.dll`: the 41
   compiled passes, `nightsky/` with its credits, `LICENSE`, `NOTICE`, `THIRD_PARTY_NOTICES.md` and `licenses/`.
   - The loader must deploy them beside the runtime's `d3d9.dll`.
   - Import them with `tools\inputs.py import runtime --file`, one import at a time.
2. Store the built `d3d9.dll` and record what it was built from, with `runtime\build_runtime.ps1` (no `-NoImport`),
   so `tools\check_repo.py` passes. This is the one LFS import of the round: it stays local.
   - **A build loads the CPU for many minutes.** Before you start one, check that no PoC game runs (`gmod.exe` under
     the PoC install) and that `<repo>/out/r10/poc.lock` is absent. Another agent measures frame times there. If it
     is busy, do the other steps first and check again.
3. Make GitHub's package workflow able to build the same package:
   - `tools/ci` fetches the library at its pin (`pins.json`, the cache keys);
   - `collect_runtime.py` takes the `numos` folder.

   Do not start the workflow.
4. The package's licence files: the library's `LICENSE`, `NOTICE` and third-party notices travel with the runtime
   part, and the night sky data keeps its credits. `packages/README.md` and the part's own notes say so.
5. Update every test that lists the runtime part's files, licences or patches.
6. Run `tools\test.ps1 -Config Release` from `sky2p` until it passes. Then build the package locally with
   `python tools\build_package.py`, and report its size beside the published one's.

**Deliver.** Commits on `sky-enhanced-p`, and your report, `docs/handover/sky-enhanced-P-report.md`:

- what the package now carries, and where the loader puts it;
- the import and the build record;
- the workflow changes;
- the gate's output;
- the package's size before and after;
- what you could not do.

## Rules for both tasks

- **No game sessions.** Do not start Garry's Mod, the PoC or the field install. Claude does every test in the game.
- **Off limits:** SourcePT, its local checkout, OpenRemix. Never open them.
- **The library's licence:** keep every copyright and licence header. Do not modify the library's files.
- **No loader change:** nothing under `loader/`.
- **Nothing outward:** no push, no pull request, no Workshop upload, no tag, and no merge into `main`.
- **Commits:** on your own branch only, as the repository's git config identity, with no co-author trailer.
- **No LFS import:** do not run `tools\inputs.py import` for the runtime. Builds are `-NoImport`.
- **Paths:** tracked files, commit messages and reports name no user account and give no absolute local path
  (AGENTS.md rule 10).
- **Scratch:** temporary files go under the repository's `out\`. Delete large build copies you no longer need.
- **Documentation duties** of AGENTS.md apply. Shared documents (CHANGELOG, ROADMAP, COMPONENTS, RESEARCH, TESTING)
  get additive edits only. Leave ADRs to Claude.
- **If you are blocked,** write what blocks you in your report and stop. Do not work around a rule.

## What Claude does

- Reviews each task's diff and report.
- Tests in the PoC: Standard before and after (it must not change), then the four judged scenes in Enhanced, with
  frame times.
- Tunes the weather tables in the game.
- Writes the decision record, and shows the round to the user.
