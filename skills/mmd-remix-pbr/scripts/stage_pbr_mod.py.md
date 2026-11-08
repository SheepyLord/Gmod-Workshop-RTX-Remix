# stage_pbr_mod.py

Stages the Remix mod folder of a Workshop character package from the live `ai_pbr` mod (or another
rpai mod, such as `ai_pbr_2048`).

Copies only the DDS files the named layers reference, checks every copy by SHA-256, copies the layers
and writes a `mod.usda` that lists them. The folder is the `--mod` input of `package_content.py`.

```powershell
& $py stage_pbr_mod.py --src <GarrysMod>\rtx-remix\mods\ai_pbr --dest out\packages\x\pbr_x `
    --layer evernight_cf3eec2f --layer model_e2c25f9e --doc "Evernight and March 7th RTX PBR, packaged for the Workshop."
```

Layer names are the rpai model keys (`rpai status` lists them). The destination must not exist.
Nothing is written outside it.

## Names

The user's rule (2026-11-08) through [model_names.py](model_names.py.md): the `--dest` folder's name
(`pbr_<name>`, the deployed `rtx-remix\mods\pbr_<name>`) and the `--doc` text carry no game, version,
author or rating tag. A tagged one (`pbr_robin_r18`, `--doc "Robin R18 ..."`) ends the run with exit 1
before anything is written. Keep rpai keys out of `--doc`: rpai derives a key from the PMX's English
name (`robin_r18_f9c3e4b4`), so it may carry tags; inside the mod a key stays a file name.

Part of the `mmd-remix-pbr` skill ([SKILL.md](../SKILL.md)); the full method and every option are in
[tool/README.md](../tool/README.md). Run with the rpai venv's Python
(`%USERPROFILE%\.rpai\venv\Scripts\python.exe`); it needs only the standard library.

## Side effects

Reads the live mod; writes only `--dest`, which must not exist yet: the named layers, exactly the DDS
files they reference (each copy checked by SHA-256) and a `mod.usda` listing them.

## Exit codes

0 on success; 1 when a step fails or a name is refused (the reason is printed); 2 for a bad command
line (argparse). Tests: workshop-content-pack's `test_names.py` (the name refusal).
