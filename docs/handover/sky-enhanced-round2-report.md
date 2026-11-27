# The Enhanced sky, round 2: report

The round was built on the branch `sky-enhanced`, on top of round 1, and shown to the user, who decided to merge and
publish it with the Enhanced sky as the default (see The user's decisions).

The user saw [round 1](sky-enhanced-report.md) on 2026-11-26 and answered: "Yes, please start round 2 and add more
customization of the sky and cloud, not limited to presets. Codex agents can be ran in fast mode."

- Decision record: [ADR 0268](../decisions/0268-the-enhanced-sky-gets-sun-rays-an-editor-and-mist-choices.md)
  (proposed), with round 1's [ADR 0267](../decisions/0267-the-enhanced-sky-is-the-numos-library-as-a-second-sky.md).
- Plan and briefs: [sky-enhanced-round2-plan.md](sky-enhanced-round2-plan.md) (tasks R2, E, R3, E2, E3).
- Task reports: [runtime, R2 and R3](sky-enhanced-R2-report.md), [companion, E, E2 and E3](sky-enhanced-E-report.md).

## What the player gets

- **Sun rays across the sky.** A low sun shows rays through gaps in the clouds and past buildings, strongest in hazy
  air. A setting scales them (0 to 2; 1 is physical).
- **The Enhanced sky editor,** a page beside the Night sky editor. Every setting that shapes the Enhanced sky is a
  control (46, in eight groups), in the library's own units with a help line. Start from 21 looks (the twelve
  weathers, four of the library's, five of ours), save your own by name, copy a look as one line of text and paste it
  elsewhere. "My own look" replaces the weather's look; rain, snow and sand still follow the weather.
- **Light and mist settings for every weather:** sun rays, rainbow, night brightness, moonlight, starlight, star
  twinkle, cloud shadows, the mist on the map (Enhanced mist, or Remix fog near you with Enhanced beyond), and lamp
  glow in the mist (off by default).
- **A rainbow** in sunlit rain, fading as the air dries over five minutes.
- **Retuned weathers:** a bright haze for hazy days, a light haze for fair weather, storms with breaks, smog from the
  air, crisper fair-weather cumulus.
- **Both skies** take Moon size and brightness from the Night sky editor.

## What is on the branch

| Part | What |
|---|---|
| Runtime patch 0109 | Sun rays: a pass of ours on the library's cloud shadow map (task R2) |
| Runtime patch 0110 | What Remix volumetrics do in Enhanced, decided by the runtime (`rtx.atmosphere.numos.volumetrics`) |
| Runtime patch 0111 | The rainbow, in the Enhanced composite |
| Runtime patch 0112 | The sky adapter released when the device shuts down |
| Runtime patch 0113 | The rays without colour clipping or hatching (task R3) |
| The companion | The editor page and its looks (tasks E, E2, E3), style settings, the mode's own data, the rainbow's rain, no more writes of `rtx.volumetrics.enable` |
| The weather tables | Claude's tuning from PoC trials: `enhanced_weather.lua`, `enhanced_builtin_looks.lua` |

## Who did what

- **Code:** Codex agents, GPT 6.2 Astra at maximum effort in fast mode, as the user asked. Five tasks, each 10 to
  50 minutes: R2 and R3 (runtime), E, E2, E3 (companion).
- **Plan, review, every test in the game, the weather and look values:** Claude.

## Tests in the PoC

At 3840x2160, DLSS Performance (1920x1080 rendered), frame generation off, RTX 5090. The pictures and logs are scratch,
in the main checkout's `out/sky2` (sheets in `judged/R2`, `judged/R2b`, `judged/E5`). Other sessions used the machine
during most runs (Codex builds, another session's package build and upload): single frame times can be off by a
millisecond or two. Costs below are from comparisons inside one game launch where it matters.

### Sun rays

**First build (0109).** The pass worked: its debug views showed clean shafts radiating from the sun through broken
cumulus, and converging toward the point opposite the sun. Three faults:

- at strength 1 the rays were faint, and invisible in the library's clean air;
- above strength 1 the sky beside the clouds turned a saturated electric blue in patches (a per-channel clamp);
- a fine diagonal hatching in the ray term, and a bright line along the horizon in a debug view.

**After the fix (0113),** with the clouds held still and each picture normalised by its own sky's median
(auto-exposure scales a whole picture):

| Sky | Strength 1: share of sky darker by 10 % / by 25 % | Strength 2 |
|---|---|---|
| Partly cloudy, haze 8, sun 10 degrees up, toward it | 16.7 % / 1.6 % | 23.8 % / 11.1 % |
| Partly cloudy, haze 20, sun 8 degrees up, toward it | 18.2 % / 1.9 % | 28.7 % / 15.3 % |
| The same, 70 degrees to the side | 17.3 % / 0 % | 29.7 % / 15.4 % |
| Humid, haze 12, sun 18 degrees up | 9.6 % / 2.9 % | 12.0 % / 8.1 % |
| Noon, haze 8, low view toward the sun | 0 % / 0 % | 3.1 % / 0 % |

- No electric blue: the air in a cloud's shadow is a deeper blue, the removed light keeps its colour.
- No hatching: while the camera turns at 8 degrees a second the picture at strength 2 is smooth at full size.
- **Cost:** below what a frame time can show. Strength 0, 1 and 2 differed by less than the frame-to-frame noise;
  the task measured 0.05 ms for the pass at High on a fixture.
- **Rays need haze.** With the bright haze of the new hazy weather (density 40) and the sun 10 degrees up behind the
  building and the clouds, strong rays fan out at strength 1: the round's best picture
  (`judged/R2/tune-haze2-low.jpg`).

### The editor

- At 3840x2160 the page works: every group, label and help line reads, the buttons and the look list work.
- The first build left an empty band at the top in Enhanced, had a haze density that stopped at 10 (a hazy day needs
  20 to 80) and colour pickers eight lines tall; task E2 fixed all three. Task E3 added Haze darkness.
- Seen again with the final build (`judged/R2b/ui-editor-now.jpg`): no band, haze density from 0 to 100 with its help
  line, colour pickers half as tall, Haze darkness and Lamp glow in mist in place.
- Not seen in the game: saving, loading, pasting and refusing a look. The task's tests cover them offline (55 sky
  tests), including that every weather's and built-in look passes the editor's own checks.

### Mist and lamps

**Lamps in the library's haze** cost 16 ms a frame in round 1. What costs is the number of lights a 64-pixel tile
draws. On `gm_construct` in dense fog at night, without the flashlight:

| Lights a tile | Frame (ms) |
|---|---|
| no lamps | 11.8 |
| 64 (the library's default) | 31.2 |
| 8 | 14.9 |
| 4 | 13.3 |
| 2 | 12.6 |

With the cap the editor's "Lamp glow in mist" uses (4 at High and Medium, 2 at Low), turning it on cost 0.1 to 1.1 ms
over ten views of `gm_construct` with the flashlight on. It stays off by default: in one view of an earlier run, the
flashlight at the camera still cost 12 ms more, and the glow it draws in the mist is faint.

**What Remix volumetrics do in Enhanced** (`gm_construct`, flashlight on, one launch):

| View | Standard | Enhanced mist | Remix fog near you | Round 1's rule |
|---|---|---|---|---|
| Fog at night, toward a lit room | 12.5 | 13.6 | 16.6 | 14.9 |
| Fog at night, the other way | 14.7 | 12.7 | 16.2 | 14.3 |
| Hazy | 12.3 | 11.4 | 13.4 | 12.2 |
| Low sun | 14.1 | 12.1 | 15.4 | 13.7 |
| Noon | 13.9 | 12.2 | 15.3 | 12.8 |

- Enhanced mist veils the foggy night map; Remix fog near you keeps the near map crisp with the fog beyond, for 2 to
  4 ms more with the flashlight on. With the player's Remix fog switch off it is the Enhanced mist, as intended.
- Standard looked the same at the end of the launch as at its start.

**On a real map:** on `gm_construct` with the flashlight on, Enhanced cost 2.4 to 5.5 ms less than Standard over ten
views (Enhanced 10.1-11.8 ms, Standard 12.5-16.7). Standard pays for Remix volumetrics lighting the flashlight's beam,
which Enhanced pauses by default.

### The weathers and the looks

- **Hazy:** round 1's grey fog wall over a blue-lit map came from dense height fog, which the sky's light on surfaces
  ignores. A hazy day is now the aerosol's: a pale sky with a whitish horizon and a wide glow round the sun.
- **Partly cloudy:** crisper cumulus (round 1's nearest cloud was a smooth mass) and a light haze, so a low sun has a
  glow and visible rays.
- **Smoggy:** darker and greyer than hazy; the two still look alike from a distance.
- **Thunderstorm, rain:** clearer air shows the storm's own clouds, a slate colour and gaps give the thunderstorm
  breaks. Looking away from the sun a closed storm deck still reads as mid-grey overcast.
- **Five new looks,** checked at noon and at a low sun: mackerel sky, towering cumulus, humid summer, high cirrus,
  after the rain. Two tried and left out: a low stratus lid (it drew soft blobs) and dust (a grey wall).

### The rainbow

- After rain, through the companion, a rainbow shows, red on the outside, where the geometry puts it (its foot on the
  horizon about 35 degrees from the point opposite a sun 25 degrees up), and fades as the air dries.
- Forced by the option alone in the first trial, it drew nothing, even in a clear sky. Every scene of that trial
  used one look, whose near haze reaches 6 km; a later check drew it (see The rainbow check).

### What Enhanced costs against Standard

The judged scenes, each taken in Standard and then in Enhanced within one game launch (`gm_flatgrass`, no
flashlight), so both share the machine's state:

| Views | Standard (ms) | Enhanced (ms) | Enhanced minus Standard |
|---|---|---|---|
| Noon, three views | 10.1 to 12.3 | 9.5 to 10.8 | -0.4 to -1.5 |
| Low sun, partly cloudy | 11.1, 11.2 | 10.3, 9.2 | -0.8, -2.0 |
| Low sun, storm | 14.4 | 12.6 | -1.8 |
| Sunset and twilight, six views | 9.1 to 10.2 | 7.9 to 8.6 | -1.0 to -1.6 |
| Night | 9.3, 8.8 | 9.1, 8.3 | -0.2, -0.5 |
| Overcast | 11.2 | 10.3 | -0.9 |
| Rain, thunderstorm | 9.2 to 9.7 | 11.3 to 11.7 | +1.9 to +2.1 |

- On average Enhanced costs 0.6 ms less than Standard (median 1.0 ms less); only rain and storms cost more.
- On `gm_construct` with the flashlight on, Enhanced cost 2.4 to 5.5 ms less (see Mist and lamps).

### Standard is unchanged

Standard with this round's runtime against the published runtime, the judged scenes taken the same way:

- **Pictures:** 0.1 to 2.7 levels apart (of 255) in every view but the thunderstorm's two (7.4 and 10.0); two runs of
  one runtime differ by up to 53 there (lightning).
- **Frame time:** against the published runtime measured the same afternoon, the same way, the new runtime averaged
  0.57 ms less (from 2.3 ms less to 1.7 ms more over the 18 views); the noon views, measured again after the machine
  was quiet, 0.25 ms more on average. That is within what two runs of one runtime show. (Against the published
  runtime's run of 02:00 on a quiet machine it looked 1.5 ms slower: the afternoon's load, not the runtime.)
- **The PoC's sky setting:** one Standard run had shown the Enhanced sky, because the stalled runs had left Enhanced on
  in the PoC's settings and that run set none; it was repeated with Standard set explicitly.

### The rainbow check

A forced rainbow draws both bows (the primary red outside, the fainter secondary reversed) with the weather left to
Remix, with the companion's clear weather and with its partly cloudy weather (`judged/R2b/bow-check-chroma.jpg`). The
earlier forced scenes that drew nothing all used one look, whose near haze reaches 6 km: the bow most likely fails at
that range, which the sheet weathers (overcast, drizzle, rain, thunderstorm, snow) also use. A runtime bug for the next
round; after rain the weather turns to one with the 1 km range, where the bow shows.

### Storms with a lower exposure

Remix's exposure bias at -0.5, -1 and -1.5 stops makes the tuned thunderstorm gloomier, without more contrast
(`judged/R2b/storm-ev-*.jpg`). At -1 stop it reads as a dark storm day. A per-weather exposure is an option for the
next round.

### Other checks

- **Device objects left at exit:** 51, as in the published runtime; round 1's runtime left 52 (patch 0112).
- **Every option the scenes sent was accepted,** the new keys included.
- **The PoC's own state:** two capture runs stalled (once the game was likely paused by focus) and left their sky in
  the PoC's `garrysmod/cfg/client.vdf`, which another session then met. The field's file was not touched. Every
  capture run now writes that file back, the probe has a watchdog, and the PoC's sky settings were put back.

## Known problems

1. **Storms still read as overcast** looking away from the sun: auto-exposure lifts a dark deck to mid-grey.
2. **Rain streaks and snowflakes look dark** in Enhanced (round 1 too): the host's particles are not lit by the
   Enhanced sky.
3. **The map is cooler and bluer under Enhanced** than under Standard at noon (round 1 too).
4. **Lamp glow in the mist is faint**, and the flashlight's beam does not show in it.
5. **The rainbow seems to fail where the near haze reaches 6 km,** the range of the overcast, drizzle, rain,
   thunderstorm and snow weathers. After rain the weather turns to one with the 1 km range, where the bow shows.
6. **Hazy and smoggy** are closer than they should be from a distance.
7. **Still from round 1:** Enhanced has the library's own night (no Night sky editor layers, sun dogs, eclipse corona,
   shooting stars or sky without a horizon; the user wants ours brought to it later); the Low detail level was no
   cheaper than Medium; the six translations are agent-written.

## Not done in this round

- Rain shafts.
- Tests not run: the editor's save, load, paste and refusal in the game (offline tests only), VR's fall-back in a
  headset, a map with its own sky, multiplayer, a slower GPU, the field game (on Steam's main branch, where the loader
  does not start).

## The user's decisions (2026-11-26)

Asked after this report: merge and publish the Enhanced sky as an experimental choice (off by default), or a third
round first; and round 1's three open questions. The answers, and what followed:

1. "Merge both rounds and publish the Enhanced sky as the default choice, on by default, with Standard unchanged."
   Claude made Enhanced the companion's default, reworded the Sky page's help in the seven languages, and added a test
   that a new player's game starts in Enhanced and VR in Standard.
2. "Yes, please update the credit lines." The line the library's README asks for, "Sky and clouds: NUMOS by Kim2091
   (Sparkles)", is in the repository's README and the Remix menu's About panel (task M). The Workshop page stays as
   it is: the user has no item's page edited, since an edit sends the item to Steam's review.
3. The night: "Yes, and open this for later, we should adapt our own night sky with the enhanced night." Enhanced
   ships with the library's night; our night sky on Enhanced is an open item on the roadmap.
4. The menu: "yes please add and translate the NUMOS sky's remix men[u]." Task M (Codex, in the
   [plan](sky-enhanced-round2-plan.md)): the library's pages in the Remix menu, translated into the six languages.

## After the decisions: checks in the PoC

The new default and task M's menu, at 3840x2160 on `gm_flatgrass` (pictures in the main checkout's `out/sky2/judged/D1`
and `out/sky2/judged/M`):

- **Enhanced as the default** (run `D1-default` with the round's runtime, run `M1-sky` with patch 0114): with the
  saved sky quality left out of the PoC's settings for the run, the game started in Enhanced, and the Sky page showed
  it with its new help line; choosing Standard and then Enhanced switched as before. No Lua errors; the Remix log
  held its usual 29 lines (the game's shader-model messages, 51 device objects at exit).
- **The Remix menu.** Graphics Settings opened from the start (`RTX_GUI_DISPLAY_UI=1`) in English, Traditional
  Chinese and Russian, the language from an extra rtx.conf layer; the runtime logged 3,986 translated texts for each,
  and the first tab rendered cleanly in both scripts. Clicks posted to the game's window do not reach the fork's
  menu, which reads the real cursor. With real mouse input, sent only while the PoC game was the window in front and
  the cursor put back after each step, the Graphics tab showed the companion note and the Night, Haze and Cloud
  settings with live values for two minutes, in English, and the game quit normally.
- **Not seen in the game:** the new texts in the six other languages (the Traditional Chinese and Russian runs
  reached the first tab only, because the desktop's foreground went elsewhere and the clicks held off), the developer
  menu's Sky Tuning tabs and the weather preset window. Task M's unit tests cover their logic, and the catalogs and
  the DLL hold every text ([the task's report](sky-enhanced-M-report.md)).

## State of the branch

- `main` gets the round as one commit with the branch's final tree, so that only the runtime that ships goes into
  Git LFS: `d3d9.dll` 536,982,528 bytes, SHA-256 `36a44370...`, built from the fork's `ef15c09d4` with patches
  0001-0114. The branch `sky-enhanced` keeps the history locally, with round 1's and round 2's earlier runtimes.
- The fork branch `claude/sky-enhanced` in the live runtime worktree holds patches 0107-0114 as commits.
- Release gate: `tools\test.ps1 -Config Release` passed at `d75109c4`, the round with `main` and task M merged: the
  repository's conventions, the Release build, CTest 35 of 35, the Python suites (2,259, 29 and 26 tests; 4
  skipped). The first run had caught two sky scenarios that read a Standard option after the reset, which now
  lands on Enhanced; they were fixed and the sky suite passed 30 runs in a row.
