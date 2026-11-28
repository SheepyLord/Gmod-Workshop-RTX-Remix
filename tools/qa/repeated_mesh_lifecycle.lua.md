# repeated_mesh_lifecycle.lua

On single-player gm_flatgrass, the probe creates 88 client-side copies of a stock prop containing a 100–999 triangle mesh. It moves and settles the props, hides all but three, brings them back, switches the existing Force merge all meshes option on and restores it, and removes the props. Each phase uses the same camera and records a screenshot and visible count. This exercises placement, transitions between merged and shared geometry, and cleanup.

Run the prepared PoC with the harness's shared lock and the Remix developer API available.

```powershell
python tools/poc_session.py --evidence out/mesh-life-check run --name mesh-life --addons --map gm_flatgrass --extra=-insecure --screenshots 0 --console "sv_cheats 1" --console "hideconsole" --lua tools/qa/repeated_mesh_lifecycle.lua --lua-shots 180
```

The probe removes its client props and hooks, reveals any panels it hid, and restores its daylight and weather convars and its session-scoped Remix option. Completion is NL_MESH_LIFE_END complete restored=true followed by NL_SHOT_DONE. NL_MESH_LIFE_ERROR identifies a failed phase.
