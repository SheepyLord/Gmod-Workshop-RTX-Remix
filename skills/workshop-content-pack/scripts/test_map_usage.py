"""Tests of map_usage.py on a synthetic map item (see test_map_usage.py.md)."""
import json
import os
import struct
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import map_usage as U  # noqa: E402
from test_rekey_fit import gma  # noqa: E402


def bsp(faces, props=(), entities="", overlays=()):
    """A VBSP v20 holding the lumps map_usage reads. faces: (material, area, normal z, flags); overlays:
    (material, side) squares in lump 45, each with a skipped face so that it has a texinfo."""
    faces = list(faces) + [(m, 1.0, 0.0, 0x200) for m, _side in overlays]
    names = []
    for m, *_ in faces:
        if m not in names:
            names.append(m)
    strdata, offsets = bytearray(), []
    for n in names:
        offsets.append(len(strdata))
        strdata += n.encode() + b"\0"
    lumps = {
        0: entities.encode() + b"\0",
        1: struct.pack("<3ffi", 0, 0, 1, 0, 0) + struct.pack("<3ffi", 1, 0, 0, 0, 0) + struct.pack("<3ffi", 0, 0, -1, 0, 0),
        2: b"".join(struct.pack("<3fiiiii", 0, 0, 0, i, 64, 64, 64, 64) for i in range(len(names))),
        6: b"", 7: b"", 43: bytes(strdata), 44: b"".join(struct.pack("<i", o) for o in offsets),
    }
    texinfo, face_data = bytearray(), bytearray()
    for i, (m, area, nz, flags) in enumerate(faces):
        texinfo += bytes(64) + struct.pack("<ii", flags, names.index(m))
        plane = 0 if nz > 0.7 else 2 if nz < -0.7 else 1
        f = bytearray(56)
        struct.pack_into("<HBBihhh", f, 0, plane, 0, 0, 0, 0, i, -1)
        struct.pack_into("<f", f, 24, area)
        face_data += f
    lumps[6], lumps[7] = bytes(texinfo), bytes(face_data)
    ov = bytearray()
    first = len(faces) - len(overlays)
    for k, (_m, side) in enumerate(overlays):
        rec = bytearray(352)
        struct.pack_into("<ih", rec, 0, k, first + k)
        for j, (x, y) in enumerate(((0, 0), (side, 0), (side, side), (0, side))):
            struct.pack_into("<3f", rec, 280 + 12 * j, x, y, 0)
        ov += rec
    lumps[45] = bytes(ov)
    head = bytearray(b"VBSP" + struct.pack("<i", 20) + bytes(16 * 64) + struct.pack("<i", 1))
    body = bytearray()
    base = len(head)
    gl_index = None
    for i in range(64):
        if i == 35:
            continue
        data = lumps.get(i, b"")
        struct.pack_into("<ii", head, 8 + 16 * i, base + len(body), len(data))
        body += data
    if props:
        models = sorted({m for m, _ in props})
        sprp = bytearray(struct.pack("<i", len(models)))
        for m in models:
            sprp += m.encode().ljust(128, b"\0")
        sprp += struct.pack("<i", 0)   # no leaves
        n = sum(c for _, c in props)
        sprp += struct.pack("<i", n)
        for m, c in props:
            for _ in range(c):
                rec = bytearray(64)
                struct.pack_into("<H", rec, 24, models.index(m))
                sprp += rec
        gl_off = base + len(body) + 4 + 16
        gl = struct.pack("<i", 1) + struct.pack("<iHHii", 0x73707270, 0, 10, gl_off, len(sprp)) + bytes(sprp)
        struct.pack_into("<ii", head, 8 + 16 * 35, base + len(body), len(gl))
        body += gl
    return bytes(head + body)


def mdl(textures, cdmaterials, size):
    """A studio model header with a view box of `size` and its texture and $cdmaterials names."""
    b = bytearray(1024)
    b[0:4] = b"IDST"
    struct.pack_into("<i", b, 4, 48)
    struct.pack_into("<3f", b, 128, 0, 0, 0)
    struct.pack_into("<3f", b, 140, *size)
    struct.pack_into("<4i", b, 204, len(textures), 300, len(cdmaterials), 600)
    pos = 700
    for i, t in enumerate(textures):
        struct.pack_into("<i", b, 300 + 64 * i, pos - (300 + 64 * i))
        b[pos:pos + len(t) + 1] = t.encode() + b"\0"
        pos += len(t) + 1
    for i, c in enumerate(cdmaterials):
        struct.pack_into("<i", b, 600 + 4 * i, pos)
        b[pos:pos + len(c) + 1] = c.encode() + b"\0"
        pos += len(c) + 1
    return bytes(b)


VMT = '"LightmappedGeneric"\n{\n\t"$basetexture" "%s"\n%s}\n'


