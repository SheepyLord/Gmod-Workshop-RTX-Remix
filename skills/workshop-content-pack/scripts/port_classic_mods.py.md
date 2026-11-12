# port_classic_mods.py

Ports a finished map's Remix mod, or the set of mod folders it was played with, from a classic install's
`rtx-remix\mods` into one mod folder for a content pack, keeping what each hash showed. Used for the
classic install's Poolday (three folders) and SafeHouse (one) on 2026-11-12.

```powershell
$K = '<repo>\skills\workshop-content-pack\scripts'; $e = 'E:\RTX_c_backup\GarrysMod_RTX_c\rtx-remix\mods'
$B = '<repo or worktree>\out\packages\pool-day-rtx'
python -I "$K\port_classic_mods.py" --dest "$B\pool_day_rtx" --source "$e\Poolday" --source "$e\Poolday_mirror_fix" `
  --source "$e\gmodrtx_poolday_fix" --blank-missing --drop-unreferenced --json "$B\port-report.json" --dry-run
# then without --dry-run; one source is a plain copy under the new name:
python -I "$K\port_classic_mods.py" --dest "<B>\safehouse_rtx" --source "$e\SafeHouse"
```

## Why one folder needs care

The runtime ranks mod folders by name (case-sensitive byte order: `!` < digits < upper case < `_` < lower
case < `~`) and, for each texture, mesh or light hash, uses the first folder that replaces it, whole
(`AssetReplacer::getReplacementMaterial`, `getReplacementsForMesh`, `getReplacementsForLight`). Inside one
folder its sub-layers are composed by USD instead: the stronger layer wins attribute by attribute and a
weaker layer fills what the stronger leaves unset. A merge therefore keeps the look only where no later
folder adds attributes to a hash an earlier folder owned. One more runtime rule: a mesh prim with nothing
in it (`over "mesh_X" {}`) registers no replacement (`processReplacement` returns false), so the next
folder's override of that hash was the live one.

## What it does

1. Orders the `--source` folders by the runtime's rule and prints the order (strongest first).
2. Walks each from its `mod.usda` with [usd_refs.py](usd_refs.py.md): every layer (text and binary
   crate), referenced file, missing file, unreferenced file, shader name.
3. For every hash prim (`mat_`, `mesh_`, `light_`, `sky_`) more than one source authors, finds the owner
   (the first source with a non-empty prim) and refuses when a later source sets a property, child prim
   or composition arc the owner does not (that would apply once merged). Take the dead override out of
   the later source first, or keep the folders apart.
4. Copies each source unchanged into `<dest>\<source folder name>\` and writes `<dest>\mod.usda` (game
   name, replacement layer type, `--doc`, the sources' common `metersPerUnit` and `upAxis`) with their
   `mod.usda` files as sub-layers, strongest first. The runtime finds mods only one folder deep, so the
   nested `mod.usda` files are plain layers. With one source the folder is copied as it is.
5. `--blank-missing`: a texture reference to a file the source never had becomes `@@` (no texture: what
   Remix drew, minus an `err:` line in its log). Without it, missing files are refused. Missing layers
   and missing files named by binary layers are always refused.
6. `--drop-unreferenced`: files no layer reaches are left out (Poolday's three unused MDL copies and the
   two textures of a material a later fix took over).
7. Every copy is SHA-256-checked; the result is built as `<dest>.partial-<pid>`, renamed into place, and
   walked again: every reference must resolve.

## Options

| Option | Meaning |
|---|---|
| `--dest` | the new mod folder (named after the map: `<map>_rtx`) |
| `--source` | a mod folder (repeatable); order on the command line does not matter |
| `--blank-missing`, `--drop-unreferenced` | above |
| `--doc` | the root layer's `doc` (several sources only); straight double quotes become single |
| `--dry-run` | report only |
| `--force` | replace an existing `--dest` |
| `--json` | the report: order, per source its layers, missing and unreferenced files, the overlaps, refusals; after a write also each file written and the references blanked |

## Exit codes

0 done (or a dry run with nothing refused); 1 refused (missing files without `--blank-missing`, a merge
difference, an unreadable layer, a reference outside the mod or not relative, sources whose stage
metadata differ, `--dest` exists, a source and `--dest` inside one another); 2 bad command line (also two
sources with one folder name).

## Side effects

Writes only `--dest` (and its `.partial-<pid>` while working) and `--json`. Reads the sources.

## The 2026-11-12 ports

| Pack | Sources | Result |
|---|---|---|
| `pool_day_rtx` | `Poolday` (20 materials, 4 lights), `Poolday_mirror_fix` (the mirror, two mesh category fixes), `gmodrtx_poolday_fix` (path-traced water) | two overlaps, neither a difference: `mat_3C0A7FF562C52317` (Poolday sets both values the mirror fix also sets), `mesh_345F539D9A62C372` (empty in Poolday: the mirror fix's override was live and stays live); 39 references to files Poolday never had blanked (20 metallic maps in a `metallness/` folder it lacks, 7 height, 6 normal and 6 roughness maps: the 39 `err:` lines R19 counted in the Remix log); 5 unreferenced files left out; 73 files, 347 MB |
| `safehouse_rtx` | `SafeHouse` | a copy: 223 files, 2.82 GB, 16 layers of which 13 binary (Poly Haven models), every reference present |

Tests: [test_port_classic_mods.py](test_port_classic_mods.py.md).

## Provenance

Written by Claude for this user on 2026-11-12. Standard library only; not third-party code.
