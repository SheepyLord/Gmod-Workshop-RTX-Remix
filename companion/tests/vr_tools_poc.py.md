# vr_tools_poc.py

T evidence uses bounded NLVR_T_CHUNK records for JSON over 3000 bytes: per-realm sequence,
2800-character base64 pieces, maximum 1024 pieces. The reader validates counts/duplicates/
completion and restores original record order. Truncated console output is a failure,
never silently ignored. Camera evidence retains only needed projection fields.

--tools-case linear_trial is a labelled 30-second experiment on a frozen package:
stationary yaw-90 hold, private zero-linear-force, COM-target and no-Use variants.
It is not a production/full-feature pass. Server command ids and client command-clock
records align phase windows through capture stalls instead of assuming CurTime matches
native test time.

Review modes: --tools-case review defaults to 160 active seconds (still <180), includes
the full features timeline plus held-trigger hand use, speed snap, pushed-stick releases,
forced drop paths, refusal feedback, death and T Stop. --tools-case drop_api is a separate
30-second native API diagnostic on a frozen recorded package; it is not a features pass.
Review client/server sources are appended in private fixture scope, staged and fingerprinted
with the base probes. No Index is implied; use --simulate until C is approved.
Private source bytes are frozen at invocation and used for staging plus post-run snapshots,
so a later local edit cannot be mislabelled as the code a queued game actually executed.

The fixed-heading CreateMove guard remains before/after VR and returns immediately while
running, leaving W/K commands intact. The generated shared probe saves m_yaw, temporarily
sets zero before Start, and restores it on every shared cleanup path. This prevents desktop
input from rotating the scripted play space before the private earliest mover attaches.
The private receipt also restores/compares its original string before Exit. This changes
no controller frames. The earlier text about removing the flat override means removing
its effect while VR runs, rather than removing the inactive heading guard.

T's fixture wrapper around tools/vr_session.py. Example: py -3 companion/tests/vr_tools_poc.py
--simulate --package out/dist/package.gma --evidence out/vr/v4t/next --seconds 60.
--tools-case native/features selects the measurement scenario; other options pass through.
--tools-case engine is a separate 30-second native-control diagnostic: level stationary
hand/head, native trigger pickup, then Use with mouse X/Y and turn/strafe-left command pulses.
It observes their actual axes without pretending to implement hand following; use its raw
records/captures, not the feature-acceptance checker. It runs only after W is merged.
--tools-case motion trials an owned server angular shadow controller using the held native
body, with no mass/gravity/collision changes, and native Use+forward/back distance commands.
It is a prototype measurement, not a product mode; the controller is removed on drop/cleanup.
Default active durations are 30/60 seconds respectively. Incomplete or >=180-second requests
are refused before locks, snapshots or other PoC work; every task session stays under three minutes.
Uses the actual packaged W/K/T code, native scripted poses/actions, shared lock/snapshot/
launch/capture/rollback driver. Removes only the shared test's flat CreateMove override so
production buttons reach the engine; adds a test-owned earliest mover to clear physical input.
Omits the shared wrist-HUD fixture's clip/reserve writes (and its restore) because the selected
weapon can be a physgun, tool or Hands. Capture names remain standard; no changed-ammo HUD
claim is made. Production inventory, selection and tool commands remain the measured paths.
Waits one second after final native Stop before the unchanged live-selector comparison.

Simulation takes only PoC lock; Index takes both. Locks wait up to two hours and are released
only by their owner. If the authorised field game is present, invokes the main checkout's
normal console-quit helper and records its result; never touches field files or SteamVR.
The complete client/server probes are staged as ordinary Lua in a fresh private PoC addon
inside the snapshotted addons root, after lock acquisition/transaction setup. No autorun,
native binary or policy exemption is added. Short admin/server and client includes execute
them, avoiding the known long-console-fragment overflow. The standard addon rollback removes
the whole private tree. Hashes/paths are recorded; JSON argument transport stays in out.
Needs the unattended driver's Pillow environment (py -3 on this machine). Inputs package,
fresh evidence folder and duration under three minutes. Outputs ordinary receipts plus
tools-records.json, source snapshots/provenance and tools captures. No production files or
settings edited. Exit follows the shared driver: 0 pass, 1 failure, 2 failed preflight.
Feature semantics are separately checked against the retained measurements, not inferred from
the renderer's success. No stand-in replaces NLVR.Weapon in a PoC run.
After Q's reviewed integration, keeps the standard driver's role/handle/source-extent capture
validation instead of M's earlier size-based compatibility checker. Uses Q's pending-transaction
and free-space safeguards unchanged; interrupted preparations need their matching rollback.
Raw head is (0,0,1.6) m; main hand starts (0.3,-0.25,1.2) m. Physgun axes use a level
head. Wheel/tool captures look down 35 degrees toward the hand, keeping the hand UI in the
nominal headset field instead of photographing it from a horizon-facing camera.
The fixed gm_construct camera is (0,0,512) game units at yaw zero, the open-air arena
verified by W, with room for all three physgun axes and push/pull without a nearby wall.

Q4 integration adds retained coverage and the shared one-second flat-render settlement after the second Stop. No field files or SteamVR settings are changed.

Independent review round: live hooks use the shared dispatcher and detached compatibility snapshots; geometry witnesses use raw posed-mesh/hand-bone data with rejecting placement/skew mutants. Full destructive acceptance stays gated pending Claude's fixes repair. See VR-V4-Q-resume.md for exact test/evidence scope.
