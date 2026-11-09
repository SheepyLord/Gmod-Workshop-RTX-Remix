"""Split a map remaster's Remix mod into Workshop-sized parts and fit each part under a byte budget.

A remix-map-pbr remaster's Remix mod (mod.usda; materials.usda with one over "mat_<HASH>" block per
texture hash; textures/*.dds) can be far larger than one Workshop item may be (about 4 GB). This script
writes one mod folder per part, each under its budget:

  split    each material block goes to the first --part whose maps use its texture (the pipeline's
           work/textures.json and work/inventory.json say which materials, so which maps, use it).
           Blocks no part's maps use are left out; blocks with no map information go to the first part.
  shrink   without re-encoding: every DDS holds its full mip chain, so a map at half size is the same
           file without its top mip (the encoder made each mip from the full-size image). A constant
           BC4/BC5 map (every 4x4 block the same, one value in it) keeps only its 16 px tail and
           samples exactly as before. Byte-identical files are written once; the blocks point at that
           copy.
  fit      cuts until the part fits, tier by tier; a tier is applied to its least important textures
           first, and a later tier only when the earlier ones were not enough:
             1 aux        roughness, metallic and height maps at half the size of their albedo
             2 props      model (prop) textures at most twice their source size
             3 world      world textures above 2048 at 2048
             4 prop-nrm   model normal maps at half the size of their albedo
             5 world-nrm  world normal maps at half the size of their albedo
             6 halve      every texture halved again, round by round, down to --min-side
           Least important: for models the fewest instances, for world textures the smallest share of
           the world's area (models before world textures where a tier has both).
  write    <part folder> with mod.usda (its own mod name), materials.usda (its blocks, in source
           order) and textures/; nothing else, so the folder is what package_content.py --mod takes.

Usage:

    python -I fit_map_mod.py --mod <mod folder> --textures-json <work\\textures.json>
        --inventory-json <work\\inventory.json> --part <folder>=<map>[,<map>...] [--part ...]
        [--budget BYTES] [--part-budget <part name>=BYTES] [--mod-name <part name>=<text>]
        [--min-side N] [--report FILE] [--dry-run] [--force]

The last component of a part folder is the deployed mod name (rtx-remix\\mods\\<name>). The budget
counts every file the part writes (default 3,850,000,000 bytes, leaving room for an add-on and the
archive's index under 4 GB). Exit codes: 0 written (or planned, --dry-run), 1 refused or a budget out
of reach (nothing written), 2 bad command line.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import struct
import sys
import time

DEFAULT_BUDGET = 3_850_000_000
CONST_SIDE = 16
PARTIAL = 1 << 16

# DXGI formats and FourCCs of block-compressed DDS: block bytes.
DXGI_BLOCK = {70: 8, 71: 8, 72: 8, 73: 16, 74: 16, 75: 16, 76: 16, 77: 16, 78: 16, 79: 8, 80: 8, 81: 8,
              82: 16, 83: 16, 84: 16, 94: 16, 95: 16, 96: 16, 97: 16, 98: 16, 99: 16}
DXGI_NAME = {70: "BC1", 71: "BC1", 72: "BC1", 73: "BC2", 74: "BC2", 75: "BC2", 76: "BC3", 77: "BC3", 78: "BC3",
             79: "BC4", 80: "BC4", 81: "BC4S", 82: "BC5", 83: "BC5", 84: "BC5S", 94: "BC6H", 95: "BC6H",
             96: "BC6H", 97: "BC7", 98: "BC7", 99: "BC7"}
FOURCC = {b"DXT1": ("BC1", 8), b"DXT2": ("BC2", 16), b"DXT3": ("BC2", 16), b"DXT4": ("BC3", 16),
          b"DXT5": ("BC3", 16), b"ATI1": ("BC4", 8), b"BC4U": ("BC4", 8), b"ATI2": ("BC5", 16),
          b"BC5U": ("BC5", 16)}

KIND = {"diffuse_texture": "albedo", "albedo_texture": "albedo", "normalmap_texture": "normal",
        "emissive_mask_texture": "emissive", "reflectionroughness_texture": "aux", "metallic_texture": "aux",
        "height_texture": "aux"}

TIERS = ("aux", "props", "world", "prop-nrm", "world-nrm", "halve")
TIER_TEXT = {
    "aux": "roughness, metallic and height maps at half the size of their albedo",
    "props": "model textures at most twice their source size",
    "world": "world textures above 2048 at 2048",
    "prop-nrm": "model normal maps at half the size of their albedo",
    "world-nrm": "world normal maps at half the size of their albedo",
    "halve": "every texture halved again, down to the floor",
}

MAT = re.compile(r'^\s*over "mat_([0-9A-Fa-f]{16})"')
REF = re.compile(r"@\./textures/([^@]+)@")
ASSET = re.compile(r"@([^@]*)@")


class Refused(Exception):
    pass


def read_text(path: str) -> str:
    with open(path, encoding="utf-8") as f:
        return f.read()


def read_json(path: str):
    with open(path, encoding="utf-8") as f:
        return json.load(f)


# --- DDS ------------------------------------------------------------------------------------------

class Dds:
    """Header facts of one block-compressed DDS file."""

    def __init__(self, path: str):
        self.path = path
        self.name = os.path.basename(path)
        self.size = os.path.getsize(path)
        with open(path, "rb") as f:
            head = f.read(148)
        if len(head) < 128 or head[:4] != b"DDS " or struct.unpack_from("<I", head, 4)[0] != 124:
            raise Refused(f"{self.name}: not a DDS file")
        self.height, self.width = struct.unpack_from("<II", head, 12)
        depth = struct.unpack_from("<I", head, 24)[0]
        self.mips = max(1, struct.unpack_from("<I", head, 28)[0])
        caps2 = struct.unpack_from("<I", head, 112)[0]
        fourcc = head[84:88]
        if fourcc == b"DX10":
            if len(head) < 148:
                raise Refused(f"{self.name}: truncated DX10 header")
            dxgi, dim, misc, array = struct.unpack_from("<IIII", head, 128)
            if dxgi not in DXGI_BLOCK:
                raise Refused(f"{self.name}: DXGI format {dxgi} is not block-compressed")
            if array != 1 or dim != 3 or misc & 4:
                raise Refused(f"{self.name}: only single 2D textures are supported")
            self.fmt, self.block, self.offset = DXGI_NAME[dxgi], DXGI_BLOCK[dxgi], 148
        elif fourcc in FOURCC:
            self.fmt, self.block = FOURCC[fourcc]
            self.offset = 128
        else:
            raise Refused(f"{self.name}: format {fourcc!r} is not block-compressed")
        if caps2 & 0x200 or (depth > 1 and caps2 & 0x200000):
            raise Refused(f"{self.name}: cube maps and volume textures are not supported")
        if self.size != self.offset + self.levels_bytes(0):
            raise Refused(f"{self.name}: {self.size} bytes, but its header describes "
                          f"{self.offset + self.levels_bytes(0)}")
        self.side = max(self.width, self.height)
        self.constant = None   # (block bytes) when every block of the top mip is one constant block

    def level_dims(self, i: int):
        return max(1, self.width >> i), max(1, self.height >> i)

    def level_bytes(self, i: int) -> int:
        w, h = self.level_dims(i)
        return ((w + 3) // 4) * ((h + 3) // 4) * self.block

    def levels_bytes(self, drop: int) -> int:
        return sum(self.level_bytes(i) for i in range(drop, self.mips))

    def bytes_after(self, drop: int) -> int:
        return self.offset + self.levels_bytes(drop)

    def max_drop(self) -> int:
        return self.mips - 1

    def drop_for_side(self, side: int) -> int:
        """Smallest drop whose larger side is at most `side` (bounded by the mip chain)."""
        d = 0
        while d < self.max_drop() and (self.side >> d) > side:
            d += 1
        return d

    def reduced(self, drop: int) -> bytes:
        with open(self.path, "rb") as f:
            head = bytearray(f.read(self.offset))
            f.seek(self.offset + sum(self.level_bytes(i) for i in range(drop)))
            data = f.read()
        if drop:
            w, h = self.level_dims(drop)
            struct.pack_into("<II", head, 12, h, w)
            struct.pack_into("<I", head, 20, self.level_bytes(drop))
            struct.pack_into("<I", head, 28, self.mips - drop)
        out = bytes(head) + data
        if len(out) != self.bytes_after(drop):
            raise Refused(f"{self.name}: short read")
        return out


def bc4_values(block: bytes):
    """The 16 values of one unsigned BC4 block."""
    e0, e1 = block[0], block[1]
    if e0 > e1:
        pal = [e0, e1] + [((7 - i) * e0 + i * e1) / 7.0 for i in range(1, 7)]
    else:
        pal = [e0, e1] + [((5 - i) * e0 + i * e1) / 5.0 for i in range(1, 5)] + [0, 255]
    bits = int.from_bytes(block[2:8], "little")
    return [pal[(bits >> (3 * j)) & 7] for j in range(16)]


def check_constant(d: Dds):
    """Mark a BC4/BC5 map whose top mip is one repeated block holding one value per channel."""
    if d.fmt not in ("BC4", "BC5"):
        return
    n = d.level_bytes(0) // d.block
    with open(d.path, "rb") as f:
        f.seek(d.offset)
        first = f.read(min(n, 256) * d.block)
        blk = first[:d.block]
        if first != blk * (len(first) // d.block):
            return
        f.seek(d.offset)
        top = f.read(n * d.block)
    if top != blk * n:
        return
    halves = [blk[i:i + 8] for i in range(0, d.block, 8)]
    if all(len(set(bc4_values(h))) == 1 for h in halves):
        d.constant = blk


def content_hash(path: str, offset: int, limit=None) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        f.seek(offset)
        left = limit
        while True:
            chunk = f.read(1 << 20 if left is None else min(1 << 20, left))
            if not chunk:
                break
            h.update(chunk)
            if left is not None:
                left -= len(chunk)
                if left <= 0:
                    break
    return h.hexdigest()


# --- USDA -----------------------------------------------------------------------------------------

class Block:
    def __init__(self, lines, index):
        self.lines = lines
        self.index = index
        self.hash = None
        self.comment = ""
        for ln in lines:
            m = MAT.match(ln)
            if m:
                self.hash = m.group(1).upper()
                break
        if lines and lines[0].lstrip().startswith("#"):
            self.comment = lines[0].strip()[1:].strip()
        self.refs = []          # (input, file)
        for ln in lines:
            for m in REF.finditer(ln):
                inp = re.search(r"inputs:(\w+)", ln)
                self.refs.append((inp.group(1) if inp else "?", m.group(1)))
        for ln in lines:
            for m in ASSET.finditer(ln):
                a = m.group(1)
                if a.startswith("./") and not a.startswith("./textures/"):
                    raise Refused(f"mat_{self.hash}: asset {a} outside textures/ is not supported")
        # filled by planning
        self.name = None
        self.maps = set()
        self.world = False
        self.share = 0.0
        self.inst = 0
        self.src = 0
        self.known = False
        self.main_cap = None
        self.normal_cap = None
        self.aux_half = False

    def text(self, rename) -> str:
        out = []
        for ln in self.lines:
            out.append(REF.sub(lambda m: "@./textures/" + rename.get(m.group(1), m.group(1)) + "@", ln))
        return "\n".join(out)


def parse_materials(text: str):
    """(prefix, blocks, suffix) of a build_mod.py materials.usda."""
    lines = text.split("\n")
    starts = [i for i, ln in enumerate(lines) if MAT.match(ln)]
    if not starts:
        raise Refused("materials.usda has no over \"mat_<HASH>\" blocks")
    blocks, spans = [], []
    for k, s in enumerate(starts):
        b = s
        if b > 0 and lines[b - 1].lstrip().startswith("#"):
            b -= 1
        depth, e, opened = 0, s, False
        while e < len(lines):
            depth += lines[e].count("{") - lines[e].count("}")
            if "{" in lines[e]:
                opened = True
            if opened and depth == 0:
                break
            e += 1
        if e >= len(lines) or not opened:
            raise Refused(f"materials.usda: block at line {s + 1} is not closed")
        if k + 1 < len(starts) and e >= starts[k + 1]:
            raise Refused(f"materials.usda: block at line {s + 1} overlaps the next one")
        spans.append((b, e))
        blocks.append(Block(lines[b:e + 1], k))
    prefix = "\n".join(lines[:spans[0][0]])
    suffix = "\n".join(lines[spans[-1][1] + 1:])
    for (b0, e0), (b1, _) in zip(spans, spans[1:]):
        if any(ln.strip() for ln in lines[e0 + 1:b1]):
            raise Refused(f"materials.usda: unexpected text between blocks at line {e0 + 2}")
    return prefix, blocks, suffix


# --- plan -----------------------------------------------------------------------------------------

class Unit:
    """One output file of a part: a group of byte-identical source files (or equal constants)."""

    def __init__(self, dds: Dds, key):
        self.dds = dds
        self.key = key
        self.files = [dds.name]
        self.users = []      # (block, kind)
        self.drop = 0
        self.bytes = dds.size

    @property
    def name(self):
        return self.files[0]


class Part:
    def __init__(self, folder: str, maps, index=0):
        self.folder = os.path.abspath(folder)
        self.name = os.path.basename(self.folder.rstrip("\\/"))
        self.maps = maps
        self.index = index
        self.blocks = []
        self.units = []
        self.unit_of = {}
        self.budget = DEFAULT_BUDGET
        self.mod_name = None
        self.tiers = []
        self.text_bytes = 0


def albedo_side(block, units_by_file):
    sides = [units_by_file[f].dds.side for i, f in block.refs if KIND.get(i) == "albedo"]
    side = max(sides) if sides else 0
    if block.main_cap is not None and side:
        side = min(side, block.main_cap)
    return side


def required_side(block, kind, unit, units_by_file, floor):
    side = unit.dds.side
    target = side if block.main_cap is None else min(side, block.main_cap)
    if kind == "aux" and block.aux_half:
        target = min(target, (albedo_side(block, units_by_file) or side) // 2)
    if kind == "normal" and block.normal_cap is not None:
        target = min(target, block.normal_cap)
    return max(target, min(floor, side))


def unit_drop(unit: Unit, units_by_file, floor):
    d = unit.dds
    if d.constant is not None:
        return d.drop_for_side(CONST_SIDE)
    need = max(required_side(b, k, unit, units_by_file, floor) for b, k in unit.users)
    return d.drop_for_side(need)


def importance(block):
    """Sort key, least important first: models by instances, then world textures by area share."""
    if block.world or not block.known:
        return (1, block.share, block.index)
    return (0, block.inst, block.index)


def tier_steps(tier, part, units_by_file, floor):
    blocks = sorted(part.blocks, key=importance)

    def has(block, kind):
        return any(KIND.get(i, "albedo") == kind for i, _ in block.refs)

    steps = []
    if tier == "aux":
        for b in blocks:
            if has(b, "aux") and not b.aux_half:
                steps.append((b, lambda b=b: setattr(b, "aux_half", True)))
    elif tier == "props":
        for b in blocks:
            if b.known and not b.world and b.src:
                cap = max(2 * b.src, floor)
                if albedo_side(b, units_by_file) > cap:
                    steps.append((b, lambda b=b, cap=cap: setattr(b, "main_cap", cap)))
    elif tier == "world":
        for b in blocks:
            if (b.world or not b.known) and albedo_side(b, units_by_file) > 2048:
                steps.append((b, lambda b=b: setattr(b, "main_cap", 2048)))
    elif tier in ("prop-nrm", "world-nrm"):
        want_world = tier == "world-nrm"
        for b in blocks:
            if (b.world or not b.known) == want_world and has(b, "normal"):
                cap = max(albedo_side(b, units_by_file) // 2, floor)
                if b.normal_cap is None or b.normal_cap > cap:
                    steps.append((b, lambda b=b, cap=cap: setattr(b, "normal_cap", cap)))
    elif tier == "halve":
        for b in blocks:
            side = albedo_side(b, units_by_file)
            if side > floor:
                cap = max(side // 2, floor)
                steps.append((b, lambda b=b, cap=cap: setattr(b, "main_cap", cap)))
    return steps


def fit_part(part: Part, floor: int):
    units_by_file = part.unit_of
    users_of = {}
    for u in part.units:
        for b, _ in u.users:
            users_of.setdefault(id(b), set()).add(u)
    total = part.text_bytes
    for u in part.units:
        u.drop = unit_drop(u, units_by_file, floor)
        u.bytes = u.dds.bytes_after(u.drop)
        total += u.bytes
    start = total
    part.tiers = [{"tier": "lossless", "text": "constant maps to a 16 px tail, byte-identical files once",
                   "bytes_after": total}]
    if total <= part.budget:
        return total, start
    for tier in TIERS:
        rounds = 0
        while True:
            steps = tier_steps(tier, part, units_by_file, floor)
            if not steps:
                break
            rounds += 1
            applied, before = 0, total
            for b, apply in steps:
                apply()
                for u in users_of.get(id(b), ()):
                    nd = unit_drop(u, units_by_file, floor)
                    if nd != u.drop:
                        nb = u.dds.bytes_after(nd)
                        total += nb - u.bytes
                        u.drop, u.bytes = nd, nb
                applied += 1
                if total <= part.budget:
                    break
            part.tiers.append({"tier": tier, "text": TIER_TEXT[tier], "round": rounds, "steps": len(steps),
                               "applied": applied, "saved": before - total, "bytes_after": total})
            if total <= part.budget or tier != "halve":
                break
            if before == total:
                break
        if total <= part.budget:
            return total, start
    raise Refused(f"{part.name}: {total:,} bytes after every cut, over its budget of {part.budget:,}")


# --- main -----------------------------------------------------------------------------------------

def load_usage(textures_json, inventory_json):
    tex = read_json(textures_json)
    inv = read_json(inventory_json)
    mats = inv.get("materials", {})
    by_hash, by_name = {}, {}
    for name, t in tex.items():
        maps = set()
        for m in t.get("materials", []):
            maps.update(mats.get(m, {}).get("maps", []))
        info = {"name": name, "maps": maps, "world": bool(t.get("world")), "share": float(t.get("share") or 0),
                "inst": int(t.get("instances") or 0), "src": max(int(t.get("w") or 0), int(t.get("h") or 0))}
        by_name[name.lower()] = info
        for h in t.get("hashes", []):
            by_hash.setdefault(h.upper().replace("0X", "").rjust(16, "0"), []).append(info)
    return by_hash, by_name


def merge_info(infos):
    out = {"name": infos[0]["name"], "maps": set(), "world": False, "share": 0.0, "inst": 0, "src": 0}
    for i in infos:
        out["maps"] |= i["maps"]
        out["world"] |= i["world"]
        out["share"] = max(out["share"], i["share"])
        out["inst"] = max(out["inst"], i["inst"])
        out["src"] = max(out["src"], i["src"])
    return out


def build_units(part: Part, tex_dir: str, cache: dict):
    files = {}
    for b in part.blocks:
        for inp, f in b.refs:
            files.setdefault(f, []).append((b, KIND.get(inp, "albedo")))
    groups = {}
    for f in sorted(files):
        p = os.path.join(tex_dir, f)
        if not os.path.isfile(p):
            raise Refused(f"textures/{f} is referenced but missing")
        if f not in cache:
            d = Dds(p)
            check_constant(d)
            part_hash = content_hash(p, d.offset, PARTIAL)
            cache[f] = (d, part_hash)
        d, part_hash = cache[f]
        if d.constant is not None:
            key = ("const", d.fmt, d.constant, d.level_dims(d.drop_for_side(CONST_SIDE)),
                   d.mips - d.drop_for_side(CONST_SIDE))
        else:
            key = ("data", d.size, d.fmt, part_hash)
        groups.setdefault(key, []).append(d)
    units = []
    for key, members in groups.items():
        if key[0] == "data" and len(members) > 1:
            full = {}
            for d in members:
                full.setdefault(content_hash(d.path, 0), []).append(d)
            subgroups = [(key + (h,), ms) for h, ms in full.items()]
        else:
            subgroups = [(key, members)]
        for k, ms in subgroups:
            u = Unit(ms[0], k)
            u.files = [d.name for d in ms]
            for d in ms:
                u.users.extend(files[d.name])
                part.unit_of[d.name] = u
            units.append(u)
    part.units = sorted(units, key=lambda u: u.name)


def mod_usda_text(src_text: str, part: Part, source_name: str) -> str:
    sub = re.search(r"subLayers\s*=\s*\[(.*?)\]", src_text, re.S)
    if not sub or ASSET.findall(sub.group(1)) != ["./materials.usda"]:
        raise Refused("mod.usda: only a mod whose one sublayer is ./materials.usda is supported")
    text = src_text
    if part.mod_name:
        if not re.search(r'string lightspeed_mod_name = "[^"]*"', text):
            raise Refused("mod.usda has no lightspeed_mod_name to replace")
        text = re.sub(r'(string lightspeed_mod_name = )"[^"]*"', lambda m: m.group(1) + json.dumps(part.mod_name),
                      text, count=1)
    maps = " and ".join(sorted(part.maps))
    own = re.search(r'string lightspeed_mod_name = "([^"]*)"', src_text)
    title = part.mod_name or (own.group(1) if own else source_name)
    doc = (f"{title}: the materials {maps} uses that no earlier part holds, fitted for "
           f"the Workshop by fit_map_mod.py from the {source_name} build; edits are overwritten." if part.index else
           f"{title}: the materials {maps} uses, fitted for the Workshop by fit_map_mod.py "
           f"from the {source_name} build; edits are overwritten.")
    if re.search(r'^\s*doc = "[^"]*"', text, re.M):
        text = re.sub(r'^(\s*doc = )"[^"]*"', lambda m: m.group(1) + json.dumps(doc), text, count=1, flags=re.M)
    return text


def materials_text(prefix: str, blocks, suffix: str, part: Part) -> str:
    rename = {}
    for u in part.units:
        for f in u.files:
            rename[f] = u.name
    head = re.sub(r'^(\s*doc = )"([^"]*)"',
                  lambda m: m.group(1) + json.dumps(m.group(2) + f"; part {part.name}, fitted by fit_map_mod.py"),
                  prefix, count=1, flags=re.M)
    return head + "\n" + "\n\n".join(b.text(rename) for b in blocks) + "\n" + suffix


def safe_to_replace(folder: str) -> bool:
    for root, dirs, files in os.walk(folder):
        rel = os.path.relpath(root, folder)
        if rel == ".":
            if set(dirs) - {"textures"} or set(files) - {"mod.usda", "materials.usda"}:
                return False
        elif rel == "textures":
            if dirs or any(not f.lower().endswith(".dds") for f in files):
                return False
        else:
            return False
    return True


def write_part(part: Part, prefix, suffix, mod_text, force):
    if os.path.exists(part.folder):
        if not force:
            raise Refused(f"{part.folder} exists (use --force to replace a folder this script wrote)")
        if not safe_to_replace(part.folder):
            raise Refused(f"{part.folder} holds files this script does not write; not replacing it")
    tmp = f"{part.folder}.partial-{os.getpid()}"
    if os.path.exists(tmp):
        shutil.rmtree(tmp)
    os.makedirs(os.path.join(tmp, "textures"))
    written = 0
    try:
        for u in part.units:
            data = u.dds.reduced(u.drop)
            if len(data) != u.bytes:
                raise Refused(f"{u.name}: wrote {len(data)} bytes, planned {u.bytes}")
            with open(os.path.join(tmp, "textures", u.name), "wb") as f:
                f.write(data)
            written += len(data)
        for name, text in (("mod.usda", mod_text),
                           ("materials.usda", materials_text(prefix, part.blocks, suffix, part))):
            data = text.encode("utf-8")
            with open(os.path.join(tmp, name), "wb") as f:
                f.write(data)
            written += len(data)
        verify_part(tmp, part)
        if os.path.exists(part.folder):
            shutil.rmtree(part.folder)
        os.replace(tmp, part.folder)
    except BaseException:
        shutil.rmtree(tmp, ignore_errors=True)
        raise
    return written


def verify_part(folder: str, part: Part):
    text = read_text(os.path.join(folder, "materials.usda"))
    _, blocks, _ = parse_materials(text)
    if [b.hash for b in blocks] != [b.hash for b in part.blocks]:
        raise Refused(f"{part.name}: the written materials.usda lost or reordered blocks")
    refs = {f for b in blocks for _, f in b.refs}
    have = set(os.listdir(os.path.join(folder, "textures")))
    if refs - have:
        raise Refused(f"{part.name}: missing textures {sorted(refs - have)[:3]}")
    if have - refs:
        raise Refused(f"{part.name}: unreferenced textures {sorted(have - refs)[:3]}")
    for f in have:
        d = Dds(os.path.join(folder, "textures", f))
        u = part.unit_of[f]
        if d.side != max(1, u.dds.side >> u.drop) or d.mips != u.dds.mips - u.drop:
            raise Refused(f"{part.name}: {f} came out {d.width}x{d.height} with {d.mips} mips")


def parse_args(argv):
    ap = argparse.ArgumentParser(description="Split a map remaster's Remix mod into parts that fit a budget.")
    ap.add_argument("--mod", required=True, help="the remaster's mod folder (mod.usda, materials.usda, textures)")
    ap.add_argument("--textures-json", required=True, help="the pipeline's work/textures.json")
    ap.add_argument("--inventory-json", required=True, help="the pipeline's work/inventory.json")
    ap.add_argument("--part", action="append", required=True, metavar="FOLDER=MAP[,MAP]",
                    help="an output mod folder and the maps it serves, in order (repeatable)")
    ap.add_argument("--budget", type=float, default=DEFAULT_BUDGET, help="bytes per part (default 3.85e9)")
    ap.add_argument("--part-budget", action="append", default=[], metavar="NAME=BYTES")
    ap.add_argument("--mod-name", action="append", default=[], metavar="NAME=TEXT",
                    help="the part's lightspeed_mod_name (default: the source's)")
    ap.add_argument("--min-side", type=int, default=128, help="no map is cut below this side (default 128)")
    ap.add_argument("--report", help="write the plan and result as JSON")
    ap.add_argument("--dry-run", action="store_true", help="plan and report only")
    ap.add_argument("--force", action="store_true", help="replace part folders this script wrote before")
    return ap.parse_args(argv)


def main(argv=None) -> int:
    try:
        a = parse_args(argv)
    except SystemExit as e:
        return 2 if e.code else 0
    started = time.time()
    try:
        mod = os.path.abspath(a.mod)
        tex_dir = os.path.join(mod, "textures")
        for p in (os.path.join(mod, "mod.usda"), os.path.join(mod, "materials.usda"), tex_dir):
            if not os.path.exists(p):
                raise Refused(f"{p} is missing")
        parts, names = [], set()
        for spec in a.part:
            if "=" not in spec:
                raise Refused(f"--part {spec}: expected FOLDER=MAP[,MAP]")
            folder, maps = spec.rsplit("=", 1)
            p = Part(folder, {m.strip() for m in maps.split(",") if m.strip()}, len(parts))
            if not p.maps:
                raise Refused(f"--part {spec}: no maps")
            if not re.fullmatch(r"[A-Za-z0-9_.-]{1,64}", p.name):
                raise Refused(f"--part {spec}: the folder name {p.name!r} is not a valid mod name")
            if p.name.lower() in names:
                raise Refused(f"--part {spec}: two parts named {p.name}")
            try:
                overlap = os.path.commonpath([p.folder.lower(), mod.lower()]) in (mod.lower(), p.folder.lower())
            except ValueError:      # different drives
                overlap = False
            if overlap:
                raise Refused(f"--part {spec}: the output and the source mod overlap")
            names.add(p.name.lower())
            p.budget = int(a.budget)
            parts.append(p)
        by_name = {p.name.lower(): p for p in parts}
        for spec in a.part_budget:
            n, _, v = spec.partition("=")
            if n.lower() not in by_name or not v:
                raise Refused(f"--part-budget {spec}: no part named {n}")
            by_name[n.lower()].budget = int(float(v))
        for spec in a.mod_name:
            n, _, v = spec.partition("=")
            if n.lower() not in by_name or not v:
                raise Refused(f"--mod-name {spec}: no part named {n}")
            by_name[n.lower()].mod_name = v

        src_mod_text = read_text(os.path.join(mod, "mod.usda"))
        mat_text = read_text(os.path.join(mod, "materials.usda"))
        prefix, blocks, suffix = parse_materials(mat_text)
        by_hash, by_name_info = load_usage(a.textures_json, a.inventory_json)

        left_out, unknown = [], []
        for b in blocks:
            infos = by_hash.get(b.hash)
            if not infos and b.comment:
                nm = re.sub(r"\s*\([^)]*\)\s*$", "", b.comment).strip().lower()
                if nm in by_name_info:
                    infos = [by_name_info[nm]]
            if infos:
                info = merge_info(infos)
                b.name, b.maps, b.world = info["name"], info["maps"], info["world"]
                b.share, b.inst, b.src, b.known = info["share"], info["inst"], info["src"], True
            target = None
            for p in parts:
                if b.maps & p.maps:
                    target = p
                    break
            if not b.maps:
                unknown.append(b.hash)
                target = parts[0]
            if target is None:
                left_out.append(b.hash)
                continue
            target.blocks.append(b)

        cache, results = {}, []
        source_name = os.path.basename(mod.rstrip("\\/"))
        for p in parts:
            if not p.blocks:
                raise Refused(f"{p.name}: no material of its maps ({', '.join(sorted(p.maps))})")
            build_units(p, tex_dir, cache)
            mod_text = mod_usda_text(src_mod_text, p, source_name)
            p.text_bytes = len(mod_text.encode("utf-8")) + len(
                materials_text(prefix, p.blocks, suffix, p).encode("utf-8"))
            total, start = fit_part(p, a.min_side)
            src_bytes = sum(cache[f][0].size for b in p.blocks for f in {f for _, f in b.refs})
            results.append((p, mod_text, total, start))
            print(f"{p.name}: {len(p.blocks)} materials, {len(p.units)} files; source {src_bytes / 1e9:.3f} GB, "
                  f"lossless {start / 1e9:.3f} GB, fitted {total / 1e9:.3f} GB (budget {p.budget / 1e9:.3f} GB)")
            for t in p.tiers[1:]:
                print(f"  tier {t['tier']} (round {t['round']}): {t['applied']} of {t['steps']} textures, "
                      f"-{t['saved'] / 1e9:.3f} GB -> {t['bytes_after'] / 1e9:.3f} GB")
        unref = len(set(os.listdir(tex_dir)) - {f for b in blocks for _, f in b.refs})
        print(f"left out: {len(left_out)} materials of other maps; no map information: {len(unknown)} "
              f"(first part); unreferenced source files: {unref}")

        report = {"source": mod, "budget_default": int(a.budget), "min_side": a.min_side,
                  "left_out": left_out, "no_map_information": unknown, "unreferenced_source_files": unref,
                  "parts": []}
        for p, mod_text, total, start in results:
            report["parts"].append({
                "name": p.name, "folder": p.folder, "maps": sorted(p.maps), "budget": p.budget,
                "mod_name": p.mod_name, "materials": len(p.blocks), "files": len(p.units),
                "lossless_bytes": start, "planned_bytes": total, "tiers": p.tiers,
                "units": [{"file": u.name, "merged": u.files[1:], "format": u.dds.fmt,
                           "source": f"{u.dds.width}x{u.dds.height}",
                           "out": "{}x{}".format(*u.dds.level_dims(u.drop)), "drop": u.drop,
                           "source_bytes": u.dds.size, "bytes": u.bytes, "constant": u.dds.constant is not None,
                           "kinds": sorted({k for _, k in u.users}),
                           "materials": sorted({b.name or b.hash for b, _ in u.users})} for u in p.units]})
        if not a.dry_run:
            for p, mod_text, total, start in results:
                written = write_part(p, prefix, suffix, mod_text, a.force)
                if written != total:
                    raise Refused(f"{p.name}: wrote {written:,} bytes, planned {total:,}")
                for r in report["parts"]:
                    if r["name"] == p.name:
                        r["written_bytes"] = written
                print(f"wrote {p.folder} ({written:,} bytes)")
        report["seconds"] = round(time.time() - started, 1)
        if a.report:
            with open(a.report, "w", encoding="utf-8") as f:
                json.dump(report, f, indent=1)
        return 0
    except Refused as e:
        print(f"refused: {e}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
