# motion_server_harness.lua

The LuaJIT side of [test_motion_server.py](test_motion_server.py.md): loads the Character Motion Importer's
`sv_commands.lua` with the parts of Garry's Mod it uses stubbed (hooks, net messages, timers, cvars and
`RunConsoleCommand` applied at the end of a frame, an in-memory `data/`, entities whose unknown methods do
nothing, a small JSON encoder and decoder), then runs one scenario.

```powershell
luajit tools\tests\motion_server_harness.lua <scenario> packages\character-motion-importer\mmd_vmd_npc\lua\mmd_vmd_npc
```

Scenarios: `select`, `play`, `reset`, `stop_all`, `disconnect`, `debug_rate`, `cvar_shutdown`, `cvar_crash`,
`cvar_lua`, `cvar_admin`, `built_budget`, `build_limits`, `keep_flexes`, `ragdoll_collision`, `built_flags`,
`details_walk` (what each checks: the table in [test_motion_server.py.md](test_motion_server.py.md)). The cvar
scenarios load the file a second time, with the same `data/` and cvars, for the next map's Lua state. The budget
scenarios lower the limits through `MMDVMDNPC.Guard`.

The stubs also cover a player's tool settings (`GetInfoNum` from `ply.info`), flex weights by controller id, the
pose-cut counter (NW2 integers), a model's ragdoll as `prop_ragdoll` entities report it (18 bodies on main bones;
a model whose name has `caped` 22, three of them on main bones), the collider class registered through
`scripted_ents.Register` with its shadow physics object, and the built folder listed from the in-memory `data/`
(the add-on's `BuiltMotionIDs`).

**Output:** `PASS <scenario>`, exit 0; a failed check raises `FAIL <scenario>: <why>` (exit 1).
**Writes:** nothing on disk.