class Usage(unittest.TestCase):
    def item(self, root):
        faces = [("concrete/floor01", 200.0, 1.0, 0), ("maps/testmap/concrete/floor01_1_-2_3", 100.0, 1.0, 0),
                 ("/concrete//floor01", 50.0, 1.0, 0), ("maps/testmap/concrete/floor01_wvt_patch", 50.0, 1.0, 0),
                 ("brick/wall01", 100.0, 0.0, 0), ("skybox/sky", 1000.0, 1.0, 0x4), ("tools/toolsnodraw", 50.0, 1.0, 0)]
        blob = bsp(faces, props=[("models/test/box.mdl", 2)],
                   entities=('{\n"classname" "prop_physics"\n"model" "models/test/box.mdl"\n}\n'
                             '{\n"classname" "infodecal"\n"texture" "decals/stain01"\n}\n'),
                   overlays=[("overlays/poster01", 20.0)])
        files = [("maps/testmap.bsp", blob),
                 ("materials/concrete/floor01.vmt", (VMT % ("Concrete/Floor01_tex", '\t"$surfaceprop" "concrete"\n')).encode()),
                 ("materials/brick/wall01.vmt", ('"WorldVertexTransition"\n{\n\t"$basetexture" "brick/wall01"\n'
                                                '\t"$basetexture2" "brick/wall01b"\n\t"$translucent" "1"\n}\n').encode()),
                 ("materials/models/test/boxtex.vmt", (VMT % ("models/test/boxtex", "")).encode()),
                 ("materials/overlays/poster01.vmt", (VMT % ("overlays/poster01", "")).encode()),
                 ("materials/decals/stain01.vmt", (VMT % ("decals/stain01", "")).encode()),
                 ("models/test/box.mdl", mdl(["boxtex"], ["models/test/"], (10, 10, 10)))]
        path = os.path.join(root, "map.gma")
        with open(path, "wb") as fh:
            fh.write(gma(files))
        return path

    def test_usage(self):
        with tempfile.TemporaryDirectory() as root:
            u = U.usage([self.item(root)], log=lambda *_: None)
        self.assertEqual(u["maps"], ["testmap"])
        self.assertEqual(u["world_area"], 500)   # sky and tools left out; the cubemap and blend copies and a
        # root material written "/concrete//floor01" folded into their material
        t = u["textures"]
        self.assertAlmostEqual(t["concrete/floor01_tex"]["floor"], 80.0, places=3)
        self.assertAlmostEqual(t["brick/wall01"]["wall"], 10.0, places=3)   # a blend's two textures share
        self.assertAlmostEqual(t["brick/wall01b"]["wall"], 10.0, places=3)
        self.assertIn("translucent", t["brick/wall01"]["flags"])
        self.assertEqual(t["concrete/floor01_tex"]["surfaceprop"], "concrete")
        # 3 instances (2 static, 1 entity) x box surface 600 x 0.5 seen, per cent of 500
        self.assertAlmostEqual(t["models/test/boxtex"]["props"], 180.0, places=3)
        self.assertEqual(t["models/test/boxtex"]["models"], {"models/test/box.mdl": 3})
        self.assertAlmostEqual(U.importance(t["concrete/floor01_tex"]), 120.0, places=3)
        # an overlay's area from its UV square (20 x 20), an infodecal 64 x 64; both on walls
        self.assertAlmostEqual(t["overlays/poster01"]["wall"], 400 * 100.0 / 500, places=3)
        self.assertAlmostEqual(t["decals/stain01"]["wall"], 4096 * 100.0 / 500, places=3)
        self.assertEqual(U.importance(None), 0.0)

    def test_cli_and_refusal(self):
        with tempfile.TemporaryDirectory() as root:
            path = self.item(root)
            out = os.path.join(root, "u.json")
            self.assertEqual(U.main(["--source", path, "--json", out]), 0)
            with open(out, encoding="utf-8") as fh:
                self.assertIn("concrete/floor01_tex", json.load(fh)["textures"])
            empty = os.path.join(root, "empty.gma")
            with open(empty, "wb") as fh:
                fh.write(gma([("materials/a.vmt", b'"x" {}')]))
            self.assertEqual(U.main(["--source", empty, "--json", out]), 1)
            self.assertEqual(U.main(["--source", os.path.join(root, "missing.gma"), "--json", out]), 1)


class Parts(unittest.TestCase):
    def test_norm_and_vmt(self):
        self.assertEqual(U.norm_texture("pak:materials/Foo\\Bar.vtf"), "foo/bar")
        self.assertEqual(U.norm_texture("materials/x/y.vmt"), "x/y")
        shader, keys = U.parse_vmt('"VertexLitGeneric"\n{\n "$baseTexture" "a/b"\n $surfaceprop metal\n}')
        self.assertEqual(shader, "vertexlitgeneric")
        self.assertEqual(keys["$basetexture"], "a/b")
        self.assertEqual(keys["$surfaceprop"], "metal")

    def test_mdl(self):
        info = U.mdl_info(mdl(["a", "b"], ["models/x/"], (2, 3, 4)))
        self.assertEqual(info["textures"], ["a", "b"])
        self.assertEqual(info["cdmaterials"], ["models/x"])
        self.assertAlmostEqual(info["box_area"], 2 * (6 + 12 + 8))
        self.assertIsNone(U.mdl_info(b"NOPE" + bytes(300)))


if __name__ == "__main__":
    unittest.main()
