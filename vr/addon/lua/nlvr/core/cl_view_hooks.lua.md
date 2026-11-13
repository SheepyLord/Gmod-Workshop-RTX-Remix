# cl_view_hooks.lua

Take(ctx,callback) exclusively owns CalcView using the authoritative stock registry or ULib's five
priority tables. A private-event capability probe verifies stock table mutation affects dispatch;
unknown detached libraries refuse camera startup safely. Registrations/removals during ownership are
deferred and restored. Re-entry returns false rather than recursing or invoking another view.
Check detects library/authoritative table replacement; Stop restores only tables still owned, preserving
replacement writers. Module callback errors retain registry isolation. No files/SDK/settings writes.
Returns ownership object or nil/detail; Lua assertions/harness failures propagate, no CLI exit code.

Second verification: Stop restores the held plain table even when empty, preserving ULib Hooks/BackwardsHooks invariants for subsequent Remove/Add/Start. The private dispatch entry and ULib level identities/entry fields are checked each frame. Both stock and ULib undergo an authoritative-dispatch/short-circuit capability probe; a shaped but detached or non-short-circuiting library is refused safely.
