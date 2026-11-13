# vr_ui_flat_probe.lua

Test-only diagnostic selected by vr_ui_poc.py --flat-probe --seconds 25. Drives the production flat-panel
pointer against the real HTML Resume button, with original cursor dispatch, OS cursor movement only,
relative cursor deltas, key-code dispatch and double-press dispatch. Records both native cursor getters,
hover/focus classes, argument/state snapshots and whether each actual click resumed. No call simulates a
successful Resume; explicit Hide/Activate resets happen only after measuring each attempt. The standard
driver owns locks, snapshots, quit and rollback. Restores all overridden test functions at Exit. No standalone
use, persistent settings or process exit code. Captures and bounded JSON stay under the launcher's out root.

Corrected acceptance requires menu_before_press=true as well as hidden afterward. Hide and reactivation
are separated across frames. --probe-setters first opens client popups and compares both setters, client
clicker off/on, reset, GMod and raw native mouse codes; use --seconds 35 for all seven attempts. Desktop
focus and both getters are recorded. The early probes' positive reset results are explicitly excluded in
the report because they lacked the before-press assertion.
