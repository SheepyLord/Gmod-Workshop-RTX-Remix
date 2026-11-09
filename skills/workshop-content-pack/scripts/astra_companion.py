"""Turn a map's Astra RTX companion (a .gma made for the old Astra startup loader) into the two
halves of a native-loader content pack: a Lua add-on folder and a Remix mod folder.

The Astra companions stored their Remix mod inside the archive as data GMod would mount
(data_static/astra/<map>/rtx/*.dds.dat, mod.usda.dat, startup.json) and needed a startup d3d9.dll
proxy and the AstraRTXBridge module to unpack and publish it. The native loader deploys a mod
folder itself, so this script writes the mod as it was published (every payload checked against
startup.json's SHA-256), the lights and settings of the old add-on as data for a small runtime
(astra_companion/runtime.lua), and leaves out what only the old route needed (the PNG fallback
atlases, the bridge protocol).

See astra_companion.py.md for the inputs, outputs and options.
"""
from __future__ import annotations

import argparse
import hashlib
import io
import json
import math
import os
import re
import shutil
import struct
import sys
import time

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
TEMPLATE_DIR = os.path.join(SCRIPT_DIR, "astra_companion")
REPO = os.path.normpath(os.path.join(SCRIPT_DIR, "..", "..", ".."))
DEFAULT_LAYER = os.path.join(REPO, "packages", "runtime", "layers", "classic_remix_defaults.conf")

CATEGORY_FLAGS = {"particle": 1 << 10, "animated_water": 1 << 18, "legacy_emissive": 1 << 24}
# Remix reads these inputs from the red channel only.
SINGLE_CHANNEL_ROLES = {"reflectionroughness_texture", "metallic_texture", "height_texture"}
MIN_DISTANT_DIAMETER = 0.05729577951308232  # degrees; the runtime's smallest sampled half-angle x2
MAX_MEMBER = 512 << 20
NAME_RE = re.compile(r"^[a-z0-9_]{1,64}$")
MAP_RE = re.compile(r"^[a-z0-9_\-]{1,96}$")
SHA_RE = re.compile(r"^[0-9a-f]{64}$")
HASH_RE = re.compile(r"^[0-9a-fA-F]{16}$")
TEXREF_RE = re.compile(r"(asset inputs:(\w+) = @\./textures/)([0-9a-f]{64})(\.dds@)")
DXGI_BC7, DXGI_BC7_SRGB, DXGI_BC4 = 98, 99, 80


class Refused(Exception):
    """A check failed: the archive or the profile is not what this script converts."""


# --------------------------------------------------------------------------- the archive

class Gma:
    """Index and members of a plain GMAD archive (versions 1-3), read on demand."""

    def __init__(self, path: str):
        self.path = path
        self.fh = open(path, "rb")
        f = self.fh
        if f.read(4) != b"GMAD":
            raise Refused(f"{path}: not a GMAD archive")
        version = f.read(1)[0]
        if version not in (1, 2, 3):
            raise Refused(f"{path}: GMAD version {version}")
        f.read(16)  # SteamID, timestamp
        if version > 1:
            while self._string():
                pass
        self.title, self.description, self.author = self._string(), self._string(), self._string()
        f.read(4)
        self.members: dict[str, tuple[int, int]] = {}
        sizes = []
        while True:
            (number,) = struct.unpack("<I", f.read(4))
            if number == 0:
                break
            name = self._string().replace("\\", "/")
            size, _crc = struct.unpack("<qI", f.read(12))
            if size < 0 or name.lower() in self.members:
                raise Refused(f"{path}: bad index entry {name!r}")
            sizes.append((name.lower(), size))
        offset = f.tell()
        for name, size in sizes:
            self.members[name] = (offset, size)
            offset += size
        f.seek(0, os.SEEK_END)
        if f.tell() < offset:
            raise Refused(f"{path}: truncated")

    def _string(self) -> str:
        out = bytearray()
        while True:
            c = self.fh.read(1)
            if not c:
                raise Refused(f"{self.path}: truncated header")
            if c == b"\0":
                return out.decode("utf-8", "replace")
            out += c
            if len(out) > 1 << 20:
                raise Refused(f"{self.path}: header string too long")

    def size(self, name: str) -> int:
        return self.members[name.lower()][1]

    def read(self, name: str, limit: int = MAX_MEMBER) -> bytes:
        offset, size = self.members[name.lower()]
        if size > limit:
            raise Refused(f"{name}: {size} bytes, more than {limit}")
        self.fh.seek(offset)
        data = self.fh.read(size)
        if len(data) != size:
            raise Refused(f"{name}: truncated")
        return data

    def close(self) -> None:
        self.fh.close()


class CompanionFolder:
    """An extracted companion (the archive's files under their paths), read like Gma. With --mod-from
    only its manifests are read, so a folder whose payloads were pruned still converts."""

    def __init__(self, path: str):
        self.path = os.path.abspath(path)
        self.title = os.path.basename(self.path)
        self.members: dict[str, tuple[str, int]] = {}
        for root, _dirs, names in os.walk(self.path):
            for name in names:
                full = os.path.join(root, name)
                rel = os.path.relpath(full, self.path).replace("\\", "/").lower()
                self.members[rel] = (full, os.path.getsize(full))

    def size(self, name: str) -> int:
        return self.members[name.lower()][1]

    def read(self, name: str, limit: int = MAX_MEMBER) -> bytes:
        full, size = self.members[name.lower()]
        if size > limit:
            raise Refused(f"{name}: {size} bytes, more than {limit}")
        with open(full, "rb") as handle:
            return handle.read()

    def close(self) -> None:
        pass


