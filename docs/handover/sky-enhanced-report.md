# The Enhanced sky, round 1: report

For the user's decision. The round is on the branch `sky-enhanced`: nothing is merged, pushed or published.

The user asked on 2026-11-25 for an improved sky, cloud and sun-ray system that players can switch to, with today's
sky kept as the default. This round delivers that switch. The Enhanced sky runs in the PoC through the player's own
setting, and today's sky is unchanged. Three parts of the request are not there yet: rays through cloud gaps, rain
shafts and a rainbow. Lamp glow in the Enhanced haze does not work yet either.

- Decision record: [ADR 0267](../decisions/0267-the-enhanced-sky-is-the-numos-library-as-a-second-sky.md) (proposed).
- Plan and briefs: [sky-enhanced-plan.md](sky-enhanced-plan.md).
- Task reports: [runtime](sky-enhanced-R-report.md), [companion](sky-enhanced-C-report.md),
  [package](sky-enhanced-P-report.md).

## Who did what

- **Research** (Claude, in forks): today's sky, the techniques, and the library. The notes are scratch, in the main
  checkout's `out/sky2`.
- **Code** (Codex agents, GPT 6.2 Astra at maximum effort, as the user asked):
  - R: the runtime port;
  - C: the companion's switch and mapping;
  - P: the package.
- **Review, every test in the game, and the weather tuning** (Claude).

## What is on the branch

| Part | What |
|---|---|
| Runtime patch 0107 | The Windows install helpers keep a `!` in a path. They dropped it, which stopped the tagged install in this checkout |
| Runtime patch 0108 | The library as sky mode 2: its adapter ported from its own integration commit, both skies' shader names kept apart by a build step, 230 options under `rtx.atmosphere.numos.`, no menu pages, no files written into the game folder, Standard in VR |
| The library | `Kim2091/numos-sky` (Apache-2.0), pinned at `41842c69` and unmodified, a clone recorded in `runtime/base.json` |
| The companion | "Sky quality: Standard / Enhanced" and a detail level on the Sky page (`nativeloader_sky_enhanced`, `nativeloader_sky_enhanced_quality`), eight new texts in six languages, and the mapping of the page's weathers, clock, Moon, wind and fog onto the library (`enhanced_sky.lua`, `enhanced_weather.lua`) |
| The package | The stored runtime (`d3d9.dll` 532,803,072 bytes, SHA-256 `d8b30bd8...`), and 55 library files beside it in `numos/`: 41 compiled passes, the night sky data with its credits, the licence and notices. 44.15 MiB larger than the published package |
| The package workflow | Its inputs fetch the library at its pin and collect `numos/`. It was not started |

## Tests in the PoC

At 3840x2160, DLSS Performance (1920x1080 rendered), frame generation off, RTX 5090. The pictures and logs are
scratch, in the main checkout's `out/sky2`. Other sessions were working on the machine, and no frame time was
repeated, so differences of a few tenths of a millisecond are within what one run can show.

### Standard is unchanged

On `gm_flatgrass`. Run S is the new runtime and the new companion with the setting at Standard. Its control, B2, is
the published package deployed the same fresh way.

| Compared | Frame time | Picture difference (of 255) |
|---|---|---|
| S against B2 | mean -0.20 ms (-0.65 to +0.22) | noon, night, overcast 0.08-0.15; low sun 0.8-0.9; sunset 1.8-3.3 |
| B2 against the first baseline (the same runtime twice) | mean -0.61 ms | noon 0.1-0.3; low sun 0.2-0.4; sunset 1.7-2.7 |

- The sky is the same, and nothing is slower.
- **Not settled:** the low-sun views differ a little more than two published runs do. The clouds sit a fraction
  apart; the look is the same. The cause was not found.

### Enhanced, through the player's setting

