"""Give a map mod physical roughness: each material's roughness map remapped into its material class's range.

    python -I retune_roughness.py --mod <mod folder> --out <new mod folder> --source <map item>
        [--source <*_dir.vpk> ...] [--rules FILE] [--ai-dir DIR] [--restore-grain [--grain-ratio 0.8]
        [--grain-corr 0.7]] [--work DIR] [--json FILE] [--dry-run] [--force]

Mods made with PBRFusion (BigCity RTX, 2026-11-14) ship PBRify's raw roughness: it follows the albedo's
brightness and sits near 0.5 on brick, concrete and plaster, which the path tracer draws as a plastic sheen.
This script names each material's game texture by its hash in the sources (vtf_hash.py), picks a class by
the texture's path (ordered regex rules), normalises the material's roughness to its 2nd-98th percentile and
maps it into the class's range (this project's standards: plaster 0.78-0.94, concrete 0.68-0.94, brick
0.74-0.95, ...). It scales the normal map's slopes by the class's gain, and on facades whose albedo alpha is a
two-level window mask (HL2's envmap mask, 0 on the panes) makes the panes glossy and flat. The albedo changes
only with --restore-grain. Materials no source names, or whose class is "skip" (sky, weapons, characters, glass, lights), keep
their maps. --out is a hard-linked copy of --mod in which only the rewritten maps are new files.

--restore-grain also puts back the game texture's fine grain where the mod's upscaler smoothed it away (the
albedo, box-downsampled to the source's size, kept less than --grain-ratio of the source's high-pass energy and
still correlates at least --grain-corr with it): back-projection, the albedo plus the bicubic upscale of the
source minus that downsample. Smooth, grainless pavement and cobbles read as plastic too.

--ai-dir takes PBRify maps made from the mod's albedo (<HASH>_rough.png, <HASH>_normal.png in DirectX
convention) instead of the mod's own maps. Encoding uses the RTX Remix Toolkit's NVTT exporter through rpai's
dds module (skills/mmd-remix-pbr/tool), BC4 for roughness and BC5 for normals, each at its old size.

Exit codes: 0 done (or a dry run); 1 refused (no mod.usda, a missing source, --out exists, no NVTT);
2 bad command line.
"""
from __future__ import annotations

import argparse
import io
import json
import os
import re
import shutil
import sys
from concurrent.futures import ThreadPoolExecutor

import numpy as np
from PIL import Image, ImageFilter

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import usd_refs  # noqa: E402
import vtf_hash  # noqa: E402

RPAI_TOOL = os.path.normpath(os.path.join(HERE, "..", "..", "mmd-remix-pbr", "tool"))

# class: (roughness low, roughness high, normal slope gain); "facade" also gets glossy window panes
CLASSES = {
    "facade": (0.64, 0.92, 1.0),
    "skyline": (0.55, 0.88, 0.7),
    "brick": (0.74, 0.95, 1.3),
    "concrete": (0.68, 0.94, 1.0),
    "plaster": (0.78, 0.94, 0.8),
    "wallpaper": (0.62, 0.86, 0.8),
    "stone": (0.60, 0.90, 1.4),
    "slate": (0.35, 0.70, 1.0),
    "roof_tile": (0.58, 0.88, 1.2),
    "wood_painted": (0.46, 0.80, 1.0),
    "wood_floor": (0.42, 0.75, 1.0),
    "wood_rough": (0.65, 0.90, 1.1),
    "metal": (0.45, 0.85, 1.0),
    "decal_paint": (0.55, 0.85, 0.8),
    "paper": (0.74, 0.93, 0.6),
    "sign": (0.45, 0.78, 0.8),
    "stain": (0.62, 0.92, 0.8),
    "ground": (0.80, 1.00, 1.2),
    "slime": (0.30, 0.75, 0.8),
    "carpet": (0.86, 1.00, 0.8),
    "tarpaper": (0.74, 0.95, 1.0),
}
WINDOW_ROUGH = 0.12

