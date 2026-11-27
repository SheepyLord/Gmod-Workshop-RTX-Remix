# Our night sky on the Enhanced sky: the design (2026-11-26)

A design for the user's decision. Nothing here is coded yet.

The user, at the merge of the Enhanced sky (2026-11-26): "Yes, and open this for later, we should adapt our own night
sky with the enhanced night." Then, the same evening: "Plan how our own night sky could be integrated into the Enhanced
sky, and show the user the design before any code."

## What each sky shows at night today

| | Standard (ours) | Enhanced (the NUMOS library) |
|---|---|---|
| Stars | the night sky image's star layer, or simulated stars | real stars: the Hipparcos catalogue to magnitude 7.5, drawn as points, twinkling near the horizon |
| Constellations | a layer of their own in the image | none |
| Milky Way | the image's galaxy band | the real one, from Gaia, at its measured brightness |
| Nebulae | the image's coloured nebula layer | none |
| Editor | brightness and colour for each layer (Night sky editor) | Starlight and Star twinkle (Enhanced sky editor) |
| The Moon | ours: real maps, phase, earthshine, a glow, size 0.5-5 degrees, the colours of a lunar eclipse | the library's: real maps, the measured phase law, earthshine, eclipses; our editor's size and brightness reach it; no glow |
| Clouds at night | dark | lit by the Moon |
| Shooting stars | yes, with a rate and a brightness | none |
| Night glow | the weather's tinted airglow | physical airglow and zodiacal light |
| Twilight | stars from 1 degree below the horizon, the Milky Way at 18 | physical, continuous |
| Solar eclipse | the Sun's disc, chromosphere and corona behind the Moon | the Moon covers the Sun; no corona |

Standard's night is a picture: colourful nebulae, the constellations, a bright band. Enhanced's is physical: few stars
over the town's glow, the Moon lighting the clouds. Pictures: `out/sky2/judged/night/` (gm_construct, partly cloudy,
midnight: Standard, Enhanced).

## The design

**One rule:** the library keeps what it does best (the air, the twilight, the Moon's light on clouds and the map), and
our night sky brings its look and its editor. The library stays pinned and unmodified (ADR 0267): the runtime draws our
parts in the Enhanced sky's own composite, as it already draws the sun rays and the rainbow there.

1. **Our night sky image in Enhanced.** The runtime adds the image's four layers (stars, constellations, Milky Way,
   nebulae), each with the Night sky editor's brightness and colour, to the Enhanced sky behind the air and the
   clouds: the air dims them toward the horizon, clouds cover them, the Moon's disc hides what lies behind it. The
   library's own stars and Milky Way are switched off while the image shows (its `nightSkyStars` setting), so nothing is
   drawn twice. Whether the library's starlight on the night air goes with them is to be checked; if it does, the
   night air keeps it. The layers come out in the twilight as they do in Standard: the stars and constellations early,
   the Milky Way and the nebulae in full darkness.
   - **Brightness.** The image is put into the library's light units once, so that at the editor's defaults its Milky
     Way is as bright as the library's (measured in the PoC). From there the Enhanced editor's Night brightness and
     Starlight move the image as they move the library's stars.
   - **A choice** on the Night sky editor page: *Stars: Night sky image* or *Real stars* (the library's).
2. **Shooting stars**, as in Standard: the editor's rate and brightness, behind the clouds and through the air.
3. **The Moon.** The library's Moon stays: it is the one that lights the clouds and the map. The editor's size and
   brightness already reach it; the editor's Glow adds our glow around it.
4. **The discs drawn by the runtime.** The fix for the dark ring round the sun (this round) has the runtime draw the
   Sun's and the Moon's discs in Enhanced itself. With that, a solar eclipse in Enhanced gets our chromosphere and
   corona, behind the clouds.
5. **Night glow.** The library's physical airglow and zodiacal light stay. The editor's Night glow changes the Standard
   sky only, and its line says so in Enhanced.
6. **One editor page for both skies.** In Enhanced the Night sky editor shows the image's layers, the shooting stars,
   the Moon's size, brightness and glow, and the Stars choice; a control that does nothing in the sky on screen is
   hidden, with a line saying which sky it belongs to. VR keeps the Standard sky.
7. **Reflections.** Water and mirrors at night show the same image, Moon and stars.

**Not in this plan:** sun dogs, the 46 degree halo and the circumzenithal arc in Enhanced's high cloud. The library
draws its cirrus in passes of its own (`cloud_cirrus_map`, `cloud_cirrus_composite`); our arcs would have to read its
cirrus map from our code and light it as ours does. A separate study, if wanted.

## Cost

Four texture reads for each sky pixel at night (Standard pays the same), and a few instructions for the shooting
stars and the glow. Expected well under 0.1 ms at 4K; measured in the PoC at the end.

## How it would be built

- **Runtime** (Codex, one patch on the fork branch `claude/sky-enhanced`): the night sky image's textures and the
  editor's night settings bound to the Enhanced composite; the layers, shooting stars, the Moon's glow and the eclipse
  there and in reflections; the Stars choice switching the library's `nightSkyStars`.
- **Companion** (Codex): the Night sky editor page in Enhanced, the Stars choice, its help lines, the six languages.
- **Claude**: the review; PoC captures of midnight clear and cloudy, twilight, a full moon, a shooting star and an
  eclipse in Standard and in Enhanced with each choice; Standard unchanged; the cost; the gate.

## Decisions for the user

1. **Stars in Enhanced by default:** our night sky image (recommended), or the library's real stars? The other stays
   one choice away.
2. **The Moon:** the library's Moon with our glow (recommended), or our own Moon disc drawn over it?
3. **Night glow:** the library's physical airglow alone (recommended), or our weather night glow added on top?
4. **Sun dogs and the other ice halos in Enhanced:** a separate study later (recommended), or now?

## The user's decisions (2026-11-26)

"Yes, as recommended": our night sky image by default with the library's real stars one choice away; the library's
Moon with our glow; the library's airglow alone; sun dogs and the other ice halos a separate study later.

The work starts after round 3's tasks S and H ([sky-enhanced-round3-plan.md](sky-enhanced-round3-plan.md)): task NR
builds on S's discs in the same runtime files, and task NC on H's changes to the same pages. Round 2's "Rules for both
tasks" hold.

## Task NR: our night sky in the Enhanced composite (the runtime)

On the fork branch `claude/sky-enhanced`, after patch 0115 (task S), as one patch or more; the library unmodified;
Standard (modes 0 and 1) with no diff.

1. **Inputs.** The night sky image's four textures (`AtmosphereStarMap`, `...Galaxy`, `...Nebula`,
   `...Constellations`) and the night sky editor's values (each layer's weight and saturation, the ceiling and the
   brightness, the shooting stars' chance and brightness, the Moon's glow, the eclipse's corona and chromosphere
   settings) reach the passes that draw Enhanced's camera sky (`compositePrimarySky`) and its reflections (the PSR
   miss). Prefer a small block of our own (beside `NumosSkyEffectsArgs`) over binding all of Standard's arguments.
