# Handovers

## Claude and Codex handoffs

- **2026-11-27 · Codex · Repeated props in Modern House** on `codex/sky-postfx-frame-time`. The user approved runtime patches 0121–0124 for the distribution item. The [combined handoff](repeated-mesh-frame-report.md) records the source, checks and game evidence.

- **2026-11-27 · Codex · Lower clouds and post-processing** on `codex/sky-postfx-frame-time`. Runtime patches 0121–0123 established the comparison baseline for the combined update. The [report](renderer-frame-output-report.md) records the build, PoC checks and remaining verification limits.

## Plans and reports

The Model Hotloader's frames without a character (2026-11-27), Codex's finding relayed by the user (the pre-render
callback used 0.46 ms a frame with no imported character): [hotloader-idle-report.md](hotloader-idle-report.md) (the
client's entity list checks only what may have changed instead of every prop, ragdoll and NPC each frame; legacy
searches only while a legacy entity exists; the natives rest when nothing needs them; the server's tick no longer
searches for server-side worlds nothing makes; measured A B A B in the PoC; package only, ADR 0273; merged on the
user's "Merge and publish").

The Enhanced sky below the horizon (2026-11-27), the user's report "the horizon looks a bit off":
[sky-enhanced-horizon-report.md](sky-enhanced-horizon-report.md) (the library's lit ground under the haze instead of a
wall of fog past a map's edge; No horizon in Enhanced with the clouds of the opposite side; runtime patches 0118-0120),
plan and briefs [sky-enhanced-horizon-plan.md](sky-enhanced-horizon-plan.md), task report
[runtime and companion](sky-enhanced-HR-report.md) (with HR2).

Our night sky on the Enhanced sky (2026-11-27), as the user approved the design:
[sky-enhanced-night-report.md](sky-enhanced-night-report.md) (the night sky image and its editor in Enhanced, real
stars one choice away, shooting stars, the Moon's glow, a solar eclipse that darkens the sky; runtime patches 0116 and
0117), design and briefs [sky-enhanced-night-plan.md](sky-enhanced-night-plan.md), task reports
[runtime](sky-enhanced-NR-report.md) (with NR2) and [companion](sky-enhanced-NC-report.md).

The Enhanced sky's round 3, the user's report after the merge (2026-11-26):
[sky-enhanced-round3-report.md](sky-enhanced-round3-report.md) (no black circle round the Sun or the Moon with DLSS,
runtime patch 0115; less mist by default and a Mist setting with Off), plan
[sky-enhanced-round3-plan.md](sky-enhanced-round3-plan.md), task reports [runtime](sky-enhanced-S-report.md) and
[companion](sky-enhanced-H-report.md).

The Enhanced sky (the user's request of 2026-11-25), merged on 2026-11-26 after two rounds on the user's "Merge and
publish": [sky-enhanced-round2-report.md](sky-enhanced-round2-report.md) (round 2: sun rays, the editor, mist
choices, a rainbow, the weathers retuned; the user's decisions at the merge; what is still wrong), after
[sky-enhanced-report.md](sky-enhanced-report.md) (round 1: the NUMOS library as a second sky). Plans and briefs:
[round 1](sky-enhanced-plan.md), [round 2](sky-enhanced-round2-plan.md). Task reports: [runtime](sky-enhanced-R-report.md),
[companion](sky-enhanced-C-report.md) and [package](sky-enhanced-P-report.md) in round 1;
[runtime](sky-enhanced-R2-report.md) and [companion](sky-enhanced-E-report.md) in round 2; the library's Remix menu in
seven languages, runtime patch 0114, after the user's answers: [sky-enhanced-M-report.md](sky-enhanced-M-report.md).

For the next loader release: [main-branch-plan.md](main-branch-plan.md). It covers Garry's Mod's main and prerelease
branches, where the 64-bit game is `gmod_win64.exe` in the game folder and RTX does not load. The user postponed it on
2026-11-25, to ship with other loader changes. Nothing is built yet.

VR V8 (the user's requests of 2026-11-13: the V4 neutral-yaw fixture, precise and two-handed grabbing, a freeze key,
frame generation in the headset, the desktop's resolution) was approved by the user on 2026-11-13 and merged to
`main`; Claude coded it on the branch `vr8` and ran it in the PoC and on the Index: [report](VR-V8-report.md).

VR V6 (performance) and V7 (true stereo) were approved by the user on 2026-11-13 and merged to `main`; Claude coded
both on the branch `vr6`, and V5 was skipped: [report](VR-V6-V7-report.md), [plan](VR-V6-V7-plan.md).
VR V2-V4 were approved by the user on 2026-11-12 as a deliverable at this stage and merged to `main`; Claude finished
V4 after Q's [hand-over](VR-V4-Q-resume.md). The [V4 report](VR-V4-report.md) starts with the final state, its test
results and what is still untested.

V2/V3 Q's implementation and evidence work is complete on v2q: [Q report](VR-V2V3-Q-report.md).
It records the 15-check scripted confirmations, both flat batches (including the first startup
failure), the passing full Release gate, preserved failures/recovery and the limits. Natural
controller alignment (C), the old absolute ghost guard and V4 package acceptance remain open;
the measured V2/V3 artifact predates the inbound W source.

VR V1, "RTX in the headset", was approved by the user and merged into `main` on 2026-11-10. **Start with
[VR-V1-report.md](VR-V1-report.md)**: what works and what does not, each spike's result, the measured costs, what in
the plan turned out wrong, how to look with the headset on, and the proposal for V2. The design,
made with the user on 2026-11-10, is [VR-plan.md](VR-plan.md). Its work plan with the
interfaces between the pieces is [VR-V1-plan.md](VR-V1-plan.md), and its tasks' briefs are
[VR-V1-A-sdk-and-probe.md](VR-V1-A-sdk-and-probe.md), [VR-V1-C-runtime.md](VR-V1-C-runtime.md),
[VR-V1-D-module.md](VR-V1-D-module.md), [VR-V1-E-addon-and-page.md](VR-V1-E-addon-and-page.md) and, for putting them
together, [VR-V1-Q-integration.md](VR-V1-Q-integration.md). The reports are
[A: SDK and probe](VR-V1-A-report.md), [C: runtime](VR-V1-C-report.md),
[D: module](VR-V1-D-report.md), [E: add-on and page](VR-V1-E-report.md),
[Q: integration and acceptance](VR-V1-Q-report.md) and
[Q: first review fixes and render-side pacing](VR-V1-Q-review-report.md). The last report supersedes the
serial pacing decision and measurements in the earlier reports. The module/add-on review follow-up is accepted;
the second independent runtime review is followed by
[Q: runtime review corrections and renewed acceptance](VR-V1-Q-runtime-review-report.md), accepted and merged into `vr`.
Claude directs and reviews, Codex writes the code
(the user's choice for the VR work). VR reaches `main` only when the user approves a milestone.

The latest round is R28, the user's request of 2026-11-10 (GitHub issue 2 resolved in the package: no Windows Error
Reporting snapshot of a crashed game, no texture preload at the end of a load; add-ons like HyperReal FX kept from
lagging the game: periodic screen read-backs stopped, repeated font definitions made once, slow hooks named and
`nativeloader_lag_report`; the light updater's bounded draw list): [R28-report.md](R28-report.md), done by Claude with a
Claude subagent for the review (no Codex).

After it, the user's report of 2026-11-11 (unsubscribing did not uninstall RTX on a computer where other Steam
accounts subscribe; an uninstall that left an earlier RTX installation): [unsubscribe-report.md](unsubscribe-report.md),
by Claude, package only ([ADR 0188](../decisions/0188-unsubscribing-with-the-loader-already-installed.md)).

Then the user's request of 2026-11-13 (a player still had the RTX Remix menu and a broken sky after removing the add-on;
make sure no RTX and bundled add-on stay after an unsubscribe or in a start without RTX):
[uninstall-leftovers-report.md](uninstall-leftovers-report.md), by Claude, package only
([ADR 0206](../decisions/0206-rtx-a-removed-loader-left-removes-itself.md)).

Then the user's report of 2026-11-11 on material colours above 1 under RTX (`[507 | -1] npc_citizen`; the user's
rule: "in Remix, `$color` should be capped at 1 wherever it exists"): [colour-cap-report.md](colour-cap-report.md), by
Claude, package only ([ADR 0190](../decisions/0190-material-colours-above-1-capped-for-remix.md)).

Then the RTX fixes' crash on the queued render thread, which the VR work's crash triage traced to the fixes (a prop
lighting hook calling into an entity the main thread had already deleted): [queued-draws-report.md](queued-draws-report.md),
by Claude, package only, merged and published 2026-11-12
([ADR 0192](../decisions/0192-the-fixes-never-read-a-queued-draws-renderable.md)).

Then the user's report of 2026-11-12 ("The field game takes a long time to load enhancements each start"): the Remix
runtime reread every replacement texture of every mod at each start; runtime patch 0086 keeps those reads between
starts: [mod-load-cache-report.md](mod-load-cache-report.md), by Claude, package only, merged and published 2026-11-12
([ADR 0195](../decisions/0195-the-mod-loader-keeps-its-texture-reads-between-starts.md)).

Then GitHub issue 5 of 2026-11-13 ("Default texture pack is not ready: resource_sampling_unsupported" at the centre
of the screen on every map): MineMod's line, caused by the render guard keeping its shaders inert; the guard keeps it
off the screen: [issue5-report.md](issue5-report.md), by Claude, package only, merged on the user's approval without
an in-game check and published 2026-11-13
([ADR 0210](../decisions/0210-an-add-ons-notice-of-the-guards-refusal-stays-off-the-screen.md)).

Then the user's requests of 2026-11-14 on the lights (the RTX flashlight's automatic brightness, on by default; the
dance animation player's light with uniform lighting, aim, colour temperature, a rim light and presets):
[lights-report.md](lights-report.md), by Claude on the branch `qol-lights`, package only, merged into `main` with the round (`qol-1114`) without an in-game check, on the user's "Commit and push"
([ADR 0208](../decisions/0208-the-rtx-flashlights-automatic-brightness.md),
[ADR 0209](../decisions/0209-the-dance-lights-uniform-lighting-and-options.md)).
Then GitHub issue 6 of 2026-11-13 ("Gmod ToPBR stopped loading?": textures written, no material shown): ToPBR's scan
of the other mods published nothing when it could not read a file (a binary Remix Toolkit mesh was enough); ToPBR stays,
publishes past such mods and its page says what it does beside Imported game PBR; the automatic categorization is
bounded, obeys its switches and keeps the player's `rtx.conf` choices: [issue6-topbr-report.md](issue6-topbr-report.md),
by Claude, package only, on the branch `qol-topbr`, merged into `main` with the round (`qol-1114`) without an in-game check, on the user's "Commit and push"
([ADR 0212](../decisions/0212-topbr-kept-and-publishes-past-unreadable-mods.md),
[ADR 0213](../decisions/0213-automatic-categorization-hardened.md)).
Then the user's request of 2026-11-14 for a main-menu note on demo PBR resources (Workshop collection 3834474695)
and what a map without PBR looks like: by Claude on the branch `qol-menu`, merged into `main` with the round (`qol-1114`) without an in-game check, on the user's "Commit and push" ([ADR
0217](../decisions/0217-a-main-menu-note-on-pbr-for-maps.md); no report of its own: the decision record and
[pbr_note.lua.md](../../companion/nativeloader/lua/nativeloader/menu/pbr_note.lua.md) hold it).
Then the user's QoL request of 2026-11-14 (a long silent wait between "Ready to play!" and a playable map; an estimate
of a load's length learned from the loads before): [load-eta-report.md](load-eta-report.md), by Claude, package only,
on the branch `qol-load`, merged into `main` with the round (`qol-1114`) without an in-game check, on the user's "Commit and push"
([ADR 0214](../decisions/0214-after-ready-to-play-the-overlay-stays-until-the-game-runs.md),
[ADR 0215](../decisions/0215-the-loads-estimate-learned-from-the-loads-before.md)).
Then the user's requests of 2026-11-14 after that round ("Update the standard, from now on the changelog should also be posted fully to the Steam workshop update log"; noclipping players moving broken glass; the crosshair under frame generation): [glass-crosshair-report.md](glass-crosshair-report.md) (runtime patch 0094, [ADR 0222](../decisions/0222-the-workshop-change-notes-carry-the-changelog.md), [ADR 0223](../decisions/0223-frame-generation-gets-the-frame-before-its-ui.md)).
Then the user's report of 2026-11-14 on the bundled Advanced MMD Animation Player ("very laggy ... the selection, assignment, action like assigning an animation to an NPC always result in a few seconds of hangs", with three requests: keep the flexes a motion does not animate, a long slider in the debug window, ragdoll collision for dancing NPCs): reproduced and timed in the PoC with the user's motion library, fixed (a click asks for its built flags, not every motion's details) and the options checked in the game: [mmd-player-report.md](mmd-player-report.md), by Claude, package only, on the branch `mmd-player-perf` ([ADR 0224](../decisions/0224-the-animation-player-answers-a-click-with-its-built-flags.md)).
Then GitHub issue 3 ("Command poster is disabled for Remix compatibility"; the user: "The command poster allow user to render a screenshot at a resolution higher than their current resolution"): the runtime renders the poster in tiles of the window's size and the engine guard takes the command: [issue3-poster-report.md](issue3-poster-report.md), by Claude, runtime patch 0095, on the branch `issue3-poster` ([ADR 0226](../decisions/0226-the-poster-command-rendered-in-tiles-by-the-runtime.md)).
Then the user's report of 2026-11-15, "the remix Alt+X menu can not be opened in field game and other users ... Alt+X will disable control to the game, but the remix menu is not drawn": with frame generation on, the menu and the HUD were drawn into the HUD-less copy patch 0094 blits last: [altx-menu-report.md](altx-menu-report.md), by Claude, runtime patch 0096, on the branch `altx-menu`.
Then GitHub issue 12, a Radeon RX 9060 XT crashing with 0xC0000005 at the main menu and in maps: `LockImage` resolved every single-sample read-back into itself under MSVC: [issue12-amd-resolve-report.md](issue12-amd-resolve-report.md), by Claude, runtime patch 0097, on the branch `issue12-lockimage`.
Then, found while investigating the field's crashes at a level change (the brief of 2026-11-15): the About tab read the asset replacer's secret replacements while DXVK's command thread rebuilt them, a crash soon after a start or at a level change in a start that had just deployed a new map pack: [secrets-race-report.md](secrets-race-report.md), by Claude, runtime patch 0098, on the branch `secrets-race-0098`.
Then the user's request of 2026-11-15 ("make skybox enhancement, add a sky editor in the tab to allow user to customize how each element in the night sky looks (allow changing brightness of stellar elements). Note if the night sky is a whole picture, don't proceed and report honestly"): the night sky is not one picture, but its constellations were baked into the nebula; each layer now has a brightness and a colour, the constellations a layer of their own, and the companion a Night sky editor page: [night-sky-editor-report.md](night-sky-editor-report.md), by Claude, runtime patch 0099, on the branch `night-sky-editor` ([ADR 0227](../decisions/0227-the-night-sky-editor.md)).
Then the user's go-ahead of 2026-11-15 ("Yes, please translate them") to translate the Remix menu's 98 texts the upstream merge brought, found behind while building patch 0099: [remix-menu-i18n-report.md](remix-menu-i18n-report.md), by Claude, runtime patch 0100, on the branch `remix-menu-i18n`.
Then the user's report of 2026-11-16 (a black region on an imported character's skirt under RTX, "hypothesis is due to clipping", and whether a general fix can be applied): [backface-twins-report.md](backface-twins-report.md), by Claude, the Model Hotloader's natives rebuilt (back-face copies deform with the layer facing outside, ADR 0228), on the branch `backface-twins`.
Then the user's QoL requests of 2026-11-16 (ToPBR on the map's own surfaces by default with a range to choose, marked experimental; a three-second hold before a dance returns to the reference pose; an option for how hard a dancing NPC pushes props): [qol-2026-11-16-report.md](qol-2026-11-16-report.md), by Claude, the fixes' fourteenth native patch and package changes, on the branch `qol-topbr-scope-dance` ([ADR 0229](../decisions/0229-topbr-takes-the-maps-own-surfaces-unless-the-player-widens-it.md), [ADR 0230](../decisions/0230-a-dance-holds-its-last-pose-and-its-bodies-weigh-its-ragdoll.md)).
Then the user's request of 2026-11-16 to ship Linlong's RTX package with the main package: [linlong-pbr-report.md](linlong-pbr-report.md), by Claude, package only, on the branch `linlong-pbr` ([ADR 0231](../decisions/0231-linlongs-rtx-pbr-ships-with-the-model-hotloader.md)).
Then the user's request of 2026-11-16 for a mesh separator (a piece of a vanilla or imported model spawned as a prop with generated physics; the design made with the user through three rounds of questions): [mesh-separator-report.md](mesh-separator-report.md) with its [plan](mesh-separator-plan.md), by Claude, the Model Hotloader's natives and Lua, on the branch `mesh-separator` ([ADR 0232](../decisions/0232-the-mesh-separator.md)); its last section, the selection in the editor only, on `separator-overlay` ([ADR 0233](../decisions/0233-the-mesh-separator-selects-in-its-editor.md)).

