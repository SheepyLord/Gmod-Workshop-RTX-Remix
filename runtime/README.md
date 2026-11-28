# runtime/

## Repeated prop geometry (0124)

0124 shares the bottom-level geometry of compatible, heavily repeated props when the merged structure incurs sustained GPU build work. It follows the lower-cloud and post-effect changes in the same binary. [Combined runtime handoff](../docs/handover/repeated-mesh-frame-report.md)

## Lower clouds and post-processing (0121–0123)

0121 restores a native unit-test source required during clean configuration. 0122 adds a conservative screen-tile mask to the Enhanced sky's lower cloud renderer. 0123 removes the full-screen copy after each out-of-place post effect. The final sRGB pass writes the public output image in both buffer orders. [Build and game checks](../docs/handover/renderer-frame-output-report.md)

## Enhanced floor horizon and reflected ground (0120)

The virtual ground now samples cloud shadows at the actual hit and filters distant shadow gaps
when seen edge-on from the floor. PSR shades a reflected ground miss with the existing far air
and height fog. The two-layer ground array from 0118 has been removed. The Release install is
staged in the runtime worktree for review. [HR2 measurements and build](../docs/handover/sky-enhanced-HR-report.md#hr2)

## Enhanced No horizon (0119)

The shared No Horizon option gives Enhanced a lower sky with mirrored air, full-resolution
clouds from the opposite direction, and its existing night sources. The extra renderer and
lower sky-view table live only while the option is active. The Release install in the fork
worktree’s `_output/` is ready for review.
[Build, measurements and reviewer views](../docs/handover/sky-enhanced-HR-report.md#no-horizon-in-enhanced-0119)

## Ground below the Enhanced horizon (0118)

With haze active, camera and specular misses into the NUMOS planet now end on lit ground. The
composite integrates the air up to the ground and blends the limb across one traced pixel.
[Ground checks and reviewer views](../docs/handover/sky-enhanced-HR-report.md)

## Enhanced night after the first PoC test (0117)

The night image and meteors add six stops to the measured Gaia conversion. Real stars retain their
physical scale. The host applies lunar occultation to the sunlight entering NUMOS before it bakes
the sky and clouds and emits the map's Sun. The camera and reflections keep the exposed photosphere
and corona behind the Moon. The 0117 Release is staged in the runtime worktree's `_output/`.
[NR2 measurements and first checks](../docs/handover/sky-enhanced-NR-report.md#nr2)

## The Night sky editor in Enhanced (0116)

The Enhanced camera sky and mirror reflections draw the four existing night-image textures in NUMOS's
celestial frame. `rtx.atmosphere.numos.nightSkyImage` defaults to True. False selects the library's
real stars and Gaia Milky Way. The library lights the air, the clouds and the ground. Both visible
sources include the editor's shooting stars and Moon glow, and the chromosphere and corona during a
solar occultation. [Task NR calibration, build and first checks](../docs/handover/sky-enhanced-NR-report.md)

## Enhanced Sun and Moon edges (0115)

Patch 0115 limits the visible discs' brightness and filters their rims across two traced pixels.
The camera and perfect reflections share the calculation. The atmosphere, clouds and emitted
lights use the original illuminance. The packaged runtime includes 0114. The 0115 Release DLL
is staged in the runtime worktree's `_output/` for the reviewer's DLSS comparison.
[Measurements and first PoC checks](../docs/handover/sky-enhanced-S-report.md)

## Enhanced sky in the Remix menu (0114)

The Alt+X developer menu adds six NUMOS tabs under Game Setup → Step 2 → Sky Tuning. Graphics Settings
offers Night, Haze and Cloud controls. Both use the active Enhanced sky and the live options also set by
the companion. The Weather presets window applies the eleven built-in weathers in memory. The menu
and its help are available in English and all six runtime translations.

Patch 0114 is pending review in the game. The staged DLL is in the runtime worktree's `_output/`.
The packaged record covers patches through 0113. [Build and first checks](../docs/handover/sky-enhanced-M-report.md)

## Enhanced sun rays after the first PoC review (0113)

The ray pass uses the renderer's blue noise and filters history at the reprojected position. Stronger rays
keep at least a quarter of each sky channel, and the correction ends at the virtual planet's horizon.
The staged Release DLL is in the runtime tree's `_output/`. The [R3 handover](../docs/handover/sky-enhanced-R2-report.md#r3)
records the timing, DLL hash and the reviewer's first checks.

## Enhanced sky round 2 review build (0109–0112)

The four patches add camera-sky sun rays and four diagnostic views, a choice of Enhanced mist or
near-camera Remix fog, a double rainbow in sunlit rain, and disposal of the sky adapter at D3D9 shutdown.
The staged DLL is in the runtime worktree's `_output/` with the round 1 NUMOS assets. The new options
and their defaults, patch commits, build hash, and first PoC checks are in the
[Task R2 handover](../docs/handover/sky-enhanced-R2-report.md). [base.json](base.json) records all
four as pending while the packaged DLL remains at 0108.

## Enhanced sky package on the review branch (0107–0108)

The review branch adds the NUMOS library at `41842c6` as optional sky mode 2. Mode 0 uses the game's sky,
mode 1 the Standard atmosphere, and VR renders a request for mode 2 as Standard. The companion can set the
221 library settings and nine adapter controls under `rtx.atmosphere.numos.`.

Patch 0107 repairs tagged installs in checkout paths containing `!`. Patch 0108 integrates the renderer and its
offline tests. The tagged install stages `numos/` beside `d3d9.dll` in `_output/`. The review package
preserves that layout, including 41 standalone shaders, four night-sky data files, credits and licences.
The packaged DLL, patch hashes and clone pins are recorded together. [Build record](base.json),
[package handover](../docs/handover/sky-enhanced-P-report.md)

The option inventory, patch resolutions and reviewer’s scene checks are in the
[Task R report](../docs/handover/sky-enhanced-R-report.md).

## Upstream merge (0106)

Patch `0106-Merge-upstream-dxvk-remix-main-of-2026-11-23-2b46bed.patch`
([ADR 0265](../docs/decisions/0265-the-runtime-merges-upstream-main-of-2026-11-23.md),
[report](../docs/handover/upstream-1123-report.md), fork branch `claude/upstream-main-1123`, on 0105's `0165da89b`):
NVIDIA's `dxvk-remix` `main` of 2026-11-23 (`58ac72412`), the 25 commits after 0093's `2b46bed0c`, merged with
`2b46bed0c` as the base (a temporary `git replace --graft` of 0093's squashed commit `20e3553eb` onto it) and squashed
into one commit. Of upstream's 194 files, 99 are files patches 0001-0105 change too; 49 conflicted. The next update
merges `58ac72412..<main>` the same way.

- **Remix API 0.1000.3.** Upstream's `SceneInstanceAdd`, `SceneInstanceUpdate`, `SceneInstanceRemove` and
  `UpdateMaterial` (its 0.6.12, the experimental GPU-resident scene, `rtx.gpuResidentScene`, off) are slots 43-46 after
  `AddWaterDisturbance` (376 bytes); `remixapi_InstanceInfoParticleSpawnMaskEXT` is struct type 34 (33 upstream).
  `util_remix_api_version.h` writes a 0.1000.2 client its 344 bytes and a 0.1000.0 or 0.1000.1 client its 328; the
  fork's `docs/RemixApiChangelog.md` has the entry.
- **GPU layouts.** Upstream's view-model material bit is texture flag bit 31 (`rtx_materials.h`, `surface.h`; 22
  upstream, inside the MMD alpha cutoff's bits 19-30); `RtInstance` is 832 bytes with the fork's MMD alpha key and
  upstream's original mesh members in its copy constructor; `GpuParticleSystemDesc` 128 bytes and the particle constants
  480 (`worldToProjection` at 352: the fork's `sceneTlasValid` row and upstream's spawn context row).
- **Behaviour.** A failed queue submission or fence wait ends the process through the fork's
  `handleDeviceLost(reason)`, with upstream's memory report; option reads of trivially copyable values come from
  upstream's published copy inside the fork's `kLockFreeRead` branch, and a layer's save keeps upstream's NoSave rule
  under the fork's update mutex; RTX IO keeps a failed read's target until its reads complete and marks it failed only
  in the current upload generation; the texture categories stay the fork's `TextureCategorySets`, upstream's new
  `getTargetBuffer()` included, and upstream's new option locks around the fixed-function stage loops
  (`d3d9_device.cpp`, `d3d9_rtx.cpp`) see only those copies, refreshed before the lock is taken (the update mutex is
  not recursive); upstream's per-frame light conversion cache keeps the fork's lookup logging; the global
  tonemapper keeps its colour grading controls with upstream's shared, clamped `colorGrading`; upstream's local
  tonemapper changes stay out (the fork has none).
- **Left to the build:** the spawn kernel rejects a masked-out birth in the fork's `SpawnSample` form, upstream's
  GPU-resident frame end calls the fork's `manageTextureVram(ctx)`, upstream's spawn mask test expects type 34. The
  fork's `test_memory_diagnostics` (the memory log throttle) became `test_memory_stats_data`.
- **Found in the PoC:** the first build (`804b7da0`) refreshed the category copies inside `d3d9_device.cpp`'s locked
  stage loop, locking the update mutex twice on one thread: `std::system_error` (EDEADLK) and a crash at the first
  draws of every session. The refresh now comes before the lock.

Built by `build_runtime.ps1` in `out/worktrees/r17/out/runtime-src` (0001-0106): **`d3d9.dll` 510,292,480 bytes, SHA-256
`74115025eaa60ab65fcde74b2c90b7c3c22690c8fc8b5603f39c264d60770b33`** (74,876,380 bytes xz in Git LFS). Imported beside it from the same build with `tools\inputs.py import runtime
--file`: `usd/plugins/RemixParticleSystem/generatedSchema.usda` (upstream's birth mask properties). No loader
(`winmm.dll`) change.

Patch `0105-The-geometry-workers-sleep-when-idle-instead-of-poll.patch` (S1 of the second load speed-up plan, the
user's request of 2026-11-17 to do its remaining items; [ADR 0243](../docs/decisions/0243-the-geometry-workers-sleep-when-idle.md),
[report](../docs/handover/remix-workers-report.md); fork branch `claude/remix-workers`, commit `0165da89b` on 0104's
`8cd421cd8`): the geometry workers sleep when idle. `D3D9Rtx::GeometryProcessor` (`d3d9_rtx.h:220`) is the one
`WorkerThreadPool` in low-latency mode, whose idle workers polled their queues, tried to steal and yielded without end:
the two `geometry-processing` threads kept a core busy each from their first task to the end of the game, in the main
menu too. An idle low-latency worker now polls as before for `kWorkerSpinWindow` (1 ms) after its last task, then
sleeps on a condition variable until a task is counted or the pool stops; `Schedule` reads an atomic count of sleepers
after the push and the task count's increment and notifies under the lock only when one sleeps; a worker counts itself
before it tests for work under that lock, so no wake-up is lost; the destructor wakes the sleepers. The high-latency
mode (the ray tracing pipelines' and the asset exporter's pools) is unchanged. The logic is in the self-contained
`src/util/util_worker_idle.h` (`WorkerSpin`, `WorkerSleep`); `util_threadpool.h` gains a few marked lines, the fork's
`docs/fork-touchpoints.md` an entry; `tests/rtx/unit/test_worker_idle.cpp` (156 checks) is compiled from the patch by
the Release gate, which also compiles upstream's pool from the base commit and patches 0001-0105 and runs it (with a
local clone of the fork; [test_runtime_remix_workers.py](../tools/tests/test_runtime_remix_workers.py.md)). Upstream's
own `util_threadpool` test (8 workers, 2,000 tasks, cancellations) passes with it. Exported alone (`format-patch -1
--start-number 105 --zero-commit`) and built by `build_runtime.ps1` in `out/worktrees/r17/out/runtime-src`
(0001-0105): **`d3d9.dll` 479,886,336 bytes, SHA-256 `541806a9fa1f00504c2a24ea0e0f707a0a051bf12108b9355ef8f6735a64262c`**
(70,854,432 bytes xz in Git LFS). No loader (`winmm.dll`) change.

Patches 0101-0104 fix the runtime's findings of the repository review of 2026-11-16 (`out/review/repository-review.md`
in the main checkout: findings 1, 10 and 17; the user approved fixing every finding) and what the PoC smoke test of
those fixes found (0104). Fork branch `claude/review-runtime`: `aa92fe27a` (0101), `e5c5cae45` (0102), `ffaa14878`
(0103), `8cd421cd8` (0104), on 0100's `25c85588b`; each exported alone (`format-patch -1 --start-number <N>
--zero-commit`) and built together by `build_runtime.ps1` in `out/worktrees/r17/out/runtime-src` (0001-0104):
**`d3d9.dll` 479,885,312 bytes, SHA-256 `f88d381dbb12f0cc70228ae411f8859b0c19bd986eaae888049adc8fedcc08da`**
(70,861,508 bytes xz in Git LFS; 0001-0103's build, `2ee16d49...`, was never published). No loader (`winmm.dll`)
change.

- **Patch `0101-A-mod-s-Remix-Logic-option-layer-only-its-own-config.patch`** (finding 1): the loader deploys the Remix
  mods of any subscribed Workshop item as content, and an `RtxOptionLayerAction` node in such a mod's Remix Logic
  graph acquired an option layer, above `rtx.conf`, from any config file it named (a UNC path made Windows offer the
  player's login to another host), the file could set every runtime option (the folder NRC loads its CUDA DLLs from,
  the welcome message the splash formatted as printf, captures, keys), and a hash list that failed to parse
  (`std::stoull`) threw out of the graph and ended the game. Now `rtx_mod_layer_policy.h` (new, self-contained)
  holds the rules: in a mod's stage the graph's parser refuses an asset path that names a drive, a root, a share or a
  scheme before USD's resolver looks for it, and what it resolves to must lie in the mod's folder (the stage's root
  layer's; in-memory stages keep upstream's resolution; a string-typed asset path resolves as a token does);
  `RtxOptionManager::acquireModLayer` (the graph's only way to a layer now) loads only a file in a mod's folder below
  `rtx-remix/mods`, without `.` or `..`, a stream, a device or a share other than the game's, and marks the layer a
  mod's layer, which applies only rendering options (`rtx.atmosphere.`, `rtx.weather.`, `rtx.volumetrics.`,
  `rtx.tonemap.`, `rtx.autoExposure.`, `rtx.bloom.`, `rtx.postfx.` and eight single look options; never text,
  lists, keys, integer vectors, an integer without a declared range of at most 1024 values, a debugging option, a
  name ending as a file, folder, message or key, the player's own settings or runtime state), creates no dynamic
  options and never shares a layer with code. The refused keys count as rejected keys (kept on save) and are logged
  once. For every layer, and for `readOption` (the Remix API's `SetConfigVariable`, which any server's client Lua
  reaches), a value that fails to parse is refused and leaves the value as it was; `SetConfigVariable` returns
  `INVALID_ARGUMENTS` for it. `RtxOptionLayerAction` catches what acquiring could still throw. No Remix mod the
  package ships uses Remix Logic graphs (checked by the gate). Unit tests: `tests/rtx/unit/test_mod_layer_policy.cpp`
  (338 checks; also compiled by the gate, [test_runtime_mod_option_layers.py](../tools/tests/test_runtime_mod_option_layers.py.md))
  and `test_mod_option_layer.cpp` (62 checks, through the real option manager: refused paths, a file in a mod's folder,
  reload, a code layer and `readOption` with a hash list that fails to parse; meson only).
- **Patch `0102-The-splash-the-welcome-message-shown-as-text-once-fo.patch`** (finding 10): `ImGuiSplash::update`
  drew `rtx.welcomeMessage` as `TextWrapped`'s printf format, and `rtx.splashMessageDisplayTimeSeconds` (unbounded,
  compared every frame with a start time that stayed at the epoch when the splash never started) brought the splash
  back at once; both are reachable through the Remix API. The welcome message is drawn with `TextWrapped("%s", ...)`;
  the display time is capped at 60 s (the option's maximum, and again where it is read; `RtxOptions.md`); the splash
  starts only in the first two minutes after the first frame, never times from the epoch, and is done for the process
  once its time has passed (a steady clock). The gate scans the code the patches add for a printf-style ImGui call
  whose format is a runtime value ([test_runtime_imgui_formats.py](../tools/tests/test_runtime_imgui_formats.py.md)).
  The fork's base commit, which no patch shows, has more calls of that shape, each carrying fixed or driver text:
  `dxvk_memory_tracker.cpp` (counts and byte sizes), `dxvk_imgui.cpp` (`TextSeparator`'s literals, the HUD's progress
  lines, NGX's reason, the render size), `dxvk_imgui_capture.cpp` (the capture menu's own lines), `rtx_user_menu.cpp`
  (tab descriptions), `rtx_fork_upscaler_ui.cpp` (the upscaler's reason, the render size).
- **Patch `0103-The-startup-text-from-rtx-remix-mods-nativeloader_ui.patch`** (finding 17): the splash and the font
  atlas read the editable startup text (patch 0012, ADR 0050) from `garrysmod/data/nativeloader_ui`, where any server's
  client Lua writes `.txt` files, so a server's text stayed on the splash at every later start. `StartupMessage::folder`
  is now `rtx-remix/mods/nativeloader_ui` (relative to the game's folder, as before), where
  [`package_fixes.py`](../tools/package_fixes.py.md) deploys the texts create-only (the player's edits are kept):
  neither GMod's Lua nor another Workshop item's package can write there (the loader skips a content package whose
  root files overlap the RTX package's), and the folder holds no mod file, so Remix's mod manager passes it by. A copy
  edited in the old folder is not read any more and not moved: a file in `garrysmod/data` may as well be a server's,
  which the runtime cannot tell from the player's. The loader leaves such an edited file in place (no longer tracked)
  and removes the unedited ones. Checked by [test_runtime_splash.py](../tools/tests/test_runtime_splash.py.md).
- **Patch `0104-The-Remix-API-an-empty-value-changes-nothing-and-suc.patch`** (found by the PoC smoke test of
  0101-0103): 0101 made `remixapi_SetConfigVariable` answer `INVALID_ARGUMENTS` whenever `readOption` read nothing,
  and `Config::findOption` takes `""` for no value, so an empty value, which had always changed nothing and answered
  success, became a failure. The RTX package's Lua sets its session texture lists and the eye-white aliases to `""`
  whenever they are empty, and the fixes' binding printed a failure for each (902 lines in a four-minute session). An
  empty value is a success again; a value that fails to parse is still refused. Checked by
  [test_runtime_mod_option_layers.py](../tools/tests/test_runtime_mod_option_layers.py.md).

Patch `0100-Translate-the-Remix-menus-98-new-texts-zh-CN-zh-TW-j.patch` (the user's go-ahead of 2026-11-15; fork
branch `claude/remix-menu-i18n`, commit `25c85588` on 0099's `1dd38dbf`): the Remix menus' (Alt+X) texts that came
with the upstream merge of patch 0093, translated into the six languages. That merge brought 98 menu texts the
catalogs did not have: the water simulation and its sludge, the dissolve of alpha-blended draws, colour inversion,
the eye's iris depth scale and limbal ring, the particles' spawn distribution and RTXDI's sparse neighbour
candidates. The build's `i18n/tools/embed.py` checks the `.po` files only against `remix.pot`, which had not been
regenerated, so it passed and the six languages showed those texts in English. `i18n/tools/update_strings.py`
regenerated `remix.pot` (3,452 messages) and merged it into every catalog: the 98 are translated (agent-written,
keeping to each `i18n/glossary/<language>.md`, which gains the terms this batch settled), the 16 to 18 entries whose English left the sources stay at the end
as obsolete `#~` entries, and the other entries' references move to their current lines, which is most of the
patch's 3.4 MB. No code changes. `update_strings.py --check` passes, `embed.py` reports 3,452 of 3,452 in every
language (the fonts have every character used) and `test_embed.py` passes. Exported alone (`format-patch -1
--start-number 100 --zero-commit`) and built by `build_runtime.ps1` in `out/worktrees/r17/out/runtime-src`
(0001-0100): **`d3d9.dll` 479,855,616 bytes, SHA-256 `2c157ebe717182bb4bd2b8305fe0fbed29a09c0d36b84f78be6d7415e54290ab`**
(70,817,488 bytes xz in Git LFS); it holds all 98 new texts in each language (searched for in the DLL).

Patch `0099-Atmosphere-the-night-sky-editor-each-layer-on-its-ow.patch` (the user's request of 2026-11-15 for a sky
editor, [ADR 0227](../docs/decisions/0227-the-night-sky-editor.md); fork branch `claude/night-sky-editor`, commit
`1dd38dbf` on 0098's `173bdc84`): each layer of the night sky image on its own. The four layers the sky adds in gamma
space (the stars, the constellations' bright stars, the galaxy band, the nebulae) each have a brightness
(`rtx.atmosphere.starMap{Star,Constellation,Galaxy,Nebula}Brightness`, 1, 0-8), turned into the gamma-space weight
brightness^(1/2.2), and a colour (`...Saturation`, 1, 0-2); the sum is held at 1, or at the largest weight above it
(`rtx_night_sky_layers.h`, self-contained). The constellations, until now baked into the nebula texture, are a layer
of their own beside it: `<nebula name>_constellations.dds`, bound at 222 (`AtmosphereStarMapConstellations`), with no
new path option for Lua to reach. A layer at 0 is neither drawn nor kept (its texture freed, loaded again when turned
up), and the image's night has its own flag, so every layer off is a night without stars, not the procedural field.
The shooting stars' fixed 8 % of slots becomes `shootingStarsPerMinute` (1.2) and their brightness
`shootingStarBrightness` (1). Three new 16-byte rows of `AtmosphereArgs`, zeroed in `normalizeForSkyLutCache`;
`RtxOptions.md` rows; `tests/rtx/unit/test_night_sky_layers.cpp` (860 checks), compiled from the patch by the
Release gate ([test_runtime_night_sky_editor.py](../tools/tests/test_runtime_night_sky_editor.py.md)). The patch adds
no Remix menu text; the fork's catalogs were already behind its sources (`update_strings.py --check` fails: 98 menu
texts of the sources are not in them, since before this patch). Exported alone (`format-patch -1 --start-number 99
--zero-commit`) and built by `build_runtime.ps1` in `out/worktrees/r17/out/runtime-src` (0001-0099): **`d3d9.dll`
479,795,712 bytes, SHA-256 `52a8a3d27fe097b0959669a4aa0829512ed1f84eee5162ebed6e1206f3322537`** (70,832,400 bytes xz
in Git LFS). The package's `atmosphere` folder has the nebula without the constellations and the constellations'
layer at 8192 and, for the low tier, 4096 ([`bake_nightsky.py`](../tools/sky/bake_nightsky.py.md)).

Patch `0098-The-About-tab-takes-the-secret-replacements-whole-no.patch` (the field's crash of 2026-11-15 soon after a
start, and a PoC crash at a level change; fork branch `claude/secrets-race`, commit `173bdc84` on 0097's `678b28d1`):
the asset replacer hands its secret replacements to the About tab whole.
`AssetReplacer::updateSecretReplacements` (`rtx_asset_replacer.cpp:222`) cleared and refilled `m_secretReplacements`
on DXVK's command thread whenever mods finished loading, changed or reloaded, while `ImGuiAbout::Secrets::update`
walked it every frame on the thread that presents (the material system's render thread, or the main thread while a
level loads), with a plain `bool` between them: both crashes read freed nodes at `dxvk_imgui_about.cpp:233`. The
command thread now builds the map on its own, checks the selected variants against it and publishes it under a lock
(`SecretHandoff`, `rtx_secret_handoff.h`, self-contained); the About tab takes a copy under the same lock
(`getSecretReplacementInfo` returns by value; `dxvk_imgui_about.cpp` is unchanged, its `const auto&` binds the copy).
A load without secret replacements leaves the tab's copy as it was, as before. `tests/rtx/unit/test_secret_handoff.cpp`
(22 checks) is compiled from the patch by the Release gate ([test_secret_handoff.py](../tools/tests/test_secret_handoff.py.md)).
Still unguarded upstream: `markVariantStatus` (a ticked secret) writes `m_variantInfos` on the present thread while
`getReplacementsForMesh` reads it on the command thread. Exported alone (`format-patch -1 --start-number 98
--zero-commit`) and built by `build_runtime.ps1` in `out/worktrees/r17/out/runtime-src` (0001-0098): **`d3d9.dll`
478,662,144 bytes, SHA-256 `7c7291b6852da7f77ca4fef2c8b3cb834f2491e0a29bbfd2968f3f22877e0122`** (70,706,696 bytes xz
in Git LFS).

Patch `0097-LockImage-a-read-back-resolves-only-a-multisampled-i.patch` (GitHub issue 12, fork branch
`claude/lockimage-resolve`, commit `678b28d1` on 0096's `7db13a1b`): a read-back resolves only a multisampled
image. `D3D9DeviceEx::LockImage` chose the image to read back with
`sampleCount != 1 ? pResource->GetResolveImage() : std::move(resourceImage)` and resolved while `resourceImage` was
still set; MSVC never moves there (the conditional binds the resolve image's const reference), so every read-back of
a GPU-written single-sample image also resolved the image into itself, which AMD's driver crashes on (a null read at
`amdvlk64+0x3f798a`). R13's released texture copies (the `minimum` memory profile) made such read-backs common: the
main menu's slideshow, fonts and textures in a map. An explicit branch now moves `resourceImage` for a single-sample
image. Checked by [test_runtime_lockimage_resolve.py](../tools/tests/test_runtime_lockimage_resolve.py.md) (the
removed and added lines compiled with MSVC `/std:c++latest`) and in the built code (the single-sample branch takes
the pointer without an AddRef, and `if (resourceImage != nullptr)` is a real test again, `LockImage+0x9f6`). Exported
alone (`format-patch -1 --start-number 97 --zero-commit`) and built by `build_runtime.ps1` in
`out/worktrees/r17/out/runtime-src` (0001-0097): **`d3d9.dll` 478,660,096 bytes, SHA-256
`c60ef71c9894ab87da9e5f51e1f5a483f34194c60168c8106c5bb06d93beb253`** (70,705,108 bytes xz in Git LFS).

Patch `0096-The-Remix-menu-and-the-HUD-drawn-into-the-back-buffe.patch` (the user's report of 2026-11-15, fork
branch `claude/dlfg-menu`, commit `7db13a1b` on 0095's `9b6e1101`): the Remix menu and the HUD drawn into the
presented image again with DLSS frame generation on. The swapchain's present blitted the game's frame into the back
buffer and then (0094) the frame before its UI into the presenter's HUD-less image; the HUD and the Remix menu
(`ImGui_ImplDxvk::RenderDrawData`) bind no target of their own and draw into the one the last blit leaves bound, so
they went into the HUD-less copy, which frame generation only reads: Alt+X took the input and nothing was shown. The
HUD-less blit now comes first and the back buffer's last; the HUD-less copy stays without UI, so DLSS-G keeps the
menu in place as UI. Checked by [test_dlfg_hudless.py](../tools/tests/test_dlfg_hudless.py.md) (the blits' order) and
in the PoC (`out\qa-poc\altx`: the basic and the developer menu drawn with DLSS frame generation 3x on, absent
before). Exported alone (`format-patch -1 --start-number 96 --zero-commit`) and built by `build_runtime.ps1` in
`out/worktrees/r17/out/runtime-src` (0001-0096): **`d3d9.dll` 478,660,096 bytes, SHA-256
`d03f09c80abb93ea826b340a1a46a93e64c82ea94bd4f02d7e03a377540e932a`** (70,718,044 bytes xz in Git LFS).

Patch `0095-Poster-GMod-s-poster-command-rendered-in-tiles-of-th.patch`
([ADR 0226](../docs/decisions/0226-the-poster-command-rendered-in-tiles-by-the-runtime.md), GitHub issue 3, the user's
request of 2026-11-15, fork branch `claude/poster`, commit `9b6e1101` on 0094's `81b4d393`): GMod's `poster` command
rendered by the runtime. `d3d9.dll` exports `rtxposter_Start`, `rtxposter_Cancel` and `rtxposter_GetStatus`
(`rtx_poster_api.h`, version 1; the engine guard keeps a byte-identical copy). They reach the poster through its own
instance (`rtx_poster_instance.h`), not the Remix API's registered device, which GMod never registers (the first PoC
run's `rtxposter_Start` answered `RTXPOSTER_E_NO_DEVICE` that way). While a poster renders, the camera
manager narrows the main, view model and sky cameras' projections to one tile's window of the game's view
(`rtx_poster_math.h`: only the clip x and y rows change; the camera keeps the game's field of view and aspect), each
tile the window's own size, overlapping its neighbours by a sixteenth of the window's short side (16 to 256 pixels);
a tile's first frame resets the history, its last (64 by default) is read back before its UI and the tiles are
blended over their overlaps into 8-bit BGR, written as a PNG by Windows' encoder (WIC through `ole32.dll` at run time)
on a thread of its own, as `<path>.part` and renamed (`rtx_poster.cpp`, `rtx_poster_png.cpp`). The runtime's clock
stands still, exposure keeps its value, motion blur and the lens effects are left out; the physical sky's cloud layer
and aerial perspective are fitted to the tile's window, the sky matte's viewport stretched to it (its jitter shrunk to
a pixel), textures and the sky sampled for the poster's pixel. It stops when the view moves, the window changes size,
VR starts or it is cancelled; at most 16 times the window and 16384 x 16384. `tests/rtx/unit/test_poster_math.cpp`
(764 checks) is compiled from the patch by the Release gate ([test_runtime_poster.py](../tools/tests/test_runtime_poster.py.md)).
Exported alone (`format-patch -1 --start-number 95 --zero-commit`) and built by `build_runtime.ps1` in
`out/worktrees/r17/out/runtime-src` (0001-0095): **`d3d9.dll` 478,660,096 bytes, SHA-256
`4b1b0b1817e9448848d7307bbc43863569a8f44f1d53e037b1e509fcb4a3c99a`** (70,712,160 bytes xz in Git LFS).

Patch `0094-DLSS-frame-generation-keeps-the-UI-in-place-a-HUD-le.patch`
([ADR 0223](../docs/decisions/0223-frame-generation-gets-the-frame-before-its-ui.md), the user's request of 2026-11-14,
fork branch `claude/dlfg-hudless`, commit `81b4d393` on 0093's `20e3553e`): DLSS Frame Generation gets the frame
before its UI (NGX's HUD-less colour, `pHudless`), so the crosshair and the HUD stay in place in the generated frames
instead of moving with the scene. The D3D9 swapchain keeps a copy of its back buffer while the frame generation
presenter runs; `injectRTX` blits the final output into it after the game's target and marks the frame
(`DlfgHudlessHandoff`, the self-contained `rtx_dlfg_hudless.h`); the present blits the copy beside each frame
generation back buffer with the back buffer's own blitter call; the present thread passes it to
`NGX_VK_EVALUATE_DLSSG` only for a marked frame, with barriers like the back buffer's, and logs `[DLFG] frame
generation gets each frame before its UI (HUD-less input), from frame N` once. No option; frame generation off, nothing
changes. `tests/rtx/unit/test_dlfg_hudless.cpp` (38 checks) is compiled from the patch by the Release gate
([test_dlfg_hudless.py](../tools/tests/test_dlfg_hudless.py.md)). Exported alone (`format-patch -1 --start-number 94
--zero-commit`) and built by `build_runtime.ps1` in `out/worktrees/r17/out/runtime-src` (0001-0094): **`d3d9.dll`
478,622,720 bytes, SHA-256 `55b30956085671e3d1d970a6da65e8d52c402b51f15304c50d1c5836a575b27d`** (70,698,152 bytes xz
in Git LFS).

Patch `0093-Merge-upstream-dxvk-remix-main-of-2026-11-14-remix-1.patch`
([ADR 0218](../docs/decisions/0218-the-runtime-follows-upstream-dxvk-remix-main.md),
[report](../docs/handover/upstream-runtime-report.md), fork branch `claude/upstream-main-1114`, commit `20e3553e`): NVIDIA's
`dxvk-remix` `main` of 2026-11-14 (`2b46bed0c`), 57 commits past `remix-1.6.1`, merged onto 0001-0092 with
`remix-1.6.1` as the merge base (patch 0001 holds the fork's 1.6.1 merge as a snapshot, so the merge took a temporary
`git replace --graft` of 0001's commit) and squashed into one commit. The next update merges `2b46bed0c..<main>` the
same way as 0094.

- **RTXDI** is upstream's recorded `dc8eb03` (RemixProjGroup/RTXDI), and
  [`submodules/rtxdi.patch`](submodules/rtxdi.patch) now holds the fork's Numos volumetrics (`30431e9..3b39a7c`:
  `volume_composite_helpers`, `volume_integrator`, `volume_lighting`) on it. `evalVolumetricNEE` keeps upstream's fetch
  in uniform control flow (NVBUGS 7020086) and the fork's consumer gain and edge falloff.
- **Remix API 0.1000.2.** Upstream's `SetWaterSim` and `AddWaterDisturbance` are slots 42-43 after the fork's 41
  functions (344 bytes), its struct types are 29-33 and `SLUDGE` is bit 28. `util_remix_api_version.h` writes a
  0.1000.0 or 0.1000.1 client its 328 bytes; upstream's texture transform fields of the material extensions are read
  only from 0.1000.2 clients (every 0.1000.x version compares above upstream's 0.6.6 gate). `remixapi_SetConfigVariable`
  keeps the fork's call without upstream's outer lock: the fork's `readOption` takes the update mutex (patch 0029).
- **GPU layouts.** The alpha blend dissolve mode is flags0 bits 3-5 (`alphaBlendDissolveShift` 3; the texture flags'
  bits 19-30 hold the MMD alpha cutoff); the camera material flags are opaque offsets 11 and 12; `GpuParticle` is 64
  bytes (`timeToLive` float at 44, `emitterObjectPickingValue` at 48); `RaytraceArgs` and `ParticleSystemConstants`
  (464 bytes) gain a padded row; particle bindings 63 (the fork's spawn statistics), 64 and 65.
- **Shaders.** Emission is read only for an emissive material, where upstream moved it, with the fork's legacy
  emissive alpha mask, texture factor blend, sRGB textures, tint and adaptive intensity (gated on the adaptive
  intensity, so an adaptive material without a fixed one still emits). The spawn kernel keeps the shelter relocation
  and landing trace with upstream's surface-area triangles and rejected spawns. The eye override takes the EyeRefract
  flag as a parameter.
- **USD.** The fork's value reader takes float2 values; texture transforms clamp an infinite authored value to their
  limit, as upstream's do. `usdg.dll` (upstream's USDG file format and package resolver) is linked by `d3d9.dll` and
  installed beside it, with `usd/plugins/usdg/resources/plugInfo.json`; the categories and particle schemas carry
  `sludge` and the particle controls.

Built by `build_runtime.ps1` in `out/worktrees/r17/out/runtime-src` (0001-0093): **`d3d9.dll` 478,618,112 bytes,
SHA-256 `3237fe73bfc5a243de9fccb86036dccdb350411bafdc30960c5f47c75c59b0e9`** (70,695,080 bytes xz in Git LFS; the
1.6.1 build was 418,989,056, the new shader permutations make most of the difference). Imported beside it from the
same build with `tools\inputs.py import runtime --file`: `usdg.dll` (240,640 bytes, `36e14a05...`), its
`plugInfo.json`, both plugin DLLs and both schemas. `-Install` stops locally at upstream's new `usdg-converter`
install step, whose batch helper drops the `!` of this repository's path (the converter is not shipped); GitHub's
package workflow has no `!` in its paths. The unit suite of the same build passes 57 of 58 tests (upstream's API
version, camera material and particle picking tests and the fork's MMD alpha test fitted to the merged layouts);
`test_remix_categories` cannot load `d3d9.dll` in its process, as before. `RtxOptions.md` is regenerated from the
build.

Patches `0091-Core-fixes-the-pipeline-handle-race-command-list-rec.patch` and
`0092-Reflex-no-sent-message-is-dispatched-inside-Present.patch`
([ADR 0216](../docs/decisions/0216-the-runtimes-pipeline-handle-race-and-in-present-message-dispatch-fixed.md),
[report](../docs/handover/crash-0xc0000005-report.md), branch `claude/crash-0xc0000005`), the "Crash detected ...
0xC0000005" most players report:

- **0091** ports upstream dxvk-remix `c1a891bf85dbda78cab979010089c5c9b4256a11` ("[REMIX-6230] Core fixes", MIT) with
  its exact hunks: `DxvkGraphicsPipeline::getPipelineHandle` copies the new instance's `VkPipeline` while `m_mutex` is
  held (the state-cache workers' `emplace_back` reallocated `m_pipelines` between the unlock and the read, and the
  render thread bound a freed handle: `nvoglv64.dll+0xe622f8` 7-35 s after start); `DxvkSubmissionQueue` recycles a
  finished command list before it decrements `m_pending` and wakes the waiters; frame generation waits once on the
  swapchain's acquire semaphore. The same handle fix in `DxvkComputePipeline::getPipelineHandle` (not upstream's).
- **0092**: `RtxReflex::latencyPing`, inside Present, peeks for the PCL ping only while `GetQueueStatus` reports a
  posted message and no sent one, with `PM_REMOVE | PM_QS_POSTMESSAGE`, so another Source game's WM_COPYDATA
  release/reacquire is no longer handled mid-frame. `PM_QS_POSTMESSAGE` alone does not stop `PeekMessage` from
  dispatching sent messages (measured; RESEARCH.md).

Exported one at a time (`format-patch -1 --start-number 91|92 --zero-commit`) from `827870ba` and `dd580bc2` on 0090's
`aea5d31e`, and built with it by `build_runtime.ps1` in `out/worktrees/r17/out/runtime-src` (0001-0092), replacing the
Moon-only import below: **`d3d9.dll` 418,989,056 bytes, SHA-256
`e242dfdb08486fd97012e3af89b2955fc4f9a11e992902e383cbb844cc857531`** (61,736,412 bytes xz in Git LFS). The build's PDB
shows the handle loaded before the unlock (graphics `+0xb5 mov r14,[rax+1C8h]`, unlock `+0xbd`; compute `+0xa8 mov
rsi,[rax+80h]`, unlock `+0xb0`; before: `+0x207 mov rax,[rdi+1C8h]` after the unlock at `+0xb4`, and `+0x146 mov
rax,[rdi+80h]` after `+0x9e`). Its unit tests: 39 of 40 pass; `test_remix_categories` cannot load `d3d9.dll` in its
process with this build or the 0090 one alike. [`test_runtime_crash_fixes.py`](../tools/tests/test_runtime_crash_fixes.py.md)
checks both patches statically.

Patch `0090-Atmosphere-the-Moon-by-day.patch` ([ADR 0207](../docs/decisions/0207-the-moon-by-day.md),
[report](../docs/handover/moon-by-day-report.md), branch `claude/moon-by-day`): the moons are drawn by day. A
moon's light is added to the sky's in-scatter in front of it, and its disc hides only what lies beyond it (the stars and
the night sky image, the airglow layer and the halos, earlier moons, the sun disc); with the in-scatter faded out at
night this is the old replace composite exactly. By day each moon's light follows the real Moon's phase law
(`rtx_moon_daylight.h`: Allen's law over the drawn Lunar-Lambert one, held from 150 degrees) times
`rtx.atmosphere.daytimeMoonBrightness` (default 1, 0-4, 0 = no moon by day), handed over to the night's look as the
sun sinks to 5 degrees below the horizon. The horizon hides a disc below it unless `rtx.atmosphere.noHorizon`.
`AtmosphereArgs` grows by one 16-byte row (`moonDaytimeScale0-3`, zeroed in the LUT cache key); the dev menu's
Daytime Brightness (Moons, Global Lighting) is translated in the six catalogs; `RtxOptions.md` has the option;
`tests/rtx/unit/test_moon_daylight.cpp` is compiled from the patch by the Release gate (`test_moon_daylight.py`).
Built from the clone's `claude/moon-by-day` at `aea5d31e` (0001-0090, on `vr2`'s `1097d701`) by `build_runtime.ps1` in
`out/worktrees/r17/out/runtime-src`: `d3d9.dll` 418,989,056 bytes, SHA-256
`fb0e2b21d057a76ee0572c57d5e33311a94e048ed5c54758102a61b6ec5b2ee0` (61,729,712 bytes xz in Git LFS); imported, then
replaced on the same branch by the 0001-0092 build above.

Patch `0089-VR-true-stereo-each-eye-path-traced-with-its-own-vie.patch` (VR V7,
[ADR 0198](../docs/decisions/0198-vr-true-stereo-by-swapping-the-eyes-state.md), branch `vr6`): with
`RTXVR_QUALITY_TRUE_STEREO` and Ray Reconstruction the frame is path traced once per eye. `rtx_vr_eye.h` names the eye
the render thread is tracing; the right eye's `Resources`, ReSTIR GI, Ray Reconstruction, NRC and SHaRC are a second
set in `DxvkObjects` behind the existing accessors, each eye's camera stands in for Main, the sky's integrators and
the froxel volumetrics run once on the centre camera, each eye fits the aerial perspective volume and keeps its own
cloud history, and the NRC library is shared by both caches. `vrmath::eyeToCentreView`, `eyeProjection` and
`eyeFrustumBasis` are unit-tested in `tests/rtx/unit/test_vr_math.cpp`. Built from the clone's `vr2` at `1097d701`
(0001-0089): `d3d9.dll` 418,468,864 bytes, SHA-256
`8d64393fdb4343f7e4db2f71c683a9becbd5fe167c84d23924712fb052fd437f`.

Patch `0088-The-VR-frame-s-GPU-work-in-rtxvr_Status.patch` (VR V6,
[ADR 0201](../docs/decisions/0201-vr-auto-reads-the-gpus-work.md), branch `vr6`): `rtxvr_Status` gains `gpuMsWork`, the
VR frame's GPU span without the queue's waits for the CPU (on the Index 6 to 10 ms of each 45 fps frame is pacing), and
`stereoActive`, reserved for true stereo; the status is 496 bytes within API 4. Built from the clone's `vr2` at
`77014404` (0001-0088): `d3d9.dll` 418,447,872 bytes, SHA-256
`746ca8bd565c6a5b21c9b0d91fcaddeedefbd303e586df0190c7a6ad5b0bf9bc`.

Patch `0087-A-live-VR-quality-step-rtxvr_SetQuality-API-4.patch` (VR V6,
[ADR 0199](../docs/decisions/0199-vr-auto-quality-ladder.md), branch `vr6`): `rtxvr_SetQuality`, API version 4. The
render thread writes the step's DLSS mode, bounces, volumetrics and cloud samples into the `! VR session` layer and
reallocates the eye images when the scale changes; the status reports the step in use. `vrpolicy::validQuality` and
`topQuality` (V1's preset) are unit-tested in `tests/rtx/unit/test_vr_math.cpp`. Built from the clone's `vr2` at
`6471ff89` (0001-0087): `d3d9.dll` 418,447,872 bytes, SHA-256
`444e781da327315ff1df33cf16b14068e766b81848e45897783ad53be4c7bf93`.

The merge of VR V2-V4 with `main` (2026-11-12) imports one build of every patch, 0001-0086: the VR clone's `vr2`
at `308ca2f7` (`39e2ab77` with 0086 applied by `git am`), built by `build_runtime.ps1` in
`out/worktrees/r17/out/runtime-src`: `d3d9.dll` 418,444,288 bytes, SHA-256
`7572e10453a386093eac75e0fa8424d53bfbbdeced163b8c15534a03390cb9d6`.

R's 2026-11-11 follow-up is imported once for V2, from the clone's vr2 at 39e2ab77, through
patch 0085. The centre projection stays at 0.4 m; GPU depth/tile minima select search starts down
to 0.15 m, with one-primary-texel spacing. GPU indirect commands select either the retained fixed
kernel or the adaptive kernel, without CPU readback or a new wait. Rejected wider-footprint and
colour-guidance trials remain in the patch history; the accepted 3 x 3 coverage is retained.
The selected d3d9.dll is 418403840 bytes, SHA-256
027aae44befc301774508b09401808fa16615592e05a02bcf64bd9d761123278. base.json has no pending patches.
The module provenance refresh keeps N's unchanged executable image. Q needs no further runtime
import unless code changes. The Release gate passes (34 native and 964 Python tests); the
runtime reference passes 326 assertions. [vr_v2_scene.py](vr_v2_scene.py.md) uses the current
production driver. [R's report](../docs/handover/VR-V2-R-report.md) records close-hand/prop images,
costs and the unmatched old absolute left-eye ghost threshold, alongside the better matched-control
result. No literal pass of that single-image threshold is claimed.

VR V2 task R is on v2r, with exported patches from the clone's vr2 branch. Patch 0072 declares
rtxvr_SetOverlayWindow and RTXVR_WINDOW_SHOW/NO_MIRROR in both API headers without changing version 3
or any structure. Patch 0073 completes compositor-free overlay-copy acknowledgement and SDK guards;
0074 implements the window source after 2D, capped to 1920 pixels wide, and mirror suppression over
black. Patches 0075 to 0078 add discontinuity-only depth coverage for reconstructed thin colour and
select a 0.4 m nearest guaranteed eye depth after 0.2 m, 0.3 m and the moving 0.35 m scene exceeded
the 1.0 ms warp budget. The recorded Index centre grows from 3072 x 2752 to 3112 x 2752 pixels,
1.3% more; API 3 remains. The physical Index currently has a different IPD; its extents are reported
separately from that recorded simulation descriptor.
The CPU reference has 274 assertions, including a reconstructed-colour ghost regression in both eyes.
The Index barrel widths are 284/284/282 pixels, preserving the accepted V1 silhouettes.
The final moving-ring Index captures reduce extra dark pixels from 709/836 to 153/183 at a mean
0.94 ms combined coverage/warp on the RTX 5090, with recommended 2468 x 2740 pixel eyes at 90 Hz.
See [the task report](../docs/handover/VR-V2-R-report.md) for current proof and integration
dependencies. Those initial experiments used -NoImport; the dated follow-up above records R's
single selected import and supersedes that initial package-provenance dependency.

[vr_v2_scene.lua](vr_v2_scene.lua.md) is the unshipped client probe fragment for R's controlled
thin features, held prop and window panel. The task report keeps the corresponding sources,
timings, image-analysis scripts and captures; the fragment is never loaded by an ordinary game.
Patch `0086-Keep-the-mod-loader-s-texture-reads-between-starts.patch` ([ADR 0195](../docs/decisions/0195-the-mod-loader-keeps-its-texture-reads-between-starts.md), [report](../docs/handover/mod-load-cache-report.md)) follows 0071 on `main`; the VR branches' 0072-0085 sort before it and touch none of its files. Built as `cfb2173b` on the 71 patches in `out/worktrees/mlc/rt` (a worktree of the fork clone made by `build_runtime.ps1`), exported alone (`format-patch -1 --start-number 86 --zero-commit`), then built and imported by `build_runtime.ps1`: `d3d9.dll` 418,398,720 bytes, SHA-256 `dfbc26d59a8a7da3d28bb04a282dd7973647316dab97e320abec5693e8ac8030`. `rtx_mod_texture_store.h` is self-contained; the Release gate compiles it with `tests/rtx/unit/test_mod_texture_store.cpp` from the patch (`test_mod_texture_cache.py`).

The second VR review adds patches 0065 to 0071, on the runtime branch `vr` at `d29445c5`
([report](../docs/handover/VR-V1-Q-runtime-review-report.md)). The warp searches near to far in inverse
depth, refines both surfaces bordering an interval and falls back to observed background at a disocclusion.
Its spacing follows the depth texture: 34 intervals at the Index's 1536 x 1376 pixel input. The normal
path has no saved tap setting; the launcher can override intervals for a controlled comparison.

Only a camera whose VR projection was latched in that frame and generation can produce eyes. The first
output also requires an actual camera-ring match: a queued flat view can already have the VR projection.
After that first match, the later counted fallback remains. A known
consumed camera is skipped while a different fresh pose is pending, with a separate diagnostic count;
a genuinely unknown camera retains the plan's counted newest-pose fallback. The module predicts without
waiting. Wire ABI 3 adds focus-loss and wait-error counters. Loss of focus skips an interval and can resume;
persistent RequestFailed errors stop after five seconds, and incompatible errors stop immediately.

VR allocations catch both DxvkError and standard exceptions and report RTXVR_E_RESOURCES. Eye images start
UNDEFINED and transition to GENERAL before storage writes. Only the render context observes overlay canvases,
timing records are bounded even without eligible frames, and capture requests remain pending until output.
The preset selects DLSS when supported and TAAU otherwise. Launcher-only allocation/focus probes exercise
the real render-thread failure/recovery paths; zero or unset leaves them disabled.

Startup independently requests two instance and four device names, six in total
([ADR 0157](../docs/decisions/0157-steamvr-requirements-do-not-depend-on-fsr.md)). The fourth device name is
VK_KHR_get_memory_requirements2; earlier builds got it only when the optional FSR DLL loaded. The old
five-name delta below belongs to the tested installation with that DLL present. No OpenVR load/init, VR
worker, VR GPU image/query allocation, preset or warp prewarm is added before Start. The device owns dormant
CPU state and enabled-name copies, and existing pipeline hooks do their inactive checks and FOV bookkeeping.
Tap and fault diagnostics are read only when VR initializes. Final selected binary/package identities and
the renewed flat/Index receipts are kept in the second-review report; experiments use -NoImport.

The startup correction is [ADR 0158](../docs/decisions/0158-the-first-headset-frame-must-match-its-camera.md).
The selected d3d9.dll is 418358272 bytes, SHA-256
`e43aef99a74d333fa75cbb27f8848ae7ba25ce4e8e200f5c7d0f936a69382046`. Final 310 s gm_construct and
120 s modern_house runs on the RTX 5090/Index at 90 Hz reached 85/30 frames/s with zero failed Submit
calls or unmatched poses. Mean warp brackets were 0.56/0.64 ms at the recommended 2468 x 2740 pixel
eye size; GPU utilization before launch was 0%/1%. Their original-scale crops and complete fine
profiles are in the report. The canonical package is the local runtime-review-final2 GMA named there.
Its -NoImport build has 249 CPU assertions. The physical look accepted 351 matched pairs with zero
unmatched poses; a controlled five-second metadata mismatch withheld 505 initial cameras, then accepted
2014 matched pairs. The superseded `2cbf7f0d` build had a physical first-frame fallback despite its correct FOV.
That build's Index acceptance used 310 s on gm_construct and 120 s on modern_house, with zero failed Submit
calls or unmatched poses. Under substantial background GPU load the new warp brackets averaged
1.98 ms and 2.65 ms respectively; these are not isolated shader costs. The report retains the
original-scale edge crops, fine pass timings, corrected flat controls and final local package identity.

Q's review follow-up adds patches 0062-0064: wire ABI 2, render-side Submit/WaitGetPoses,
compositor-epoch explicit timing, display scheduling feedback and consumed-pose exclusion.
The matching module predicts poses without waiting; V1 has no module serial wait. See the
[follow-up report](../docs/handover/VR-V1-Q-review-report.md) for five-minute A/B results and
the security/paused-lifecycle corrections. This follow-up's selected DLL is 418337280 bytes,
SHA-256 2a6aca62d0102b061fa27f433b4ccaa0bedbbee57f159150b71cc609b32fa249,
runtime clone vr at 9d22eef6, imported once after experimental NoImport builds.

VR-Q adds patch 0060: the renderer waits for the ready module's first camera, and only
produces one output for each fresh pose. The page installs the producer at SDK readiness;
BeginFrame can bootstrap while the renderer is STARTING. The shared version 1 header is unchanged
and the ordinary Python gate compares its bytes against the runtime patch series.
Patch 0061 keeps the VR projection/extent and last left-eye mirror through a completion timeout;
no duplicate Submit is made and no resize oscillation occurs while the producer waits.

VR-V1-C adds patches 0042 to 0059 ([task report](../docs/handover/VR-V1-C-report.md)). VR-Q imported
the combined build once: `vr` at `72f3cb83`, d3d9.dll 418332672 bytes, SHA-256
`66cbcc7c64f84b31e0e18de0e9644affbdfea31d3810d80d0ae6a7021786c52a`.
`base.json` records every packaged patch/dependency; no pending patch remains. Experimental
builds used `-NoImport`. All of this stays on the VR milestone branches pending review/approval.

The `rtxvr` C API is dormant until Start. A device-owned session uses the existing
runtime final-output image as a centre view at headset density, replaces only the main camera's
projection, gathers that picture through depth and each eye's full transform, submits on DXVK's
locked Vulkan queue, and crops the left eye into the original game target. Raster draws after
injection remain on the desktop. Unique-sized raster canvases feed independent OpenVR overlay
images. Captures save PNGs through asynchronous GPU readback; fine timestamp brackets report
lighting, upscaling, warp and preparation/raster/output work. The module owns OpenVR and supplies the pinned
v2.15.6 interfaces; the runtime neither loads its DLL nor starts a session.

The VR preset is DLSS Performance with Ray Reconstruction when supported, otherwise TAAU, with
one to four bounces, in one
fileless option layer above quality presets. Stop revokes OpenVR access
synchronously and removes the layer and VR allocations on the render thread, restoring the
ordinary output size even in a menu. The desktop present interval is zero during VR, without
changing the game's `mat_vsync`. No new saved option or menu control is introduced.

The initial late-activation build added five supported extension names at ordinary device creation:
`VK_KHR_external_fence_capabilities`, `VK_NV_external_memory_capabilities` (instance), and
`VK_KHR_timeline_semaphore`, `VK_KHR_dedicated_allocation`, `VK_KHR_win32_keyed_mutex` (device).
The final second-review build independently adds VK_KHR_get_memory_requirements2 as a fourth device
name; FSR supplied it in the original tested setup. The runtime already enables timeline-semaphore
functionality through Vulkan 1.2. No additional feature boolean, VR GPU resource, worker, OpenVR call
or warp prewarm is added to flat startup; dormant CPU state and hooks are described above. Start
checks SteamVR's complete lists against the actual enabled names, including provider additions.
See the report for measured flat startup and frame times and the spike evidence.

Review follow-up starts at 0055: pole-safe camera-basis matching, half-metre axial near-edge
coverage and fine GPU stages with command-list coverage. Periodic JSON and capture timings.json
separate application work, queue gaps and opaque SDK transfer spans. Those original profiling patches
kept wire version 1; the current second-review wire version is 3, as described above.
See the report for reset/loss behavior and measured follow-up results.

R26 adds `0041-Atmosphere-the-sky-without-a-horizon.patch`
([ADR 0139](../docs/decisions/0139-the-sky-without-a-horizon.md)): `rtx.atmosphere.noHorizon` (bool,
default False), for maps that float in the sky or in space. A view direction below the horizon gets
the sky instead of the ground-level haze the planet's sky gave it:

- **the air's gradient** of its mirror above (`noHorizonMirror` in `atmosphere_common.slangh`): the
  sky-view LUT's bake marches the mirror's air into the LUT's lower half, with the true direction's
  angle to the sun and moons for the phase terms (`evalAtmosphereRadiance`'s new `phaseDir`), so the
  sun's aureole stays around the sun;
- **the clouds and the high layer** of its antipode (`noHorizonCloudDir`): the screen-space cloud pass
  marches `-dir` for a pixel below the horizon (`marchCloudLayers`' new `phaseDirYUp` keeps the true
  direction for the clouds' phase), the high layer meets the antipode's shell, and secondary rays read
  the antipode's texel of the dome LUT. A mirror of the clouds read as a lake's reflection. Within
  0.0015 of the horizon the cloud ray is held just above it, so no line of bare sky is left. The
  cloud bleed fades out over the first 6 degrees below (a dome texel's silver lining belongs to its own
  direction);
- **what lies beyond the air** where it is: the stars and the night sky image without the horizon's
  fade (the airglow's boost toward the horizon is its mirror's), the moons and their glow lit through
  the air of their mirror. The sun disc keeps the time of day: below the horizon it is night.

`AtmosphereArgs::noHorizon` takes the former `r18Pad0` slot (the buffer keeps its size); it stays in the
sky-view LUT's key, and the transmittance/multiscattering and voxel-grid keys zero it. Off, every site
computes what it did before. The dev menu's No Horizon (Atmosphere) shows the option's description;
both are translated in the six catalogs, and `RtxOptions.md` is regenerated.

Built in `out/worktrees/r17/out/runtime-src` on 0040 (`3cb32fb8`) as `17dcc86c` (branch
`claude/r26-sky`), exported alone (`format-patch -1 --start-number 41`), then built and imported by
`build_runtime.ps1` (the tree checked against the base and the 37 patches, both compile passes):
`d3d9.dll` 418,258,944 bytes, SHA-256 `35ce500857c852e7babf0bd5a6fdc9495eef39703cfb2d4c33547c0bcec33054`,
build identity `remix-main+17dcc86c`; 61,618,824 bytes xz in Git LFS. No texture, buffer or new pass;
the DLL grows by 0.7 MB of shader code. PoC checks in [TESTING.md](../docs/TESTING.md) ("R26").

R20-E adds `0040-Publish-live-upscaling-state-for-startup-advice.patch`
([ADR 0123](../docs/decisions/0123-live-upscaling-readback.md)). The selected device publishes one
versioned atomic snapshot at `rtx.runtime.upscalingState`, through the existing
`remixapi_GetGameValue`; plugins cannot write the reserved `rtx.runtime.` namespace. Readiness waits
for startup graphics/DLSS presets and pending callbacks, is invalidated by dependent option edits and refreshed
at each present. The fixes' `RemixConfig.GetUpscalingState()` reads it for R20-B's startup hint.
Unit test: `test_upscaling_state` (also compiled from the patch by the aggregate Release gate).

**0040 is not yet in the imported `d3d9.dll`.** Its exact hash is in `base.json`'s `pending_patches`,
separately from unchanged packaged provenance. Integration imports one DLL with every reviewed R20
runtime patch; `build_runtime.ps1` clears the pending record on import. The guard accepts only
declared new suffix patches, never changes to packaged inputs. Pending patches still participate in
every source-tree/build check.
R20-D adds patches 0034 and 0035 ([report](../docs/handover/R20-D-report.md),
[ADR 0121](../docs/decisions/0121-source-effect-categories-for-the-session.md),
[ADR 0122](../docs/decisions/0122-raster-canvases-keep-their-native-draws.md)):

- Three NoSave GMod effect categories, joined with saved particle/decal tags, preserve Source
  effect vertex color and texture factors. Blended meshes retain their geometry.
- Non-primary raster canvases preserve native color/alpha write masks and blending before
  RTX-only rejection and after injection. Explicit ray-traced targets retain precedence.
- Premultiplied transmission filters use a private legacy blend value within the existing four
  GPU bits; zero-alpha backgrounds are transparent. The shared CPU/GPU opacity helper is used
  by every ray path. Dynamic effect alpha/filter draws do not use static opacity micromaps.
- The fallback introduced by patch 0012 now links the renamed project. The correction is in
  0034, without rewriting the historical patch series.

Built in the assigned R17 clone on `codex/r20-render`: a5251896 (0034), then 1d53ee00 (0035),
from 51cf1b8b. Existing recorded NVAPI/RTXDI and DLSS/SHARC state was preserved. Both new patches
were exported individually with git format-patch -1 and absolute output paths. The Release/Ninja
wrapper verifies the exact patch/dependency tree and runs both shader/embed passes; optimization 3,
release DLL CRT, Tracy/shim off, download_apics=false. No GPU record grows and no SDK binary changes.
The new headers are listed in src/dxvk/meson.build.

Final DLL: 417,502,720 bytes, SHA-256
`0c961bd62c758d0e2d716c0371c5a772f4fc0aeaf760e5f723df82ea9522968e`, build identity
`remix-main+1d53ee00`. Imported once after visual acceptance through tools/inputs.py import;
base.json records all 35 patches. Dedicated test_gmod_effects covers category lifetime/snapshots
and the filter equation; the existing runtime suite was rebuilt in its separate unit configuration.
Evidence is in the R20-D worktree's out/r20d/runtime-filter-* and runtime-import-* receipts.

The R20-Q follow-up narrows dirty notifications to **19 option objects** registered by
`RtxInitializer`: selectors, upscaler/graphics presets and their upscaling/FG inputs and outputs.
Sky/weather/effect/category writes leave readiness intact. Device ownership and publication locks
are unchanged; genuine dependent edits and failed convergence remain unready. `test_upscaling_options`
exercises actual option writes/callbacks: 20,100 unrelated writes with intervening reads, selector/preset
transitions and failed convergence. Run it beside `test_upscaling_state` in `_CompUnitTest_x64`.
The re-exported **single 0040** still applies to `51cf1b8b`; its new hash is in
`base.json.pending_patches`. The test DLL remains unimported.

Follow-up source commit: `d9aba9be` on `51cf1b8b`; local `-NoImport` DLL SHA-256
`7fb71c9e745949df43750ff6d3f57cc379086aede87521778becd29510ce9ab6`. The dedicated runtime units
pass. With Q's merged companion and advancing sky, all 3,512 steady timer reads are ready, with
3,517 sun writes and zero unrelated invalidations; including selector transitions, readiness is
99.97%. See the [follow-up report](../docs/handover/R20-E-report.md) and `out/r20e-followup` receipts.

R19 adds `0033-Bound-the-DDS-readers-and-fix-the-review-s-other-run.patch`
([report](../docs/handover/R19-R-report.md)), the runtime's findings of the pre-release review
([R19-review.md](../docs/handover/R19-review.md)):
- **The DDS readers (H1).** A DDS file in any loaded mod could corrupt the game's memory: the partial
  loader wrote one size per mip level into a table of 16 whatever count the header gave, and GLI's
  fallback copied as many bytes as the header claimed from a buffer as large as the file. Both now check
  the headers with `gli::detail::dds_check_layout` (`include/gli/core/load_dds.inl`) before they read the
  data: a format GLI knows, sides of 1 to 65536, at most 16 levels and no more than the sides allow (a
  count of 0 reads as 1), at most 2048 layers, 1 to 6 cube faces, and 64-bit sizes with overflow checks
  that fit in the file (a volume's levels count their depth). The partial loader
  (`rtx_dds_file_parser.h`) also measures the file in 64 bits, checks every read, places nothing for a
  subresource the file lacks and maps only a file that still holds the checked data; GLI's reader
  refuses empty, short and unmeasurable files, and the fallback reads DDS only. Unit test:
  `test_dds_reader`.
- **String options read beside the render thread (F-01).** `RtxOption::getCopy()` copies a value under
  the update mutex. The menus' string reads use it (text boxes, the texture menu's legacy-emissive and
  thin-wall strings, the capture name, the language), and the fallback-mod list.
- **A texture the cache shares takes the strongest preload of its users (F-03)**, at its next draw
  (`PreloadStrength` in `rtx_texture_budget.h`).
- **The middle deck (F-04, F-05).** Its patch mask is probed along the ray at most a quarter of a patch
  apart (3 to 16 probes), and its moon-shadow taps read the mask where they are.
- **Config (R-01, R-03).** A file saved through a link keeps its previous contents in a backup until the
  rewrite completes; the float parser refuses NaN and infinities. `rtx.gmod.eyeWhiteBrightness`'s
  description says it scales all scene-adaptive emission (R-02).

No option, texture or buffer is added. Built in `out/worktrees/r17/out/runtime-src` on 0032 (`e095f29a`),
as `248fa6ee`, whose author was then corrected to the fork's git identity: `51cf1b8b`, the same tree
(branch `claude/r19-review-fixes`). The stored `d3d9.dll` reports `remix-main+248fa6ee`.

R18 adds `0032-Atmosphere-thin-decks-a-middle-deck-of-its-own-sun-d.patch`
([ADR 0110](../docs/decisions/0110-thin-decks-a-middle-deck-of-its-own-ice-arcs-a-milky-haze-and-twilight.md),
[report](../docs/handover/R18-report.md)), R17's limits:
- **Thin decks close.** `nvdfProfileDepthKm` is a weather field; overcast, drizzle and fog draw 0.9, 0.6
  and 0.45 km decks at 0.25, 0.18 and 0.15 km, drizzle and fog baked at a cover of 2. The shape
  displacement (`nubis3ShapeVarietyKm`) shrinks with the profile depth, all of it at 0.6, none at 0.1.
- **The middle deck has a cover of its own.** A 2D patch mask (`cloudLayer2PatchSizeKm`, 14 km), read
  at the ray's entry, middle and exit through the deck, is the sampler's cover against a nominal of 1. The
  deck reads layer 1's body field `cloudLayer2FieldScale` times finer (cloudlets of
  `cloudLayer2CellSizeKm`, 0.5 km), and a ray that meets no patch marches nothing.
- **Plate-crystal halos** on the high layer (`cirrusArcStrength`): the sun dogs and the circumzenithal
  arc, for the sun and moon 0, and the 46 degree halo with the 22 degree one.
- **A milky haze.** The weather fields `aerosolAbsorption` (a scale on `mieAbsorption`) and
  `mieAnisotropy`; hazy has 0.12 and 0.8.
- **The twilight** keeps the sky LUT whole to half of `twilightFadeDepth` (16 degrees) and fades it out
  over the other half.

No texture or buffer is added; `AtmosphereArgs` grows by one 16-byte row. Built in
`out/worktrees/r17/out/runtime-src` on 0031 (`80c4a8cb`), as `e095f29a`.

R17 adds `0031-Atmosphere-cloud-genera-per-weather-a-sun-disc-and-a.patch`
([ADR 0109](../docs/decisions/0109-cloud-genera-per-weather-a-sun-disc-and-a-high-cloud-layer.md),
[report](../docs/handover/R17-report.md)). Each weather owns its cloud genera through fifteen new
weather fields, and its presets map to them:
- the low layer's base, edge billows, cell size and bake cover (`nvdfNominalCoverage`, a step; above 1
  a closed deck);
- the middle deck;
- the high layer's cover, kinds and optical depth.

Numos also draws the sun's disc for the camera. A 2D high cloud layer at 9 km adds fibrous cirrus, a
cirrostratus veil with the 22 degree halo and cirrocumulus grains. Cost at 3840x2160: the high layer
nothing measurable, the middle deck 0.3-1.2 ms where drawn. Built in
`out/worktrees/r17/out/runtime-src` on 0030 (`9907d412`), as `80c4a8cb`.

R13-F adds `0030-Load-material-preloads-at-their-first-draw-instead-o.patch`
([ADR 0103](../docs/decisions/0103-material-preloads-load-at-their-first-draw.md),
[report](../docs/handover/R13-F-report.md)): a USD material's `preload_textures` no longer loads every
mip of every texture when its mod loads. Such a texture starts at its smallest mips, as a streamed
texture does. The first `addTexture` of it (the frame an instance first draws the material) pins it and
stages every mip synchronously; the upload goes with that frame's others in
`submitTexturesToDeviceLocal`, before the scene is built and traced, so the frame that first draws the
material already samples the whole chain. From then on it is a preload as before, and patch 0026's
pressure rule still releases it while undrawn. A material drawn in the frame its mod loaded may find the
upload of its smallest mips still waiting: that upload is replaced by one of every mip, in the same
frame; a texture whose load is on the worker thread is finished synchronously by the next frames.
Textures too large to stream, the Remix API's and dome lights' preloads, and everything while
`rtx.texturemanager.neverDowngradeTextures` is on load whole with the mod.
`rtx.texturemanager.preloadOnFirstDraw` (default True) turns it off for materials loaded afterwards.
`[RTX Preload]` log lines report each frame with first draws: textures, bytes, staging time, and what
still waits. Rule and unit check: `preloadWaitsForFirstDraw` in `rtx_texture_budget.h`,
`test_texture_budget_pressure`. Measured as 0029 on 0028 (`claude/r13-first-draw`), then cherry-picked
onto R13-D's 0029 (`claude/r13-option-lock` a816a673) as branch `claude/r13-first-draw-0030` in
`out/worktrees/r10-eyes/out/runtime-src`, which built the packaged DLL.

R13-D adds `0029-Lock-RtxOption-edits-made-beside-the-render-thread-s.patch`
([report](../docs/handover/R13-D-report.md)): whatever reads or writes an option's layer values or
the dirty option map holds the update mutex (the rule is at `getUpdateMutex()` in `rtx_option.h`).
`readOption`, which `remixapi_SetConfigVariable` calls on the game's thread, and
`clearFromStrongerLayers` take it; `acquireLayer` and `releaseLayer` take it after the layer mutex, as
`applyPendingValues` does; the Remix menu, which draws on the game's thread, takes it for Discard
Changes, saving, Delete All, the migrations and its unsaved and misplaced counts, and holds the layer
mutex over its Option Layers list. `applyPendingValues` keeps the lock between its passes unless a
callback runs, and up to its final clear, so an edit from another thread is resolved in this frame or
the next instead of being dropped. Stress test: `test_rtx_option_threads`.

R13-B adds six patches ([ADR 0100](../docs/decisions/0100-one-copy-and-idle-release-of-game-textures.md),
[report](../docs/handover/R13-B-report.md)):

- `0023-Log-host-memory-by-memory-type-mapping-and-purpose-i.patch`: the opt-in census
  (`rtx.profiler.memory.requestSnapshot`) also writes `[RTX Host Memory]` rows, with or without the
  memory profiler: each memory type's chunks and dedicated allocations, the address range of each
  host-visible memory object, the process counters and the committed address space by protection with
  the part DXVK's mappings cover. Allocation groups gain the memory flags they received, whether the
  application released the image while the renderer holds it, and the allocation's name.
  [host_memory_census.py](../tools/qa/host_memory_census.py.md) reads them.
- `0024-Keep-one-copy-of-managed-GMod-textures-and-release-i.patch`: for patch 0022's class (static
  managed 2D textures), `d3d9.releaseManagedHostCopies` (`DXVK_RELEASE_MANAGED_HOST_COPIES`; Auto, the
  gmod.exe default, is on below 28 GiB of RAM or 15 GiB of VRAM) frees a texture's CPU copy once its
  image holds the data and it was not locked for 10 presented seconds; a later lock reads it back
  first. `d3d9.managedTextureBudgetMiB` (`DXVK_MANAGED_TEXTURE_BUDGET_MIB`; -1, the gmod.exe default,
  is VRAM / 4; 0 off) releases images not drawn for 60 presented seconds, least recently used first,
  while the class holds more than the budget; the data stays (read back first when needed), the next
  use uploads it again with the same hash, and Remix frees a released image once no instance samples it.
  Other games keep both off. The resolved values are logged at startup; `[RTX Managed Textures]` lines
  report the passes and the CPU copy bytes. Policy and unit test: `src/d3d9/d3d9_managed_memory.h`,
  `test_managed_texture_memory`. The texture copy buffers are named `d3d9 texture copy`.
- `0025-Let-replacement-textures-give-way-under-real-VRAM-pr.patch`: under real pressure (within 2 %,
  at least 256 MiB, of the driver's live budget, or over it) the replacement texture budget stops growing
  or gives back the overflow plus that margin, whatever the configured percentage or fixed budget; with
  the margin free nothing changes. `[RTX Texture Budget]` lines report it. Rule and unit test:
  `src/dxvk/rtx_render/rtx_texture_budget.h`, `test_texture_budget_pressure`.
- `0026-Let-undrawn-preloaded-material-textures-give-way-und.patch`: a USD material's
  `preload_textures` pins its textures at every mip from the moment the mod loads, and the budget (with
  patch 0025's cap) never touches pinned textures. Under the same real pressure, a preloaded texture no
  instance has drawn for 10 seconds now gives way and drops to its smallest mip; when an instance draws
  it again it is pinned and loaded whole again. Under pressure the streamed textures also get 0025's
  limit less what pinned ones hold. While memory is free nothing changes; dome lights, textures too
  large to stream and `rtx.texturemanager.neverDowngradeTextures` stay pinned. `[RTX Texture Budget]`
  lines report the pinned bytes and count the releases and restores. Rules and unit test:
  `preloadPinChange` and `streamedTextureLimitMib` in `rtx_texture_budget.h`,
  `test_texture_budget_pressure`. For tests, `DXVK_TEXTURE_PRESSURE_TEST_BUDGET_MIB` caps the budget
  these rules see (a warning in the log when set); on a large card WDDM pages a background process's
  memory before it lowers the game's budget, so real pressure is hard to make there.
- `0027-Count-what-creates-deferred-managed-GMod-texture-ima.patch`: the `[RTX Managed Textures]` line
  counts the deferred images (and bytes) that sampling, a view, a flushed upload, `PreLoad` and a
  draw's upload created, so a burst shows which call made it. Diagnostics only.
- `0028-Fix-a-hash-race-baker-sources-and-unmarked-writes-of.patch`: the review's fixes. A
  memory-managed texture keeps its hash in an atomic that the hash API and `GetStableHash` read, so a
  caller on another thread (ToPBR from Lua) never races the image release; a texture tracked through
  `addTexture` in the last frames counts as in use, so the terrain baker's preloaded sources do not give
  way; a writable lock with `D3DLOCK_NO_DIRTY_UPDATE` keeps the CPU copy for good; and with neither
  option on (other games) the once-a-second pass and its log do not run. Unit checks in
  `test_managed_texture_memory` and `test_texture_budget_pressure`.

The [GPU probe](../tools/qa/build_managed_texture_probe.ps1.md)'s `r13` sequence proves exact pixels and
hashes through upload, released copies, read-back locks, a rewrite, image release, re-upload and a
device reset, against the original runtime.

R12-C patch `0022-Allocate-unused-managed-GMod-textures-only-on-GPU-us.patch` defers GPU backing
for unused static 2D managed GMod textures ([ADR 0096](../docs/decisions/0096-demand-loaded-character-classification-and-memory-census.md)).
The model catalog and CPU buffers remain ready; sampling, upload or `PreLoad` creates the original
image without changing its format/mips/hash. `d3d9.deferManagedTextures` defaults on for `gmod.exe`
only, with an explicit config or `DXVK_DEFER_MANAGED_TEXTURES` override. Other pools/types/usages,
conversion formats and `evictManagedOnUnlock` keep their existing paths. The shared initializer
preserves zero contents and queues a deferred clear before the upload on the same command stream.
The [GPU probe](../tools/qa/build_managed_texture_probe.ps1.md) compares allocation, exact pixels,
LOD, partial writes and original/new texture hashes. See the [R12-C report](../docs/handover/R12-C-report.md).

R12-C adds `0021-Log-opt-in-allocation-census-with-D3D9-size-format-a.patch`
([ADR 0096](../docs/decisions/0096-demand-loaded-character-classification-and-memory-census.md)).
Enable the existing memory profiler at process launch with `RTX_PROFILER_MEMORY_ENABLE=1`, then
request `rtx.profiler.memory.requestSnapshot = True` through the Remix API. On the next present it
resets that NoSave request and logs `[RTX Allocation]` begin/group/end JSON rows, with actual live
allocation slices grouped by category/type/locality, dimensions, Vulkan format and D3D9
pool/format/mip count (primary and resolve images). Pool `-1` means unavailable. It keeps images
still held by the renderer visible after the application's D3D9 texture is released. The registry
copy/update lock protects diagnostic metadata; grouping and log I/O happen after releasing it.
No hashes, resource contents or allocation/eviction policy change. The ordinary profiler remains
disabled. See [the parser](../tools/vram_census.py.md) and [Source probe](../tools/qa/vram_probe.lua.md).

R10-E adds `0019-Keep-imported-eye-white-emission-on-isolated-surface.patch`
([ADR 0088](../docs/decisions/0088-imported-character-eye-whites.md)). NoSave proxy/original texture
aliases isolate automatic emission to named eye-white surfaces; original PBR replacements retain
precedence. A NoSave brightness multiplier scales automatic and C-16 authored adaptive emission
through the existing luminance helper, preserving the saved adaptive scale. Its runtime unit test
covers alias validation, isolation, material inputs, C-16 normalization, brightness and option
lifetime/invalidation. R10-E builds with `-NoImport`; the committed packaged record intentionally
remains at patches 0001–0018 until Claude imports the reviewed DLL.

The new source files in 0019 are `src/dxvk/rtx_render/rtx_eye_whites.h` (strict aliases,
revisioned snapshots and automatic material inputs) and `tests/rtx/unit/test_eye_whites.cpp`.
Existing D3D9/external category snapshots preserve original atlas alpha/normal tags for proxy draws.

This repository's changes to the RTX Remix runtime ([ADR 0033](../docs/decisions/0033-one-repository-package-inputs-in-git-lfs.md)).
The runtime is the GMod fork of NVIDIA's DXVK-Remix, `sambow23/dxvk-remix-gmod`. Its source, with
NVIDIA's SDKs, is about 3.6 GB and keeps its own history, so this repository holds:

- [`base.json`](base.json): the fork's commit the patches apply to (`gmod-numos3` at `c6b48ed1`); what
  else the build has that the fork's tree does not record ([ADR 0034](../docs/decisions/0034-the-runtimes-build-inputs-recorded.md),
  [RESEARCH.md](../docs/RESEARCH.md) section 31): `submodules` built at another commit or with a patch
  (NVAPI R615; RTXDI with the fork's uncommitted changes) and `clones` the build reads (the DLSS SDK,
  SHARC); and `packaged`, the SHA-256 of the `d3d9.dll` the RTX package ships with what it was built
  from, which [`tools/check_repo.py`](../tools/check_repo.py.md) holds `runtime/` to;
- [`submodules/`](submodules): patches of submodules (`git diff HEAD --binary --full-index` in the
  submodule), named by `base.json`;
- [`patches/`](patches): this project's commits on top of it, as `git format-patch` files, applied in
  name order:

| Patch | What |
|---|---|
| `0001-Snapshot-...` | The fork's `gmod-1.6.1` working tree during its remix-1.6.1 merge, which the rest was built on |
| `0002-Translate-the-Remix-menus-...` | The Remix menus (Alt+X) in zh-CN, zh-TW, ja, ko, fr and ru ([RESEARCH.md](../docs/RESEARCH.md) section 25) |
| `0003-i18n-the-translators-glossaries` | The translators' glossaries |
| `0004-Atmosphere-...` | The real Moon, the night sky image, lunar and solar eclipses, and `dxvk.numCompilerThreads < 0` ([ADR 0032](../docs/decisions/0032-real-moon-stars-eclipses-and-fog-presets.md), RESEARCH.md section 29) |
| `0005-i18n-...` | Complete weather display translations and formatted status, clearer cache names, strict catalog checks and tests; dependency setup tolerates `!` in paths |
| `0006-i18n-...` | Static translated migration buttons with separately formatted counts; regression coverage for both migration directions |
| `0007-Keep-view-models-...` | First-person arms/weapons remain enabled independently of primary-space player bodies ([ADR 0043](../docs/decisions/0043-player-body-viewmodel-and-shadows.md)) |
| `0008-Save-Remix-config-...` | Atomic checked config saves; failed saves retain their baseline/unsaved state and failed reloads retain live values ([ADR 0044](../docs/decisions/0044-remix-settings-persistence.md)) |
| `0009-Default-diagnostics-...` | Explicit saved diagnostic consent, legacy SDK archival, twelve-second welcome timeout and permanent dismissal ([ADR 0045](../docs/decisions/0045-diagnostic-consent-and-welcome.md)) |
| `0010-Resolve-layered-alpha-...` | Reject cutouts during ray traversal in query/trace/PSR/indirect paths, refresh cached opacity flags, and ignore incompatible outline meshes ([ADR 0047](../docs/decisions/0047-ignore-incompatible-model-outlines.md), [ADR 0048](../docs/decisions/0048-layered-alpha-cutouts.md)) |
| `0011-Keep-imported-model-...` | Join transient imported-model smooth-normal tags with the saved set on D3D9, cached-draw and external submission paths ([ADR 0049](../docs/decisions/0049-importer-normals-material-labels-and-motion-access.md)) |
| `0012-Read-localized-project-...` | Load bounded editable startup templates and their font glyphs; point launch text to this repository ([ADR 0050](../docs/decisions/0050-startup-text-and-main-menu-diagnostics.md)) |
| `0013-Default-to-minimum-...` | Default path bounces to 1/12 consistently across graphics presets and option metadata ([ADR 0051](../docs/decisions/0051-path-bounce-defaults.md)) |
| `0014-Never-save-over-unread-...` | A missing user.conf/rtx.conf reloads as empty, so Discard Changes works on a fresh profile; a file that exists but could not be read blocks Save, export and the diagnostic choices until it is read; saves retry briefly held files, rewrite links in place and show failures; the outline rule spares view models, mirrored geometry and replacements with their own culling ([ADR 0044](../docs/decisions/0044-remix-settings-persistence.md), [ADR 0047](../docs/decisions/0047-ignore-incompatible-model-outlines.md)) |
| `0015-Record-GPU-memory-...` | Share the bounded VRAM collector with heap locality, driver totals and category snapshots at cuts, five-minute intervals and device loss; log the escaped queue reason first, then flush/replace `last_gpu_crash.json` through a per-process temporary with two brief retries, before the crash recorder, Aftermath and Sentry; rate-limit OMM warnings, report free VRAM/previous budget/use/thresholds at a budget drop and preserve pending counts at loss; record the six test sources omitted from the fork snapshot, without silent guards ([ADR 0065](../docs/decisions/0065-runtime-memory-diagnostics.md)) |
| `0017-Apply-scoped-MMD-alpha-...` | Join saved and transient Model Hotloader texture tags, use an exact default-0.5 cutout reference, and promote blended coverage at the cutoff in shared ray/OMM evaluation; include cutoff/category in OMM identity and material-history invalidation ([ADR 0081](../docs/decisions/0081-mmd-alpha-texture-category.md)) |
| `0018-Keep-denoiser-history-...` | Mark an instance's material as changed for the MMD alpha rule only between the first draws of consecutive frames, never for a new instance; patch 0017 compared the merged in-frame state and discarded tagged characters' denoiser history every frame (R8) |
| `0020-Rank-generated-fallback-mods-...` | Mods named in `rtx.gmod.fallbackMods` (default `~gmod_topbr`, the fixes' ToPBR output) get priority 1: every authored mod wins over them for materials, meshes and lights whatever its folder name, also when it loads or reloads later, and their search paths come first ([ADR 0092](../docs/decisions/0092-generated-fallback-mods-rank-last.md)) |
| `0021-Log-opt-in-allocation-census-...` | The opt-in allocation census with D3D9 size, format and pool ([ADR 0096](../docs/decisions/0096-demand-loaded-character-classification-and-memory-census.md)) |
| `0022-Allocate-unused-managed-GMod-...` | Static managed GMod textures get GPU memory only on first use ([ADR 0096](../docs/decisions/0096-demand-loaded-character-classification-and-memory-census.md)) |
| `0023-Log-host-memory-by-memory-type-...` | The census also accounts host memory: memory types, host mappings, the process and its address space ([ADR 0100](../docs/decisions/0100-one-copy-and-idle-release-of-game-textures.md)) |
| `0024-Keep-one-copy-of-managed-GMod-...` | One copy of each static managed texture, and idle images released over a budget; automatic for gmod.exe ([ADR 0100](../docs/decisions/0100-one-copy-and-idle-release-of-game-textures.md)) |
| `0025-Let-replacement-textures-give-way-...` | Replacement textures stop growing near the driver's live budget and give back the overflow over it ([ADR 0100](../docs/decisions/0100-one-copy-and-idle-release-of-game-textures.md)) |
| `0026-Let-undrawn-preloaded-material-textures-...` | Under the same pressure, preloaded material textures no instance draws drop to their smallest mip, and are preloaded again when drawn ([ADR 0100](../docs/decisions/0100-one-copy-and-idle-release-of-game-textures.md)) |
| `0027-Count-what-creates-deferred-...` | The managed texture log counts what created each deferred image: sampling, a view, a flushed upload, `PreLoad`, a draw ([ADR 0100](../docs/decisions/0100-one-copy-and-idle-release-of-game-textures.md)) |
| `0028-Fix-a-hash-race-baker-sources-...` | The review's fixes of 0024 and 0026: an atomic stable hash for the API, the terrain baker's sources count as in use, `D3DLOCK_NO_DIRTY_UPDATE` keeps the CPU copy, no pass in other games ([ADR 0100](../docs/decisions/0100-one-copy-and-idle-release-of-game-textures.md)) |
| `0029-Lock-RtxOption-edits-made-beside-...` | Option layer values and the dirty option map change only under the update mutex: the Remix API, graph layers, the menu, migrations; an edit from another thread is never dropped at the end of a frame ([R13-D report](../docs/handover/R13-D-report.md)) |
| `0030-Load-material-preloads-at-their-first-draw-...` | A material's `preload_textures` loads at its first draw, whole, before that frame renders, instead of when the mod loads; `rtx.texturemanager.preloadOnFirstDraw` ([ADR 0103](../docs/decisions/0103-material-preloads-load-at-their-first-draw.md)) |
| `0031-Atmosphere-cloud-genera-per-weather-...` | Cloud genera as weather fields (low layer base, billows, cell size and bake cover, the middle deck, the high layer), presets mapped to genera; the sun disc; a 2D high cloud layer (cirrus, cirrostratus with its halo, cirrocumulus); the galaxy and nebula after astronomical twilight ([ADR 0109](../docs/decisions/0109-cloud-genera-per-weather-a-sun-disc-and-a-high-cloud-layer.md)) |
| `0032-Atmosphere-...` | R17's limits: a profile depth per weather so thin stratiform decks close; the middle deck's own patch mask and cloudlet size; sun dogs, the circumzenithal arc and the 46 degree halo; the aerosol's absorption and phase per weather (a milky haze); the twilight kept to 8 degrees down ([ADR 0110](../docs/decisions/0110-thin-decks-a-middle-deck-of-its-own-ice-arcs-a-milky-haze-and-twilight.md)) |
| `0033-Bound-the-DDS-readers-...` | The pre-release review's runtime findings: both DDS readers check a file's headers against the file before reading it; string options copied under the update mutex beside the render thread; a shared texture takes its users' strongest preload; the middle deck's patch probes and moon-shadow taps; config saves through links and non-finite floats ([R19-R report](../docs/handover/R19-R-report.md)) |
| `0040-Publish-live-upscaling-...` | Runtime-owned atomic effective upscaling/frame-generation state and capabilities, gated on presets and callback convergence, for the native startup hint readback; pending the combined R20 runtime import ([ADR 0123](../docs/decisions/0123-live-upscaling-readback.md)) |
| `0041-Atmosphere-the-sky-without-...` | `rtx.atmosphere.noHorizon`: below the horizon the mirror's sky gradient, the antipode's clouds and high clouds, the true angle to the sun for every phase term, the stars and moons where they are ([ADR 0139](../docs/decisions/0139-the-sky-without-a-horizon.md)) |
| `0086-Keep-the-mod-loader-s-texture-reads-...` | The USD mod loader keeps each texture file's DDS headers and five smallest mips per mod in `rtx-remix\cache\mod-textures` and uses them while a folder listing shows the file unchanged (size, write and change times, file id), so a later start opens no texture file; `rtx.initializer.modTextureCache`; `[RTX Mod Load]` timing lines ([ADR 0195](../docs/decisions/0195-the-mod-loader-keeps-its-texture-reads-between-starts.md)) |
| `0090-Atmosphere-the-Moon-by-day` | The moons by day: a moon's light added to the sky in front of it, its disc hiding only what lies beyond; by day the real Moon's phase law times `rtx.atmosphere.daytimeMoonBrightness`, the night's look kept; no disc below the horizon unless `noHorizon` ([ADR 0207](../docs/decisions/0207-the-moon-by-day.md)) |
| `0091-Core-fixes-the-pipeline-handle-race-...` | Upstream dxvk-remix `c1a891bf85` (MIT): the pipeline handle read under the pipeline's lock (graphics, and compute too), a finished command list recycled before its waiters wake, frame generation's duplicate acquire-semaphore waits removed ([ADR 0216](../docs/decisions/0216-the-runtimes-pipeline-handle-race-and-in-present-message-dispatch-fixed.md)) |
| `0092-Reflex-no-sent-message-is-dispatched-...` | The Reflex latency ping inside Present peeks only while `GetQueueStatus` shows a posted message and no sent one (`PM_REMOVE \| PM_QS_POSTMESSAGE`): no window procedure runs mid-frame ([ADR 0216](../docs/decisions/0216-the-runtimes-pipeline-handle-race-and-in-present-message-dispatch-fixed.md)) |
| `0093-Merge-upstream-dxvk-remix-main-...` | NVIDIA's dxvk-remix `main` of 2026-11-14 (`remix-1.6.1..2b46bed0c`, 57 commits): RTXDI `dc8eb03` with the fork's volumetrics, Remix API 0.1000.2 with upstream's additions after the fork's, the fork's GPU bits kept and upstream's moved, `usdg.dll` beside `d3d9.dll` ([ADR 0218](../docs/decisions/0218-the-runtime-follows-upstream-dxvk-remix-main.md)) |
| `0094-DLSS-frame-generation-keeps-the-UI-...` | DLSS Frame Generation gets the frame before its UI (NGX's HUD-less colour): a copy of the back buffer filled at injection, blitted beside each frame generation back buffer with the back buffer's own blit, passed for each frame that filled it, so the crosshair and the HUD stay in place in the generated frames ([ADR 0223](../docs/decisions/0223-frame-generation-gets-the-frame-before-its-ui.md)) |
| `0106-Merge-upstream-dxvk-remix-main-...` | NVIDIA's dxvk-remix `main` of 2026-11-23 (`2b46bed0c..58ac72412`, 25 commits): VRAM pressure crash fixes, the merged BLAS transform fix, view-model SSS, fewer draw-path locks, the GH:1112 revert; Remix API 0.1000.3 with upstream's GPU-resident scene functions after the fork's; upstream's view-model bit at texture flag bit 31 ([ADR 0265](../docs/decisions/0265-the-runtime-merges-upstream-main-of-2026-11-23.md)) |

- [`build_runtime.ps1`](build_runtime.ps1.md): applies them in a worktree of a fork clone, builds, and
  stores the new `d3d9.dll` in [`packages/runtime`](../packages/README.md).

Patch `0016-Add-scene-adaptive-opaque-emission` adds optional `emissive_adaptive_intensity`
([ADR 0067](../docs/decisions/0067-scene-adaptive-emission.md)). The geometric-mean scene Yf and
paired exposure use a three-slot, nonblocking readback ring (eligible after two frames), then the
shared raytracing constants. The half-float material input occupies the unused high subsurface-index
byte and constant DLSS-alpha byte; the 64-byte material record stays unchanged, and input zero
preserves its previous bytes. Both opaque and Source-eye evaluation use the new intensity helper;
already evaluated interactions keep their radiance. Texture preload preserves the new USD value;
public API materials and baked terrain retain a zero adaptive input.

The feature defaults on for positive inputs; `rtx.adaptiveEmission.scale` defaults to 1,
`minLuminance` to 0, `maxLuminance` to 64, and `fallbackLuminance` to 0.18. Fallback is used when
auto exposure is off or before a completed readback exists. The zero lower clamp permits fading
in darkness. `[RTX Adaptive Emission]` logs the raw Yf, paired exposure, effective luminance,
sample frame/age, scale and enablement at cuts and five-minute intervals. These are the real
geometric mean and smoothed exposure; transition brightness is still affected by exposure's
0.15/0.75-second integrator. The combined package's only `AperturePBR_Opacity.mdl` lives in the fixes
part's breakable-glass assets, and declares the input with default 0 and range 0..65504; the runtime
part itself has no MDL. Its MDL preview retains fixed emission.

The built runtime itself, `d3d9.dll` and NVIDIA's DLLs, lives in `packages\runtime\files` (Git LFS), so
building the RTX package needs neither the fork nor its SDKs. Only a change to the runtime does.

## Changing the runtime

R7-A's branch build is deliberately **not imported**: the task forbids package edits.
Its new DLL, source identity, additional USD schema resource and test/provenance gate status are
recorded in the [R7-A report](../docs/handover/R7-A-report.md). Until Claude imports it during
integration (or separately approves unimported-build validation), the existing repository
provenance convention rejects patch 0017 against the older `packaged` record.

1. Make the change in the fork worktree `build_runtime.ps1` uses (or any tree at `base.json`'s commit
   with the patches applied), and commit it there.
2. Export the series again into `patches\`, replacing the old files:
   `git -C <worktree> format-patch --binary --no-signature --zero-commit -o <this repo>\runtime\patches <base commit>..HEAD`
3. `runtime\build_runtime.ps1 -Fork <clone>`: it checks that the worktree is exactly what `base.json`
   and these patches describe, builds, imports `d3d9.dll` and writes `packaged` in `base.json`. Then
   build the package (`tools\build_package.py`), test it in the PoC, and commit on a branch. Until the
   DLL is built and stored again, `tools\test.ps1` fails on a changed patch.

An existing source tree needs a configured Release/Ninja build with optimization 3, the release DLL
CRT, Tracy/shim off and `download_apics=false`. A missing `meson-private/coredata.dat` or mismatched
saved options stop the wrapper before setup, compilation or import. A newly created source worktree
is configured once with those settings through `python -m mesonbuild.mesonmain setup`, after
`Enter-VsDevEnv`; its first setup does not compile runtime targets before the wrapper's two shader
passes. See [the build script's instructions](build_runtime.ps1.md) for explicit offline setup.

A new base (the fork moved on): rebase the series there, export it again, set `commit` in
`base.json`, and rebuild. NVIDIA's DLLs change only with the fork's SDKs; import those from the fork
build's `_output` folder with `tools\inputs.py import runtime --root "<_output>=files"` (without
`--prune`, which would drop `files\atmosphere`).

## R6 T4 rebuild (2026-10-31)

- Source: base `c6b48ed1` plus patches 0001-0015; second-review fix commit
  `024a98665149e628db827cd0f9ce142828c14701` in the isolated `out/runtime-src` clone;
  verified tree `d6516436af1cabf354059b1ba4a8841550236eee`.
- Build: x64 Release, MSVC 19.44.35228, Meson 1.12.1, Ninja with four jobs, Tracy/shim off and
  `download_apics=false`. `build_runtime.ps1 -Fork <own clone> -Worktree <own clone>` reconfigured
  and ran both compile passes once with all review fixes. Saved Meson options and the diagnostics
  compile command verify optimization 3 and `/MD /O2 /DNDEBUG`. The DLL labels itself
  `remix-main+024a9866`.
- `d3d9.dll`: 395,540,480 bytes, SHA-256
  `c40f28e4371f7525dce01afad7316ae3efeabb2099c7ec19fe1df5dc3706ac19`.
  `base.json` records its source/patch hashes. The two shipped USD plugin DLLs are byte-identical
  to the existing inputs and were not imported again; only the changed DLL consumes new LFS storage
  (58,336,968 bytes compressed).
- No downloads: the already prepared clone has the recorded submodules/clones. SDK junctions point
  only to the declared versions in `H:/packman-repo/chk`. A process-local
  `PM_MODULE_DIR_EXT=out/tmp/offline-packman` resolver validates every package/link instead of
  invoking Packman's network/bootstrap code. Its Python and the compiler were already installed.
- The dedicated `_CompUnitTest_x64` build passes all 27 tests, including `test_memory_diagnostics`
  with a stale fixture. Patch 0015 now records the five omitted unit sources and the medium API app
  byte-for-byte from the user's staged fork index, without guards. All six compile; the five unit
  sources run in the suite. The medium API app is a separate GPU app and was not launched.
  Unit dependency staging used literal-path
  PowerShell copies because the upstream install batch helpers strip `!` from paths.
- `inputs.py verify --part runtime --deep`: zero problems. The combined package passes this
  worktree's `nlctl` validation: 1,008 files, digest
  `90d6fa1ae7206eea8eb4a0170ce5ccd8a5c22df3d532701eb2faf151895f9961`.
  No game session or GPU-loss trigger was run; see [TESTING.md](../docs/TESTING.md#r6-t4-runtime-memory-diagnostics).
- Repository Release validation: 23/23 CTests and 333 Python tests (two skips). The known guard
  cache-path limitation needs only that unchanged test executable copied to `out/tmp`; the local
  wrapper temporarily redirects its generated CTest command and restores it after the run.
  No loader/test source changed. The whole-worktree drive alias was removed.

The second review's configure-only scratch setup matches all 95 saved Release options and was
deleted after comparison. Its dedicated diagnostics test checks the five nonzero OMM counters,
reason escaping, PID-specific temporary files, two 10 ms sharing retries, preservation of the old
marker and cleanup after replacement failure. T2's integration reader ignores the additional fields;
see [RESEARCH.md](../docs/RESEARCH.md#r6-t4-runtime-memory-snapshots-2026-10-31).

Exact second-review import from this worktree (invoked by `build_runtime.ps1`):

```powershell
python tools/inputs.py import runtime --file 'out/runtime-src/_CompRelease_x64/src/d3d9/d3d9.dll=files/d3d9.dll'
```

Local second-review receipts are under `out/tmp`, prefixed `runtime-review2-`: `build.log`,
`verify-before.log`, `setup.log`, `setup-comparison.json`, `release-config.json`,
`recorded-sources.json`, `diagnostics-build.log`, `diagnostics-tests.log`, `unit-build.log`,
`unit-tests.log`, `unit-summary.json`, `verify.log`, `import.json`, `inputs-verify.log`, `package-build.log`,
`release-tests.log`, `release-summary.json` and `test-short-guard.ps1`. The first review's receipts retain the
`runtime-review-` prefix.

## C-16 rebuild (2026-10-31)

The isolated source commit is `8a5df5d8ef2e4529f20f7c07c195cb6dc3588afe`, tree
`1a6009a44590fe673282b7ceecf759548df646b8`: base `c6b48ed1` plus patches 0001-0016.
The completed build uses x64 Release, MSVC 19.44.35228, Meson 1.12.1, Ninja with four jobs,
optimization 3, the release DLL CRT, Tracy/shim off and `download_apics=false`.
Build identity: `remix-main+8a5df5d8`. The DLL is 396,802,048 bytes, SHA-256
`9906eec639b8768baf468daebb2f281c45f04754eaaf6cd60c0c5f7c883cc543`.

The R6 source, git metadata, configured builds and local dependency bytes were copied under this
worktree's `out/runtime-src`; thirty SDK junctions resolve to the already installed Packman
versions. Both saved Meson configurations and 694 shader dependency files in each were relocated
to this copy. When reusing another configured tree, relocate the shader `.d` paths too: their
timestamp checks otherwise keep following the old includes even after the shader stamp is removed.
The process-local offline resolver from R6 validates existing SDK links and cannot download.

`build_runtime.ps1` runs its source/configuration checks, reconfigures the version, and completes
both compile passes. `out/tmp/c16-runtime-build.log` records real shader compilation.
`out/tmp/c16-embedded-shaders.json` confirms the newly compiled auto-exposure and opaque G-buffer
SPIR-V are embedded in the DLL. The dedicated unit configuration passes all 28 tests, including
`test_adaptive_emission` and the regenerated `RtxOptions.md` check. Game/GPU acceptance and
eye-white tuning remain with Claude; no game or install was touched.

Exact runtime import, invoked by `build_runtime.ps1` from this worktree:

```powershell
python tools/inputs.py import runtime --file 'H:\BACKUP_20260815\Modding\!NVIDIA-RTX-Remix\out\worktrees\c16-runtime\out\runtime-src\_CompRelease_x64\src\d3d9\d3d9.dll=files/d3d9.dll'
```

The MDL declaration is the only other imported input (plain text):

```powershell
python tools/inputs.py import fixes --file 'out/c16-mdl/AperturePBR_Opacity.mdl=garrysmod/rtx-remix/mods/base_mod/breakable_glass/assets/remix_materials/AperturePBR_Opacity.mdl'
```

Local evidence is under `out/tmp/c16-*`: build/verification logs, saved Release options, shader
relocation and embedded-shader receipts, final runtime unit build/tests, MDL import, package and
repository checks. See [TESTING.md](../docs/TESTING.md#c-16-scene-adaptive-emission) for final gate
results and the project manager's GPU acceptance cases.

Final offline gates pass: exact source verification, deep input verification (zero problems),
the 1,023-file combined package's `--require-nlctl` validation, and plain
`tools/test.ps1 -Config Release` (24 CTests; 376 Python tests, two skips). The guard test needs no
path workaround here. Only the DLL's new 58,495,348-byte xz LFS object consumes binary storage.
