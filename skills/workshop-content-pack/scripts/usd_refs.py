"""The files a Remix mod's USD layers reference, text (.usda) and binary crate (.usd/.usdc) alike.

Standard library only (no pxr). Imported by check_pack.py and port_classic_mods.py.

    walk(mod)                  every layer reached from mod.usda (sub-layers, references, payloads),
                               every file they name, the names that resolve to nothing, the shaders
    layer_references(path)     the asset paths one layer names, in file order
    crate_tokens(path)         the token table of a binary crate layer (asset paths live there)
    blank_missing(text, layer_dir, exists)   a text layer with references to missing files set to @@

A text layer's asset paths are @...@ (or @@@...@@@); @@ is an empty asset (Remix: "no texture") and is
not a reference. A crate stores every asset path, sub-layer path and reference path as a token; the
token table is LZ4-compressed (TfFastCompression), which this module decodes itself.
"""
from __future__ import annotations

import os
import re
import struct

LAYER_EXTENSIONS = (".usd", ".usda", ".usdc")
SHADER_EXTENSIONS = (".mdl",)
# What a token must end with to be taken for an asset path in a crate layer.
PATH_LIKE = re.compile(r"\.(dds|png|jpe?g|tga|bmp|exr|hdr|usd|usda|usdc|usdz|mdl)$", re.I)


# ---- text layers ------------------------------------------------------------------------------

def text_references(text: str):
    """(start, end, path) of every non-empty asset path in a .usda text, skipping strings and comments.

    start/end span the whole @...@ (or @@@...@@@) so a caller can replace it."""
    out = []
    i, n = 0, len(text)
    while i < n:
        c = text[i]
        if c == "#":  # a comment runs to the end of the line
            j = text.find("\n", i)
            i = n if j < 0 else j
            continue
        if c == '"':
            if text.startswith('"""', i):
                j = text.find('"""', i + 3)
                i = n if j < 0 else j + 3
            else:
                j = i + 1
                while j < n and text[j] != '"' and text[j] != "\n":
                    j += 2 if text[j] == "\\" else 1
                i = j + 1
            continue
        if c == "@":
            if text.startswith("@@@", i):
                j = text.find("@@@", i + 3)
                if j < 0:
                    break
                out.append((i, j + 3, text[i + 3:j]))
                i = j + 3
                continue
            if text.startswith("@@", i):  # the empty asset
                i += 2
                continue
            j = text.find("@", i + 1)
            if j < 0 or "\n" in text[i + 1:j]:
                i += 1
                continue
            out.append((i, j + 1, text[i + 1:j]))
            i = j + 1
            continue
        i += 1
    return out


def blank_missing(text: str, layer_dir: str, exists=os.path.isfile):
    """(new text, [missing paths]): every relative reference that does not resolve becomes @@.

    Only file references are blanked; a missing sub-layer or reference to a layer stays (an error to
    fix by hand), and so does a bare shader name (Remix resolves .mdl by name)."""
    missing, pieces, last = [], [], 0
    for start, end, ref in text_references(text):
        if ref.lower().endswith(LAYER_EXTENSIONS) or not ref.startswith(("./", "../")):
            continue
        if exists(os.path.normpath(os.path.join(layer_dir, ref))):
            continue
        missing.append(ref)
        pieces.append(text[last:start])
        pieces.append("@@")
        last = end
    pieces.append(text[last:])
    return "".join(pieces), missing


# ---- crate layers -----------------------------------------------------------------------------

def is_crate(path: str) -> bool:
    with open(path, "rb") as fh:
        return fh.read(8) == b"PXR-USDC"


def lz4_block(src: bytes, limit: int) -> bytes:
    """Decode one raw LZ4 block (no frame), at most limit bytes."""
    out = bytearray()
    i, n = 0, len(src)
    while i < n:
        token = src[i]
        i += 1
        length = token >> 4
        if length == 15:
            while True:
                b = src[i]
                i += 1
                length += b
                if b != 255:
                    break
        out += src[i:i + length]
        i += length
        if i >= n:
            break
        offset = src[i] | (src[i + 1] << 8)
        i += 2
        if offset == 0 or offset > len(out):
            raise ValueError("LZ4: bad match offset %d" % offset)
        match = token & 15
        if match == 15:
            while True:
                b = src[i]
                i += 1
                match += b
                if b != 255:
                    break
        match += 4
        start = len(out) - offset
        if offset >= match:
            out += out[start:start + match]
        else:
            for k in range(match):
                out.append(out[start + k])
        if len(out) > limit:
            raise ValueError("LZ4: output past %d bytes" % limit)
    return bytes(out)


