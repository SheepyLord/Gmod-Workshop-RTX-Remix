# workshop_update_fixtures.py

Builds two local packages for the [Workshop update game check](../../docs/handover/workshop-updates-report.md).
Run from this worktree with a cache that contains both Faelynn (Gym Uniform) assets from the field
report and Helena (Dorm).

```powershell
python -I tools/qa/workshop_update_fixtures.py "<field install>/garrysmod/data/mmd_hotloader"
```

The cache is read-only. The tool writes each Hotloader add-on, its local GMA and its inventory
under `out/wsup/fixtures/v1` or `v2`. Supply `--out` with a fresh directory under `out` to
repeat the build. The offline packer needs Windows. The revised Gym mesh gets a new asset hash.
Helena keeps its asset hash and gets a valid manifest with different bytes at the same length.
Each build records the padded raw size in the inner manifest along with the digest and packed
size. The tool checks the packed control bytes and prints both digests for comparison with the
PoC cache. The [two-launch driver](workshop_update_session.py.md) decodes every packet from the
finished archives before configuring the PoC. Exit 0 means both archives were built.
Input, packaging or validation errors exit nonzero.