On `gm_flatgrass`, with `nativeloader_sky_enhanced 1`, and the weather and the time set through the companion as in
the baseline. The detail level was High (the loader's tier on this computer).

| Run | What |
|---|---|
| E | The first weather table. By day it ran in all 18 views without a crash and without a black or doubled sky. The night was black, and rain and thunderstorm were a flat grey |
| E2 | The first tuning, through the package built from the branch. The loader deployed `numos` itself |
| E3 | The second tuning. The storm's ring is gone |

What E3 shows, against the baseline:

- **Fair-weather noon:** dense, rounded cumulus with grey bases and layers toward the horizon, with thin cirrus
  streaks behind. Today's clouds are thin and flat.
- **A low sun:** the sun behind thick cloud with bright edges, and clouds lit from the side.
- **Sunset and twilight:** pink cirrus over mauve cumulus at -2 degrees, where today's sky has grey clouds. At +2
  the look is pastel, with the sun behind the cloud bank. Twilight at -6 is as bright as Standard's.
- **Night:** moonlit cumulus on dark blue, the Moon's glow behind cloud, and faint stars.
- **Rain at 14:00:** the storm's clouds show through the rain.

What is still wrong in E3:

- **No rays through cloud gaps,** at any haze range and with three times the aerosol. The library draws the clouds'
  shadow only in its near haze.
- **Storms are flat.** The thunderstorm is an even grey with one bright break, and the low-sun storm toward the sun
  is a pale wall with no dark underside and no glow at the sun. It reads as steady rain.
- **The nearest noon cloud** is a smooth mass with little fine detail.
- **At night** the cloud beside the Moon has hard-edged dark holes, and there is no Milky Way picture as Standard
  has.

### Cost on `gm_flatgrass`

E3 against run S, over the 18 views: 0.72 ms more on average.

| Views | S (ms) | E3 (ms) | Difference |
|---|---|---|---|
| Noon, three views | 8.0 to 9.8 | 8.4 to 11.2 | +0.2 to +1.4 |
| Low sun, fair and storm | 7.9 to 10.1 | 8.3 to 10.7 | +0.4 to +0.7 |
| Sunset at +2 degrees | 9.4, 9.5 | 8.2, 8.8 | -1.2, -0.8 |
| Sunset at -2, twilight at -6 | 7.7 to 8.3 | 8.2 to 9.0 | +0.2 to +0.9 |
| Night | 8.0, 8.3 | 8.3, 9.5 | +0.4, +1.2 |
| Overcast | 10.1 | 9.9 | -0.1 |
| Rain, thunderstorm | 8.1 to 8.7 | 10.6 to 11.2 | +2.1 to +2.5 |

Nothing was measured on a slower GPU.

### Cost on a real map: lamps in the haze

On `gm_construct`, with the first tuning, Enhanced cost 19.6 to 27.4 ms a frame where Standard cost 10.0 to 11.7:
13.4 ms more on average over ten views. A breakdown of one noon view found the part:

| Setting | Frame time (ms) |
|---|---|
| Enhanced, everything on | 25.33 |
| Local lights in the near haze off (`aerialPerspectiveLocalLights`) | 10.25 |
| The haze's scene shadow off (`aerialPerspectiveSceneShadow`) | 25.41 |
| The near haze off (`aerialPerspective`) | 9.82 |
| Standard | 11.02 |

- **The library's local lights in the near haze cost about 15 ms.**
- **The third tuning turns them off** in every Enhanced weather.
- **The scene shadow costs nothing and stays on:** without it a white veil washes the map out.

A confirming run with the third tuning, through the player's setting: ten views in one launch from one camera place,
without the flashlight, in Standard, in Enhanced, and in Enhanced with the lights forced back on.

| Views | Standard (ms) | Enhanced (ms) | Lights forced on (ms) |
|---|---|---|---|
| Noon, four views | 11.1 to 12.8 | 10.4 to 10.8 | 23.0 to 28.2 |
| Hazy, two views | 9.9, 11.4 | 9.8, 10.7 | 27.7, 24.3 |
| Night in fog, two views | 11.0, 12.3 | 12.1, 11.5 | 29.9, 25.1 |
| Fair night, two views | 11.6, 10.5 | 11.1, 10.9 | 28.7, 28.9 |

- **Enhanced now costs 0.5 ms less than Standard on average** on this map (from 1.95 ms less to 1.07 ms more).
- **The lights cost 16 ms a view on average.**
- **What the lights drew:** in dense fog at night, a ceiling lamp's soft cone in a lit room and a faint glow at a
  doorway. In the other eight views the pictures match with and without them. Standard shows a soft haze in that
  room. An earlier run in this round, with the flashlight on, showed no beam in the Enhanced fog.
- **The look on the map:** at noon the clouds sit behind the towers and the light is natural, but the ground is bluer
  than in Standard. In haze the scene is cold: teal grass and blue-grey towers, where Standard is warm beige.

### The twelve weathers

At noon on `gm_flatgrass`, with the first tuning.

- **Look right:** clear, partly cloudy, overcast, drizzle, rain.
- **Hazy and smoggy look wrong:** an even grey-beige wall with no blue overhead and no glow round the sun. They read
  as fog and look alike. The hazy view also has a dark block with a hard vertical edge on the horizon.
- **Snow and blizzard:** the flakes are dark specks against the sky.
- **Foggy, blizzard and sandstorm** are flat walls, which suits them. Foggy and blizzard are the dearest weathers, at
  13.0 to 13.4 ms.

### Detail levels

| View | High | Medium | Low | Standard |
|---|---|---|---|---|
| Noon at 30 degrees (ms) | 8.77 | 6.37 | 6.94 | 8.02 |
| Low sun, toward the sun (ms) | 8.83 | 7.08 | 7.56 | 8.10 |

- Medium saves about 2 ms and is cheaper than Standard.
- Low measured slower than Medium in both views. As measured it buys nothing; the cause was not found.
- Still pictures look the same at all three levels. Motion was not judged.

### The switch

Standard, then Enhanced, then Standard, at one view. The Standard sky came back with its clouds, sun disc, building
shadow and ground glint. No haze stayed (ground view level 113.8 before, 113.3 after), and the frame time returned to
8.2-8.4 ms.

### The haze's range

The library's near haze ends at 1 km by default.

| View | 1 km | 6 km | 20 km |
|---|---|---|---|
| Thunderstorm, straight up | A pale ring 35-40 degrees round the zenith | No ring; clouds and the sun's glow | No ring, but a flat blue-purple |
| Thunderstorm, sunside | Grey, faint cloud | Storm clouds and the sun's bright spot | Flat blue-purple haze |
| Low sun, partly cloudy, toward the sun | No rays | No rays | No rays |

- **The ring** is where the range ends against the storm sheet's base at 800 m.
- **The fix in the table:** the weathers built on that sheet (overcast, drizzle, rain, thunderstorm, snow) set 6 km.
  In the judged views that cost nothing measurable; straight up it cost up to 0.9 ms.
- **Not tested:** what 6 km does to nearby shafts, since the same 96 slices spread six times as far.

### Logs

- No error or warning names the library in any launch, and no option was refused.
- At exit the runtime reports 52 device objects not disposed of, against 51 in the published runtime.

## The weather tuning

The companion's first table reused the Standard sky's fog distances. The library's fog is physical and hides the sky,
so 400 m in a storm showed a flat grey. Three tuning passes changed values only, in `enhanced_weather.lua`:

1. Ten stops of night gain in every weather (six was still dark, thirteen looked like day), and visibilities in
   kilometres for rain, storms, snow, smog and haze.
2. The 6 km haze range for the sheet weathers, and a thinner cirrus in partly cloudy.
3. Local lights in the near haze off.

## Not done in this round

- **Rays through cloud gaps.** They need a sky ray pass of ours on the library's cloud shadow map, which reaches the
  horizon.
- **Rain shafts and a rainbow.** The library has neither.
- **Lamp glow in fog.** With the library's haze in place of Remix volumetrics, and its local lights off for their
  cost, a lamp shows no cone or glow in Enhanced fog.
- **Our night features in Enhanced:** the night sky editor, sun dogs and arcs, the solar eclipse's corona, shooting
  stars, and the sky without a horizon.
- **Tests not run:** VR's fall-back in a headset, a map with its own sky, a multiplayer server, a slower GPU, and
  drizzle and snow with the second tuning.
- **The six translations** of the eight new texts are agent-written.

## Known problems to fix before a release

1. **Lamps in the haze** cost 16 ms a frame for a lamp's cone in dense fog. Find out why they cost that much, and
   why the flashlight drew no beam, before they are turned on again.
2. **Hazy and smoggy** read as fog, and hazy has a dark block on the horizon.
3. **Storms are flat,** and the near noon cloud is smooth.
4. **The ground is bluer** than in Standard, and haze scenes are cold.
5. **Volumetrics are restored from what Lua can read.** The companion turns Remix volumetrics off in Enhanced and
   puts back the value it recorded. It cannot read a value changed only in the Remix menu. The clean fix is in the
   runtime: suspend Remix volumetrics while mode 2 is active, with no option change.
6. **The night gain and the lamps' switch are sent with the weather.** They belong with the mode, so they also
   apply when the weather is left to Remix.
7. **The Low detail level** is no cheaper than Medium.
8. **One more device object is left at exit** than before.

## State of the branch

- `sky-enhanced` holds the plan, the three tasks, three tuning commits, the decision record and this report.
- The fork branch `claude/sky-enhanced` holds the runtime commits `f57c9e4f0` and `1370af0d2`, in the live runtime
  worktree.
- The stored runtime is one Git LFS object (78.8 MB), local only.
- The Release gate (`tools\test.ps1 -Config Release`) passed on the merged branch at `8c178a0a`: the conventions,
  CTest 35 of 35, and the Python suites, 2,249 tools tests among them. Only this line was written after it.
- Nothing was pushed, and the Workshop item is unchanged.
