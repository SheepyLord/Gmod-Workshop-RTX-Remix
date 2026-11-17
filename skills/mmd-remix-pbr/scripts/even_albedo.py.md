# even_albedo.py

Evens out the colour blocks a character's sheet paints on separate UV islands, for rpai's per-texture
`albedo_source` (the tool README, "Recoloured albedo"). Made for Linlong's hair (2026-11-16): her two hair
sheets paint cream, pink and orange-brown blocks on separate islands, which meet with hard edges on the mesh
wherever the hair twists or lies in clumps. A plain red test albedo removed every block in game, so they are
the texture's and not the lighting's.

## Usage

```powershell
$py = "$env:USERPROFILE\.rpai\venv\Scripts\python.exe"
& $py scripts\even_albedo.py --sheet "<folder>\hair1.png" --sheet "<folder>\hair2.png" --out-dir "$env:USERPROFILE\.rpai\work\<key>\game"
```

Then point the sheets at the copies in the per-model preset:
`"textures": {"hair1.png": {"albedo_source": "%USERPROFILE%\\.rpai\\work\\<key>\\game\\hair1_even.png"}}`.

| Option | Default | Meaning |
|---|---|---|
| `--sheet` | (required, repeatable) | a sheet to even; sheets given together share one main tone |
| `--out-dir` | (required) | where `<stem>_even.png` and `even_preview.jpg` go |
| `--sigma` | 28 | the blur radius in texels that separates detail from broad colour: wider than a strand, narrower than an island |
| `--keep-colour` | 0.35 | the share of the fine a*/b* detail kept (0 = one hue everywhere) |
| `--keep-shading` | 0.15 | the share of the broad lightness variation kept |
| `--tone` | measured | the main tone as `L,a,b`; measured as the median of the sheets' bright (above the median L*), low-chroma (below the 60th percentile) texels |

## What it does

In CIELAB, per sheet: lightness = main tone + (sheet − blur(sheet)) + keep-shading × (blur − main tone);
a* and b* = main tone + keep-colour × (sheet − blur(sheet)). The blur wraps at the sheet's edges. Alpha is
copied unchanged (an opaque sheet stays opaque).

## Output and exit

Writes `<out-dir>/<stem>_even.png` for each sheet and `even_preview.jpg` (each original beside its copy at 768
px); prints the main tone and each sheet's broad lightness spread before and after (Linlong: main tone L* 84.7,
a* 2.2, b* 13.9; spread 3.6 and 4.6 down to 1.0). Exit 0; an unreadable sheet raises.

## Side effects

None beyond the output folder. It does not touch the game, a mod or the per-model preset.