Then the user's report of 2026-11-16 on Imported game PBR (a blank list, no word of a character's Remix mod) and the animation player's music (back with an NPC spawned later): [pbr-page-dance-music-report.md](pbr-page-dance-music-report.md), by Claude, package only (the fixes' and the motion importer's Lua), on the branch `pbr-panel-dance-music`.
Then the repository review of 2026-11-16 (30 findings; "The user approved the fixes for the reported list"): [review-fixes-report.md](review-fixes-report.md), by Claude with five subagents, package only (runtime patches 0101-0104, the fixes' fifteenth patch, the Model Hotloader's natives and Lua, the VR module, the engine guard, the fixes' Lua, the material editor, the publisher), on the branch `review-lua-tools` ([ADR 0234](../decisions/0234-what-a-server-a-workshop-item-and-lua-may-reach.md)).
Then the user's request of 2026-11-16 for an uninstallation pop-up (a player who deleted `winmm.dll` and unsubscribed at the same time): [leftovers-popup-report.md](leftovers-popup-report.md), by Claude, package only (the companion's Lua and translations), on the branch `leftovers-popup` ([ADR 0235](../decisions/0235-a-window-when-rtx-is-left-without-its-loader.md)).
Then the user's report of 2026-11-16 on Linlong's RTX PBR (her hair's colour not uniform, the effect too weak): [linlong-pbr-tune-report.md](linlong-pbr-tune-report.md), by Claude, package only (the Model Hotloader part's `mods/mmdhl_pbr_linlong`) and the `mmd-remix-pbr` skill, on the branch `linlong-pbr-tune` ([ADR 0236](../decisions/0236-linlongs-pbr-an-evened-hair-texture-and-stronger-maps.md)).
Then developer debug views from Lua (found in that work: the debug module's `SetDebugView` went through `RemixConfig`'s list since ADR 0234): [debug-views-report.md](debug-views-report.md), by Claude, package only (the debug module 0.2.2, its source patch 0004), on the branch `claude/suspicious-jennings-845d66` ([ADR 0237](../decisions/0237-developers-set-remix-options-through-the-debug-modules-developer-gate.md)).
Then the user's request of 2026-11-16 for a second load speed-up round ("the game usually takes 2-3 minutes to load, if this can be further decreased, we can save a lot of time for the user"), investigated first (the plan with its measurements in the main checkout's `out/load-speedup-2/PLAN.md`), then the four items the user chose ("H1, A2, H2, H3"): [load-speedup-2-report.md](load-speedup-2-report.md), by Claude, package only (the Model Hotloader's Lua, the load accelerator's module and add-on, the companion's menu line), on the branch `load-speedup-2` ([ADR 0238](../decisions/0238-the-hotloaders-map-start-work-once-and-after-the-map-runs.md), [ADR 0239](../decisions/0239-the-load-accelerator-caches-links-junctions-and-character-packs.md)).
Then the user's request of 2026-11-17 for the second plan's remaining items ("Let's also do the remaining 6 points in the plan. Every second matters"; the loader items then rejected): [load-speedup-3-report.md](load-speedup-3-report.md), by Claude, package only (the load accelerator's module and add-on, the companion's load overlay), on the branch `load-speedup-3` ([ADR 0240](../decisions/0240-arc9s-attachment-icons-decoded-when-first-drawn.md), [ADR 0241](../decisions/0241-the-load-overlay-names-the-slowest-lua-callbacks.md), [ADR 0242](../decisions/0242-what-a-load-reads-read-ahead-for-the-next.md)); S1 in `remix-workers-report.md` on its own branch, `remix-workers`.
Then the user's request of 2026-11-17 ("Make invisible models have no collision": other add-ons' invisible entities in imported characters' hair and clothing physics; Enhanced Death Animations the example): the scene capture leaves out what nobody can see: [invisible-colliders-report.md](invisible-colliders-report.md), by Claude, package only (the Model Hotloader's `secondary_collision.lua`, one line of the VR add-on), on the branch `invisible-colliders` ([ADR 0245](../decisions/0245-mmd-hair-and-clothing-leave-out-what-nobody-sees.md)).
Then the user's request of 2026-11-18 (servers that refuse `render.GetDXLevel()` below 90 refused RTX players; "As per our plan", their R24 item 1.1): in multiplayer games the RTX package answers the DirectX level the game was started at, set up before any server's Lua: [multiplayer-dxlevel-report.md](multiplayer-dxlevel-report.md), by Claude, package only (the companion's prelude script and render guard, the RTX client module's prelude hook), on the branch `multiplayer-dxlevel` ([ADR 0246](../decisions/0246-the-directx-level-servers-see.md)).
Then the user's report of 2026-11-19 (the game crashed when they typed `disconnect` to go back to the main menu; the seventh field crash of its kind) and their choice of the guard: before the game leaves threaded rendering, the engine guard drops queued render calls whose object is gone and logs them: [render-queue-check-report.md](render-queue-check-report.md), by Claude, package only (the engine guard), on the branch `render-queue-check` ([ADR 0247](../decisions/0247-queued-render-calls-checked-before-the-game-leaves-threaded-rendering.md)).
Then the user's request of 2026-11-20 ("replace other map's skybox to our own RTX skybox by default, but we also allow user to switch back to the map (3D) skybox if applicable. Display a chat message about this when map join"; the gm_stelliferous confusion; a map's own sky above the RTX sky) and their three answers: the RTX sky by default, the map's own sky with its 3D skybox per map, a map's RTX version's sky (its add-on's or a sky file's) above the RTX sky, one chat line at each map's start: [map-sky-report.md](map-sky-report.md), by Claude, package only (the companion), on the branch `map-sky` ([ADR 0249](../decisions/0249-which-sky-a-map-shows.md)).
Then the user's request of 2026-11-21 ("In the advanced mmd player, camera section, add a convenience function, default on, when in camera motion, hide the player in the world"): the Camera tab's "Hide yourself during camera motion", your body, what you hold and wear, the RTX fixes' body and weapon copies and your RTX flashlight's light left out of the shot while each camera frame draws, on your screen only: [mmd-camera-hide-report.md](mmd-camera-hide-report.md), by Claude, package only (the character motion importer, one hook in the fixes' flashlight), on the branch `mmd-camera-hide-player` ([ADR 0250](../decisions/0250-hide-yourself-during-camera-motion.md)).
Then the user's "Do this task here" of 2026-11-21 for the camera runs' two findings: the RTX fixes' weapon copy no longer draws the held weapon before the frame (with it, third-person views lost their path tracing), and the Model Hotloader's scene capture handles entities without a model scale; then the weapon copy draws only with its private textures, so nothing of you shows in your own first-person view: [shadow-copies-report.md](shadow-copies-report.md), by Claude, package only (one file of the fixes, one of the Model Hotloader), on the branch `local-shadow-fixes` ([ADR 0251](../decisions/0251-the-weapon-copy-draws-nothing-before-the-frame.md), [ADR 0252](../decisions/0252-the-weapon-copy-draws-only-with-its-private-textures.md)).
Then the user's report of 2026-11-21 ("Disconnecting from a map / server still causes fast termination crash, when a session is long / with lots of things spawned"): the check of 2026-11-19 had run and passed every call, and the 660th queued call was written over while the game ran the calls before it; the engine guard now also watches that run, puts written-over calls back, skips changed ones and logs what ran before: [render-run-check-report.md](render-run-check-report.md), by Claude, package only (the engine guard), on the branch `render-run-check` ([ADR 0254](../decisions/0254-queued-render-calls-checked-again-while-the-game-runs-them.md)).
Then the user's report of 2026-11-21 ("the game is laggy for each item" after a fresh subscription to a content pack; "optimize this lag and the speed of installation"): the Model Hotloader installs a pack's models several at once, its asset checks side by side below normal priority, and adds installed models to the library without rebuilding it for each; package only, the Hotloader's natives rebuilt: [pack-install-report.md](pack-install-report.md) ([ADR 0255](../decisions/0255-workshop-models-install-several-at-once.md)).
Then a Workshop report of 2026-11-21 ("What is the "default texture pack is not ready" thing in the middle of my screen?"; another player found DLib, Workshop 1153306104, caused it) and the user's "Please investigate what is the problem and address it": DLib replaces the game's hook library when it loads, after the early render guard, which lost its whole hook layer (MineMod's line of GitHub issue 5 came back); the guard now takes its place inside DLib's own `hook.Reconstruct` and `hook.Call2`: [dlib-hooks-report.md](dlib-hooks-report.md), by Claude, package only (the render guard), on the branch `dlib-hooks` ([ADR 0256](../decisions/0256-the-guard-inside-dlibs-hook-library.md)).
Then the follow-up the DLib check named (2026-11-21): ULib (ULX's library, Workshop 557962238) writes its own hook library over the render guard's `hook.Call` and `hook.Add` from its client autorun, which took the guard's hook layer away in every game with ULib as DLib's takeover did; the guard now works inside ULib's records, watching its priority lists, with its own depth pass and frame hooks at ULib's priorities, and the lag report times what a ULib record holds: [ulib-hooks-report.md](ulib-hooks-report.md), by Claude, package only (the render guard and the lag report), on the branch `ulib-hooks`, built on `dlib-hooks` ([ADR 0257](../decisions/0257-the-guard-inside-ulibs-hook-library.md)).
Then the follow-up the content packs' install report left (with the spawn menu open, each library update of a pack's install still rebuilt the library window's whole list): the window brings the rows of the characters `library.Add` listed up to date alone, new ones and ones a package takes over, as a rebuild would show them; package only, on top of ADR 0255's uncommitted state: [library-rows-report.md](library-rows-report.md) ([ADR 0258](../decisions/0258-the-library-window-adds-rows-for-new-characters.md)).
Then the user's request of 2026-11-22 ("Update the animation player to improve the experience on imported models. Currently, the imported models' animation needs constantly rebuilt between game sessions."): the Advanced MMD Animation Player names a Model Hotloader carrier's builds after the build model of its skeleton, so a character resized, imported again or updated finds the motions built before, in the same session and the next; expression mappings follow; earlier builds adopted once; by Claude, package only, on the branch `mmd-built-keys`: [mmd-shared-builds-report.md](mmd-shared-builds-report.md) ([ADR 0259](../decisions/0259-imported-characters-share-their-builds-across-carriers.md)).
Then the user's request of 2026-11-22 ("during installation, when the payload is being unpacked, there might be risk that the user's disk is nearly full and a full disk will cause a failure. Without modifying the loader, try to handle this situation"): the loader already refuses before it unpacks and keeps the installed versions; the companion's menu now says so with the numbers, and warns before an update would not fit, from the RTX client module's new `disk_space()`; by Claude, package only, on the branch `disk-space-notice`: [disk-space-report.md](disk-space-report.md) ([ADR 0260](../decisions/0260-the-package-says-when-the-disk-is-too-full-for-updates.md)).
Then the user's report of 2026-11-23 ("The game still face a fast termination crash after some playing on disconnect"): three more field crashes after ADR 0254; the queued call was intact and its target gone, a material-variable setter whose variable the RTX fixes' map-exit cleanup had destroyed with `UncacheAllMaterials`; the engine guard runs the main thread's queued calls through the queued context's own flush before the cleanup, skips calls on a material variable that is gone, and logs as events happen; investigated, reproduced and validated by Claude, implemented and reviewed by Opus 5.5 subagents, package only, merged to `main`: [disconnect-uncache-report.md](disconnect-uncache-report.md) ([ADR 0261](../decisions/0261-queued-render-calls-run-before-the-map-exit-cleanup.md)).
Then the user's "Yes, fix it" of 2026-11-23 for the same fault in the `rtx_flush_textures` console command: the RTX fixes' texture cleanup, also reached by the console command and by the Lua global `RTX_CleanupMapTextures`, let the render thread run setters queued before its uncache on destroyed variables in the middle of a game (PoC: exit 0xC0000005); the fixes' sixteenth native patch `cleanup-drain` has the cleanup ask the engine guard's exported flush itself, whoever calls it, and skip the purge when nobody can make sure; the hook calls the cleanup alone again; reproduced and validated by Claude, implemented and reviewed by Opus 5.5 subagents, package only, merged to `main`: [cleanup-drain-report.md](cleanup-drain-report.md) ([ADR 0262](../decisions/0262-the-texture-cleanup-runs-the-queued-render-calls-itself.md)).
Then the user's report and request of 2026-11-24 ("When I forgot to put PBR into the folder of a pmx, and I reimported it in the same session, PBR are not applied." and "allow user to hide all the debug menu (motion and camera) but keep in debug mode, so user can take screenshot or move"): an unchanged PMX imported again keeps its asset id and the RTX fixes kept the first "no maps" answer for the session; a finished import or Reload now has the fixes submit the character's materials again and the module forget that model's folder scans and texture answers (the fixes' seventeenth native patch `game-rescan`); and the MMD animation player's Hide windows keeps debug mode; reproduced and validated by Claude, the native patch by an Opus 5.5 subagent, package only, merged to `main`: [reimport-pbr-debug-windows-report.md](reimport-pbr-debug-windows-report.md) ([ADR 0263](../decisions/0263-a-re-import-looks-at-the-models-folder-again.md), [ADR 0264](../decisions/0264-hide-the-debug-windows-and-stay-in-debug-mode.md)).
Then the user's request of 2026-11-24 ("Investigate and Address https://github.com/SheepyLord/Gmod-Workshop-RTX-Remix/issues/14 if this is a problem" and "The most recent dxvk carries a few useful fixes. Please up our package's remix version and test carefully."): GitHub issue 14 not reproduced (a mod in its format applies with ToPBR off and on; a reply on the issue asks for the reporter's Remix log), and NVIDIA's dxvk-remix `main` of 2026-11-23 merged as runtime patch 0106 (Remix API 0.1000.3), with a crash the PoC found in the first build fixed in the patch, tested in the PoC: [upstream-1123-report.md](upstream-1123-report.md), by Claude, package only, on the branch `upstream-1123` ([ADR 0265](../decisions/0265-the-runtime-merges-upstream-main-of-2026-11-23.md)).
Then the open item of that testing (2026-11-24): release QA's `map-glass` and `spawned-glass` failed with every package because their probes counted the entities of Glass-Rewrite-Remix, which G1 replaced on 2026-11-01, while the glass broke; the probes now count what the player sees of G1 and both sessions pass on the PoC and in the field: [release-qa-glass-report.md](release-qa-glass-report.md), by Claude, tools only.
Then the user's report of 2026-11-25 ("the ragdoll's mmd physics, when spawn or reset, started up at an unexpected position far away from the model"): PMX rigid bodies without a bone (skirt lattices, chest helpers) started at the map's origin at every reset and their joints dragged the skirt across the map; each now rides with the bone of the nearest boned body through its joints: [boneless-bodies-report.md](boneless-bodies-report.md), by Claude, the Model Hotloader's natives, package only ([ADR 0266](../decisions/0266-a-body-without-a-bone-starts-with-the-character.md)).
Then the plan's item S1 (the user's request of 2026-11-17 to do the plan's remaining items): Remix's geometry workers sleep when idle instead of keeping two cores busy: [remix-workers-report.md](remix-workers-report.md), by Claude, runtime patch 0105 (fork branch `claude/remix-workers`), on the branch `remix-workers` ([ADR 0243](../decisions/0243-the-geometry-workers-sleep-when-idle.md)).
Then the user's request of 2026-11-14 after the runtime update ("Fix issue #1", and the PBR note: one line, Hide, hidden after ten seconds, a button to hide it forever): Source eyes show their irises (Remix's eye shading on, the fixes' thirteenth patch keeping the eye's TexGen to its draw) and the note as asked, checked in the PoC: [issue1-eyes-report.md](issue1-eyes-report.md), by Claude, package only, on the branch `issue1-pbr-note` ([ADR 0219](../decisions/0219-the-pbr-note-one-line-three-buttons-ten-seconds.md), [ADR 0220](../decisions/0220-source-eyes-show-their-irises.md)).
Then the user's request of 2026-11-14 ("Make the dxvk-remix up-to-date from upstream. Test in game and post to github and workshop."): NVIDIA's dxvk-remix `main` merged as runtime patch 0093, with the fork's API line kept compatible, tested in the PoC: [upstream-runtime-report.md](upstream-runtime-report.md), by Claude, package only, on the branch `upstream-1114` ([ADR 0218](../decisions/0218-the-runtime-follows-upstream-dxvk-remix-main.md)).
Then the user's request of 2026-11-14 ("Enhance the skybox about the moon, the moon should be visible during the day
given correct moon phase"): the moon by day, as bright as the real one at its phase, runtime patch 0090 and the
companion's Moon by day slider: [moon-by-day-report.md](moon-by-day-report.md), by Claude, package only, on the branch
`qol-moon`, merged into `main` with the round (`qol-1114`) without an in-game check, on the user's "Commit and push" ([ADR 0207](../decisions/0207-the-moon-by-day.md)).

On the same branch, the user's request of 2026-11-14 to trace "0xC0000005", the crash most players report: the
investigation's clusters and the runtime's fixes, upstream dxvk-remix `c1a891bf85` ported (patch 0091) and no sent
message handled inside Present (patch 0092): [crash-0xc0000005-report.md](crash-0xc0000005-report.md), by Claude,
package only, merged into `main` with the round (`qol-1114`) without an in-game check, on the user's "Commit and push"
([ADR 0216](../decisions/0216-the-runtimes-pipeline-handle-race-and-in-present-message-dispatch-fixed.md)).

Beside it, the user's report of 2026-11-10 on the Model Hotloader's imports (a static prop's slow physics, no
percentage, a crash once the importer showed a new import): [hotloader-import-report.md](hotloader-import-report.md),
by Claude (no Codex). Its follow-up, the fixes part's Seamless Portals off the same crash path:
[portals-render-mesh-report.md](portals-render-mesh-report.md).

Before it, R27, the user's report of 2026-11-09 (HUD add-ons that turned the screen white under RTX:
HUD Mk.2's "depth-only" colour target and the render guard's refused bindings): [R27-report.md](R27-report.md),
done by Claude with a Claude subagent for the review (no Codex).

