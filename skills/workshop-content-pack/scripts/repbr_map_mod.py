"""Give another author's Remix map mod new PBR maps by material class, sized to fit one Workshop item.

    <rpai python> -I repbr_map_mod.py --mod <re-keyed full-size mod> --out <new mod folder>
        --source <map item> [--source <*_dir.vpk> ...] --rules <map rules.json>
        [--budget 3850000000] [--work <folder>] [--json <report>] [--plan-only]
        [--preview <folder> --only HASH|name,...] [--force]

For a mod whose maps came out of an AI pipeline run on 4x upscales (PBRFusion: PBRify's 1x normal and
roughness models on the upscaled albedo, so the relief is nearly flat and the roughness sits near 0.5). Per
material it keeps the author's albedo and makes new maps:

1. Names each material's game texture by its hash in the sources (retune_roughness.texture_names) and finds
   where the texture shows on the map (map_usage.usage: floor, wall and ceiling area, props).
2. Picks a class from the rules file (ordered regular expressions on the texture path; per-hash overrides).
   A material whose albedo lies outside SubUSDs (the author's CC0 scans) is class "scan" unless a rule says
   otherwise; one no source names keeps its maps.
3. Plans every texture's size under --budget: each starts at 256 px (or less, if smaller) and the
   doubling with the most weight per byte goes first (weight = map_usage.importance x the class's weight x
   the role's: albedo 1, normal 0.8, roughness 0.3, height 0.25, divided by the doublings already given),
   up to the author's size and --max-side. Author's DDS files are cut by leaving out top mips, as fit_mod.py.
4. Runs PBRify's 1x NormalV3, RoughnessV2 and Height models (rpai's ModelRunner) on the albedo at the game
   texture's scale: twice the source's side, 512-2048 px, with wrap-around padding for world textures, so a
   1x model sees features at the size it was trained on. Cached in --work/ai.
5. Composes each map at its planned size from the class's recipe (see RECIPE below): the AI normal plus
   relief from the albedo's fine detail, scaled to the class's mean slope; the AI roughness normalised to its
   2nd-98th percentile and mapped into the class's range, rougher in cavities, glossier where the VMT's
   envmap mask is high, with large soft smudges on polished floors; a height map and displace_in on world
   floors and walls of the classes that ask for it; a metallic constant. The albedo gets the game texture's
   fine grain back where the upscale smoothed it (retune_roughness.restore_grain).
6. Encodes with the RTX Remix Toolkit's NVTT exporter (rpai.dds: BC7 albedo, BC5 normals, BC4 roughness and
   height), rewrites the material inputs in a copy of the author's layers, copies every other file the
   layers reach, and checks that every reference resolves.

--plan-only prints the classes and the size plan; --preview writes PNGs of the --only materials (albedo,
normal, roughness, height side by side) without encoding.

Exit codes: 0 done; 1 refused (no mod.usda, a missing source, --out exists without --force, a reference that
does not resolve, the budget out of reach, no NVTT exporter); 2 bad command line.
"""
from __future__ import annotations

import argparse
import hashlib
import heapq
import io
import json
import math
import os
import re
import shutil
import sys
import time
from concurrent.futures import ThreadPoolExecutor

import numpy as np
from PIL import Image, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import fit_map_mod as F  # noqa: E402
import map_usage  # noqa: E402
import retune_roughness as R  # noqa: E402
import usd_refs  # noqa: E402

DEFAULT_BUDGET = 3_850_000_000
ROLE_WEIGHT = {"albedo": 1.0, "normal": 0.8, "roughness": 0.3, "height": 0.25, "metallic": 0.15, "other": 0.5}
INPUT_ROLE = {"diffuse_texture": "albedo", "albedo_texture": "albedo", "normalmap_texture": "normal",
              "reflectionroughness_texture": "roughness", "height_texture": "height",
              "metallic_texture": "metallic"}
BLOCK = {"BC1": 8, "BC4": 8, "BC2": 16, "BC3": 16, "BC5": 16, "BC6H": 16, "BC7": 16}
SLACK = 1 << 20   # room for the layers' edits
NEW_FORMAT = {"albedo": "BC7", "normal": "BC5", "roughness": "BC4", "height": "BC4"}
NEW_SUFFIX = {"albedo": "a", "normal": "n", "roughness": "r", "height": "h"}
GENERATED = ("normal", "roughness", "height")

# A class's recipe; the rules file may set any key per class. Classes "keep" (the author's maps), "scan"
# (the author's CC0 scans: their maps, sized) and "skip" (glass, lights, sky: untouched but sized) exist always.
RECIPE = {
    "rough": (0.55, 0.85),   # roughness range the AI roughness is mapped into
    "rough_from": "ai",      # "ai" or "albedo" (inverted luminance) or "flat" (the middle of the range)
    "normal": 0.06,          # target mean |xy| of the unit normals (0 = flat)
    "detail": 0.0,           # relief from the albedo's fine detail (slope gain on its high-pass)
    "height": 0.0,           # displace_in on world textures (0 = no height map)
    "cavity": 0.0,           # roughness added in the height's hollows (grout, cracks), 0-1
    "smudge": 0.0,           # amplitude of large soft roughness variation (polished floors)
    "envmask": 0.0,          # how far the VMT's base-alpha envmap mask lowers roughness, 0-1
    "metal": 0.0,            # metallic constant
    "grain": True,           # restore the game texture's grain where the upscale smoothed it
    "from_source": False,    # leave out the author's albedo: the game texture, upscaled 4x by PBRify UpscalerV4
    "set_if_present": None,  # {input: [type, literal]} changed where the author set that input (foliage scattering)
    "weight": 1.0,           # multiplies the importance in the size plan
    "max_side": None,        # caps every map of the class
}
WORK_MIN, WORK_MAX = 512, 2048
MIN_SIDE = 256


# ---- materials and rules ------------------------------------------------------------------------

HEAD = re.compile(r'(?:over|def)\s+(?:\w+\s+)?"(mat_[0-9A-Fa-f]{16})"')
INPUT = re.compile(r"(?:uniform\s+)?(asset|float|color3f|float3|bool|int|token)\s+inputs:(\w+)\s*=\s*"
                   r"(@[^@]*@|\([^)\r\n]*\)|[^\s(]+)")


