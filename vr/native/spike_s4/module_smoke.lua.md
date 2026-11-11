# module_smoke.lua

Additional real-GMod smoke test for the production `gmcl_nlvr_win64.dll`. The S4 session driver
stages the built module after a PoC snapshot and passes this file as a second `poc_session.py --lua`.
Requires the existing PoC RTX runtime, which has no `rtxvr_GetApiVersion` export. Logs require,
Version, Probe, initial State, off-state BeginFrame, Start acceptance, the eventual failure detail,
two Stop calls, final State and stopped BeginFrame. A bounded timer polls for at most eight seconds
and then removes itself. `NL_D_MODULE_DONE` marks completion. No fake OpenVR or fake runtime is
staged. The missing runtime export is rejected before OpenVR loads. No file or archived cvar is
changed by this Lua. Errors appear in the console evidence, not a process exit status.
