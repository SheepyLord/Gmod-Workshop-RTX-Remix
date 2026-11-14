"""Remix texture hashes of Source VTFs, read from Workshop archives, BSP pakfiles, VPKs and folders.

A module (imported by rekey_mod_hashes.py and identify_map_mod.py). Needs `xxhash` (the system Python
has it); everything else is the standard library.

The runtime hashes the CPU copy of a texture's top mip as the game uploaded it: XXH64 (seed 0) when
`rtx.useObsoleteHashOnTextureUpload` is True (the RTX package's classic defaults), XXH3-64 otherwise
(Remix's default). Block-compressed VTFs go up as they are. Uncompressed ones are converted by the game
to a format the device takes (RGBA8888 to BGRA, or BGRX with the pad byte hashed as 0, ...). Where the
layout is not certain this module returns several candidate byte layouts per frame; both hash functions
are computed on the same candidate, so a candidate whose XXH3 matches a mod's hash gives that texture's
XXH64 exactly, and the others match nothing.

    texture_hashes(blob)            [(xxh64, xxh3), ...] for every frame and candidate layout ("%016X")
    iter_vtfs(path)                 (name, blob) of every VTF in a .gma, legacy .bin, .bsp, *_dir.vpk or folder
"""
from __future__ import annotations

import io
import lzma
import os
import struct
import zipfile

import xxhash

# VTF image formats: id -> (bytes per pixel, or block bytes for 4x4 blocks), block?
FORMATS = {
    0: (4, False), 1: (4, False), 2: (3, False), 3: (3, False), 4: (2, False), 5: (1, False), 6: (2, False),
    7: (1, False), 8: (1, False), 9: (3, False), 10: (3, False), 11: (4, False), 12: (4, False),
    13: (8, True), 14: (16, True), 15: (16, True), 16: (4, False), 17: (2, False), 18: (2, False),
    19: (2, False), 20: (8, True), 21: (2, False), 22: (2, False), 23: (4, False), 24: (8, False),
    25: (8, False), 26: (4, False),
}
FLAG_ONEBITALPHA, FLAG_EIGHTBITALPHA, FLAG_ENVMAP = 0x1000, 0x2000, 0x4000