# First match wins, on the lower-case VTF path ("pak:" stripped). Written for HL2's city textures (BigCity).
RULES = [
    (r"/skybox/|/models/weapons/|/models/combine_soldier/|/models/player|/effects/|light_domelight|/glass/|"
     r"nukwindow|glasswindow|/hunter/|/sprites/|/particle/", "skip"),
    (r"graffiti", "decal_paint"),
    (r"bills|posters|pinup", "paper"),
    (r"decalsign|security_decal|tres_decal|metalsign|sign_cafe|sign_hotel", "sign"),
    (r"decalstain|drain|pipestain|trashdecal|decomp_puddle", "stain"),
    (r"decalmetal", "metal"),
    (r"milrug|carpet", "carpet"),
    (r"/building_template/", "facade"),
    (r"/composite/|/buildings/gen|assault_skybox_building|cs_havana/building03|factory_skybox", "skyline"),
    (r"coast01_sheet|dirtfloor|grassfloor|/nature/(dirt|grass|mud|sand)", "ground"),
    (r"/brick/", "brick"),
    (r"/plaster/wallpaper", "wallpaper"),
    (r"/plaster/", "plaster"),
    (r"/concrete/|train_ce|nuke_ceiling|pavement|rightcurb|props_debris/concretefloor|canal_bridge", "concrete"),
    (r"/stone/", "stone"),
    (r"tilefloor", "slate"),
    (r"tileroof", "roof_tile"),
    (r"wooddoor|door_sn01|trainstation_bench", "wood_painted"),
    (r"woodfloor|test_speakers/floor04", "wood_floor"),
    (r"woodwall|/wood/", "wood_rough"),
    (r"/metal/|/dev/|ironmetal|nukdoors|nuke_metalfloor|basementdoor|fence3", "metal"),
    (r"toxicslime", "slime"),
    (r"tarpaper", "tarpaper"),
]

INPUT = re.compile(r"asset\s+inputs:(diffuse_texture|normalmap_texture|reflectionroughness_texture)\s*=\s*@([^@]*)@")
HEAD = re.compile(r'"mat_([0-9A-Fa-f]{16})"')


def classify(name, rules=RULES):
    """The class of a VTF path, or None when no rule matches."""
    n = (name or "").lower().replace("\\", "/")
    if n.startswith("pak:"):
        n = n[4:]
    for pattern, cls in rules:
        if re.search(pattern, n):
            return cls
    return None


def remap(rough, lo, hi):
    """Roughness (0-1) normalised to its 2nd-98th percentile and mapped into [lo, hi]."""
    p2, p98 = np.percentile(rough, [2, 98])
    if p98 - p2 > 0.02:
        t = np.clip((rough - p2) / (p98 - p2), 0, 1)
    else:
        t = np.full_like(rough, 0.5)
    return (lo + (hi - lo) * t).astype(np.float32)


def _filter(mask, size, kind):
    img = Image.fromarray((mask * 255).astype(np.uint8), "L")
    return np.asarray(img.filter(ImageFilter.MinFilter(size) if kind == "min" else ImageFilter.MaxFilter(size))) > 127


def window_mask(alpha):
    """1 on the panes of a facade's painted windows, or None. The panes are the near-black texels of the alpha
    (0-1; HL2's envmap mask is 0 there) that form solid regions: 2-60 % of the texture below 0.1, of which at
    least 80 % survive an opening (a 5 px minimum, then maximum), so grunge in a graded mask is no pane."""
    core = alpha < 0.1
    low = float(core.mean())
    if not 0.02 <= low <= 0.60:
        return None
    side = min(alpha.shape)
    k = 5 if side >= 64 else 3
    opened = _filter(_filter(core, k, "min"), k, "max")
    if float(opened.mean()) < 0.8 * low:
        return None
    keep = _filter(opened, 3, "max")
    return (np.clip((0.18 - alpha) / 0.1, 0, 1) * keep).astype(np.float32)


