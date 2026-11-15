"""Tests of retune_roughness.py on synthetic data (see test_retune_roughness.py.md)."""
import io
import json
import os
import sys
import tempfile
import unittest
from contextlib import redirect_stdout

import numpy as np
from PIL import Image, ImageFilter

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import retune_roughness as R  # noqa: E402
from test_rekey_fit import gma, h64, make_vtf  # noqa: E402

LAYER = '''#usda 1.0
over "RootNode"
{
    over "Looks"
    {
%s
    }
}
'''
MAT = '''        over "mat_%s"
        {
            over "Shader"
            {
                asset inputs:diffuse_texture = @./SubUSDs/%s_diffuse.a.rtex.dds@
                asset inputs:normalmap_texture = @./SubUSDs/%s_normal.n.rtex.dds@
                asset inputs:reflectionroughness_texture = @./SubUSDs/%s_roughness.r.rtex.dds@
            }
        }
'''


def read(path):
    with open(path, "rb") as fh:
        return fh.read()


def nvtt_present():
    sys.path.insert(0, R.RPAI_TOOL)
    try:
        from rpai import config
        return config.nvtt_path().exists()
    except Exception:  # noqa: BLE001
        return False


class Pure(unittest.TestCase):
    def test_classify(self):
        self.assertEqual(R.classify("materials/brick/brickwall014b.vtf"), "brick")
        self.assertEqual(R.classify("pak:materials/cs_assault/pavement001.vtf"), "concrete")
        self.assertEqual(R.classify("materials/building_template/building_template002b.vtf"), "facade")
        self.assertEqual(R.classify("materials/decals/decalgraffiti001a.vtf"), "decal_paint")
        self.assertEqual(R.classify("pak:materials/skybox/militiabk.vtf"), "skip")
        self.assertEqual(R.classify("materials/models/weapons/v_physcannon/v_superphyscannon_sheet.vtf"), "skip")
        self.assertIsNone(R.classify("materials/something/else.vtf"))

    def test_remap(self):
        rough = np.linspace(0.3, 0.6, 1000, dtype=np.float32)
        out = R.remap(rough, 0.7, 0.9)
        self.assertAlmostEqual(float(out.min()), 0.7, places=5)
        self.assertAlmostEqual(float(out.max()), 0.9, places=5)
        self.assertTrue(np.all(np.diff(out) >= 0))  # the order of the texels is kept
        flat = R.remap(np.full(100, 0.5, np.float32), 0.6, 0.8)
        self.assertTrue(np.allclose(flat, 0.7))

    def test_window_mask(self):
        a = np.ones((64, 64), np.float32)
        a[10:30, 10:20] = 0  # 4.9 % panes
        m = R.window_mask(a)
        self.assertIsNotNone(m)
        self.assertEqual(float(m[15, 15]), 1.0)
        self.assertEqual(float(m[50, 50]), 0.0)
        self.assertIsNone(R.window_mask(np.ones((64, 64), np.float32)))  # opaque: no mask
        rng = np.random.default_rng(4)
        speckle = np.where(rng.random((64, 64)) < 0.15, 0.0, 1.0).astype(np.float32)
        self.assertIsNone(R.window_mask(speckle))  # scattered dark texels are grunge, not panes
        graded = np.clip(rng.uniform(0.25, 0.55, (64, 64)), 0, 1).astype(np.float32)  # grey, grungy panels
        graded[rng.random((64, 64)) < 0.02] = 0.05  # a few near-black grunge texels
        graded[8:56, 4:28] = 0  # one solid pane, 28 %
        g = R.window_mask(graded)
        self.assertIsNotNone(g)
        self.assertEqual(float(g[30, 15]), 1.0)  # the pane
        panels = np.ones((64, 64), bool)
        panels[6:58, 2:30] = False
        self.assertEqual(float(g[panels].max()), 0.0)  # building_template006b: no gloss on the panels
        b = np.ones((64, 64), np.float32)
        b[:50] = 0  # 78 % below one half: not a window mask
        self.assertIsNone(R.window_mask(b))

    def test_octahedral_and_gain(self):
        rng = np.random.default_rng(1)
        n = rng.normal(0, 0.2, (32, 32, 3)).astype(np.float32)
        n[..., 2] = 1
        n /= np.linalg.norm(n, axis=2, keepdims=True)
        back = R.oct_decode(R.oct_encode(n))
        self.assertLess(float(np.abs(back - n).max()), 0.02)
        stronger = R.scale_normals(n, 1.5)
        self.assertGreater(float(np.abs(stronger[..., :2]).mean()), float(np.abs(n[..., :2]).mean()))
        flat = R.scale_normals(n, 1.0, np.ones((32, 32), np.float32))
        self.assertTrue(np.allclose(flat[..., 2], 1.0, atol=1e-5))