def open_companion(path: str):
    return CompanionFolder(path) if os.path.isdir(path) else Gma(path)


def verified(gma: Gma, path: str, size: int, sha256: str) -> bytes:
    if path.lower() not in gma.members:
        raise Refused(f"missing from the archive: {path}")
    if gma.size(path) != size:
        raise Refused(f"{path}: {gma.size(path)} bytes, startup.json says {size}")
    data = gma.read(path)
    if hashlib.sha256(data).hexdigest() != sha256:
        raise Refused(f"{path}: SHA-256 differs from startup.json")
    return data


# --------------------------------------------------------------------------- the Astra manifests

def load_json(gma: Gma, path: str) -> dict:
    try:
        value = json.loads(gma.read(path, 8 << 20).decode("utf-8"))
    except (UnicodeDecodeError, json.JSONDecodeError) as error:
        raise Refused(f"{path}: {error}") from error
    if not isinstance(value, dict):
        raise Refused(f"{path}: not a JSON object")
    return value


def find_startup(gma: Gma) -> tuple[str, str]:
    found = [n for n in gma.members if re.fullmatch(r"data_static/astra/[a-z0-9_\-]+/rtx/startup\.json", n)]
    if len(found) != 1:
        raise Refused(f"expected one data_static/astra/<map>/rtx/startup.json, found {len(found)}")
    return found[0], found[0].split("/")[2]


def find_index(gma: Gma, map_name: str, wanted: str | None) -> str:
    if wanted:
        if wanted.lower() not in gma.members:
            raise Refused(f"index {wanted} is not in the archive")
        return wanted.lower()
    found = [n for n in gma.members if re.fullmatch(r"data_static/[a-z0-9_]+/" + re.escape(map_name) + r"/rtx/index\.json", n)]
    if len(found) != 1:
        raise Refused(f"expected one data_static/<folder>/{map_name}/rtx/index.json, found {len(found)}")
    return found[0]


def check_startup(startup: dict, map_name: str) -> None:
    if startup.get("version") != 1 or startup.get("map") != map_name:
        raise Refused("startup.json: version or map differ")
    files = startup.get("files")
    if not isinstance(files, list) or not files:
        raise Refused("startup.json: no files")
    prefix = f"data_static/astra/{map_name}/rtx/"
    seen = set()
    for item in files:
        sha = item.get("sha256")
        if not (isinstance(sha, str) and SHA_RE.match(sha)) or sha in seen:
            raise Refused(f"startup.json: bad or repeated sha256 {sha!r}")
        seen.add(sha)
        if item.get("target") != f"textures/{sha}.dds" or not str(item.get("path", "")).lower().startswith(prefix) \
                or not str(item["path"]).endswith(".dds.dat") or not isinstance(item.get("bytes"), int):
            raise Refused(f"startup.json: unexpected descriptor {item!r}")
    layer = startup.get("layer")
    if not isinstance(layer, dict) or layer.get("target") != "mod.usda" or not SHA_RE.match(str(layer.get("sha256"))):
        raise Refused("startup.json: no mod.usda layer")


def check_index(index: dict, map_name: str) -> None:
    if index.get("version") != 1 or index.get("map") != map_name:
        raise Refused("index.json: version or map differ")
    if not isinstance(index.get("materials"), list) or not index["materials"]:
        raise Refused("index.json: no materials")
    prefix = f"astra/{map_name}/"
    for item in index["materials"]:
        name = item.get("material") if isinstance(item, dict) else None
        if not (isinstance(name, str) and name.startswith(prefix) and re.fullmatch(r"[a-z0-9_\-]+", name[len(prefix):])):
            raise Refused(f"index.json: bad material {name!r}")
    hashes = (index.get("startup") or {}).get("hashes") or {}
    for name, aliases in hashes.items():
        if not isinstance(aliases, list) or not aliases or not all(isinstance(a, str) and HASH_RE.match(a) for a in aliases):
            raise Refused(f"index.json: bad hash aliases for {name}")


# --------------------------------------------------------------------------- lights

def finite(value) -> bool:
    return isinstance(value, (int, float)) and not isinstance(value, bool) and math.isfinite(value)


def unit(vector) -> bool:
    return isinstance(vector, dict) and all(finite(vector.get(a)) for a in "xyz") \
        and abs(sum(vector[a] ** 2 for a in "xyz") - 1) <= 1e-4


