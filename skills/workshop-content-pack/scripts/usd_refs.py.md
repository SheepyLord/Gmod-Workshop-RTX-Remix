# usd_refs.py

A module, not a command: which files a Remix mod's USD layers reference, read without `pxr`.
[check_pack.py](check_pack.py.md) and [port_classic_mods.py](port_classic_mods.py.md) import it.

| Function | Does |
|---|---|
| `walk(mod, root="mod.usda")` | follows every layer reached from `mod.usda`: sub-layers, references and payloads to `.usd`, `.usda` and `.usdc` files, nested to any depth. Returns a `Walk`: `layers` (mod.usda first), `crate` (the binary ones among them), `files` (each referenced non-layer file and the layers naming it), `missing`, `outside` (leaves the mod), `bare` (neither `./`, `../` nor a shader name), `shaders` (bare `.mdl` names: Remix resolves them itself; a shader file beside the layer that names it counts as used, as USD anchors a bare name there first), `errors` (an unreadable layer); `used()` is every layer and file, lower case |
| `layer_references(path)` | the asset paths one layer names, in file order, without repeats |
| `text_references(text)` | `(start, end, path)` of each `@...@` and `@@@...@@@` in a `.usda` text, skipping strings and comments; `@@` is the empty asset (Remix: "no texture") and is not a reference |
| `blank_missing(text, layer_dir)` | the text with every relative file reference that resolves to nothing set to `@@`, and the list of those paths; references to layers and bare shader names are left alone |
| `crate_tokens(path)` | the token table of a binary crate layer (`PXR-USDC`, version 0.4.0 or later) |
| `lz4_block`, `fast_decompress` | the decoders `crate_tokens` uses: a raw LZ4 block, and USD's `TfFastCompression` (a chunk-count byte, then one block or that many size-prefixed blocks) |
| `mod_files(mod)` | every file in a mod folder, relative with `/` |

**Why a crate reader.** A map mod made in the RTX Remix Toolkit can hold binary `.usd` layers: the Safehouse
mod's 13 photoscanned furniture models (`ambientmodels/*.usd`) reference their own albedo maps in
`ambientmodels/SubUSDs/textures/`, which no text layer names. A crate stores every asset path, sub-layer
path and reference path as a token, so the token table lists them all. Tokens that end in a Remix data or
layer extension are taken as references. The table is LZ4-compressed; this module decodes it in Python
(the standard library has no LZ4). On the Safehouse mod it read all 16 layers in 0.4 s.

**Why not a regular expression.** `@([^@]+)@` (what `check_pack.py` used before) runs from the second `@`
of an empty asset `@@` across lines to the next `@`, so a layer written by the Remix Toolkit, whose
attributes carry `customData = { asset default = @@ }`, gave nonsense references.

Standard library only; runs under `python -I` (the importing script puts its own folder on `sys.path`).
No side effects. Tests: [test_port_classic_mods.py](test_port_classic_mods.py.md).

## Provenance

Written by Claude for this user on 2026-11-12, while porting the classic install's Poolday and SafeHouse
mods. The crate layout (header, table of contents, `TOKENS` section) and `TfFastCompression`'s framing
follow OpenUSD's documented file format; no OpenUSD code is copied. Not third-party code.
