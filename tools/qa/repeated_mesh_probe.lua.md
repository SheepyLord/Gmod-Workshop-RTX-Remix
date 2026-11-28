# repeated_mesh_probe.lua

The client probe measures the stationary courtyard and walking hallway from the Modern House field study. Run from the repository root with a prepared single-player PoC package, the subscribed map, cheats enabled and the project's shared game lock.

```powershell
python tools/poc_session.py --evidence out/repeated-mesh-check run --name modern-house --addons --map gm_construct --mount-workshop 3495468649 --change-map modern_house --extra=-insecure --extra=-tickrate --extra=120 --width 3840 --height 2160 --screenshots 0 --settle 0 --timeout 600 --hang-grace 360 --console "sv_cheats 1" --console "hideconsole" --lua tools/qa/repeated_mesh_probe.lua --lua-shots 420
```

The initial courtyard warm-up allows map textures and PBR replacements to settle before GPU profiling. Each route emits two 12-second NL_MESH_SAMPLE records with real rendered frames, timings, player travel, focus, output resolution and live rendering settings. The harness takes a screenshot of each route in response to NL_SHOT. A successful run prints NL_MESH_END complete and NL_SHOT_DONE. NL_MESH_ERROR identifies a failed setup. Each window records its focus state and background cap. A focus change restarts the route and the window up to three times. A remaining interrupted window is marked in the record so comparisons can exclude it.

The probe temporarily enables ToPBR and Enhanced No horizon and uses fixed camera routes. It restores its convars, hidden panels and starting pose, then removes its hooks. The session harness owns the game installation snapshot and rollback.
