# vr_stubs.lua: VR engine stand-ins

Loaded by vr_harness.lua. Math supplies independent Source-basis full Euler transforms/vectors. Wire is a bounds-checked bit stream with IEEE754 float bytes through LuaJIT FFI; Command and Move provide mutable engine-style records, Traces supplies deterministic no-hit line/hull stubs. No native VR, game, files or network. Run through test_vr.py; assertion failures exit LuaJIT nonzero.

Inputs are the session/context arguments described above. Outputs are returned Lua tables and active-session state only. Errors propagate to the owning session or harness; there is no process exit code for production Lua.

V4 adds weapon metadata/clips/fire time, inventory/ammo/give/strip/select, command button/wheel/queued selection, persistent weapons.Register/GetStored, mutable Bullet data and client model attachment/bone fixtures. See vr_v4_harness.lua.md for the wiki contracts, fixture inputs and explicit limits. S.Model takes local bones/attachments; SetupBones enables rigid world transforms (matrix translation/angles subset). S.ClientsideModels(fixturesByPath) installs ClientsideModel and returns its created-object list for ownership checks. S.Player takes ammoTypes/caps/classes; engine prediction, SWEP inheritance and automatic reload are deliberately driven by feature tests, not faked here.

Bullet follows the wiki defaults, including a zero direction until the caller supplies one; NULL inflictor/ignored entity and zero hull size. The caller supplies the firing entity as Attacker where its scenario needs that engine context.

CMoveData stand-in now exposes independent movement angles, three speed fields and buttons for actual client/server basis tests.

Independent review round: live hooks use the shared dispatcher and detached compatibility snapshots; geometry witnesses use raw posed-mesh/hand-bone data with rejecting placement/skew mutants. Full destructive acceptance stays gated pending Claude's fixes repair. See VR-V4-Q-resume.md for exact test/evidence scope.