def oct_decode(rgb):
    """Remix's hemispherical octahedral normals (RG 0-255) to unit vectors."""
    a = rgb[..., :2].astype(np.float32) / 255 * 2 - 1
    x = (a[..., 0] + a[..., 1]) * 0.5
    y = (a[..., 0] - a[..., 1]) * 0.5
    n = np.dstack([x, y, 1 - np.abs(x) - np.abs(y)])
    return n / np.maximum(np.linalg.norm(n, axis=2, keepdims=True), 1e-6)


def oct_encode(n):
    """Unit tangent-space normals (DirectX) to Remix's hemispherical octahedral RG8 (B = 0), the Toolkit's maths."""
    n = n.astype(np.float32).copy()
    n[..., 2] = np.abs(n[..., 2])
    n /= np.maximum(np.abs(n).sum(axis=2, keepdims=True), 1e-8)
    out = np.zeros(n.shape[:2] + (3,), np.uint8)
    out[..., 0] = np.floor(((n[..., 0] + n[..., 1]) * 0.5 + 0.5) * 255 + 0.5).clip(0, 255)
    out[..., 1] = np.floor(((n[..., 0] - n[..., 1]) * 0.5 + 0.5) * 255 + 0.5).clip(0, 255)
    return out


def scale_normals(n, gain, flat=None):
    """Slopes times gain; where `flat` (0-1) is set, blended toward a flat normal."""
    n = n.astype(np.float32).copy()
    n[..., :2] *= gain
    n[..., 2] = np.maximum(n[..., 2], 0.05)
    if flat is not None:
        f = flat[..., None]
        n = n * (1 - f) + np.array([0, 0, 1], np.float32) * f
    return n / np.maximum(np.linalg.norm(n, axis=2, keepdims=True), 1e-6)


FOURCC = {13: b"DXT1", 14: b"DXT3", 15: b"DXT5", 20: b"DXT1"}
RAW = {0: (4, (0, 1, 2)), 1: (4, (3, 2, 1)), 2: (3, (0, 1, 2)), 3: (3, (2, 1, 0)), 9: (3, (0, 1, 2)),
       10: (3, (2, 1, 0)), 11: (4, (1, 2, 3)), 12: (4, (2, 1, 0)), 16: (4, (2, 1, 0))}


def decode_vtf(blob):
    """The top mip of a VTF's first frame as an RGB image: DXT1/3/5 through Pillow's DDS reader behind a
    minimal header, 8-bit RGB(A) layouts directly. ValueError for other formats."""
    v = vtf_hash.Vtf(blob)
    top = v.top_frames()[0]
    if v.fmt in FOURCC:
        head = b"DDS " + (124).to_bytes(4, "little")
        head += b"".join(x.to_bytes(4, "little") for x in (0x81007, v.h, v.w, len(top), 0, 1)) + bytes(44)
        head += b"".join(x.to_bytes(4, "little") for x in (32, 4)) + FOURCC[v.fmt] + bytes(20)
        head += (0x1000).to_bytes(4, "little") + bytes(16)
        return Image.open(io.BytesIO(head + top)).convert("RGB")
    if v.fmt in RAW:
        n, order = RAW[v.fmt]
        a = np.frombuffer(top, np.uint8).reshape(v.h, v.w, n)
        return Image.fromarray(np.ascontiguousarray(a[..., list(order)]), "RGB")
    raise ValueError("VTF format %d" % v.fmt)


def source_images(sources, wanted):
    """{hash: RGB image} of the source textures; wanted is {lower-case VTF name: {hash, ...}}."""
    out = {}
    for src in sources:
        for name, blob in vtf_hash.iter_vtfs(src):
            hs = wanted.get(name.lower())
            if not hs or hs <= set(out):
                continue
            try:
                pairs = {x for pair in vtf_hash.texture_hashes(blob) for x in pair}
                img = decode_vtf(blob)
            except (ValueError, KeyError, IndexError, OSError):
                continue
            for h in hs:
                if h in pairs and h not in out:
                    out[h] = img
    return out


def _lum(img):
    return np.asarray(img.convert("L"), np.float32) / 255