def fast_decompress(data: bytes, size: int) -> bytes:
    """TfFastCompression: a chunk count byte, then one LZ4 block (0) or that many size-prefixed blocks."""
    chunks = data[0]
    if chunks == 0:
        return lz4_block(data[1:], size)
    out, i = bytearray(), 1
    for _ in range(chunks):
        (length,) = struct.unpack_from("<i", data, i)
        i += 4
        out += lz4_block(data[i:i + length], size - len(out))
        i += length
    return bytes(out)


def crate_tokens(path: str):
    """The token table of a crate layer (version 0.4.0 or later: compressed tokens)."""
    with open(path, "rb") as fh:
        data = fh.read()
    if data[:8] != b"PXR-USDC":
        raise ValueError("%s is not a USD crate file" % path)
    major, minor = data[8], data[9]
    if (major, minor) < (0, 4):
        raise ValueError("%s: crate version %d.%d predates compressed tokens" % (path, major, minor))
    (toc,) = struct.unpack_from("<Q", data, 16)
    (count,) = struct.unpack_from("<Q", data, toc)
    for k in range(count):
        name, start, _size = struct.unpack_from("<16sqq", data, toc + 8 + 32 * k)
        if name.rstrip(b"\0") != b"TOKENS":
            continue
        (tokens, raw, packed) = struct.unpack_from("<QQQ", data, start)
        text = fast_decompress(data[start + 24:start + 24 + packed], raw)
        names = text.split(b"\0")
        if names and names[-1] == b"":
            names.pop()
        if len(names) != tokens:
            raise ValueError("%s: %d tokens, the header says %d" % (path, len(names), tokens))
        return [t.decode("utf-8", "replace") for t in names]
    raise ValueError("%s has no TOKENS section" % path)


# ---- one layer, a whole mod -------------------------------------------------------------------

def layer_references(path: str):
    """The asset paths a layer names (text or crate), in file order, without repeats."""
    if is_crate(path):
        found = [t for t in crate_tokens(path) if PATH_LIKE.search(t) and "\n" not in t]
    else:
        with open(path, encoding="utf-8", errors="replace") as fh:
            found = [ref for _, _, ref in text_references(fh.read())]
    seen, out = set(), []
    for ref in found:
        if ref not in seen:
            seen.add(ref)
            out.append(ref)
    return out


class Walk:
    """What walk() found, paths relative to the mod with / separators."""

    def __init__(self):
        self.layers = []        # every layer reached, mod.usda first
        self.crate = []         # the layers among them that are binary crates
        self.files = {}         # referenced non-layer file -> the layers naming it
        self.missing = []       # (layer, reference) that resolve to nothing
        self.outside = []       # (layer, reference) that leave the mod
        self.bare = []          # (layer, reference) neither ./ ../ nor a shader name
        self.shaders = set()    # bare shader names (Remix resolves them itself)
        self.errors = []        # (layer, text) a layer that could not be read

    def used(self):
        return {p.lower() for p in self.layers} | {p.lower() for p in self.files}


def walk(mod: str, root: str = "mod.usda") -> Walk:
    """Follow every layer from root: sub-layers, references and payloads to .usd/.usda/.usdc files."""
    w = Walk()
    queue, seen = [root], set()
    while queue:
        rel = queue.pop(0)
        key = rel.lower()
        if key in seen:
            continue
        seen.add(key)
        path = os.path.join(mod, rel)
        w.layers.append(rel)
        try:
            if is_crate(path):
                w.crate.append(rel)
            refs = layer_references(path)
        except (OSError, ValueError, IndexError, struct.error) as error:
            w.errors.append((rel, str(error)))
            continue
        for ref in refs:
            if not ref.startswith(("./", "../")):
                if ref.lower().endswith(SHADER_EXTENSIONS) and "/" not in ref and "\\" not in ref:
                    w.shaders.add(ref)
                    # USD anchors a bare name to the layer's folder first: a shader file there is used.
                    beside = os.path.normpath(os.path.join(os.path.dirname(rel), ref)).replace("\\", "/")
                    if os.path.isfile(os.path.join(mod, beside)):
                        w.files.setdefault(beside, []).append(rel)
                else:
                    w.bare.append((rel, ref))
                continue
            inner = os.path.normpath(os.path.join(os.path.dirname(rel), ref)).replace("\\", "/")
            if inner.startswith("../") or inner == "..":
                w.outside.append((rel, ref))
                continue
            if not os.path.isfile(os.path.join(mod, inner)):
                w.missing.append((rel, ref))
                continue
            if inner.lower().endswith(LAYER_EXTENSIONS):
                queue.append(inner)
            else:
                w.files.setdefault(inner, []).append(rel)
    return w


def mod_files(mod: str):
    """Every file in the mod folder, relative with / separators."""
    out = []
    for folder, _, names in os.walk(mod):
        for name in names:
            out.append(os.path.relpath(os.path.join(folder, name), mod).replace("\\", "/"))
    return sorted(out)
