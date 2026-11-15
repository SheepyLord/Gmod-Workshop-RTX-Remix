"""Where each texture of a map shows: world area (floor, wall, ceiling) and props, from the map's BSP.

    python -I map_usage.py --source <map item .gma/.bin or .bsp> [--source <*_dir.vpk> ...] --json OUT

A module too (imported by repbr_map_mod.py). For every BSP in the first source it sums the faces' area per
material (the faces lump's own area field; sky, nodraw, hint, skip and trigger faces and `tools/` materials
left out), split by the face's plane into floor (normal z above 0.7), ceiling (below -0.7) and wall. VBSP's
cubemap copies (`maps/<map>/<material>_x_y_z`) count as their material. Each material's VMT, found in any
source, names its base texture (`$basetexture`; a blend's `$basetexture2` takes half the area). Props: the
static props of the game lump and the models the entities name; each counts its instances times the surface
of the model's box, shared among its textures (MDL texture names under each `$cdmaterials` folder, then the
VMT's base texture), and half of that is taken as seen.

The result maps each texture (lower case, without `materials/` and `.vtf`) to its share of the world area in
per cent (`world`, `floor`, `wall`, `ceiling`), its props' share (`props`), the models that use it, the VMTs
that name it and their flags. `importance()` weighs them for a texture budget: floor 1.5, wall 1, ceiling
0.6, props 1.

Exit codes: 0 written; 1 no BSP in the first source; 2 bad command line.
"""
from __future__ import annotations

import argparse
import io
import json
import lzma
import os
import re
import struct
import sys
import zipfile

SKIP_FLAGS = 0x2 | 0x4 | 0x40 | 0x80 | 0x100 | 0x200   # sky2d, sky, trigger, nodraw, hint, skip
FLAG_KEYS = ("$translucent", "$alphatest", "$additive", "$selfillum", "$envmap", "$basealphaenvmapmask",
             "$normalmapalphaenvmapmask", "$bumpmap", "$envmapmask", "$nocull", "$vertexalpha")
VMT_PAIR = re.compile(r'"?(\$[\w]+|%[\w]+|include)"?\s+"?([^"\r\n{}]*)"?', re.I)


# ---- containers -------------------------------------------------------------------------------

def _gma_entries(data: bytes):
    p = 5 + 16
    version = data[4]

    def cstr():
        nonlocal p
        e = data.index(b"\0", p)
        s = data[p:e].decode("utf-8", "replace")
        p = e + 1
        return s
    if version > 1:
        while cstr():
            pass
    cstr(); cstr(); cstr()
    p += 4
    index = []
    while True:
        num = struct.unpack_from("<I", data, p)[0]
        p += 4
        if num == 0:
            break
        name = cstr()
        size = struct.unpack_from("<q", data, p)[0]
        p += 12
        index.append((name, size))
    for name, size in index:
        yield name, data[p:p + size]
        p += size


def _pak_files(bsp: bytes, exts):
    if bsp[:4] != b"VBSP":
        return
    ofs, ln = struct.unpack_from("<ii", bsp, 8 + 16 * 40)
    try:
        z = zipfile.ZipFile(io.BytesIO(bsp[ofs:ofs + ln]))
    except zipfile.BadZipFile:
        return
    for info in z.infolist():
        if info.filename.lower().endswith(exts):
            try:
                yield info.filename, z.read(info)
            except Exception:  # noqa: BLE001  Valve's LZMA entries
                continue