def mod_materials(mod):
    """{HASH: {"layer": rel, "inputs": {name: value}}} from every text layer reached from mod.usda; asset
    values are paths relative to the mod ('' for @@)."""
    walk = usd_refs.walk(mod)
    out = {}
    for layer in walk.layers:
        if layer in walk.crate:
            continue
        with open(os.path.join(mod, layer), encoding="utf-8", errors="replace") as fh:
            text = fh.read()
        spans = material_spans(text)
        base = os.path.dirname(layer)
        for h, _start, _end in spans:
            out.setdefault(h, {"layer": layer, "inputs": {}})
        for m in INPUT.finditer(text):
            owner = next((h for h, start, end in spans if start < m.start() < end), None)
            if owner is None:
                continue
            val = m.group(3).strip()
            if val.startswith("@"):
                val = val[1:-1]
                val = os.path.normpath(os.path.join(base, val)).replace(os.sep, "/") if val else ""
            out[owner]["inputs"][m.group(2)] = val
    return out, walk


def material_spans(text):
    """[(HASH, open, close)] of every mat_<HASH> prim's body in a layer's text (usd_refs.prim_spans): an
    input belongs to the material whose braces hold it, not to the material before it in the file, so a mesh
    replacement's own material that follows a material's block stays out of it."""
    return [(name[4:].upper(), start, end) for name, _path, start, end in usd_refs.prim_spans(text)
            if re.fullmatch(r"mat_[0-9A-Fa-f]{16}", name)]


def load_rules(path):
    with open(path, encoding="utf-8") as fh:
        return load_rules_data(json.load(fh))


def load_rules_data(data):
    """(classes, (rules, scan_rules), overrides, skip_flags) from a rules file's data: {"classes": {name: recipe},
    "rules": [[regex, class], ...], "scan_rules": [...], "overrides": {HASH: class}, "skip_flags": [flag, ...]}."""
    classes = {"keep": {"keep": True}, "scan": {"keep": True}, "skip": {"keep": True}}
    for name, rec in data.get("classes", {}).items():
        classes[name] = rec
    for name, rec in classes.items():
        for k in rec:
            if k not in RECIPE and k not in ("keep", "note", "albedo"):
                raise ValueError("class %s: unknown key %s" % (name, k))
    rules = [(re.compile(p, re.I), c) for p, c in data.get("rules", [])]
    scan_rules = [(re.compile(p, re.I), c) for p, c in data.get("scan_rules", [])]
    for _p, c in rules + scan_rules:
        if c not in classes:
            raise ValueError("rule class %s has no recipe" % c)
    overrides = {k.upper(): v for k, v in data.get("overrides", {}).items()}
    for c in overrides.values():
        if c not in classes:
            raise ValueError("override class %s has no recipe" % c)
    skip_flags = set(data.get("skip_flags", []))
    return classes, (rules, scan_rules), overrides, skip_flags


def recipe(classes, cls):
    r = dict(RECIPE)
    r.update(classes[cls])
    return r


def classify(h, texture, inputs, rules, overrides, flags=(), skip_flags=()):
    """(class, why): a per-hash override; "keep" for a texture no source names; "skip" for a VMT flag in
    skip_flags; for the author's own assets (an albedo outside SubUSDs, mostly CC0 scans) the scan rules or
    "scan"; else the first rule whose pattern the texture path matches; else "keep"."""
    rules, scan_rules = rules if isinstance(rules, tuple) else (rules, [])
    if h in overrides:
        return overrides[h], "override"
    alb = inputs.get("diffuse_texture", "")
    if not texture:
        return "keep", "unnamed"
    hit = set(flags) & set(skip_flags)
    if hit:
        return "skip", "flag " + ",".join(sorted(hit))
    if alb and not alb.replace("\\", "/").startswith("SubUSDs/"):
        for pattern, cls in scan_rules:
            if pattern.search(texture):
                return cls, "scan rule"
        return "scan", "outside SubUSDs"
    for pattern, cls in rules:
        if pattern.search(texture):
            return cls, "rule"
    return "keep", "no rule"


# ---- size plan ----------------------------------------------------------------------------------

class Refused(Exception):
    pass


