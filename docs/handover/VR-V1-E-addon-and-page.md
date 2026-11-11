# VR-V1-E: the add-on and the VR page

Read first: [VR-plan.md](VR-plan.md) (the design; "The add-on and the VR page", "HUD and panels" and the V1 row are
your part, and the decisions table is binding), [VR-V1-plan.md](VR-V1-plan.md) (interfaces: "Module to Lua" and
"The frame, in the add-on" are binding; the rules for every task and for PoC tests), [AGENTS.md](../../AGENTS.md),
[companion/README.md](../../companion/README.md) and [companion/i18n/README.md](../../companion/i18n/README.md).
You are the implementer; Claude reviews. Your branch is `vr-e` in `out\worktrees\vr-e`.

The module (`gmcl_nlvr_win64.dll`, task VR-D) and the runtime's VR output (task VR-C) are being built at the same
time. You write Lua against the `nlvr` table as the work plan defines it, and test it with a stand-in for that
table; the pieces meet at integration (VR-Q). If the interface cannot do something you need, say so in your report
with the function you would add: do not invent module functions silently.

## What to build

### The VR page (companion, always loaded)

`companion/nativeloader/lua/autorun/client/nativeloader_vr.lua` (with its `.md`): a "VR" category in the RTX Remix
tab (see `nativeloader_menu.lua` for the tab and its categories, `nativeloader_blood_menu.lua` for a small page)
and the console commands `nl_vr_start` and `nl_vr_exit`.

- **Start VR** and **Exit VR**.
- **Status:** SteamVR installed and running, the headset's model, its refresh rate, the recommended size, the
  controllers; the state while starting (SteamVR may take many seconds to come up) and the reason when it fails,
  in words a player can act on.
- **The GPU warning:** below 12 GB of VRAM or on the low performance tier the page warns (nothing is blocked). The
  loader's status file has the tier and the memory profile (`native-loader/status.json`, read as
  `nativeloader_menu.lua` reads it; [ADR 0062](../decisions/0062-loader-layers-performance-tiers-and-gpu-dumps.md),
  [ADR 0101](../decisions/0101-memory-profiles.md)).
- **Frame times** while VR runs: the compositor's frame timing and the share of reprojected and dropped frames,
  the runtime's GPU time by pass, the sizes rendered (`nlvr.Info()`).
- Translated like the rest of the tab, in the six languages (`companion/i18n`, made and checked by
  `tools/companion_i18n.py`; labels short, the rest on a help line). You translate; say in
  `companion/i18n/README.md`, as earlier rounds did, that these lines are machine translations awaiting review.
  Write non-ASCII text through UTF-8 files and check the bytes afterwards: a `?` where a letter should be has
  happened before.
- **While VR is off the page is the only VR code loaded**, and it costs nothing: no hook that runs per frame, no
  timer unless the page is open, the module not required until the player presses Start VR (or opens the page's
  status, if you need the module for it: say which you chose and why). Console output stays English.
- If VRMod or gVRMod is installed and active (both would drive the view), Start VR refuses and names the add-on
  to turn off. Read `out\vr-plan\src\gVRMod` in the main checkout for how to recognise them; copy nothing.

### The add-on (loaded at Start VR)

`vr/addon/` (deployed by the package as `garrysmod/addons/nlvr`; its Lua under `lua/nlvr/`, nothing under
`autorun`): the page includes its files when the state becomes `"running"`, and Exit VR removes every hook and
timer it added.

- **The view at the head:** the frame protocol of the work plan (`PreRender`, `CalcView`,
  `nlvr.SetFrameCamera`). Tracking space to the world: the tracking origin at the player's feet, turned by a
  play-space yaw; `nl_vr_scale` game units a metre (choose the default and say why: the player model's height
  against a real person's; gVRMod's choice is a reference). The field of view passed to the engine wide enough
  that it culls nothing an eye sees (task VR-C's spike S6 gives the number; make it a setting until then). The
  player's own model and view model are not in the eyes in V1 (hands come in V2).
- **The flat HUD kept out of the eyes:** `HUDShouldDraw` and `HUDPaint` (and what else draws 2D into the view,
  such as the default HUD elements, the crosshair, notifications) are off while VR runs and come back at Exit.
  The escape menu and the console still work on the desktop window.
- **The wrist HUD:** health, armour and the active weapon's ammo, painted into a render target of its own when a
  number changes (its size one nothing else uses: the runtime finds the target by that size) and shown as a
  SteamVR overlay on the left controller (`nlvr.OverlayCreate`, `OverlaySource`, `OverlayAttach`), readable at
  arm's length. The package's render guard (`companion/nativeloader/lua/autorun/_nativeloader_guard.lua`) judges
  render targets under RTX: check what it does with this one, and if it needs a rule say so in your report rather
  than changing the guard (it is not in your paths).
- **Exit VR returns to the flat game with the player's settings:** every setting changed for VR (for example
  `fps_max`, when it is below the headset's refresh rate) is changed for the session and put back at Exit, on a
  SteamVR quit event and in `ShutDown`; nothing archived of the game's own stays changed. The add-on's own
  settings (`nl_vr_*`) may be saved.
- Single-player and the listen host only in V1; on another server Start VR says it is not supported yet.

## Tests

- Offline, in the gate: a LuaJIT harness run from Python, as `companion/tests/test_lag_report.py` and
  `tools/tests/test_render_guard.py` do: the page's state machine (start, running, failure, exit, a SteamVR quit),
  that nothing runs per frame before Start and nothing after Exit, the settings put back in every way out, the
  tracking-to-world maths, the HUD kept out and restored, the wrist HUD's numbers and when it repaints, the
  refusal beside VRMod, the GPU warning's conditions.
- In the PoC (the PoC lock; rules in the work plan), flat: the page in the RTX Remix tab at 1920x1080 and at
  3840x2160 (the user plays at 4K with GUI Scaler: companion windows scale by `ScrH()/1080`), in English and one
  translated language; Start VR without the module present says so cleanly. The whole thing in VR is VR-Q's.

## Your paths

`companion/nativeloader/lua/autorun/client/nativeloader_vr.lua` and its `.md`, the one line that adds the "VR"
category where the tab's categories are listed, `companion/i18n/**` (additive), `companion/tests/**` (new files),
`vr/addon/**`, `docs/handover/VR-V1-E-report.md`. Check that the package's build picks the new companion file up
(`tools/package_fixes.py`) and say in your report what VR-Q has to add for `vr/addon` (do not change packaging).

## Done

The page and the add-on with their documents; the catalogs complete and checked; the offline tests in the gate;
the page seen in the PoC; `tools\test.ps1 -Config Release` passing in `out\worktrees\vr-e`; the report (what was
built, the choices made and why, the interface as you used it, the evidence under `out\vr\e\` in the main
checkout, what is open, your text for CHANGELOG, TESTING and the decision records).