def grain_kept(src, albedo):
    """(high-pass energy of the albedo box-downsampled to the source's size / the source's, their correlation)."""
    down = albedo.convert("RGB").resize(src.size, Image.BOX)
    a, b = _lum(src), _lum(down)
    hp_a = a - _lum(src.convert("L").filter(ImageFilter.GaussianBlur(2)))
    hp_b = b - _lum(down.convert("L").filter(ImageFilter.GaussianBlur(2)))
    ratio = float(hp_b.std() / max(hp_a.std(), 1e-4))
    corr = float(np.corrcoef(a.ravel(), b.ravel())[0, 1]) if a.std() > 1e-4 and b.std() > 1e-4 else 1.0
    return ratio, corr


def restore_grain(src, albedo):
    """Back-projection: the albedo plus the bicubic upscale of (source - albedo box-downsampled to the source's
    size). The upscale's edges stay; the source's grain, which the upscaler smoothed, comes back. Alpha kept."""
    rgba = albedo.convert("RGBA")
    rgb = rgba.convert("RGB")
    down = rgb.resize(src.size, Image.BOX)
    out = []
    for s, d, m in zip(src.convert("RGB").split(), down.split(), rgb.split()):
        res = np.asarray(s, np.float32) - np.asarray(d, np.float32)
        up = np.asarray(Image.fromarray(res, "F").resize(rgba.size, Image.BICUBIC), np.float32)
        out.append(np.clip(np.asarray(m, np.float32) + up, 0, 255))
    alpha = np.asarray(rgba.getchannel("A"), np.uint8)
    return np.dstack([np.dstack(out).round().astype(np.uint8), alpha])


def texture_names(sources):
    names = {}
    for src in sources:
        for name, blob in vtf_hash.iter_vtfs(src):
            try:
                for x64, x3 in vtf_hash.texture_hashes(blob):
                    names.setdefault(x64, name)
                    names.setdefault(x3, name)
            except (ValueError, KeyError, IndexError):
                continue
    return names


def materials(mod):
    """{HASH: {input: path relative to the mod}} from every text layer reached from mod.usda."""
    walk = usd_refs.walk(mod)
    out = {}
    for layer in walk.layers:
        if layer in walk.crate:
            continue
        path = os.path.join(mod, layer)
        with open(path, encoding="utf-8", errors="replace") as fh:
            text = fh.read()
        # each input belongs to the material whose braces hold it (a mesh replacement's own material may
        # follow a material's block: its inputs are not that material's)
        spans = [(name[4:].upper(), start, end) for name, _path, start, end in usd_refs.prim_spans(text)
                 if re.fullmatch(r"mat_[0-9A-Fa-f]{16}", name)]
        base = os.path.dirname(layer)
        for m in INPUT.finditer(text):
            owner = next((h for h, start, end in spans if start < m.start() < end), None)
            if owner is None or not m.group(2):
                continue
            rel = os.path.normpath(os.path.join(base, m.group(2)))
            out.setdefault(owner, {})[m.group(1)] = rel
    return out


def load_rules(path):
    """A rules file: {"classes": {name: [lo, hi, gain]}, "rules": [[regex, class], ...]} (each key optional;
    rules given replace the defaults, classes given are added to them)."""
    classes, rules = dict(CLASSES), list(RULES)
    if path:
        with open(path, encoding="utf-8") as fh:
            data = json.load(fh)
        for k, v in data.get("classes", {}).items():
            classes[k] = tuple(float(x) for x in v)
        if "rules" in data:
            rules = [(p, c) for p, c in data["rules"]]
    return classes, rules


