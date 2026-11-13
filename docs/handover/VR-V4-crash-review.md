# Q4 reviewed crash classification and resumption

Claude/user explicitly diagnosed PID 49376 and directed Q to continue on 2026-11-12.
This supersedes the earlier unknown-cause hard stop; it does not approve a milestone.

Windows LocalDumps keeps the newest ten full dumps in
`H:\SteamLibrary\steamapps\common\GarrysMod_RTX_c\_debug_tools\hangdumps\wer`.
Q may only read or copy from there. It must never write, delete or move a source file.
The shared driver copies the exact `gmod.exe.<pid>.dmp` to that run's evidence, verifies
full size/SHA-256, and retains Application event1000. Earlier failed evidence stays.

The known fixes crash requires **both** the module timestamp **0x6af185ec** and the
return address **gmcl_RTXFixesBinary_win64.dll+0x41605b** on the faulting thread's
captured stack, beginning at **RSP from the exception stream context**, not its separate
thread-list context. A bounded read-only parser confirms this in the reviewed full dumps:

| PID | Faulting thread | Exception-context stack match |
|---|---:|---|
| 49376 | 46900 | RSP + 128 bytes, fixes+0x41605b |
| 50472 | 4908 | RSP + 128 bytes, fixes+0x41605b |
| 22984 | 36732 | RSP + 176 bytes, fixes+0x41605b; exception RIP client.dll+0x5744c |

Claude's diagnosis: a tier0 material-system queued-render worker enters the fixes
R_StudioRenderFinal / R_StudioSetupSkinAndLighting chain, then GetBoneCountForRenderable
(prop_fixes.cpp357/265) calls GetModel on a freed IClientRenderable. A stale executable
slot passes the existing check, the wrong function overwrites the return address and
ret-to-zero escapes the normal handlers. The crash predates VR and exists in the published
fixes module. Claude handles the production fix separately; Q does not disguise it.

Either this exact build/stack signature or the existing **startup-only** NVIDIA
nvoglv64.dll+0xe622f8 signature permits **one** fresh-folder retry after verified restoration.
The shared driver re-executes the complete original caller CLI so all semantic reducers
run on the child evidence. A persistent claim prevents reusing the same retry permission.
Any unknown crash, wrong build, absent proof, or second consecutive crash stops and is
reported. No entity-removal changes, r_forcehwlight setting or other avoidance cvar.

Code: [classifier](../../tools/vr_crash.py.md), [driver](../../tools/vr_session.py.md),
[offline tests](../../tools/tests/test_vr_crash.py.md). All 82 shared-driver tests pass.
Actual reviewed signature receipts remain under `out/vr/v4q/resume`; the49376 run also
retains its verified WER copy and new `crash.json`, without replacing the original receipt.


## Authorized retry outcome

The one fresh retry of49376 ran as combined-sim-02, PID 50548, and crashed with the same
signature. Its exception RSP 386895181112/thread 53620 stack contains the return atRSP + 128;
RIP is0. The verified362335573-byte WER copy is retained in that run, SHA-256
157ced6b372117e8a643dad2f74ea2197bf073610f3a7242b0dd7f0fd8f27549.
Application 1000/39243 at2026-11-12T15:54:04.3876210Z matches the game. The shared receipt
correctly has prior_crash=true and retry_eligible=false, so Q stopped without a third run.
PoC restoration is clean; no field game ended, SteamVR unchanged, no Index or Release gate.
This is the reviewed pre-existing fixes crash, not newly attributed to VR or a fixture phase.
