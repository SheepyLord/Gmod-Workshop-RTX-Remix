# 0130: An engine guard for Lua start-up: material fallback cycles cut, a watchdog names a stuck add-on

- Status: Accepted 2026-11-08 (R23, the user's items 6 and 7)
- Context: the user: "Address compatibility to weapon bases like ARC9 ... user report that they cause
  load hang, which ARC9 load hang is reproduced" and "Investigate what can cause the game to stuck at
  'starting lua' and design / propose fixes and perform fixes / mitigation. Try to make sure user can
  load into maps." Standing instruction of the same day: no loader (`winmm.dll`) change without the
  user's approval; fix in the package.

## What stopped the game

A field start with the ARC9 base and six ARC9 packs stopped at "Starting Lua" with the main thread at
100 % CPU, about 150,000 `NtCreateFile` calls a second, for minutes ([RESEARCH.md](../RESEARCH.md), R23).
[ARC9] Gunsmith Reloaded (2910537020) `lua/arc9/shared/sh_csgo_effects.lua` calls
`game.AddParticles("particles/csgo_explosions_fx.pcf")`; that system uses
`materials/particle/warp5_explosion.vmt`, `Refract` with `"<dx90" { "$fallbackmaterial"
"particle/warp5_explosion" }`, a fallback to itself. GMod RTX runs Source's fixed-function shader paths,
so the `<dx90` block applies, and `CMaterial::InitializeShader` in `materialsystem.dll` (rva
0xf950-0xfc33) reads `$fallbackmaterial`, loads that VMT, takes its shader and starts again, with no
pass counter: forever. A vanilla session at DirectX level 95 never reads the block. RTXLauncher's
`MaterialSystemFallbackPatch` caps exactly this loop but does not match this build.

## Decision

1. **A package module, not the loader.** The engine guard is a binary module of this repository,
   `gmcl_nlengineguard_win64.dll` and `gmsv_nlengineguard_win64.dll` from one source
   ([engine_guard/](../../engine_guard/README.md)), MIT, shipped in the fixes part (`modules/`,
   `package_fixes.py --lua-bin`) and recorded as repository builds (ADR 0126). A loader patch set writes
   bytes only and cannot carry this logic, and loader changes now need the user's approval.
2. **The detour.** The one call in that loop that reads `$fallbackmaterial` (a 36-byte pattern that must
   occur exactly once, its key string checked through the `lea`) is redirected to a 15-byte stub
   allocated within a call's reach: `mov r9, r14` (the material, which the loop keeps in r14 and whose
   first virtual function is `GetName`) and a jump to the hook, which calls `KeyValues::GetString` and
   answers `""` instead of a fallback that names the material itself, or that would be the seventeenth
   fallback followed for one material while they come less than two seconds apart (a cycle through other
   materials, however slow the disk); an empty fallback read for the material ends its chain, so separate
   initializations of one material never add up. With `""` the engine goes on with the shader's own
   fallback chain, as for a material without that key. Every other key and every other fallback is returned
   unchanged. The first 16 cut fallbacks are named in the console.
3. **Only where it is sure, once per process.** Besides the pattern and its key string, the loop must call
   r14's `GetName` (`mov rax,[r14]; mov rcx,r14; call [rax]`) within 0x100 bytes after the call, so r14 is
   the material, and the call's displacement must be 4-byte aligned; the image is scanned under SEH. The
   module pins itself before the call site changes (the stub jumps into it) and rewrites the displacement
   with one aligned interlocked store. The second copy (client and server are two images in one local game)
   finds the first one's stub, changes nothing, and reads its counts through `nl_engine_guard_cut_v1`. A
   game build that fails a check gets no guard; `nlengineguard.reason` says why.
4. **Early enough, only in RTX starts.** The companion's `!!!!nativeloader_engine_guard.lua` (shared, sorted
   before every autorun whose name does not itself start with four `!`) requires it in both realms of a
   local game, and the early view of
   `includes/init.lua` (`_nativeloader_guard.lua`, ADR 0056) requires it in the client realm before
   anything else, which is the only companion code a remote server's start runs. Both only where this
   machine's loader activated RTX in this start: the loop happens only under RTX's shader paths, and a
   start through an off switch loads no native code.
5. **The watchdog, for the causes the guard does not know.** From the module's load until the realm's
   `Initialize` (or its first tick, if an add-on's failing `Initialize` hook stopped the companion's; at the
   latest 150 s after the gamemode loaded, so it never stretches over a long map load, and 15 minutes in
   all) a thread samples the main thread every 3 s: suspended only for `GetThreadContext` and one copy of
   its committed stack (from `StackLimit` up: touching the guard page from another thread would take it
   from the main thread's stack growth) into a buffer allocated beforehand, so it never waits on a lock the
   main thread holds. When the nearest Lua chunk name on that stack has not changed for 90 s, it writes
   `garrysmod/data/native-loader/startup-stall.json` (realm, the last four samples' module+offset and Lua
   names, the guard's count) and shows one message per process, naming the file. A start that goes on after
   all removes the report; otherwise the next start shows a 30-second notice that names the file and the
   add-on that has it.
6. **The message is the companion's.** Its words come from the companion's own catalog
   (`nativeloader/engine_guard_words.lua`, in the player's language), never from DATA, which any server's
   client Lua can write. The module takes only the first `SetMessage` call, and the companion removes the
   function from the table after making it (the early view on a remote server keeps the module's English):
   no server's Lua sets the text of a native, topmost dialog.

## Review

An independent review (a Claude subagent, read only) confirmed the detour's ABI, address arithmetic, patch and
two-copy handoff, and found what decisions 3, 5 and 6 now cover (the guard page, a failing `Initialize` hook
stretching the watch, the message's text from DATA or a server's Lua, unaligned and unproven builds, the load
order), plus a cycle rule that slid over separate initializations; all fixed before release (R23 report).

## Not chosen

- Overriding `particle/warp5_explosion.vmt` from the package: it fixes one material of one add-on,
  depends on the search order of mounted add-ons, and the next self-reference stops the game again.
- Changing the add-on's files: never another add-on's files.
- Wrapping `include` in Lua to track progress: GMod resolves relative includes from the calling chunk,
  so a wrapper changes what gets included; the watchdog reads the stack instead.
- Interrupting a stuck Lua loop with a debug hook from the watchdog thread: LuaJIT's compiled traces never
  call hooks, and setting one from another thread races the interpreter.

## Consequences

ARC9 with Gunsmith Reloaded starts under RTX (PoC: the published package stopped at Lua and hung for
300 s; this build loaded the map in 95 s and cut the fallback 6 times); the material renders without its
DX8 fallback material. Of the 738 Workshop items installed here, only Gunsmith Reloaded has such a
fallback, so the guard changes nothing else there.
Any other material whose fallbacks lead back into its own chain is cut the same way, and named in the
console. Materials initialized before the module loads (the menu, a map's own before the first autorun)
are not guarded. A start stuck for another reason is named instead of looking like a frozen game, and the
next start says which add-on to disable. The guard's two modules are about 210 KB each; the watchdog
holds a 1 MiB buffer and one sleeping thread during start-up only. A remote server's start is guarded
only where the loader prepared the early view (the supported stock `includes/init.lua`).
