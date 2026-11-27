# Task M — the translated Enhanced sky menu

Runtime patch [0114](../../runtime/patches/0114-Add-the-translated-NUMOS-controls-to-the-Remix-menus.patch) adds the NUMOS controls to Alt+X in English, Simplified Chinese, Traditional Chinese, Japanese, Korean, French and Russian. Fork commit `ef15c09d4` on `claude/sky-enhanced` builds on the stored runtime at `bd3cb3226`. The Release install finished **2026-11-27 01:00:11 UTC**. The DLL is staged in the runtime worktree's `_output/`. The packaged runtime is still at 0113.

## First checks in the PoC

1. Open **Alt+X → developer menu → Game Setup → Step 2: Parameter Tuning → Sky Tuning**. In English, choose **Enhanced** on the single Sky Mode control. Switch to Traditional Chinese. Open **Sky → Sun rays**, **Clouds → Cirrus**, then **Setup → All settings**. Search for `moon2.phase` and hover the result. Check the translated label and help, the exact option key, the numeric values and the four separate moon slots when the filter is cleared.
2. Open **Weather → Weather presets**. Select Storm with **Follow game weather** off. Affected settings should show the current preset's values and a weather tag. Switch to **Custom settings**, wait for the transition, move a cloud or ray control, then change look on the companion's Enhanced sky editor. Verify both changes reach the rendered sky. Switch back to Standard with the preset window open. The window and the six Enhanced tabs should close. A VR session with Enhanced selected should show the Standard controls and the VR note.
3. Open **Alt+X → Graphics Settings → Graphics**. Check Night, Haze and Cloud settings, including the three mist choices. Switch through Simplified Chinese, Japanese and Korean for the glyphs, then French and Russian for long labels, help wrapping and tab scrolling. Check About → Credits for the sky credit and contributor. Use `rtx.gui.logUntranslatedText` to catch a missed text on a path the reviewer opens.

## Pages and controls

The developer pages draw only when the device's effective sky mode is 2. The combo still offers the game sky (Skybox Rasterization), Standard and Enhanced. A note in both menus and the preset window identifies the companion's **Sky and weather** and **Enhanced sky editor** pages. A map start or a change of weather or look can apply those values again.

| Developer tab | Controls |
|---|---|
| Sky | Sun position, size and shadows, day/night cycle, dust, atmosphere and colour. Sun rays has enable, strength, quality, range, step override, history weight and the four diagnostic views. |
| Clouds | Cloud decks and cirrus, shape, lighting, ground shadows, wind, motion vectors, reconstruction and quality. |
| Haze | Distance haze and its scale, ground fog, sun shadows, local lights, froxel quality and the three Enhanced/Remix mist policies. |
| Night | Night gain, stars, moonlight, lunar disc, Earth's Moon and the four independent game moons. |
| Weather | Current preset, the built-in selector, lightning rate/colour and test strike, and the rainbow's strength, distance and depth. |
| Setup | World and haze scale, ground measurement, Set to Here, camera override, world-change counter, diagnostics and searchable All settings. |

The developer preset window offers Clear, Fair, PartlyCloudy, Cloudy, Overcast, Haze, Fog, Storm, Drizzle, Altostratus and Cirrus. The menu translates their display names. Custom settings clears the manual preset. Follow game weather, transition time, incoming and outgoing weather and game blend operate on the existing `rtx.atmosphere.numos.weather.*` options. The player-facing Graphics tab groups night, star and moon brightness, haze and fog, cloud coverage, density, type, shadows, quality and resolution.

The About panel adds `'softsoundd'` to the integration contributors. Under the localized **Sky and clouds** heading it credits **NUMOS by Kim2091 (Sparkles)**. The author's name stays literal in all seven languages.

## Integration and omissions

The native pages adapt the MIT integration at `1532c782` and retain its copyright headers. Setup covers all 221 registered fields at library pin `41842c6`. Its 203 label/help entries include six shared by all four moons. The widgets display short menu-specific help and the full option key. The reference in `RtxOptions.md` keeps the library's full descriptions and bounds. The graphics tooltip for Haze World Scale explains that lowering the scale increases the haze at a fixed game distance.

