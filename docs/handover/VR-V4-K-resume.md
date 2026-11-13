> Second verification follow-up now targets .15: safe lapse/carry, persistent
> serial ACKs under the real coalescer and readiness+.3 s B checks. See the current
> report for final evidence. Older .10/.14 commands below remain historical only.

> Post-reboot verification completed on fresh evidence folders: review7-physical
> and the corrected review7-button analysis pass on .14. The failed earlier attempts
> and crash-interrupted queue are retained; see the current report for exact status.

> Review follow-up on 2026-11-12 supersedes the completed .10 resumption below.
> See [the current report](VR-V4-K-report.md): .14 contains the nine review fixes,
> expanded tests and fresh simulated proof. The old pause commands are historical.

> Completed resumption on 2026-11-12: the two named simulations and Index run now
> pass on frozen .10. See [the final report](VR-V4-K-report.md) for selected results,
> visual/C limits, final gate and review status. The pause instructions below are
> retained as historical recovery context; do not restart their completed runs.

# Resume VR V4 task K: reloads and ammo counter

**Paused at the user's request on 2026-11-11. Task K is unfinished.** This note is
the starting point for a new thread with no previous context. Start no more work
until the user resumes it. The only session left running at the interruption,
`sim-empty-01`, has now finished, passed analysis and restored the PoC. No K game,
session driver, batch, lock or pending PoC transaction remains.

## Task, branch and boundaries

Worktree: `H:\BACKUP_20260815\Modding\!NVIDIA-RTX-Remix\out\worktrees\v4k`.
Branch: `v4k`. Read [the K brief](VR-V4-K-reload.md), [V4 interfaces/rules](VR-V4-plan.md),
[V2/V3 rules](VR-V2V3-plan.md), [binding design](VR-plan.md) and `../../AGENTS.md`.
[K's report](VR-V4-K-report.md) is a detailed checkpoint, **not a final handover**.

Only K's `cl_reload*`, `sv_reload*`, `sh_reload*` modules/sidecars, its
`companion/tests/vr_reload*` tests/sidecars, the existing tools bridge if needed,
ADRs 0179-0180/index and K's handover notes may be edited. Shared docs belong to Q;
proposed additive text is in the report. This resume file was explicitly requested.
Never edit `loader/`, push, publish, start workflows or merge into `main`/`vr2`.
Inbound reviewed `vr2` merges are allowed by the original task, when work resumes.
Use configured SheepyLord identity; every commit ends with:

```text
Co-Authored-By: Codex <noreply@openai.com>
```

All scratch/build/evidence stays under this worktree's ignored `out/`. Use the
PoC only. Never alter Steam depot files, field-install files, Remix user.conf or
foreign locks. SteamVR stays running and unchanged. The user permits the existing
normal-console-quit field-game helper when GPU/VR tests need it; K has needed no
actual field quit so far (no `*/field-quit.json` receipts).

## Source and current package

Production implementation is frozen at **`15049a90f632c7bc740d4be625e12d1109c0faf8`**.
Later commit `4a8c9ccf` only updates the checkpoint report. This parking commit
adds/updates handover docs, not production code.

Reviewed source merged inbound: M, R's final runtime import, W (`0e83c0e7`, K merge
`2dfb2f6c`) and Q (`6117fa27`, K merge `0567c8ba`). Last checked `vr2`: `6117fa27`.
Read newer reviewed Q/W/C reports and commits on resumption before choosing whether
to merge/rebuild/recalibrate. No C controller-frame implementation is in this package.

Current normal build: **`out/dist/gmod-rtx-remix-0.0.0-v4k.10.gma`**.

- GMA bytes: **2,085,763,112**. SHA-256:
  `748423ec099aef247252b4cc9fe7f532baee58eafce5e36a1eb3144ff560528f`.
- Payload: 1,811 files, 2,085,207,689 bytes; 1,812 archive entries including manifest.
  Manifest digest `7b2883a243c88914f9acfde9fe6e28fa6a0174cddfea6769018249f1e1e33452`.
- Runtime: 418,403,840 bytes, SHA-256
  `027aae44befc301774508b09401808fa16615592e05a02bcf64bd9d761123278`.
