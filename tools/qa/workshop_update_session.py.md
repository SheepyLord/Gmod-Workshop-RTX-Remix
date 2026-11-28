# workshop_update_session.py

Runs the WU character update check unattended against the PoC. From the worktree, choose a new evidence directory.

```powershell
$e = 'out/wsup/game-' + [DateTime]::UtcNow.ToString('yyyyMMdd-HHmmss')
python -I tools/qa/workshop_update_session.py --evidence $e --plan
python -I tools/qa/workshop_update_session.py --evidence $e
```

`--plan` opens the two local GMAs, unpacks every Hotloader packet against the published size and SHA-256, and prints the four `poc_session.py` commands. Normal execution takes the shared PoC lock, snapshots the install, sets aside its existing add-ons, cache and saves, then stages the two QA Lua files. It installs the branch RTX package and v1, runs v1, configures v2 and runs v2. It supplies the selector recorded in v1 as the second launch's initial `cl_playermodel`.

The driver verifies each session's `NL_WU` output, shot acknowledgements and images, deployed fixture version, RTX activation and normal exit. It keeps both `*-results.json` files, the original `v1.gms`, `baseline.json`, the PoC logs and side-view screenshots under the evidence directory. Restoration runs on success and on failure. A clean run ends with `PASS WU` and `restoration.json` records the rollback. After an interrupted run, with the PoC closed, the recovery command uses the same evidence directory.

```powershell
python -I tools/qa/workshop_update_session.py --evidence $e --restore
```

Requires Windows, the Release loader tools, the branch RTX GMA in `out/wsup/rtx`, and the [fixture archives](workshop_update_fixtures.py.md) in `out/wsup/fixtures`. Exit 0 means the selected operation completed. An invalid archive, failed observation, missing screenshot or unverified rollback exits nonzero. [Exact commands and acceptance values](../../docs/handover/workshop-updates-report.md#claudes-two-launch-poc-check)
