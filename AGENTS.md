# AGENTS.md

Start here. This file tells an agent (or a human) what this repo is, the rules that are not
negotiable, and how to build, test and document a change.

## What this repo is

A **native loader for vanilla 64-bit Garry's Mod**. The user drops one file, `bin\win64\winmm.dll`,
into an otherwise untouched Steam install. At start-up it reads **packages** (`.gma` files from the
Workshop or local folders), deploys their native payloads (the NVIDIA RTX Remix runtime, `gmcl_`
binary modules, files under the game root such as `rtx-remix\mods`) and loads the Remix runtime
before the engine creates its Direct3D 9 device. It replaces the old workflow of keeping a separate,
patched copy of GMod managed by RTXLauncher.

- How it works: [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md)
- What each component does: [docs/COMPONENTS.md](docs/COMPONENTS.md)
- Where we are and what is next: [docs/ROADMAP.md](docs/ROADMAP.md) (current: **M0-M7, R1, R3, R4 (reviews, fixes, the QoL round's review and field QA; loader 0.10.1), R5 (the user's QoL report), R6 (performance tiers and stability evidence; loader 0.11.0), C-16 (steady anime eye whites), G1 (a glass overhaul), R7 (the user's report of 2026-11-01; loader 0.12.0), R8 (the user's report after R7; loader 0.12.1), R9 (glass realism and feedback), R10 (the user's character report: steady eye whites for imported characters, NPCs after a map change, VMD expressions on the model's own morphs) and R11 (automatic PBR: imported game characters' own maps, kept when their source folder is gone; a safer ToPBR; real replacements always first), R12 (the user's report after R11-B: NPCs after a re-import, game maps for renamed textures and manual choices per texture, manual eye whites, unused character textures no longer held in VRAM) and R13 (less RAM and VRAM with budgets that scale with the computer: memory profiles in loader 0.13.0, characters loaded on first use, idle game textures released, compact imported game maps; the lag report's Combine trigger) done, R14 (noclip and glass; the guide with annotated screenshots) done, R15 (imported characters: painted shadows left out and solid hair in RTX sessions; the loader release candidate) done, R16 (the sky at a map's start; the RTX package built on GitHub with every native binary and a SHA-256 report) done, R17 (cloud genera for each weather, a sun disc and a high cloud layer in Numos; the package workflow started by hand for releases) done, R18 (R17's sky limits: thin decks that close, a middle deck with its own patches, sun dogs and the other ice halos, a milky haze, a longer twilight) done, R19 (the pre-release review's findings fixed: content packages only from subscriptions, bounded DDS readers, the fixes' Lua paths kept in the game; release v0.14.0, loader 0.14.0) done, R20 (the user's report of 2026-11-06: particle and decal add-ons under RTX, the upscaling hint from the runtime's live state, the loader update reminder and the warning before the server browser, Dynamic Toolgun Screen and Blood Overhaul RTX in the package with realistic blood impacts, time passing by default, the dupe icon; loader 0.15.0) done, R21 (Blood Overhaul's resources and their PBR in the package by the author's permission; no Model Hotloader warning about the game's build) done, R22 (a loading window while the first start unpacks the package, loader 0.16.0; the frame generation hint also at the top right) done, R23 (the user's report of 2026-11-08: an engine guard and start-up watchdog for "Starting Lua" hangs, ARC9 under RTX; Wuthering Waves game roughness and metalness; a PBR progress notice; the material editor's tabs; skills; the multiplayer notice on a loader branch awaiting approval) done, R24 (the multiplayer notice as Lua in the add-on, run in the menu realm; ARC9 view models' stickers and gun screens, its DirectX warning; view model materials through the pipeline; a load overlay saying what a map load is doing) done, R25 (the user's report of 2026-11-09: a stuck spawn-menu drag ended; ARC9's magnified scopes path traced through a raytraced render target, its gun path traced, no black copy of the scope) done, R26 (the user's request of 2026-11-09: the sky without a horizon; the load accelerator, failed file lookups and add-on searches answered from memory in RTX starts) done, R27 (the user's report of 2026-11-09: HUD add-ons that turned the screen white under RTX; depth-only colour targets and refused base textures in the render guard) done, R28 (the user's request of 2026-11-10: GitHub issue 2 resolved in the package: no Windows Error Reporting snapshot of a crashed game, no texture preload at the end of a load; periodic screen read-backs stopped and repeated font definitions made once under RTX, slow hooks named and `nativeloader_lag_report`; the light updater's bounded draw list) done, V1 (VR, "RTX in the headset": Start VR on the RTX Remix tab's VR page puts the path-traced game into a SteamVR headset, off until then; approved by the user on 2026-11-10) done; V2-V4 (VR hands, movement, menus, physics, weapons, reload and tools in the headset; approved by the user on 2026-11-12 as a deliverable at this stage) done; V6-V7 (VR Auto quality, a seven-step ladder that holds half the headset's refresh, and true stereo, each eye path traced with its own history; V5 skipped, VR is single-player only; approved by the user on 2026-11-13) done; V8 (VR holds that follow the hand, two hands on one object and one-hand turning, a freeze key, frame generation as SteamVR's Motion Smoothing; approved by the user on 2026-11-13) done; the QoL round of 2026-11-14 (the Moon by day, the start-up crash 0xC0000005 fixed in the runtime, ToPBR fixed (GitHub issue 6), the flashlight's automatic brightness and the dance light, the load overlay's estimate, a main-menu PBR note) done; the runtime brought up to date with NVIDIA's dxvk-remix `main` of 2026-11-14 (runtime patch 0093, Remix API 0.1000.2) done; GitHub issue 1 (Source eyes show their irises) and the PBR note as the user asked (2026-11-14) done; the crosshair and the HUD still under DLSS frame generation (runtime patch 0094), noclip and broken glass, and the changelog posted in full as the Workshop change notes (2026-11-14) done; the Advanced MMD Animation Player's hitch on each click fixed, with keep expressions, ragdoll collision for dancing NPCs and the debug window's timeline (2026-11-15) done; GitHub issue 3 (the `poster` command under RTX: the runtime renders it in tiles of the window's size, runtime patch 0095, the engine guard takes the command; 2026-11-15) done; the RTX Remix menu (Alt+X) drawn again with frame generation on (runtime patch 0096, 2026-11-15) done; GitHub issue 12 (Radeon cards crashed at the main menu and in maps: every single-sample read-back resolved into itself, runtime patch 0097, 2026-11-15) done; the About tab's secrets race (a crash soon after a start or at a level change after new RTX content deployed, runtime patch 0098, 2026-11-15) done; the night sky editor (each element of the night sky on its own in the RTX Remix tab, the constellations a layer of their own; runtime patch 0099, 2026-11-15) done; the Remix menu's (Alt+X) 98 texts from the upstream update translated into the six languages (runtime patch 0100, 2026-11-15) done; imported characters' back-face copies deform with the layer facing outside (no black patches on skirts and sleeves under RTX; the Model Hotloader's natives, 2026-11-16) done; the user's QoL requests of 2026-11-16 (ToPBR on the map's own surfaces unless the player widens its range, marked experimental, the fixes' fourteenth native patch; a dance holds its last pose three seconds before the reference pose; a dancing NPC's push strength) done; Linlong's RTX PBR materials shipped with the Model Hotloader (the user's request of 2026-11-16, package only) done; the Mesh Separator (a piece of a Model Hotloader character or a vanilla prop, ragdoll or NPC detached as a Static Props library prop with generated physics; the Hotloader's natives and Lua, 2026-11-16) done; the Mesh Separator's selection in its editor only, nothing drawn on the model in the world (ADR 0233, the user's request of 2026-11-16) done; the user's report of 2026-11-16 (Imported game PBR names the PBR Remix draws for each material and follows the characters; a dance's music ends with its dancer; package only) done; the repository review of 2026-11-16 (30 findings fixed in the package as the user approved: what a server, a Workshop item and Lua may reach, crashes on crafted input, the publisher; runtime patches 0101-0104, the fixes' fifteenth native patch, ADR 0234) done; a window when RTX Remix is left without its loader (the user's request of 2026-11-16: at the first map, since no add-on runs in the main menu without `winmm.dll`; ADR 0235) done; Linlong's PBR retuned (the user's report of 2026-11-16: her hair one even colour, the stronger maps they chose; ADR 0236) done; developer debug views from Lua again (the debug module writes Remix options through the Remix API behind its developer gate, `RemixConfig`, servers and an ordinary game's add-ons still refused; ADR 0237, 2026-11-16) done; the second load speed-up round (the user's request of 2026-11-16, the four items they chose: the Model Hotloader's map-start work done once and its warm characters made ready after the map runs, the load accelerator caching links, junctions and character packs; modern_house in the user's game 92 s -> 30 s; ADR 0238, ADR 0239) done; the third load speed-up round (the user's request of 2026-11-17, the plan's remaining items: ARC9's attachment icons decoded when first drawn, the load's slowest Lua callbacks named, a load's reads read ahead for the next; ADR 0240-0242; the loader items rejected) done; imported characters' hair and clothing leave out what nobody can see (other add-ons' invisible ragdolls and helpers, Enhanced Death Animations the example; ADR 0245, 2026-11-17) done; the DirectX level servers see (the user's request of 2026-11-18: in multiplayer games an RTX start answers `render.GetDXLevel()` with the level the game was started at, 90, set up by the RTX client module before any server's Lua; ADR 0246, package only) done; the crash when the game leaves threaded rendering (the user's report of 2026-11-19, `disconnect` back to the main menu, the seventh field crash of its kind: the engine guard drops queued render calls whose object is gone before `disconnect` and `map` run them, and logs them; ADR 0247, package only) done; a map's add-on keeps a fixed sky, such as space, under the player's own sky (the user's answer of 2026-11-20 for the gm_stelliferous remaster; ADR 0248, package only) done; R2 (field parity with the classic install) in progress**)
- Picking up a milestone from another agent: [docs/handover/](docs/handover/README.md) (your brief is there; the latest is [render-queue-check-report.md](docs/handover/render-queue-check-report.md) (the crash when the game leaves threaded rendering: before `disconnect` and `map` run the queued render calls, the engine guard drops those whose object is gone and logs them; the freed objects were GMod's own; package only, 2026-11-19), after [multiplayer-dxlevel-report.md](docs/handover/multiplayer-dxlevel-report.md) (the DirectX level servers see: in multiplayer games `render.GetDXLevel()` answers the level the game was started at, set up before any server's Lua by the RTX client module's prelude; package only, 2026-11-18), after [invisible-colliders-report.md](docs/handover/invisible-colliders-report.md) (imported characters' hair and clothing leave out what nobody can see: other add-ons' hidden entities, Enhanced Death Animations' bone-follower helpers the example; package only, 2026-11-17), after [load-speedup-3-report.md](docs/handover/load-speedup-3-report.md) (the third load speed-up round: ARC9's attachment icons decoded when first drawn, the load's slowest Lua callbacks named in the overlay's end line, a load's reads recorded and read ahead; package only, 2026-11-17), after [load-speedup-2-report.md](docs/handover/load-speedup-2-report.md) (the second load speed-up round: the Model Hotloader builds its library once for a catalog burst, decodes manifests and rigs once and makes its warm characters ready after the map runs; the load accelerator caches links, junctions and character packs; package only, 2026-11-16), after [debug-views-report.md](docs/handover/debug-views-report.md) (developer debug views from Lua again: behind the debug module's developer gate it writes Remix options through the Remix API, `RemixConfig` unchanged; the debug module 0.2.2, package only, 2026-11-16), after [linlong-pbr-tune-report.md](docs/handover/linlong-pbr-tune-report.md) (Linlong's PBR: an evened hair texture and stronger maps, chosen from an A/B in the user's game; package and skill, 2026-11-16), after [leftovers-popup-report.md](docs/handover/leftovers-popup-report.md) (a window when RTX Remix is left in the game without its loader: put the loader back, or delete by hand; package only, 2026-11-16), after [review-fixes-report.md](docs/handover/review-fixes-report.md) (the repository review's 30 findings fixed in the package: the RemixConfig allowlist, a mod's option layers, the startup text's folder, VR's native single-player gate, the Model Hotloader's server rules and crash fixes, limits for lights, portals and tools, the publisher's checks; runtime patches 0101-0104, 2026-11-16), after [pbr-page-dance-music-report.md](docs/handover/pbr-page-dance-music-report.md) (Imported game PBR names each material's PBR source and follows the characters; a dance's music ends with its dancer; package only, 2026-11-16), after [mesh-separator-report.md](docs/handover/mesh-separator-report.md) (the Mesh Separator: a piece of a Model Hotloader character or a vanilla prop, ragdoll or NPC detached as a prop with generated physics; the Hotloader's natives and Lua, 2026-11-16; its last section: the selection in the editor only, ADR 0233), after [linlong-pbr-report.md](docs/handover/linlong-pbr-report.md) (Linlong's RTX PBR in the Model Hotloader part, the user's pack; package only, 2026-11-16), after [qol-2026-11-16-report.md](docs/handover/qol-2026-11-16-report.md) (ToPBR on the map's own surfaces by default with a range to choose, marked experimental; the dance end hold; a dancing NPC's push strength; the fixes' fourteenth native patch, 2026-11-16), after [backface-twins-report.md](docs/handover/backface-twins-report.md) (imported characters' back-face copies deform with the layer facing outside: no black patches on skirts and sleeves under RTX; the Model Hotloader's natives, 2026-11-16), after [remix-menu-i18n-report.md](docs/handover/remix-menu-i18n-report.md) (the Remix menu's 98 texts from the upstream merge translated into the six languages; runtime patch 0100, 2026-11-15), after [night-sky-editor-report.md](docs/handover/night-sky-editor-report.md) (the night sky editor: each layer of the night sky image with its own brightness and colour, the constellations split out of the nebula, the moon, shooting stars and night glow; runtime patch 0099, 2026-11-15), after [secrets-race-report.md](docs/handover/secrets-race-report.md) (the About tab's secrets race: a crash soon after a start or at a level change after new RTX content deployed; runtime patch 0098, 2026-11-15), after [issue12-amd-resolve-report.md](docs/handover/issue12-amd-resolve-report.md) (GitHub issue 12: Radeon cards crashed with 0xC0000005 at the main menu and in maps; runtime patch 0097, 2026-11-15), after [altx-menu-report.md](docs/handover/altx-menu-report.md) (the RTX Remix menu, Alt+X, not drawn with frame generation on: runtime patch 0096, 2026-11-15), after [issue3-poster-report.md](docs/handover/issue3-poster-report.md) (GitHub issue 3: the `poster` command under RTX, rendered in tiles by the runtime; runtime patch 0095 and the engine guard, 2026-11-15), after [mmd-player-report.md](docs/handover/mmd-player-report.md) (the Advanced MMD Animation Player: a click asks for its built flags, not every motion's details; keep expressions, ragdoll collision, the debug timeline; 2026-11-15, package only), after [glass-crosshair-report.md](docs/handover/glass-crosshair-report.md) (the changelog on the Workshop, noclip and broken glass, the crosshair under frame generation: runtime patch 0094, 2026-11-14), after [issue1-eyes-report.md](docs/handover/issue1-eyes-report.md) (GitHub issue 1: Source eyes show their irises; the PBR note as the user asked, 2026-11-14, package only), after [upstream-runtime-report.md](docs/handover/upstream-runtime-report.md) (the runtime up to date with NVIDIA's dxvk-remix `main`, runtime patch 0093, 2026-11-14), after the QoL round of 2026-11-14: [moon-by-day-report.md](docs/handover/moon-by-day-report.md), [crash-0xc0000005-report.md](docs/handover/crash-0xc0000005-report.md), [issue6-topbr-report.md](docs/handover/issue6-topbr-report.md), [lights-report.md](docs/handover/lights-report.md) and [load-eta-report.md](docs/handover/load-eta-report.md) (runtime patches 0090-0092, package only), then [VR-V8-report.md](docs/handover/VR-V8-report.md) (VR milestone V8, 2026-11-13), then [VR-V6-V7-report.md](docs/handover/VR-V6-V7-report.md) (VR milestones V6 and V7, 2026-11-13), then [VR-V4-report.md](docs/handover/VR-V4-report.md) (VR milestones V2-V4, 2026-11-12), then [VR-V1-report.md](docs/handover/VR-V1-report.md) (VR milestone V1), then [uninstall-leftovers-report.md](docs/handover/uninstall-leftovers-report.md) (RTX a removed loader left in the game, 2026-11-13, package only), then [unsubscribe-report.md](docs/handover/unsubscribe-report.md) (the user's unsubscribe report of 2026-11-11, package only) and [colour-cap-report.md](docs/handover/colour-cap-report.md) (material colours above 1 capped for Remix, 2026-11-11, package only) and [queued-draws-report.md](docs/handover/queued-draws-report.md) (the RTX fixes' crash on the queued render thread, 2026-11-12, package only) and [mod-load-cache-report.md](docs/handover/mod-load-cache-report.md) ("Loading enhancements" at every start, runtime patch 0086, 2026-11-12, package only) and [issue5-report.md](docs/handover/issue5-report.md) (GitHub issue 5: MineMod's "Default texture pack is not ready" line kept off the screen by the render guard, 2026-11-13, package only), after [R28-report.md](docs/handover/R28-report.md), beside it [hotloader-import-report.md](docs/handover/hotloader-import-report.md) (the Model Hotloader's imports, 2026-11-10) and its follow-up [portals-render-mesh-report.md](docs/handover/portals-render-mesh-report.md), after [R27-report.md](docs/handover/R27-report.md), after [R26-report.md](docs/handover/R26-report.md), after [R25-report.md](docs/handover/R25-report.md), after [R24-report.md](docs/handover/R24-report.md), after [R23-report.md](docs/handover/R23-report.md), after [R22-report.md](docs/handover/R22-report.md), after [R21-report.md](docs/handover/R21-report.md) with its [plan](docs/handover/R21-plan.md), after [R20-report.md](docs/handover/R20-report.md) with its [plan](docs/handover/R20-plan.md), after [R19-report.md](docs/handover/R19-report.md) with its [plan](docs/handover/R19-plan.md), after [R18-report.md](docs/handover/R18-report.md), [R17-report.md](docs/handover/R17-report.md), [R16-report.md](docs/handover/R16-report.md), [R15-report.md](docs/handover/R15-report.md), [R14-report.md](docs/handover/R14-report.md) and [R13-report.md](docs/handover/R13-report.md), after [R12-report.md](docs/handover/R12-report.md) and [R11-report.md](docs/handover/R11-report.md) with its follow-up [R11-B-report.md](docs/handover/R11-B-report.md))
- Why it is built this way: [docs/decisions/](docs/decisions/README.md)
- Facts gathered about GMod, Remix and the existing RTX tooling: [docs/RESEARCH.md](docs/RESEARCH.md)
- This machine (installs, toolchain): [docs/ENVIRONMENT.md](docs/ENVIRONMENT.md)

VR: milestones V1 (2026-11-10; [report](docs/handover/VR-V1-report.md), [design](docs/handover/VR-plan.md)),
V2-V4 (hands, movement, menus, physics, weapons, reload and tools; approved 2026-11-12 as a deliverable at this
stage; [V4 report](docs/handover/VR-V4-report.md)), V6-V7 (Auto quality and true stereo;
[V6-V7 report](docs/handover/VR-V6-V7-report.md)) and V8 (grabbing, freezing, frame generation;
[V8 report](docs/handover/VR-V8-report.md)), both approved 2026-11-13, are merged; V5 was skipped and VR is
single-player only. A VR milestone reaches `main` only when the user approves it, and the next one starts only when
the user asks. Codex coded V1-V4 under Claude's direction; Claude finished V4 and coded V6-V8. VR test runs leave
SteamVR running and unchanged and take both shared locks.

## Repo map

| Path | What |
|---|---|
| `loader/` | C++20 loader: `core/` library (`nl_core`), `tests/`, `proxy/` (the `winmm.dll`), `cli/` (`nlctl.exe`) |
| `tools/` | Build, test and maintenance scripts; each has a `.md` beside it; `vr_session.py` runs the production VR session in the PoC with both shared locks and keeps its counters, timings and images under `out` |
| `tools/steam/` | Steam depot manifest tools: verify an install, build the vanilla PoC copy |
| `tools/gmapack/` | Vendored `.gma` reader and writer (Python) |
| `tools/sky/` | Tools that make the runtime's sky textures (the Moon, the night sky image) |
| `tools/ci/` | What `package.yml` builds the package's native binaries from (`pins.json`) and the scripts it runs: the fixes' modules, the debug module and the bridge, the runtime's files, this repository's modules, the Model Hotloader's natives, the pinned downloads, the cache keys ([tools/ci/README.md](tools/ci/README.md)); and the record of what this repository's own modules in `packages/` were built from, which `check_repo.py` checks: refresh them with `repo_builds.py refresh`, not `inputs.py import` ([ADR 0126](docs/decisions/0126-a-record-of-what-this-repositorys-modules-were-built-from.md)) |
| `packages/` | Every input of the RTX package's fifteen parts, so this repo alone builds it: text as it is, binaries xz-compressed in Git LFS, each part indexed in `files.json` ([packages/README.md](packages/README.md), [ADR 0033](docs/decisions/0033-one-repository-package-inputs-in-git-lfs.md)) |
| `runtime/` | This project's changes to the Remix runtime fork, as patches against the fork commit in `base.json`, with what else the build has (submodule settings, clones; [ADR 0034](docs/decisions/0034-the-runtimes-build-inputs-recorded.md)), and the script that rebuilds `d3d9.dll` from them ([runtime/README.md](runtime/README.md)) |
| `third_party/` | Vendored third-party code, byte-identical to upstream, each with its licence: `lzma/` (LZMA SDK decoder); `jolt/` (Jolt Physics 5.3.0, linked into the glass module); `openvr/` (OpenVR v2.15.6 header and BSD-3-Clause licence); `reshade/` holds only ReShade's licence, for the unchanged ReShade binary the RTX package carries |
| `skills/` | Agent skills, each a `SKILL.md` with references and scripts: AI PBR materials for MMD characters (`mmd-remix-pbr`, with the `rpai` tool) and for maps (`remix-map-pbr`), and Workshop content packs with their dependencies (`workshop-content-pack`) ([skills/README.md](skills/README.md)) |
| `dist/` | What the end-user bundle ships besides `winmm.dll`: the default `native-loader/config.json` and the player README ([ADR 0017](docs/decisions/0017-release-bundle-and-ci.md)) |
| `glass/` | The glass system (G1, [ADR 0070](docs/decisions/0070-glass-overhaul.md)): `addon/` (the Lua add-on: panes, damage, cracks, fracture, broken-glass manager), `native/` (the Jolt client module for broken glass) |
| `vr/` | VR (V1, approved 2026-11-10): `native/` owns OpenVR in `gmcl_nlvr_win64.dll`, with offline tests and the development probe; `addon/` owns the head camera and wrist HUD; `input/` holds the action manifest and controller bindings. The companion owns the VR page and the runtime owns eye output ([ADR 0145](docs/decisions/0145-vr-in-the-rtx-package.md)) |
| `engine_guard/` | The engine guard (R23, [ADR 0130](docs/decisions/0130-an-engine-guard-for-lua-start-up.md)): `gmcl_`/`gmsv_nlengineguard_win64.dll`, shipped in the fixes part: cuts material fallbacks that lead back into their own chain (they stopped RTX starts at "Starting Lua") and watches start-up to name a stuck add-on; from R24 also loaded in the menu realm, where its load overlay shows what a map load is doing ([ADR 0134](docs/decisions/0134-what-a-map-load-is-doing.md)); from R28 every realm's load also switches Windows Error Reporting's snapshot of the game off ([ADR 0142](docs/decisions/0142-no-crash-snapshot-of-the-game.md)) |
| `fs_accel/` | The load accelerator (R26, [ADR 0140](docs/decisions/0140-the-load-accelerator.md)): `gmcl_`/`gmsv_nlfsaccel_win64.dll` and its add-on (`addon/`, deployed as `garrysmod/addons/nlloadaccel`), the package's `load-accelerator` part: answers GMod's failed lookups in the loose add-on folders from directory listings (import hooks on `filesystem_stdio.dll`) and `file.Find(pattern, <add-on title>)` from an index of GMod's add-on table; loaded at menu start by the companion's `load_accel.lua`, in RTX starts (the loader hides the package's add-ons without RTX) |
| `.github/ISSUE_TEMPLATE/` | The issue forms GitHub shows when someone opens an issue: `bug_report.yml` asks for what happened, the steps, other add-ons, a screenshot or video, the main menu's RTX Remix diagnostics (Copy diagnostics) and the logs for each kind of problem; `feature_request.yml`; `config.yml` leaves blank issues to maintainers and links the README, the latest loader release and the Workshop item. [`test_issue_forms.py`](tools/tests/test_issue_forms.py.md) checks them against GitHub's rules and against the buttons, files and commands they name |
| `.github/workflows/` | CI: `build.yml` runs `tools\test.ps1 -Config Release` and keeps the bundle as an artifact only for a `v*` tag, which releases it, or when a person starts it; no push of a branch or pull request starts it, and agents start it only for a release being prepared or when the user asks ([ADR 0114](docs/decisions/0114-the-loader-workflow-runs-only-for-a-release-or-by-hand.md)). `package.yml`, started only by a person for a release, builds the RTX package on GitHub, every native binary built or fetched there, reports the SHA-256 of the `.gma` and of every file in it, and keeps the newest `.gma` as its one `rtx-package` artifact ([ADR 0106](docs/decisions/0106-the-rtx-package-built-on-github.md), [ADR 0108](docs/decisions/0108-releases-built-on-github-by-hand-development-built-here.md)). Every artifact, the loader's bundle included, expires two days after its run ([ADR 0113](docs/decisions/0113-every-actions-artifact-expires-after-two-days.md)) |
| `docs/` | Architecture, package format, on-disk layout, testing, roadmap, research, decisions |
| `CHANGELOG.md` | Notable changes, newest first |

## Rules

1. **Develop against the PoC install.** `<SteamLibrary>\steamapps\common\GarrysMod_PoC` is a
   byte-exact vanilla copy made for experiments (where the Steam library is: [docs/ENVIRONMENT.md](docs/ENVIRONMENT.md)). The field install `...\common\GarrysMod` is the
   user's real game: change it only when the user asks in this conversation, after backing up what
   you will touch. The user replaced `GarrysMod_RTX_c` with this project's implementation on
   2026-10-30: it is no longer a classic RTX baseline. Never write there or in
   `GarrysMod_RTX_c_backups`; prepare a fresh legacy fixture under `out` for migration tests.
2. **Never write Steam's files on disk.** Depot files in any install stay byte-identical; anything we
   need differently happens in memory or through a declared, journaled override (later milestones).
   [`tools/steam/verify_install.py`](tools/steam/verify_install.py.md) proves an install is still vanilla.
   The user's legacy-migration request (2026-10-30) permits one narrow exception: restore recognized
   pre-existing RTXLauncher modifications to hash-verified stock bytes, with the old bytes archived
   first in the deployment transaction ([ADR 0042](docs/decisions/0042-legacy-remix-migration.md)).
   This never permits patching an otherwise vanilla depot file on disk.
3. **Never touch Remix `user.conf`**, and never destroy a file the user edited (compare hashes first).
   A package's `replace-owned` file that changed is put back, and whatever was in its place is kept
   (`native-loader\backup\edits`, or `backup\originals`, put back when the package goes); a
   `create-only` file the user changed stays theirs ([ADR 0035](docs/decisions/0035-restore-automatically.md),
   the user, 2026-10-29).
4. **Native code is opt-in.** Only allowlisted packages may deploy or load native code
   ([ADR 0003](docs/decisions/0003-native-trust-allowlist.md)); a package from any other subscribed
   Workshop item may hold content only ([ADR 0027](docs/decisions/0027-content-packages-from-any-subscription.md));
   subscribed means Steam's record names a subscriber, not merely installed: any server can make the game
   download an item ([ADR 0111](docs/decisions/0111-content-packages-only-from-subscribed-items.md)). Do not loosen the allowlist, the path
   rules or the off switches without a new decision record that the user agreed to.
5. **Ask before anything outward-facing:** pushing to `origin`, publishing or updating a Workshop
   item, changing Steam settings or launch options, deleting user data.
   - **Standing permission** (the user, 2026-10-28;
     [ADR 0019](docs/decisions/0019-agents-push-main-and-update-workshop.md)): agents push `main` to
     `origin` and update the project's Workshop items (3829070317 and test items) without asking, once
     `tools\test.ps1` passes. Other branches, tags (a `v*` tag makes a public release) and force pushes
     still need asking.
   - **Test items** (the user, 2026-10-28): agents may upload test items for this project to the
     Workshop, and update them, without asking. Keep them hidden. Modern House RTX is one: 3829275998
     ([ADR 0023](docs/decisions/0023-content-packages-and-modern-house-item.md)).
   - **Never remove or delete anything on the Workshop until the user says the project is done.** That
     covers the test items too (the first is 3829070317,
     [ADR 0015](docs/decisions/0015-workshop-route-for-native-packages.md)).
   - Making an item public, or publishing another real package, still needs the user's go-ahead.
   - **Item 3829070317 is the project's distribution item** (the user, 2026-10-28;
     [ADR 0016](docs/decisions/0016-one-workshop-item-kept-current.md)). It holds the combined RTX
     package, and during development commits, merges and pushes of `main` keep it current: git hooks
     run [`tools/publish_workshop.py`](tools/publish_workshop.py.md) in the background, which builds the
     package here from `packages/` and uploads it when its content changed. That update needs no asking.
     A commit on `main` therefore publishes whatever its packaging inputs hold, so test those changes on
     a branch first. **Only a person starts GitHub's package workflow** (`package.yml`, every native
     binary built there and a SHA-256 report), for a release; `publish_workshop.py --from-ci` then
     uploads that run's `.gma` ([ADR 0106](docs/decisions/0106-the-rtx-package-built-on-github.md),
     [ADR 0108](docs/decisions/0108-releases-built-on-github-by-hand-development-built-here.md)), within
     two days, before the run's artifacts expire
     ([ADR 0113](docs/decisions/0113-every-actions-artifact-expires-after-two-days.md)). Never
     start that workflow yourself. The build checks the package with the **main checkout's** built
     `nlctl.exe`: after a manifest change (a new key or kind), run `tools\build.ps1 -Config Release`
     there before the merge, or the publish fails. Install the hooks once per clone:
     `python tools\publish_workshop.py --install-hooks` (they also run Git LFS's hooks; a push without
     git-lfs is refused). The package's content comes from `packages/` and its native binaries from
     the sources `runtime/`, `tools/ci/pins.json` and this repository name, so a part changes only by a
     change committed here; the add-ons' own repositories do not reach the item.
   - **Every upload's change note carries the changelog in full** (the user's standard of 2026-11-14,
     [ADR 0222](docs/decisions/0222-the-workshop-change-notes-carry-the-changelog.md)): after the version
     line, each `CHANGELOG.md` entry added or reworded since the item's last upload, in Steam's markup and
     ASCII; what one note (8000 characters) cannot hold goes up in further notes with the same archive.
     `publish_workshop.py` does it for development builds and releases;
     `python tools\publish_workshop.py --show-notes` previews it.
