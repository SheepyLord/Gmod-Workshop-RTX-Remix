# 0208: The RTX flashlight's automatic brightness

- Status: Accepted 2026-11-14 on the branch `qol-lights`, tested offline; the in-game checks are the user's call.
- Decided by: the user's request, Claude choosing how. The user: "Enhance the RTX flashlight allow better / automatic
  adjustment of the brightness (enabled by default) to prevent overbright and overdim. (This is connected to [the
  dance light item])."
- Builds on: [0112](0112-fixes-lua-apis-stay-in-the-game-and-follow-the-player.md) (the flashlight's R19 fixes, one
  Remix light per player). Shares its distance maths with [0209](0209-the-dance-lights-uniform-lighting-and-options.md).
- Licence: the change is in the GPL-2.0 fixes part (`packages/fixes`), the established practice for its Lua; the new
  maths file is this project's own code (MIT), the same file the MIT character motion importer ships.

## Context

The RTX fixes replace the engine's flashlight with a Remix sphere light (`remixlua/cl/remixapi/cl_remix_flashlight.lua`)
of a fixed radiance: the colour times `rtx_flashlight_brightness / 1000`. The classic install's settings, which the
companion applies at the first start (`classic_defaults.lua`), are Brightness 5, radius 20, cone angle 90 (Remix shaping's
half angle: a hemisphere) and the light 20 units behind the eyes. A sphere light's irradiance on a surface d away is
pi x radiance x (radius / d)^2: a wall 30 units ahead gets about seventy times the light of one at 250 and is blown out,
the end of a corridor at 1000 units gets a sixteenth and is dark. Remix's own exposure adapts the whole picture, slowly,
whatever lights it.

## Decision

1. **On by default** (`rtx_flashlight_auto 1`). With it off the light is exactly as before: the fixed radiance, no
   measurement.
2. **Where the beam lands.** Each frame the light measures what it lights with seven traces across the beam: its axis
   and six directions around it at half its cone angle, at most 20 degrees off the axis. They start at the eyes (the
   light itself sits behind them, inside the wall the player backs against) and each hit is measured from the light.
   The mask is `MASK_OPAQUE_AND_NPCS`: walls, props and characters stop a trace; glass, grates and water let it
   through, as they let the light through. The player, the vehicle they sit in and the car a seat is parented to are
   filtered (their own hull would read as a wall up close). A trace that starts inside a solid (noclip in a wall) is
   ignored; when none tells anything the gain holds.
3. **One distance.** The seven hits make one distance, the inverse-square mean (the distance at which a single surface
   would get the light they get together), the axis counting twice: a near wall in part of the beam dominates, as it
   dominates the picture.
4. **The gain.** (distance / normal distance)^(2 x strength), kept between 1/64 and Max Boost. Brightness keeps its
   meaning: the level at the normal distance. Defaults: normal distance 256 units (about 5 m), strength 0.8 (a fifth
   of the change with distance is kept as a depth cue), Max Boost 8. The traces reach no farther than where the gain
   reaches its maximum (about 1170 units with the defaults), between 512 and 8192.
5. **Eased, fast down and slow up.** In log space with a time constant of 0.08 s when the gain drops and 0.6 s when it
   rises: a surface that comes close never flashes, and a measurement that flickers (a trace crossing a door frame)
   does not pump the light. The light comes on at its measured gain. Another player's light, which this client also
   draws, is measured ten times a second from that player's eyes and eased every frame.
6. **The haze is not boosted.** Above a gain of 1 the volumetric scale is divided by the gain, so a boost lights far
   surfaces and not the haze beside the player; dimming dims the haze as well.
7. **The menu** (Lights > Flashlight): an "Automatic Brightness" section with the switch, its help line, Strength,
   Normal Distance and Max Boost; Reset restores them (`rtx_flashlight_auto_strength 0.8`,
   `rtx_flashlight_auto_distance 256`, `rtx_flashlight_auto_max 8`). `rtx_flashlight_debug 1` also prints the beam's
   distance and gain once a second and marks where the beam lands.
8. **Shared, not dependent.** The maths (target, inverse-power mean, easing, sampling ring) is
   `remixlua/cl/remixapi/cl_remix_light_gain.lua`, a pure module the flashlight `include`s. The character motion
   importer ships the same file as `mmd_vmd_npc/cl_light_gain.lua` for its dance light (ADR 0209); the tests require
   the two copies to be the same bytes, so the two lights cannot drift apart while neither part needs the other.

## Consequences

- Seven `util.TraceLine` calls a frame for your own flashlight while it is on, and seven a tenth of a second for each
  other player's; no allocation per frame (reused vectors and trace tables).
- A held prop or a character right in front of the flashlight dims it as a wall would: that is what would blow out.
- Pointing at the sky or across a field far beyond reach brightens the light to Max Boost; it lights nothing there, and
  the haze is not boosted. Turning back to something near dims it within a few frames.
- **VR** (checked, unchanged): the flashlight follows the player's eye angles, which VR sets from the head (pitch and
  yaw, no roll), from the player's eye position; the measurement uses the light's own place and direction, so it works
  the same in the headset. VR does not drive the flashlight from a hand: the main hand's stick click is mapped to a
  `flashlight` action in `vr/addon/lua/nlvr/core/cl_input.lua`, but no module reads it (the VR plan's flashlight on
  the off hand's wrist was never built). True stereo renders through the runtime, so the measurement runs once a frame.
- The fixes' loader includes every file of `remixlua/cl/remixapi/` as a sub-add-on; the maths file only returns its
  table, so that is harmless. Its path joins the render guard's list of bundled Lua paths (ADR 0086), as every bundled
  Lua file must.
- Six new menu texts in the bundled add-ons' catalogs (`companion/i18n/addons`), translated by Claude, not yet
  reviewed by a person.

## Alternatives considered

- **Measure the picture's brightness** (a read-back of the frame or of Remix's exposure): R28 stopped periodic screen
  read-backs because they stall the GPU, and the picture's brightness mixes the flashlight with everything else.
- **One trace along the axis:** flickers whenever the axis crosses an edge, and misses the side walls of a corridor
  that dominate the screen.
- **Change the light's falloff:** Remix lights are physical; there is no falloff exponent to set, and a light that did
  not fall off within a frame would look flat. The gain changes only the light's overall level; near and far surfaces
  in one picture still fall off as they should.
- **Leave it to Remix's auto exposure:** slow, global, and it would also darken scenes the flashlight does not light.
- **Off by default:** the user asked for it on by default.
