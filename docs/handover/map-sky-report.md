# Which sky a map shows: report

By Claude, 2026-11-20, on the branch `map-sky` (worktree `out/worktrees/msky`); package only (the companion). Decision: [ADR 0249](../decisions/0249-which-sky-a-map-shows.md). Facts and measurements:
[RESEARCH.md](../RESEARCH.md), "A map's own sky under RTX". For modders: [docs/MAP_SKY.md](../MAP_SKY.md).

## What the user asked

"Improve the compatibility of the RTX addon to the game's own skybox. We should replace other map's skybox to our own
RTX skybox by default, but we also allow user to switch back to the map (3D) skybox if applicable. Display a chat
message about this when map join. Make sure the confusion on gm_stelliferous RTX can be resolved and avoided in the
future and allow more modding and enhancement (like custom skybox for different map that comes above the stock RTX sky
we have)" (2026-11-20, run in its own session).

Three answers of theirs, asked during the work:

| Question | Their answer |
|---|---|
| A map whose RTX version ships its own sky: which sky by default? | The pack's own sky (it comes above the RTX sky) |
| Switching back to a map's own sky: remembered per map, or one switch? | Per map |
| On a map showing a fixed sky (space, a pack's skybox, the map's own), does a time or weather change still swap in the RTX sky until the next map (ADR 0248)? | Yes, keep ADR 0248 |

## The confusion on gm_stelliferous RTX

