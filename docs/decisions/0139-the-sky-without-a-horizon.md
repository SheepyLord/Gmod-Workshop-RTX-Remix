# 0139: The sky without a horizon

- Status: Accepted 2026-11-09
- Decided by: the agent in R26, on the user's request: "In the sky and weather tab, add an option to allow
  the sky to be rendered in the whole sky box (like some universe / floating island maps), disabling the
  horizon", and "Add a no-horizon option in the sky options, when enabled the entire sky will be rendered
  for the whole skybox without any horizon effect." How a sky below the horizon should look was the agent's
  choice, made from PoC sessions; the main session reviews the branch.
- Runtime patch: `runtime/patches/0041-*` ([runtime/README.md](../../runtime/README.md)).

## Context

The physical sky (`rtx.skyMode 1`) is a planet's: the atmosphere frame stands on the ground under the
camera, and a ray aimed below the horizon runs into the planet. The runtime does not draw the ground there:
its sky-view LUT marches such a ray through the planet as ground-level air, which saturates into one even
haze. Below the horizon there are no clouds and no high clouds (their marches only meet rays going up), the
stars fade out within a degree of it, the airglow brightens toward the nadir, and a moon there is drawn as a
black disc. On a normal map the world's ground hides all of it. On a map that floats in the sky or in space,
every view over the edge shows it: a flat haze under a sharp horizon line, grey-blue at noon, brown-orange at
sunset, navy at night (RESEARCH.md, "R26: the sky below the horizon"). No runtime option changed that:
`planetRadius`, `atmosphereThickness`, `flipUpAxis` and the time cycle all keep the planet under the camera,
and the air's density is a function of the height above it.

## Decision

1. **One runtime option, `rtx.atmosphere.noHorizon` (bool, default False)**, in patch 0041. Below the
   horizon the sky goes on: every part of it is shaded from a direction above the horizon, chosen per layer.
   - **The air's gradient: the mirror** `(x, -y, z)` (`noHorizonMirror`). The sky-view LUT's bake marches
     the mirror's air into the LUT's lower half. The gradient has no pattern a mirror could repeat, and the
     mirror keeps the azimuth, so the twilight's warm side stays on the sun's side and the sky is
     continuous at the horizon. The brightest band of the day sky stays at eye level, where the line of
     sight crosses the most air, on both sides of it.
   - **The clouds and the high cloud layer: the antipode** `-dir` (`noHorizonCloudDir`), the clouds above
     the horizon behind the viewer. The screen-space cloud pass marches it for a pixel below the horizon,
     the high layer meets the antipode's shell, and secondary rays read the antipode's texel of the dome
     LUT. Near the horizon these clouds are distant and faded into the haze, which hides where the two
     sides meet; a ray within 0.0015 of the horizon is held just above it, where the march still meets the
     slab (the pass skips |y| <= 0.001), so no line of bare sky is left.
   - **The angle to the sun and the moons stays the view's own.** Every phase term (Rayleigh and Mie in the
     LUT's bake, the clouds' lobes, powder and moon lobe, the high layer's phase, 22 and 46 degree halos,
     sun dogs and arcs) uses the true direction. So the sun's aureole, the silver linings and the halos stay
     around the sun: a 22 degree halo around a low sun is a whole ring, and no glow of a sun that is not
     there appears below. The multiple scattering has no phase and follows the mirror exactly.
   - **The cloud bleed fades out over the first 6 degrees below the horizon.** It reads the dome LUT,
     whose texels were lit for their own direction's angle to the sun, so it would bring a silver lining
     to the wrong place below (the antisolar point for the antipode).
   - **What lies beyond the air is drawn where it is, in every direction**: the stars, the galaxy and the
     nebulae of the night sky image without the horizon's fade (the airglow's boost toward the horizon is
     its mirror's), the moons and their glow, lit through the air of their mirror, so a moon below the
     horizon is a lit moon, not a black disc.
   - **The sun still sets.** Its disc, the solar eclipse and everything the sun lights keep the time of
     day: below the horizon it is night, as before.
   - The field is the former `r18Pad0` slot of `AtmosphereArgs` (the constant buffer keeps its size). It
     stays in the sky-view LUT's cache key, so the LUT is baked again when it changes; the transmittance,
     multiscattering and voxel-grid keys zero it. Off, every changed site computes what it did before,
     from the same inputs, and the rendering is unchanged (RESEARCH.md, "R26", the A/B).
   - Reflections and indirect light see the same sky below the horizon (the same `evalSkyRadiance` and
     LUT, the dome LUT's antipode texel). The volumetric fog's sky ambient stays the upper hemisphere's.
   - The dev menu: **No Horizon** under Atmosphere, its tooltip the option's description; both translated
     in the runtime's six catalogs; `RtxOptions.md` regenerated.
2. **The companion's checkbox, No horizon** (`nativeloader_sky_no_horizon`, a saved client setting, off),
   under Sky in the Sky and weather panel, sends the option. It is how the player sees whichever physical
   sky is shown, not whose sky it is:
   - with the companion in charge it goes out with the rest of the sky;
   - on a map whose add-on owns the sky (ADR 0031, ADR 0105) it is sent too, but only when ticked or
     changed, so with the setting at its default such a map still gets nothing from the companion;
   - changing it does not take that map's sky over (as the update interval does not). A content pack that
     watches the companion's sky settings to yield its own sun (the Workshop content pack skill's
     `SKY_CONVARS`) needs no change: the companion never takes the sky over for it.
   The guide's Sky and weather picture is captured again with the checkbox (badge 2).

