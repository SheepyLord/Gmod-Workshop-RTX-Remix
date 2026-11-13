# Natural poses for integrated fixtures

Shared test support only. `profiles()` derives the same recorded Index component
references as C's accepted observer. `natural_timeline(data)` converts a desired
palm position/aim into a raw controller pose, retaining actions and head samples.
`inject(text)` adds the companion Lua helper to a shared driver probe; callers put
the profiles in `CONFIG.q_controller_profiles`. Existing live component values are
kept and absent controllers get explicitly labelled recorded reference components.
Raw SDK validity is retained in `controllers_live`. No hardware or SteamVR settings
are changed. This never claims live-controller or live-finger acceptance. No files
are written by this module and there are no exit codes.

The helper is injected after the local CONFIG declaration so subsequent observer closures share the same local QFrames. Both-hand +/-45 degree round-trip tests verify raw-pose conversion and reject identity substitution.
