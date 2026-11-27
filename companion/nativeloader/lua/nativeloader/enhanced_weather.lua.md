# enhanced_weather.lua

Round 2 adds the remaining editor fields to every weather at their library defaults. The returned `mode` table
holds shared settings and the High, Medium and Low detail settings, including the ray quality and lamp limits.
The lamps start off at all three levels. Night brightness starts at the ten stops measured in round 1.
The 6 km mist range stays in the sheet weathers and is editable as part of a look.
Every row inherits `mieAbsorption = {0.0044, 0.0044, 0.0044}` per kilometre unless it supplies its own
neutral absorption triplet. The sky suite runs the editor's validator on every weather and built-in look.

Holds the Enhanced sky's twelve weather tables. Edit the table for a particular weather at the end of
[the Lua file](enhanced_weather.lua). Each starts from a named NUMOS built-in preset. The shared values come from
`include/numos/settings_fields.inl` and `src/weather.cpp` at library revision `41842c6`.
The [Task C handover](../../../../docs/handover/sky-enhanced-C-report.md) gives the origin of the GMod values.

The module takes no arguments. It returns `presets`, indexed by the existing `nativeloader_weather` names,
and `defaults`, the library values used when releasing a weather. Keys are relative to `rtx.atmosphere.numos.`.
Cloud heights, thicknesses and fog visibility are metres. Wind is kilometres per second and bearings are degrees.
Visibility is the distance at which contrast falls to 2%. Zero clears the height fog.
For a newly mapped NUMOS key, include its library value in `defaults` so all twelve endpoints blend and the
setting can be released.

[enhanced_sky.lua](enhanced_sky.lua.md) reads the tables. The data module performs no I/O and has no exit code.
