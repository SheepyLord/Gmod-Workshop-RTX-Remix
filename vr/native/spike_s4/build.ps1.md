# build.ps1

Builds the disposable S4 client module from [module.cpp](module.cpp) with MSVC x64. Run from the
worktree: `powershell -NoProfile -File vr/native/spike_s4/build.ps1`. Optional `-Out` is relative to
the worktree and defaults to `out/vr/d/s4/build`. Requires the repository's VS toolchain and GMod
Lua headers. Produces an object, import library and `gmcl_nlvrs4_win64.dll` under that directory.
Changes only this process's compiler environment; no game is started or modified. Exit 0 on success,
otherwise PowerShell reports the compiler failure.
