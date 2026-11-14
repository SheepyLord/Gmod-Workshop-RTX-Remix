# GitHub issue 1 (Source eyes) and the PBR note: report (2026-11-14)

The user's request of 2026-11-14, after the runtime update: "Then address these: 1. Fix issue #1. 2. The PBR materials
for maps menu does not work. Change title to "Obtaining more PBR resources" Remove the maps without PBR button. Replace
it with the Hide button. Change it with just 1 line of text as summary. Make it hide automatically after 10 seconds. Add
a button to hide it forever." Done by Claude on the branch `issue1-pbr-note`; package only (the fixes part's module and
Lua, the runtime part's defaults layer, the companion), no loader (`winmm.dll`) change, no runtime rebuild.

## Issue 1: "VMT shaders such as $Iris, $color are ignored in render time"

[ADR 0220](../decisions/0220-source-eyes-show-their-irises.md). The reporter: no `$iris` on any model with movable eyes;
`$color` and `$selfillum` looked ignored ("a slight faint outline" where the iris is); a skin change did not apply.

**Root cause of the missing irises (two faults):**

1. **The runtime's eye shading was off.** Each Source eye already reached the runtime as an eye: the fixes'
   fixed-function `Eyes_dx9`/`EyeRefract_ff` ports tag the iris projection on stage 1 and the runtime logs
   `[GMod Eye] Handoff` (with `rtx.gmod.enableInstrumentation`). But `rtx.eye.enable` defaults to `False`, the classic
   install never set it, and so `DrawCallState::isEye()` was false and every eye drew as a plain sclera.
2. **The first EyeRefract eye of a model lost its TexGen.** With the shading on, a model whose eyes are its first meshes
   (GTA 5 Improved Models' Franklin, Workshop 3567271959) kept one white eye: only the second eye drawn ever reached the
   runtime (32 of 32 handoffs at its origin), the same mesh whichever material it had. Source's shader API commits its
   cached texture stage state between the shader's `RTX_SetEyeTexGenState(1)` and the draw, and the helper writes the
   device behind that cache.

**The fix:** the package's Remix defaults pin `rtx.eye.enable = True` (`tools/remix_defaults.py`, `EYES`), and the RTX
fixes' thirteenth native patch, [eye-texgen](../../packages/fixes/licenses/oversized-skinning/eye-texgen/README.md),
writes the eye's stage 1 TexGen again at the top of the module's `DrawIndexedPrimitive` hook while the shader's request
stands (`EyeTexGen::Request`, per thread).

**The issue's other points, checked in the PoC:**

- `$color`: a render colour (`Entity:SetColor`) and a model material's `$color2` tint models under RTX (a red oil drum
  both ways; values above 1 are capped since [ADR 0190](../decisions/0190-material-colours-above-1-capped-for-remix.md),
  two days after the report). A model VMT's `$color` does nothing without RTX either: studiorender writes the render
  colour into it at each draw.
- Skins: a pop can's skins 0 and 1 (blue, red) and a Combine soldier's change under RTX. Not reproduced; the reporter's
  model would be needed.
- `$selfillum`: glows only with the RTX fixes' Legacy Emissive categorization (Utilities > RTX Remix), which the classic
  defaults leave off (`rtx_auto_categorize_emissive 0`); with it on, the Combine console's screen and lights glow at
  night. Left off: it also makes every unlit material of every map glow, the user's call.

## The PBR note

[ADR 0219](../decisions/0219-the-pbr-note-one-line-three-buttons-ten-seconds.md), superseding ADR 0217's card and text.
"Open the collection" asked Steam's overlay first (`steamworks.ViewFile`), which shows nothing where the overlay is off
and reports no failure, so `gui.OpenURL` was never tried. Now: the title "Obtaining more PBR resources", one line, and
Open the collection (`gui.OpenURL` first), Hide (this start), Don't show again (for good); it hides itself after ten
seconds on screen, counted while the pointer is not over it. Three new messages in the six languages.

## Verified

- **Offline** (`tools\test.ps1 -Config Release` with `NL_FIXES_CLONE`): `test_eye_texgen.py` (the patch's files, the
  hook's order, the shipped layer, the SDK-free regression: 19 checks), `test_remix_defaults.py` (the pinned value),
  `test_pbr_note.py` (thirteen scenarios of the real script in a mocked menu realm), the companion's catalogs complete
  (703 of 703 in each language), `test_ci_tools.py`'s replay of the thirteen patches against the recorded tree.
- **Module build**: `build_modules.ps1 -Only fixes` with the local fixes clone, garrysmod_common `a854f23` and premake
  5.0.0-beta2: 5,598,208 bytes, SHA-256 `172e0dd6...926ba34c`; the patched tree `daa6870d...` matched.
- **PoC** (`poc_session.py`, gm_construct, 1280x720; evidence `out/qa-poc/issue1-eyes` for the diagnosis and
  `out/qa-poc/issue1-final` with the package built from the branch, 0.0.0-dev.20261114211841+5040d905):
  - `06-eye-compare` (before the fix): eight HL2 characters with the shading off and on; on, all show irises.
  - `08-issue1-rest`: Franklin with one white eye; anime models (Flandre, Tsukushi Aria) unchanged; skins; colours.
  - `09`-`12`: the diagnosis (the handoff log at one origin; the eye-route log; material experiments).
  - `issue1-final/01-eyes`: the citizen, Alyx, Barney and Kleiner show irises by default; Franklin both irises (two
    origins in the handoff log); Flandre unchanged; normal quit.
  - `issue1-final/02-menu`: the note on the main menu with its one line and three buttons (the menu re-shown with
    `nativeloader_pbr_note` while the Workshop mounted; `menu.png`).
  - `issue1-final/03-selfillum`: Legacy Emissive on before first draw; the switch put back to 0 before quitting.

Not covered: the field install; the note's Open the collection in the user's own game with the Steam overlay; VR.

## Open

- Legacy Emissive by default (for `$selfillum`): the user's decision.
- A reply on GitHub issue 1: drafted for the user, not posted.
