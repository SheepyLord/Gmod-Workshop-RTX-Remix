# Shared VR hook-library fixture

Original LuaJIT and PoC test support; no upstream implementation is copied.
`Fixture.New(mode, existing)` returns a hook API, the compatibility registry, and
the priority registry. Modes are `ulib` (default), `stock`, and a detached-table
`unknown` adversarial case. Existing registrations migrate at normal priority.
All VR harnesses use this fixture for hook-library compatibility tests.

The contract follows [ULib's public hook API and its documented priority tests](https://github.com/TeamUlysses/ulib/blob/master/lua/ulib/shared/hook.lua):
priorities -2 through 2, ignored monitor returns, six returned values, object IDs,
Remove-before-Add, and an unguarded backward-registry index in Remove when the
authoritative event exists. The last two deliberately expose broken VR restoration.
`order` is an offline-only way to test both orders within a priority; leave it unset
in a game. No files, convars, settings or processes are changed. There are no exit
codes; assertions in its callers fail the suite.

Q4 adds independent posed-mesh grip references for ten stock models and all-class captures in both hands. Stock weapon_fists has an empty WorldModel: its avatar hands are checked, and no nonexistent weapon mesh is required. Other modeled weapons retain strict independent grip limits. Private fixture Lua now stages as plain files in the journaled test add-on and installs the shared ULib API into the existing engine hook table.

An optional third target argument installs methods into the existing engine hook table, preserving its identity and cached table references. All harnesses still share the same implementation.

Independent review round: live hooks use the shared dispatcher and detached compatibility snapshots; geometry witnesses use raw posed-mesh/hand-bone data with rejecting placement/skew mutants. Full destructive acceptance stays gated pending Claude's fixes repair. See VR-V4-Q-resume.md for exact test/evidence scope.