def image_bytes(fmt: int, w: int, h: int) -> int:
    unit, block = FORMATS[fmt]
    if block:
        return max(1, (w + 3) // 4) * max(1, (h + 3) // 4) * unit
    return w * h * unit


class Vtf:
    def __init__(self, blob: bytes):
        if blob[:4] != b"VTF\0":
            raise ValueError("not a VTF")
        major, minor, header = struct.unpack_from("<III", blob, 4)
        self.w, self.h, self.flags, self.frames = struct.unpack_from("<HHIH", blob, 16)
        self.fmt = struct.unpack_from("<i", blob, 52)[0]
        self.mips = blob[56]
        low_fmt = struct.unpack_from("<i", blob, 57)[0]
        low_w, low_h = blob[61], blob[62]
        self.depth = struct.unpack_from("<H", blob, 63)[0] if (major, minor) >= (7, 2) else 1
        self.depth = max(1, self.depth)
        self.frames = max(1, self.frames)
        if self.fmt not in FORMATS:
            raise ValueError("VTF format %d" % self.fmt)
        self.faces = 1
        if self.flags & FLAG_ENVMAP:
            self.faces = 6 if (major, minor) >= (7, 5) else 7
        data = None
        if (major, minor) >= (7, 3):
            count = struct.unpack_from("<I", blob, 68)[0]
            for i in range(count):
                tag, flags, value = struct.unpack_from("<3sBI", blob, 80 + 8 * i)
                if tag == b"\x30\0\0":
                    data = value
        if data is None:
            data = header + (image_bytes(low_fmt, low_w, low_h) if low_fmt in FORMATS and low_w and low_h else 0)
        self.data = data
        self.blob = blob

    def top_frames(self):
        """The top mip of each frame (face 0, slice 0), as stored."""
        per_level = [image_bytes(self.fmt, max(1, self.w >> m), max(1, self.h >> m)) for m in range(self.mips)]
        offset = self.data
        for m in range(self.mips - 1, 0, -1):  # smallest mip first
            offset += per_level[m] * self.frames * self.faces * max(1, self.depth >> m)
        size = per_level[0]
        stride = size * self.faces * self.depth
        out = []
        for f in range(self.frames):
            start = offset + f * stride
            chunk = self.blob[start:start + size]
            if len(chunk) != size:
                raise ValueError("truncated VTF")
            out.append(chunk)
        return out


def _swizzle(data: bytes, order, pad=None, src=4) -> bytes:
    """Reorder channels of `src`-byte pixels into BGRA (order: source index of B, G, R, A or None)."""
    n = len(data) // src
    out = bytearray(n * 4)
    for k, idx in enumerate(order):
        if idx is None:
            if pad is not None:
                out[k::4] = bytes([pad]) * n
        else:
            out[k::4] = data[idx::src]
    return bytes(out)


def upload_candidates(v: Vtf, top: bytes):
    """Byte layouts the game may have uploaded for one top mip."""
    fmt = v.fmt
    alpha = bool(v.flags & (FLAG_ONEBITALPHA | FLAG_EIGHTBITALPHA))
    if FORMATS[fmt][1]:
        return [top]
    if fmt == 0:   # RGBA8888
        return [_swizzle(top, (2, 1, 0, 3)), _swizzle(top, (2, 1, 0, None), 0)] if alpha else \
            [_swizzle(top, (2, 1, 0, None), 0), _swizzle(top, (2, 1, 0, 3))]
    if fmt == 1:   # ABGR8888
        return [_swizzle(top, (1, 2, 3, 0)), _swizzle(top, (1, 2, 3, None), 0)]
    if fmt == 11:  # ARGB8888 (stored as in Source's enum name)
        return [_swizzle(top, (3, 2, 1, 0)), _swizzle(top, (3, 2, 1, None), 0)]
    if fmt == 12:  # BGRA8888
        return [top, _swizzle(top, (0, 1, 2, None), 0)]
    if fmt == 16:  # BGRX8888
        return [_swizzle(top, (0, 1, 2, None), 0), top]
    if fmt in (2, 9):   # RGB888
        return [_swizzle(top, (2, 1, 0, None), 0, 3), _swizzle(top, (2, 1, 0, None), 255, 3), top]
    if fmt in (3, 10):  # BGR888
        return [_swizzle(top, (0, 1, 2, None), 0, 3), _swizzle(top, (0, 1, 2, None), 255, 3), top]
    return [top]


def texture_hashes(blob: bytes):
    """[(xxh64, xxh3)] over every frame's top mip and every candidate layout."""
    v = Vtf(blob)
    out = []
    for top in v.top_frames():
        for data in upload_candidates(v, top):
            out.append(("%016X" % xxhash.xxh64_intdigest(data, seed=0), "%016X" % xxhash.xxh3_64_intdigest(data)))
    return out


def source_table(path: str, cache: dict, log=print):
    """[(xxh64, xxh3, width, height)] for every VTF of one source, from `cache` when the source is
    unchanged (keyed by path, size and time)."""
    st = os.stat(path)
    key = "v2|%s|%d|%d" % (os.path.abspath(path).lower(), st.st_size, int(st.st_mtime))
    if key not in cache:
        rows, failed = [], 0
        for _, blob in iter_vtfs(path):
            try:
                v = Vtf(blob)
                rows.extend([x64, x3, v.w, v.h] for x64, x3 in texture_hashes(blob))
            except (ValueError, KeyError, IndexError, struct.error):
                failed += 1
        cache[key] = rows
        log("hashed %s: %d layouts (%d VTFs unreadable)" % (path, len(rows), failed))
    return cache[key]


def load_cache(path):
    import json
    if path and os.path.isfile(path):
        with open(path, encoding="utf-8") as fh:
            return json.load(fh)
    return {}


def save_cache(path, cache):
    import json
    if path:
        os.makedirs(os.path.dirname(os.path.abspath(path)), exist_ok=True)
        tmp = path + ".tmp"
        with open(tmp, "w", encoding="utf-8") as fh:
            json.dump(cache, fh)
        os.replace(tmp, path)


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


def _bsp_pak(bsp: bytes):
    if bsp[:4] != b"VBSP":
        return
    ofs, ln = struct.unpack_from("<ii", bsp, 8 + 16 * 40)
    try:
        z = zipfile.ZipFile(io.BytesIO(bsp[ofs:ofs + ln]))
    except zipfile.BadZipFile:
        return
    for info in z.infolist():
        if info.filename.lower().endswith(".vtf"):
            try:
                yield "pak:" + info.filename, z.read(info)
            except Exception:  # Valve's LZMA entries
                continue


def _vpk(path: str):
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
                crc, preload, arch, off, length, term = struct.unpack_from("<IHHIIH", data, p)
                p += 18
                pre = data[p:p + preload]
                p += preload
                if ext.lower() == "vtf" and folder.lower().startswith("materials"):
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


def iter_vtfs(path: str):
    """(name, blob) of every VTF a source holds: a Workshop .gma or legacy .bin (with its BSPs'
    pakfiles), a .bsp, a *_dir.vpk, or a folder (searched for .vtf, .gma and .bsp files)."""
    low = path.lower()
    if os.path.isdir(path):
        for folder, _, names in os.walk(path):
            for n in names:
                p = os.path.join(folder, n)
                if n.lower().endswith(".vtf"):
                    with open(p, "rb") as f:
                        yield os.path.relpath(p, path).replace("\\", "/"), f.read()
                elif n.lower().endswith((".gma", ".bsp")):
                    yield from iter_vtfs(p)
        return
    if low.endswith("_dir.vpk"):
        yield from _vpk(path)
        return
    with open(path, "rb") as f:
        data = f.read()
    if low.endswith(".bsp"):
        yield from _bsp_pak(data)
        return
    if data[:4] != b"GMAD":
        data = lzma.LZMADecompressor(format=lzma.FORMAT_ALONE).decompress(data)
    for name, blob in _gma_entries(data):
        n = name.lower()
        if n.endswith(".vtf"):
            yield name, blob
        elif n.endswith(".bsp"):
            yield from _bsp_pak(blob)
