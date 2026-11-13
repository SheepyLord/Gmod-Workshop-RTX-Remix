# sv_core.lua: Server session, validation and movement

New(protocol) returns SV; server.lua assigns its fixed Modules before Start. Full VR accepts only the single-player player or listen host, in the stub and again here. Players[ply] stores active, head, hands, history.left/right (time,pose,seq), seq, since, scale. Start activates modules and seven session hooks on demand; Stop(ply), last departure or shutdown removes everything and NLVR_SV. OnStart/OnStop/OnSync/OnDeath/OnSpawn registration helpers and On/Emit are scoped by the registry. Death notifies modules while keeping VR active. Sync accepts two arrivals per server tick, exact length, monotonic uint32 sequence, finite vectors/angles, all positions within SV.Reach(ply) of server EyePos, controls/curls in 0..1. Bad packets count in Debug.dropped and never enter state/history; history holds the last second, with a 1024-entry bound. Movers run in ascending priority in SetupMove; the first true result owns this command, and Move returns true for it. Mutate mv, not the entity. Net.On owns module readers; incoming module traffic is bounded to 64/tick and 4096 bytes. Net.Send(ply,type,writer) snapshots values, sends only changed payloads, at most one module packet total per player/tick, and replaces queued intermediate states; Tick flushes the newest pending state. All hooks disappear with the last player. No physics implementation, file writes or authority for remote clients.

Inputs are the session/context arguments described above. Outputs are returned Lua tables and active-session state only. Errors propagate to the owning session or harness; there is no process exit code for production Lua.

The active Tick hook also ages out histories without a new packet; after a second without sync all tracked validity flags become false. Pending output is oldest-first by initial queue insertion, preserving fairness when one message type changes continuously.

REACH is exposed in game units (default 100 at 40 units/metre). SV.Reach(ply) scales that limit to each active player; the protocol constant remains 2.5 metres.

Start/last Stop print the actual active global, nlvr.* hook count, permanent receiver, accepted syncs and total drops once per transition. These one-shot diagnostics give both-realm PoC evidence without adding an idle hook or receiver.


Review correction: after validating tracking-relative sync, add the authoritative player velocity to the hands before storing world-space velocity/history. Throws and physics therefore include walking/sprinting.


Velocity contract: synced pose.vel is the wire tracking-relative controller velocity, rotated to world axes and scaled to game units/s. It is never overwritten by stick/body motion. pose.wvel = (pose.vel or zero) + authoritative ply:GetVelocity(). Only following, holding and throw histories consume wvel; gestures, bare/weapon melee and reload consumers retain vel semantics. The wire format is unchanged.

Independent review applies the shared sh_move_basis.lua in SetupMove before server movers, matching client correction without changing the weapon command.