6. **No binaries in git, except the RTX package's inputs in `packages/`** (the user, 2026-10-30;
   [ADR 0033](docs/decisions/0033-one-repository-package-inputs-in-git-lfs.md)): there every binary is
   stored xz-compressed in Git LFS, and only through `tools\inputs.py import`, which indexes it. No game
   files, build outputs or `.gma` packages anywhere else. Test fixtures are generated by the tests. Mind
   the LFS quota (10 GiB of storage and of downloads a month; a pushed object is never freed): import
   only what a part ships.
7. **Licences.** This repo is MIT. `garrys-mod-rtx-remixed` is GPL-2.0: read it for behaviour, do not
   copy its code into this repo's code. Its shipped files and local interface changes remain in
   `packages/fixes` under that licence, a separate part the package aggregates. The translated
   interface data in `companion/i18n/addons` is also GPL-2.0; the package carries its editable catalogs
   and `COPYING` ([ADR 0038](docs/decisions/0038-complete-bundled-interface-translations.md)).
   Third-party code goes in `third_party/<name>/` with its licence file; a part in `packages/` keeps
   its source's licence beside it. The repository is public (the user made it so by 2026-11-06, as
   https://github.com/SheepyLord/Gmod-Workshop-RTX-Remix): everything in `packages/` is published
   with it, so a part holds only what may be redistributed.

