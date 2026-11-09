# test_remix_hash_prediction.py

Offline tests for the [MMD PBR skill](../../skills/mmd-remix-pbr/SKILL.md)'s Remix texture hashes
([`remixhash.py`](../../skills/mmd-remix-pbr/tool/rpai/remixhash.py.md)): which hash function the game uses,
decided from the native loader's layers as the runtime decides it, and the hash `rpai` predicts for a VTF.

## Usage

From `tools/`: `python -m unittest discover -s tests -p test_remix_hash_prediction.py -v`.
Also runs in `tools\test.ps1`.

## What it checks

- **The conf reader** reads lines as the runtime's `parseUserConfigLine` does: case-sensitive keys, quotes
  dropped, trailing blanks kept, the last line winning, `[hl2.exe]` sections skipped and `[gmod.exe]` read,
  a byte order mark hiding the first line; and bools as the runtime parses them (`yes`, `True ` and
  `True # comment` read as False).
- **Which file decides**, in fake game roots under `out/tmp`: the field install's layout of 2026-11-09
  (the loader's `status.json` listing `native-loader/remix/dxvk-1.conf`, the package's classic defaults,
  whose line 139 sets the option, with `rtx.conf` and `user.conf` silent: the case `rpai` read as XXH3
  from 2026-10-29); the first listed DXVK file winning over the root `dxvk.conf`; `rtx.conf` beating
  the DXVK files unless its value is empty; `user.conf` beating all and staying unchanged; the
  loader's journal when the latest start was not active (with the user's own lists); no loader at all;
  the 259/260-character limit on a list; a base game mod making the option unknown.
- **Hashes** (only with `numpy` and `xxhash`, rpai's requirements; skipped otherwise, as on GitHub's runner,
  which installs only Pillow): two live hashes the game reported to `rpai hashes` in the field
  (`0x84168AFC8CF54915`, a 1024x1024 single-colour sheet recorded for 9 models, and `0x37B3BC9B48184AA9`,
  a 520x520 one recorded for 4), reproduced from VTFs the test writes in Model Hotloader's layout
  (`native/assets.cpp`: an 80-byte 7.2 header, the mip chain smallest first); one candidate per known
  hash function and both when unknown; BGRA with the alpha flag, BGR0 without, and a DXT5 top mip's
  raw blocks, against XXH64 of bytes built by hand.
- **`rpai hashes`** (`cli.cmd_hashes` with a stand-in context and no game; with `numpy` and `xxhash`): it logs
  `hash    XXH64: native-loader/remix/dxvk-1.conf line 139 ...`, records `obsolete_hash` and
  `obsolete_hash_source` in `hashes.json`, predicts the one recorded hash, and reuses an earlier live hash only
  from a record whose `obsolete_hash` matches.

## Inputs and outputs

Writes its game roots and VTFs under the worktree's `out/tmp/` and removes them. Reads the skill's
source; never connects to or launches a game, and reads nothing of an install.

## Exit codes

0 when all tests pass; 1 on failure (unittest).
