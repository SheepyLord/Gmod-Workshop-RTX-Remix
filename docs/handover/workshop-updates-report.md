# WU · Workshop character updates

Branch `workshop-updates`, based on `55e5dcfc`. The revised Workshop model takes the previous
entry's place. NPC and player choices move to carriers built for the new geometry. Older saves can
still load. The change ships in the Model Hotloader part of the RTX package. [ADR 0278](../decisions/0278-workshop-character-updates-follow-the-pack-model.md)

## Why resubscribing appeared to help

On November 28 Steam downloaded the GF2 A update at 07:48 UTC. The loader deployed it at 09:54 and
the Hotloader installed the corrected Faelynn (Gym Uniform) at 09:57:01. At 10:20:28 the player's
history still recorded the earlier asset. Both entries bore the same name, and the cached Citizen
and player carriers referenced the old ID. The installed and published GMA hashes matched.
Resubscribing ultimately redeployed that same archive. [Field records](../RESEARCH.md#gf2-a-reached-the-game-before-the-old-head-was-selected-2026-11-28)

The inner package changes ID on every export. The Gym item's `terms.file` remains
`GirlsFrontline FaelynnSSR0101.pmx`. A pack-scoped item key or unique source now identifies that
model through a new export, display name or asset hash. The old field record can be recovered
from its saved Workshop terms and the earlier build ID on surviving siblings. The loader journal
also identifies both current and previous pack owners, including a one-model update with no
surviving sibling. A legacy record
without enough evidence cannot safely transfer its choices. Authors can give ambiguous sources
permanent keys with the offline packer's `--model-key`.

An in-place revision has a separate check. The install record keeps the hashes of `manifest.json`
and `model.bin`, and a pending update survives a closed game. Already-loaded copies can need a
restart. The library moves after its successor checks out. Cleanup retains the old bytes while a
live entity or generated save carrier refers to them. Steam fetching an update during play still
requires the next start before the loader can deploy it.

## Automated checks

`tools/test.ps1 -Config Release` passed at **11:43:07 UTC on 2026-11-28**, with the pinned fixes
checkout available. All 35 CTests passed. The three Python suites reported 2,338 tests with nine
skips. The Workshop install harness ran all 29 scenarios and the actor harness ran all 13.
`tools/inputs.py verify` checked 16 parts and reported zero problems.

The [Workshop harness](../../tools/tests/hotloader_workshop_install_harness.lua.md#pack-updates)
uses the packaged Lua to install revisions, including a field-shaped cache with both Gym entries.
The [actor harness](../../tools/tests/mmd_lazy_load_harness.lua.md) checks the player selector,
Citizens, arms, recent timestamps and loading a save through the duplicator. It also exercises
withdrawn multiplayer approvals. A read-only replay also fed the shipped matcher the field
install records, mounted manifests, saved Workshop terms and loader journal. It found exactly
one replacement, `7c6d7e466389…` to `a95c9a34a5ee…`, in Steam item `3847047590`.

The worktree's `nlctl manifest` accepted both local content archives. The full branch RTX archive
is in `out/wsup/rtx`, version `0.0.0-dev.20261128114114+daa2c523`, 2,280 files,
SHA-256 `ad601fc9182b8e6ae1fe3b191415a6a46f0dd60dde4ced08744f71197aa6772f`.
All 15 changed Lua and localization files in that GMA matched both the worktree and its input
index byte for byte. The full package build finished at **11:41:38 UTC on November 28, 2026**.
The live PoC appearance and selection check is pending.

## Claude's two-launch PoC check

Run these commands from the `workshop-updates` worktree. The second command is an offline preflight.
The third runs both game launches and restores the PoC automatically.

```powershell
$e = 'out/wsup/game-' + [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss')
python -I tools/qa/workshop_update_session.py --evidence $e --plan
python -I tools/qa/workshop_update_session.py --evidence $e
```

The driver takes the shared PoC lock, snapshots the install and sets its existing data, saves
and add-ons aside. It stages the [client probe](../../tools/qa/workshop_update_probe.lua.md) and
[pose helper](../../tools/qa/workshop_update_pose.lua.md). V1 records the actual save filename,
its SHA-256, the selected player model and three immutable carrier keys. The session tool restores
Steam Cloud settings at quit, so the driver supplies the **observed v1 selector** at v2 startup.
V2 reads the migrated registrations and history before any new spawn. It uses the registered
Citizen entry from the NPC tab, photographs it, then issues `gm_load` on the recorded v1 file.
Sandbox pastes a same-map save in place. A fresh Lua realm also resumes the saved-actor check.
Both launches use single-player `gm_flatgrass` to match the GF2 head comparison.

### Session commands in execution order

These are the four `poc_session.py` calls inside the driver. The driver prepares the isolated
cache, installs the probe add-on and writes the phase request around these calls.

```powershell
$session = @('tools/poc_session.py', '--evidence', "$e/poc")
$rtx = 'out/wsup/rtx/gmod-rtx-remix-0.0.0-dev.20261128114114_daa2c523.gma'
$v1 = 'out/wsup/fixtures/v1/wu-fixture.gma'
$v2 = 'out/wsup/fixtures/v2/wu-fixture.gma'
$game = @('--map','gm_flatgrass','--players','1','--addons','--extra=-insecure','--extra=+gamemode','--extra=sandbox')
$probe = @('--console','engine_no_focus_sleep 0','--console','gmod_npcweapon none','--console','hideconsole',
           '--hide-hud','--lua','tools/qa/workshop_update_probe.lua','--lua-shots','780','--screenshots','0',
           '--settle','0','--width','1600','--height','900','--timeout','900')

python @session install --replace-config --allow-local $rtx --allow-local $v1 --subscribed-content off --remix on
python @session run --name v1 @game @probe
python @session config --allow-local $rtx --allow-local $v2 --subscribed-content off --remix on
$selector = (Get-Content -Raw "$e/baseline.json" | ConvertFrom-Json).selector
python @session run --name v2 @game --extra=+cl_playermodel "--extra=$selector" @probe
```

The driver restores and verifies the original PoC directories, loader files, configuration,
registry and saves in its final step. It keeps the actual v1 `.gms` and the three screenshots.
After reinstating the original directories, it runs
`python tools/field_snapshot.py --snapshot "$e/snapshot" rollback --config Release`.
To finish restoration after an interrupted run, use the same evidence directory with the PoC closed.

```powershell
python -I tools/qa/workshop_update_session.py --evidence $e --restore
```

### Pass and fail values

Each probe observation occupies one `NL_WU` JSON line of fewer than 500 bytes. The expected
Gym assets begin with **`7c6d7e466389`** in v1 and **`a95c9a34a5ee`** in v2. Helena stays
**`81b3caae0303`** throughout. The verifier compares full asset IDs.

| Observation | Pass |
|---|---|
| `entry`, `library` | Two fixture rows, exactly one Gym and one Helena, install idle. Gym uses the expected ID for that phase. In v2 `replacement` is the corrected Gym ID, including after loading the save. |
| `player`, `rendered`, `published`, `npc_entry` | `cl_playermodel` is `mmd_` plus the first 16 digits of the body key. The host body and actual hands model resolve to the expected Gym ID and their published player/arms keys. The NPC tab and its saved Citizen rig agree. V2 has new keys before the probe spawns anything. |
| `recent` | V1 records the old Gym. V2's `before_spawn` history includes the new Gym at a time at least as recent as v1 and excludes the old Gym. The `after_spawn` observations identify the current rigs and recent use again. |
| `spawn`, `head` | The host spawns a Citizen ahead. In the generated `Reference` sequence at cycle zero and scale **1.15** (tolerance 0.001), the current rendered eye midpoint to head distance is **2.756 ± 0.03** Source units in v1 and **2.607 ± 0.03** in v2. The rig and attached asset must agree. |
| `helena` | Exactly **63,247 bytes** in both runs. The SHA-256 of the actual cache file and the install record both equal `663b8b295a042f8e8f448a8d4f4734d1d74b5f062d1368d0340cd38ca1bbae5a` in v1 and `2747fec1c9ae250309ab6c9a01100d0a10bf874173f9be4d893a0b1c4dd83c59` in v2. |
| `save`, `load`, `head.view=restored` | The v2 load uses the exact v1 filename, size and digest. Sandbox pastes the NPC carrying the run token saved by the v1 duplicator modifier. Its rig key equals the v1 Citizen key, both asset IDs are the old Gym, and its measured distance is **2.756 ± 0.03**. |
| `result` and session receipts | Both phases end with `ok=true`, zero mismatches and `NL_SHOT_DONE`. All three acknowledged PNGs exist, both games exit normally under RTX, and `restoration.json` reports `clean=true`. |

A timeout, stale palette, wrong selector, duplicate row, out-of-tolerance distance, missing saved
actor, image or receipt, or failed restoration fails the run. Evidence is in `$e/v1-results.json`,
`$e/v2-results.json`, `$e/baseline.json`, `$e/v1.gms`, and `$e/poc/{v1,v2}/`. The image labels are
`wu_v1_head`, `wu_v2_head` and `wu_restored_head`. The probe samples the submitted `MMDRenderPose`
matrices for `ValveBiped.Bip01_Head1`, `Eye_L` and `Eye_R` in the same frame as its side camera.
It holds that view for the external screenshot acknowledgement.
The published reference values and bone names come from
`<modding>/ipg/GF2RTX/tools/head_probe/README.md` and its `gf2_head_probe.lua`.

The follow-up preflight found one incorrect field in the original fixtures. Their Helena packet
contained 63,247 raw bytes but declared 63,246 in the inner manifest. The builder now writes the
actual padded length. The regenerated local archives have SHA-256
`e3040348b5fa88793b9c2eacd535d20509aba35251906f974a034237c60832c4` (v1) and
`bc1074b2fab2d1e83a0926df17ef4fd3fe794cc2244d12db3445ec0cf5bde23b` (v2). Both passed
`nlctl manifest` and every archived Hotloader packet decoded against its declared length and hash.
The [offline harness](../../tools/tests/test_workshop_update_session.py.md) exercises the probes
and their verdicts. Both Lua files passed LuaJIT syntax checking. The longest encoded client
console command was 224 bytes. The mocked two-launch driver verified restoration after a pass
and a failed measurement. The follow-up Release gate passed at 12:07:37 UTC on November 28.
All five focused WU tests passed, including the final runner handoff and rollback test.

### Claude's run (2026-11-28): PASS

`tools/qa/workshop_update_session.py` ran both launches unattended in the PoC (RTX on, gm_flatgrass, 1600x900, the
branch package `0.0.0-dev.20261128114114+daa2c523`). The runner's verdict was "PASS WU. Both launches, the saved actor
and PoC restoration verified". The `NL_WU` lines show:

| Observation | v1 (old pack) | v2 (updated pack) |
|---|---|---|
| Library | 2 rows; one Faelynn (Gym Uniform), at `7c6d7e466389...` | 2 rows; one Faelynn (Gym Uniform), at `a95c9a34a5ee...`; `replacement` names it |
| Player model and hands | `mmd_4dde9550031aa7ac` and their arms key, old asset | `mmd_4ca7eecad81f74ee` and new arms key, new asset, before anything spawned; the NPC entry and the recent list moved too |
| Citizen at 1.15, eye midpoint to head (Reference, cycle 0) | 2.7558 | 2.6075 |
| Helena's manifest | 63,247 bytes, `663b8b29...` | 63,247 bytes, `2747fec1...` (a same-size update, installed) |
| The v1 save loaded in v2 | | Its Citizen on the old asset and carrier key, 2.7560; afterwards the library still shows one Gym row |

The side views (`wu_v1_head`, `wu_v2_head`) show the old head ahead of the neck with light through the gap, and the
corrected head on the neck. The PoC was restored (`restoration.json`).

### Rebuilding the branch RTX archive

The default worktree scratch path made one HL2 texture path exactly 260 characters. The local
build used the same package builder and `nlctl` checks with the shorter `out/w` staging directory.
With the Release build present, the following reproduces that route from this worktree.

```powershell
@'
from pathlib import Path
import sys
sys.path.insert(0, str(Path("tools").resolve()))
import publish_workshop as build
from package_workshop import find_nlctl
assert find_nlctl()
config = build.load_config(build.CONFIG)
version = f"0.0.0-dev.{build.stamp()}+{build.fingerprint(config)[:8]}"
build.build(config, version, Path("out/w").resolve(), print, dest=Path("out/wsup/rtx").resolve())
'@ | python -I -
```

## State

- Merged to `main` as one commit, `5935a2cb`, on top of the glass fix, with ADR 0278 accepted. The Release gate passed
  on the merged tree first: 35 of 35 CTests, 2,288 Python tests of `tools`, one skipped.
- Uploaded to the Workshop item as **0.0.0-dev.20261128122050+ad5d946b**, its change note the changelog's entry.
- For the user's own game: the first start with this build moves the old Faelynn (Gym Uniform) entry and the choices
  that name it to the corrected model. The read-only replay of the field records found that one replacement and no
  other.