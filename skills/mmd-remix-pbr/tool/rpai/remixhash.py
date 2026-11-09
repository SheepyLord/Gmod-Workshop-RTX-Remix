"""Offline Remix texture hashes for Model Hotloader's VTFs, and the hash function the game uses.

The runtime (``D3D9CommonTexture::SetupForRtxFrom``, ``HashTextureData`` in
``src/d3d9/d3d9_texture_hash.h``) hashes the CPU buffer of subresource 0 - the
top mip as uploaded - with ``XXH64(data, size, 0)`` when
``rtx.useObsoleteHashOnTextureUpload`` is true, otherwise with ``XXH3_64bits``.
The RTX package's classic defaults set it to True; Remix's own default is False.
``resolve_obsolete_hash_option`` decides it the way the runtime does (below).

How Source uploads a Model Hotloader VTF (RGBA8888; Model Hotloader sets the
flag 0x2000 or no flag):

* with an alpha flag (0x2000; 0x1000 counts too, though no measured VTF had
  it) as A8R8G8B8: the BGRA bytes;
* without one as X8R8G8B8, writing only B, G and R. This project's runtime
  hashes the pad byte as zero (``GetDefinedTexelBits``), so these hash as BGR0.

Compiled addons ship block-compressed VTFs, whose blocks go up unchanged: the
top mip's raw DXT5 data reproduced all 3 live hashes of Robin's robin_zzz.mdl
(2026-10-25). DXT1 and DXT3 are hashed the same way.

Measured 2026-11-09 on every live hash rpai and ToPBR recorded whose VTF the
field install still has: this rule reproduces 251 of rpai's 264 and 3 of
ToPBR's 3. The 13 misses are opaque sheets recorded by 2026-10-26, before the
runtime zeroed the pad byte (one single-colour sheet hashed three ways then and
one way in every record since); no other layout or hash function matches them.
So a texture gets one candidate when the option is known, and one per hash
function when it is not (an override for a hash nothing uses is inert).
"""

from __future__ import annotations

import json
import os
import struct
from collections.abc import Mapping
from dataclasses import dataclass
from pathlib import Path

ALPHA_FLAGS = 0x1000 | 0x2000  # TEXTUREFLAGS_ONEBITALPHA | TEXTUREFLAGS_EIGHTBITALPHA
BLOCK_BYTES = {13: 8, 14: 16, 15: 16, 20: 8}  # DXT1, DXT3, DXT5, DXT1_ONEBITALPHA: bytes per 4x4 block


@dataclass
class Vtf:
    width: int
    height: int
    flags: int
    format: int
    mips: int
    frames: int
    data_end: int


def read_vtf_header(blob: bytes) -> Vtf:
    if blob[:4] != b"VTF\0":
        raise ValueError("not a VTF")
    width, height, flags, frames = struct.unpack_from("<HHIH", blob, 16)
    image_format = struct.unpack_from("<i", blob, 52)[0]
    return Vtf(width, height, flags, image_format, blob[56], max(1, frames), len(blob))


def top_mip_rgba(blob: bytes, vtf: Vtf):
    """Mip 0 of an RGBA8888 VTF as an (n, 4) uint8 array. The chain is stored smallest first, so it is the tail."""
    import numpy as np

    if vtf.format != 0:
        raise ValueError(f"VTF format {vtf.format} is not RGBA8888")
    size = vtf.width * vtf.height * 4
    return np.frombuffer(blob, np.uint8, size, vtf.data_end - size * vtf.frames).reshape(-1, 4)