Menu edits resolve on the same in-memory option layer as `SetConfigVariable`. A later companion write takes effect there too. While an Enhanced page is open, the UI requests a copy of resolved weather, ground and diagnostic values from the render thread. A weather-owned field shows its current effective value. These changes add no shader or library modifications.

ADR 0267 keeps preset management out of the game folder. The port omits the preset-file list and folder opener, file creation, duplication, renaming and deletion, save/save-as/save-all, reload/import/export, saved tuning and weather bindings, seed generation, randomization, seed clipboard tools and the `.numos-presets-written` marker. Built-in selection and transitions run in memory. The integration's **Use NUMOS Haze** action is replaced by the fork's mist selector so the player can choose the fog policy directly.

## Catalog checks

Python wrote the catalogs as UTF-8. Regeneration added 539 active English texts and retired five previous texts. This also picked up previously unextracted lines from the existing particle mask, dissolve and visible-set controls. Each language's glossary now includes the new sky terms.

`update_strings.py --check` exited 0. The release catalog and test commands ran from the runtime root.

```powershell
python i18n/tools/update_strings.py --check
python i18n/tools/embed.py --pot i18n/remix.pot --latin-font external/fonts/NVIDIASans/NVIDIASansMd.ttf --fonts-dir i18n/fonts --out "$taskLogs/rtx_i18n_check.cpp" i18n/zh-CN.po i18n/zh-TW.po i18n/ja.po i18n/ko.po i18n/fr.po i18n/ru.po
python -m unittest discover -s i18n/tools -p test_embed.py
```

```text
i18n: 3986 messages; translated: zh-CN 3986/3986, zh-TW 3986/3986, ja 3986/3986, ko 3986/3986, fr 3986/3986, ru 3986/3986
Ran 5 tests
OK
```

The font and printf checks passed. The bundled Traditional Chinese font lacks 閾 (U+95BE), 恒 (U+6052) and 墻 (U+58BB). The translations use 臨界值, 恆星 and 牆. The existing fonts cover the final text. A strict UTF-8 check found zero replacement characters or extra question marks across all six active catalogs. Non-ASCII characters as a share of the new text were **85.7% zh-CN, 85.8% zh-TW, 89.4% ja, 68.0% ko, 3.2% fr and 82.6% ru**. Traditional Chinese uses Taiwan terminology, with a character-conversion pass for newly written Chinese text and corrections against the glossary and installed font.

Every new explicit numeric example, unit symbol and option key was checked against the English. An independent scan found each entire encoded language table, including indexes and printf safety flags, in the installed DLL. The 3,234 new translations are present in the binary.

## Build and evidence

In the following commands, `$buildScript` is `runtime/build_runtime.ps1` in this worktree, `$fork` is the fork checkout, `$runtimeTree` is the prepared runtime worktree, and `$taskLogs` is `out/task-m` in this worktree. The Meson commands run from the runtime tree in the x64 build environment.

```powershell
& $buildScript -Fork $fork -Worktree $runtimeTree -NoImport -Install -Jobs 6
python -m mesonbuild.mesonmain install -C _CompRelease_x64 --tags unit --no-rebuild --quiet
python -m mesonbuild.mesonmain test -C _CompRelease_x64 --suite dxvk --no-rebuild
& $buildScript -Fork $fork -Worktree $runtimeTree -Verify
```

```text
d3d9.dll 536982528 bytes, SHA-256 36a443703351a9d1ec9cfa7946ecdd8bc6e9dd71a649e0a3ff158467d19cfb7a
Ok:                81
Fail:              0
```

The unit suite ended **2026-11-27 01:00:52 UTC**. The sky unit case checks metadata coverage, layer ownership and the sequence of companion write → menu edit → new companion look across frame resolution. The verifier reconstructed all 110 patch files through 0114 and matched tree `8550f658102c965bc9d567feba33d2691e843593`, two submodule settings and three pinned clones. The build, unit-test and installed DLLs matched. All 55 staged NUMOS files matched the pinned data or built shaders.

The fork touchpoint audit ran before and after the commit. The SHA-256 of 0114 is `a63c2e48ef75658521a547beed220d4c4ed3ee9f7fdce69f204c514a430b4bef`. The aggregate repository check, run as `python tools/check_repo.py`, returned `repo conventions OK`. Logs and checks are under `out/task-m/`. The reviewer owns in-game appearance, interaction and packaging. Task M ran no game.
