# renderer_frame_probe.lua

Use a prepared single-player PoC with the Remix developer API available. With the shared game lock held, run this from the repository root.

```powershell
python tools/poc_session.py --evidence out/renderer-frame-qa run --name renderer-frame --addons --map gm_flatgrass --extra=-insecure --width 3840 --height 2160 --screenshots 0 --settle 0 --timeout 600 --hang-grace 360 --console "sv_cheats 1" --console "hideconsole" --lua tools/qa/renderer_frame_probe.lua --lua-shots 430
```

The probe holds the camera at fixed coordinates over opaque ground and at the map edge. It temporarily hides first-start dialogs for the captures. It checks Enhanced sky with and without No horizon, Standard sky, a turning view and all eight sharpening, blur and lens combinations. It records frame samples as `NL_RENDER_SAMPLE` lines and asks the harness for a picture of each view. Its first view stays covered long enough for a bounded Vulkan profile.

The probe temporarily sets sky convars and session-scoped Remix options. It restores them and removes its hooks before `NL_SHOT_DONE`. Completion is `NL_RENDER_END` with `reason=complete` and `restored=true`. A missing map, developer API or option emits `NL_RENDER_ERROR`. Compare the records, images and GPU commands of the published and candidate packages. The probe makes no package or repository edits.