Before it, R26, the user's request of 2026-11-09 (the sky without a horizon, for universe and
floating-island maps; faster map loads with hundreds of add-ons, the load accelerator, in RTX starts):
[R26-report.md](R26-report.md), done by Claude with Claude subagents for the sky option and the review (no
Codex).

Beside it, a diagnosis of GitHub issue #2 (lag, high RAM use, a game that lingers after a crash) with a player's 654
Workshop add-ons: [issue-2-memory-report.md](issue-2-memory-report.md), by Claude; R28 made its fixes 1 to 4 and 7,
and says what is left of 5 and 6.

Before it, R25, the user's report of 2026-11-09 (a spawn-menu icon left on the screen by a drag GMod
never ended; ARC9's magnified scopes path traced through a raytraced render target; ARC9's gun path traced, its
screen reads and 2D before the view model skipped): [R25-report.md](R25-report.md), done by Claude with Claude
subagents for two reviews (no Codex).

Before it, R24, the user's follow-up of 2026-11-08 (the multiplayer notice as Lua in the add-on;
ARC9 view models' stickers, gun screens and DirectX warning; view model materials through the pipeline; what a
map load is doing, in an overlay; load time measured): [R24-report.md](R24-report.md), done by Claude with one
Claude subagent for the review (no Codex).

