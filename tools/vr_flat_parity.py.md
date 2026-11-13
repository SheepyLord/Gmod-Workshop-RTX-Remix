# vr_flat_parity.py

Runs five plus five alternating complete VR-off launches, published/candidate, with one map,
pose, window and settings. `py -3 tools/vr_flat_parity.py --package out/dist/candidate.gma --evidence
out/vr/v2q/new-parity`. The published baseline is read from the main checkout's publication
receipt and its entire GMA SHA-256 must match. Nothing is published. Uses the PoC lock only;
the standard driver snapshots, restores and validates every launch. Requires Pillow.

Reports each launch's timed frame-interval median, median of those five medians, launch-to-map
ready times, all client/server hooks/timers/receivers, explicit empty off VR inventories and
the one expected candidate server stub receiver. Screenshots are compared pairwise with RGB
mean absolute and RMS differences and raw difference images. These numbers are observations;
they do not label a noisy sample a speedup or prove perceptual parity on their own.

Predeclared numeric guards: the candidate median of frame medians may increase by at most
the larger of 0.25 ms or 5%; median launch-to-map by at most 1 s or 10%; each paired full-RGB
mean difference may be at most the largest published-to-published difference plus 1/255.
These are practical detection bounds, not claims of mathematical zero cost. Full raw inventory
differences are retained in addition to the strict VR-specific off checks.

`--analyse` rebuilds the aggregate without launching; missing/failed launches remain failures.
`--run N` runs only an explicitly selected absent launch, preserving all existing evidence.
A failed batch stops for diagnosis; use a fresh evidence batch to repeat it. Internal `--one`
invokes one isolated production-driver process. Each launch has 20 timed flat seconds; the
camera is held for three more seconds so the final screenshot precedes camera cleanup.

Outputs normal evidence and parity.json/baseline-identity.json under out. Invokes only the
authorised field-game normal-quit helper when necessary and records it. No depot/user.conf,
SteamVR setting, loader source or package input is edited. Exit 0 only for ten complete
passing launches and required off inventories/images; nonzero on any missing/failing item.

Large server inventories use the same bounded numbered base64 transport as the client, with
server record IDs above 900000 to avoid collisions. Truncated/missing chunks remain fatal.

Timer lists come from the engine lua_dumptimers_cl/sv console commands after the timed window,
with begin/end markers and delivery receipts. This build has no timer.GetTable. Known VR
session timer existence is checked directly; raw complete dump output remains in each console log.

Aggregation requires complete available engine timer dumps with no VR timer. Missing markers,
unknown dump commands or a remaining VR timer fail, independently of native frame success.

Each completed child yields 3.2 seconds outside the locks before the next launch, allowing
other already-waiting labs a turn; the timed flat sample is unchanged.

Timer parsing retains exact names/source lines without name normalization. The patcher's suffix
is its patch ID encoded as hex, not a numeric instance. Raw time/repetition/paused fields remain
in the dump. Paired additions/removals and published-to-published variation are both reported.
Candidate hooks/receivers/timers must retain the published common set and add nothing beyond
the published union except the declared dormant stub receiver/page hook. An unexplained callback
fails even when its name does not start with nlvr. Numerical tolerances remain unchanged.

--run N --retry-preparation preserves an installation failure in its original folder and selects
a fresh canonical-N-retry-M folder, recorded in attempt-selection.json. It requires no game.log,
no summary and an actual failed install with no run step. A launched (even failed) game cannot
be substituted; that needs a new batch. This preserves the five-plus-five actual game alternation
when preparation never launched one. Original parity.json stays failed; parity-recovered.json
contains the selected ten complete game runs plus all failed-preparation pointers.


Each alternating child uses the normal --package/--evidence CLI with private --single, so the shared known-crash retry can reproduce the complete child and its reducers in a fresh folder. Legacy --one is normalized first. Aggregation follows only a recorded successful first known retry with verified parent restoration and matching one-use claim; unknown, repeated, outside-root or unclaimed attempts cannot replace a launch. All original folders remain. limited-flat-policy.json records no VR start, targets, damage or world-entity removal; the static driver decoration remains until normal quit.