def _vpk_files(path: str, exts):
    with open(path, "rb") as f:
        head = f.read(28)
        sig, version, tree = struct.unpack_from("<III", head, 0)
        if sig != 0x55AA1234:
            return
        header = 12 if version == 1 else 28
        f.seek(header)
        data = f.read(tree)
    base = path[:-len("_dir.vpk")]
    p = 0

    def cstr():
        nonlocal p
        e = data.index(b"\0", p)
        s = data[p:e].decode("utf-8", "replace")
        p = e + 1
        return s
    entries = []
    while True:
        ext = cstr()
        if not ext:
            break
        while True:
            folder = cstr()
            if not folder:
                break
            while True:
                name = cstr()
                if not name:
                    break
                _crc, preload, arch, off, length, _term = struct.unpack_from("<IHHIIH", data, p)
                p += 18
                pre = data[p:p + preload]
                p += preload
                if ("." + ext.lower()).endswith(exts):
                    entries.append(("%s/%s.%s" % (folder, name, ext), pre, arch, off, length))
    handles = {}
    try:
        for rel, pre, arch, off, length in entries:
            if arch == 0x7FFF:
                fpath, off = path, header + tree + off
            else:
                fpath = "%s_%03d.vpk" % (base, arch)
            fh = handles.get(fpath)
            if fh is None:
                fh = handles[fpath] = open(fpath, "rb")
            body = b""
            if length:
                fh.seek(off)
                body = fh.read(length)
            yield rel, pre + body
    finally:
        for fh in handles.values():
            fh.close()


def iter_files(path: str, exts=(".vmt",)):
    """(name, blob) of every file with one of `exts` in a .gma/.bin (and its BSPs' pakfiles), a .bsp, a
    *_dir.vpk or a folder. BSPs themselves are yielded when ".bsp" is in exts."""
    exts = tuple(e.lower() for e in exts)
    low = path.lower()
    if os.path.isdir(path):
        for folder, _, names in os.walk(path):
            for n in names:
                p = os.path.join(folder, n)
                if n.lower().endswith(exts):
                    with open(p, "rb") as f:
                        yield os.path.relpath(p, path).replace("\\", "/"), f.read()
                if n.lower().endswith(".bsp"):
                    with open(p, "rb") as f:
                        yield from _pak_files(f.read(), exts)
        return
    if low.endswith("_dir.vpk"):
        yield from _vpk_files(path, exts)
        return
    with open(path, "rb") as f:
        data = f.read()
    if low.endswith(".bsp"):
        if ".bsp" in exts:
            yield os.path.basename(path), data
        yield from _pak_files(data, exts)
        return
    if data[:4] != b"GMAD":
        data = lzma.LZMADecompressor(format=lzma.FORMAT_ALONE).decompress(data)
    for name, blob in _gma_entries(data):
        n = name.lower()
        if n.endswith(exts):
            yield name, blob
        if n.endswith(".bsp"):
            yield from _pak_files(blob, exts)


# ---- BSP, VMT, MDL ----------------------------------------------------------------------------

def _lump(blob, i):
    ofs, ln = struct.unpack_from("<ii", blob, 8 + 16 * i)
    return blob[ofs:ofs + ln]


def norm_texture(t: str) -> str:
    """'Materials\\Foo/Bar.vtf' and 'pak:materials/foo/bar' -> 'foo/bar'."""
    t = t.replace("\\", "/").strip().lower()
    if t.startswith("pak:"):
        t = t[4:]
    if t.startswith("materials/"):
        t = t[len("materials/"):]
    for ext in (".vtf", ".vmt"):
        if t.endswith(ext):
            t = t[:-4]
    return t.strip("/")


