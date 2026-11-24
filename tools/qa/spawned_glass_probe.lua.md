# spawned_glass_probe.lua

Client Lua for release QA's `spawned-glass` session ([`release_qa.py`](release_qa.py.md)), or by hand:
`poc_session.py run --console "sv_cheats 1" --lua tools\qa\spawned_glass_probe.lua --lua-shots 120` (any map with
open ground ahead of the player; release QA uses gm_construct). It spawns the glass system's own pane the way the
spawn menu does and shoots it with the 357, apart from map windows (review R4: a spawned pane alone once crashed RTX
sessions with `mat_queue_mode 2`), and counts what the player sees of the glass system (G1,
[glass/addon](../../glass/README.md)).

G1 keeps no entity for a broken piece: the pieces live in each client's debris world (`NLGlassDebris`, on the
Jolt module `gmcl_nlglass_win64.dll`). Until 2026-11-24 the probe spawned `procedural_shard_4` from
Glass-Rewrite-Remix, the add-on G1 replaced on 2026-11-01, so nothing was spawned with any package since
([report](../../docs/handover/release-qa-glass-report.md)).

1. **Setup.** Looks 25 degrees down and runs `gm_spawnsent nlglass_annealed_96x64` (G1's annealed 96x64 preset in
   the spawn menu's Glass Rewrite category; the pane lies on the ground at the eye trace), waits up to 10 s for the
   new entity and G1's record of it (`NLGlass.Client.byIndex`), aims at its centre, selects the 357 and waits
   until the debris world has imported the map (`NLGlassDebris.Backend()` is `jolt`, at most 60 s) and the gun is
   drawn. It counts the pane's draws through `NLGlass.Client`'s observation slot, `Observe`, unset in play (the
   probe hands the slot back as it found it). Screenshot `before_shot`.
2. **The shot** (real `+attack`, one round). For 2.5 s it samples every frame in `PostRender`, after the
   translucent pass where panes and debris draw: the most debris draw calls in one frame and the frames that drew
   any (`NLGlassDebris.Stats()`). Then it reports the glass left in the pane (its remaining cells' area over its
   outline's, `NLGlass.Fracture`), the pieces created since the shot (`NLGlassDebris.Count()`), the backend, those
   draws and the pane's own draws after the shot. Screenshot `after_shot`.

Each step prints one `NL_QA_GLASS` line, a JSON object with its `step` (`setup`, `break`, `done`); an error
inside the probe prints an `error` step and ends it. `NL_SHOT` lines pace the screenshots (answered by the session
driver with `nl_shot_taken <n>`). Sent again, it cancels its earlier copy.

| Step | Fields |
|---|---|
| `setup` | `g1`, `preset`, `spawned`, `tracked`, `center`, `mesh` (G1 built the pane's mesh), `pane_draws`, `glass_left`, `backend`, `waited`, `pieces` |
| `break` | `open` (less than all of its glass left), `pane_valid`, `glass_left` (0-1), `pieces` (created since the shot), `live`, `backend`, `draws`, `drawn_frames`, `frames`, `pane_draws` (since the shot) |
| `done` | `pieces`, `backend` |

Release QA passes the session when the probe reaches `done`, the pane was spawned, G1 tracks it, built its mesh and
drew it, the debris world is `jolt` before and after the shot, and the round left a hole and pieces that were drawn.

Side effects: that session's map state only (a pane with a hole, debris, the player's view and weapon).
Exit codes: none.
