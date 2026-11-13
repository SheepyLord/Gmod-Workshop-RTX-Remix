# VR V4 K: second verification corrections

Branch v4k, 2026-11-12. This supersedes the handover at198e45e5. All seven new
verification items are addressed below, with failing-before cases retained. Fresh
physical and B simulations pass on **.15**; B has a native-readiness+0.3 s bound,
not an unbounded acceptance window. No Index run was required because successful
counter placement/drawing output is unchanged. Whole V4/user acceptance remains separate.

## Item-by-item correction and tests

1. **B acceptance has a real upper bound.** Full-phase counting is used only to
   detect duplicate ticks. Delivery must be no earlier than the released tap and
   native readiness, and no later than0.3 s after readiness for every class. The
   readiness point is the maximum of released intent, observed server relative
   attack deadlines and client absolute deadlines aligned to the phase clock.
   Observations stop at the first client reload bit, excluding the lock caused by
   the reload itself. Deploy mode additionally requires the injected native lock;
   its argument is no longer unused. RPG checks native clipless reserve behavior
   as well as the same exact-tick/readiness/latency criteria. Counterexamples reject
   a10-second stale ACK delay, >.3 s late RPG delivery and late duplicate ticks.
   verify2-latency-before.log and verify2-own-reload-before.log retain failures.
   The .14 record remains valid at0.027..0.127 s, but is not used as .15 measurement.
2. **Core coalescing and safe lapse.** The harness uses the production Packet
   encoder, drops identical server signatures, replaces unsent state by type and
   delivers at most one packet/player/tick. The heartbeat test runs through that
   path; freezing its increment is a detected mutant. K latches A/B intent:
   an eject started in K cannot become a grenade/orb at an ACK edge or after a2 s
   hitch. A hitch cancels secondary-hold interpretation until release. Unknown or
   stale server state reserves the eject control, rather than handing its tap to W.
   Short-lapse policy/carry grace is5 real seconds; carries survive it on both
   halves, including temporary stale-sync invalidation. Insertion still needs fresh
   authority/poses. Explicit Stop, death, vehicle, release and weapon changes clear
   carry as appropriate; longer outages are bounded. Tests: verify_hitch_eject,
   verify_eject_ack_edge, verify_b_hitch_intent, verify_carry_hitch,
   verify_server_carry_hitch, verify_carry_stale_sync_hitch,
   verify_heartbeat_coalescing and the heartbeat mutant. The prior lease-expiry
   logic failures are in verify2-before.log/verify2-stale-pose-before.log.
3. **Glove lock/pull is busy.** Shoulder free-hand checks now include P's
   gloves_target/pulling state, in addition to props, climbing and other owners.
   verify_glove_lock and verify_glove_pull fail before and pass after; K never
   steals the grip from the glove action. No P/H/W/core file changed.
4. **Serial-based persistent retry.** Action81 adds a16-bit intent serial. State82
   carries persistent serial/kind/result in every later report, including rate
   refusal; routine reports cannot erase it. Client has one in-flight intent,
   retries it at bounded real-time spacing for up to5 s, and recognizes completed
   serial replays without repeating inventory effects. Refusal/timeout stays in
   debug. verify_retry_coalesced_state (also the revised review_retry_eject) couples
   real client and server paths: a slow game tick refuses eject, another packet
   occupies the slot, routine state replaces the pending reply, then the later
   ACK causes a successful retry. No rate ACK is manually injected.
5. **Map-restored holds are recognized.** A stock-gun primary deadline more than
  300 s ahead is treated as K's saved hold, never adopted as an external prior.
   Empty and already-loaded restored guns recover; normal nearer external
   cooldowns remain preserved. verify_map_hold inserts/fires after a saved-hour
   deadline; verify_map_loaded_hold releases it on a loaded gun. Both failed before.
6. **Stronger oracles and less counter allocation.** review_removed_prune inspects
   the actual production state.guns table through the closure, not a per-command
   counter. Removing both prune paths is a detected mutant. review_holster now
   returns to each gun, physically inserts and fires through the explicit engine
   oracle; a timer written into the future fails. review_idle_cost includes
   holster-write counts; removing the interval guard fails. The counter reuses one
   numeric buffer and scalar comparisons, making no per-frame value table/signature
   string. verify_counter_buffer checks identity and actual counter concat calls.
   The small oracle is still not a native engine implementation.