def convert_light(light: dict) -> dict:
    """One Astra scene light to the RemixLight API's arguments, as the old runtime made them."""
    kind, base, shape = light.get("type"), light.get("base"), light.get("shape")
    lid = light.get("id")
    if kind not in ("sphere", "rect", "disk", "distant") or not isinstance(base, dict) or not isinstance(shape, dict):
        raise Refused(f"light {lid}: unsupported type or shape")
    if not (isinstance(base.get("hash"), int) and 0 < base["hash"] < 2 ** 53):
        raise Refused(f"light {lid}: bad hash")
    radiance = base.get("radiance")
    if not (isinstance(radiance, dict) and all(finite(radiance.get(a)) and radiance[a] >= 0 for a in "xyz")):
        raise Refused(f"light {lid}: bad radiance")
    shape = json.loads(json.dumps(shape))
    if kind != "distant" and not (isinstance(shape.get("position"), dict) and all(finite(shape["position"].get(a)) for a in "xyz")):
        raise Refused(f"light {lid}: bad position")
    if kind == "sphere" and not (finite(shape.get("radius")) and shape["radius"] > 0):
        raise Refused(f"light {lid}: bad radius")
    if kind in ("rect", "disk"):
        if not all(unit(shape.get(k)) for k in ("xAxis", "yAxis", "direction")):
            raise Refused(f"light {lid}: bad axes")
        sizes = ("xSize", "ySize") if kind == "rect" else ("xRadius", "yRadius")
        if not all(finite(shape.get(k)) and shape[k] > 0 for k in sizes):
            raise Refused(f"light {lid}: bad size")
    scaled = dict(radiance)
    if kind == "distant":
        if not unit(shape.get("direction")) or not (finite(shape.get("angularDiameterDegrees")) and 0 < shape["angularDiameterDegrees"] <= 180):
            raise Refused(f"light {lid}: bad direction or angle")
        # The Astra manifests hold Cycles' emitted radiance; the API's distant light divides by
        # sin(half angle)^2 (distantLightSampleArea), so multiply by it once here. The energy uses
        # the authored angle; only the sampled cone is widened to the runtime's minimum.
        s = math.sin(math.radians(shape["angularDiameterDegrees"]) / 2)
        scaled = {a: radiance[a] * s * s for a in "xyz"}
        shape["angularDiameterDegrees"] = max(shape["angularDiameterDegrees"], MIN_DISTANT_DIAMETER)
    if shape.get("volumetricRadianceScale") is None:
        shape["volumetricRadianceScale"] = 1
    if "shaping" in shape:
        shaping = shape["shaping"]
        if kind == "distant" or not isinstance(shaping, dict) or not unit(shaping.get("direction")):
            raise Refused(f"light {lid}: bad shaping")
    return {"id": lid, "type": kind, "base": {"hash": base["hash"], "isDynamic": False, "radiance": scaled}, "shape": shape}


# --------------------------------------------------------------------------- DDS and BC4

def dds_info(data: bytes) -> dict:
    if data[:4] != b"DDS " or len(data) < 148:
        raise Refused("not a DDS file")
    height, width = struct.unpack_from("<II", data, 12)
    mips = struct.unpack_from("<I", data, 28)[0] or 1
    if data[84:88] != b"DX10":
        return {"width": width, "height": height, "mips": mips, "dxgi": None, "offset": 128}
    return {"width": width, "height": height, "mips": mips, "dxgi": struct.unpack_from("<I", data, 128)[0], "offset": 148}


