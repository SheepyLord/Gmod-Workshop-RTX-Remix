# vr_move_latency_check.py

`python companion/tests/vr_move_latency_check.py out/vr/v2l/<run> [--require-fixed]` reads real
CalcView rows from the standard driver's summary. Outputs per-frame `latency-frames.csv` and
`latency-analysis.json`: horizontal error mean/p95/max, signed error/speed lag for each ramp,
interpolated-reference cross-correlation lag for sway, step sizes and exact zero-step counts
while tracking moves. Stable interiors exclude acceleration boundaries. A tilted-head interval
checks preserved camera roll but zero command/player roll. No third-party dependencies.
When present, the separate after-Exit record also gives actual player/flat CalcView roll.
`--require-fixed` requires all segments/step-increment errors below 0.05 units, no tick-rate holds and zero command/player
roll; without it the tool measures a baseline without claiming a pass. Native acceptance is
required either way. Exit 0 passes the selected checks; 1 fails; missing data raises an error.
Reads/writes only the named repository evidence folder; no game/Steam changes or processes.