7. **Precise docs.** Carry rendering depends on fresh heartbeat ACKs plus bounded
   short-lapse grace; the no-heartbeat claim is removed. W message64's bounded
   muzzle offset<=1.5 m, pitch+/-45 degrees, foregrip<=0.65 m/two-hand re-aim and
   SafeMuzzle trace all contribute to the loading-port transform. Client-synced
   poses remain bounded client inputs, not independent tracking attestation.
   test_port_chain_documented enforces the missing details; its failure is retained.

K keeps [ADR0180](../decisions/0180-physical-vr-reload-gestures-and-checks.md).
The corrections implement the reviewed contract without changing the native
allowlist, hooks/convars outside K or the public W interface.

## Offline and gate evidence

Evidence root: **this worktree's out/vr/v4k/**. Current offline suite:
**132 cases (114 LuaJIT +18 Python)**, plus **33 scaffold cases**, pass.
verify2-offline.log / verify2-scaffold.log retain runs. The real encoder/coalescer
is used by default. Four mutation checks must fail when heartbeat advancement,
pruning, valid holster time or bounded timer writes are removed. New direct
failures are in verify2-before.log, verify2-latency-before.log,
verify2-docs-before.log, verify2-stale-pose-before.log and
verify2-own-reload-before.log. Passing counters cannot substitute for native proof.

Final **tools/test.ps1 -Config Release PASSES**, exit0: **34/34 CTests,28.78 s;
Python29+26+1274 =1329 tests**, main group144.251 s, skips1+1+6 =8. Includes all132
K cases and33 scaffold cases. Receipts: verify2-release.log / verify2-release.exit.
Only handover documentation changed afterward. Earlier gate logs, including the
interrupted NUL-tailed one, remain separate.

## Frozen .15 package

Production commit **8be81b82**; later analyzer/test/doc changes are not packaged.
Normal build: out/dist/gmod-rtx-remix-0.0.0-v4k.15.gma,
**2085773993 bytes**, SHA256
`7902f9cc13009f95976056652dd471fedfb9b6791c75d11fcce96a6148a9de18`.
1811 payload files /2085218570 payload bytes,1812 archive entries with manifest.
Digest `84b5f02531205d023399820a0423d8038b9f138ebdedb037798aeb4c8ca2bf53`.
package-source-15.json, package-15.log, package-audit-15.json and dist JSON retain
normal build/source identity. No private fixture is packaged. Native imports unchanged:

- Runtime418403840 bytes, SHA256
  `027aae44befc301774508b09401808fa16615592e05a02bcf64bd9d761123278`.
- Module510464 bytes, SHA256
  `a1628079de069a7a747d506a23ee8f7c957f18f8f7e2283155fd896205fc13b7`.

State82 appends configured-policy and persistent action serial/result. Both K
halves ship atomically. Action81 serial/lease/result widths are checked by the
actual packet encoder. Real-time one-per-tick/80 ms server limits remain; retries
are not a grant of extra inventory authority.

## Fresh native simulations (.15 only)

verify2-physical and verify2-button use fresh folders, simulation and the production
snapshot/install/normal quit/rollback driver. Render scale.5 gives actual eyes
1234x1370, centre1560x1376 and primary780x688; nominal recommendation2468x2740/90 Hz
is distinct. This reduces test rendering/capture cost without lowering inventory,
pose, five-second hold or latency acceptance criteria. Simulation loads no OpenVR.

| Run | Rendered/matched | Result |
|---|---:|---|
| verify2-physical | 10508/10508 | Seven-class physical sequence PASS |
| verify2-button | 10055/10055 | Seven ordinary/deploy B checks PASS after observer-cutoff correction |

Both have0 SDK submits/Submit errors/unmatched/drops/Lua/module errors, normal quit
and clean rollback: **2877 depot files valid**, original trees/registry/data/settings
restored and protected user.conf hashes identical. summary.json, reload.json,
reload-checks.json, reload-receipt.json and restoration.json retain raw evidence.

Physical hold seconds by class: pistol5.135, .3575.256, SMG1 5.244, AR2 5.241,
shotgun6.411, crossbow6.411, RPG5.878. All include actual empty attack attempts,
no engine reload/switch, constant reserve, shoulder take, insertion and firing again.
Native clip/reserve before/insert/after:

| Class | Empty | Insert | After firing |
|---|---|---|---|
| pistol | 0/62 | 18/44 | 17/44 |
| .357 | 0/62 | 6/56 | 5/56 |
| SMG1 | 0/61 | 45/16 | 43/16 |
| AR2 | 0/61 | 30/31 | 28/31 |
| shotgun | 0/60 | 1/59 then2/3 shells | 2/57 |
| crossbow | 0/60 | 1/59 | 0/59 |
| RPG | -1/59, logically empty | -1/59, logically loaded | -1/58, empty |

RPG first arms through production insertion, never defaults a free chamber.
Four ejects have live cosmetic physics. Physical counter:569 matrices, error0,
34 stable numeric groups, paints1..44. B:569 matrices, error0,21 groups, paints1..28.
Raw class pictures and declared counter sources are under each run's captures/.

### B delivery latencies and the retained analysis failure

| Class | B after native readiness, s |
|---|---:|
| pistol | .1226 |
| .357 | .0268 |
| SMG1 | .0134 |
| AR2 | .0909 |
| shotgun | .0277 |
| crossbow | .0255 |
| RPG | .0900 |

All are below **.3 s**, with exactly one native reload tick/class and nonpositive
native player attack lock at delivery. Native deadline/release/delivery/bound
values are in measurements[<class>].B in reload-checks.json.

Initial analysis rejected AR2: a client sample0.5 ms before the server receipt
already contained the reload's own new lock. That incorrectly made readiness a
future time. reload-checks-original-own-reload-lock.json and the original exit1/log
remain; verify2-own-reload-before.log fails on that counterexample. Observation
now stops at the first client reload bit, before the action can create a new lock.
The actual .3 s upper bound is unchanged. Corrected pass/exit0 is in
verify2-button-analysis-corrected.log and verify2-button-corrected.exit.

## Historical discrepancies, safety and open work

The previous review's native .10 holster baselines did **not** refill SMG/pistol
after4.4 s in Hands with sk_auto_reload_time=3. The SDK oracle reproduces that
route, and .11 verifies fresh timers/return/insert/fire, but a native holster
refill/deadlock is not claimed reproduced in this GMod build. Those artifacts are
not relabelled current .15. The earlier .14 Index run and its counts remain
historical; counter placement/painter output did not change, so no new Index run.

The prior field preflight invoked the prescribed external quit helper, whose log
shows forced tree termination of PID36876 after90 s without a console window.
That actual event was reported and retained. K subsequently switched to direct
normal-only console quit; it records forced=false and safely refuses without a
console. It never calls that force fallback again. No field files were edited.

A machine blue screen interrupted K while queued, without K preparing a PoC
transaction; Claude archived the other worker's stale lock. K did not touch it.
Fresh post-reboot folders were used, and no K game or machine crashed afterward.
Failed/queued/observer records are preserved, including the earlier2.203 s capture
hitch, lease lapse and missed SMG gesture. Per-gun state survived; the new short
carry/intent tests cover the danger exposed by that lapse. No foreign lock or
other worker evidence was removed. Captures may be NTFS-compressed only after
full size/SHA checks, with per-run manifests; unique failed evidence is kept.

Open: C's natural wrist/palm/tip and small/occluded item fit; Q's combined V4/T/wheel
acceptance; worn comfort/readability/haptic feel and other devices; existing Q/R
startup/ghost/disocclusion limits. A raw wrist item can obscure a small shell or
.357 well; K-specific grip offsets may still be needed after C. No W/H/P/core
source change was made or requested by this implementation. No milestone approval.

## Text for Q's additive shared docs

- CHANGELOG: safe reload intent/carry across short lapses, persistent idempotent
  action ACK/retry under coalescing, glove busy guards and saved-map hold recovery.
- COMPONENTS: K81 includes an intent serial;82 includes configured policy and a
  persistent action result. Availability/pose authority still gates inventory.
- TESTING:132 K cases plus33 scaffold; real packet coalescing, mutation guards,
 2 s hitch and slow-tick coupled cases; B readiness+.3 s in native receipts.
- RESEARCH: distinguish prerequisite native readiness from a reload's own new lock;
  full-phase duplicate counting is not a latency acceptance window. W64's pitch,
  foregrip re-aim and SafeMuzzle trace are part of the bounded client-input chain.
