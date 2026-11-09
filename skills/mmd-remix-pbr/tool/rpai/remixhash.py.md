# remixhash.py

Offline Remix texture hashes for Model Hotloader's VTFs, and the hash function the game uses.

The runtime (`D3D9CommonTexture::SetupForRtxFrom`, `HashTextureData` in
`src/d3d9/d3d9_texture_hash.h`) hashes the CPU buffer of subresource 0 - the
top mip as uploaded - with `XXH64(data, size, 0)` when
`rtx.useObsoleteHashOnTextureUpload` is true, otherwise with `XXH3_64bits`.
The RTX package's classic defaults set it to True; Remix's own default is False.

How Source uploads a Model Hotloader VTF (RGBA8888; Model Hotloader sets the
flag 0x2000 or no flag):

* with an alpha flag (0x2000; 0x1000 counts too, though no measured VTF had
  it) as A8R8G8B8: the BGRA bytes;
* without one as X8R8G8B8, writing only B, G and R. This project's runtime
  hashes the pad byte as zero (`GetDefinedTexelBits`), so these hash as BGR0.

Compiled addons ship block-compressed VTFs, whose blocks go up unchanged: the
top mip's raw DXT5 data reproduced all 3 live hashes of Robin's robin_zzz.mdl
(2026-10-25). DXT1 and DXT3 are hashed the same way.

Measured 2026-11-09 on every live hash rpai and ToPBR recorded whose VTF the
field install still has: this rule reproduces 251 of rpai's 264 and 3 of
ToPBR's 3. The 13 misses are opaque sheets recorded by 2026-10-26, before the
runtime zeroed the pad byte (one single-colour sheet hashed three ways then and
one way in every record since); no other layout or hash function matches them.
So a texture gets one candidate when the option is known, and one per hash
function (XXH64's first) when it is not; an override for a hash nothing uses is inert.

Part of the `mmd-remix-pbr` skill ([SKILL.md](../../SKILL.md)); the full method and every option are in [tool/README.md](../../tool/README.md).

Run with the rpai venv's Python (`%USERPROFILE%\.rpai\venv\Scripts\python.exe`). The module imports
only the standard library; `predict` needs `numpy` and `xxhash` (both in `requirements.txt`).

## Functions

| Function | What |
|---|---|
| `predict(blob, obsolete=True)` | The VTF's Remix hash as `["0x..."]`: XXH64 for `True`, XXH3 for `False`, both (XXH64 first) for `None` |
| `upload_bytes(blob)` | The top mip as the runtime hashes it: raw blocks, BGRA, or BGR0 |
| `read_vtf_header(blob)`, `top_mip_rgba(blob, vtf)` | VTF header fields; mip 0 of an RGBA8888 VTF as an `(n, 4)` array (the chain is stored smallest first) |
| `resolve_obsolete_hash_option(game_root, env=None)` | `HashOption(obsolete, source)`: `True`/`False`, or `None` when it cannot be told offline, with the deciding file and line (or the default) |
| `read_obsolete_hash_option(game_root)` | Its `obsolete` alone |
| `remix_layers(game_root, env=None)` | The Remix Config and DXVK Config file lists the game reads, and where they come from |
| `read_conf(path)` | One conf as the runtime's parser reads it: key -> (value, line number) |

## How the option is decided

As the runtime does at start-up (`RtxOptionLayer::initializeSystemLayers`, then
`RtxOptionImpl::resolveValue`; the repository's `docs/RESEARCH.md` gives the source lines), strongest first:

1. `user.conf` in the game root (User Settings). Read, never written.
2. A base game mod's `rtx.conf` (baseGameMod Remix Config): only when the confs set both
   `rtx.baseGameModRegex` and `rtx.baseGameModPathRegex`. Its folder comes from the game's command line,
   which rpai cannot see, so the option is then unknown (`None`) unless `user.conf` sets it.
3. The Remix Config list (`DXVK_RTX_CONFIG_FILE`, else `rtx.conf`).
4. The DXVK Config list (`DXVK_CONFIG_FILE`, else `dxvk.conf`). The native loader puts the package's layers
   here, as copies in `native-loader/remix/dxvk-<n>.conf`; the classic defaults set the option to True.
5. Remix's default, False. The runtime's built-in defaults for executables (config.cpp) have none for
   `gmod.exe`, and the option has no environment variable.

Within one list the first file that holds the option wins (layers of one priority sort by name, and the
last file's name sorts last). Paths are relative to the game root, the game's working folder.

The lists come from, in this order:

1. The loader's report of its latest start, `garrysmod/data/native-loader/status.json`, when RTX was active:
   `activation.layers.rtx` and `.dxvk` are what the runtime read, the user's own lists included.
2. Otherwise the loader's journal, `native-loader/state.json`: the deployed runtime package's
   `rtx_conf_layers` / `dxvk_conf_layers` in its payload folder (what the next RTX start copies), then the
   user's list from this process's environment or the root conf. The loader's generated layers (tier,
   non-NVIDIA, memory, diagnostics) are left out: they never set the option.
3. Without the loader, the runtime's defaults: the environment's lists, else `rtx.conf` and `dxvk.conf`.

A list of 260 characters or more reads as empty in the runtime (`env::getEnvVar` uses a `MAX_PATH`
buffer), so only the root conf is read then.

What the parser keeps from the runtime's (`parseUserConfigLine`): keys are case-sensitive; a value runs
from the first non-blank after `=` to the end of the line with every `"` dropped, so trailing blanks or a
comment after the value make it unreadable; a later line wins; lines after a `[name]` header count only for
`[gmod.exe]`; a byte order mark hides the first line; an empty value is no value. A bool reads as True for
`true` or `1` in any case and as False for anything else, an unreadable value included.

## Side effects

None: computes hashes in memory and reads the game's Remix confs, the loader's `status.json` and
`state.json`, and the runtime package's conf files. It writes nothing.

## Exit codes

None: a library module, imported by `rpai` (`tool/rpai/cli.py`), not run on its own. Tests:
`tools/tests/test_remix_hash_prediction.py` in the repository.
