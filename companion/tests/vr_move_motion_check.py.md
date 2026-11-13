# vr_move_motion_check.py

`python companion/tests/vr_move_motion_check.py <evidence> [--require-smooth]` compares actual
rendered-frame camera/engine/core/network positions with the latest authoritative FinishMove sample
at the same-process monotonic timestamp. Records raw step mean, standard deviation, extrema,
p05/p95 spread, near-zero steps and origin lag for steady walking/sprint/full-trigger flight.
Also reports step spread normalized for render-interval variation (so a genuine longer rendered
frame is not mistaken for tick stepping), and the largest backwards step after sprint release.
Writes `motion-frames.csv` and `motion-analysis.json` only inside the named evidence folder.
Missing samples fail. `--require-smooth` requires normalized p05..p95 step spread <=10% of mean
and backwards stopping step <0.1 units, plus the standard native acceptance. Exit 0 passes, 1
fails; bad inputs raise ordinary CLI errors. No external dependencies, game or Steam operations.

Q can supply explicit measured intervals/stop window. The minimum 20 rendered samples and 10% smoothness guard remain unchanged; legacy callers retain the original windows.
