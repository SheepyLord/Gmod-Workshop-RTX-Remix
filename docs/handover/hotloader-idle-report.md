# The Model Hotloader's frames without a character (report)

Claude, 2026-11-27, a side session of the main session, on the branch `hotloader-idle` (worktree
`out/worktrees/hlidle`), from `origin/main` at `c3698292`. Package only: the Model Hotloader's Lua; no loader
(`winmm.dll`), runtime or natives change. Decision: [ADR 0273](../decisions/0273-the-hotloaders-frames-cost-nothing-without-a-character.md).
Facts: [RESEARCH.md](../RESEARCH.md), "The Model Hotloader's frame with no character". Merged to `main` by the main
session on the user's "Merge and publish" (2026-11-27); the State section at the end says what was published.

## The task

Codex found, and the user relayed in one line: "with zero imported characters present, the Model Hotloader's
pre-render callback still used 0.46 ms per frame". Make the Hotloader's per-frame work cost nothing measurable when no
imported character exists, proportional to the characters present otherwise, without changing anything a character
does. Codex's own measurement (map, method) was not given, so it was measured again first.

## What a frame cost with no character

The pre-render callback is `PreRender` `MMDHL.Shadows` (`mmd_hotloader/lua/mmdhl/client.lua`). With no character it:

- rebuilt the entity list (`UpdateClientInstances` calls `mmdhl.InvalidateEntityList()` then `mmdhl.Entities()`),
  checking every candidate (every prop, ragdoll, NPC and player of the map) for the networked asset that makes it a
  character; the frame's other ten or so calls reuse that list;
- searched the whole map for legacy `mmdhl_ragdoll` entities (`ents.FindByClass`), as `Think` `MMDHL.RenderMode` and
  the translucent pass's `MMDHL.Models` also did, three searches a frame;
- had the natives prepare a frame and sweep their render caches, each a call queued for Source's render thread.

Measured in the PoC (below), the list was nearly all of it: 234 of the callback's 264 µs on gm_construct with 600
more props, where the callback took 0.26 to 0.29 ms; on gm_construct as it is, 0.035 ms. The cost follows the map's
entities (0.354 ms with 590 client entities in a later launch), so Codex's 0.46 ms fits a busier map than these; its
map was not given. The server's tick added `MMDHL.NativePose`'s search of every entity for
ragdolls with a server-side world (`MMDHLInstance`), which no code of the add-on makes any more: 0.011 to 0.041 ms a
tick.

## The fix

- `carrier.lua` (client): the entity list keeps which candidates carry a model. Those are checked at every list as
  before; any other candidate only when something may have given it one: its creation (checked at every list for two
  seconds), its return into view (`NotifyShouldTransmit`), its networked asset arriving (`EntityNetworkedVarChanged`
  for `MMDHLAsset`, half a second, since the hook runs before the value changes and a value read for the frame is kept
  for it), the add-on noting it (`mmdhl.NoteCarrier`). The other candidates are checked in turn, at least one a frame
  and each within about ten seconds at sixty frames a second, as a safety net for a change no hook announced. The full
  scan every five seconds, the list's order and the client ragdoll and copy registries are as before; the server's
  list is unchanged. `mmdhl.HasLegacyRagdolls()` says whether a legacy entity exists (noted at creation and by the
  full scan).
- `client.lua`: the three legacy searches run only while a legacy entity exists; the render boundary returns after
  `UpdateClientInstances` when `mmdhl.NativeIdle()` says nothing needs the natives.
- `native_render.lua`: `mmdhl.NativeIdle()`: no model listed, no client instance (`instances.lua`
  `mmdhl.HasClientInstances()`), no editor or library preview, no legacy entity, no reader of the frame profile, for
  two seconds (so that the cache sweep releases what the last character used). The update-rate LOD's frame-time
  average keeps running in the idle frames.
- `carrier.lua` (server): `MMDHL.NativePose` searches only once a ragdoll has a server-side world (the change hook on
  the server, or one search every five seconds); from then on as before.
- The package index (`packages/model-hotloader/files.json`) re-imported for the five files; the part's README lists
  the change.

## Measurements