def compose(mod, h, tex, cls, classes, ai_dir):
    """New roughness (L8) and normal (octahedral RGB8) arrays at the mod's sizes, and the material's figures."""
    lo, hi, gain = classes[cls]
    r_path = os.path.join(mod, tex["reflectionroughness_texture"])
    r_size = _size(r_path)
    ai_rough = os.path.join(ai_dir, h + "_rough.png") if ai_dir else None
    src = ai_rough if ai_rough and os.path.isfile(ai_rough) else r_path
    rough0 = np.asarray(_load(src, "L"), np.float32) / 255
    old_mean = float(np.asarray(_load(r_path, "L"), np.float32).mean() / 255)
    rough = remap(rough0, lo, hi)
    rough = np.asarray(Image.fromarray(rough, "F").resize(r_size, Image.BILINEAR))
    info = {"class": cls, "range": [lo, hi], "gain": gain, "roughness_from": "ai" if src == ai_rough else "mod",
            "old_mean": round(old_mean, 3)}
    win = win_r = win_n = None
    alb = tex.get("diffuse_texture")
    if cls == "facade" and alb and os.path.isfile(os.path.join(mod, alb)):
        with Image.open(os.path.join(mod, alb)) as im:
            alpha = np.asarray(im.getchannel("A"), np.float32) / 255 if "A" in im.getbands() else None
        if alpha is not None:
            win = window_mask(alpha)  # at the albedo's size

    def scaled(mask, size):
        return np.clip(np.asarray(Image.fromarray(mask, "F").resize(size, Image.BILINEAR), np.float32), 0, 1)

    if win is not None:
        win_r = scaled(win, r_size)
        rough = rough * (1 - win_r) + WINDOW_ROUGH * win_r
        info["window_share"] = round(float((win_r > 0.5).mean()), 3)
    out = {"roughness": (np.clip(rough, 0, 1) * 255 + 0.5).astype(np.uint8)}
    n_rel = tex.get("normalmap_texture")
    if n_rel and os.path.isfile(os.path.join(mod, n_rel)) and (gain != 1.0 or win_r is not None or ai_dir):
        n_path = os.path.join(mod, n_rel)
        n_size = _size(n_path)
        ai_normal = os.path.join(ai_dir, h + "_normal.png") if ai_dir else None
        if ai_normal and os.path.isfile(ai_normal):
            rgb = np.asarray(_load(ai_normal, "RGB").resize(n_size, Image.BICUBIC), np.float32)
            n = rgb / 255 * 2 - 1
        else:
            n = oct_decode(np.asarray(_load(n_path, "RGB")))
        if win is not None:
            win_n = scaled(win, n_size)
        out["normal"] = oct_encode(scale_normals(n, gain, win_n))
    info["new_mean"] = round(float(out["roughness"].mean() / 255), 3)
    return out, info


def _size(path):
    with Image.open(path) as im:
        return im.size


def _load(path, mode):
    with Image.open(path) as im:
        return im.convert(mode)


