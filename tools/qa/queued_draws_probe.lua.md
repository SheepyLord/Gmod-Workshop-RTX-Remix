# queued_draws_probe.lua

Client Lua for [queued_draws_session.py](queued_draws_session.py.md), which puts a settings table in front of it
(`NLQD = {mode, seconds, shots, yaw, center, per_frame, settle}`) and sends it with `poc_session.py run --lua`
([ADR 0192](../../docs/decisions/0192-the-fixes-never-read-a-queued-draws-renderable.md)). The scene's centre is set
on the ground under `center` (a trace, as [queued_draws_server.lua](queued_draws_server.lua.md) does).

- **`stress`**: a `Think` hook removes, every frame, the `per_frame` client models (`ClientsideModel`: a watermelon,
  a PHX cube, an oil drum, a crate, a door, a can) it created the frame before, and creates as many again, all in
  view around the centre (the driver's default is none: eight a frame exhausted an engine list); it removes each
  client-side gib a quarter second after it first sees it (`ents.FindByClass("class C_PhysPropClientside")`; in the
  PoC sessions it found none, and the gibs of the props the server script breaks fade out by themselves); and it prints
  an `NLQD_PAD` line of up to `console_churn` base64 characters, as the crashed VR sessions' probe printed its packets. Every removal frees an entity whose draw the
  material system's queued render thread may still be running, the condition of the fixes' crash before the
  queued-draws patch. Every `shots` seconds it prints a checkpoint line and `NL_SHOT stress-<n>`; after `seconds` it
  removes its hook and models and prints `NL_SHOT_DONE`, unless the game has crashed first.
- **`lighting`**: draws nothing itself. After `settle` seconds (the server's still scene, the Remix denoiser) it
  prints `NL_SHOT lighting-1`, then `lighting-2` and `lighting-3` three seconds apart, then `NL_SHOT_DONE`.

Screenshots are paced with `NL_SHOT <label>`, answered by the driver with `nl_shot_taken <n>`. Lines:

| Line | Holds |
|---|---|
| `NLQD start\|checkpoint\|done seconds <s> frames <n> client_models <n> freed <n> gibs_freed <n> console_bytes <n> fps <n>` | stress progress: frames churned, client models created and freed, gibs freed, console text printed, the frame rate |
| `NLQD_PAD <text>` | the console churn (no meaning) |
| `NLQD lighting start\|settled`, `NLQD done` | lighting progress |

Side effects: client entities of that session only; nothing archived. Exit codes: none (client Lua).
