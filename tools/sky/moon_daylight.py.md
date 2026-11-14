# moon_daylight.py

The Moon against the day sky, computed offline from the runtime's own formulas
([ADR 0207](../../docs/decisions/0207-the-moon-by-day.md), runtime patch 0090). It is where the decision's
numbers come from: how bright the sky is where the Moon stands, how bright the drawn Moon is, and so how the
Moon shows once its light is added to the sky in front of it.

```powershell
python -I tools\sky\moon_daylight.py
python -I tools\sky\moon_daylight.py --weather clear --season winter --hours 9,12,15
python -I tools\sky\moon_daylight.py --brightness 2 --lowest-sun -6 --json out\moon\table.json
```

What it rebuilds, in numpy (no GPU, no game):

- **The sky.** The transmittance LUT (`transmittance_lut.comp.slang`, 512 x 128, 40 power-distributed steps) and
  the multiple-scattering LUT (`multiscattering_lut.comp.slang`, 32 x 32, 64 directions of 20 steps, the ground's
  bounce), each read bilinearly through the runtime's texel mapping, then `evalAtmosphereRadiance`'s 32-step march
  from the ground (`atmosphere_common.slangh`, the sky-view LUT's bake) with the air, aerosol, phase and sun of a
  weather preset (`clear`, `partlyCloudy`, the companion's default, or `hazy`), and R18's twilight fade.
- **The Moon.** Moon 0 as `evalTexturedMoon` lights it: the sun's illuminance through the Kasten-Young air mass
  towards the Moon (`getAtmosphericTransmittanceForDir`), times brightness / pi, the near side's mean albedo (0.12),
  and the Lunar-Lambert term with earthshine, averaged over a smooth sphere's disc and over its lit part. The day's
  scale is `rtx_moon_daylight.h`'s (the real Moon's phase law over the drawn one's, held from 150 degrees), handed
  over to the night's look as `evalSkyRadiance` does.
- **Where they stand.** The sun and the Moon as the companion's sky model puts them
  ([`sky_model.lua`](../../companion/nativeloader/lua/nativeloader/sky_model.lua.md)): latitude 40, a season's day,
  the Moon `phase` of a turn east of the sun along the ecliptic and 5.64 degrees off it (no eclipse).

Output: for each time (`--hours`) and phase (crescent, quarter, gibbous, full, waxing and waning) with the sun at least
`--lowest-sun` degrees high (default 0) and the Moon at least 1 degree up: the sun's and the Moon's heights and their
angle apart, the sky's luminance where the Moon stands, the drawn Moon's mean luminance over its lit part, the scale on
it now, and three contrasts (the lit part over the sky around it): **shown** (with the scale, as the runtime draws it
after patch 0090), **night** (the night's look, unscaled, as the day would have shown it without the phase law) and
**real** (a real Moon of the same full brightness, by Allen's phase law). Luminances are Rec. 709 Y in the runtime's
units (the preset's sun illuminance, 19 or 20). `--json` also writes the rows. `--brightness` is
`rtx.atmosphere.daytimeMoonBrightness` (the companion's Moon by day). `--ground-row 0` puts the multiple-scattering LUT's
bottom row on the ground as the runtime does (see [RESEARCH.md](../../docs/RESEARCH.md), "The Moon by day"): that row
then holds nothing, and the sky comes out about 10 % darker; the default lifts it 1 m, as the physics intends.

Inputs: none but the arguments. Side effects: only `--json`'s file. Takes about 2 s. Exit codes: 0, or 2 for a bad
argument. Tested by [`test_moon_daylight.py`](../tests/test_moon_daylight.py.md).