One launch per row group, the shipped files then the branch's, A B A B (old, new, old, new), each phase 15 seconds,
compiled under their shipped chunk names so that the render guard treats both alike; with three characters spawned
after the idle phases (the add-on's bundled character, three ragdolls). PoC, RTX on, 1600x900, the published package
`0.0.0-dev.20261127124158+e90984c6` (main `7817bcab`, the same Hotloader as this branch's base). Hook times are ms a
frame; evidence in `out/hlidle/evidence/construct-1` and `construct-props600` of the worktree.

| gm_construct | median frame | `MMDHL.Shadows` | all Hotloader hooks | all hooks |
|---|---|---|---|---|
| as it is (212 client entities), old | 5.49, 5.46 | 0.035, 0.035 | 0.085, 0.092 | 1.72, 1.73 |
| as it is, new | 5.65, 5.49 | 0.015, 0.014 | 0.048, 0.046 | 1.75, 1.74 |
| 600 more props (452 client entities), old | 6.23, 6.41 | 0.264, 0.292 | 0.330, 0.365 | 2.02, 2.14 |
| 600 more props, new | 6.43, 6.02 | 0.019, 0.018 | 0.059, 0.053 | 1.80, 1.76 |
| 600 more props, three characters, old | 11.04, 11.40 | 1.749, 1.788 | 1.887, 1.927 | 4.06, 4.09 |
| 600 more props, three characters, new | 11.01, 11.10 | 1.421, 1.424 | 1.510, 1.510 | 3.70, 3.73 |
| as it is, three characters, old | 12.88, 12.61 | 1.450, 1.440 | 1.575, 1.570 | 3.86, 3.86 |
| as it is, three characters, new | 12.67, 12.92 | 1.413, 1.455 | 1.499, 1.545 | 3.78, 3.88 |

A third launch deployed this branch's build (`0.0.0-dev.20261127190250+c0c6db9f`) instead, 600 props again (590
client entities this time); its first phase ran the deployed files as they are, then the same B A B and the three
characters (`out/hlidle/evidence/deployed-new-props600`):

| gm_construct, 600 more props | median frame | `MMDHL.Shadows` | all Hotloader hooks | all hooks |
|---|---|---|---|---|
| the branch's package, deployed | 6.16 | 0.018 | 0.059 | 1.71 |
| new files over it | 6.25, 6.05 | 0.017, 0.019 | 0.056, 0.060 | 1.72, 1.72 |
| old files over it | 6.20 | 0.354 | 0.428 | 2.06 |
| three characters, new | 12.79, 12.81 | 1.493, 1.488 | 1.580, 1.581 | 3.81, 3.79 |
| three characters, old | 13.02, 13.03 | 1.998, 1.993 | 2.169, 2.160 | 4.37, 4.33 |

Its server ran the branch's `carrier.lua` throughout: `MMDHL.NativePose` 0.0016 to 0.0022 ms a tick (0.041 before),
the server's Hotloader hooks 0.016 to 0.019 ms a tick with no character (0.054 to 0.059 before).

- With no character, what remains is about a microsecond a hook for the Hotloader's 40-odd per-frame hooks (the
  probe's timer included) and 14 to 19 µs in the pre-render callback (the list's turn, the idle check), the same on
  both maps: nothing measurable in a frame. Per hook on gm_construct: `MMDHL.Models` 15.7 to 1.1 µs and
  `MMDHL.RenderMode` 13.4 to 2.2 µs (their searches).
- With three characters on the busy map, the render boundary's `UpdateClientInstances` took 349 and 357 µs before and
  49 µs after; their presentation (443 to 454 µs) and bounds (62 to 64 µs) were the same.
- Frame medians move by up to 0.4 ms between phases of one launch (6.02 to 6.43 for the same code), more than what is
  saved, so the hook timers carry the comparison.
- The harness (below) counts per frame on a map of 661 candidates: before, 661 asset reads, three map searches and
  both native calls with no character, 664 reads with three; after, 2 reads and nothing else, 5 with three.

## With characters: what was looked at and left

With characters present the change also removes the map-wide work (the full list pass, the three searches, their
result tables, a sort closure a list). What remains per frame is the characters' own: for each, its pose (the bone
palette read through `SetupBones`/`GetBoneMatrix`, about 0.15 ms each here), its morph weights read per morph, the
update-rate LOD, its bounds and draws; at 0.45 ms for three and proportional to them, left as it is: the update-rate
LOD already slows unseen ones to 10 Hz, and changing when an expression or a pose is read would change what a
character does. Small per-frame allocations remain (the list's table at each build, one `Vector` in
`MMDHL.MainCamera`), measured at about a microsecond.

