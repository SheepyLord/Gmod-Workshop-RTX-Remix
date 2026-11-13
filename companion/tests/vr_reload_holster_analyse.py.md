# Native holster evidence analysis

`python -B companion/tests/vr_reload_holster_analyse.py <evidence> [--baseline]`.
Reads the completed transactional holster run. Writes holster-checks.json: actual
watched clip/reserve/timer before, while in Hands and after returning, elapsed
holster interval, and post-insertion native state. Baseline mode reports whether
the reported bug actually reproduced; a clean baseline probe is not a claim of
reproduction. After mode requires no refill, preserved reserve, a fresh relative
holster timer and successful subsequent insertion. Parent metadata, managed-error
and restoration checks remain required. Exit0 passes those mode-specific checks;
nonzero fails. No game process, settings or network side effects.

Cycling requires the observed native clip to decrease after insertion, with unchanged reserve; merely observing a loaded gun or an attack attempt cannot pass it. The offline no-fire counterexample enforces this.