Before it, R23, the user's report of 2026-11-08 (an engine guard and start-up watchdog for
"Starting Lua" hangs, ARC9 under RTX; Wuthering Waves game maps; a PBR progress notice; the material
editor's tabs; the skills; the multiplayer notice on a loader branch awaiting approval):
[R23-report.md](R23-report.md), done by Claude with one Claude subagent (no Codex).

Before it, R22, the user's item 52 (a loading window while the first start unpacks the
package, loader 0.16.0; the frame generation hint also at the top right): [R22-report.md](R22-report.md),
done by Claude alone at the user's request (no Codex).

Before it, R21, the user's two requests after R20's release (Blood Overhaul's resources by
permission; no Hotloader warning after game updates): [R21-report.md](R21-report.md), with its
[plan](R21-plan.md) and the task reports ([A](R21-A-report.md), [B](R21-B-report.md)), then the 4K GPU
timeout during a map load, closed as not reproducible ([R21-C](R21-C-report.md)).

Before it, R20, the user's report of 2026-11-06 (items 44-51), loader 0.15.0:
[R20-report.md](R20-report.md), with its [plan](R20-plan.md) and the task reports
([A](R20-A-report.md), [B](R20-B-report.md), [C](R20-C-report.md), [D](R20-D-report.md),
[E](R20-E-report.md), [Q](R20-Q-report.md)), then the field check of the published package
([R20-F](R20-F-report.md)) and the fix it led to, the toolgun display at night ([R20-T](R20-T-report.md)).

