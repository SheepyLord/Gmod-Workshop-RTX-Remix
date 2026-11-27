# 0272: The Enhanced sky below the horizon: the ground, and No horizon

- Status: Accepted 2026-11-27 (the user's report).
- The user, after the Enhanced night was published: "Please improve the look of the horizon and fix the no-horizon
  mode for the enhanced sky mode. Currently the horizon looks a bit off." Their screenshot showed a map whose floor
  ends: beyond it, below the horizon, one flat pale wall of fog under a straight line.
- Runtime patches 0118, 0119 and 0120, the companion. No loader (`winmm.dll`) change. Supersedes nothing: ADR 0139
  (the sky without a horizon, Standard) is extended to the Enhanced sky.
- Design and briefs: [sky-enhanced-horizon-plan.md](../handover/sky-enhanced-horizon-plan.md). Reports:
  [the round](../handover/sky-enhanced-horizon-report.md), [runtime and companion](../handover/sky-enhanced-HR-report.md).

## Context

- **A wall of fog.** The Enhanced composite hazes a camera ray that leaves the scene with the library's miss
  composite, which applies the height fog from the near field's range to 2000 km. Below the fog base the library's fog
  grows denser downward (it is clamped only ten scale heights under the base), so for every ray below the horizon the
  column never ends: the pixel is the fog's own flat colour. The library assumes the host's terrain covers that half
  of the view; in Garry's Mod it shows wherever a map's floor ends below the horizon, from a height, over a cliff or on
  maps that float. What the library draws there itself, the air in front of a lit ground with the clouds' shadows, was
  hidden by it. In the PoC (gm_flatgrass from the air at its edge) it was grey at noon, orange-brown at sunset and
  black at night, under a perfectly straight line.
- **No horizon ignored.** Nothing on the Enhanced path read `rtx.atmosphere.noHorizon` (ADR 0139), and the companion
  greyed the checkbox out in Enhanced and dropped the setting there.

## Decision

1. **Below the horizon the Enhanced sky ends at the library's ground** (No horizon off, the default). A camera ray, or a
   mirror's ray, that leaves the scene below the planet's limb is composited as a surface where it meets the ground at
   the sky's ground-level datum. Its radiance is the library's lit ground (sun, moons, the sky's light and the clouds'
   shadow) without the air in front of it, and the near field, the far field and the fog end at that distance, so no
   fog below the ground and no air counted twice. A pixel across the limb gets both shares, antialiased over a pixel.
   The clouds' shadow is looked up where the ground really is, filtered over the pixel's footprint near the limb, and a
   mirror's ray is shaded from the library's far air and fog in the reflection pass, with no per-pixel record (patch
   0120). With the haze off nothing changes (the library's own sky already shows there).
2. **No horizon in Enhanced, as in Standard (ADR 0139):**
   - **The air** below eye level is the mirror's gradient with the true direction's angle to the sun and the moons: a
     host pass bakes the lower hemisphere (512 by 128) with the library's own march, multiple scattering, lunar light,
     airglow, zodiacal and stellar light, on the first frame and whenever the library bakes its sky-view table. With
     the phase direction equal to the march's it reproduces the library's table bit for bit.
   - **The clouds** below eye level are those of the opposite side, at the screen clouds' quality: a second library
     renderer whose camera is the main camera point-reflected, with the main renderer's settings, measured ground,
     wind, evolution and clock each frame, its own haze, ground probes, lamps, lightning, night data and cloud dome
     off. The composite takes its clouds only where the camera sees the sky below eye level; surfaces below the horizon
     get none (those clouds are a sky at infinity). Both decks fade into the horizon's air over the last half degree.
   - **The haze** below eye level is the mirror's far field and fog; the near field (shadowed air, lamp glow) fades out
     over two degrees below eye level. Real surfaces keep their haze.
   - **The night** is drawn in every direction through the mirror's air: the night sky image, shooting stars, the
     moons lit (not black) with their glow, the library's stars in the catalogue night. The sun still sets: its disc
     and corona show only above the horizon.
   - **Reflections and indirect light** below the horizon read the same air and the main renderer's cloud dome at the
     antipode, with no ground.
   - **Off,** no second renderer, no table and no extra pass exists; the output is patch 0118's.
3. **The companion** sends No horizon in both skies, from the existing `nativeloader_sky_no_horizon`, and keeps its
   checkbox enabled in Enhanced. Its help and the guide already fit both skies. VR keeps the Standard sky.

## Alternatives

- **Keeping the fog, or clamping its density at the base:** the column below the horizon is still endless, a wall.
- **The library's cloud dome for the camera's clouds below:** 256 by 256 over the sphere, about 1.4 by 0.5 degrees a
  texel near the horizon, 60 by 20 pixels at 3840x2160 with a 90 degree view; blurred blobs under sharp clouds.
- **A library lens to turn the rays round:** its lenses keep a ray on its axis's side (`cloudLensMagnify`), so no lens
  maps a ray going down to one going up.
- **Our own cloud march below the horizon:** the library does not hand its cloud fields to the host
  (`FrameOutputs`), and it stays unmodified.
- **The mirror's air with the mirror's phase:** a second sun glow below the horizon (ADR 0139's reason).
- **Mirroring the screen clouds:** looking down, the mirror of the view is off the screen.

## Consequences

- **Cost, No horizon off:** the ground below the horizon costs nothing measurable, and patch 0120 shades a mirror's
  ray without memory of its own. **No horizon on:** the second renderer's screen clouds and their bakes; in the PoC at
  3840x2160 with DLSS 1.6 to 2.5 ms (Standard's No horizon 1.4 to 1.7 ms in the same launch), and about 488 MiB of
  video memory at DLSS Quality, 356 MiB at Performance, freed when it goes off.
- **The shadow near the limb:** where one traced pixel spans several shadow texels, the ground's direct light is held
  to the shadow under the ray's origin (patch 0120), so a sunlit patch far out under a broken deck can be drawn darker
  than it is; without it, gaps in an overcast deck drew a bright strip along the horizon.
- **The ground below the horizon** is the library's: one even surface of albedo `rtx.atmosphere.groundAlbedo` (0.3),
  lit and shadowed, at the ground level the library measures under the camera. A map seen from a height sits on an
  endless plain; on a floating map No horizon is the choice.
- **Limits of No horizon:** the clouds below carry no lightning; the near field below the ground level still holds the
  library's dense fog there, so a floating island's underside can sit in fog; the clouds below are the bases of the
  opposite side's clouds, as in Standard.
