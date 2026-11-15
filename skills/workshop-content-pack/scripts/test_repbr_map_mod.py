"""Tests of repbr_map_mod.py on synthetic data (see test_repbr_map_mod.py.md)."""
import io
import json
import os
import sys
import tempfile
import unittest
from contextlib import redirect_stdout

import numpy as np
from PIL import Image

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import repbr_map_mod as M  # noqa: E402
import retune_roughness as R  # noqa: E402
from test_map_usage import VMT, bsp  # noqa: E402
from test_rekey_fit import gma, h64, make_vtf  # noqa: E402
from test_retune_roughness import LAYER, MAT, nvtt_present, read  # noqa: E402

RULES = {
    "skip_flags": ["translucent"],
    "classes": {
        "brick": {"rough": [0.74, 0.95], "normal": 0.12, "detail": 0.3, "cavity": 0.3, "height": 0.002},
        "metal": {"rough": [0.2, 0.4], "normal": 0.03, "metal": 0.9},
        "tile_source": {"from_source": True, "rough": [0.1, 0.3], "normal": 0.05},
    },
    "scan_rules": [["^scans/rebuild", "tile_source"]],
    "rules": [["^brick/", "brick"], ["^metal/", "metal"]],
    "overrides": {},
}


class Plan(unittest.TestCase):
    def test_ladder(self):
        t = M.Tex("a", "albedo", 4096, 2048, "BC7", 1.0, mips=13)
        self.assertEqual(t.side, 256)
        self.assertEqual(t.dims(), (256, 128))
        self.assertEqual(t.ladder[-1], 4096)
        capped = M.Tex("b", "roughness", 4096, 4096, "BC4", 1.0, max_side=16, mips=13)
        self.assertEqual(capped.side, 16)   # a one-value map keeps its tail
        small = M.Tex("c", "albedo", 128, 128, "BC7", 1.0, mips=8)
        self.assertEqual(small.side, 128)
        t.i = t.ladder.index(1024)
        self.assertEqual(t.drop(), 2)

    def test_greedy_budget(self):
        hero = M.Tex("hero", "albedo", 4096, 4096, "BC7", 10.0, mips=13)
        prop = M.Tex("prop", "albedo", 4096, 4096, "BC7", 0.01, mips=13)
        rough = M.Tex("hero:r", "roughness", 4096, 4096, "BC4", 3.0)
        budget = hero.cost(4096) + prop.cost(512) + rough.cost(2048) + 10000
        total = M.plan_sizes([hero, prop, rough], budget, 0)
        self.assertLessEqual(total, budget)
        self.assertEqual(hero.side, 4096)
        self.assertLess(prop.side, 1024)
        with self.assertRaises(M.Refused):
            M.plan_sizes([M.Tex("x", "albedo", 4096, 4096, "BC7", 1.0)], 1000, 0)


class Classify(unittest.TestCase):
    def test_order(self):
        classes, rules, overrides, skip = M.load_rules_data(RULES)
        sub = {"diffuse_texture": "SubUSDs/X_diffuse.a.rtex.dds"}
        scan = {"diffuse_texture": "ambientcg/Bricks_Color.a.rtex.dds"}
        self.assertEqual(M.classify("H", "brick/wall", sub, rules, overrides)[0], "brick")
        self.assertEqual(M.classify("H", "brick/wall", sub, rules, {"H": "metal"})[0], "metal")
        self.assertEqual(M.classify("H", None, sub, rules, overrides)[0], "keep")
        self.assertEqual(M.classify("H", "brick/wall", sub, rules, overrides, ["translucent"], skip)[0], "skip")
        self.assertEqual(M.classify("H", "brick/wall", scan, rules, overrides)[0], "scan")   # scans before rules
        self.assertEqual(M.classify("H", "scans/rebuild_me", scan, rules, overrides)[0], "tile_source")
        self.assertEqual(M.classify("H", "other/thing", sub, rules, overrides)[0], "keep")
        with self.assertRaises(ValueError):
            M.load_rules_data({"classes": {"x": {"roughh": [0, 1]}}})
        with self.assertRaises(ValueError):
            M.load_rules_data({"rules": [["a", "nope"]]})


