# test_rpai_keys.py

Offline unit tests of the mmd-remix-pbr skill's rpai model keys (`skills/mmd-remix-pbr/tool/rpai`):

| Class | Cases |
|---|---|
| `KeyTests` | `config.model_key` leaves the naming rule's tags out of the slug: a rating tag, a game, a version, the PMX editor's default English name (which gives `model_<id8>`), a non-ASCII name. `config.legacy_model_key` is the key before 2026-11-17. Every per-model preset in the skill is named `<slug>_<id8>` with a slug that `model_key` gives back unchanged, so no preset name carries a tag. |
| `MoveTests` | `cli.adopt_legacy_work` renames the old key's work folder to the new key, and leaves it when the new folder exists or there is no old key. `cli.model_preset` reads a preset still named after the old key until one named after the new key exists. `cli.cmd_publish` writes the new key's layer, deletes the old key's layer and its DDS files, and `mod.usda` lists only the new layer. `cli.cmd_remove` deletes both keys' layers. |

```powershell
Set-Location tools; python -m unittest tests.test_rpai_keys -v
```

`tools\test.ps1` runs it with the other tests in `tools\tests`. Standard library only, besides rpai's own
modules, which are imported from the skill's `tool` folder.

## Side effects

Writes only into a temporary folder (`tempfile`, which honours `TEMP`), removed after each test. DDS
encoding is replaced by a stub, so NVTT is not needed. No game, no network, no real `RPAI_HOME`.

## Exit codes

0 when every test passes, 1 otherwise (unittest's own codes).
