# Lights: the RTX flashlight's automatic brightness and the dance light's uniform lighting (2026-11-14)

The user's two requests:

- "The RTX Remix light of the dance animation player needs modification and enhancement, allow more customization and
  allow an uniformed lighting option where light level scale with the distance to character."
- "Enhance the RTX flashlight allow better / automatic adjustment of the brightness (enabled by default) to prevent
  overbright and overdim. (This is connected to [the dance light item])."

Done by Claude on the branch `qol-lights` (worktree `out\worktrees\q-light`, from `main` at `bfbe2350`). Package only:
the RTX fixes' flashlight Lua (`packages/fixes`) and the character motion importer's dance light
(`packages/character-motion-importer`), with the companion's render-guard path list and the add-on catalogs; no
loader (`winmm.dll`), runtime or native module change. Decisions: [ADR 0208](../decisions/0208-the-rtx-flashlights-automatic-brightness.md)
(the flashlight) and [ADR 0209](../decisions/0209-the-dance-lights-uniform-lighting-and-options.md) (the dance light);
the facts with file and line references are in [RESEARCH.md](../RESEARCH.md) ("The RTX flashlight and the dance
light: what sets their brightness").

**State:** committed on `qol-lights`, not merged, not pushed, nothing published. Tested offline only; the in-game checks
below are the user's call. A merge into `main` changes the package's inputs, so its hook publishes the Workshop item
(AGENTS.md rule 5).

## Why the lights were too bright and too dim

Both lights are Remix sphere lights of a fixed radiance, and a sphere light lights a surface d away with
pi x radiance x (radius / d)^2. The flashlight sits 20 units behind the eyes in the classic settings (Brightness 5,
a hemisphere cone): a wall 30 units ahead gets about seventy times the light of one at 250, the end of a corridor at
1000 units a sixteenth. The dance light sits 45 units behind the camera; a camera path swings from a face close-up to
a wide shot, so the dancer goes from blown out to dark within one song.

## The RTX flashlight: automatic brightness, on by default (ADR 0208)

- Each frame seven traces across the beam (its axis and six around it at half the cone, at most 20 degrees) find where
  it lands; they start at the eyes and are measured from the light. Glass, grates and water let them through; the
  player, their vehicle and the car a seat belongs to are left out; a trace that starts in a solid is ignored.
- One distance from them, near hits counting most (the inverse-square mean, the axis twice); the light's gain is
  (distance / normal distance)^(2 x strength), between 1/64 and Max Boost, eased in log space: down with a 0.08 s time
  constant, up with 0.6 s. It comes on at its measured gain. Another player's light is measured ten times a second.
- The haze is not boosted (the volumetric scale is divided by a gain above 1).
- Brightness keeps its meaning: the level at the normal distance.

| Setting | Default | Menu (Lights > Flashlight, Automatic Brightness) |
|---|---|---|
| `rtx_flashlight_auto` | 1 | Adjust brightness to distance, with a help line |
| `rtx_flashlight_auto_strength` | 0.8 | Strength, 0-1 |
| `rtx_flashlight_auto_distance` | 256 units | Normal Distance, 32-2048 |
| `rtx_flashlight_auto_max` | 8 | Max Boost, 1-16 |

Reset restores them. `rtx_flashlight_auto 0` is the light as before, with no traces. `rtx_flashlight_debug 1` prints
the beam's distance and gain once a second and marks where the beam lands (a cyan sphere).

**VR, checked:** VR does not drive the flashlight from a hand. The main hand's stick click is mapped to a `flashlight`
action in `vr/addon/lua/nlvr/core/cl_input.lua`, but no module reads it (the VR plan's wrist flashlight was not built).
The flashlight follows the player's eye angles, which VR sets from the head, and the measurement uses the light's own
place and direction, so automatic brightness works the same in the headset; it runs once a frame (true stereo is the
runtime's).

## The dance light: uniform lighting and more (ADR 0209)

Everything new is off by default, so an existing setup looks as it did (the harness checks the old values).

| Setting | Default | What |
|---|---|---|
| `mmd_vmd_npc_flashlight_uniform` | 0 | Uniform lighting: intensity x (d / normal distance)^(2 x strength), within 1/64 and Max boost, d being the light's distance to where its axis passes the character's body (a face close-up measures to the face) |
| `mmd_vmd_npc_flashlight_uniform_strength` | 1 | How much of the change with distance it makes up |
| `mmd_vmd_npc_flashlight_uniform_distance` | 150 units | Where Brightness applies unchanged: Brightness becomes the character's light at this distance |
| `mmd_vmd_npc_flashlight_uniform_max` | 16 | The most it brightens for a far character |
| `mmd_vmd_npc_flashlight_aim` | 0 | Aim at the part of the character the view is on (pelvis to head) instead of along the view |
| `mmd_vmd_npc_flashlight_temperature` | 0 (off) | Colour temperature in kelvin at white's luminance, tinted by the RGB colour |
| `mmd_vmd_npc_flashlight_rim` | 0 (off) | A rim light 80 units behind the chest (as the camera sees it) and 40 above, aimed at the head, at this share of Brightness at the normal distance, no haze |

- **The character:** the camera path's dancer (or the debug preview's anchor), the self playback's dancer in its
  third-person view, else the dancing character whose body passes nearest the light's axis inside its cone (this
  client's own dances, the camera tracks, the group actors, and a look into the beam four times a second for dances
  only the server's flag reports). With none, the light measures what it points at as the flashlight does, and holds
  its gain when nothing is hit.
- **Cuts:** the gain eases (0.03 s down, 0.12 s up) but is set at once when the light jumps (farther than 32 units and
  a quarter of the distance, or about 20 degrees, in one frame) or the character changes.
- **Presets** (a Preset choice): Camera light (as before), Uniform camera light, Follow spot (aimed, FOV 40), Stage with
  rim light (aimed, FOV 70, rim 0.8). They leave brightness, colour and offsets alone.
- **Menu** (the tool's Lighting tab): the Preset choice under the switches; a Character lighting section (Uniform
  lighting, Strength, Normal distance, Max boost, Aim at the character, Rim light, with help lines); Temperature (K) at
  the top of Color. 19 new keys in all nine of the add-on's languages.
- **Without Remix** (the add-on alone): the projected texture with the same maths for its 100 / d fade.

## One distance maths, two copies

`cl_remix_light_gain.lua` (fixes) and `cl_light_gain.lua` (motion importer) are the same file: target gain,
inverse-power mean, easing, jump test, sampling ring, colour temperature. Each part ships its own, so neither needs the
other; `test_lights.py` fails if they differ. Both paths are in the render guard's list of bundled Lua
(`_nativeloader_guard.lua`), which the guard's tests require of every bundled Lua file.

## Files

- `packages/fixes/.../remixlua/cl/remixapi/cl_remix_flashlight.lua`, `.../cl_remix_light_gain.lua` (new), the part's
  `files.json` and README section.
- `packages/character-motion-importer/mmd_vmd_npc/lua/mmd_vmd_npc/cl_flashlight.lua`, `cl_light_gain.lua` (new),
  `sh_core.lua` (catalog), `lua/autorun/mmd_vmd_npc.lua` (sends the maths file), `lua/weapons/gmod_tool/stools/mmd_vmd_npc.lua`
  (the Lighting tab), the part's `files.json`.
- `companion/nativeloader/lua/autorun/_nativeloader_guard.lua` (two paths), `companion/i18n/addons/*` (six texts),
  `companion/i18n/README.md` (review note).
- Tests: `tools/tests/flashlight_harness.lua` (`auto`), `test_flashlight.py`, `light_gain_harness.lua`,
  `dance_light_harness.lua`, `test_lights.py`, each with its `.md`.
- Docs: ADRs 0208 and 0209 and their rows, CHANGELOG, RESEARCH, TESTING, this report and its line in the handover index.

## Verified (offline)

- `test_flashlight.py` (server, client, auto) and `test_lights.py` (the copies, the maths, eight dance-light scenarios,
  the menu against the catalog) pass; see [TESTING.md](../TESTING.md) ("Lights").
- Each harness failed against deliberately broken copies (no cut snap, no hold, aiming at the feet, the nearest dancer
  instead of the one on the axis, no rim share, no luminance scaling, symmetric easing, remote lights every frame,
  solid traces counted, no initial gain, traces from the light, no vehicle filter).
- `check_addon_i18n.py` (motion: 481 keys in nine languages, 0 problems) and `companion_i18n.py check` (480 add-on
  texts in six languages).
- `inputs.py verify`: 15 parts, 0 problems. The full gate, `tools\test.ps1 -Config Release` in the worktree on
  `742e4158`: all checks passed (C++ 35 of 35; Python 1911 tests in `tools`, 29 in `tools\gmapack`, 26 in
  `tools\steam`, OK). The next commit only restored two blank lines' indentation in the fixes' flashlight and
  re-indexed it; the flashlight, light, render-guard and inputs tests passed again after it.

## In-game checks still needed (the user's call)

The flashlight (RTX start, a dark map, flashlight key):

1. Walk up to a wall: no blow-out; look down a long corridor or across a hall: brighter than before, not blown out;
   sweep across door frames and pillars: no visible pumping or flicker.
2. `rtx_flashlight_debug 1`: the console line once a second and the cyan marker where the beam lands.
3. Lights > Flashlight: Adjust brightness to distance off is the light as before; Strength, Normal Distance and Max
   Boost act as described; Reset.
4. In a vehicle (HL2 jeep, a simfphys or LVS car): the light stays lit.
5. `rtx_flashlight_volumetric 1` outdoors at night, pointing at the sky: no glowing haze.
6. VR: switch the flashlight with the keyboard key in the headset; it follows the head and adjusts.
7. The section's labels in a CJK language fit.

The dance light (a dance with a camera path, the tool's Lighting tab):

1. Preset "Uniform camera light": the dancer stays evenly lit through close-ups and wide shots; no flash at cuts.
2. Strength, Normal distance and Max boost; Brightness still sets the level.
3. "Follow spot": the light centred on the dancer; "Stage with rim light": an outline from behind, no haze blob.
4. Temperature 3200 and 8000: warm and cool at the same brightness, tinted by the RGB sliders.
5. Third-person self playback, and first person with Follow my eyes: the dancer on the axis evenly lit; with no
   dancer, a wall ahead.
6. A group dance: the camera's anchor dancer is the one kept even.
7. An existing setup with the defaults looks as before.
8. Without RTX (the add-on alone): the projected texture with uniform lighting.

## Open questions

1. Should the dance light's uniform lighting be on by default, as the flashlight's automatic brightness is? It is off
   (the request said "allow ... an option"); the Uniform camera light preset turns it on in one choice.
2. The flashlight's normal distance (256) and strength (0.8) are a guess at where the classic Brightness 5 looked
   right; the in-game check may want other defaults.
3. VR's main-hand stick click is mapped to `flashlight` but nothing reads it: should it switch the flashlight (a VR
   change, which needs the user's approval)?
4. The translations (6 x 6 for the flashlight, 19 x 8 for the dance light) are Claude's and await a person's review.

## Published

The user asked for the round to be committed and pushed when finished (2026-11-14: "Commit and push after you finish"). `main` was fast-forwarded to `058f28cf` (the round on `qol-1114`, one squashed commit per item, after the gate passed on the combined tree: C++ 35 of 35, Python 1,958 + 29 + 26 tests); the merge's hook built the package from `packages/` and uploaded item 3829070317 as **0.0.0-dev.20261114090900+c46c58b9** (2,088,047,623 bytes, SHA-256 `94061aff390e3ebbddcbbc689610ee7c10439f1c5d3f444c343f714f8b1c9ae4`, content digest `cb36cc1c...`) at 2026-11-14 09:09:20 UTC. Not yet checked in a game: the checks above are open.
