# authored_mod_session.py

A locked PoC RTX session that checks an authored Remix mod in the RTX Remix Toolkit's packaged format still applies
under the RTX package, with ToPBR off and on ([GitHub issue 14](https://github.com/SheepyLord/Gmod-Workshop-RTX-Remix/issues/14):
"Custom RTX weapon files no longer applying to material hash after ToPBR update"). The issue's mod overrides a weapon
texture's material with `over "mat_<hash>" { over "Shader" { ... } }` and only metallic, normal and roughness maps (no
`info:mdl:sourceAsset`, no albedo, maps named `*.a.rtex.dds`); its screenshot showed Alt+X's texture info calling the
weapon's texture a "Legacy material", which means no loaded mod had a material for that hash. Runtime patch 0020 ranks
ToPBR's `~gmod_topbr` after every authored mod ([ADR 0092](../../docs/decisions/0092-generated-fallback-mods-rank-last.md)).

```powershell
py -3 -I tools\qa\authored_mod_session.py --evidence <main checkout>\out\authored-mod\run1 --package out\dist\<package>.gma
py -3 -I tools\qa\authored_mod_session.py --evidence <same folder> --rollback   # after an interrupted run
```

| Option | Meaning |
|---|---|
| `--evidence` | A new folder under this repository's or the main checkout's `out` |
| `--package` | The RTX package to install (`.gma`) |
| `--topbr-wait` | Seconds ToPBR runs at scope 2 before the last screenshot (default 90) |
| `--lock-timeout` | How long to wait for `out\r10\poc.lock` (6 hours) |
| `--keep-copies` | Keep the PoC's moved originals and the snapshot's copies after a verified restore |
| `--rollback` | Restore the PoC from an interrupted run's evidence |

## What it does

1. Takes the main checkout's `out\r10\poc.lock`, snapshots the PoC ([`field_snapshot.py`](../field_snapshot.py.md)),
   moves its state into `originals\` ([vr_session.py](../vr_session.py.md)'s `preserve`: fresh data and Remix mods
   folders), installs the package ([`poc_session.py`](../poc_session.py.md) `install --allow-local --remix on
   --replace-config`) and ends a running field game ([mmd_reimport_session.py](mmd_reimport_session.py.md)'s
   `end_field_games`).
2. **Launch 1** (gm_construct, 1600x900): sends [authored_mod_probe.lua](authored_mod_probe.lua.md), holds the RTX
   sky at 14:00, gives the player the crowbar, spawns an oil drum and a wooden crate frozen on the ground ahead, locks
   the view, reads the Remix texture hashes of the crowbar's view model and of both props
   (`RemixMaterial.GetTextureHash`, `NLAM_HASHES`) and takes `01-base.png` after closing the package's windows.
3. Writes two mods into the PoC's `rtx-remix\mods` (copies in `mods\`): `nlam_toolkit`, the issue's format for the
   crowbar's and the drum's hashes (metallic 1, roughness near 0: dark mirror metal, a flat normal map; uncompressed
   DX10 DDS files of one colour), and `nlam_control`, the format rpai writes (`sourceAsset`, a red albedo) for the
   crate's.
4. **Launch 2**: the same scene with both mods loaded from the start: `02-mods-topbr-off.png`; then
   `rtx_topbr_scope 2` and `rtx_topbr_enabled 1`, `--topbr-wait` seconds, `03-mods-topbr-on.png`; keeps ToPBR's
   `materials.usda` (`topbr-materials.usda`) and puts both convars back.
5. Ends the game, keeps both launches' `console.log` and `remix-dxvk.log`, restores the PoC and the video settings,
   checks the `user.conf` hashes.

Verdict in `summary.json` (`verdict`, `reasons`, `summary`) and on the last line. It passes when the Remix log's
`[RTX Mod Load]` lines (runtime patch 0086) show `nlam_toolkit` with one material per hash and three maps each and
`nlam_control` with its materials, no `USD mod worker failed` line, and no authored hash in ToPBR's `materials.usda`.
The screenshots are for a person: with the mods, the drum is dark mirror metal and the crate red, with ToPBR on as off.

Exit code 0 on a pass, 1 on a failure, other codes on an error. Side effects: the PoC is used, its state put back
afterwards; the field game is ended if one runs.