class Layers(unittest.TestCase):
    def test_set_inputs(self):
        text = LAYER % (MAT % (("ABCDEF0123456789",) * 4))
        out = M.set_inputs(text, "mat_abcdef0123456789", {
            "normalmap_texture": ("asset", "@./SubUSDs/new.n.rtex.dds@"),
            "metallic_constant": ("float", "0.9")})
        self.assertIn("asset inputs:normalmap_texture = @./SubUSDs/new.n.rtex.dds@", out)
        self.assertIn("float inputs:metallic_constant = 0.9", out)
        self.assertIn("ABCDEF0123456789_diffuse.a.rtex.dds", out)   # untouched
        self.assertEqual(out.count("inputs:normalmap_texture"), 1)
        with self.assertRaises(KeyError):
            M.set_inputs(text, "mat_0000000000000000", {})

    def test_mesh_material_after_a_block(self):
        """A mesh replacement's own material that follows a material's block (Country Estate's garden gnome)
        is neither read as that material's inputs nor edited with them."""
        mesh = ('    over "meshes"\n    {\n        def Material "Material_0"\n        {\n'
                '            def Shader "Shader"\n            {\n'
                '                asset inputs:diffuse_texture = @./models/gnome.dds@\n'
                '                asset inputs:metallic_texture = @./models/gnome_m.dds@\n            }\n        }\n    }\n')
        text = (LAYER % (MAT % (("ABCDEF0123456789",) * 4))).rstrip()[:-1] + mesh + "}\n"
        with tempfile.TemporaryDirectory() as root:
            with open(os.path.join(root, "mod.usda"), "w", encoding="utf-8") as fh:
                fh.write('#usda 1.0\n(\n    subLayers = [\n        @./changes.usda@\n    ]\n)\n')
            with open(os.path.join(root, "changes.usda"), "w", encoding="utf-8") as fh:
                fh.write(text)
            mats, _walk = M.mod_materials(root)
        inputs = mats["ABCDEF0123456789"]["inputs"]
        self.assertEqual(inputs["diffuse_texture"], "SubUSDs/ABCDEF0123456789_diffuse.a.rtex.dds")
        self.assertNotIn("metallic_texture", inputs)
        out = M.set_inputs(text, "mat_ABCDEF0123456789", {"metallic_texture": ("asset", "@@")})
        self.assertIn("@./models/gnome_m.dds@", out)   # the mesh's material untouched
        self.assertEqual(out.count("inputs:metallic_texture"), 2)   # one added to the material


class Compose(unittest.TestCase):
    def test_maps(self):
        rng = np.random.default_rng(5)
        n = np.dstack([rng.normal(0, 0.1, (64, 64)), rng.normal(0, 0.1, (64, 64)), np.ones((64, 64))]).astype(np.float32)
        n /= np.linalg.norm(n, axis=2, keepdims=True)
        h = np.zeros((64, 64), np.float32)
        h[::8, :] = -1   # grout lines low
        ai = {"normal": n, "roughness": rng.random((64, 64)).astype(np.float32), "height": h + 1}
        albedo = Image.fromarray(rng.integers(0, 255, (128, 128, 4), dtype=np.uint8), "RGBA")
        rec = dict(M.RECIPE, rough=(0.74, 0.95), normal=0.12, detail=0.3, cavity=0.3, height=0.002)
        sizes = {"normal": (128, 128), "roughness": (64, 64), "height": (64, 64)}
        out, info = M.compose(sizes, rec, ai, albedo, None, 1, True)
        self.assertEqual(out["normal"].shape, (128, 128, 3))
        unit = R.oct_decode(out["normal"])
        self.assertAlmostEqual(M.normal_strength(unit), 0.12, delta=0.02)
        r = out["roughness"].astype(np.float32) / 255
        self.assertGreaterEqual(float(r.min()), 0.73)
        self.assertLessEqual(float(r.max()), 1.0)
        self.assertGreater(float(r[::8, :].mean()), float(r[4::8, :].mean()))   # cavities rougher
        self.assertEqual(out["height"].shape, (64, 64))
        flat, _ = M.compose({"normal": (32, 32)}, dict(rec, normal=0.0, detail=0.0), ai, albedo, None, 1, True)
        self.assertLess(M.normal_strength(R.oct_decode(flat["normal"])), 0.01)
        env = np.zeros((128, 128), np.uint8)
        env[:, 64:] = 255
        glossy, _ = M.compose({"roughness": (64, 64)}, dict(rec, cavity=0, envmask=0.6), ai, albedo, env, 1, True)
        g = glossy["roughness"].astype(np.float32)
        self.assertLess(g[:, 40:].mean(), g[:, :24].mean())

    def test_noise_and_blur_tile(self):
        a = M.smudge_noise((64, 32), 7)
        self.assertLessEqual(float(np.abs(a).max()), 1.0 + 1e-6)
        self.assertLess(float(np.abs(a[:, 0] - a[:, -1]).mean()), 0.25)   # periodic: neighbours across the seam
        x = np.zeros((16, 16), np.float32)
        x[0, 0] = 1
        b = M.gauss_f(x, 1.0)
        self.assertAlmostEqual(float(b.sum()), 1.0, places=4)
        self.assertGreater(float(b[-1, -1]), 0)   # wraps