## Characters still behave

The same probe with each package deployed for real (the published one, then this branch's build,
`0.0.0-dev.20261127190250+c0c6db9f`, the same hour): gm_construct, a map change to gm_flatgrass, then from the library
(the add-on's bundled character) a ragdoll, an NPC, `gmod_cleanup`, a ragdoll again and the player's own model, each
spawned where the player aims, with a screenshot of each. Evidence: `out/hlidle/evidence/behaviour-old` and
`behaviour-new`.

| | published | branch |
|---|---|---|
| No character, 15 s after the map: the natives' frame steps a second | 225 | 0 (idle) |
| Ragdoll: frames from the server's ready to listed with its world | 138 (its first asset load) | 152 |
| NPC; ragdoll again; the player's model (an entity already there) | 0; 0; 0 | 0; 0; 0 |
| Each: bodies and joints of its hair and clothing, backend | 599, 809, `cpu_mt_v2` | the same |
| Each in view: presentation one frame behind, drawn this frame | yes | yes |
| Two characters: frame steps a second | 163 | 166 |
| Four seconds after the clean up | 269 | 0 (idle) |
| The player's model | 272 | 269 |

The screenshots match: the ragdoll fallen and at rest beside the standing NPC with its weapon, eyes, hair and clothing
as before; the player's model in third person with its hair down its back and its shadow. The natives went idle after
the clean up and the next ragdoll was listed in the frame the server said it was ready. The player's model is the case
the networked asset's change hook serves (an entity that was there before gets a model): listed at once. No error, no
render error, both games quit normally.

## Tests

- [`test_hotloader_idle_frames.py`](../../tools/tests/test_hotloader_idle_frames.py.md) (new, 14 tests): loads the
  shipped `client.lua`, `carrier.lua` and `native_render.lua` under LuaJIT and runs frames; the server realm's tick
  too. Its `idle` and `server_pose` scenarios fail on the files before the change.
- All 61 Model Hotloader harness tests pass. The gate, `tools\test.ps1 -Config Release` from the worktree (with
  `NL_FIXES_CLONE` set for the CI tree replay): all checks passed in 427 s, 35 of 35 CTests, 2,283 Python tests of
  `tools` (one skipped), 29 of `tools\gmapack` and 26 of `tools\steam` (one skipped each).

## Not covered

- Codex's own map and measurement were not given; the 0.46 ms was reproduced in kind (0.26 to 0.29 ms with 452 client
  entities), not at that figure.
- The field install (the task said PoC only), multiplayer (another server's catalog, a remote scene), the legacy
  backend (`mmdhl_native_carrier 0`), whose entities still take the old searches.
- A model given to an entity in view with no hook announcing it is found within one turn (about ten seconds on a map
  of 600 candidates) instead of the next frame; no case of that was found in the game.
- The package used for the behaviour check was built before a comment-only edit of `carrier.lua`.

## Files

`packages/model-hotloader/mmd_hotloader/lua/mmdhl/carrier.lua`, `client.lua`, `native_render.lua` (and its `.md`),
`instances.lua`, `packages/model-hotloader/files.json`, `packages/model-hotloader/README.md`,
`tools/tests/hotloader_idle_frames_harness.lua` and `test_hotloader_idle_frames.py` (new, with their `.md`),
`docs/decisions/0273-...` and the index, `docs/RESEARCH.md`, `docs/TESTING.md`, `CHANGELOG.md`, this report and the
handover index.

## State

- Merged to `main` on the user's "Merge and publish" (2026-11-27) as one commit with the branch's tree, ADR 0273
  accepted, `AGENTS.md` and `docs/ROADMAP.md` brought up to date; the Release gate passed on it in the main session's
  worktree before the push (35 of 35 CTests, 2,283 Python tests of `tools`, one skipped).
- Pushed as `a55817a8` and uploaded to the Workshop item as **0.0.0-dev.20261127202857+80dac6f3**, its change note the
  changelog's entry.