def bsp_faces(blob: bytes, mapname: str):
    """{material: [floor, wall, ceiling] area} of a BSP's drawn faces."""
    planes = _lump(blob, 1)
    texdata = _lump(blob, 2)
    texinfo = _lump(blob, 6)
    faces = _lump(blob, 7)
    strdata = _lump(blob, 43)
    strtab = _lump(blob, 44)
    names = []
    for i in range(len(texdata) // 32):
        sid = struct.unpack_from("<i", texdata, i * 32 + 12)[0]
        off = struct.unpack_from("<i", strtab, sid * 4)[0]
        names.append(strdata[off:strdata.index(b"\0", off)].decode("latin-1").replace("\\", "/").lower())
    pre = "maps/%s/" % mapname.lower()
    cube = re.compile(r"_-?\d+_-?\d+_-?\d+$")
    out = {}
    for i in range(len(faces) // 56):
        plane, side = struct.unpack_from("<HB", faces, i * 56)
        tinfo = struct.unpack_from("<h", faces, i * 56 + 10)[0]
        area = struct.unpack_from("<f", faces, i * 56 + 24)[0]
        if tinfo < 0 or area <= 0:
            continue
        flags, tdata = struct.unpack_from("<ii", texinfo, tinfo * 72 + 64)
        if flags & SKIP_FLAGS or tdata < 0 or tdata >= len(names):
            continue
        name = names[tdata]
        if name.startswith(pre):
            name = cube.sub("", name[len(pre):])
        # Hammer can store a material at the root as "/name" (Country Estate's custom textures): the VMT is
        # materials/name.vmt, so the name is normalised like every VMT path
        name = re.sub(r"/+", "/", name).strip("/")
        if name.endswith("_wvt_patch"):   # VBSP's copy of a blend for displacements: its base material
            name = name[:-len("_wvt_patch")]
        if name.startswith("tools/"):
            continue
        nz = struct.unpack_from("<f", planes, plane * 20 + 8)[0] * (-1 if side else 1)
        slot = 0 if nz > 0.7 else 2 if nz < -0.7 else 1
        acc = out.setdefault(name, [0.0, 0.0, 0.0])
        acc[slot] += area
    return out


DECAL_AREA = 64.0 * 64.0   # an infodecal's area in square units (its size is the texture's, unknown here)


def bsp_overlays(blob: bytes, mapname: str):
    """{material: area} of the BSP's overlays (lump 45: posters, signs, stains placed on brushes; each overlay's
    area from its four UV points) and of its infodecal entities (DECAL_AREA each)."""
    texdata = _lump(blob, 2)
    texinfo = _lump(blob, 6)
    strdata = _lump(blob, 43)
    strtab = _lump(blob, 44)
    ov = _lump(blob, 45)
    out = {}

    def material(tinfo):
        if tinfo < 0 or (tinfo + 1) * 72 > len(texinfo):
            return None
        tdata = struct.unpack_from("<i", texinfo, tinfo * 72 + 68)[0]
        if tdata < 0 or (tdata + 1) * 32 > len(texdata):
            return None
        sid = struct.unpack_from("<i", texdata, tdata * 32 + 12)[0]
        off = struct.unpack_from("<i", strtab, sid * 4)[0]
        name = strdata[off:strdata.index(b"\0", off)].decode("latin-1").replace("\\", "/").lower()
        return re.sub(r"/+", "/", name).strip("/")
    size = 352   # doverlay_t: id, texinfo, face count, 64 faces, U, V, 4 UV points, origin, normal
    for i in range(len(ov) // size):
        base = i * size
        tinfo = struct.unpack_from("<h", ov, base + 4)[0]
        name = material(tinfo)
        if not name:
            continue
        pts = [struct.unpack_from("<3f", ov, base + 280 + 12 * k) for k in range(4)]
        area = 0.5 * abs(sum(pts[k][0] * pts[(k + 1) % 4][1] - pts[(k + 1) % 4][0] * pts[k][1] for k in range(4)))
        out[name] = out.get(name, 0.0) + max(area, 1.0)
    ents = _lump(blob, 0).decode("latin-1", "replace")
    for block in re.findall(r"\{([^{}]*)\}", ents):
        if re.search(r'"classname"\s+"infodecal"', block, re.I):
            m = re.search(r'"texture"\s+"([^"]+)"', block, re.I)
            if m:
                name = re.sub(r"/+", "/", m.group(1).replace("\\", "/").lower()).strip("/")
                out[name] = out.get(name, 0.0) + DECAL_AREA
    return out


def bsp_props(blob: bytes):
    """{model: instances} from the static props and the entities' "model" keys."""
    counts = {}
    gl = _lump(blob, 35)
    if len(gl) >= 4:
        for i in range(struct.unpack_from("<i", gl, 0)[0]):
            gid, _flags, _ver, ofs, ln = struct.unpack_from("<iHHii", gl, 4 + 16 * i)
            if gid != 0x73707270:  # 'sprp'
                continue
            data = blob[ofs:ofs + ln]
            n = struct.unpack_from("<i", data, 0)[0]
            models = [data[4 + 128 * j:4 + 128 * (j + 1)].split(b"\0")[0].decode("latin-1").lower().replace("\\", "/")
                      for j in range(n)]
            p = 4 + 128 * n
            p += 4 + 2 * struct.unpack_from("<i", data, p)[0]
            props = struct.unpack_from("<i", data, p)[0]
            p += 4
            size = (ln - p) // props if props else 0
            for j in range(props):
                mi = struct.unpack_from("<H", data, p + j * size + 24)[0]
                if mi < len(models):
                    counts[models[mi]] = counts.get(models[mi], 0) + 1
    ents = _lump(blob, 0).decode("latin-1", "replace")
    for m in re.findall(r'"model"\s+"(models/[^"]+\.mdl)"', ents, re.I):
        m = m.lower().replace("\\", "/")
        counts[m] = counts.get(m, 0) + 1
    return counts


def parse_vmt(text: str):
    """(shader, {lower-case key: value}) of a VMT; the first value of a key wins."""
    m = re.match(r'\s*"?([\w]+)"?', text)
    keys = {}
    for k, v in VMT_PAIR.findall(text):
        keys.setdefault(k.lower(), v.strip())
    return (m.group(1).lower() if m else ""), keys


def mdl_info(blob: bytes):
    """{"textures", "cdmaterials", "box_area"} of a studio model, or None."""
    if blob[:4] != b"IDST" or len(blob) < 220:
        return None
    vmin = struct.unpack_from("<3f", blob, 128)
    vmax = struct.unpack_from("<3f", blob, 140)
    if vmin == vmax:
        vmin, vmax = struct.unpack_from("<3f", blob, 104), struct.unpack_from("<3f", blob, 116)
    ntex, itex, ncd, icd = struct.unpack_from("<4i", blob, 204)
    names, cds = [], []
    for i in range(max(0, min(ntex, 512))):
        base = itex + 64 * i
        off = struct.unpack_from("<i", blob, base)[0]
        names.append(blob[base + off:blob.index(b"\0", base + off)].decode("latin-1").replace("\\", "/").lower())
    for i in range(max(0, min(ncd, 64))):
        off = struct.unpack_from("<i", blob, icd + 4 * i)[0]
        cds.append(blob[off:blob.index(b"\0", off)].decode("latin-1").replace("\\", "/").lower().strip("/"))
    dx, dy, dz = (abs(b - a) for a, b in zip(vmin, vmax))
    return {"textures": names, "cdmaterials": cds, "box_area": 2 * (dx * dy + dy * dz + dz * dx)}


# ---- usage --------------------------------------------------------------------------------------

def usage(sources, log=print):
    """The usage table of the BSPs in sources[0] (see the module's docstring)."""
    faces, props, maps, overlays = {}, {}, [], {}
    for name, blob in iter_files(sources[0], (".bsp",)):
        if blob[:4] != b"VBSP":
            continue
        mapname = os.path.basename(name)[:-4]
        maps.append(mapname)
        for mat, acc in bsp_faces(blob, mapname).items():
            f = faces.setdefault(mat, [0.0, 0.0, 0.0])
            for i in range(3):
                f[i] += acc[i]
        for m, n in bsp_props(blob).items():
            props[m] = props.get(m, 0) + n
        for m, area in bsp_overlays(blob, mapname).items():
            overlays[m] = overlays.get(m, 0.0) + area
    if not maps:
        return None
    vmts, models = {}, {}
    for src in sources:
        for rel, blob in iter_files(src, (".vmt", ".mdl")):
            key = rel.replace("\\", "/").lower()
            if key.endswith(".vmt"):
                k = norm_texture(key)
                if k not in vmts:
                    vmts[k] = parse_vmt(blob.decode("latin-1", "replace"))
            elif key in props and key not in models:
                try:
                    info = mdl_info(blob)
                except (struct.error, ValueError):
                    info = None
                if info:
                    models[key] = info
        log("read %s: %d VMTs, %d of %d models" % (os.path.basename(src), len(vmts), len(models), len(props)))
    total = sum(sum(v) for v in faces.values()) or 1.0
    # overlays and decals lie on faces already counted: they weigh their texture (as wall) but not the total
    for m, area in overlays.items():
        faces.setdefault(m, [0.0, 0.0, 0.0])[1] += area
    tex = {}

    def entry(t):
        return tex.setdefault(t, {"world": 0.0, "floor": 0.0, "wall": 0.0, "ceiling": 0.0, "props": 0.0,
                                  "models": {}, "vmts": [], "shader": "", "surfaceprop": "", "flags": []})

    def note(t, mat, shader, keys):
        e = entry(t)
        if mat not in e["vmts"]:
            e["vmts"].append(mat)
        e["shader"] = e["shader"] or shader
        e["surfaceprop"] = e["surfaceprop"] or keys.get("$surfaceprop", "").lower()
        for k in FLAG_KEYS:
            v = keys.get(k, "")
            if v and v not in ("0", "") and k[1:] not in e["flags"]:
                e["flags"].append(k[1:])

    for mat, (fl, wa, ce) in faces.items():
        vm = vmts.get(mat)
        if not vm:
            continue
        shader, keys = vm
        bases = [keys[k] for k in ("$basetexture", "$basetexture2") if keys.get(k)]
        for b in bases:
            t = norm_texture(b)
            e = entry(t)
            share = 100.0 / total / len(bases)
            e["floor"] += fl * share
            e["wall"] += wa * share
            e["ceiling"] += ce * share
            e["world"] += (fl + wa + ce) * share
            note(t, mat, shader, keys)
    for m, n in props.items():
        info = models.get(m)
        if not info or not info["textures"]:
            continue
        seen = 0.5 * n * info["box_area"] / len(info["textures"]) * 100.0 / total
        for tname in info["textures"]:
            for cd in info["cdmaterials"] or [""]:
                key = norm_texture(cd + "/" + tname)
                vm = vmts.get(key)
                if vm and vm[1].get("$basetexture"):
                    t = norm_texture(vm[1]["$basetexture"])
                    e = entry(t)
                    e["props"] += seen
                    e["models"][m] = e["models"].get(m, 0) + n
                    note(t, key, *vm)
                    break
    for e in tex.values():
        for k in ("world", "floor", "wall", "ceiling", "props"):
            e[k] = round(e[k], 4)
    unmatched = sorted(((m, round(100.0 * sum(a) / total, 4)) for m, a in faces.items() if m not in vmts),
                       key=lambda kv: -kv[1])
    return {"maps": maps, "world_area": round(total), "textures": tex, "unmatched": unmatched}


def importance(e) -> float:
    """A texture's weight for a size budget: floor 1.5, wall 1, ceiling 0.6, props 1 (per cent of the
    world's area)."""
    if not e:
        return 0.0
    return 1.5 * e.get("floor", 0) + e.get("wall", 0) + 0.6 * e.get("ceiling", 0) + e.get("props", 0)


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    ap.add_argument("--source", action="append", required=True)
    ap.add_argument("--json", required=True)
    a = ap.parse_args(argv)
    for s in a.source:
        if not os.path.exists(s):
            print("ERROR missing source: %s" % s)
            return 1
    u = usage(a.source)
    if u is None:
        print("ERROR no BSP in %s" % a.source[0])
        return 1
    with open(a.json, "w", encoding="utf-8") as fh:
        json.dump(u, fh, indent=1, sort_keys=True)
    top = sorted(u["textures"].items(), key=lambda kv: -importance(kv[1]))[:12]
    print("maps %s: %d textures used; most weight: %s" % (", ".join(u["maps"]), len(u["textures"]),
          ", ".join("%s %.2f" % (t, importance(e)) for t, e in top)))
    if u["unmatched"]:
        print("faces whose material has no VMT in the sources: %d, %.2f %% of the area (%s)" % (
            len(u["unmatched"]), sum(a for _m, a in u["unmatched"]),
            ", ".join(m for m, _a in u["unmatched"][:5])))
    return 0


if __name__ == "__main__":
    sys.exit(main())