R20-T diagnoses the night field finding and fixes the toolgun's HUD material depth state:
[brief](R20-T-toolgun-night.md), [report](R20-T-report.md), branch `r20-toolgun`. The report keeps
the 4K before/after views, older-runtime comparison, native RTX-off cases and preservation receipts.

Before it, R19: the pre-release review's findings fixed and release v0.14.0: [R19-report.md](R19-report.md), with its [plan](R19-plan.md) and the [verified review](R19-review.md); before it R18, R17's sky limits addressed (thin decks that close, a middle deck with its own patches, sun dogs and the other ice halos, a milky haze, a longer twilight): [R18-report.md](R18-report.md); before it R17, a sky that fits the weather (cloud genera for each weather, a sun disc, a high cloud layer) and the package workflow started by hand: [R17-report.md](R17-report.md); before it R16, the sky at a map's start and the RTX package built on GitHub with every native binary and a hash report: [R16-report.md](R16-report.md); and R15, imported characters' painted shadows and solid hair, then the loader's release candidate: [R15-report.md](R15-report.md).

The latest QoL batch fixes [player bodies, arms and shadows](../decisions/0043-player-body-viewmodel-and-shadows.md).
The previous batch adds legacy Remix migration in loader 0.8.0. GarrysMod_RTX_c now runs our implementation and is no longer the classic baseline.

