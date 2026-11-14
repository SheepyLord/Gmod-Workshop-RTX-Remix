# 0209: The dance light's uniform lighting and options

- Status: Accepted 2026-11-14 on the branch `qol-lights`, tested offline; the in-game checks are the user's call.
- Decided by: the user's request, Claude choosing how. The user: "The RTX Remix light of the dance animation player
  needs modification and enhancement, allow more customization and allow an uniformed lighting option where light
  level scale with the distance to character."
- Shares its distance maths with [0208](0208-the-rtx-flashlights-automatic-brightness.md), the RTX flashlight's
  automatic brightness.
- Part: the character motion importer (`packages/character-motion-importer`, the MMD VMD NPC add-on, MIT).

## Context

The dance animation player's light (`lua/mmd_vmd_npc/cl_flashlight.lua`) follows the add-on's view: the imported
camera path (or its debug preview), the third-person self-playback camera, else the player's eyes. In RTX starts it is
a Remix sphere spotlight of a fixed radiance (the colour times Brightness / 4), without Remix a projected texture. With
the classic install's settings (Brightness 0.28, FOV 100, radius 30, 45 units behind the camera) it sits beside the
camera and always points along the view. A camera path swings from face close-ups to wide shots, so the dancer is
blown out at one moment and dark the next: the light falls off with the square of the distance (pi x radiance x
(radius / d)^2). Its only settings were brightness, cone, distances, colour, offsets and the Remix shaping.

## Decision

1. **Uniform lighting** (`mmd_vmd_npc_flashlight_uniform`, off by default: the user asked for an option, and an
   existing setup keeps its look until it is chosen). The light's intensity is multiplied by
   (d / normal distance)^(2 x strength), kept between 1/64 and Max boost, so the character gets the same light at every
   distance. d is the distance from the light to where its axis passes the character's body: the point of the segment
   from the feet to the head (the pelvis and head bones, the feet as far below the pelvis as the head is above it)
   nearest the axis. A face close-up measures to the face, a full shot to the body. Brightness keeps its meaning and
   becomes the character's light at the normal distance: intensity as illuminance at the character. Defaults:
   strength 1, normal distance 150 units, Max boost 16 (`_uniform_strength`, `_uniform_distance`, `_uniform_max`).
2. **The character.** The one the view is about: the camera path's anchor (the dancer the path is authored around;
   in the debug preview its anchor), the self playback's dancer in its third-person view. Otherwise the dancing
   character whose body passes nearest the light's axis, inside its cone plus 15 degrees and its throw distance. Dancing
   is this client's own poser (`MMDVMDNPC.LocalPlaybacks`) or the server's `MMDVMDNPCDancing` flag; candidates are the
   local playbacks, the camera tracks' anchors, the assigned group actors and a look into the beam
   (`ents.FindInCone`) four times a second, which finds dances this client did not build. With no character in the
   beam the light measures what it points at as the RTX flashlight does (seven traces, ADR 0208; the player and their
   vehicle left out), and when nothing is hit it holds its gain.
3. **Easing that never lags a cut.** The gain eases in log space, 0.03 s down and 0.12 s up, and is set at once when the
   view jumps (the light moved farther than 32 units and a quarter of the distance, or turned more than about 20 degrees,
   in one frame: a camera cut) or the character changes.
4. **Aim at the character** (`_aim`, off by default): the light points at the part of the body the view is on, the
   point of the pelvis-to-head segment nearest the view's axis (never the feet), instead of straight along the view.
   With no character it points along the view.
5. **Colour temperature** (`_temperature`, kelvin, 0 = off): a curve fit of the black body's colour from 1000 to 40000
   K, scaled to the luminance of white so a warmer light is no darker, tinted by the red, green and blue settings.
   Without Remix the projected texture keeps its strongest channel at 255 and carries the rest in its brightness.
6. **Rim light** (`_rim`, 0-2, 0 = off): a second Remix sphere light behind the character as the camera sees it, 80
   units behind its chest and 40 above, aimed at its head (cone 35 degrees, softness 0.5, no haze), lighting the
   character at that share of Brightness at the normal distance. It needs a character and goes with it. Without Remix a
   second projected texture without shadows.
7. **Presets**: Camera light (as before), Uniform camera light, Follow spot (aimed, FOV 40, softness 0.2) and Stage
   with rim light (aimed, FOV 70, rim 0.8). A preset sets uniform lighting, its strength, aim, the rim light, FOV and
   softness; brightness, colour and offsets stay the player's (`MMDVMDNPC.FlashlightPresets`,
   `MMDVMDNPC.ApplyFlashlightPreset`).
8. **The haze is not boosted:** above a gain of 1 the volumetric scale is divided by the gain, so a far camera's boost
   lights the dancer and not the haze beside the camera.
9. **Without Remix** the same maths with the projected texture's own falloff: Source's flashlight shader fades as
   100 / d beyond 100 units with GMod's default attenuation (constant 0, linear 100, quadratic 0), so the exponent is 1
   and nothing closer than 100 units gets brighter.
10. **The menu** (the tool's Lighting tab): a Preset choice with its help line under the switches; a new Character
    lighting section with Uniform lighting and its help, Strength, Normal distance, Max boost, Aim at the character
    and its help, Rim light and its help; Temperature (K) and its help at the top of Color. Nineteen new catalog keys in
    all nine of the add-on's languages.
11. **The maths** is `mmd_vmd_npc/cl_light_gain.lua`, the same bytes as the RTX fixes' `cl_remix_light_gain.lua`
    (ADR 0208); the add-on's autorun sends it to clients.

## Consequences

- With the defaults nothing changes: the same position, direction, radiance and shaping, and no traces or looks for
  dancers (the offline harness checks the values the light had).
- With uniform lighting a dancer keeps one level of light through a camera path's cuts and dolly moves; a wide shot
  beyond the normal distance x 4 (Max boost 16) gets less, by design, so the boost stays bounded.
- The light follows the view from the `Think` hook as before, which runs before the frame's `CalcView`: it uses the
  previous frame's camera. Through a cut the light keeps one frame of the old place with the old gain, so the dancer's
  light stays uniform; the next frame both change.
- Cost: with an option on, a few bone reads a frame, a look into the beam four times a second, and seven traces a frame
  only while no character is in the beam. With every option off, none.
- Translations (19 keys x 8 languages, Arabic and Spanish included as the add-on ships them) are written by Claude
  and not yet reviewed by a person.

## Alternatives considered

- **Light distance from the camera instead of the light:** the light sits 45 units behind the camera in the classic
  settings; the light's own distance is what its falloff follows.
- **Distance to the character's centre:** a face close-up would measure to the pelvis and blow out the face; the point
  the axis passes gives the part on screen.
- **Uniform lighting on by default:** the user asked for an option, and existing setups keep their look; a preset turns
  it on in one choice. Whether it should be on by default is left to the user.
- **A fill light:** the main light already sits beside the camera, so its shadows fall behind the character; a light
  behind it (the rim) adds what a camera light lacks.
- **GMod's saved tool presets** (`ControlPresets`): they write the player's preset files; four built-in looks in a
  plain choice are enough, and the sliders stay the place for one's own.