class Tex:
    """One planned texture: an author's DDS (sized by leaving out top mips) or a generated map. Its sides are
    the mip ladder full, full/2, ...; it starts at the smallest side not below MIN_SIDE."""

    def __init__(self, key, role, w, h, fmt, weight, src=None, max_side=None, mips=None, dds=None):
        self.key, self.role, self.w, self.h, self.fmt = key, role, w, h, fmt
        self.dds = dds
        self.weight = weight
        self.src = src            # author's file (relative), or None for a generated map
        self.full = max(w, h)
        n = mips or max(1, int(math.log2(self.full)) + 1)
        ladder = sorted({self.full >> k for k in range(n) if (self.full >> k) >= 1})
        cap = max_side or self.full
        self.ladder = [x for x in ladder if x <= cap] or ladder[:1]
        start = [x for x in self.ladder if x >= min(MIN_SIDE, self.full)]
        self.i = self.ladder.index(start[0]) if start else len(self.ladder) - 1
        self.level = 0

    @property
    def side(self):
        return self.ladder[self.i]

    def next_side(self):
        return self.ladder[self.i + 1] if self.i + 1 < len(self.ladder) else None

    def dims(self, side=None):
        s = (side or self.side) / self.full
        return max(1, round(self.w * s)), max(1, round(self.h * s))

    def drop(self):
        d = 0
        while (self.full >> d) > self.side:
            d += 1
        return d

    def cost(self, side=None):
        """Exact bytes: an author's file with its top mips left out, or a new DDS (DX10 header, full mip chain)."""
        side = side or self.side
        if getattr(self, "dds", None) is not None:
            d = 0
            while (self.full >> d) > side:
                d += 1
            return self.dds.bytes_after(d)
        w, h = self.dims(side)
        block, total = BLOCK.get(self.fmt, 16), 148
        while True:
            total += ((w + 3) // 4) * ((h + 3) // 4) * block
            if w == 1 and h == 1:
                return total
            w, h = max(1, w // 2), max(1, h // 2)


def plan_sizes(texes, budget, fixed):
    """Greedy: the doubling with the most weight per added byte first, until the budget is spent."""
    total = fixed + sum(t.cost() for t in texes)
    if total > budget:
        raise Refused("the budget is out of reach even at the smallest sizes: %d > %d" % (total, budget))
    heap = []

    def push(i, t):
        nxt = t.next_side()
        if nxt:
            gain = t.weight / (t.level + 1)
            extra = t.cost(nxt) - t.cost()
            heapq.heappush(heap, (-gain / max(extra, 1), i))
    for i, t in enumerate(texes):
        push(i, t)
    while heap:
        _, i = heapq.heappop(heap)
        t = texes[i]
        nxt = t.next_side()
        extra = t.cost(nxt) - t.cost()
        if total + extra > budget:
            continue
        total += extra
        t.i += 1
        t.level += 1
        push(i, t)
    return total


def texture_table(sources):
    """{hash: [VTF name as the source holds it, width, height]} for both hash functions."""
    import vtf_hash
    out = {}
    for src in sources:
        for name, blob in vtf_hash.iter_vtfs(src):
            try:
                v = vtf_hash.Vtf(blob)
                for x64, x3 in vtf_hash.texture_hashes(blob):
                    out.setdefault(x64, [name, v.w, v.h])
                    out.setdefault(x3, [name, v.w, v.h])
            except (ValueError, KeyError, IndexError):
                continue
    return out


# ---- AI maps ------------------------------------------------------------------------------------

def read_dds(path, side):
    """A DDS at its mip closest to and not below `side` (the larger dimension), as an RGBA image."""
    d = F.Dds(path)
    drop = 0
    while drop < d.max_drop() and (d.side >> (drop + 1)) >= side:
        drop += 1
    return Image.open(io.BytesIO(d.reduced(drop))).convert("RGBA")


def work_side(src_side, full):
    return int(min(full, max(WORK_MIN, min(WORK_MAX, 2 * (src_side or full // 4)))))


def run_ai(runner, config, img, wrap):
    """NormalV3, RoughnessV2 and Height on an RGB float image; wrap-around padding for tiling textures."""
    rgb = np.asarray(img.convert("RGB"), np.float32) / 255
    h, w = rgb.shape[:2]
    pad = max(16, min(h, w) // 8) if wrap else 0
    if pad:
        rgb = np.pad(rgb, ((pad, pad), (pad, pad), (0, 0)), mode="wrap")
    out = {}
    for role, model in (("normal", config.NORMAL_MODEL), ("roughness", config.ROUGHNESS_MODEL),
                        ("height", config.HEIGHT_MODEL)):
        a = runner.run(model, rgb)
        if pad:
            a = a[pad:pad + h, pad:pad + w]
        out[role] = a if role == "normal" else a.mean(axis=2)
    return out


def save_ai(ai_dir, key, maps):
    os.makedirs(ai_dir, exist_ok=True)
    Image.fromarray((np.clip(maps["normal"], 0, 1) * 255 + 0.5).astype(np.uint8), "RGB").save(
        os.path.join(ai_dir, key + "_normal.png"), compress_level=1)
    Image.fromarray((np.clip(maps["roughness"], 0, 1) * 255 + 0.5).astype(np.uint8), "L").save(
        os.path.join(ai_dir, key + "_rough.png"), compress_level=1)
    Image.fromarray((np.clip(maps["height"], 0, 1) * 65535 + 0.5).astype(np.uint16)).save(
        os.path.join(ai_dir, key + "_height.png"), compress_level=1)


def load_ai(ai_dir, key):
    p = {r: os.path.join(ai_dir, "%s_%s.png" % (key, r)) for r in ("normal", "rough", "height")}
    if not all(os.path.isfile(x) for x in p.values()):
        return None
    with Image.open(p["normal"]) as a, Image.open(p["rough"]) as b, Image.open(p["height"]) as c:
        return {"normal": np.asarray(a.convert("RGB"), np.float32) / 255 * 2 - 1,
                "roughness": np.asarray(b.convert("L"), np.float32) / 255,
                "height": np.asarray(c, np.float32) / 65535}



VTF_FOURCC = {13: b"DXT1", 14: b"DXT3", 15: b"DXT5", 20: b"DXT1"}
VTF_RAW = {0: (4, (0, 1, 2), 3), 1: (4, (3, 2, 1), 0), 2: (3, (0, 1, 2), None), 3: (3, (2, 1, 0), None),
           9: (3, (0, 1, 2), None), 10: (3, (2, 1, 0), None), 11: (4, (1, 2, 3), 0), 12: (4, (2, 1, 0), 3),
           16: (4, (2, 1, 0), None)}


def decode_vtf_rgba(blob):
    """The top mip of a VTF's first frame as RGBA (DXT through Pillow's DDS reader, 8-bit layouts directly)."""
    import vtf_hash
    v = vtf_hash.Vtf(blob)
    top = v.top_frames()[0]
    if v.fmt in VTF_FOURCC:
        head = b"DDS " + (124).to_bytes(4, "little")
        head += b"".join(x.to_bytes(4, "little") for x in (0x81007, v.h, v.w, len(top), 0, 1)) + bytes(44)
        head += b"".join(x.to_bytes(4, "little") for x in (32, 4)) + VTF_FOURCC[v.fmt] + bytes(20)
        head += (0x1000).to_bytes(4, "little") + bytes(16)
        return Image.open(io.BytesIO(head + top)).convert("RGBA")
    if v.fmt in VTF_RAW:
        n, order, alpha = VTF_RAW[v.fmt]
        a = np.frombuffer(top, np.uint8).reshape(v.h, v.w, n)
        rgb = a[..., list(order)]
        al = a[..., alpha:alpha + 1] if alpha is not None else np.full(rgb.shape[:2] + (1,), 255, np.uint8)
        return Image.fromarray(np.ascontiguousarray(np.dstack([rgb, al])), "RGBA")
    raise ValueError("VTF format %d" % v.fmt)


def source_rgba(sources, wanted):
    """{hash: RGBA image} of the game textures; wanted is {lower-case VTF name: {hash, ...}}."""
    import vtf_hash
    out = {}
    for src in sources:
        for name, blob in vtf_hash.iter_vtfs(src):
            hs = wanted.get(name.lower())
            if not hs or hs <= set(out):
                continue
            try:
                pairs = {x for pair in vtf_hash.texture_hashes(blob) for x in pair}
                img = decode_vtf_rgba(blob)
            except (ValueError, KeyError, IndexError, OSError):
                continue
            for h in hs:
                if h in pairs and h not in out:
                    out[h] = img
    return out


def upscale4(runner, config, img, wrap):
    """PBRify UpscalerV4 (4x) on the RGB, wrap-around padded for tiling textures; alpha bicubic."""
    rgb = np.asarray(img.convert("RGB"), np.float32) / 255
    h, w = rgb.shape[:2]
    pad = max(8, min(h, w) // 8) if wrap else 0
    if pad:
        rgb = np.pad(rgb, ((pad, pad), (pad, pad), (0, 0)), mode="wrap")
    up = runner.run(config.UPSCALERS["v4"], rgb)
    if pad:
        up = up[4 * pad:4 * (pad + h), 4 * pad:4 * (pad + w)]
    out = Image.fromarray((np.clip(up, 0, 1) * 255 + 0.5).astype(np.uint8), "RGB").convert("RGBA")
    alpha = img.getchannel("A")
    if alpha.getextrema() != (255, 255):
        out.putalpha(alpha.resize(out.size, Image.BICUBIC))
    return out

# ---- composition --------------------------------------------------------------------------------

def resize_f(a, size, resample=Image.BICUBIC):
    """Resize a float32 2-D array to size (w, h)."""
    if (a.shape[1], a.shape[0]) == tuple(size):
        return a.astype(np.float32)
    return np.asarray(Image.fromarray(a.astype(np.float32), "F").resize(size, resample), np.float32)


def gauss_f(a, sigma):
    """Separable Gaussian blur of a float 2-D array, wrapping at the edges (textures tile)."""
    if sigma <= 0:
        return a.astype(np.float32)
    r = max(1, int(math.ceil(3 * sigma)))
    k = np.exp(-0.5 * (np.arange(-r, r + 1) / sigma) ** 2).astype(np.float32)
    k /= k.sum()
    out = a.astype(np.float32)
    for axis in (0, 1):
        acc = np.zeros_like(out)
        for i, w in enumerate(k):
            acc += w * np.roll(out, i - r, axis=axis)
        out = acc
    return out


def smudge_noise(size, seed, cells=6):
    """Tileable soft noise in [-1, 1]: random phases on a few low frequencies."""
    w, h = size
    rng = np.random.default_rng(seed)
    y, x = np.mgrid[0:h, 0:w].astype(np.float32)
    acc = np.zeros((h, w), np.float32)
    for _ in range(10):
        fx, fy = rng.integers(1, cells + 1), rng.integers(-cells, cells + 1)
        ph = rng.uniform(0, 2 * math.pi)
        acc += np.cos(2 * math.pi * (fx * x / w + fy * y / h) + ph) / math.hypot(fx, fy)
    acc /= max(1e-6, float(np.abs(acc).max()))
    return acc


def normal_strength(n):
    return float(np.sqrt(n[..., 0] ** 2 + n[..., 1] ** 2).mean())


def scale_to(n_slopes, target):
    """Unit normals from slopes (dx, dy) scaled so the mean |xy| of the unit normals is about target."""
    def unit(s):
        n = np.dstack([s[..., 0], s[..., 1], np.ones(s.shape[:2], np.float32)])
        return n / np.linalg.norm(n, axis=2, keepdims=True)
    if target <= 0:
        return unit(n_slopes * 0)
    f = 1.0
    for _ in range(4):
        cur = normal_strength(unit(n_slopes * f))
        if cur < 1e-5:
            break
        f *= target / cur
        f = float(np.clip(f, 0.05, 20.0))
    return unit(n_slopes * f)


def albedo_detail_slopes(albedo_rgb, sigma=1.5):
    lum = np.asarray(albedo_rgb, np.float32) @ np.array([0.2126, 0.7152, 0.0722], np.float32) / 255
    hp = lum - gauss_f(lum, sigma)
    gx = np.zeros_like(hp)
    gy = np.zeros_like(hp)
    gx[:, 1:-1] = (hp[:, 2:] - hp[:, :-2]) * 0.5
    gy[1:-1, :] = (hp[2:, :] - hp[:-2, :]) * 0.5
    return np.dstack([-gx, -gy])   # DirectX: brighter is higher, green down


def compose(tex_sizes, rec, ai, albedo, envmask, seed, world):
    """New maps at the planned sizes: {role: uint8 array}. tex_sizes: {role: (w, h)}."""
    out, info = {}, {}
    hgt = None
    if "height" in ai:
        h = ai["height"]
        lo, hi = np.percentile(h, [1, 99])
        hgt = np.clip((h - lo) / max(hi - lo, 1e-4), 0, 1)
    if "normal" in tex_sizes:
        size = tex_sizes["normal"]
        n = ai["normal"]
        nz = np.maximum(n[..., 2:3], 0.05)
        slopes = n[..., :2] / nz
        s = np.dstack([resize_f(slopes[..., 0], size), resize_f(slopes[..., 1], size)])
        if rec["detail"] > 0 and albedo is not None:
            s = s + rec["detail"] * albedo_detail_slopes(albedo.convert("RGB").resize(size, Image.LANCZOS))
        unit = scale_to(s, rec["normal"])
        out["normal"] = R.oct_encode(unit)
        info["normal_strength"] = round(normal_strength(unit), 3)
    if "roughness" in tex_sizes:
        size = tex_sizes["roughness"]
        lo, hi = rec["rough"]
        if rec["rough_from"] == "albedo" and albedo is not None:
            lum = np.asarray(albedo.convert("L").resize(size, Image.BOX), np.float32) / 255
            src = 1 - lum
        elif rec["rough_from"] == "flat":
            src = np.full((size[1], size[0]), 0.5, np.float32)
        else:
            src = resize_f(ai["roughness"], size)
        r = R.remap(src, lo, hi) if rec["rough_from"] != "flat" else np.full_like(src, (lo + hi) / 2)
        if rec["cavity"] > 0 and hgt is not None:
            hh = resize_f(hgt, size)
            cav = np.clip((np.percentile(hh, 35) - hh) / 0.25, 0, 1)
            r = r + rec["cavity"] * cav * (1 - r)
        if rec["envmask"] > 0 and envmask is not None:
            m = np.asarray(Image.fromarray(envmask).resize(size, Image.BILINEAR), np.float32) / 255
            r = r * (1 - rec["envmask"] * m)
        if rec["smudge"] > 0:
            r = r + rec["smudge"] * smudge_noise(size, seed)
        r = np.clip(r, 0.02, 1.0)
        out["roughness"] = (r * 255 + 0.5).astype(np.uint8)
        info["rough_mean"] = round(float(r.mean()), 3)
    if "height" in tex_sizes and hgt is not None:
        out["height"] = (resize_f(hgt, tex_sizes["height"]) * 255 + 0.5).clip(0, 255).astype(np.uint8)
    return out, info


def adjust_albedo(img, spec):
    """Optional colour changes from a class's "albedo" key: saturation, exposure (linear multiplier),
    max (soft ceiling on linear albedo)."""
    if not spec:
        return img
    rgba = np.asarray(img.convert("RGBA"), np.float32) / 255
    lin = np.where(rgba[..., :3] <= 0.04045, rgba[..., :3] / 12.92, ((rgba[..., :3] + 0.055) / 1.055) ** 2.4)
    if "saturation" in spec:
        y = lin @ np.array([0.2126, 0.7152, 0.0722], np.float32)
        lin = y[..., None] + (lin - y[..., None]) * float(spec["saturation"])
    if "exposure" in spec:
        lin = lin * float(spec["exposure"])
    if "max" in spec:
        m = float(spec["max"])
        lin = np.where(lin > m * 0.8, m * 0.8 + (lin - m * 0.8) / (1 + (lin - m * 0.8) / (m * 0.2)), lin)
    lin = np.clip(lin, 0, 1)
    srgb = np.where(lin <= 0.0031308, lin * 12.92, 1.055 * lin ** (1 / 2.4) - 0.055)
    rgba[..., :3] = srgb
    return Image.fromarray((rgba * 255 + 0.5).astype(np.uint8), "RGBA")



def shade(albedo_rgb, unit_normals):
    """Albedo lit by a grazing light from the upper left (30 degrees up) plus a little ambient: relief shows."""
    L = np.array([-0.61, -0.5, 0.61], np.float32)   # DirectX tangent space: y down, so -y is up the image
    L /= np.linalg.norm(L)
    d = np.clip((unit_normals * L).sum(axis=2), 0, 1)
    a = np.asarray(albedo_rgb, np.float32) / 255
    return Image.fromarray((np.clip(a * (0.18 + 1.25 * d[..., None]), 0, 1) * 255).astype(np.uint8), "RGB")


def preview_sheet(path, mod, inputs, roles, maps, label, crop=512):
    """Whole albedo; then 1:1 crops of the top size: albedo, the author's normal lit, the new normal lit, the
    author's roughness, the new roughness, the new height."""
    at = roles["albedo"]
    w, h = at.dims()
    alb = Image.fromarray(maps["albedo"]) if "albedo" in maps else read_dds(os.path.join(mod, inputs["diffuse_texture"]), max(w, h))
    if inputs.get("diffuse_texture") and os.path.isfile(os.path.join(mod, inputs["diffuse_texture"])) and "albedo" in maps:
        old_alb = read_dds(os.path.join(mod, inputs["diffuse_texture"]), max(w, h)).convert("RGB").resize((w, h))
    else:
        old_alb = None
    alb = alb.convert("RGB").resize((w, h), Image.LANCZOS)
    c = min(crop, w, h)
    box = ((w - c) // 2, (h - c) // 2, (w - c) // 2 + c, (h - c) // 2 + c)
    tiles = [alb.resize((crop, crop)), alb.crop(box)]
    if old_alb is not None:
        tiles.insert(1, old_alb.crop(box))

    def crop_of(img, size):
        img = img.resize((w, h), Image.BICUBIC) if img.size != (w, h) else img
        return img.crop(box)
    old_n = inputs.get("normalmap_texture")
    if old_n and os.path.isfile(os.path.join(mod, old_n)):
        on = read_dds(os.path.join(mod, old_n), max(w, h)).convert("RGB").resize((w, h), Image.BICUBIC)
        tiles.append(shade(alb.crop(box), R.oct_decode(np.asarray(on.crop(box)))))
    else:
        tiles.append(Image.new("RGB", (c, c), (40, 0, 0)))
    if "normal" in maps:
        nn = Image.fromarray(maps["normal"]).resize((w, h), Image.BICUBIC)
        tiles.append(shade(alb.crop(box), R.oct_decode(np.asarray(nn.crop(box)))))
    old_r = inputs.get("reflectionroughness_texture")
    if old_r and os.path.isfile(os.path.join(mod, old_r)):
        tiles.append(crop_of(read_dds(os.path.join(mod, old_r), max(w, h)).convert("L"), (w, h)).convert("RGB"))
    else:
        tiles.append(Image.new("RGB", (c, c), (40, 0, 0)))
    if "roughness" in maps:
        tiles.append(crop_of(Image.fromarray(maps["roughness"]), (w, h)).convert("RGB"))
    if "height" in maps:
        tiles.append(crop_of(Image.fromarray(maps["height"]), (w, h)).convert("RGB"))
    from PIL import ImageDraw
    sheet = Image.new("RGB", (crop * len(tiles), crop + 16), (20, 20, 20))
    for i, t in enumerate(tiles):
        sheet.paste(t.resize((crop, crop)), (i * crop, 16))
    ImageDraw.Draw(sheet).text((4, 2), label[:200], fill="white")
    sheet.save(path, quality=90)


# ---- layers -------------------------------------------------------------------------------------

def set_inputs(text, prim, values):
    """Set inputs on `over "Shader"` of material prim (mat_<HASH>) in a layer's text: replace an existing
    value (metadata kept) or add the line. values: {name: (type, literal)}."""
    want = prim[4:].upper() if prim.lower().startswith("mat_") else prim.upper()
    span = next(((start, end) for h, start, end in material_spans(text) if h == want), None)
    if span is None:
        raise KeyError(prim)
    begin, end = span
    block = text[begin:end]
    sh = re.search(r'over\s+"Shader"\s*(\([^)]*\))?\s*\{', block)
    if not sh:
        raise KeyError(prim + "/Shader")
    for name, (typ, lit) in values.items():
        pat = re.compile(r"((?:uniform\s+)?\w+\s+inputs:%s\s*=\s*)(@[^@]*@|\([^)\r\n]*\)|[^\s(]+)" % re.escape(name))
        hit = pat.search(block)
        if hit:
            block = block[:hit.start(2)] + lit + block[hit.end(2):]
        else:
            sh = re.search(r'over\s+"Shader"\s*(\([^)]*\))?\s*\{', block)
            line_start = block.rfind("\n", 0, sh.start()) + 1
            pad = re.match(r"[ \t]*", block[line_start:]).group(0) + "    "
            block = block[:sh.end()] + "\n%s%s inputs:%s = %s" % (pad, typ, name, lit) + block[sh.end():]
    return text[:begin] + block + text[end:]


def asset(rel_from_layer):
    return "@./%s@" % rel_from_layer.replace("\\", "/") if rel_from_layer else "@@"


# ---- main ---------------------------------------------------------------------------------------

def parse_args(argv):
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--mod", required=True)
    ap.add_argument("--out")
    ap.add_argument("--source", action="append", required=True)
    ap.add_argument("--rules", required=True)
    ap.add_argument("--budget", type=int, default=DEFAULT_BUDGET)
    ap.add_argument("--max-side", type=int, default=4096)
    ap.add_argument("--work")
    ap.add_argument("--json")
    ap.add_argument("--plan-only", action="store_true")
    ap.add_argument("--preview")
    ap.add_argument("--only")
    ap.add_argument("--force", action="store_true")
    ap.add_argument("--workers", type=int, default=6)
    return ap.parse_args(argv)


def cached(path, make):
    if os.path.isfile(path):
        with open(path, encoding="utf-8") as fh:
            return json.load(fh)
    data = make()
    with open(path + ".tmp", "w", encoding="utf-8") as fh:
        json.dump(data, fh)
    os.replace(path + ".tmp", path)
    return data


def sources_key(sources):
    h = hashlib.sha256()
    for s in sources:
        st = os.stat(s)
        h.update(("%s|%d|%d;" % (os.path.abspath(s).lower(), st.st_size, int(st.st_mtime))).encode())
    return h.hexdigest()[:16]


def main(argv=None) -> int:
    a = parse_args(argv)
    mod = os.path.abspath(a.mod)
    if not os.path.isfile(os.path.join(mod, "mod.usda")):
        print("ERROR no mod.usda in %s" % mod)
        return 1
    for s in a.source:
        if not os.path.exists(s):
            print("ERROR missing source: %s" % s)
            return 1
    if not a.out and not (a.plan_only or a.preview):
        print("ERROR --out is required unless --plan-only or --preview")
        return 2
    out = os.path.abspath(a.out) if a.out else None
    if out and os.path.exists(out) and not (a.plan_only or a.preview):
        if not a.force or not os.path.isfile(os.path.join(out, "mod.usda")):
            print("ERROR %s exists (use --force to replace an earlier output)" % out)
            return 1
    work = os.path.abspath(a.work or (out or mod) + ".work")
    os.makedirs(work, exist_ok=True)
    classes, rules, overrides, skip_flags = load_rules(a.rules)
    t0 = time.time()

    key = sources_key(a.source)
    names = cached(os.path.join(work, "names-%s.json" % key), lambda: texture_table(a.source))
    use = cached(os.path.join(work, "usage-%s.json" % key), lambda: map_usage.usage(a.source)) or {
        "maps": [], "world_area": 0, "textures": {}}
    mats, walk = mod_materials(mod)
    print("materials %d, named %d, map %s, %.0f s" % (len(mats), sum(1 for h in mats if h in names),
                                                       ",".join(use["maps"]), time.time() - t0), flush=True)
    lost = sum(a for _m, a in use.get("unmatched", []))
    if lost > 0.5:
        print("WARNING %.2f %% of the world's area has materials without a VMT in the sources (their textures "
              "get no weight in the size plan): %s" % (lost, ", ".join(m for m, _a in use["unmatched"][:5])),
              flush=True)

    # classes
    plan = {}
    for h, m in sorted(mats.items()):
        tex = map_usage.norm_texture(names[h][0]) if h in names else None
        u = use["textures"].get(tex) if tex else None
        cls, why = classify(h, tex, m["inputs"], rules, overrides, (u or {}).get("flags", []), skip_flags)
        plan[h] = {"texture": tex, "class": cls, "why": why, "importance": round(map_usage.importance(u), 4),
                   "flags": (u or {}).get("flags", []), "world": (u or {}).get("world", 0),
                   "props": (u or {}).get("props", 0)}

    # textures to plan; a material without known usage (unnamed, or drawn by something the BSP does not
    # list: dynamic props, particles, a texture swapped at run time) is no less likely to show: half the
    # median importance of the placed ones
    placed = sorted(p["importance"] for p in plan.values() if p["importance"] > 0)
    unknown = 0.5 * placed[len(placed) // 2] if placed else 1e-4
    texes, by_file, replaced = [], {}, set()
    for h, p in plan.items():
        rec = recipe(classes, p["class"])
        inputs = mats[h]["inputs"]
        imp = (p["importance"] if p["importance"] > 0 else unknown) * float(rec.get("weight", 1.0))
        cap = min(a.max_side, rec.get("max_side") or a.max_side)
        alb = inputs.get("diffuse_texture") or ""
        alb_d = None
        if alb and alb.lower().endswith(".dds") and os.path.isfile(os.path.join(mod, alb)):
            try:
                alb_d = F.Dds(os.path.join(mod, alb))
            except F.Refused:
                alb_d = None
        roles = {}
        src_wh = (names[h][1], names[h][2]) if h in names else None
        if rec.get("from_source") and src_wh and not rec.get("keep"):
            for role in ("albedo",) + GENERATED:
                if role == "height" and not (rec["height"] > 0 and p["world"] > 0):
                    continue
                roles[role] = ("new", None)
            for inp in ("diffuse_texture", "normalmap_texture", "reflectionroughness_texture", "height_texture",
                        "metallic_texture"):
                if inputs.get(inp):
                    replaced.add(inputs[inp])
            p["generate"] = True
            p["from_source"] = True
            alb_d = None
        elif rec.get("keep") or alb_d is None:
            for inp, role in INPUT_ROLE.items():
                f = inputs.get(inp)
                if f and f.lower().endswith(".dds") and os.path.isfile(os.path.join(mod, f)):
                    roles[role] = ("file", f)
            p["generate"] = False
        else:
            roles["albedo"] = ("file", alb)
            for role in GENERATED:
                if role == "height" and not (rec["height"] > 0 and p["world"] > 0):
                    continue
                roles[role] = ("new", None)
            for inp in ("normalmap_texture", "reflectionroughness_texture", "height_texture", "metallic_texture"):
                if inputs.get(inp):
                    replaced.add(inputs[inp])
            p["generate"] = True
        p["roles"] = {}
        for role, (kind, f) in roles.items():
            if kind == "file":
                try:
                    d = F.Dds(os.path.join(mod, f))
                except F.Refused:
                    continue
                w = imp * ROLE_WEIGHT.get(role, ROLE_WEIGHT["other"])
                t = by_file.get(f)
                if t is None:
                    F.check_constant(d)   # a one-value BC4/BC5 map keeps only its 16 px tail: nothing is lost
                    t = Tex(f, role, d.width, d.height, d.fmt, w, src=f, max_side=16 if d.constant else cap,
                            mips=d.mips, dds=d)
                    by_file[f] = t
                    texes.append(t)
                else:
                    t.weight = max(t.weight, w)
                p["roles"][role] = t
            else:
                w0, h0 = (alb_d.width, alb_d.height) if alb_d is not None else (4 * src_wh[0], 4 * src_wh[1])
                t = Tex("%s:%s" % (h, role), role, w0, h0, NEW_FORMAT[role], imp * ROLE_WEIGHT[role], max_side=cap)
                texes.append(t)
                p["roles"][role] = t
    kept_refs = {f for f in walk.files if f not in by_file}
    replaced -= {f for h, p in plan.items() if not p["generate"] for f in mats[h]["inputs"].values()
                 if isinstance(f, str)}
    # a file a binary layer names (a mesh's own textures) stays, whatever the material inputs say
    replaced -= {f for f, layers in walk.files.items() if any(layer in walk.crate for layer in layers)}
    fixed = sum(os.path.getsize(os.path.join(mod, f)) for f in kept_refs - replaced
                if os.path.isfile(os.path.join(mod, f)))
    fixed += sum(os.path.getsize(os.path.join(mod, f)) for f in walk.layers)
    try:
        total = plan_sizes(texes, a.budget - SLACK, fixed)
    except Refused as error:
        print("ERROR %s" % error)
        return 1
    print("plan: %d textures, %.2f GB (%.2f GB of layers and files kept as they are), budget %.2f GB" % (
        len(texes), total / 1e9, fixed / 1e9, a.budget / 1e9), flush=True)
    by_class = {}
    for h, p in plan.items():
        c = by_class.setdefault(p["class"], [0, 0])
        c[0] += 1
        c[1] += sum(t.cost() for t in p["roles"].values())
    for c, (n, b) in sorted(by_class.items(), key=lambda kv: -kv[1][1]):
        print("  %-18s %4d materials %7.1f MB" % (c, n, b / 1e6))
    if a.json and a.plan_only:
        with open(a.json, "w", encoding="utf-8") as fh:
            json.dump({h: {**{k: v for k, v in p.items() if k != "roles"},
                           "sizes": {r: t.dims() for r, t in p["roles"].items()}}
                       for h, p in plan.items()}, fh, indent=1)
    if a.plan_only:
        return 0

    only = None
    if a.only:
        want = {x.strip().lower() for x in a.only.split(",")}
        only = {h for h, p in plan.items() if h.lower() in want or (p["texture"] or "").split("/")[-1] in want
                or (p["texture"] or "") in want}

    # AI maps
    ai_dir = os.path.join(work, "ai")
    need = [h for h, p in plan.items() if p["generate"] and (only is None or h in only)]
    todo = [h for h in need if load_ai(ai_dir, h) is None
            or (plan[h].get("from_source") and not os.path.isfile(os.path.join(ai_dir, h + "_albedo.png")))]
    if todo:
        sys.path.insert(0, R.RPAI_TOOL)
        from rpai import config  # noqa: E402
        from rpai.ai import ModelRunner  # noqa: E402
        runner = ModelRunner(tile=int(os.environ.get("REPBR_TILE", "512")), log=lambda *_: None)
        t1 = time.time()
        up_src = {}
        if any(plan[h].get("from_source") for h in todo):
            want = {}
            for h in todo:
                if plan[h].get("from_source"):
                    want.setdefault(names[h][0].lower(), set()).add(h)
            up_src = source_rgba(a.source, want)
        for i, h in enumerate(todo):
            p = plan[h]
            full = p["roles"]["albedo"].full
            src = max(names[h][1], names[h][2]) if h in names else None
            ws = work_side(src, full)
            if p.get("from_source"):
                img = upscale4(runner, config, up_src[h], wrap=p["world"] > 0)
                os.makedirs(ai_dir, exist_ok=True)
                img.save(os.path.join(ai_dir, h + "_albedo.png"), compress_level=1)
                img = img.resize((max(1, round(img.width * ws / max(img.size))),
                                  max(1, round(img.height * ws / max(img.size)))), Image.LANCZOS)
            else:
                img = read_dds(os.path.join(mod, mats[h]["inputs"]["diffuse_texture"]), ws)
            if max(img.size) != ws:
                s = ws / max(img.size)
                img = img.resize((max(1, round(img.width * s)), max(1, round(img.height * s))), Image.LANCZOS)
            save_ai(ai_dir, h, run_ai(runner, config, img, wrap=p["world"] > 0))
            if (i + 1) % 20 == 0 or i + 1 == len(todo):
                print("ai %d/%d %.0f s" % (i + 1, len(todo), time.time() - t1), flush=True)
        runner.unload()

    # grain sources
    grain_src = {}
    want_src = {}
    for h in need:
        if recipe(classes, plan[h]["class"])["grain"] and plan[h]["texture"] and not plan[h].get("from_source"):
            want_src.setdefault(names[h][0].lower(), set()).add(h)
    if want_src:
        grain_src = R.source_images(a.source, want_src)

    def build_one(h):
        p = plan[h]
        rec = recipe(classes, p["class"])
        inputs = mats[h]["inputs"]
        res = {}
        ai = load_ai(ai_dir, h)
        at = p["roles"]["albedo"]
        aw, ah_ = at.dims()
        if p.get("from_source"):
            with Image.open(os.path.join(ai_dir, h + "_albedo.png")) as im:
                albedo = im.convert("RGBA")
            new_albedo = True
        else:
            albedo = read_dds(os.path.join(mod, inputs["diffuse_texture"]), max(aw, ah_))
            new_albedo = False
        if albedo.size != (aw, ah_):
            albedo = albedo.resize((aw, ah_), Image.LANCZOS)
        src = grain_src.get(h)
        if src is not None and rec["grain"]:
            ratio, corr = R.grain_kept(src, albedo)
            if ratio < 0.8 and corr >= 0.7:
                albedo = Image.fromarray(R.restore_grain(src, albedo), "RGBA")
                new_albedo = True
                res["grain"] = [round(ratio, 3), round(corr, 3)]
        if rec.get("albedo"):
            albedo = adjust_albedo(albedo, rec["albedo"])
            new_albedo = True
        env = None
        if rec["envmask"] > 0 and "basealphaenvmapmask" in p["flags"]:
            env = np.asarray(albedo.getchannel("A"), np.uint8)
        sizes = {r: t.dims() for r, t in p["roles"].items() if r in GENERATED}
        maps, info = compose(sizes, rec, ai, albedo, env, int(h[:8], 16), p["world"] > 0)
        res.update(info)
        if new_albedo:
            maps["albedo"] = np.asarray(albedo, np.uint8)
        return h, maps, res

    if a.preview:
        os.makedirs(a.preview, exist_ok=True)
        for h in sorted(only or []):
            if h not in need:
                continue
            _h, maps, res = build_one(h)
            name = (plan[h]["texture"] or h).split("/")[-1]
            preview_sheet(os.path.join(a.preview, "%s_%s.jpg" % (name, h[:6])), mod, mats[h]["inputs"],
                          plan[h]["roles"], maps, "%s %s %s" % (name, plan[h]["class"], res))
            print("preview", name, plan[h]["class"], res, flush=True)
        return 0

    # build
    sys.path.insert(0, R.RPAI_TOOL)
    from rpai import config, dds  # noqa: E402
    if not config.nvtt_path().exists():
        print("ERROR the NVTT exporter is missing: %s" % config.nvtt_path())
        return 1
    stage = out + ".partial"
    if os.path.exists(stage):
        shutil.rmtree(stage)
    os.makedirs(os.path.join(stage, "SubUSDs"))
    png_dir = os.path.join(work, "png")
    os.makedirs(png_dir, exist_ok=True)
    edits, report, jobs = {}, {}, []
    t2 = time.time()
    with ThreadPoolExecutor(max(1, a.workers // 2)) as ex:
        for h, maps, res in ex.map(build_one, need):
            p = plan[h]
            rec = recipe(classes, p["class"])
            layer = mats[h]["layer"]
            ldir = os.path.dirname(layer)
            vals = {}
            for role, arr in maps.items():
                png = os.path.join(png_dir, "%s_%s.png" % (h, role))
                Image.fromarray(arr).save(png, compress_level=1)
                rel = os.path.join("SubUSDs", "%s_repbr_%s.%s.rtex.dds" % (h, role, NEW_SUFFIX[role]))
                jobs.append((png, os.path.join(stage, rel), role))
                inp = {"albedo": "diffuse_texture", "normal": "normalmap_texture",
                       "roughness": "reflectionroughness_texture", "height": "height_texture"}[role]
                vals[inp] = ("asset", asset(os.path.relpath(rel, ldir or ".")))
                if role == "albedo":
                    p["roles"]["albedo"].replaced = True
            if "height" in maps:
                vals["displace_in"] = ("float", "%g" % rec["height"])
            elif "height_texture" in mats[h]["inputs"]:
                vals["height_texture"] = ("asset", "@@")
                vals["displace_in"] = ("float", "0")
            vals["metallic_constant"] = ("float", "%g" % rec["metal"])
            for name, (typ, lit) in (rec.get("set_if_present") or {}).items():
                if name in mats[h]["inputs"]:
                    vals[name] = (typ, lit)
            if mats[h]["inputs"].get("metallic_texture"):
                vals["metallic_texture"] = ("asset", "@@")
            if "reflection_roughness_constant" in mats[h]["inputs"] and "roughness" in maps:
                vals["reflection_roughness_constant"] = ("float", "%g" % float(np.mean(rec["rough"])))
            edits.setdefault(layer, {})["mat_" + h] = vals
            report[h] = {"texture": p["texture"], "class": p["class"], "importance": p["importance"],
                         "sizes": {r: t.dims() for r, t in p["roles"].items()}, **res}
    print("composed %d materials in %.0f s; encoding %d maps" % (len(need), time.time() - t2, len(jobs)),
          flush=True)
    t3 = time.time()
    dds.encode([(__import__("pathlib").Path(s), __import__("pathlib").Path(d), k) for s, d, k in jobs],
               workers=a.workers, log=lambda *_: None)
    print("encoded in %.0f s" % (time.time() - t3), flush=True)
    for src_png, _dst, _kind in jobs:
        try:
            os.remove(src_png)
        except OSError:
            pass

    # layers: copy, with the edits
    for layer in walk.layers:
        dst = os.path.join(stage, layer)
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        if layer in edits:
            with open(os.path.join(mod, layer), encoding="utf-8", errors="replace") as fh:
                text = fh.read()
            for prim, vals in edits[layer].items():
                text = set_inputs(text, prim, vals)
            with open(dst, "w", encoding="utf-8", newline="\n") as fh:
                fh.write(text)
        else:
            shutil.copyfile(os.path.join(mod, layer), dst)
    # every other file the layers reach: sized as planned, or as it is
    for _round in range(3):
        final = usd_refs.walk(stage)
        todo_files = [os.path.normpath(os.path.join(os.path.dirname(layer), ref)).replace(os.sep, "/")
                      for layer, ref in final.missing]
        if not todo_files:
            break
        for f in todo_files:
            srcf, dst = os.path.join(mod, f), os.path.join(stage, f)
            if os.path.isfile(dst) or not os.path.isfile(srcf):
                continue
            os.makedirs(os.path.dirname(dst), exist_ok=True)
            t = by_file.get(f)
            if t is not None and t.side < t.full:
                with open(dst, "wb") as fh:
                    fh.write(t.dds.reduced(t.drop()))
            else:
                shutil.copyfile(srcf, dst)
    final = usd_refs.walk(stage)
    if final.missing or final.errors:
        print("ERROR references that do not resolve: %s" % ", ".join(
            "%s -> %s" % m for m in (final.missing + final.errors)[:10]))
        return 1
    size = sum(os.path.getsize(os.path.join(r, f)) for r, _d, fs in os.walk(stage) for f in fs)
    if size > a.budget:
        print("ERROR the result is %d bytes, over the budget %d" % (size, a.budget))
        return 1
    if os.path.exists(out):
        shutil.rmtree(out)
    os.replace(stage, out)
    print("wrote %s: %d files, %.2f GB, %.0f s" % (out, len(final.files) + len(final.layers), size / 1e9,
                                                  time.time() - t0), flush=True)
    if a.json:
        with open(a.json, "w", encoding="utf-8") as fh:
            json.dump({"bytes": size, "budget": a.budget, "materials": report,
                       "classes": {h: p["class"] for h, p in plan.items()}}, fh, indent=1)
    return 0


if __name__ == "__main__":
    sys.exit(main())
