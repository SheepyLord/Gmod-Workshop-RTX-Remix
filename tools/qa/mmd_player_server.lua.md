# mmd_player_server.lua

Server half of [mmd_player_session.py](mmd_player_session.py.md): the driver puts it in the session's fresh data
folder as `nlmp_probe/server.txt`, and one console line runs it on the server
(`lua_run RunString(file.Read("nlmp_probe/server.txt","DATA"),"nlmp_server")`) before the client half,
[mmd_player_probe.lua](mmd_player_probe.lua.md), starts. Never install it as an autorun.

- Wraps, with a timer that keeps each call's own time apart from what it calls: the add-on's `MMDVMDNPC`
  functions (not `L`/`LFormat`) and those of `MMDVMDNPC.Actor` (the options' helpers), its `mmdvmd_*` net
  receivers and `MMDVMDNPC*` hooks, `file.*`, `util.JSONToTable`/`TableToJSON`/`CRC`/`Compress`/`Decompress`, the
  entity methods the add-on poses with (bone manipulation, `SetupBones`, sequence lookups, flexes, NW2 writes),
  `Player:ChatPrint`, `net.Start`/`Send`/`Broadcast` and a few `mmdhl` functions; and, once asked (`wrap_tool`),
  the tool object's `LeftClick`, `RightClick` and `Reload`. Timing runs only between `begin` and `end`.
- Records the time between server ticks while timing.
- Answers the client half's `nlmp_cmd` net messages: `setup` (sets `sv_cheats 1` and `ai_disabled 1`, gives
  and selects the tool gun, spawns two imported characters from the PoC's library as citizens 180 units in
  front of the player, 140 apart, through `mmdhl.SpawnNPC`, or plain citizens without a library), `begin`,
  `end` (writes the window's report) and `wrap_tool`. Each answer is a file in `data\nlmp_probe`
  (`server_<kind>.json`) and an `nlmp_reply` net message.
- The feature phase, each a coroutine stepped once a tick: `build` writes a four-second test dance
  (`nlmp_probe_dance`: both upper arms swing out from frame 20 and hold until frame 100, まばたき closes the eyes
  from frame 30 to 90), deletes an earlier build of it, selects the first NPC and builds it through the add-on
  (`BeginBuildForPlayer`), waiting up to 120 s for the built file; `followers` reports what the engine's
  `CreateBoneFollowers` makes for that NPC (the functions present, the `phys_bone_follower` entities before and
  after, their owner, parent, place and physics, `GetBoneFollowers`) and destroys them again; `collision` plays the
  dance on the first NPC and reports, a third of a second in, the colliders (`mmd_vmd_npc_collider` entities owned
  by the NPC, flagged `MMDHLSceneExcluded`), the box's collision group and hull collisions, then mid-hold the hands'
  and other bones' places, a trace through each hand, a player-sized hull into the box's empty corner and into the
  head, the largest gap between a collider and its bone, the Model Hotloader's `sceneDiagnostics`, how far a
  gravity-less pop can put at the right hand moves in 0.6 s, and after the stop the same state again; `flexes` sets 笑い to 0.6
  on the second NPC, selects it twice, plays the dance and records 笑い and まばたき after the selection, at the
  start, mid-dance and after the stop; `select1`, `debug_state` (the player's last debug frame and the first NPC's
  bones) and `cleanup` (deletes the test dance and its build).

Console output: `NLMP_SERVER_READY`, `NLMP_ERROR spawn <reason>`, `NLMP_ERROR <job> <error>`. Side effects: the
cheats and AI settings above for this session, two NPCs, the tool gun, the network strings `nlmp_cmd` and
`nlmp_reply`, the test dance and its build (removed by `cleanup`), the `data\nlmp_probe` files; nothing outlives
the game.
