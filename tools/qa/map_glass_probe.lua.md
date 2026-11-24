# map_glass_probe.lua

Client Lua for release QA's `map-glass` session ([`release_qa.py`](release_qa.py.md)), or by hand:
`poc_session.py run --map modern_house --console "sv_cheats 1" --lua tools\qa\map_glass_probe.lua --lua-shots 180`.
It shoots a map window the way a player does, then the broken window again, then its pieces on the floor
(review R4: shooting a window crashed the game), and counts what the player sees of the glass system (G1,
[glass/addon](../../glass/README.md)).

G1 keeps no entity for a broken piece: the pieces live in each client's debris world (`NLGlassDebris`, on the
Jolt module `gmcl_nlglass_win64.dll`). The probe therefore counts no entities. Until 2026-11-24 it counted the
`procedural_shard` entities of Glass-Rewrite-Remix, the add-on G1 replaced on 2026-11-01, and so failed with every
package since, though the windows broke ([report](../../docs/handover/release-qa-glass-report.md)).

1. **Setup.** Counts the map's glass windows as the engine has them (`func_breakable` with a glass brush material)
   and the windows G1 tracks (`NLGlass.Client.records`), picks the nearest upright one G1 tracks, stands 90 units
   in front of it at eye level (`setpos`/`setang`, which need `sv_cheats 1` for the session; it is not archived),
   selects the 357 and waits until the debris world has imported the map (`NLGlassDebris.Backend()` is `jolt`, at
   most 60 s) and the gun is drawn. Screenshot `before_shot`.
2. **The first shot** (real `+attack`). For 2.5 s it samples every frame in `PostRender`, after the translucent
   pass where the debris draws: the most debris draw calls in one frame and the frames that drew any
   (`NLGlassDebris.Stats()`). From half time it reads where the pieces are (`NLGlassDebris.Diagnostics(256)`, the
   manager's read-only QA accessor) and counts those within 512 units of the window. Then it reports whether the
   window is open (its entity gone, or for a G1 pane less glass left), the pieces created since the shot
   (`NLGlassDebris.Count()`), the backend and those draws. Screenshot `after_first_shot`.
3. **The window again**: two rounds through where the pane was; the rays that hit a piece and the splits
   (`ray_hits`, `splits`) are reported. Screenshot `after_more_shots`.
4. **The floor**: three rounds at the nearest piece lying at least 24 units below eye level and 40 units away (or 60
   units below the window's centre if no position was read). Screenshot `after_floor_shots`.

Each step prints one `NL_QA_GLASS` line, a JSON object with its `step` (`setup`, `break`, `again`, `floor`,
`done`); an error inside the probe prints an `error` step and ends it. `NL_SHOT` lines pace the screenshots
(answered by the session driver with `nl_shot_taken <n>`). Sent again, it cancels its earlier copy.

| Step | Fields |
|---|---|
| `setup` | `g1` (the glass system runs on the client), `windows`, `tracked`, `natives`, `target` (G1's pane id), `native`, `center`, `backend`, `waited` (seconds until the debris world was ready), `pieces` |
| `break` | `open`, `pane_valid`, `glass_left` (0-1), `pieces` (created since the shot), `live`, `backend`, `draws` (most debris draw calls in a frame), `drawn_frames`, `frames`, `read` (positions read), `near` (within 512 units), `nearest` |
| `again`, `floor` | `pieces`, `ray_hits`, `splits`, `draws`; `floor` also `aimed_at_piece` |
| `done` | `pieces`, `backend` |

Release QA passes the session when the probe reaches `done`, G1 tracks a window, the debris world is `jolt` before
and after the shot, the window opens, it breaks into pieces, they are drawn and some lie within 512 units of it.
The follow-up shots are reported, not judged: a round lands on a piece only when one lies under it.

Side effects: the map state of that session only (a broken window, debris, the player's place and weapon).
Exit codes: none.
