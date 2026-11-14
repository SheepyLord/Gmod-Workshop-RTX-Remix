# cl_interact_predict.lua

Client drawing of held props at the hands' current pose, VR V8
([ADR 0203](../../../../../docs/decisions/0203-precise-vr-holds-follow-the-hand.md)). Included by
[`cl_interact.lua`](cl_interact.lua.md); `Predict.New(ctx)` returns `Update`, `Pose`, `Debug` and `Stop`.

- `Update(states, pair, now)`, after each message 41: an entity a hand holds, that is one physics body
  (`single`) and not a `prop_ragdoll`, gets a `RenderOverride` that keeps the one it had (its own field and whatever
  it inherited) and calls it, or `DrawModel`. `follow` is the server's `tracking` flag for that hold; a pair of hands on
  one body uses the pair frame.
- `Pose(ent, now)`, at draw time: while the hold is followed and fresh (a message within 0.4 s), the pose
  [`sh_grab_math.lua`](sh_grab_math.lua.md) gives for this frame's shown hands (`ctx.Hand[hand].shown`, after the
  hands' world stop); otherwise the entity's own networked pose. Each switch between the two blends from the last drawn
  pose over `BLEND` (0.12 s). The override sets `SetRenderOrigin`/`SetRenderAngles` and `SetupBones` for that one draw
  and clears them after it.
- A released body that has blended back to its physics pose gets its own override back; `Stop` gives every override
  back. Overrides another add-on put in place after ours are left alone.
- `Debug(ent)`: `{mode = "held" | "physics", follow, blending, drawn}` (`drawn`: the last drawn position).

Inputs: the interact module's server states and the core's hand poses. Outputs: drawing only; it never moves an entity
or its physics. No hooks, convars, files or exit codes. Tests: the `v8_predict` and `v8_message` harness cases.
