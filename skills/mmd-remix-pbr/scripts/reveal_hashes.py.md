# reveal_hashes.py

Shows a spawned model's hidden parts, runs `rpai hashes`, then hides exactly those parts again and
checks the visibility matches what it was. Remix reports a texture's hash only once the game has drawn
it, so hidden parts (outfit layers, toggled accessories) keep **predicted** hashes, which are often
wrong (the first Firefly layer's predictions for the bunny suit, ears, beads and heels all were, so
those parts never got their PBR; 2026-11-06).

```powershell
& $py reveal_hashes.py --game-root H:\SteamLibrary\steamapps\common\GarrysMod 32c908bc 76 "<pmx>"
& $py reveal_hashes.py 19c0edc5 83 "<pmx>" --asset 19c0edc5     # options after the PMX go to rpai hashes
```

| Argument | Meaning |
|---|---|
| `--game-root` | the Garry's Mod folder of the game to drive (default: the first running game); also passed to `rpai hashes` |
| `--settle` | seconds to let the shown parts draw before `rpai hashes` (default 8) |
| `asset` | the Model Hotloader asset id or prefix of the spawned model |
| `count` | the PMX's material count (`classes.json` in rpai's work folder lists them) |
| `pmx` | the PMX path, as rpai takes it |
| further options | passed to `rpai hashes` (such as `--asset <id8>`) |

Prints the hidden parts per spawned copy, rpai's lines about predicted and live hashes, and
`restored exactly: True` (or `False`).

Parts a material morph hides, and painted shadows the companion leaves out of the draw in RTX sessions
(`nativeloader_hide_painted_shadows`, ADR 0104), are not drawn by showing their bodygroup: they keep
predicted hashes, and painted shadows need no PBR.

## Side effects

Changes part visibility on the spawned copies through `mmdhl.SetMaterialVisible` (the rpai bridge,
`abtest.py`'s helpers), and puts back exactly the parts it showed, also when `rpai hashes` fails. Runs
`rpai hashes` with the rpai venv's Python (`RPAI_HOME\venv`, default `%USERPROFILE%\.rpai`), which
updates `work\<model key>\hashes.json`. Writes nothing else. Do not run it while the user is arranging
the scene, nor beside another session's capture.

## Exit codes

0 done and the visibility restored exactly; 1 the visibility differs afterwards, `rpai hashes` failed,
or the game did not answer (the error is printed); 2 bad command line.

## Provenance

Written for this user by Claude in the Firefly remake session (2026-11-06) in the installed copy of this
skill, with that machine's paths fixed in it; copied into the repository on 2026-11-08 with the paths
taken from `--game-root`, `RPAI_HOME` and the script's own folder, an argument parser and exit codes.
Run with the rpai venv's Python. Part of the `mmd-remix-pbr` skill ([SKILL.md](../SKILL.md)).