def mip_sizes(width: int, height: int, mips: int, block_bytes: int) -> list[tuple[int, int, int]]:
    out = []
    for level in range(mips):
        w, h = max(1, width >> level), max(1, height >> level)
        out.append((w, h, ((w + 3) // 4) * ((h + 3) // 4) * block_bytes))
    return out


def dds_header(width: int, height: int, mips: int, dxgi: int, top_bytes: int) -> bytes:
    """The header layout the Astra textures use: DX10 extension, mip chain, texture 2D."""
    header = struct.pack("<4s7I44x", b"DDS ", 124, 0xA1007, height, width, top_bytes, 1, mips)
    header += struct.pack("<2I4s5I", 32, 0x4, b"DX10", 0, 0, 0, 0, 0)
    header += struct.pack("<5I", 0x401008, 0, 0, 0, 0)
    header += struct.pack("<5I", dxgi, 3, 0, 1, 0)
    assert len(header) == 148
    return header


_W8 = None


def _weights():
    import numpy as np
    global _W8
    if _W8 is None:
        # Weight on the second endpoint for each index of BC4's eight-value mode (red0 > red1).
        _W8 = np.array([0, 1, 1 / 7, 2 / 7, 3 / 7, 4 / 7, 5 / 7, 6 / 7], dtype=np.float64)
    return _W8


def _assign(blocks, e0, e1):
    import numpy as np
    w = _weights()
    palette = e0[:, None] * (1 - w)[None, :] + e1[:, None] * w[None, :]
    distance = np.abs(blocks[:, :, None] - palette[:, None, :])
    index = distance.argmin(axis=2)
    error = np.take_along_axis(distance, index[..., None], axis=2)[..., 0]
    return index, (error ** 2).sum(axis=1)


def bc4_encode(channel) -> bytes:
    """BC4_UNORM blocks of a 2-D uint8 array: range fit, then two least-squares endpoint passes."""
    import numpy as np
    h, w = channel.shape
    bh, bw = (h + 3) // 4, (w + 3) // 4
    padded = np.pad(channel, ((0, bh * 4 - h), (0, bw * 4 - w)), mode="edge").astype(np.float64)
    blocks = padded.reshape(bh, 4, bw, 4).transpose(0, 2, 1, 3).reshape(-1, 16)
    out = np.empty((blocks.shape[0], 8), dtype=np.uint8)
    weights = _weights()
    step = 1 << 15
    for start in range(0, blocks.shape[0], step):
        b = blocks[start:start + step]
        e0, e1 = b.max(axis=1), b.min(axis=1)
        flat = e0 == e1
        index, sse = _assign(b, e0, e1)
        for _ in range(2):
            t = weights[index]
            a = 1 - t
            saa, stt, sat = (a * a).sum(1), (t * t).sum(1), (a * t).sum(1)
            sav, stv = (a * b).sum(1), (t * b).sum(1)
            det = saa * stt - sat * sat
            ok = np.abs(det) > 1e-9
            safe = np.where(ok, det, 1)
            n0 = np.clip(np.rint(np.where(ok, (sav * stt - stv * sat) / safe, e0)), 0, 255)
            n1 = np.clip(np.rint(np.where(ok, (stv * saa - sav * sat) / safe, e1)), 0, 255)
            n0, n1 = np.maximum(n0, n1), np.minimum(n0, n1)
            index2, sse2 = _assign(b, n0, n1)
            better = (n0 > n1) & ~flat & (sse2 < sse)
            e0, e1 = np.where(better, n0, e0), np.where(better, n1, e1)
            index = np.where(better[:, None], index2, index)
            sse = np.where(better, sse2, sse)
        index[flat] = 0  # red0 == red1: the six-value mode, whose index 0 is red0 itself
        bits = np.zeros(b.shape[0], dtype=np.uint64)
        for j in range(16):
            bits |= index[:, j].astype(np.uint64) << np.uint64(3 * j)
        chunk = out[start:start + step]
        chunk[:, 0], chunk[:, 1] = e0.astype(np.uint8), e1.astype(np.uint8)
        for k in range(6):
            chunk[:, 2 + k] = ((bits >> np.uint64(8 * k)) & np.uint64(0xFF)).astype(np.uint8)
    return out.tobytes()


def bc4_decode(data: bytes, width: int, height: int):
    """The reference decode of BC4_UNORM blocks (float palette), for the quality check and tests."""
    import numpy as np
    bh, bw = (height + 3) // 4, (width + 3) // 4
    raw = np.frombuffer(data, dtype=np.uint8, count=bh * bw * 8).reshape(-1, 8).astype(np.uint64)
    r0, r1 = raw[:, 0].astype(np.float64), raw[:, 1].astype(np.float64)
    bits = np.zeros(raw.shape[0], dtype=np.uint64)
    for k in range(6):
        bits |= raw[:, 2 + k] << np.uint64(8 * k)
    index = np.stack([((bits >> np.uint64(3 * j)) & np.uint64(7)).astype(np.int64) for j in range(16)], axis=1)
    eight = r0 > r1
    six = np.empty((raw.shape[0], 8))
    six[:, 6], six[:, 7] = 0, 255
    pal = np.empty((raw.shape[0], 8))
    for p in (pal, six):
        p[:, 0], p[:, 1] = r0, r1
    for i in range(1, 7):
        pal[:, i + 1] = ((7 - i) * r0 + i * r1) / 7
    for i in range(1, 5):
        six[:, i + 1] = ((5 - i) * r0 + i * r1) / 5
    pal = np.where(eight[:, None], pal, six)
    values = np.take_along_axis(pal, index, axis=1)
    image = values.reshape(bh, bw, 4, 4).transpose(0, 2, 1, 3).reshape(bh * 4, bw * 4)
    return image[:height, :width]


def decode_bc7_mip(width: int, height: int, payload: bytes, dxgi: int):
    """One BC7 surface to an RGBA uint8 array, through Pillow's BCn decoder."""
    import numpy as np
    from PIL import Image
    header = dds_header(width, height, 1, dxgi, len(payload))
    with Image.open(io.BytesIO(header + payload)) as image:
        image.load()
        return np.asarray(image.convert("RGBA"))


def bc7_to_bc4(data: bytes) -> tuple[bytes, float]:
    """A BC7 single-channel map as BC4: every mip of the original decoded and its red channel
    encoded again, so the original's mip chain is kept. Returns the file and the worst mip's PSNR
    (dB, against the BC7 decode) over mips of at least 16x16."""
    import numpy as np
    info = dds_info(data)
    if info["dxgi"] != DXGI_BC7:
        raise Refused("not BC7_UNORM")
    offset, parts, worst = info["offset"], [], float("inf")
    sizes = mip_sizes(info["width"], info["height"], info["mips"], 16)
    if offset + sum(s for *_, s in sizes) > len(data):
        raise Refused("mip chain longer than the file")
    for w, h, size in sizes:
        rgba = decode_bc7_mip(w, h, data[offset:offset + size], info["dxgi"])
        offset += size
        red = np.ascontiguousarray(rgba[..., 0])
        encoded = bc4_encode(red)
        parts.append(encoded)
        if w >= 16 and h >= 16:
            mse = float(((bc4_decode(encoded, w, h) - red.astype(np.float64)) ** 2).mean())
            worst = min(worst, 99.0 if mse == 0 else 10 * math.log10(255 ** 2 / mse))
    top = mip_sizes(info["width"], info["height"], 1, 8)[0][2]
    return dds_header(info["width"], info["height"], info["mips"], DXGI_BC4, top) + b"".join(parts), worst


# --------------------------------------------------------------------------- Lua output

LUA_NAME = re.compile(r"^[A-Za-z_][A-Za-z0-9_]*$")
LUA_KEYWORDS = set("and break do else elseif end false for function goto if in local nil not or repeat return then true until while".split())


def lua_string(text: str) -> str:
    out = ['"']
    for byte in text.encode("utf-8"):
        c = chr(byte)
        if c in '"\\':
            out.append("\\" + c)
        elif 32 <= byte < 127:
            out.append(c)
        else:
            out.append("\\%03d" % byte)  # three digits: a following digit must not join the escape
    out.append('"')
    return "".join(out)


def lua_value(value, indent: str = "") -> str:
    inner = indent + "    "
    if isinstance(value, bool):
        return "true" if value else "false"
    if isinstance(value, int):
        return str(value)
    if isinstance(value, float):
        if not math.isfinite(value):
            raise Refused("a non-finite number in the Lua data")
        text = repr(value)
        return text if any(c in text for c in ".e") else text + ".0"
    if isinstance(value, str):
        return lua_string(value)
    if isinstance(value, list):
        if not value:
            return "{}"
        if all(not isinstance(v, (dict, list)) for v in value) and len(value) <= 8:
            return "{ " + ", ".join(lua_value(v) for v in value) + " }"
        return "{\n" + "".join(f"{inner}{lua_value(v, inner)},\n" for v in value) + indent + "}"
    if isinstance(value, dict):
        if not value:
            return "{}"
        items = []
        for key, item in value.items():
            name = key if LUA_NAME.match(key) and key not in LUA_KEYWORDS else "[" + lua_string(key) + "]"
            items.append(f"{name} = {lua_value(item, inner)}")
        flat = "{ " + ", ".join(items) + " }"
        if len(flat) <= 100 and "\n" not in flat:
            return flat
        return "{\n" + "".join(f"{inner}{item},\n" for item in items) + indent + "}"
    raise Refused(f"cannot write {type(value).__name__} as Lua")


AUTORUN = """\
-- {title}: the RTX Remix companion of {map} (lights, scoped Remix settings, the bake's tint).
-- Made by astra_companion.py (workshop-content-pack skill) from the map's former Astra companion;
-- the PBR materials are the Remix mod rtx-remix/mods/{mod}, which the native loader deploys with
-- this add-on. Runs in RTX sessions on {map} only; {prefix}_status prints its state.
local MAP, DIR = "{map}", "{addon}"
if SERVER then
    AddCSLuaFile()
    AddCSLuaFile(DIR .. "/runtime.lua")
    AddCSLuaFile(DIR .. "/profile.lua")
    AddCSLuaFile(DIR .. "/hashes.lua")
    return
end
if game.GetMap() ~= MAP then return end
local start = include(DIR .. "/runtime.lua")
local profile = include(DIR .. "/profile.lua")
if isfunction(start) and istable(profile) then start(profile, DIR) end
"""


def read_layer_defaults(path: str | None) -> dict[str, str]:
    values: dict[str, str] = {}
    if not path or not os.path.isfile(path):
        return values
    with open(path, encoding="utf-8", errors="replace") as handle:
        for line in handle:
            match = re.match(r"^\s*(rtx\.[A-Za-z0-9_.]+)\s*=\s*(.*?)\s*$", line)
            if match:
                values[match.group(1)] = match.group(2)
    return values


# --------------------------------------------------------------------------- the conversion

def load_profile(path: str) -> dict:
    with open(path, encoding="utf-8") as handle:
        profile = json.load(handle)
    if profile.get("schema") != 1:
        raise Refused(f"{path}: schema must be 1")
    for key in ("map", "addon", "mod", "title", "prefix", "global"):
        if not isinstance(profile.get(key), str) or not profile[key]:
            raise Refused(f"{path}: {key} is required")
    for key in ("addon", "mod", "prefix"):
        if not NAME_RE.match(profile[key]):
            raise Refused(f"{path}: {key} must be 1-64 of a-z 0-9 _")
    if not LUA_NAME.match(profile["global"]) or not MAP_RE.match(profile["map"]):
        raise Refused(f"{path}: bad global or map name")
    if not all(32 <= ord(c) < 127 for c in profile["title"]):
        raise Refused(f"{path}: the title must be printable ASCII")
    for key, value in profile.get("remix", []):
        if not (isinstance(key, str) and key.startswith("rtx.") and isinstance(value, str)):
            raise Refused(f"{path}: bad Remix option {key!r}")
    for name, value in profile.get("engine", []):
        if not (isinstance(name, str) and re.fullmatch(r"[a-z0-9_]{1,64}", name) and isinstance(value, str)):
            raise Refused(f"{path}: bad engine setting {name!r}")
    for category in profile.get("categories", []):
        if category.get("flag") not in CATEGORY_FLAGS:
            raise Refused(f"{path}: unknown category flag {category.get('flag')!r}")
    if "shell" in profile:
        check_shell(profile["shell"], path)
    return profile


def check_shell(shell, path: str) -> None:
    """The shell: {"min": [x, y, z], "max": [x, y, z], "color": [r, g, b]} (game units, sRGB bytes)."""
    if not isinstance(shell, dict) or set(shell) - {"min", "max", "color", "note"}:
        raise Refused(f"{path}: the shell takes min, max, color (and a note)")
    for key in ("min", "max"):
        value = shell.get(key)
        if not (isinstance(value, list) and len(value) == 3 and all(isinstance(v, (int, float)) and finite(v) for v in value)):
            raise Refused(f"{path}: the shell's {key} must be three finite numbers")
    if not all(lo < hi for lo, hi in zip(shell["min"], shell["max"])):
        raise Refused(f"{path}: the shell's min must be below its max on every axis")
    color = shell.get("color")
    if not (isinstance(color, list) and len(color) == 3 and all(isinstance(c, int) and 0 <= c <= 255 for c in color)):
        raise Refused(f"{path}: the shell's color must be three integers 0-255")


def shell_vtf(color: list[int], size: int = 4) -> bytes:
    """A size x size VTF 7.2 of one colour: RGB888, one mip, no low-resolution image, clamped."""
    flags = 0x4 | 0x8 | 0x100 | 0x200  # CLAMPS | CLAMPT | NOMIP | NOLOD
    header = struct.pack("<4sII I HH I HH 4x 3f 4x f I B i BB H", b"VTF\0", 7, 2, 80, size, size, flags, 1, 0,
                         *(c / 255.0 for c in color), 1.0, 2, 1, -1, 0, 0, 1)
    header += b"\0" * (80 - len(header))
    return header + bytes(color) * (size * size)


def shell_vmt(material: str) -> str:
    return ('"UnlitGeneric"\n{\n'
            f'\t"$basetexture" "{material}"\n'
            '\t"$nofog" "1"\n'
            '}\n')


def material_list(spec, index: dict) -> list[str]:
    if spec == "pbr":
        return [item["material"] for item in index["materials"]]
    if spec == "baked_fallback":
        return [item["material"] for item in (index.get("baked_fallback") or {}).get("materials", [])]
    if isinstance(spec, list) and all(isinstance(s, str) for s in spec):
        return list(spec)
    raise Refused(f"bad material list {spec!r}")


def convert(args) -> dict:
    t0 = time.time()
    profile = load_profile(args.profile)
    out = os.path.abspath(args.out)
    earlier = None
    if getattr(args, "mod_from", None):
        # The mod half of an earlier conversion of this companion, for when its archive is gone (a
        # Workshop update replaced it) or its payloads were pruned: only the manifests are read again.
        earlier = os.path.abspath(args.mod_from)
        if os.path.normcase(earlier) == os.path.normcase(out):
            raise Refused("--mod-from must be another folder than --out")
        earlier_report_path = os.path.join(earlier, "report.json")
        earlier_mod = os.path.join(earlier, "mod", profile["mod"])
        if not (os.path.isfile(earlier_report_path) and os.path.isfile(os.path.join(earlier_mod, "mod.usda"))):
            raise Refused(f"{earlier} is not an earlier conversion with mod/{profile['mod']}/mod.usda")
        with open(earlier_report_path, encoding="utf-8") as handle:
            earlier_report = json.load(handle)
    if os.path.exists(out) and os.listdir(out):
        if not args.force:
            raise Refused(f"{out} is not empty (use --force)")
        if not os.path.isfile(os.path.join(out, "report.json")):
            raise Refused(f"{out} holds something else than an earlier conversion")
        shutil.rmtree(out)
    gma = open_companion(args.gma)
    try:
        startup_path, map_name = find_startup(gma)
        if map_name != profile["map"]:
            raise Refused(f"the archive is for {map_name}, the profile for {profile['map']}")
        startup = load_json(gma, startup_path)
        check_startup(startup, map_name)
        index_path = find_index(gma, map_name, profile.get("index"))
        index = load_json(gma, index_path)
        check_index(index, map_name)

        if earlier:
            usda, overrides, report = reuse_mod(earlier, earlier_report, out, profile, map_name, args.gma)
        else:
            usda, overrides, report = convert_mod(gma, startup, out, profile, map_name, args)

        # What became of the companion's files: the startup payloads are the mod now, the Lua is
        # replaced by the new add-on, the PNG atlases (the old map-time writer's fallback) and the
        # manifests are left out.
        for name, (_, size) in gma.members.items():
            if name.startswith("materials/") and name.endswith(".png"):
                group = "left_out_png_fallback"
            elif name.startswith("data_static/astra/") and name.endswith(".dat"):
                group = "converted_to_mod"
            elif name.startswith("lua/"):
                group = "replaced_lua"
            elif name.startswith("data_static/") and name.endswith((".json", ".txt")):
                group = "read_manifests"
            else:
                group = "other"
            entry = report["source_files"].setdefault(group, {"files": 0, "bytes": 0})
            entry["files"] += 1
            entry["bytes"] += size
        if earlier:
            report["source_files"] = earlier_report.get("source_files", report["source_files"])

        return write_addon(gma, index, index_path, usda, overrides, report, out, profile, map_name, args, t0)
    finally:
        gma.close()


def reuse_mod(earlier: str, earlier_report: dict, out: str, profile: dict, map_name: str, source: str):
    if earlier_report.get("map") != map_name:
        raise Refused(f"{earlier} converted {earlier_report.get('map')}, not {map_name}")
    mod_dir = os.path.join(out, "mod", profile["mod"])
    shutil.copytree(os.path.join(earlier, "mod", profile["mod"]), mod_dir)
    with open(os.path.join(mod_dir, "mod.usda"), encoding="utf-8") as handle:
        usda = handle.read()
    tex_dir = os.path.join(mod_dir, "textures")
    written = set(os.path.splitext(n)[0] for n in os.listdir(tex_dir)) if os.path.isdir(tex_dir) else set()
    if written != set(sha for _, _, sha, _ in TEXREF_RE.findall(usda)):
        raise Refused(f"{earlier}: the mod's textures and mod.usda's references differ")
    overrides = re.findall(r'over "mat_([0-9A-F]{16})"', usda)
    keep = ("source", "source_bytes", "textures", "texture_bytes", "bc4", "bc4_kept", "unreferenced", "overrides", "shaders")
    report = {"map": map_name, "source_files": {}, **{k: earlier_report[k] for k in keep if k in earlier_report}}
    report["mod_from"] = {"folder": os.path.basename(earlier), "companion": os.path.basename(os.path.abspath(source))}
    return usda, overrides, report


def convert_mod(gma, startup: dict, out: str, profile: dict, map_name: str, args):
    layer = startup["layer"]
    usda = verified(gma, layer["path"], layer["bytes"], layer["sha256"]).decode("utf-8")
    roles: dict[str, set[str]] = {}
    for _, role, sha, _ in TEXREF_RE.findall(usda):
        roles.setdefault(sha, set()).add(role)
    files = {item["sha256"]: item for item in startup["files"]}
    missing = sorted(set(roles) - set(files))
    if missing:
        raise Refused(f"mod.usda names {len(missing)} textures startup.json lacks, first {missing[0]}")
    overrides = re.findall(r'over "mat_([0-9A-F]{16})"', usda)
    if len(overrides) != len(set(overrides)):
        raise Refused("mod.usda overrides a hash twice")

    mod_dir = os.path.join(out, "mod", profile["mod"])
    tex_dir = os.path.join(mod_dir, "textures")
    os.makedirs(tex_dir)
    renamed: dict[str, str] = {}
    report = {"map": map_name, "source": os.path.basename(args.gma), "source_bytes": os.path.getsize(args.gma),
              "source_files": {}, "textures": 0, "texture_bytes": 0, "bc4": [], "bc4_kept": [], "unreferenced": 0}
    for sha, item in sorted(files.items()):
        if sha not in roles:
            report["unreferenced"] += 1
            continue
        data = verified(gma, item["path"], item["bytes"], sha)
        info = dds_info(data)
        if args.bc4 and roles[sha] <= SINGLE_CHANNEL_ROLES and info["dxgi"] == DXGI_BC7:
            converted, psnr = bc7_to_bc4(data)
            entry = {"from": sha, "roles": sorted(roles[sha]), "size": [info["width"], info["height"]],
                     "bytes_before": len(data), "bytes_after": len(converted), "psnr_db": round(psnr, 2)}
            if psnr < args.bc4_min_psnr:
                # Detail BC4's eight levels a block cannot hold: this map keeps its BC7.
                report["bc4_kept"].append(entry)
            else:
                new_sha = hashlib.sha256(converted).hexdigest()
                entry["to"] = new_sha
                renamed[sha] = new_sha
                report["bc4"].append(entry)
                sha, data = new_sha, converted
        with open(os.path.join(tex_dir, sha + ".dds"), "wb") as handle:
            handle.write(data)
        report["textures"] += 1
        report["texture_bytes"] += len(data)

    if renamed:
        usda = TEXREF_RE.sub(lambda m: m.group(1) + renamed.get(m.group(3), m.group(3)) + m.group(4), usda)
    with open(os.path.join(mod_dir, "mod.usda"), "w", encoding="utf-8", newline="\n") as handle:
        handle.write(usda)
    written = set(os.path.splitext(n)[0] for n in os.listdir(tex_dir))
    referenced = set(sha for _, _, sha, _ in TEXREF_RE.findall(usda))
    if written != referenced:
        raise Refused("the mod's textures and mod.usda's references differ")
    report["overrides"] = len(overrides)
    report["shaders"] = sorted(set(re.findall(r"info:mdl:sourceAsset = @([^@]+)@", usda)))
    return usda, overrides, report


def write_addon(gma, index: dict, index_path: str, usda: str, overrides: list, report: dict, out: str,
                profile: dict, map_name: str, args, t0: float) -> dict:
    lights = [convert_light(light) for light in (index.get("lighting") or {}).get("lights", [])]
    layer_defaults = read_layer_defaults(args.defaults_layer)
    runtime_defaults = profile.get("runtime_defaults", {})
    defaults = {}
    for key, _ in profile.get("remix", []):
        value = layer_defaults.get(key, runtime_defaults.get(key))
        if value is None:
            raise Refused(f"no default for {key}: add it to the profile's runtime_defaults")
        defaults[key] = value
    tint = None
    if profile.get("tint"):
        tint = {"keys": list(profile["tint"]["keys"]), "recompute": bool(profile["tint"].get("recompute")),
                "materials": material_list(profile["tint"]["materials"], index)}
    categories = []
    for category in profile.get("categories", []):
        names = material_list(category["materials"], index)
        if names:
            categories.append({"name": category["name"], "flag": CATEGORY_FLAGS[category["flag"]], "materials": names})
    hashes = {name: ["0x" + a.upper() for a in aliases] for name, aliases in sorted(((index.get("startup") or {}).get("hashes") or {}).items())}
    override_set = set(overrides)
    unreplaced = sorted(a for aliases in hashes.values() for a in aliases if a[2:] not in override_set)
    if unreplaced:
        raise Refused(f"{len(unreplaced)} hash aliases have no override in mod.usda, first {unreplaced[0]}")

    lua = {
        "schema": 1, "id": profile["addon"], "title": profile["title"], "map": map_name, "prefix": profile["prefix"],
        "global": profile["global"], "sky_owner": bool(profile.get("sky_owner")), "fog_owner": bool(profile.get("fog_owner")),
        "sky_keys": list(profile.get("sky_keys", ["rtx.skyMode"])), "clear_light2rtx": bool(profile.get("clear_light2rtx", True)),
        "remix": [list(pair) for pair in profile.get("remix", [])], "defaults": defaults,
        "engine": [list(pair) for pair in profile.get("engine", [])], "lights": lights,
        "hooks_off": [list(pair) for pair in profile.get("hooks_off", [])], "hashes": "hashes.lua",
    }
    if tint:
        lua["tint"] = tint
    if categories:
        lua["categories"] = categories
    shell = profile.get("shell")
    if shell:
        lua["shell"] = {"min": list(shell["min"]), "max": list(shell["max"]), "material": profile["addon"] + "/shell"}

    mod_dir = os.path.join(out, "mod", profile["mod"])
    addon_dir = os.path.join(out, "addon", profile["addon"])
    lua_dir = os.path.join(addon_dir, "lua", profile["addon"])
    os.makedirs(os.path.join(addon_dir, "lua", "autorun"))
    os.makedirs(lua_dir)
    if shell:
        material_dir = os.path.join(addon_dir, "materials", profile["addon"])
        os.makedirs(material_dir)
        with open(os.path.join(material_dir, "shell.vtf"), "wb") as handle:
            handle.write(shell_vtf(shell["color"]))
        with open(os.path.join(material_dir, "shell.vmt"), "w", encoding="ascii", newline="\n") as handle:
            handle.write(shell_vmt(profile["addon"] + "/shell"))
    names = {"title": profile["title"], "map": map_name, "mod": profile["mod"], "addon": profile["addon"], "prefix": profile["prefix"]}
    with open(os.path.join(addon_dir, "lua", "autorun", profile["addon"] + ".lua"), "w", encoding="utf-8", newline="\n") as handle:
        handle.write(AUTORUN.format(**names))
    shutil.copyfile(os.path.join(TEMPLATE_DIR, "runtime.lua"), os.path.join(lua_dir, "runtime.lua"))
    with open(os.path.join(lua_dir, "profile.lua"), "w", encoding="utf-8", newline="\n") as handle:
        handle.write(f"-- {profile['title']}: what runtime.lua does on {map_name}. Written by astra_companion.py from\n"
                     f"-- {os.path.basename(args.profile)} and the companion's {index_path}; do not edit, convert again.\n")
        handle.write("return " + lua_value(lua) + "\n")
    with open(os.path.join(lua_dir, "hashes.lua"), "w", encoding="utf-8", newline="\n") as handle:
        handle.write(f"-- The texture hashes the mod rtx-remix/mods/{profile['mod']} replaces, per material (the\n"
                     f"-- {profile['prefix']}_status coverage check). Written by astra_companion.py.\n")
        handle.write("return " + lua_value(hashes) + "\n")
    addon_json = dict(profile.get("addon_json") or {})
    addon_json.setdefault("title", profile["title"])
    with open(os.path.join(addon_dir, "addon.json"), "w", encoding="utf-8", newline="\n") as handle:
        json.dump(addon_json, handle, indent=4, ensure_ascii=True)
        handle.write("\n")

    report.update({
        "materials": len(index["materials"]), "hash_aliases": sum(len(a) for a in hashes.values()),
        "lights": len(lights), "lights_left_out": (index.get("lighting") or {}).get("unsupported", []),
        "remix_settings": len(lua["remix"]), "tint_materials": len(tint["materials"]) if tint else 0,
        "categories": {c["name"]: len(c["materials"]) for c in categories}, "hooks_off": len(lua["hooks_off"]),
        "shell": lua.get("shell"),
        "mod_bytes": report["texture_bytes"] + len(usda.encode("utf-8")),
        "bc4_converted": len(report["bc4"]), "bc4_kept_bc7": len(report["bc4_kept"]),
        "bc4_saved_bytes": sum(e["bytes_before"] - e["bytes_after"] for e in report["bc4"]),
        "bc4_min_psnr_db": min((e["psnr_db"] for e in report["bc4"]), default=None),
        "seconds": round(time.time() - t0, 1), "addon": addon_dir, "mod": mod_dir,
    })
    with open(os.path.join(out, "report.json"), "w", encoding="utf-8", newline="\n") as handle:
        json.dump(report, handle, indent=2, ensure_ascii=True)
        handle.write("\n")
    return report


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description="Convert an Astra RTX companion .gma into a content pack's add-on and Remix mod.")
    parser.add_argument("--gma", required=True, help="the companion archive (the Workshop item's .gma), or a folder it was extracted to")
    parser.add_argument("--mod-from", help="take the mod from this earlier conversion of the companion and read only its manifests "
                        "(when the archive or its payloads are gone); the add-on is written again")
    parser.add_argument("--profile", required=True, help="the map's profile JSON (astra_companion/<map>.json)")
    parser.add_argument("--out", required=True, help="build folder: addon/<addon>/, mod/<mod>/, report.json")
    parser.add_argument("--bc4", action="store_true", help="re-encode BC7 maps Remix reads one channel of as BC4 (needs numpy and Pillow)")
    parser.add_argument("--bc4-min-psnr", type=float, default=36.0,
                        help="keep a map's BC7 when its BC4 falls below this PSNR on any mip of 16 px or more (dB, default 36)")
    parser.add_argument("--defaults-layer", default=DEFAULT_LAYER, help="the RTX package's Remix defaults layer (restore values)")
    parser.add_argument("--force", action="store_true", help="replace an earlier conversion in --out")
    args = parser.parse_args(argv)
    try:
        report = convert(args)
    except (Refused, OSError, KeyError, ValueError) as error:
        print(f"astra_companion: {error}", file=sys.stderr)
        return 1
    print(json.dumps({k: v for k, v in report.items() if k not in ("bc4", "bc4_kept")}, indent=2, ensure_ascii=True))
    return 0


if __name__ == "__main__":
    sys.exit(main())