class Grain(unittest.TestCase):
    def test_decode_vtf(self):
        dxt1 = make_vtf(13, 4, 4, bytes([0x1F, 0x00, 0x00, 0xF8]) + bytes(4))  # colour0 blue, colour1 red, all index 0
        rgb = np.asarray(R.decode_vtf(dxt1))
        self.assertEqual(rgb.shape, (4, 4, 3))
        self.assertGreater(int(rgb[0, 0, 2]), 200)  # blue
        self.assertLess(int(rgb[0, 0, 0]), 50)
        raw = make_vtf(0, 2, 1, bytes([10, 20, 30, 255, 40, 50, 60, 255]))  # RGBA8888
        self.assertEqual(np.asarray(R.decode_vtf(raw)).tolist(), [[[10, 20, 30], [40, 50, 60]]])
        with self.assertRaises(ValueError):
            R.decode_vtf(make_vtf(5, 2, 2, bytes(4)))  # I8: not decoded

    def test_restore_grain(self):
        rng = np.random.default_rng(3)
        src = Image.fromarray(rng.integers(60, 200, (32, 32, 3), dtype=np.uint8), "RGB")
        smooth = src.resize((128, 128), Image.BICUBIC).filter(ImageFilter.GaussianBlur(6)).convert("RGBA")
        smooth.putalpha(77)
        ratio, corr = R.grain_kept(src, smooth)
        self.assertLess(ratio, 0.5)  # the blur took the grain
        fixed = Image.fromarray(R.restore_grain(src, smooth), "RGBA")
        self.assertTrue(np.all(np.asarray(fixed)[..., 3] == 77))  # alpha kept
        ratio2, corr2 = R.grain_kept(src, fixed)
        self.assertGreater(ratio2, 0.65)  # one pass; pixel-level noise is the hardest case (BigCity: 0.86-0.94)
        self.assertGreater(ratio2, 2 * ratio)
        self.assertGreater(corr2, corr)
        same = src.resize((128, 128), Image.NEAREST)
        self.assertGreater(R.grain_kept(src, same)[0], 0.95)  # nothing lost, nothing to restore