- Native module: 510,464 bytes, SHA-256
  `a1628079de069a7a747d506a23ee8f7c957f18f8f7e2283155fd896205fc13b7`.
- Built normally from repository package inputs, **no native override/import**.
  `out/vr/v4k/package-source-10.json`, `package-10.log`, `package-audit-10.json`
  and adjacent dist JSON retain provenance. Audit matches all K/W Lua and both
  native identities; no private probe is shipped.

Package .8 is also retained because the accepted SWEP/tool/physgun button run used
it. .10 adds the first-grant occupied-hand marker and ownership cleanup; its B
logic is unchanged from .8. **Do not transfer measurements between these artifacts.**
Package .9 is an unmeasured intermediate build, superseded by .10. .1-.7 GMAs were
removed after their transactions restored; hash/build/raw evidence remains.

## What is implemented

- Seven stock guns: primary-only empty/ejected hold, A eject/hold-secondary,
  shoulder ammo, authoritative token/pose/reserve/obstruction checked insertion;
  shotgun +1 shells, crossbow bolt and RPG ready latch (native RPG charges reserve
  on firing, so insertion does not charge it again).
- Model-local ports and aim-to-model frames; W's muzzle angles are gun aim, not
  attachment rotation. Client 6 cm/55 degrees; server 16 cm/75 degrees, fresh
  tracking <=250 ms and carry <=30 s. Shoulder: 6..42 cm behind, 12..50 cm sideways,
  -28..18 cm vertically, in head-yaw coordinates. Server excludes P's own proxies.
- Native/client-box physics drops, deduped, ten game seconds; normalized stock
  visual lengths .12/.07/.16/.14/.065/.50/.65 m. Cleanup on lifecycle/failure.
- B tap latches until a real command consumes it; context changes cancel it.
  Zero-number/zero-tick preview calls retain their predicted bit. B holds belong T.
- Ammo overlay 387 x129, width .16 m, raw main-hand device, numeric repaint only,
  hide for no ammo/disabled/wheel. Protocol messages 80/81/82. Debug state/counters.
- A fresh grant occupies the off hand in resolver 250 **before** W's frame callback,
  even before a local model exists. K's explicit marker tag makes cleanup safe
  after that model is created. Both ordering and cleanup regressions pass.

## Verified evidence (paths relative to out/vr/v4k)

**Offline:** `offline-final.log`, **72/72 PASS =64 LuaJIT +8 Python receipt/lock cases**.
The exact gate bridge is unchanged: `companion/tests/vr_reload_test.py` via
`tools/tests/test_companion_vr_reload.py`. Uses K's own W stand-in, not a native
engine simulator. Covers holds/release/cooldowns, inventory, checks, A/B, preview
commands, hand ordering, counter, physics requests/dedup/TTL and cleanup.

**Full Release gate already PASS on frozen production source:**
`release-final.log`, `release-final.exit` =0, `release-final-source.json` =15049a90,
clean at start. **34/34 CTests, 48.24 s; Python 29+26+1214 =1269 tests**, main group
148.513 s; skips 1+1+6 =8. No new gate ran during parking.

**Native calibration:** `sim-calibrate-01`, package .2, PASS. All seven stock assets
exist/validate and muzzle/model frames were measured. 1041 rendered/matched, zero
SDK submissions/errors/unmatched/Lua/module errors. Calibration input for later
runs: `sim-calibrate-01/reload.json`. Source predates future C's corrected frames.

**Earlier physical state proof:** `sim-physical-05`, package .4, PASS for all seven:
10546 rendered/matched; empty/ejected hold 5.243..6.399 wall seconds, real empty
attack attempts, no native reload/switch, exact return/insert arithmetic, three
shotgun shells, crossbow cycles, exactly one RPG charge per shot. Per-gun numbers
are in the report and `reload-checks.json`. **Not final .10 visual acceptance.**
Old held shots faced away from shoulder ammo; later camera-only fixture changes
bring the item forward at 8.6 s and look at the calibrated loading port.

**Earlier stock button proof:** `sim-button-01`, package .4, all seven PASS,
10612 rendered/matched. Final .10 stock B repeat is still unrun.

**B-latch/toolgun investigation and accepted fix:**

- `sim-tools-button-03`: feature FAIL, two release edges lost; render-only gap
  reproduced by `b-command-gap-before.log`; fixed in `16a128c0`.
