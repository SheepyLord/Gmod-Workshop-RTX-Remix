# game_pbr_panel_harness.lua

Executes the marked imported-game PBR panel section of the packaged ToPBR driver under fake
GMod/native/Derma APIs. Verifies looked-at
character metadata, shared texture states, exact individual-map/native action arguments, no-map
and automatic actions without source metadata, menu registration and pictures only for drawn
materials. Usage: `luajit tools/tests/game_pbr_panel_harness.lua <cl_rtx_topbr_conversion.lua>`.
Also constructs the console editor at a 720p viewport with its scrolling form.
The fake DForm exposes `Clear`, matching the stock API, and deliberately lacks the spawn-menu-only
`ClearControls` method (the first real editor smoke found that compatibility error).
Known map-layout conflicts are rejected before native submission, including Windows case variants.
The cursor trace points elsewhere while the cursor-independent trace selects the character, guarding
against popup mouse position changing the material picker target.
R13-M: when the native view reports a refusal (state `error` with its one-line reason, such as a
free-disk-space limit), the selected material's status text shows that reason.

The user's report of 2026-11-16 (the page said nothing about a character whose PBR is a Remix mod, and its list went
blank): a fake `RemixMaterial.GetTextureHash` gives the two drawn materials a live hash and the unseen one none, and a
fake `AdvMat.RTX.Enhance.Lookup` (the Advanced Material Editor's index of `rtx-remix/mods`) names a pack's mod for the
first hash, with a normal and a roughness map and an emptied metallic input. Checked: `P.Effective` and `P.Describe`
give "Remix mod: pack_mod (normal, roughness)", game maps by family, "No PBR", "Not drawn yet", an editor profile
("values only") and the automatic layer as game maps; a row's label names its source, maps and hash; the summary
counts the groups ("1 × Remix mod: pack_mod", "2 × Game maps"); a picture (an `UnlitGeneric` of the material's base
texture) is made only for a drawn material and only once; with the page still built, a removed character empties the
list and says so, "List looked-at character" with the eyes on no character keeps what is shown, and a character
spawned later fills the page.

Reads its input; no filesystem writes, game or network. Exit 0 on success, nonzero on assertion.
