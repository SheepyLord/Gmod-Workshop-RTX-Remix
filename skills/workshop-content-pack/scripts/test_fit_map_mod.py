"""Unit tests of fit_map_mod.py on synthetic mods (DDS files generated here; nothing from a game)."""
import io
import json
import os
import random
import shutil
import struct
import sys
import tempfile
import unittest
from contextlib import redirect_stderr, redirect_stdout

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import fit_map_mod as F  # noqa: E402

DXGI = {"BC7": (98, 16), "BC5": (83, 16), "BC4": (80, 8)}
KIND_INPUT = {"a": "diffuse_texture", "n": "normalmap_texture", "r": "reflectionroughness_texture",
              "h": "height_texture", "m": "metallic_texture", "e": "emissive_mask_texture"}
KIND_FMT = {"a": "BC7", "n": "BC5", "r": "BC4", "h": "BC4", "m": "BC4", "e": "BC7"}


def write_text(path, text):
    with open(path, "w", encoding="utf-8", newline="\n") as f:
        f.write(text)


def read_text(path):
    with open(path, encoding="utf-8") as f:
        return f.read()


def read_bytes(path):
    with open(path, "rb") as f:
        return f.read()


def level_bytes(w, h, block):
    return ((w + 3) // 4) * ((h + 3) // 4) * block


def make_dds(path, fmt, w, h, constant=None, seed=0):
    dxgi, block = DXGI[fmt]
    mips = max(w, h).bit_length()
    head = bytearray(148)
    head[0:4] = b"DDS "
    struct.pack_into("<IIIIIII", head, 4, 124, 0x81007, h, w, level_bytes(w, h, block), 0, mips)
    struct.pack_into("<I", head, 76, 32)
    struct.pack_into("<I", head, 80, 4)
    head[84:88] = b"DX10"
    struct.pack_into("<I", head, 108, 0x401008)
    struct.pack_into("<IIIII", head, 128, dxgi, 3, 0, 1, 0)
    rnd = random.Random(seed)
    data = bytearray()
    for i in range(mips):
        n = level_bytes(max(1, w >> i), max(1, h >> i), block)
        if constant is not None:
            blk = bytes([constant, constant, 0, 0, 0, 0, 0, 0]) * (block // 8)
            data += blk * (n // block)
        else:
            data += bytes(rnd.getrandbits(8) for _ in range(min(n, 64))) + bytes([(i * 7 + seed) % 251]) * max(0, n - 64)
    with open(path, "wb") as f:
        f.write(bytes(head) + bytes(data))


class Fixture:
    """A mod folder plus textures.json and inventory.json describing which maps use what."""

    def __init__(self, root):
        self.root = root
        self.mod = os.path.join(root, "src", "brmod")
        os.makedirs(os.path.join(self.mod, "textures"))
        self.blocks, self.tex, self.mats = [], {}, {}

    def material(self, name, hash_hex, maps, sizes, world=False, share=0.0, inst=0, src=512, constant=None,
                 files=None):
        refs = []
        for k, (w, h) in sizes.items():
            fname = (files or {}).get(k) or f"{name}_{k}.{k}.rtex.dds"
            path = os.path.join(self.mod, "textures", fname)
            if not os.path.exists(path):
                make_dds(path, KIND_FMT[k], w, h, constant=(constant or {}).get(k), seed=len(self.blocks) * 10 + len(refs))
            refs.append((KIND_INPUT[k], fname))
        lines = [f"        # {name} (test)", f'        over "mat_{hash_hex}"', "        {",
                 '            over "Shader"', "            {",
                 "                uniform asset info:mdl:sourceAsset = @AperturePBR_Opacity.mdl@"]
        for inp, fname in refs:
            lines += [f"                asset inputs:{inp} = @./textures/{fname}@ (", '                    colorSpace = "raw"',
                      "                )"]
        lines += ["            }", "        }"]
        self.blocks.append("\n".join(lines))
        self.tex[name] = {"w": src, "h": src, "world": world, "share": share, "instances": inst,
                          "hashes": [f"0x{hash_hex}"], "materials": [name]}
        self.mats[name] = {"maps": sorted(maps)}

    def write(self, sublayers="@./materials.usda@"):
        text = ('#usda 1.0\n(\n    doc = "test materials"\n    upAxis = "Z"\n)\n\nover "RootNode"\n{\n    over "Looks"\n    {\n'
                + "\n\n".join(self.blocks) + "\n    }\n}\n")
        write_text(os.path.join(self.mod, "materials.usda"), text)
        mod = ('#usda 1.0\n(\n    customLayerData = {\n        string lightspeed_mod_name = "Test RTX"\n    }\n'
               f'    doc = "test"\n    subLayers = [\n        {sublayers}\n    ]\n)\n')
        write_text(os.path.join(self.mod, "mod.usda"), mod)
        self.textures_json = os.path.join(self.root, "textures.json")
        self.inventory_json = os.path.join(self.root, "inventory.json")
        write_text(self.textures_json, json.dumps(self.tex))
        write_text(self.inventory_json, json.dumps({"materials": self.mats, "maps": {}}))

    def run(self, *parts, extra=()):
        argv = ["--mod", self.mod, "--textures-json", self.textures_json, "--inventory-json", self.inventory_json]
        for p in parts:
            argv += ["--part", p]
        argv += list(extra)
        out, err = io.StringIO(), io.StringIO()
        with redirect_stdout(out), redirect_stderr(err):
            code = F.main(argv)
        return code, out.getvalue(), err.getvalue()


def dds(path):
    return F.Dds(path)


class FitTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="fit_map_mod_")
        self.fx = Fixture(self.tmp)
        self.out = os.path.join(self.tmp, "out")

    def tearDown(self):
        shutil.rmtree(self.tmp, ignore_errors=True)

    def part(self, name, maps):
        return os.path.join(self.out, name) + "=" + maps

    def refs(self, part):
        text = read_text(os.path.join(self.out, part, "materials.usda"))
        _, blocks, _ = F.parse_materials(text)
        return {b.hash: dict(b.refs) for b in blocks}

    def test_split_by_map_first_part_wins(self):
        fx = self.fx
        fx.material("shared", "00000000000000A1", {"m1", "m2"}, {"a": (64, 64)})
        fx.material("only1", "00000000000000A2", {"m1"}, {"a": (64, 64)})
        fx.material("only2", "00000000000000A3", {"m2"}, {"a": (64, 64)})
        fx.material("other", "00000000000000A4", {"m3"}, {"a": (64, 64)})
        fx.material("nomap", "00000000000000A5", set(), {"a": (64, 64)})
        fx.write()
        code, out, err = fx.run(self.part("p1", "m1"), self.part("p2", "m2"))
        self.assertEqual(code, 0, err)
        self.assertEqual(set(self.refs("p1")), {"00000000000000A1", "00000000000000A2", "00000000000000A5"})
        self.assertEqual(set(self.refs("p2")), {"00000000000000A3"})
        self.assertIn("left out: 1 materials", out)
        self.assertEqual(sorted(os.listdir(os.path.join(self.out, "p2", "textures"))), ["only2_a.a.rtex.dds"])

    def test_lossless_constants_and_duplicates(self):
        fx = self.fx
        fx.material("m1", "00000000000000B1", {"m"}, {"a": (128, 128), "m": (512, 512)}, constant={"m": 217})
        fx.material("m2", "00000000000000B2", {"m"}, {"a": (128, 128), "m": (256, 256)}, constant={"m": 217})
        # a byte-identical copy of m1's albedo under another name
        src = os.path.join(fx.mod, "textures")
        fx.material("m3", "00000000000000B3", {"m"}, {"a": (128, 128)})
        shutil.copyfile(os.path.join(src, "m1_a.a.rtex.dds"), os.path.join(src, "m3_a.a.rtex.dds"))
        make_dds(os.path.join(src, "unused.r.rtex.dds"), "BC4", 64, 64)
        fx.write()
        code, out, err = fx.run(self.part("p", "m"), extra=["--report", os.path.join(self.tmp, "r.json")])
        self.assertEqual(code, 0, err)
        files = sorted(os.listdir(os.path.join(self.out, "p", "textures")))
        # the two constant metallic maps (different sizes) become one 16 px file; m3's albedo is m1's
        self.assertEqual(files, ["m1_a.a.rtex.dds", "m1_m.m.rtex.dds", "m2_a.a.rtex.dds"])
        refs = self.refs("p")
        self.assertEqual(refs["00000000000000B2"]["metallic_texture"], "m1_m.m.rtex.dds")
        self.assertEqual(refs["00000000000000B3"]["diffuse_texture"], "m1_a.a.rtex.dds")
        m = dds(os.path.join(self.out, "p", "textures", "m1_m.m.rtex.dds"))
        self.assertEqual((m.width, m.height, m.mips), (16, 16, 5))
        with open(m.path, "rb") as f:
            f.seek(m.offset)
            self.assertEqual(f.read(8), bytes([217, 217, 0, 0, 0, 0, 0, 0]))
        a = dds(os.path.join(self.out, "p", "textures", "m1_a.a.rtex.dds"))
        self.assertEqual(read_bytes(a.path), read_bytes(os.path.join(src, "m1_a.a.rtex.dds")))
        report = json.loads(read_text(os.path.join(self.tmp, "r.json")))
        self.assertEqual(report["unreferenced_source_files"], 1)
        self.assertEqual(report["parts"][0]["tiers"][0]["tier"], "lossless")

    def test_dropped_mips_are_the_source_tail(self):
        fx = self.fx
        fx.material("w", "00000000000000C1", {"m"}, {"a": (256, 128), "r": (256, 128)}, world=True, share=0.5)
        fx.write()
        src = dds(os.path.join(fx.mod, "textures", "w_r.r.rtex.dds"))
        budget = str(src.size + dds(os.path.join(fx.mod, "textures", "w_a.a.rtex.dds")).size + 2000 - src.level_bytes(0))
        code, out, err = fx.run(self.part("p", "m"), extra=["--budget", budget])
        self.assertEqual(code, 0, err)
        r = dds(os.path.join(self.out, "p", "textures", "w_r.r.rtex.dds"))
        self.assertEqual((r.width, r.height, r.mips), (128, 64, src.mips - 1))
        with open(r.path, "rb") as f:
            head = f.read(r.offset)
            body = f.read()
        self.assertEqual(struct.unpack_from("<I", head, 20)[0], src.level_bytes(1))
        with open(src.path, "rb") as f:
            f.seek(src.offset + src.level_bytes(0))
            self.assertEqual(body, f.read())
        a = dds(os.path.join(self.out, "p", "textures", "w_a.a.rtex.dds"))
        self.assertEqual((a.width, a.height), (256, 128))      # albedo untouched by tier 1

    def test_tier_order_and_least_important_first(self):
        fx = self.fx
        sz = {"a": (512, 512), "n": (512, 512), "r": (512, 512)}
        fx.material("prop_few", "00000000000000D1", {"m"}, sz, inst=1, src=128)
        fx.material("prop_many", "00000000000000D2", {"m"}, sz, inst=50, src=128)
        fx.material("world_small", "00000000000000D3", {"m"}, sz, world=True, share=0.01, src=256)
        fx.material("world_big", "00000000000000D4", {"m"}, sz, world=True, share=0.2, src=256)
        fx.write()
        full = sum(os.path.getsize(os.path.join(fx.mod, "textures", f)) for f in os.listdir(os.path.join(fx.mod, "textures")))
        rough = dds(os.path.join(fx.mod, "textures", "prop_few_r.r.rtex.dds"))
        # room for all but about two roughness top mips: tier 1 cuts the props' roughness, nothing else
        budget = full + 6000 - 2 * rough.level_bytes(0)
        code, out, err = fx.run(self.part("p", "m"), extra=["--budget", str(budget), "--report", os.path.join(self.tmp, "r.json")])
        self.assertEqual(code, 0, err)
        side = lambda f: dds(os.path.join(self.out, "p", "textures", f)).side
        self.assertEqual(side("prop_few_r.r.rtex.dds"), 256)
        self.assertEqual(side("prop_many_r.r.rtex.dds"), 256)
        self.assertEqual(side("world_small_r.r.rtex.dds"), 512)
        self.assertEqual(side("world_big_r.r.rtex.dds"), 512)
        self.assertEqual(side("prop_few_a.a.rtex.dds"), 512)
        tiers = [t["tier"] for t in json.loads(read_text(os.path.join(self.tmp, "r.json")))["parts"][0]["tiers"]]
        self.assertEqual(tiers, ["lossless", "aux"])
        # a tighter budget: tier 1 everywhere, then tier 2 cuts the props to twice their source (256),
        # the prop with fewer instances first
        alb = dds(os.path.join(fx.mod, "textures", "prop_few_a.a.rtex.dds"))
        nrm = dds(os.path.join(fx.mod, "textures", "prop_few_n.n.rtex.dds"))
        budget = full + 8000 - 4 * rough.level_bytes(0) - alb.level_bytes(0) - nrm.level_bytes(0)
        code, out, err = fx.run(self.part("p", "m"), extra=["--budget", str(budget), "--force"])
        self.assertEqual(code, 0, err)
        self.assertEqual(side("prop_few_a.a.rtex.dds"), 256)
        self.assertEqual(side("prop_few_n.n.rtex.dds"), 256)
        self.assertEqual(side("prop_few_r.r.rtex.dds"), 128)     # half of its albedo
        self.assertEqual(side("prop_many_a.a.rtex.dds"), 512)
        self.assertEqual(side("world_small_a.a.rtex.dds"), 512)
        for s in ("world_small", "world_big"):
            self.assertEqual(side(f"{s}_r.r.rtex.dds"), 256)

    def test_world_tier_cuts_big_world_textures_by_share(self):
        fx = self.fx
        sz = {"a": (4096, 4096)}
        fx.material("w_rare", "00000000000000E1", {"m"}, sz, world=True, share=0.001, src=1024)
        fx.material("w_common", "00000000000000E2", {"m"}, sz, world=True, share=0.3, src=1024)
        fx.write()
        a = dds(os.path.join(fx.mod, "textures", "w_rare_a.a.rtex.dds"))
        budget = 2 * a.size - a.level_bytes(0) + 4000
        code, out, err = fx.run(self.part("p", "m"), extra=["--budget", str(budget)])
        self.assertEqual(code, 0, err)
        self.assertEqual(dds(os.path.join(self.out, "p", "textures", "w_rare_a.a.rtex.dds")).side, 2048)
        self.assertEqual(dds(os.path.join(self.out, "p", "textures", "w_common_a.a.rtex.dds")).side, 4096)

    def test_unreachable_budget_writes_nothing(self):
        fx = self.fx
        fx.material("x", "00000000000000F1", {"m"}, {"a": (256, 256)}, src=256)
        fx.write()
        code, out, err = fx.run(self.part("p", "m"), extra=["--budget", "1000"])
        self.assertEqual(code, 1)
        self.assertIn("over its budget", err)
        self.assertFalse(os.path.exists(self.out))

    def test_dry_run_and_force_rules(self):
        fx = self.fx
        fx.material("x", "0000000000000101", {"m"}, {"a": (64, 64)})
        fx.write()
        rep = os.path.join(self.tmp, "plan.json")
        code, out, err = fx.run(self.part("p", "m"), extra=["--dry-run", "--report", rep])
        self.assertEqual(code, 0, err)
        self.assertFalse(os.path.exists(self.out))
        self.assertTrue(os.path.exists(rep))
        self.assertEqual(fx.run(self.part("p", "m"))[0], 0)
        code, out, err = fx.run(self.part("p", "m"))
        self.assertEqual(code, 1)
        self.assertIn("--force", err)
        self.assertEqual(fx.run(self.part("p", "m"), extra=["--force"])[0], 0)
        write_text(os.path.join(self.out, "p", "notes.txt"), "mine")
        code, out, err = fx.run(self.part("p", "m"), extra=["--force"])
        self.assertEqual(code, 1)
        self.assertIn("does not write", err)
        self.assertTrue(os.path.exists(os.path.join(self.out, "p", "notes.txt")))

    def test_mod_usda_rewritten_and_other_sublayers_refused(self):
        fx = self.fx
        fx.material("x", "0000000000000201", {"m"}, {"a": (64, 64)})
        fx.write()
        code, out, err = fx.run(self.part("p", "m"), extra=["--mod-name", "p=Test RTX: part"])
        self.assertEqual(code, 0, err)
        mod = read_text(os.path.join(self.out, "p", "mod.usda"))
        self.assertIn('string lightspeed_mod_name = "Test RTX: part"', mod)
        self.assertIn("fit_map_mod.py", mod)
        fx.write(sublayers="@./lights.usda@,\n        @./materials.usda@")
        code, out, err = fx.run(self.part("q", "m"))
        self.assertEqual(code, 1)
        self.assertIn("one sublayer", err)

    def test_bad_command_lines(self):
        fx = self.fx
        fx.material("x", "0000000000000301", {"m"}, {"a": (64, 64)})
        fx.write()
        self.assertEqual(fx.run(os.path.join(self.out, "p"))[0], 1)                       # no maps
        self.assertEqual(fx.run(self.part("p", "m"), self.part("P", "n"))[0], 1)         # same name twice
        self.assertEqual(fx.run(os.path.join(fx.mod, "inner") + "=m")[0], 1)             # inside the source
        self.assertEqual(fx.run(self.part("p", "m"), extra=["--part-budget", "zz=5"])[0], 1)
        with redirect_stderr(io.StringIO()):
            self.assertEqual(F.main(["--mod", fx.mod]), 2)

    def test_constant_check_needs_one_value(self):
        p = os.path.join(self.tmp, "c.dds")
        make_dds(p, "BC4", 64, 64, constant=128)
        d = dds(p)
        F.check_constant(d)
        self.assertIsNotNone(d.constant)
        # the same block repeated but holding two values (e0 > e1, indices 0 and 1) is not constant
        with open(p, "r+b") as f:
            n = d.level_bytes(0) // 8
            f.seek(d.offset)
            f.write(bytes([200, 100, 0b001000, 0, 0, 0, 0, 0]) * n)
        d = dds(p)
        F.check_constant(d)
        self.assertIsNone(d.constant)


if __name__ == "__main__":
    unittest.main()