- `sim-tools-button-05`: SWEP/physgun PASS, tool B missing. Remains failed.
- `sim-tool-button-trace-01`, package .7: diagnostic PASS when B landed on a real
  command. **189 preview calls among 350 command samples**. `b-preview-before.log`
  separately reproduces consuming a pending tap on a preview. `231d4f6d` fixes it.
- **`sim-tools-button-final`, package .8, PASS:** 5002 rendered/matched, zero errors;
  SWEP/toolgun/physgun each one server reload tick and one original callback.
  Tool B writes one preview then real command 4701, server tick 4769. See
  `button-witness.json`, `reload-checks.json`, `reload.json`. Counter: 251 matrices,
  max error 1.49e-8 m, two stable groups, paints 1..4. The native B fix is verified;
  remaining work is final .10 stock/combined validation, not a blind re-investigation.

**`sim-empty-01`, package .10, finished during parking and PASS:**

- `reload-checks.json`: all seven reserve=0, no pickup, primary held/same weapon.
  Sampled hold durations 6.822..7.357 wall seconds.
- `summary.json`: **10839 rendered/matched**, 0 SDK submissions, Submit errors,
  unmatched, drops, Lua errors or managed-module errors; normal quit.
- Counter: 566 matrices, max positional error 0 m, seven stable groups, paints 1..5.
- `sim-empty-01-analysis.log`, `sim-empty-01.exit` =0 were written during parking.
- `restoration.json`: clean, all original roots restored, all **2877 depot files**
  valid, no missing/size/hash mismatches. Protected-before/after identical.
- Pending marker and K PoC lock absent; original driver PIDs 63320/66220/71836
  exited by themselves. No rollback repair was needed.
- `ntfs-compression.json` and its log: **363 files /3,317,180,801 logical bytes**,
  full before/after size/SHA verified, compact exit0. Raw paths/content unchanged.

Every accepted completed run has clean rollback/protected receipts. There has
been no K Index session yet. `sim-button-final`, `sim-physical-final`, `index-final`
did not exist at parking and were never launched.

## Other failed runs and operational cautions

Keep failed evidence. `sim-physical-01`: pre-map AV at known
nvoglv64.dll+0xe622f8. `sim-physical-04`: pre-map execute AV at0x100000011,
unclassified. Both restored. `sim-physical-02`/`sim-pistol-03`: rejected diagnostics
of the pistol idle getter and phase/after-Exit sampling; not relabelled passes.
The pistol getter can reset to CurTime-.115 after the native decision; proof
uses command readback **and actual empty attack attempts**, not its idle getter.
The redundant post-think hook was removed. ADR0179/report explain the mechanism.

`sim-tools-button-01` used the wrong observer name; corrected to real
OnPhysgunReload (returns nil, preserves default behavior). Queue entries02/04
were cancelled before preparation for driver/poll upgrades. K's 250-ms lock poll
uses atomic create/inherited exact-token release; it never evicts foreign owners.

Claude stopped `out/vr/v4k/run-final-simulations-v10.py` after starting empty01.
**Do not restart that batch or older batches:** they include already-completed
evidence names. No automatic follow-up controller is left. Use individual commands
below and new suffixes if a destination already exists; never overwrite a failure.

## Exact next steps when the user resumes

1. Read the rules/notes, inspect `git status` and `git log vr2`, read any newly
   accepted Q/W/C report. Merge reviewed vr2 inbound if required by the plan.
   C changes raw-controller versus palm/tip frames: recalibrate/adapt the private
   pose driver and rebuild to a new package version if those changes land. Keep
   each frozen artifact's measurements distinct. No new native import is needed
   for the current .10 source.
2. Check shared PoC pending marker/locks. Never prepare over an unfinished marker;
   recover only its matching run with the documented rollback. Never remove a
   foreign lock. Current .10 has an exact `package-audit-10.json` already.
3. Run **stock B off** simulation, require driver and analyzer exit0:

