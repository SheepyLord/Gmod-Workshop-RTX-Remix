# render_policy_test.cpp

Standalone CPU check of the actual render_policy.h functions, with session_policy.h's gate. It
covers off-thread/closing/wrong realm/missing API refusal, valid renderer options, server cvar and
malformed-key rejection, and the separate full developer gate. The write route is the regression
for debug views (ADR 0237): behind the developer gate `rtx.debugView.debugViewIdx` and every other
`rtx.*` option go through the Remix API, not `RemixConfig`; without that gate they go to
`RemixConfig`, whose list decides, also for a remote insecure server with `sv_cheats 1` and for a
local game without `-insecure` or with `sv_cheats 0`; names that are not `rtx.*` options are
refused either way; a value written through the API is restored through it. A copy of the policy
that sends every write to `RemixConfig` (the module before the fix) fails the developer-gate cases,
and a copy that sends every write to the API fails the RemixConfig cases. Compile with a C++17
compiler (MSVC `/std:c++17 /EHsc /W4 /WX`) and run it; exit 0 when every check passes, 1 otherwise.
No game, GPU, file or network access.