2. **Which stars.** A runtime option, `rtx.atmosphere.numos.nightSkyImage` (bool, default True): while it is True the
   host draws our image and the library's `nightSkyStars` is off; False gives the library's real stars and no image.
   Check whether the library's starlight on the night air depends on `nightSkyStars`, and say what you found; the
   night air keeps that light either way.
3. **The image** in the camera sky, added to the background before the cloud composite, so clouds cover it:
   - in the celestial frame the library's stars and Moon use (it must turn with them through the night);
   - through the air toward that direction (the library's view transmittance) and behind the Moon (the coverage the
     library's disk evaluation reports);
   - with Standard's twilight: the stars and the constellations from the sun 1 degree below the horizon, full at about
     8; the Milky Way and the nebulae from about 8 degrees, full at 18 (`evalNightSky`, `evalStarMap`);
   - in the library's light units: one constant, so that at the editor's defaults the image's Milky Way has the
     library's Milky Way's mean brightness (measure both and write down how), then the library's night gain and star
     gain as its own stars get them, and its pre-exposure.
4. **Shooting stars** as Standard draws them (`evalNightSky`): the editor's chance and brightness, through the air,
   behind clouds and the Moon.
5. **The Moon's glow** as Standard's (the editor's Glow): round the library's Moon, scaled by the light the library
   gives that Moon, under its disc.
6. **A solar eclipse:** our chromosphere and corona round the Sun's disc (Standard's `evalSolarEclipse`, without the
   disc S already draws) while the library's Moon covers the Sun, behind the clouds.
7. **Reflections** (the PSR miss): the image, the shooting stars and the glow too, under the clouds' dome
   transmittance as the library's disks are.
8. **Checks:** the shaders alone with the pinned Slang compiler; `runtime\build_runtime.ps1 -NoImport -Install`; a
   unit test of anything with numbers (the twilight weights, the calibration constant).

**Deliver:** the fork commit(s); the patch(es), `runtime/base.json` (`pending_patches`), `runtime/README.md`, a
CHANGELOG line for players, the option in `RtxOptions.md`; `docs/handover/sky-enhanced-NR-report.md` with the
calibration's numbers, what Claude should look at first in the game (and with which debug view), the cost you expect,
what you built and tested, and what you could not do.

## Task NC: the Night sky editor in Enhanced (the companion)

After task H, on the same branch line.

1. The **Night sky editor page** serves both skies. In Enhanced it shows the image's layers, the shooting stars, the
   Moon's size, brightness and glow, and a new choice, **Stars: Night sky image / Real stars** (a saved client
   setting, default Night sky image), sent as `rtx.atmosphere.numos.nightSkyImage`. The controls that act only in
   Standard (the simulated stars, Night glow, earthshine if it does nothing in Enhanced) stay visible with a line
   saying they change the Standard sky; in Standard the Stars choice says it is for the Enhanced sky.
2. Every setting the page has reaches the runtime in Enhanced as it does in Standard; today some are sent only in
   Standard: find which, and send them in both.
3. The Sky page's line under the Enhanced choice ("Choose Standard for the Night sky editor's layers and shooting
   stars.") says what is true now.
4. Texts in English and the six catalogs (Python, explicit UTF-8, no stray `?`); tests in
   `tools/tests/test_companion_sky.py` (the choice sent in Enhanced, not in Standard; the editor's values reaching
   Remix in Enhanced; Standard's sends unchanged); the `.md` beside each changed script; a CHANGELOG line for
   players.

**Deliver:** commits and `docs/handover/sky-enhanced-NC-report.md`: each control with its setting and what it does in
each sky, the tests and their output, what Claude must check in the game.

## What Claude does

- Reviews S and H, tests them in the PoC, merges and publishes them first: they fix the default sky every player has
  now.
- Then starts NR and NC on the merged line, reviews them, and tests the night in the PoC: midnight clear and partly
  cloudy, the twilight, a full moon and a crescent, a shooting star, an eclipse, a mirror (water) at night, in
  Enhanced with each Stars choice and in Standard (unchanged); the frame time against Standard in one launch.
- Writes the decision record, stores the runtime, runs the gate, merges and publishes.