When a milestone moves to another agent (or person), the giver writes a **brief** here and the
receiver writes a **report** here when done or blocked. Both are committed on the milestone branch,
so the next agent has the full story without the chat transcripts.

R20-B handover: [R20-B-report.md](R20-B-report.md), including the sky migration, startup hint consumer,
and the native live-readback requirement that remains open.

| Milestone | Brief | Prompt | Report | Assignee | Branch / worktree |
|---|---|---|---|---|---|
| M1 inert bootstrap | [M1-handover.md](M1-handover.md) | [M1-codex-prompt.md](M1-codex-prompt.md) | [M1-report.md](M1-report.md), [review](M1-review.md) | Codex | `m1-bootstrap` in `H:\BACKUP_20260815\Modding\!NVIDIA-RTX-Remix\out\worktrees\m1-bootstrap` (user-selected output root); merged into `main` 2026-10-27 |
| M2 core + CLI | (none: Claude, who wrote the plan) | | (none: evidence in the [roadmap](../ROADMAP.md) M2 row) | Claude | `m2-core` in the main checkout; merged into `main` 2026-10-27 |
| M3 deployer | (none: Claude; design in [ADR 0007](../decisions/0007-transactional-deployment.md)) | | (none: evidence in the [roadmap](../ROADMAP.md) M3 row) | Claude | `m3-deployer` in the main checkout; merged into `main` 2026-10-27 |
| M4 activation | [M4-handover.md](M4-handover.md) | [M4-codex-prompt.md](M4-codex-prompt.md) | [M4-report.md](M4-report.md), [review](M4-review.md) | Codex; parts 1-2 and review fixes by Claude | `m4-activation` in the main checkout; merged into `main` 2026-10-28 |
| M5 RTX fixes | [M5-plan.md](M5-plan.md) (no handover: Claude planned and built it) | | [M5-report.md](M5-report.md) | Claude | `m5-rtx-fixes` in the main checkout; merged into `main` 2026-10-28 with M6 |
| M6 Workshop route | (in the roadmap row; Claude) | | [M6-report.md](M6-report.md) | Claude | committed with M5 on `m5-rtx-fixes` (shared files); merged into `main` 2026-10-28 |
| M7 field install | [M7-plan.md](M7-plan.md) | | [M7-report.md](M7-report.md) | Claude | `m7-field` in the main checkout; merged into `main` 2026-10-28 |
| R3 whole-repo review: robustness, stability, bugs | [R3-handover.md](R3-handover.md) | [R3-codex-prompt.md](R3-codex-prompt.md) | [R3-report.md](R3-report.md) (Codex), [triage](R3-triage.md) (Claude) | Codex; triage and fixes by Claude | report on `r3-review` in `H:\BACKUP_20260815\Modding\!NVIDIA-RTX-Remix\out\worktrees\r3-review`; fixes on `r3-fixes` in `out\worktrees\r3-fixes`, from the report; merged into `main` 2026-10-29 |
| QoL updates (from 2026-10-29) | [QoL-handover.md](QoL-handover.md): state, features, limitations, standard, test protocol, pitfalls | (the user's requests) | [QoL-report.md](QoL-report.md) | Codex Astra | one branch and worktree per change under `out\worktrees`, from `main` at the brief's commit |
| R4 review and field QA of the QoL batch | (the user's request, 2026-10-31) | | [R4-review.md](R4-review.md): findings, the user's four reports, field QA, the release run | Claude (lead), seven read-only reviewers and six fix branches | `r4-review-qa` in `out\worktrees\r4`, merged from `r4-legacy`, `r4-startup`, `r4-rtxdebug`, `r4-runtime`, `r4-companion`, `r4-motion`; merged into `main` 2026-10-31 (loader 0.10.1) |
| R5 QoL round | (the user's report, 2026-10-31) | | [R5-qol.md](R5-qol.md): the night sky line, loose broken glass, Workshop packs over own imports, the RTX normals checkbox, the content pack checks, the stability proposal | Claude (lead), a glass agent and stability researchers | `r5-qol` in `out\worktrees\r5`, with `r5-glass` merged |
| R6 performance and stability | [R6-plan.md](R6-plan.md) | six briefs: [T1](R6-T1-loader-layers.md), [T2](R6-T2-evidence-telemetry.md), [T3](R6-T3-companion-docs.md), [T4](R6-T4-runtime-logs.md), [T5](R6-T5-fixes-memlimits.md), [T6](R6-T6-performance-tiers.md) | [R6-report.md](R6-report.md): what was built, the reviews, PoC QA and tier measurements, open issues | Codex (gpt-6.1-sol) through the Claude Code plugin; Claude as project manager | `r6-t1-layers` ... `r6-t6-tiers` in `out/worktrees/` |
| C-16 steady eye-white brightness | [C16-plan.md](C16-plan.md) | two briefs: [C16-A runtime](C16-A-runtime.md), [C16-B content](C16-B-content.md) | [C16-report.md](C16-report.md): what was built, the review, the PoC measurements and tuning, the packs, open issues | Codex (gpt-6.1-sol); Claude as project manager | `c16-runtime`, `c16-content` in `out/worktrees`, integrated on `c16-int` |
| G1 glass overhaul | [G1-plan.md](G1-plan.md) | two briefs: [G1-A Lua](G1-A-lua.md), [G1-B native](G1-B-native.md); fix passes [1](G1-fix-pass.md), [2](G1-fix-pass-2.md) | [G1-report.md](G1-report.md): what was built, the integration findings and fixes, the PoC measurements (old and new system), open issues | Codex (gpt-6.1-sol); Claude as project manager | `g1-lua`, `g1-native` and their fix branches in `out/worktrees`, integrated on `g1-int` |
| R7 the user's report of 2026-11-01 | [R7-plan.md](R7-plan.md) | three briefs: [R7-A MMD alpha under Remix](R7-A-mmd-alpha.md) (after Claude's investigation), [R7-B crash report and diagnostics](R7-B-crash-diagnostics.md), [R7-C glass interaction](R7-C-glass-interaction.md) | [R7-report.md](R7-report.md) (with [R7-A](R7-A-report.md), [R7-B](R7-B-report.md), [R7-C](R7-C-report.md)) | Codex (gpt-6.1-sol); Claude as project manager | `r7-crash-diag`, `r7-glass-interact` in `out/worktrees`, integrated on `r7-int` |
| R11 automatic PBR (2026-11-02) | [R11-plan.md](R11-plan.md) | one brief: [R11-A automatic PBR for vanilla Source materials and imported game characters](R11-A-autopbr.md) | [R11-report.md](R11-report.md) (with [R11-A](R11-A-report.md)) | Codex (gpt-6.1-sol); Claude as project manager | `r11-autopbr` in `out/worktrees`, with the fixes branch `codex/r11-autopbr` in `out/worktrees/r11-fixes` |
| R12 the user's report after R11-B (2026-11-02) | [R12-plan.md](R12-plan.md) | four briefs: [R12-A NPCs after a re-import](R12-A-hotloader-npc.md), [R12-B game PBR by texture features and manual overrides](R12-B-game-pbr-matching.md), [R12-C VRAM](R12-C-vram.md), [R12-D manual eye whites](R12-D-eye-white-assignment.md); a follow-up after review: [R12-B2 straight-alpha decoding and mask evidence](R12-B2-decode-and-masks.md) | [R12-report.md](R12-report.md) (with [R12-A](R12-A-report.md), [R12-B and B2](R12-B-report.md), [R12-C](R12-C-report.md), [R12-D](R12-D-report.md)) | Codex (gpt-6.1-sol); Claude as project manager | `r12-hotloader`, `r12-pbr` (fixes `codex/r12-pbr` in `out/worktrees/r12-fixes`), `r12-vram`, `r12-eyes` in `out/worktrees`, integrated on `r12-int` |
| R14 noclip and glass, the guide (2026-11-03) | [R14-plan.md](R14-plan.md) | one brief: [R14-H the guide and the help wording](R14-H-guide.md) | [R14-report.md](R14-report.md) (with [R14-H](R14-H-report.md)) | Claude (scheduled task r14-after-r13), then the main session: R14-G by Claude, R14-H by a Claude subagent, R14-T (text check and translations) by Codex | `r14` in `out/worktrees/r14`; then `r14-guide`, integrated on `r14-int` |
| R15 painted shadows, solid hair, the release candidate (2026-11-04) | [R15-plan.md](R15-plan.md) | none | [R15-report.md](R15-report.md) | Claude in the main session; Codex translated | `r15` in `out/worktrees/r15` |
| R16 the sky at a map's start, the RTX package built on GitHub (2026-11-04) | [R16-plan.md](R16-plan.md) | none | [R16-report.md](R16-report.md) | Claude in the main session; Codex translated | `r16` in `out/worktrees/r16` |
| R17 a sky that fits the weather, the package workflow by hand (2026-11-05) | none (the request is quoted in the report) | none | [R17-report.md](R17-report.md) | Claude in the main session and a Claude research subagent; Codex translated | `r17` in `out/worktrees/r17` |
| R19 the pre-release review's findings fixed, release v0.14.0 (2026-11-05) | [R19-plan.md](R19-plan.md), from the [verified review](R19-review.md) | seven part briefs in the plan | [R19-report.md](R19-report.md) (with [R19-L](R19-L-report.md), [R19-R](R19-R-report.md), [R19-X](R19-X-report.md), [R19-E](R19-E-report.md), [R19-H](R19-H-report.md), [R19-G](R19-G-report.md), [R19-T](R19-T-report.md)) | Claude subagents; Claude as project manager; Codex reviewed (the user's request) | `r19-loader`, `r19-runtime`, `r19-fixes`, `r19-editors`, `r19-hotloader`, `r19-glass`, `r19-tooling` in `out/worktrees`, integrated on `r19-int` (runtime `claude/r19-review-fixes` in `out/worktrees/r17/out/runtime-src`) |
| R20 the user's report of 2026-11-06 (items 44-51) | [R20-plan.md](R20-plan.md) | four briefs: [R20-A the loader update reminder and the multiplayer warning](R20-A-loader-menu.md), [R20-B the upscaling hint and the sky's new defaults](R20-B-companion-qol.md), [R20-C Dynamic Toolgun Screen and Blood Overhaul RTX, realistic blood impacts](R20-C-blood-and-toolgun.md), [R20-D particle and decal add-ons under RTX, the dupe icon](R20-D-render-compat.md); added during the round: [R20-E a live upscaling readback](R20-E-upscaling-readback.md), [R20-Q integration QA](R20-Q-integration-qa.md) | [R20-report.md](R20-report.md) (with [A](R20-A-report.md), [B](R20-B-report.md), [C](R20-C-report.md), [D](R20-D-report.md), [E](R20-E-report.md), [Q](R20-Q-report.md)) | Codex (gpt-6.1-sol, effort max, priority tier); Claude as project manager | `r20-menu`, `r20-qol`, `r20-blood`, `r20-render`, `r20-native`, `r20-qa` in `out/worktrees`, integrated on `r20-int` in `out/worktrees/r20` (runtime `claude/r20-int` in `out/worktrees/r17/out/runtime-src`) |
| R18 R17's sky limits addressed (2026-11-05) | none (the request is quoted in the report) | none | [R18-report.md](R18-report.md) | Claude in the main session; Codex translated | `r18` in `out/worktrees/r18` (runtime in `out/worktrees/r17/out/runtime-src`) |
| R13-D the option crash (2026-11-03) | (the R13 report's open item) | (none) | [R13-D-report.md](R13-D-report.md) | Claude, a side session of R13's project manager | `r13-option-lock` in `out/worktrees/r13-option-lock` (runtime `claude/r13-option-lock` in `out/worktrees/r12-vram/out/runtime-src`) |
| R13 less RAM and VRAM (2026-11-03) | [R13-plan.md](R13-plan.md) | three subagent tasks: R13-M compact game maps and reuse across versions, R13-A characters on first use and the lag trigger, R13-B the runtime's texture memory; R13-C memory profiles by Claude | [R13-report.md](R13-report.md) (with [R13-M](R13-M-report.md), [R13-A](R13-A-report.md), [R13-B](R13-B-report.md)) | Claude subagents; Claude as project manager (no Codex, as the user asked) | `r13-maps` (fixes `claude/r13-maps` in `out/worktrees/r12-fixes`), `r13-hotloader`, `r13-runtime` (runtime `claude/r13-runtime` in `out/worktrees/r12-vram/out/runtime-src`) in `out/worktrees`, integrated on `r13-int` |
| R13-F material preloads at their first draw (2026-11-03) | ([R13-P-report.md](R13-P-report.md) section 5.1, [ADR 0102](../decisions/0102-character-pbr-maps-stay-preloaded.md)) | (none: a Claude session started by the R13-P session) | [R13-F-report.md](R13-F-report.md): runtime patch 0030 and the A/B, same look, the hitch measured and accepted by the user ([ADR 0103](../decisions/0103-material-preloads-load-at-their-first-draw.md)) | Claude | this session's worktree `.claude/worktrees/vibrant-perlman-d01bce` (branch `claude/vibrant-perlman-d01bce`); runtime `claude/r13-first-draw-0030` (measured as `claude/r13-first-draw`) in `out/worktrees/r10-eyes/out/runtime-src` |
| R13-P streaming character PBR maps (2026-11-03) | (the R13 open item "Preloaded Remix mods", [R13-report.md](R13-report.md#open-items-and-follow-ups)) | (none: a Claude session started by the R13 session) | [R13-P-report.md](R13-P-report.md): the A/B, streaming visible at every first appearance, generators unchanged ([ADR 0102](../decisions/0102-character-pbr-maps-stay-preloaded.md)) | Claude | `r13-preload` in `out/worktrees/r13-preload` |
| R11-B cached imported game maps (2026-11-02) | [R11-B brief](R11-B-cached-game-maps.md) | (the user's request) | [R11-B-report.md](R11-B-report.md) | Codex (gpt-6.1-sol); Claude as project manager | `r11-cache` in `out/worktrees/r11-cache`, fixes `codex/r11-autopbr` in `out/worktrees/r11-fixes` |
| R10 the user's character report (2026-11-02) | [R10-plan.md](R10-plan.md) | two briefs: [R10-E steady eye whites for imported characters](R10-E-eye-whites.md), [R10-H imported NPCs after a map change and VMD expressions](R10-H-hotloader-expressions.md) | [R10-report.md](R10-report.md) (with [R10-E](R10-E-report.md), [R10-H](R10-H-report.md)) | Codex (gpt-6.1-sol); Claude as project manager | `r10-eyes`, `r10-hotloader` in `out/worktrees` |
| R9 the user's glass report (2026-11-02) | [R9-plan.md](R9-plan.md) | one brief: [R9-G realistic fracture, instant breaks, sounds, water, blasts, stable pushes, a clear button](R9-G-glass.md); the CI fixes and the melee error are Claude's | [R9-report.md](R9-report.md) (with [R9-G](R9-G-report.md)) | Codex (gpt-6.1-sol); Claude as project manager | `r9-glass` in `out/worktrees` |
| R8 the user's report after R7 (2026-11-01) | [R8-plan.md](R8-plan.md) | two briefs: [R8-C vanilla graphics add-ons](R8-C-addon-compat.md), [R8-G glass under load, collision levels, follow-up hits](R8-G-glass.md); the character noise is Claude's (runtime patch 0018); [R8-B Backrooms native fixes](R8-B-backrooms-fixes.md) | [R8-report.md](R8-report.md) (with [R8-B](R8-B-report.md), [R8-C](R8-C-report.md), [R8-G](R8-G-report.md)) | Codex (gpt-6.1-sol); Claude as project manager | `r8-compat`, `r8-glass` in `out/worktrees`, integrated on `r8-int` |
| R1 whole-repo review | [R1-handover.md](R1-handover.md) | [R1-codex-prompt.md](R1-codex-prompt.md) | [R1-report.md](R1-report.md) (Codex), [triage](R1-triage.md) (Claude) | Codex; triage and fixes by Claude | report on `r1-review`; fixes on `r1-fixes`, both in `H:\BACKUP_20260815\Modding\!NVIDIA-RTX-Remix\out\worktrees\r1-review`, from `main` after `8f8a540`; merged into `main` 2026-10-28 |

G1-B implementation/offline validation is complete: [G1-B report](G1-B-report.md). G1-A and Claude's
integration/game acceptance remain separate from that native/debris report.

G1-B's post-game fix pass is complete for implementation/offline checks:
[G1-B fix report](G1-B-fix-report.md), branch `g1-native-fix`. Integration/game acceptance remains
with Claude; the report includes real-map import counts and before/after timing limits.

## Rules for briefs

- Self-contained for someone who has read [AGENTS.md](../../AGENTS.md) and nothing else.
- State scope, files the assignee may and may not touch, acceptance criteria, how to test, what to
  report, and when to stop and ask.
- Never rewrite an accepted decision record in a brief; point to it, or ask for a new one.

## Rules for reports

- What was built (files), decisions taken (with any new decision record), test evidence (commands
  and the lines that show success), deviations from the brief, open issues, questions for the user.
- Facts worth keeping also go into [docs/RESEARCH.md](../RESEARCH.md); the report links to them.

## Native package addon menu

The 2026-10-30 continuation of QoL adds loader 0.7.0's native-package warning suppression, blue cards
and Workshop descriptions. See [QoL-report.md](QoL-report.md#native-package-addon-cards-2026-10-30)
and [ADR 0039](../decisions/0039-native-package-addon-presentation.md). Source branch:
`codex/native-addon-menu`, worktree `out/worktrees/native-addon-menu`.

## Native map glass

The next QoL batch fixes Modern House glass disappearing without shards. Source branch:
`codex/map-glass`, worktree `out/worktrees/map-glass`. See
[QoL-report.md](QoL-report.md#modern-house-map-glass-2026-10-30) and
[ADR 0040](../decisions/0040-native-map-glass-debris.md).

## Hotloader DepthWrite errors

The QoL shader batch is on codex/hotloader-depth in out/worktrees/hotloader-depth. See
[QoL-report.md](QoL-report.md#hotloader-depthwrite-shader-errors-2026-10-30) and
[ADR 0041](../decisions/0041-hotloader-remix-depth-materials.md).

| R20-D render compatibility | [R20-D brief](R20-D-render-compat.md) | [shared plan](R20-plan.md) | [R20-D report](R20-D-report.md) | Codex | `r20-render` |


- [VR V2/V3/V4 report](VR-V4-report.md): the final state (merged 2026-11-12) first, then the
  rounds' history (Q4's partial results, the door-Use crash and its repair, round 5).
  [Q's hand-over to Claude](VR-V4-Q-resume.md).


- [Q4 reviewed fixes-module crash rule](VR-V4-crash-review.md): exception-context stack
  classification, read-only WER copy and one fresh retry. The authorized retry PID 50548
  reproduced the same known fixes crash; Q stopped without a third run. Complete
  acceptance, Index, measurements, parity and Release gate remain pending.