class Main(unittest.TestCase):
    def make(self, root):
        """A map item (a BSP with a brick floor, VMTs, the VTFs) and a mod with brick, metal, a scan to rebuild and
        an unnamed material; AI maps already in the work folder (no model runs)."""
        brick = make_vtf(13, 4, 4, bytes(range(8)))
        metal = make_vtf(13, 4, 4, bytes(range(8, 16)))
        tile = make_vtf(0, 4, 4, bytes(range(64)))
        hb, hm, ht, hu = h64(bytes(range(8))), h64(bytes(range(8, 16))), None, "0123456789ABCDEF"
        import vtf_hash
        ht = vtf_hash.texture_hashes(tile)[0][0]
        files = [("maps/t.bsp", bsp([("brick/floor", 400.0, 1.0, 0), ("metal/wall", 100.0, 0.0, 0)])),
                 ("materials/brick/floor.vmt", (VMT % ("brick/floor", "")).encode()),
                 ("materials/metal/wall.vmt", (VMT % ("metal/wall", "")).encode()),
                 ("materials/brick/floor.vtf", brick), ("materials/metal/wall.vtf", metal),
                 ("materials/scans/rebuild_me.vtf", tile)]
        src = os.path.join(root, "map.gma")
        with open(src, "wb") as fh:
            fh.write(gma(files))
        mod = os.path.join(root, "mod")
        os.makedirs(os.path.join(mod, "SubUSDs"))
        os.makedirs(os.path.join(mod, "scans"))
        with open(os.path.join(mod, "mod.usda"), "w", encoding="utf-8") as fh:
            fh.write('#usda 1.0\n(\n    subLayers = [\n        @./changes.usda@\n    ]\n)\n')
        blocks = "".join(MAT % (h, h, h, h) for h in (hb, hm, hu))
        blocks += MAT.replace("./SubUSDs/%s_diffuse", "./scans/%s_diffuse") % (ht, ht, ht, ht)
        with open(os.path.join(mod, "changes.usda"), "w", encoding="utf-8") as fh:
            fh.write(LAYER % blocks)
        rng = np.random.default_rng(2)
        for h in (hb, hm, hu, ht):
            folder = "scans" if h == ht else "SubUSDs"
            Image.fromarray(rng.integers(0, 255, (64, 64, 4), dtype=np.uint8), "RGBA").save(
                os.path.join(mod, folder, "%s_diffuse.a.rtex.dds" % h), "DDS", pixel_format="DXT5")
            Image.fromarray((rng.random((64, 64)) * 60 + 100).astype(np.uint8), "L").save(
                os.path.join(mod, "SubUSDs", "%s_roughness.r.rtex.dds" % h), "DDS", pixel_format="DXT1")
            Image.fromarray(np.full((64, 64, 3), 128, np.uint8), "RGB").save(
                os.path.join(mod, "SubUSDs", "%s_normal.n.rtex.dds" % h), "DDS", pixel_format="DXT1")
        work = os.path.join(root, "work")
        ai = os.path.join(work, "ai")
        n = np.dstack([rng.normal(0.5, 0.05, (32, 32)), rng.normal(0.5, 0.05, (32, 32)), np.ones((32, 32))])
        for h in (hb, hm, ht):
            M.save_ai(ai, h, {"normal": n.astype(np.float32), "roughness": rng.random((32, 32)).astype(np.float32),
                              "height": rng.random((32, 32)).astype(np.float32)})
        Image.fromarray(rng.integers(0, 255, (16, 16, 4), dtype=np.uint8), "RGBA").save(
            os.path.join(ai, ht + "_albedo.png"))
        rules = os.path.join(root, "rules.json")
        with open(rules, "w", encoding="utf-8") as fh:
            json.dump(RULES, fh)
        return src, mod, work, rules, (hb, hm, ht, hu)

    def test_plan_only_and_refusals(self):
        with tempfile.TemporaryDirectory() as root:
            src, mod, work, rules, (hb, hm, ht, hu) = self.make(root)
            plan = os.path.join(root, "plan.json")
            with redirect_stdout(io.StringIO()) as buf:
                self.assertEqual(M.main(["--mod", mod, "--source", src, "--rules", rules, "--work", work,
                                         "--plan-only", "--json", plan]), 0)
            self.assertIn("brick", buf.getvalue())
            with open(plan, encoding="utf-8") as fh:
                p = json.load(fh)
            self.assertEqual(p[hb]["class"], "brick")
            self.assertEqual(p[hm]["class"], "metal")
            self.assertEqual(p[ht]["class"], "tile_source")
            self.assertEqual(p[hu]["class"], "keep")
            self.assertGreater(p[hb]["importance"], p[hm]["importance"])   # floor 1.5 x 80 % against wall 20 %
            self.assertIn("height", p[hb]["sizes"])
            self.assertNotIn("height", p[hm]["sizes"])
            with redirect_stdout(io.StringIO()):
                self.assertEqual(M.main(["--mod", mod, "--source", src, "--rules", rules, "--work", work,
                                         "--plan-only", "--budget", "1000"]), 1)
                self.assertEqual(M.main(["--mod", root, "--source", src, "--rules", rules, "--plan-only"]), 1)
                self.assertEqual(M.main(["--mod", mod, "--source", src + "x", "--rules", rules, "--plan-only"]), 1)
                os.makedirs(os.path.join(root, "out"))
                self.assertEqual(M.main(["--mod", mod, "--source", src, "--rules", rules, "--out",
                                         os.path.join(root, "out")]), 1)

    @unittest.skipUnless(nvtt_present(), "the RTX Remix Toolkit's NVTT exporter is not installed")
    def test_build(self):
        with tempfile.TemporaryDirectory() as root:
            src, mod, work, rules, (hb, hm, ht, hu) = self.make(root)
            before = {f: read(os.path.join(mod, "SubUSDs", f)) for f in os.listdir(os.path.join(mod, "SubUSDs"))}
            out = os.path.join(root, "out")
            report = os.path.join(root, "r.json")
            with redirect_stdout(io.StringIO()):
                self.assertEqual(M.main(["--mod", mod, "--out", out, "--source", src, "--rules", rules,
                                         "--work", work, "--json", report, "--workers", "2"]), 0)
            for f, data in before.items():
                self.assertEqual(read(os.path.join(mod, "SubUSDs", f)), data)   # --mod untouched
            with open(os.path.join(out, "changes.usda"), encoding="utf-8") as fh:
                text = fh.read()
            self.assertIn("%s_repbr_normal.n.rtex.dds" % hb, text)
            self.assertIn("%s_repbr_height.h.rtex.dds" % hb, text)
            self.assertIn("%s_repbr_albedo.a.rtex.dds" % ht, text)   # rebuilt from the game texture
            self.assertIn("inputs:displace_in = 0.002", text)
            self.assertIn("inputs:metallic_constant = 0.9", text)
            self.assertIn("%s_normal.n.rtex.dds" % hu, text)   # the unnamed material keeps its maps
            self.assertFalse(os.path.exists(os.path.join(out, "SubUSDs", "%s_normal.n.rtex.dds" % hb)))
            with Image.open(os.path.join(out, "SubUSDs", "%s_repbr_roughness.r.rtex.dds" % hb)) as im:
                r = np.asarray(im.convert("L"), np.float32) / 255
            self.assertGreater(float(r.mean()), 0.74)
            self.assertEqual(read(os.path.join(out, "SubUSDs", "%s_normal.n.rtex.dds" % hu)),
                             before["%s_normal.n.rtex.dds" % hu])
            with open(report, encoding="utf-8") as fh:
                self.assertLessEqual(json.load(fh)["bytes"], M.DEFAULT_BUDGET)


if __name__ == "__main__":
    unittest.main()
