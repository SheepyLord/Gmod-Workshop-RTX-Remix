# S4 material call queue experiment

This build-specific experiment is separate from `nlvr` and never shipped. [module.cpp](module.cpp)
implements three Lua functions (`Layout`, `Queue`, `Records`) to verify the public Source SDK's
Windows `VMaterialSystem080` / `IMatRenderContext` call queue in the current PoC. It refuses a
different `GetRenderContext` RVA or instruction prefix; `Queue` also refuses a different queued
`GetCallQueue` RVA. It calls interfaces and writes only its own marker storage. It never patches
the engine or writes depot files. Pending markers must drain before the game closes the module.

[build.ps1](build.ps1) builds the disposable DLL under `out`; [probe.lua](probe.lua) brackets an
actual render-target draw with markers and prints the measurements. Read their adjacent usage
documents. These files support the VR-V1-D report; the runtime interface and module rely on the
camera/pose ring regardless of this experiment's result.

[run.py](run.py) owns the locks, snapshot, staging, session and verified rollback.
[module_smoke.lua](module_smoke.lua) also exercises the real production module's Lua adapter in
that session. [pe_inventory.py](pe_inventory.py) creates the read-only PE/RTTI inventory used with
the Ghidra evidence.
