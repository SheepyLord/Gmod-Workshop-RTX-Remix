"""Unit tests of vtf_hash.py, rekey_mod_hashes.py and fit_mod.py on synthetic VTFs, VPKs, archives and
mods (all written here; nothing from a game)."""
import io
import json
import os
import struct
import sys
import tempfile
import unittest
from contextlib import redirect_stdout

import xxhash

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import fit_map_mod as F  # noqa: E402
import fit_mod  # noqa: E402
import rekey_mod_hashes  # noqa: E402
import vtf_hash as V  # noqa: E402
from test_fit_map_mod import make_dds  # noqa: E402


def make_vtf(fmt, w, h, top, frames=1, flags=0, version=(7, 2)):
    """A VTF with one mip (the top), no low-res image, `frames` frames of `top` (bytes or list)."""
    header = 80
    head = bytearray(header)
    head[0:4] = b"VTF\0"
    struct.pack_into("<III", head, 4, version[0], version[1], header)
    struct.pack_into("<HHIHH", head, 16, w, h, flags, frames, 0)
    struct.pack_into("<i", head, 52, fmt)
    head[56] = 1
    struct.pack_into("<i", head, 57, -1)
    struct.pack_into("<H", head, 63, 1)
    tops = top if isinstance(top, list) else [top] * frames
    return bytes(head) + b"".join(tops)


def gma(files):
    out = bytearray(b"GMAD\x03" + bytes(16) + b"\0" + b"t\0" + b"{}\0" + b"a\0" + struct.pack("<I", 1))
    for i, (name, data) in enumerate(files, 1):
        out += struct.pack("<I", i) + name.encode() + b"\0" + struct.pack("<qI", len(data), 0)
    out += struct.pack("<I", 0)
    for _, data in files:
        out += data
    return bytes(out) + struct.pack("<I", 0)


def vpk_dir(entries):
    """A VPK v1 dir file holding every entry's data in the dir file itself (archive index 0x7fff)."""
    tree, blob = bytearray(), bytearray()
    by_ext = {}
    for path, data in entries:
        folder, name = path.rsplit("/", 1)
        stem, ext = name.rsplit(".", 1)
        by_ext.setdefault(ext, {}).setdefault(folder, []).append((stem, data))
    for ext, folders in by_ext.items():
        tree += ext.encode() + b"\0"
        for folder, files in folders.items():
            tree += folder.encode() + b"\0"
            for stem, data in files:
                tree += stem.encode() + b"\0" + struct.pack("<IHHIIH", 0, 0, 0x7FFF, len(blob), len(data), 0xFFFF)
                blob += data
            tree += b"\0"
        tree += b"\0"
    tree += b"\0"
    return struct.pack("<III", 0x55AA1234, 1, len(tree)) + bytes(tree) + bytes(blob)


def h64(b):
    return "%016X" % xxhash.xxh64_intdigest(b, seed=0)


def h3(b):
    return "%016X" % xxhash.xxh3_64_intdigest(b)


