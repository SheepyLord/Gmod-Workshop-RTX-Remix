# enhanced_editor.lua

Creates the archived look controls and shared style settings for the [Enhanced sky editor](enhanced_editor_panel.lua.md).
The weather module supplies the library defaults, the twelve complete weather looks and the mode data. Each control
declares its library key, useful range, precision, label and help. The initial look is Partly cloudy. The
[control reference](../../../../docs/handover/sky-enhanced-E-report.md) lists all settings. Its E2 section updates
Haze density to 0–100 and adds **Lamp glow in mist** (`nativeloader_sky_style_aerial_perspective_local_lights`).
This archived style switch defaults off and controls `aerialPerspectiveLocalLights` across all detail levels.
Each detail level still supplies its lamp limits.

**Mist** is the first Light and mist control. The archived `nativeloader_sky_style_mist_strength` ranges
from 0 to 2 and defaults to 1. The Sky page uses the same setting. It scales the active weather or personal
look on output. Saved looks keep their original aerosol and visibility values. **Mist on the map**
(`nativeloader_sky_style_volumetrics`) stores 0 for Enhanced mist, 1 for Remix fog near you and 2 for Off.
The [controller](enhanced_sky.lua.md) maps these choices onto the runtime.

**Haze darkness** (`nativeloader_sky_look_mie_absorption`) sits after Haze density in Air. The slider runs from
0 to 3 in multiples of NUMOS's absorption. The convar and look hold the three equal coefficients per kilometre.
At 0.1 the coefficients are each 0.00044, at 1 they are 0.0044, and at 3 they are 0.0132.

The controller and UI share one editor instance. Changing a look setting selects **My own look**.
Loading validates the entire input before setting the convars and notifies the renderer once. Style controls
apply to every look and weather. Standard and VR can store edits for later.

Named looks use one compact JSON file at `data/nativeloader_companion/sky_looks/<name>.json`. The object
contains `version` (2) and `look` (all 46 weather keys). Numbers must be finite and within the editor range,
switches must be booleans, and colours must be arrays of three numbers in [0,1]. `mieAbsorption` is an array of
three equal numbers in [0,0.0132]. The reader supplies the library default for that one absent key in a version-1
look. Migration happens in memory. Missing required keys, duplicates, extra keys and invalid values reject the
entire look. The byte limit is 8192. The clipboard uses the same format and reader.

Names accept 1–32 ASCII letters, digits, hyphens and underscores. Files use lowercase names. Windows device
names are reserved. Before replacing a file the editor verifies a staged write and keeps the original until
the rename succeeds. On an interrupted replacement the next access recovers the original if the new file is
missing. A refusal names the file in the console. The UI reports the error in the selected language.

This client Lua include returns an editor factory. Operations return a result or an error for the page.
Its side effects are local convar changes and the player's requested look-file operations. No process exit code.
