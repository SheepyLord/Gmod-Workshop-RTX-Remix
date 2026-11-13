# cl_frames.lua

Included by the client core only at Start VR. `New(core).Apply()` composes the current predicted raw device pose with native Source-basis local `aim`, `hand` and `wrist` transforms. The public hand pose becomes the palm; `.raw` remains tracking space and `.device` is the raw pose in world space. `.aim` feeds `C.Ray`. Offset velocity includes angular velocity crossed with the offset. Unknown controllers preserve raw poses. The controller source is logged once per revision and plain measurements appear under `Debug.frames`.

No hooks, SDK calls, files or persistent state on include; all state belongs to the session. No exit code; errors propagate to the owning core.

Handle follow-up: Index hand origin is the central handle-axis reference measured from SteamVR body.obj sections z=.085..145 m, excluding the ring. openxr_handmodel is not accepted as a sufficient wrist/handle-fit proof. H centres its closed grasp tube on this handle reference; diagnostics fit its eight proximal/middle joints with direction from the four finger arcs. `.handle` retains the measured reference. Other controller profiles retain their existing data paths.

## Review correction (2026-11-12)

Index Handle requires successful hand components/SDK hand data and a valid tip, not a model name alone. A valid tip survives a missing hand: position stays raw, orientation/ray use the tip; an independently read wrist is retained. All components missing means fully raw. Index constants never apply to other models.