class VtfHash(unittest.TestCase):
    def test_dxt_frames_and_versions(self):
        a, b = bytes(range(8)), bytes(range(8, 16))
        blob = make_vtf(13, 4, 4, [a, b], frames=2)
        self.assertEqual(V.texture_hashes(blob), [(h64(a), h3(a)), (h64(b), h3(b))])
        blob73 = bytearray(make_vtf(13, 4, 4, a, version=(7, 3)))
        struct.pack_into("<I", blob73, 68, 1)
        blob73[80:88] = b"\x30\0\0\0" + struct.pack("<I", 88)
        blob73 = bytes(blob73[:88]) + a
        self.assertEqual(V.texture_hashes(blob73)[0], (h64(a), h3(a)))

    def test_uncompressed_layouts(self):
        rgba = bytes([10, 20, 30, 40]) * 4   # 2x2 RGBA8888
        cands = V.texture_hashes(make_vtf(0, 2, 2, rgba, flags=V.FLAG_EIGHTBITALPHA))
        self.assertEqual(cands[0][0], h64(bytes([30, 20, 10, 40]) * 4))     # BGRA first with alpha
        cands = V.texture_hashes(make_vtf(0, 2, 2, rgba))
        self.assertEqual(cands[0][0], h64(bytes([30, 20, 10, 0]) * 4))      # BGR0 first without
        bgr = bytes([1, 2, 3]) * 4
        self.assertIn((h64(bytes([1, 2, 3, 0]) * 4), h3(bytes([1, 2, 3, 0]) * 4)), V.texture_hashes(make_vtf(3, 2, 2, bgr)))
        with self.assertRaises(ValueError):
            V.texture_hashes(b"VTX\0" + bytes(100))

    def test_containers(self):
        t1, t2 = make_vtf(13, 4, 4, bytes(8)), make_vtf(13, 4, 4, bytes([1] * 8))
        with tempfile.TemporaryDirectory() as d:
            g = os.path.join(d, "map.gma")
            with open(g, "wb") as fh:
                fh.write(gma([("materials/a.vtf", t1), ("maps/x.txt", b"x")]))
            self.assertEqual([n for n, _ in V.iter_vtfs(g)], ["materials/a.vtf"])
            v = os.path.join(d, "pak_dir.vpk")
            with open(v, "wb") as fh:
                fh.write(vpk_dir([("materials/b/c.vtf", t2), ("sound/s.wav", b"w")]))
            self.assertEqual([(n, b) for n, b in V.iter_vtfs(v)], [("materials/b/c.vtf", t2)])
            cache = {}
            rows = V.source_table(v, cache, log=lambda *a: None)
            self.assertEqual(rows, [[h64(bytes([1] * 8)), h3(bytes([1] * 8)), 4, 4]])
            self.assertEqual(len(cache), 1)


class Rekey(unittest.TestCase):
    def test_rename_known_keep_others_and_refuse_clash(self):
        top_a, top_b = bytes(range(8)), bytes(range(8, 16))
        with tempfile.TemporaryDirectory() as d:
            src = os.path.join(d, "maps")
            os.makedirs(src)
            for n, t in (("a", top_a), ("b", top_b)):
                with open(os.path.join(src, n + ".vtf"), "wb") as fh:
                    fh.write(make_vtf(13, 4, 4, t))
            mod = os.path.join(d, "mod")
            os.makedirs(mod)
            layer = ('#usda 1.0\nover "RootNode"\n{\n over "Looks"\n {\n  over "mat_%s"\n  {\n  }\n  over "mat_%s"\n  {\n  }\n'
                     '  over "mat_00000000DEADBEEF"\n  {\n  }\n }\n over "meshes"\n {\n  over "mesh_X"\n  {\n'
                     '   rel material:binding = </RootNode/Looks/mat_%s>\n  }\n }\n}\n') % (h3(top_a), h64(top_b), h3(top_a))
            with open(os.path.join(mod, "mod.usda"), "w", encoding="utf-8", newline="\n") as fh:
                fh.write(layer)
            buf = io.StringIO()
            with redirect_stdout(buf):
                code = rekey_mod_hashes.main(["--mod", mod, "--source", src])
            self.assertEqual(code, 0, buf.getvalue())
            text = open(os.path.join(mod, "mod.usda"), encoding="utf-8").read()
            self.assertIn('over "mat_%s"' % h64(top_a), text)
            self.assertIn("</RootNode/Looks/mat_%s>" % h64(top_a), text)
            self.assertIn('over "mat_%s"' % h64(top_b), text)
            self.assertIn("mat_00000000DEADBEEF", text)
            self.assertIn("1 re-keyed", buf.getvalue())
            self.assertIn("1 already XXH64", buf.getvalue())
            # A second XXH3 name whose XXH64 is already a material: refused, nothing written.
            with open(os.path.join(mod, "mod.usda"), "a", encoding="utf-8") as fh:
                fh.write('over "RootNode"\n{\n over "Looks"\n {\n  over "mat_%s"\n  {\n  }\n }\n}\n' % h3(top_b))
            before = open(os.path.join(mod, "mod.usda"), encoding="utf-8").read()
            with redirect_stdout(io.StringIO()):
                self.assertEqual(rekey_mod_hashes.main(["--mod", mod, "--source", src]), 1)
            self.assertEqual(open(os.path.join(mod, "mod.usda"), encoding="utf-8").read(), before)