Searched: the repository's issues (`gh issue list --state all --search stelliferous`, `--search sky`: none), the
Workshop item 3829070317's comments (two pages) and discussions (three), the repository's docs and the remaster's
records. No player names the map. The confusion is the one ADR 0248 records: the remaster shows the map's own orbit
skybox, and with "Follow the map's sun" unticked (the user's own setting) the companion's physical sky replaced it from
the map's start, so the station hung under a pale blue daytime sky. Which sky showed depended on a setting that does not
mention the map's sky, and nothing told the player which sky they saw or how to get the other. ADR 0248 fixed that map
with a hook. Two Workshop comments asked where to stop the day cycle, the same lack of a pointer.

Now: the remaster's sky shows by default, the chat line names it ("This map shows the sky of gm_stelliferous RTX. For
the RTX sky: type nativeloader_sky_here rtx..."), This map in Sky and weather switches it for that map, and any map's RTX
version can declare its sky the same way (a sky file, no code), so the same confusion cannot arise on another map.

## What was there

- The RTX sky (`rtx.skyMode 1`) drops every draw of the sky camera; `nativeloader_sky 0` ("The map's skybox") gave the
  2D sky textures back on every map at once, never the 3D skybox.
- The session turns the 3D skybox pass off (`r_3dsky 0`: the fixes' session variables, and their per-map config a
  second after each map starts), and the companion's guard keeps it off against other Lua.
- The probes found how to bring it back (RESEARCH): `rtx.skyMode 0` with `r_3dsky 1` gives gm_construct's city and
  gm_flatgrass's grass and hills, path traced at full size; under the session's whole-map drawing the sky pass also drew
  the map itself, magnified 16 times (a dark shape over gm_flatgrass); visibility by the PAS keeps the pass to the skybox
  room and also removes the skybox room's miniature that shows overhead on gm_construct.

## What was built

- **[`map_sky.lua`](../../companion/nativeloader/lua/nativeloader/map_sky.lua.md)** (new, pure Lua): a map's sky facts
  from its BSP (the `sky_camera` and its scale, the texinfos' sky flags, an LZMA lump's stream), sky files checked,
  which sky shows (`resolve`), the This map list, the chat line's sentences.
- **[`nativeloader_sky.lua`](../../companion/nativeloader/lua/autorun/nativeloader_sky.lua.md)**:
  - reads the map, the sky files (`data_static/nativeloader/sky/<map>/*.json`) and the player's choice at the map's
    start, before anything is sent; `nativeloader_sky_here` and `data/nativeloader_companion/sky_maps.txt`;
  - the map's own sky: `rtx.skyMode 0`, the map's sun back, the weather released; its 3D skybox at scale 16 with
    `r_3dsky 1` (the fixes' question held back by `rtx_show_3dsky_warning 0` around that one command) and the PAS
    switches, their old values recorded in `nativeloader_sky_engine_saved` and put back when the sky goes, at
    `ShutDown`, and checked at the next map's start; again 1.5 s after the start (the fixes' per-map reset);
  - a sky file's `skybox` through `sv_skyname`, single-player only, the map's own name put back;
  - the user's answers: a map's RTX version's sky first; a sky or weather change shows the RTX sky until the next map
    for every sky that is not the RTX sky; a new choice shows at once, except a return to an add-on's sky, which waits
    for the next map's start;
  - the chat line 6 s after `InitPostEntity`, once per map, translated; `nativeloader_sky_message`;
  - `NATIVELOADER_SKY.mapSky()`, `line()`; `takenOver()` also true for the player's choice, and it calls no owner hook
    (gm_stelliferous RTX asks it from its own answer to that hook; an add-on that falls silent once replaced is
    remembered for the map's session);
  - the panel: what the map shows, This map, Other maps (the old Sky choice's convar), Say which sky shows, a note
    that time, weather and the night sky are the RTX sky's; `nativeloader_sky_status` two more lines.
- **[`_nativeloader_guard.lua`](../../companion/nativeloader/lua/autorun/_nativeloader_guard.lua.md)**: its exact list
  of the package's own Lua paths gains `lua/nativeloader/map_sky.lua` (`test_render_guard_addons` holds it to the
  companion's files).
- **Translations**: 37 new texts in the six catalogs (agent-written, as earlier rounds; not reviewed by a native
  speaker); the texts no longer used (the old Sky choice and its legend entry, Reset's) dropped.
- **The guide**: the Sky and weather picture captured again (1920x1080, the tool half 800 wide so the panel fits) and
  drawn with 11 callouts; its legend and a new paragraph on which sky shows. Reset is below the picture's fold now and
  left out of its legend.
- **Docs**: ADR 0249 (supersedes ADR 0031 in part; the index gains its row, ADR 0031's status says so),
  [docs/MAP_SKY.md](../MAP_SKY.md) for modders, the two Lua docs, the companion README, COMPONENTS, ROADMAP, RESEARCH,
  TESTING, CHANGELOG, the `remix-map-pbr` skill (a sky file instead of Lua for a sky that is a picture).
- No loader, runtime or fixes change.

## Evidence

- **LuaJIT**: `test_companion_sky.py` 33 tests (10 new for ADR 0249, the existing ones unchanged but the panel
  recorder and a station add-on that, like gm_stelliferous RTX, names itself only while its sky shows); the companion's
  suites by discovery: 996 tests, OK. `companion_i18n.py check`: complete.
- **PoC** (evidence in `out/map-sky/` of the worktree; the package of 2026-11-18 with the branch's two Lua files over
  the deployed ones by a temporary add-on, removed afterwards):
  - P1-P3 probes: the facts above (`p1/`, `p2/`, `p3/`).
  - `p4/s1-construct`: the RTX sky and the chat line at the start (`shot-01-chat_start.png`); This map > map: the city
    of the 3D skybox (`shot-14-map_high_y0.png`), `r_3dsky 1`, the PAS, the old values recorded.
  - `p4/s2-construct-saved`: the saved choice from the map's first frame and its chat line ("...as you chose for it");
    `auto` puts every engine value back.
  - `p4/s1b-construct-weather`: `overcast` on the map's own sky shows the RTX sky until the next map ("taken"), the
    engine put back, the choice kept; `rtx` then `map` shows the map's sky again.
  - `p4/s3-flatgrass-file`: a test add-on's sky file (`Flatgrass Day (test)`, `sky_day01_01`) above the RTX sky from the
    start, with the 3D hills; `rtx`; the map's own (the baked painted sky and the hills); `auto`.
  - `p4/s4-moon-2d`: gm_moon_surface (Workshop 2984537655): the RTX sky puts a sunset over the Moon; the map's own sky
    is its black starry sky with the Earth rising (`shot-09-map_eye_y0.png`); no 3D skybox, no engine change.
  - `p4/s5-stelliferous`, `p4/s5b-stelliferous`: the remaster's orbit sky and API sun at the start, the chat line
    naming it; `rtx` (the add-on yields); `auto` ("...until the next map starts, when the sky of gm_stelliferous RTX
    returns", after the fix that remembers a silent add-on).
  - `guide/tab`: the panel for the guide's picture.
  - Every session ended with a normal quit, settings put back (`session.json`).
- **The gate**: `tools\test.ps1 -Config Release` in the worktree, "All checks passed." (conventions; C++ 35 of 35;
  Python 29, 26 and 2170 tests). The first run had caught the render guard's exact path list missing the new module.

## Limits and follow-ups

- **3D skyboxes at another scale than 16** (gm_stelliferous 64, gm_construct_renovation 32, 3 of the 24 maps with a
  3D skybox in the user's Workshop folder) show their 2D sky alone: `rtx.skyReprojectScale` is not on RemixConfig's
  allowlist. Allowing it (a native change of the fixes' `remix_option_policy.h`) would let the companion set the map's
  scale.
- **The skybox room's miniature under the RTX sky**: the whole-map drawing still shows it where it is in view
  (gm_construct, a speck overhead). Hiding it by default needs a way to leave that room out of the whole-map drawing (a
  fixes or runtime change), or the PAS, which the default does not use.
- **The PAS while a 3D skybox shows**: parts of the map outside the PAS are not in reflections or bounce light then.
- **Not tested in the game**: the six languages (the catalogs and the harness are), a multiplayer game skipping a
  `skybox` sky file, a map whose entity lump is compressed (`util.Decompress`), VR.
- **gm_stelliferous RTX** (the fork's branch) yields its API sun when replaced and sets its sky again only at the next
  map's start; an add-on that wants to come back at once could watch `takenOver()` turn false.

## For the main thread

- Branch `map-sky`, worktree `out/worktrees/msky`, from `main` at `28b7aa7f`; nothing committed, pushed or published.
- New: `companion/nativeloader/lua/nativeloader/map_sky.lua` (and `.md`), `docs/MAP_SKY.md`,
  `docs/decisions/0249-which-sky-a-map-shows.md`, this report. Changed: `nativeloader_sky.lua` (and `.md`),
  `_nativeloader_guard.lua` (one path), `guide_pages.lua`, the guide's `sky_weather.jpg`, `tools/guide_pictures.json`,
  the seven catalogs in `companion/i18n` (not `addons/`), `companion/README.md`, `tools/tests/test_companion_sky.py`
  (and `.md`), `tools/tests/companion_ui_i18n_harness.lua` (one lookup), ADR 0031's status line, the decisions and
  handover indexes (one row each), CHANGELOG, ROADMAP, COMPONENTS, RESEARCH, TESTING, the `remix-map-pbr` and
  `workshop-content-pack` skills.
- Left to the merge: AGENTS.md's status line and its list of reports.
- The PoC: the temporary add-ons `zz_nlsky_dev` and `zz_nlsky_skyfile_test` removed, `data/nativeloader_companion/sky_maps.txt`
  removed; the loader's package and config untouched.

## Published

- Reviewed by the main thread (the code, the PoC evidence in `out/map-sky/` of the worktree, the docs), then a
  fresh `tools\test.ps1 -Config Release` on the branch: "All checks passed." (conventions; C++ 35 of 35; Python 29,
  26 and 2170 tests).
- Added at the merge: AGENTS.md's status line and its list of reports; ROADMAP's line now says `main`; in the
  changelog entry "(your choice)" became "(the user's choice)", since the entry is the Workshop change note players
  read.
- Committed on `map-sky` as `51914bdc` and merged into `main` by fast-forward from `28b7aa7f`. The merge's hook
  uploaded item 3829070317 as `0.0.0-dev.20261121012404+c409f3e0` (content digest `0841011e...`), with one change note:
  this entry. A player's game deploys it at its next start (Steam may first only download it).
