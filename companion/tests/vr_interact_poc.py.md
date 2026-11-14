# vr_interact_poc.py

Task P extension of tools/vr_session.py. Run with the same arguments, e.g.
`py -3 companion/tests/vr_interact_poc.py --package out/dist/PACKAGE.gma --evidence out/vr/v3p/RUN --seconds 116 --simulate`.
Requires the standard driver's Python/Pillow dependencies for unattended screenshots.

Generates a fourteen-phase, 112-second controller/action timeline. Appends the client probe
and transfers the server fixture via bounded admin console hex commands. Uses the shared
driver's exclusive PoC/VR locks (task P owner label, up to one hour waiting), snapshot, launch, runtime captures, compositor
checks, two Start/Exit cycles, variable restoration, depot/hash verification and cleanup.
Afterward parses NLVR_P lines into interaction.json beside the standard summary.json.
The game's argument vector is recorded in game-arguments.json and read by this wrapper's
--poc-arguments child mode before calling poc_session.main. This avoids Windows' 32767-character
process-command limit without changing the bounded console transfer or shared driver.
All scratch/evidence is below repo out. Exit is the shared driver's 0/1 (usage errors 2).
Never changes SteamVR settings, field install, loader source or package inputs. Once task N
is merged, pass --simulate for feature sessions; Index acceptance omits it.
If a field game is present when the owned PoC is about to launch, the user's expressly
authorised main-checkout out/vr/v2/quit_field_game.py normal-quit helper runs from main.
field-quit.log/json retain that action. No field file is directly written by this driver.
`--interact-phases 1,9 --seconds 30` selects a short grab/throw/gloves acceptance, with the
same production timeline and probe. Omit the phase selector for all fourteen phases.
Phase 13 is an isolated held-object impact: acquire first, then strike a fresh target. It
can be selected with the world ledge (`--interact-phases 13,6 --seconds 20`) so punch debris
cannot disturb the held-impact fixture. The report keeps per-phase witnesses explicit.

V8: phases 14 to 17 (`--interact-phases 14,15,16,17`; the default run stays 0 to 13). 14: the right hand holds a light
cube, turns the wrist a quarter turn in half a second and carries it. 15: both hands take one plank, raise it 0.2 m,
tilt it (the right hand rises 0.15 m) and turn both wrists 25 degrees about the line between them (a pitch of each
controller, which rolls the plank about its length; `interact-sim-01` rolled each controller about its own forward,
an axis across that line, which rightly rolls nothing). 16: hold, freeze with the trigger, let go, grip
again and free it with the trigger, carry it 0.25 m. 17: hold one bone of a ragdoll and freeze it. Timeline steps can
now press the right trigger and pitch either hand.

V8: `--fg-check` adds a Frame generation check after the phases (at `phases x 8 + 2` s of the timeline; give
`--seconds` room for 10 s more): the client part turns `nl_vr_frame_generation` off for 4 s and then back to the value
it had, and prints `v8-frame-generation` records (`on`, `off`, `restored`).

V8, phase 15 after the PoC's second run: the tilted plank is held level from 4.6 to 5.2 s and both wrists then turn
25 degrees from 5.2 to 5.8 s. Poses interpolate between steps, so the earlier timeline had no level moment: the turn
began where the tilt ended.