8. **Parallel milestones stay apart.** Each runs on its own branch in its own git worktree, and only
   touches the paths its brief in [docs/handover/](docs/handover/README.md) assigns. Shared docs
   (CHANGELOG, ROADMAP, COMPONENTS, RESEARCH, TESTING) get additive edits only, so merges stay trivial.
9. **Temporary and build files stay inside this repo, under the git-ignored `out\`** (the user's
   instruction): builds in `out\build\<preset>`, extra git worktrees in `out\worktrees\<name>`, test
   scratch in `out\tmp` (`tools\test.ps1` and `tools\build.ps1` point `TEMP`/`TMP` there), evidence in
   `out\<purpose>\`. Never the system temp folder or a sibling folder: in M1, Windows Defender blocked
   proxy builds and test hosts that were outside this folder.
10. **No account names or absolute local paths in tracked files.** The repository is public. Tracked
   files, commit messages, change notes, Workshop text and briefs for other agents name no user account
   and give no absolute local path: no `C:\Users\<name>\...`, and no drive path to a checkout, its
   sibling folders, a Steam library, a game install or a model folder. Write a path relative to the
   repository, or a placeholder: `%USERPROFILE%` (or `~`), `<repo>`, `<modding>` (the folder that holds a
   checkout and its siblings), `<SteamLibrary>`, `<PoC install>`, `<field install>`, `<models>`. When you
   quote tool output, put the placeholder in first. [`tools/check_repo.py`](tools/check_repo.py.md) fails
   on a Windows account folder in any text file and on the name of the account that runs it. Some files,
   [docs/ENVIRONMENT.md](docs/ENVIRONMENT.md) and some tools' defaults still hold absolute local paths: add
   none, and replace them in the lines you touch.

## Build and test

```powershell
tools\test.ps1                  # everything: conventions, Python tests, C++ build + CTest
tools\test.ps1 -SkipNative      # no compiler needed
tools\build.ps1 -Config Release # optimised C++ build (PDBs included)
tools\workflow.ps1              # what CI runs: Release checks, then the end-user bundle in out\dist
tools\workflow.ps1 -SkipTests -Install <game root>   # quick loop: build, bundle, put it in a game
git lfs pull; tools\workflow.ps1 -Package             # also the RTX package from packages\ (a local build: compared, not uploaded)
python tools\build_package.py --compare out\workshop\published.json   # the package alone, against the item
```

Toolchain: VS 2022 Build Tools (MSVC x64), CMake and Ninja bundled with it, Python 3.10+. `vswhere`
cannot see the Build Tools on the main machine; `tools\lib\VsDevEnv.psm1` handles that. Build output
goes to `out\` (git-ignored).

## Documentation duties (every change)

`tools\test.ps1` fails until these hold (checked by [`tools/check_repo.py`](tools/check_repo.py.md)):

- Every script (`.ps1 .psm1 .py .bat .cmd .lua .sh`) has `<script file name>.md` beside it: what it
  does, usage, inputs/outputs, side effects, exit codes. Update it when the script changes.
- Every C++ module folder (one with a `CMakeLists.txt`) has a `README.md` naming each source file.
- [docs/COMPONENTS.md](docs/COMPONENTS.md) lists every folder under `loader/` and `tools/`.
- Relative Markdown links resolve.

Not machine-checked, still required:

- Add a line under `## [Unreleased]` in [CHANGELOG.md](CHANGELOG.md) for every user-visible or
  design-relevant change (new component, changed behaviour, fixed bug, new rule). The next upload of the
  Workshop item posts it in full as its change note (ADR 0222): say first what changed for the player.
- Record design decisions as a new file in [docs/decisions/](docs/decisions/README.md); never rewrite an
  accepted decision, supersede it.
- Update [docs/ROADMAP.md](docs/ROADMAP.md) when a milestone item starts or finishes.
- Add facts you had to dig for (file:line, measured numbers) to [docs/RESEARCH.md](docs/RESEARCH.md).

## Glossary

| Term | Meaning |
|---|---|
| Field install | The user's Steam-managed `GarrysMod` |
| PoC install | `GarrysMod_PoC`, a vanilla copy for development |
| Bootstrap | `bin\win64\winmm.dll`: our proxy of the system `winmm.dll` |
| Package | A `.gma` with `native/manifest.json`; see [docs/PACKAGE_FORMAT.md](docs/PACKAGE_FORMAT.md) |
| Payload | Files a package deploys outside GMod's virtual file system |
| Runtime | The RTX Remix `d3d9.dll` and its dependencies (the user's fork, Remix API 0.1000.2) |
| Journal | `native-loader\state.json`: what the loader deployed, with hashes and backups |