## Alternatives

- **A mirror of everything**, the clouds included (PoC session s1): continuous, but the clouds read as a
  calm lake's reflection with the horizon as its axis, the very horizon the user wants gone; and the cloud
  bleed put a bright patch where a mirrored sun would be.
- **A pure mirror with the mirror's phase**: a second sun glow, silver linings and halos below the horizon,
  around a sun that is not there.
- **Removing the planet**: without a ground a ray below the horizon runs into ever denser air, the haze
  again.
- **Lifting the horizon** (every direction shaded as the sky some degrees higher, so no haze band is left at
  eye level): it would also change the sky above the horizon, and it pulls a low sun's aureole into a band
  along the horizon at sunset.
- **No clouds below the horizon**: a deck above would end at a line, which is again a horizon.
- **Clouds below from an offset of the cloud field**: no repeat at all, but the dome LUT of the secondary
  rays holds only the field above, so reflections would show other clouds than the view.
- **Showing the sun below the horizon too** ("space" with a sun at night): it would light nothing; the
  day-night cycle is the planet's.
- **Making the companion's checkbox part of the sky a map's add-on owns** (sent only in charge, a change
  taking the sky over): consistent with the other sky settings, but a content pack's watcher would not see
  the change and would keep its own sun beside the companion's. The view is the player's either way.

## Consequences

- Cost while off: none. On, the screen-space cloud pass also marches the pixels below the horizon, up to as
  much again as the clouds above them cost: at 3840x2160 0.5 ms more in clear weather, 1.2-1.8 ms partly
  cloudy, up to 3.2 ms overcast (RESEARCH.md, "R26"); the sky-view LUT is baked once at a change.
- The clouds below are the clouds of the opposite side seen from below (cloud bases, upside down), not
  sunlit tops: lighting tops would need the clouds' optical depth toward the ground, which no grid holds.
  Looking straight down shows the zenith's clouds, turned.
- Secondary rays below the horizon read the dome LUT's antipode texel, lit for the antipode's angle to the
  sun: a reflection of the lower sky may show a silver lining toward the antisolar point. Indirect light
  averages it away.
- The option is global for the session's sky: ticked on one map, it stays ticked on the next, where the
  ground usually hides what is below the horizon anyway.