```powershell
py -3 -B companion/tests/vr_reload_poc.py --package out/dist/gmod-rtx-remix-0.0.0-v4k.10.gma --evidence out/vr/v4k/sim-button-final --simulate --button --calibration out/vr/v4k/sim-calibrate-01/reload.json --seconds 145 *> out/vr/v4k/sim-button-final-driver.log
python -B companion/tests/vr_reload_analyse.py out/vr/v4k/sim-button-final --button *> out/vr/v4k/sim-button-final-analysis.log
```

4. Run the **final seven-class physical sequence**, same success requirements:

```powershell
py -3 -B companion/tests/vr_reload_poc.py --package out/dist/gmod-rtx-remix-0.0.0-v4k.10.gma --evidence out/vr/v4k/sim-physical-final --simulate --calibration out/vr/v4k/sim-calibrate-01/reload.json --seconds 145 *> out/vr/v4k/sim-physical-final-driver.log
python -B companion/tests/vr_reload_analyse.py out/vr/v4k/sim-physical-final *> out/vr/v4k/sim-physical-final-analysis.log
```

5. Inspect raw images `sim-physical-final/captures/<class>-{held,well,after}/`:
   centre, both eyes, known ammo overlay source. Confirm normalized items visible
   in the hand and at loading ports, not merely successful arithmetic. Captures
   carry actual debug `held_metres`. View one large image per tool call (two raw
   3K images together exceeded the tool's IPC limit). Preserve failures and fix
   actual problems within K scope. Analyze/compress each completed run only after
   restoration is clean:

```powershell
python -B out/vr/v4k/compress-captures.py sim-button-final
python -B out/vr/v4k/compress-captures.py sim-physical-final
```

6. **Index last, nobody wearing it, both locks** (omit --simulate). This exercises
   one full SMG reload plus unchanged-number counter motion. Use existing SteamVR
   settings, never quit it:

```powershell
py -3 -B companion/tests/vr_reload_poc.py --package out/dist/gmod-rtx-remix-0.0.0-v4k.10.gma --evidence out/vr/v4k/index-final --classes weapon_smg1 --calibration out/vr/v4k/sim-calibrate-01/reload.json --counter-motion --seconds 35 --window 3840x2160 *> out/vr/v4k/index-final-driver.log
python -B companion/tests/vr_reload_analyse.py out/vr/v4k/index-final *> out/vr/v4k/index-final-analysis.log
```

   Expected hand translation .217 m and yaw30, native SDK absolute transform error
   <=2 cm, unchanged numbers do not repaint, exact nonblank 387x129 source, visible
   SDK texture/transform errors0. Save actual compositor counters/presents/
   reprojections and haptic result, inspect moved/returned captures, verify clean
   Exit/rollback. Script mode composes virtual hand attachment through the real
   SDK absolute overlay API; this is not a worn physical-controller alignment test.
7. Finish `VR-V4-K-report.md` with selected per-artifact numbers, pictures, all
   limits and text for Q's shared docs. Audit package/source/identity/scope and
   clean status. The ignored `audit-package.py` whitelist includes this explicitly
   requested resume note. The Release gate above already passes this production
   code; rerun `tools/test.ps1 -Config Release` after any code/inbound change.
   Verify doc conventions after report edits. Commit with required identity/trailer;
   never push/merge outward. Final response: built, evidence/tests/numbers, open.

Use `py -3` for feature drivers (installed Python3.12 has Pillow); the usual
Miniconda `python` works for analysis/offline/gates. All individual sessions stay
under three active minutes. For a failed/prepared owned run, recovery command is:

```powershell
py -3 -B tools/vr_session.py --evidence out/vr/v4k/<matching-run> --rollback
```

Then verify restoration/protected/depot receipts before anything else. The shared
pending marker is main checkout `out/r10/vr-poc-pending.json`; locks are main
`out/r10/poc.lock` and `out/vr/vr.lock`, not worktree-local paths.

## What waits on other tasks / open questions

No user clarification is required. K uses W's stable public interface. C's natural
wrist/palm/tip correction and Q's continuing review may require recalibration and
retests; do not edit their files. T/wheel combined input/overlay behavior and full
V4 acceptance belong to Q after reviewed merges. Worn comfort/readability/haptic
feel, natural controller alignment, other devices and existing Q/R ghost/startup
limits remain open. K has not accepted the milestone, published a package or
changed SteamVR/field settings. The immediate K work is the two named simulations,
visual QA, final Index proof and final handover/audit.