class Main(unittest.TestCase):
    def make(self, root):
        """A mod with a brick, a sky and an unnamed material, and a .gma naming the first two."""
        brick = make_vtf(13, 4, 4, bytes(range(8)))  # DXT1, one block
        sky = make_vtf(13, 4, 4, bytes(range(8, 16)))
        hb, hs, hu = h64(bytes(range(8))), h64(bytes(range(8, 16))), "0123456789ABCDEF"
        src = os.path.join(root, "map.gma")
        with open(src, "wb") as fh:
            fh.write(gma([("materials/brick/brickwall001a.vtf", brick), ("materials/skybox/sky_up.vtf", sky)]))
        mod = os.path.join(root, "mod")
        sub = os.path.join(mod, "SubUSDs")
        os.makedirs(sub)
        with open(os.path.join(mod, "mod.usda"), "w", encoding="utf-8") as fh:
            fh.write('#usda 1.0\n(\n    subLayers = [\n        @./changes.usda@\n    ]\n)\n')
        with open(os.path.join(mod, "changes.usda"), "w", encoding="utf-8") as fh:
            fh.write(LAYER % "".join(MAT % (h, h, h, h) for h in (hb, hs, hu)))
        rng = np.random.default_rng(2)
        for h in (hb, hs, hu):
            Image.fromarray(rng.integers(0, 255, (16, 16, 4), dtype=np.uint8), "RGBA").save(
                os.path.join(sub, "%s_diffuse.a.rtex.dds" % h), "DDS")
            Image.fromarray((rng.random((16, 16)) * 60 + 100).astype(np.uint8), "L").save(
                os.path.join(sub, "%s_roughness.r.rtex.dds" % h), "DDS")
            Image.fromarray(np.full((16, 16, 3), 128, np.uint8), "RGB").save(
                os.path.join(sub, "%s_normal.n.rtex.dds" % h), "DDS")
        return src, mod, hb, hs, hu

    def test_dry_run_and_refusals(self):
        with tempfile.TemporaryDirectory() as root:
            src, mod, hb, hs, hu = self.make(root)
            report = os.path.join(root, "r.json")
            out = os.path.join(root, "out")
            with redirect_stdout(io.StringIO()) as buf:
                self.assertEqual(R.main(["--mod", mod, "--out", out, "--source", src, "--dry-run", "--json", report]), 0)
            self.assertIn("1 to retune, 1 skipped by rule, 1 unnamed", buf.getvalue())
            with open(report, encoding="utf-8") as fh:
                r = json.load(fh)
            self.assertEqual(r["materials"][hb]["class"], "brick")
            self.assertIn(hs, r["kept"])
            self.assertEqual(r["unnamed"], [hu])
            self.assertFalse(os.path.exists(out))
            os.makedirs(out)
            with redirect_stdout(io.StringIO()):
                self.assertEqual(R.main(["--mod", mod, "--out", out, "--source", src]), 1)  # exists, no --force
                self.assertEqual(R.main(["--mod", mod, "--out", out, "--source", src, "--force"]), 1)  # no mod.usda
                self.assertEqual(R.main(["--mod", mod, "--out", out + "2", "--source", src + "x"]), 1)
                self.assertEqual(R.main(["--mod", root, "--out", out + "2", "--source", src]), 1)

    @unittest.skipUnless(nvtt_present(), "the RTX Remix Toolkit's NVTT exporter is not installed")
    def test_run_writes_new_files_only(self):
        with tempfile.TemporaryDirectory() as root:
            src, mod, hb, hs, hu = self.make(root)
            before = {f: read(os.path.join(mod, "SubUSDs", f)) for f in os.listdir(os.path.join(mod, "SubUSDs"))}
            out = os.path.join(root, "out")
            with redirect_stdout(io.StringIO()):
                self.assertEqual(R.main(["--mod", mod, "--out", out, "--source", src, "--restore-grain"]), 0)
            for f, data in before.items():  # --mod untouched
                self.assertEqual(read(os.path.join(mod, "SubUSDs", f)), data)
            new = np.asarray(Image.open(os.path.join(out, "SubUSDs", "%s_roughness.r.rtex.dds" % hb)).convert("L"),
                             np.float32) / 255
            self.assertGreater(float(new.mean()), 0.74)  # brick range 0.74-0.95
            self.assertLess(float(new.mean()), 0.95)
            self.assertNotEqual(read(os.path.join(out, "SubUSDs", "%s_normal.n.rtex.dds" % hb)),
                                before["%s_normal.n.rtex.dds" % hb])  # brick gain 1.3: re-encoded
            for h in (hs, hu):  # skipped and unnamed: still the old bytes
                self.assertEqual(read(os.path.join(out, "SubUSDs", "%s_roughness.r.rtex.dds" % h)),
                                 before["%s_roughness.r.rtex.dds" % h])


if __name__ == "__main__":
    unittest.main()