class FitMod(unittest.TestCase):
    def mod(self, d):
        mod = os.path.join(d, "mod")
        os.makedirs(os.path.join(mod, "tex"))
        make_dds(os.path.join(mod, "tex", "a.dds"), "BC7", 1024, 1024, seed=1)
        make_dds(os.path.join(mod, "tex", "r.dds"), "BC4", 1024, 1024, seed=2)
        make_dds(os.path.join(mod, "tex", "n.dds"), "BC5", 1024, 1024, seed=3)
        make_dds(os.path.join(mod, "tex", "m.dds"), "BC4", 1024, 1024, constant=0)
        layer = ('#usda 1.0\n(\n subLayers = [@./looks.usda@]\n)\n')
        looks = ('#usda 1.0\nover "RootNode"\n{\n over "Looks"\n {\n  over "mat_00000000000000AA"\n  {\n   over "Shader"\n   {\n'
                 '    asset inputs:diffuse_texture = @./tex/a.dds@\n    asset inputs:reflectionroughness_texture = @./tex/r.dds@\n'
                 '    asset inputs:normalmap_texture = @./tex/n.dds@\n    asset inputs:metallic_texture = @./tex/m.dds@\n'
                 '   }\n  }\n }\n}\n')
        with open(os.path.join(mod, "mod.usda"), "w") as fh:
            fh.write(layer)
        with open(os.path.join(mod, "looks.usda"), "w") as fh:
            fh.write(looks)
        return mod

    def run_fit(self, *argv):
        buf = io.StringIO()
        with redirect_stdout(buf):
            code = fit_mod.main(list(argv))
        return code, buf.getvalue()

    def test_aux_first_then_lossless_layers_kept(self):
        with tempfile.TemporaryDirectory() as d:
            mod = self.mod(d)
            out = os.path.join(d, "out")
            lossless = fit_mod.plan(mod, 10 ** 12, 128)[3]["lossless_bytes"]
            # Room for everything after the lossless step but the roughness map's top mip.
            budget = lossless - F.Dds(os.path.join(mod, "tex", "r.dds")).level_bytes(0) // 2
            code, text = self.run_fit("--mod", mod, "--out", out, "--budget", str(budget))
            self.assertEqual(code, 0, text)
            self.assertEqual(F.Dds(os.path.join(out, "tex", "r.dds")).side, 512)       # aux at half its albedo
            self.assertEqual(F.Dds(os.path.join(out, "tex", "a.dds")).side, 1024)      # albedo untouched
            self.assertEqual(F.Dds(os.path.join(out, "tex", "m.dds")).side, 16)        # constant map: a tail
            with open(os.path.join(out, "tex", "a.dds"), "rb") as f1, open(os.path.join(mod, "tex", "a.dds"), "rb") as f2:
                self.assertEqual(f1.read(), f2.read())
            for name in ("mod.usda", "looks.usda"):
                self.assertEqual(open(os.path.join(out, name)).read(), open(os.path.join(mod, name)).read())
            cut = F.Dds(os.path.join(out, "tex", "r.dds"))
            with open(os.path.join(out, "tex", "r.dds"), "rb") as fh:
                fh.seek(cut.offset)
                data = fh.read()
            orig = F.Dds(os.path.join(mod, "tex", "r.dds"))
            with open(os.path.join(mod, "tex", "r.dds"), "rb") as fh:
                fh.seek(orig.offset + orig.level_bytes(0))
                self.assertEqual(data, fh.read())                                       # the source's own lower mips

    def test_out_of_reach_and_existing_out(self):
        with tempfile.TemporaryDirectory() as d:
            mod = self.mod(d)
            code, text = self.run_fit("--mod", mod, "--out", os.path.join(d, "o"), "--budget", "1000")
            self.assertEqual(code, 1)
            self.assertIn("out of reach", text)
            self.assertFalse(os.path.exists(os.path.join(d, "o")))
            os.makedirs(os.path.join(d, "o2"))
            code, text = self.run_fit("--mod", mod, "--out", os.path.join(d, "o2"))
            self.assertEqual(code, 1)
            self.assertIn("exists", text)


if __name__ == "__main__":
    unittest.main()