def upload_bytes(blob: bytes) -> bytes:
    """The top mip as the runtime hashes it: raw blocks, BGRA, or BGR0 (the pad byte zeroed)."""
    vtf = read_vtf_header(blob)
    if vtf.format in BLOCK_BYTES:
        size = max(1, (vtf.width + 3) // 4) * max(1, (vtf.height + 3) // 4) * BLOCK_BYTES[vtf.format]
        start = vtf.data_end - size * vtf.frames
        return blob[start:start + size]
    texels = top_mip_rgba(blob, vtf)[:, [2, 1, 0, 3]]  # a copy, in BGRA order
    if not vtf.flags & ALPHA_FLAGS:
        texels[:, 3] = 0
    return texels.tobytes()


def _digest(data: bytes, obsolete: bool) -> str:
    import xxhash

    value = xxhash.xxh64_intdigest(data, seed=0) if obsolete else xxhash.xxh3_64_intdigest(data)
    return f"0x{value:016X}"


def predict(blob: bytes, obsolete: bool | None = True) -> list[str]:
    """A VTF's Remix hash: one candidate when the hash function is known (True: XXH64, False: XXH3),
    XXH64's then XXH3's when it is not (None)."""
    data = upload_bytes(blob)
    return [_digest(data, function) for function in ((True, False) if obsolete is None else (obsolete,))]


# ---------------------------------------------------------------- which hash function the game uses
#
# RtxOptionLayer::initializeSystemLayers (rtx_option_layer.cpp) gives every config file its own layer:
#   DXVK Config (1): each file of DXVK_CONFIG_FILE, else dxvk.conf
#   Hardcoded EXE Config (2): config.cpp's defaults for the executable; none for gmod.exe
#   Remix Config (3): each file of DXVK_RTX_CONFIG_FILE, else rtx.conf
#   baseGameMod Remix Config (4): a mod's rtx.conf, when rtx.baseGameModRegex matches the command line
#   Environment Variable Overrides (5), Derived (6), Quality Presets: never this option
#   User Settings: user.conf
# RtxOptionImpl::resolveValue takes a bool from the strongest layer that holds it. Layers of one
# priority sort by name ("00_DXVK Config", "01_DXVK Config", ..., "DXVK Config" for the last file), so
# within a list the first file that holds the option wins (the repository's ADR 0062 measured this for
# DXVK_CONFIG_FILE). Paths are relative to the game's working folder, the game root.

OPTION = "rtx.useObsoleteHashOnTextureUpload"
EXE = "gmod.exe"  # 64-bit Garry's Mod: a conf's [gmod.exe] section applies to it, any other section does not
LIST_LIMIT = 260  # env::getEnvVar reads a variable into MAX_PATH characters; a longer list reads as empty
_KEY_CHARS = frozenset("0123456789ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz._")
_BLANKS = " \t\r"


@dataclass
class HashOption:
    """``rtx.useObsoleteHashOnTextureUpload`` as the game resolves it."""

    obsolete: bool | None  # True: XXH64; False: XXH3; None: cannot be told offline
    source: str  # the deciding file and line, Remix's default, or why it is unknown


def _skip(line: str, n: int) -> int:
    while n < len(line) and line[n] in _BLANKS:
        n += 1
    return n


def read_conf(path: Path, exe: str = EXE) -> dict[str, tuple[str, int]]:
    """A Remix conf read as the runtime's ``parseUserConfigLine`` reads it: key -> (value, line number).

    Keys are case-sensitive. A value is everything after '=' and the blanks that follow it, every '"'
    dropped; trailing blanks stay. A later line wins. Lines after a ``[name]`` header count only when
    name is the game's executable. A missing or unreadable file reads as empty, as it does in game."""
    try:
        data = path.read_bytes()
    except OSError:
        return {}
    options: dict[str, tuple[str, int]] = {}
    active = True
    for number, raw in enumerate(data.replace(b"\r\n", b"\n").split(b"\n"), 1):
        line = raw.decode("latin-1")  # byte for byte, as a std::string: a BOM is no key character
        n = _skip(line, 0)
        if line[n:n + 1] == "[":
            n += 1
            end = len(line) - 1
            while end > n and line[end] != "]":
                end -= 1
            active = line[n:end] == exe
            continue
        start = n
        while n < len(line) and line[n] in _KEY_CHARS:
            n += 1
        key = line[start:n]
        n = _skip(line, n)
        if line[n:n + 1] != "=":
            continue
        if active:
            options[key] = (line[_skip(line, n + 1):].replace('"', ""), number)
    return options


def _as_bool(value: str) -> bool:
    # Config::parseOptionValue into a fresh (false) value: anything but true/1, any case, reads as False.
    return value.lower() in ("true", "1")


def _paths(value: str) -> list[str]:
    # RtxOptionLayer::resolveConfigPaths: split at commas, skip empty entries, trim nothing.
    return [path for path in value.split(",") if path]


def _env_list(env: Mapping[str, str], name: str, default: str) -> list[str]:
    value = env.get(name) or ""
    return _paths(value) if value and len(value) < LIST_LIMIT else [default]


def _read_json(path: Path):
    try:
        return json.loads(path.read_text(encoding="utf-8-sig"))
    except (OSError, ValueError):
        return None


def _strings(value) -> bool:
    return isinstance(value, list) and all(isinstance(item, str) for item in value)


def remix_layers(game_root: Path, env: Mapping[str, str] | None = None) -> tuple[list[str], list[str], str]:
    """The Remix Config and DXVK Config file lists the game reads, in listed order, and where they come from.

    1. The loader's report of its latest start (``garrysmod/data/native-loader/status.json``), when RTX
       was active: ``activation.layers`` are the lists the runtime read, the package's copies in
       ``native-loader/remix`` and the user's own lists included.
    2. Otherwise the loader's journal (``native-loader/state.json``): the deployed runtime package's
       conf layers, which the next RTX start copies, then the user's list from this process's
       environment or the root conf. The loader's own generated layers are left out: they never set
       the option.
    3. Without the loader, the runtime's defaults: the environment's lists, else rtx.conf and dxvk.conf.
    """
    env = os.environ if env is None else env
    status = _read_json(game_root / "garrysmod" / "data" / "native-loader" / "status.json")
    activation = status.get("activation") if isinstance(status, dict) else None
    layers = activation.get("layers") if isinstance(activation, dict) else None
    if (isinstance(layers, dict) and status.get("schema") == 1 and activation.get("outcome") == "active"
            and _strings(layers.get("rtx")) and _strings(layers.get("dxvk"))):

        def as_read(names: list[str], default: str) -> list[str]:
            # The report keeps a list the runtime could not read whole (LIST_LIMIT) as the loader set it.
            return names if len(",".join(names)) < LIST_LIMIT else [default]

        return (as_read(layers["rtx"], "rtx.conf"), as_read(layers["dxvk"], "dxvk.conf"),
                "the loader's status.json of its latest start")
    journal = _read_json(game_root / "native-loader" / "state.json")
    current = journal.get("current") if isinstance(journal, dict) else None
    for package in (current.get("packages") if isinstance(current, dict) else None) or []:
        remix = package.get("remix") if isinstance(package, dict) else None
        payload = package.get("payload") if isinstance(remix, dict) else None
        if isinstance(payload, str) and payload:  # the loader's runtime: the first package with both
            own = {kind: [f"{payload}/{layer}" for layer in remix.get(f"{kind}_conf_layers") or []
                          if isinstance(layer, str)] for kind in ("rtx", "dxvk")}
            return (own["rtx"] + _env_list(env, "DXVK_RTX_CONFIG_FILE", "rtx.conf"),
                    own["dxvk"] + _env_list(env, "DXVK_CONFIG_FILE", "dxvk.conf"),
                    f"the deployed runtime package {package.get('id')} {package.get('version')}"
                    " (no active status.json)")
    return (_env_list(env, "DXVK_RTX_CONFIG_FILE", "rtx.conf"), _env_list(env, "DXVK_CONFIG_FILE", "dxvk.conf"),
            "no native loader")


def resolve_obsolete_hash_option(game_root: Path, env: Mapping[str, str] | None = None) -> HashOption:
    """``rtx.useObsoleteHashOnTextureUpload`` as the runtime resolves it at start-up. Reads only."""
    rtx, dxvk, origin = remix_layers(game_root, env)
    confs: dict[str, dict[str, tuple[str, int]]] = {}

    def conf(name: str) -> dict[str, tuple[str, int]]:
        if name not in confs:
            confs[name] = read_conf(game_root / name)
        return confs[name]

    def first_holding(names: list[str], layer: str) -> HashOption | None:
        for name in names:
            value, line = conf(name).get(OPTION, ("", 0))
            if value:  # Config::findOption: an empty value is no value
                return HashOption(_as_bool(value), f"{name} line {line} ({layer}; {origin})")
        return None

    held = first_holding(["user.conf"], "User Settings")
    if held:
        return held
    merged: dict[str, tuple[str, int]] = {}
    for name in dxvk + rtx:  # s_mergedConfig: a later file wins; config.cpp adds nothing for gmod.exe
        merged.update(conf(name))
    if all(merged.get(key, ("", 0))[0] for key in ("rtx.baseGameModRegex", "rtx.baseGameModPathRegex")):
        return HashOption(None, "unknown: rtx.baseGameModRegex and rtx.baseGameModPathRegex are set, so an "
                                "rtx.conf the game's command line points to may decide it")
    return (first_holding(rtx, "Remix Config") or first_holding(dxvk, "DXVK Config")
            or HashOption(False, f"Remix's default: no layer sets it ({origin})"))


def read_obsolete_hash_option(game_root: Path) -> bool | None:
    """True for XXH64, False for XXH3, None when it cannot be told offline."""
    return resolve_obsolete_hash_option(game_root).obsolete