def hardlink_copy(src, dst):
    for root, _dirs, files in os.walk(src):
        rel = os.path.relpath(root, src)
        os.makedirs(os.path.join(dst, rel), exist_ok=True)
        for f in files:
            os.link(os.path.join(root, f), os.path.join(dst, rel, f))


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--mod", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--source", action="append", required=True)
    ap.add_argument("--rules")
    ap.add_argument("--ai-dir")
    ap.add_argument("--work")
    ap.add_argument("--restore-grain", action="store_true")
    ap.add_argument("--grain-ratio", type=float, default=0.8)
    ap.add_argument("--grain-corr", type=float, default=0.7)
    ap.add_argument("--json")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--force", action="store_true")
    args = ap.parse_args(argv)
    if not os.path.isfile(os.path.join(args.mod, "mod.usda")):
        print("ERROR %s has no mod.usda" % args.mod)
        return 1
    for s in args.source:
        if not os.path.exists(s):
            print("ERROR source %s is missing" % s)
            return 1
    if os.path.exists(args.out) and not args.dry_run:
        if not args.force or not os.path.isfile(os.path.join(args.out, "mod.usda")):
            print("ERROR %s exists (--force replaces an earlier output, a folder with a mod.usda)" % args.out)
            return 1
    classes, rules = load_rules(args.rules)
    names = texture_names(args.source)
    mats = materials(args.mod)
    plan, report = {}, {"materials": {}, "kept": {}, "unnamed": [], "unclassified": []}
    for h, tex in sorted(mats.items()):
        if "reflectionroughness_texture" not in tex:
            continue
        name = names.get(h)
        if name is None:
            report["unnamed"].append(h)
            continue
        cls = classify(name, rules)
        if cls is None:
            report["unclassified"].append([h, name])
        elif cls == "skip":
            report["kept"][h] = name
        elif cls not in classes:
            print("ERROR rule class %s has no range" % cls)
            return 1
        else:
            plan[h] = (name, cls)
    print("materials %d: %d to retune, %d skipped by rule, %d unnamed, %d unclassified (kept)"
          % (len(mats), len(plan), len(report["kept"]), len(report["unnamed"]), len(report["unclassified"])))
    if args.dry_run:
        for h, (name, cls) in plan.items():
            report["materials"][h] = {"texture": name, "class": cls}
        if args.json:
            with open(args.json, "w", encoding="utf-8") as fh:
                json.dump(report, fh, indent=1)
        return 0
    sys.path.insert(0, RPAI_TOOL)
    from rpai import config, dds  # noqa: E402
    if not config.nvtt_path().exists():
        print("ERROR the NVTT exporter is missing: %s" % config.nvtt_path())
        return 1
    work = args.work or args.out.rstrip("\\/") + ".work"
    os.makedirs(work, exist_ok=True)
    if os.path.exists(args.out):
        shutil.rmtree(args.out)
    hardlink_copy(args.mod, args.out)
    src_imgs = {}
    if args.restore_grain:
        wanted = {}
        for h, (name, _cls) in plan.items():
            wanted.setdefault(name.lower(), set()).add(h)
        src_imgs = source_images(args.source, wanted)

    def one(item):
        h, (name, cls) = item
        maps, info = compose(args.mod, h, mats[h], cls, classes, args.ai_dir)
        info["texture"] = name
        jobs = []
        alb = mats[h].get("diffuse_texture")
        if h in src_imgs and alb and os.path.isfile(os.path.join(args.mod, alb)):
            albedo = _load(os.path.join(args.mod, alb), "RGBA")
            ratio, corr = grain_kept(src_imgs[h], albedo)
            info["grain_kept"], info["grain_corr"] = round(ratio, 3), round(corr, 3)
            if ratio < args.grain_ratio and corr >= args.grain_corr:
                png = os.path.join(work, "%s_albedo.png" % h)
                Image.fromarray(restore_grain(src_imgs[h], albedo), "RGBA").save(png)
                jobs.append((png, os.path.join(work, os.path.basename(alb)), "albedo", alb))
                info["grain_restored"] = True
        for kind, key in (("roughness", "reflectionroughness_texture"), ("normal", "normalmap_texture")):
            if kind in maps:
                png = os.path.join(work, "%s_%s.png" % (h, kind))
                Image.fromarray(maps[kind], "L" if kind == "roughness" else "RGB").save(png)
                jobs.append((png, os.path.join(work, os.path.basename(mats[h][key])), kind, mats[h][key]))
        return h, info, jobs

    jobs = []
    with ThreadPoolExecutor(8) as pool:
        for h, info, js in pool.map(one, plan.items()):
            report["materials"][h] = info
            jobs += js
    from pathlib import Path
    dds.encode([(Path(p), Path(o), k) for p, o, k, _ in jobs], workers=6, log=lambda *_: None)
    for _png, built, _kind, rel in jobs:
        dest = os.path.join(args.out, rel)
        tmp = dest + ".retune-tmp"
        shutil.copyfile(built, tmp)
        os.replace(tmp, dest)  # a new file: the hard link to --mod's copy is never written through
    means = [v["new_mean"] for v in report["materials"].values()]
    olds = [v["old_mean"] for v in report["materials"].values()]
    print("retuned %d materials (%d files): mean roughness %.3f -> %.3f; %d facades with glossy window panes; "
          "grain restored on %d albedos"
          % (len(plan), len(jobs), float(np.mean(olds)) if olds else 0, float(np.mean(means)) if means else 0,
             sum(1 for v in report["materials"].values() if "window_share" in v),
             sum(1 for v in report["materials"].values() if v.get("grain_restored"))))
    if args.json:
        with open(args.json, "w", encoding="utf-8") as fh:
            json.dump(report, fh, indent=1)
    return 0


if __name__ == "__main__":
    sys.exit(main())
