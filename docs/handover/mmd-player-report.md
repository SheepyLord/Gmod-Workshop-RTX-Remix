# The Advanced MMD Animation Player: the hitch on each click, and three options (2026-11-15)

The user's report and requests of 2026-11-14:

> The experience of using the bundled Advanced MMD Animation Player is very laggy, and the selection, assignment,
> action like assigning an animation to an NPC always result in a few seconds of hangs. Please optimize the addon to
> make a smooth experience.
>
> 1. Add an option to disable the reset of all flex to zero at the beginning of the animation play. Uninvolved
>    flexes should not be set to zero.
> 2. Improve the debug panel to add a long slider to allow dragging along the progress for easier perview.
> 3. The replay on NPC, the collsion of the NPC now is only based on the bound box. Instead, add an option, by
>    default, use the NPC's ragdoll collision, (the main 18 bodies only) to calculate collision to the world and
>    other Source engine models. The NPC's motion (and the MMD collision, if available) should not be affected.

Done by Claude on the branch `mmd-player-perf` (worktree `out\worktrees\mmd`, from `origin/main` at `6cf6e92a`).
Package only: the character motion importer part (`packages/character-motion-importer`, "Advanced MMD Animation
Player" is its tool's name, `sh_core.lua` `tool.mmd_vmd_npc.name`) and one hook in the Model Hotloader part
(`secondary_collision.lua`); no loader (`winmm.dll`), runtime or native change. Decision:
[ADR 0224](../decisions/0224-the-animation-player-answers-a-click-with-its-built-flags.md); facts with file and line
references: [RESEARCH.md](../RESEARCH.md) "The Advanced MMD Animation Player's clicks".

## Why a click hung

Measured first, before any change, in the PoC with a copy of the field's motion library (149 imported motions, one
bundled, 106 more from the user's Workshop subscriptions: 255) and two imported characters spawned as NPCs, by
[mmd_player_session.py](../../tools/qa/mmd_player_session.py.md), which clicks through the tool as a player does and
times every frame and the add-on's functions in both realms.

- Every selection (R, a click on an NPC), assignment, finished build and cleared selection made the client ask the
  server for the **details of every motion**. The server walked them all, testing each motion's file in two places and
  reading its time and size twice (about 2,000 file calls for 255 motions, all in one tick), tested a built file per
  motion, and streamed all 255 entries back. The client then **rebuilt the tool's motion list** (3,570 panels) and the
  Motion Manager. A click sends two such requests and the server deferred the second by half a second, so every click
  stalled the game twice.
- In the field, GUI Scaler walks the whole spawn menu again whenever the number of panels grows, which each of those
  rebuilds did, and the game draws at 4K with RTX: the same work costs more there.

The add-on's own time per click (server and client) was 85-360 ms; after the change it is 1-3 ms.

### Before and after (the longest frame of each action's window, and how many frames passed 100 ms)

1600x900, the Workshop mounted (`before-ws2`, `after3-ws`):

| Step | Before | After |
|---|---|---|
| `select_self_reload` (R) | 113 ms (1) | 32 ms (0) |
| `assign_npc1` | 185 ms (2) | 29 ms (0) |
| `assign_npc2` | 113 ms (2) | 31 ms (0) |
| `unassign_npc2` | 112 ms (2) | 34 ms (0) |
| `assign_npc2_again` | 130 ms (2) | 33 ms (0) |
| `clear_selection` | 159 ms (1) | 28 ms (0) |
| `select_motion_A`, `_B` (a row of the tool's list) | 98, 39 ms | 47, 55 ms |

3840x2160, the Workshop mounted, the Motion importer tab built (`before-4k`, `after2-4k`):

| Step | Before | After |
|---|---|---|
| `select_self_reload` | 388 ms (1) | 49 ms (0) |
| `assign_npc1` | 167 ms (3) | 104 ms (3) |
| `assign_npc2` | 195 ms (4) | 88 ms (0) |
| `unassign_npc2` | 196 ms (4) | 84 ms (0) |
| `assign_npc2_again` | 224 ms (6) | 117 ms (2) |
| `clear_selection` | 278 ms (4) | 100 ms (0) |
| `idle_two_assigned` (nothing clicked) | 139 ms (5) | 108 ms (1) |

At 4K the frames left near 100 ms are not the add-on's: they come as often with nothing clicked (the idle window),
and its own functions no longer appear among the costs in those windows (the Dynamic Toolgun Screen's HUD, the
companion's per-frame hooks, GUI Scaler's panel count and path tracing at 4K do). Opening the spawn menu and the
tool's panel the first time still builds the panel (about 110-180 ms once).

## What changed

- **A click asks for the built flags alone**: which motions are built for the selected character, from one listing of
  the built folder (`mmdvmd_built_flags_request` / `mmdvmd_built_flags`). The details are asked for only when a window
  opens, Refresh is pressed or the motion list changes; the walk itself now reads each motion's time and size once.
- **The lists keep their rows**: the tool's motion list is rebuilt only when what it shows changes; the Motion Manager
  updates its Built cells in place.
- The motion list is printed to the console only for `mmdvmd_list` and the Refresh button.

## The three options

| Setting | Default | Where | What |
|---|---|---|---|
| `mmd_vmd_npc_keep_flexes` | 0 | Build & Playback tab, "Keep expressions the motion does not animate" | On: a selection leaves the face, a dance sets only the flexes its motion drives and gives them back their earlier weights at its stop, the debug window puts back what it previewed. Off: every flex starts at 0, as before |
| `mmd_vmd_npc_ragdoll_collision` | 1 | Build & Playback tab, "Dancing NPCs collide with their ragdoll's body" | While an NPC dances, colliders shaped as its ragdoll's main bodies (an imported character's 18) follow its bones; players, NPCs and props collide with them instead of the box |
| (none) | | The debug window | A timeline slider across the window above its buttons, from the first frame to the last |

How ragdoll collision works: the shapes come once per model from a ragdoll that exists for an instant (each body's
convex meshes, in its bone's space); each collider is a server-only entity whose physics object is a shadow moved to
its bone every tick, so nothing it touches moves the dance. The NPC's box keeps answering traces (the tool gun,
bullets) but leaves physical contact (debris collision group, its hull's collisions off) until the dance stops. The
Model Hotloader's hair and clothing physics leaves the colliders out (`MMDHLSceneExcluded`). Engine bone followers
were tried first: `CreateBoneFollowers` makes none for a character model (it needs the model's `bone_followers` key
values). A model without a ragdoll keeps its box; a model with more than 18 bodies keeps those on ValveBiped trunk
and limb bones.

### Checked in the game (`after4-features`, `after3-ws`)

With a four-second test dance built for the imported character (both arms held out from frame 20 to 100, the eyes
closed from 30 to 90):

- **Ragdoll collision on**: 18 colliders, each within 0.23 units of its bone; traces through the held-out hands hit
  the hands' colliders (off: nothing, the hands are outside the box); a player-sized hull into the head hits the
  head's collider (off: the box); one into the box's empty corner passes (off: blocked by the box); a gravity-less pop
  can put at the hand was pushed 78 units in 0.6 s (off: 0.04); the Model Hotloader's scene capture excluded the 18
  bodies; after the stop no collider is left and the box collides again. The pose at the same frame was identical with
  the option on and off (largest bone difference 0).
- **Keep expressions on**: 笑い (not driven) set to 0.6 stayed 0.6 through two selections, the start, the dance and the
  stop, while まばたき (driven) went 0, 1, 0. **Off**: 笑い was zeroed by the selection and at the start, as before.
- **The timeline**: frames 0-120; one position (60) sent one request and the NPC took frame 60; a held sweep of 51
  positions in about 2 s sent 26 requests and ended on frame 110; the bone and flex lists waited while the knob was
  held and caught up when it was let go.

## Files

- `packages/character-motion-importer/mmd_vmd_npc/lua/mmd_vmd_npc/sv_commands.lua` (the built flags, the walk, the
  `MMDVMDNPC.Actor` table: flexes, colliders), `sv_cache.lua` (`CachedMotionMetadata`, `MotionRealms`),
  `sh_core.lua` (`BuiltTail`, `BuiltMotionIDs`, `GetModelFlexWeight`, `ActorForTraceEntity`, the six phrases in nine
  languages), `cl_menu.lua` (the requests, the flags, the Motion Manager's cells, the timeline),
  `lua/weapons/gmod_tool/stools/mmd_vmd_npc.lua` (the list's fingerprint, the two settings and switches, clicks on a
  collider), `lua/autorun/mmd_vmd_npc.lua` (two network strings); the part's `files.json`.
- `packages/model-hotloader/mmd_hotloader/lua/mmdhl/secondary_collision.lua`, the part's `files.json` and README.
- Tests: [motion_server_harness.lua](../../tools/tests/motion_server_harness.lua.md) and
  [test_motion_server.py](../../tools/tests/test_motion_server.py.md) (four scenarios),
  [motion_tab_harness.lua](../../tools/tests/motion_tab_harness.lua.md) and
  [test_motion_tab.py](../../tools/tests/test_motion_tab.py.md) (three); each fails on the code before.
- QA: [mmd_player_session.py](../../tools/qa/mmd_player_session.py.md),
  [mmd_player_probe.lua](../../tools/qa/mmd_player_probe.lua.md),
  [mmd_player_server.lua](../../tools/qa/mmd_player_server.lua.md).
- Docs: ADR 0224 and its row, CHANGELOG, ROADMAP, RESEARCH, TESTING, this report and its line in the handover index.

## Published

`tools\test.ps1 -Config Release` passed on the branch (35 native tests; 1,996, 29 and 26 Python tests; "All checks
passed"). `origin/main` had not moved from `6cf6e92a`, so `main` was pushed to `d651d7e7` with nothing to rebase. The
push's hook uploaded item 3829070317 as **0.0.0-dev.20261115072909+2bbbece3** (2,148,169,590 bytes, SHA-256
`0898a47764fca1d68bbc141d851af622129742330dde220a0ff906a507979fec`, content digest `0976b401...`; Steam sent 6.0 MB of
changed content) at 2026-11-15 07:29 UTC, with one change note of 2,983 characters: this round's entry and the issue
forms' entry, the changelog since the last upload (ADR 0222).

## Notes and open questions

1. The colliders are never sent to clients, so a player walking into a dancing NPC is corrected by the server rather
   than predicted: a small stutter at the contact is possible in multiplayer; in single player it was not visible in
   the checks above.
2. The translations of the six new phrases (eight languages) are Claude's and await a person's review.
3. Seen in passing, not this add-on's (possible follow-ups): at 4K the Dynamic Toolgun Screen's HUD costs 1-1.5 ms a
   frame while the tool gun is out, and the companion's model-layers hook 0.6-0.9 ms a frame.
4. Not checked in the field install itself (rule 1: the PoC with a copy of the field's motions and its Workshop
   subscriptions stood in for it).
