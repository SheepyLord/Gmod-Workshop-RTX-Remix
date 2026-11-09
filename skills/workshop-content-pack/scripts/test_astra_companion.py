"""Tests for astra_companion.py on a synthetic Astra companion archive (no game files needed).

Run in this folder: python -I -m unittest discover -v -p "test_astra_companion.py" (or with the
other tests: python -I -m unittest). The BC7 and BC4 tests need numpy and Pillow; the runtime tests
run astra_companion_harness.lua with LuaJIT and are skipped without it.
"""
from __future__ import annotations

import hashlib
import json
import math
import os
import shutil
import struct
import subprocess
import sys
import tempfile
import unittest
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
import astra_companion as ac  # noqa: E402

try:
    import numpy as np
    from PIL import Image  # noqa: F401
except ImportError:  # pragma: no cover
    np = None

LUAJIT = shutil.which("luajit") or next((p for p in [os.path.join(os.environ.get("LOCALAPPDATA", ""), "Programs", "LuaJIT", "bin", "luajit.exe")]
                                         if os.path.isfile(p)), None)
MAP = "gm_test_map"

# ---------------------------------------------------------------------------- test data


class Bits:
    def __init__(self):
        self.value, self.count = 0, 0

    def put(self, value: int, width: int) -> None:
        self.value |= (value & ((1 << width) - 1)) << self.count
        self.count += width


BC7_WEIGHTS4 = [0, 4, 9, 13, 17, 21, 26, 30, 34, 38, 43, 47, 51, 55, 60, 64]


def bc7_mode6_gray(values) -> bytes:
    """A BC7 mode 6 block of 16 grey values (opaque): odd endpoints, nearest 4-bit weights."""
    lo, hi = min(values), max(values)
    c0, c1 = min(lo, 254) >> 1, max(hi, 1) >> 1
    e0, e1 = (c0 << 1) | 1, (c1 << 1) | 1
    palette = [((64 - w) * e0 + w * e1 + 32) >> 6 for w in BC7_WEIGHTS4]
    index = [min(range(16), key=lambda i: abs(palette[i] - v)) for v in values]
    if index[0] >= 8:  # the anchor index's top bit is implied zero: swap the endpoints
        c0, c1 = c1, c0
        index = [15 - i for i in index]
    bits = Bits()
    bits.put(1 << 6, 7)
    for c in (c0, c1, c0, c1, c0, c1, 127, 127):
        bits.put(c, 7)
    bits.put(1, 1)
    bits.put(1, 1)
    bits.put(index[0], 3)
    for i in index[1:]:
        bits.put(i, 4)
    assert bits.count == 128
    return bits.value.to_bytes(16, "little")


def bc7_texture(width: int, height: int, mips: int, fill, dxgi: int = ac.DXGI_BC7) -> bytes:
    """A BC7 DDS whose texel (x, y) of mip m is fill(x, y, m)."""
    data = bytearray()
    for w, h, _ in ac.mip_sizes(width, height, mips, 16):
        for by in range(0, max(h, 4), 4):
            for bx in range(0, max(w, 4), 4):
                block = [fill(min(bx + x, w - 1), min(by + y, h - 1), (w, h)) for y in range(4) for x in range(4)]
                data += bc7_mode6_gray(block)
    top = ac.mip_sizes(width, height, 1, 16)[0][2]
    return ac.dds_header(width, height, mips, dxgi, top) + bytes(data)


def gma_bytes(members: dict[str, bytes]) -> bytes:
    out = bytearray(b"GMAD" + bytes([3]) + struct.pack("<QQ", 0, 0) + b"\0" + b"companion\0{}\0Astra\0" + struct.pack("<i", 1))
    for number, (name, data) in enumerate(members.items(), 1):
        out += struct.pack("<I", number) + name.encode() + b"\0" + struct.pack("<qI", len(data), zlib.crc32(data))
    out += struct.pack("<I", 0)
    for data in members.values():
        out += data
    out += struct.pack("<I", zlib.crc32(bytes(out)))
    return bytes(out)


def usda_material(hash_hex: str, refs: dict[str, str]) -> str:
    lines = [f'        over "mat_{hash_hex}"', "        {", '            over "Shader"', "            {",
             "                uniform asset info:mdl:sourceAsset = @AperturePBR_Opacity.mdl@"]
    for role, sha in refs.items():
        lines.append(f"                asset inputs:{role} = @./textures/{sha}.dds@ (")
        lines.append('                    colorSpace = "raw"')
        lines.append("                )")
    lines += ["            }", "        }"]
    return "\n".join(lines)


def build_companion(folder: str, tamper: str | None = None) -> tuple[str, dict]:
    """A companion like the Cathedral's: two PBR materials with two aliases each, one BC7
    roughness map, one sRGB albedo, one map shared by the metallic and emissive inputs, two lights,
    one baked fallback, Lua and PNG files the conversion leaves out."""
    ramp = bc7_texture(32, 32, 6, lambda x, y, size: int(255 * x / max(1, size[0] - 1)))
    albedo = bc7_texture(16, 16, 5, lambda x, y, size: 40 + 10 * ((x + y) % 4), ac.DXGI_BC7_SRGB)
    shared = bc7_texture(16, 16, 5, lambda x, y, size: 0 if x < size[0] // 2 else 255)
    textures = {name: (data, hashlib.sha256(data).hexdigest()) for name, data in
                (("ramp", ramp), ("albedo", albedo), ("shared", shared))}
    sha = {name: digest for name, (_, digest) in textures.items()}
    materials = {
        "astra/gm_test_map/atlas_0001": ["00000000000A0001", "00000000000A0002"],
        "astra/gm_test_map/atlas_0002": ["00000000000B0001", "00000000000B0002"],
    }
    blocks = []
    for alias in materials["astra/gm_test_map/atlas_0001"]:
        blocks.append(usda_material(alias, {"diffuse_texture": sha["albedo"], "reflectionroughness_texture": sha["ramp"]}))
    for alias in materials["astra/gm_test_map/atlas_0002"]:
        blocks.append(usda_material(alias, {"diffuse_texture": sha["albedo"], "metallic_texture": sha["shared"],
                                            "emissive_mask_texture": sha["shared"]}))
    usda = '#usda 1.0\nover "RootNode"\n{\n    over "Looks"\n    {\n' + "\n".join(blocks) + "\n    }\n}\n"
    if tamper == "unknown_texture":
        usda = usda.replace(sha["ramp"], "f" * 64, 1)
    if tamper == "missing_override":
        usda = usda.replace("mat_00000000000B0002", "mat_00000000000C0002")
    layer = usda.encode()
    rtx = f"data_static/astra/{MAP}/rtx/"
    startup = {
        "version": 1, "map": MAP, "generation": "0" * 64,
        "files": [{"path": f"{rtx}{digest}.dds.dat", "target": f"textures/{digest}.dds", "bytes": len(data), "sha256": digest,
                   "width": 16, "height": 16} for data, digest in textures.values()],
        "layer": {"path": f"{rtx}mod.usda.dat", "target": "mod.usda", "bytes": len(layer), "sha256": hashlib.sha256(layer).hexdigest()},
    }
    index = {
        "version": 1, "map": MAP, "generation": "1" * 64,
        "materials": [{"material": name, "maps": {"albedo": {}}} for name in materials],
        "startup": {"version": 1, "generation": "2" * 64, "hashes": materials},
        "baked_fallback": {"version": 1, "mode": "legacy_emissive", "materials": [{"material": "astra/gm_test_map/atlas_0000"}]},
        "lighting": {"version": 1, "lights": [
            {"id": "light_0000", "type": "distant", "name": "sun", "base": {"hash": 1001, "isDynamic": False, "radiance": {"x": 1e5, "y": 1e5, "z": 5e4}},
             "shape": {"direction": {"x": 0.0, "y": 0.6, "z": -0.8}, "angularDiameterDegrees": 0.01, "volumetricRadianceScale": 50.0}},
            {"id": "light_0001", "type": "sphere", "name": "lamp", "base": {"hash": 1002, "isDynamic": False, "radiance": {"x": 3, "y": 2, "z": 1}},
             "shape": {"position": {"x": 1, "y": 2, "z": 3}, "radius": 12.5}},
        ], "unsupported": [{"name": "volume", "reason": "volume only"}]},
    }
    members = {
        f"{rtx}startup.json": json.dumps(startup).encode(),
        f"data_static/astra_test/{MAP}/rtx/index.json": json.dumps(index).encode(),
        f"{rtx}mod.usda.dat": layer,
        "lua/autorun/client/zz_astra_test.lua": b"-- the old loader\n",
        f"materials/astra_test/{MAP}/pbr/atlas_0001_albedo.png": b"\x89PNG fallback",
    }
    for data, digest in textures.values():
        if tamper == "payload" and digest == sha["albedo"]:
            data = data[:-1] + bytes([data[-1] ^ 1])
        members[f"{rtx}{digest}.dds.dat"] = data
    path = os.path.join(folder, "companion.gma")
    with open(path, "wb") as handle:
        handle.write(gma_bytes(members))
    return path, {"sha": sha, "textures": textures, "usda": usda, "materials": materials}


PROFILE = {
    "schema": 1, "map": MAP, "addon": "gm_test_map_rtx", "mod": "gm_test_map_rtx", "title": "Test Map RTX",
    "prefix": "testmap_rtx", "global": "TestMapRTX", "sky_owner": True, "fog_owner": True, "sky_keys": ["rtx.skyMode"],
    "clear_light2rtx": True,
    "remix": [["rtx.skyMode", "0"], ["rtx.ignoreGamePointLights", "True"], ["rtx.tonemap.tonemapOperator", "3"], ["rtx.bloom.burnIntensity", "0.15"]],
    "runtime_defaults": {"rtx.bloom.burnIntensity": "1"},
    "engine": [["rtx_api_map_lights_autospawn", "0"]],
    "tint": {"keys": ["$color", "$color2"], "materials": "pbr", "recompute": True},
    "categories": [{"name": "baked", "flag": "legacy_emissive", "materials": "baked_fallback"},
                   {"name": "mist", "flag": "particle", "materials": ["test_mist_a", "test_mist_b"]}],
    "hooks_off": [["SetupWorldFog", "test_fog"]],
    "shell": {"min": [-100, -200.5, -30], "max": [300, 400, 250], "color": [31, 48, 88]},
}


class Base(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.mkdtemp(prefix="astra-companion-", dir=os.environ.get("TEMP"))
        self.addCleanup(shutil.rmtree, self.tmp, True)
        self.profile = os.path.join(self.tmp, "profile.json")
        with open(self.profile, "w", encoding="utf-8") as handle:
            json.dump(PROFILE, handle)
        self.layer = os.path.join(self.tmp, "layer.conf")
        with open(self.layer, "w", encoding="utf-8") as handle:
            handle.write("rtx.skyMode = 1\nrtx.ignoreGamePointLights = True\nrtx.tonemap.tonemapOperator = 6\n")

    def run_convert(self, gma: str, *extra: str, out: str | None = None) -> tuple[int, str]:
        out = out or os.path.join(self.tmp, "out")
        args = ["--gma", gma, "--profile", self.profile, "--out", out, "--defaults-layer", self.layer, *extra]
        code = ac.main(args)
        return code, out


@unittest.skipIf(np is None, "numpy and Pillow are needed")
class ConvertTest(Base):
    def test_plain_conversion_keeps_every_payload(self):
        gma, info = build_companion(self.tmp)
        code, out = self.run_convert(gma)
        self.assertEqual(code, 0)
        mod = os.path.join(out, "mod", "gm_test_map_rtx")
        for data, digest in info["textures"].values():
            with open(os.path.join(mod, "textures", digest + ".dds"), "rb") as handle:
                self.assertEqual(handle.read(), data)
        with open(os.path.join(mod, "mod.usda"), encoding="utf-8") as handle:
            self.assertEqual(handle.read(), info["usda"])
        with open(os.path.join(out, "report.json"), encoding="utf-8") as handle:
            report = json.load(handle)
        self.assertEqual(report["textures"], 3)
        self.assertEqual(report["overrides"], 4)
        self.assertEqual(report["lights"], 2)
        self.assertEqual(report["source_files"]["left_out_png_fallback"]["files"], 1)
        self.assertEqual(report["source_files"]["replaced_lua"]["files"], 1)
        self.assertEqual(report["bc4"], [])
        addon = os.path.join(out, "addon", "gm_test_map_rtx")
        for rel in ("addon.json", "lua/autorun/gm_test_map_rtx.lua", "lua/gm_test_map_rtx/runtime.lua",
                    "lua/gm_test_map_rtx/profile.lua", "lua/gm_test_map_rtx/hashes.lua"):
            self.assertTrue(os.path.isfile(os.path.join(addon, rel)), rel)
        with open(os.path.join(addon, "lua", "gm_test_map_rtx", "runtime.lua"), "rb") as a, \
                open(os.path.join(HERE, "astra_companion", "runtime.lua"), "rb") as b:
            self.assertEqual(a.read(), b.read())

    def test_lights_in_remix_units(self):
        gma, _ = build_companion(self.tmp)
        index = json.loads(ac.Gma(gma).read(f"data_static/astra_test/{MAP}/rtx/index.json"))
        sun, lamp = (ac.convert_light(light) for light in index["lighting"]["lights"])
        scale = math.sin(math.radians(0.01) / 2) ** 2
        self.assertAlmostEqual(sun["base"]["radiance"]["x"], 1e5 * scale)
        self.assertEqual(sun["shape"]["angularDiameterDegrees"], ac.MIN_DISTANT_DIAMETER)
        self.assertEqual(sun["shape"]["volumetricRadianceScale"], 50.0)
        self.assertEqual(lamp["base"]["radiance"], {"x": 3, "y": 2, "z": 1})
        self.assertEqual(lamp["shape"]["volumetricRadianceScale"], 1)
        self.assertFalse(lamp["base"]["isDynamic"])
        bad = json.loads(json.dumps(index["lighting"]["lights"][0]))
        bad["shape"]["direction"] = {"x": 1, "y": 1, "z": 0}
        with self.assertRaises(ac.Refused):
            ac.convert_light(bad)

    def test_bc4_for_single_channel_maps_only(self):
        gma, info = build_companion(self.tmp)
        code, out = self.run_convert(gma, "--bc4")
        self.assertEqual(code, 0)
        with open(os.path.join(out, "report.json"), encoding="utf-8") as handle:
            report = json.load(handle)
        self.assertEqual(len(report["bc4"]), 1)
        entry = report["bc4"][0]
        self.assertEqual(entry["from"], info["sha"]["ramp"])
        self.assertEqual(entry["roles"], ["reflectionroughness_texture"])
        mod = os.path.join(out, "mod", "gm_test_map_rtx")
        names = set(os.listdir(os.path.join(mod, "textures")))
        self.assertEqual(names, {entry["to"] + ".dds", info["sha"]["albedo"] + ".dds", info["sha"]["shared"] + ".dds"})
        with open(os.path.join(mod, "textures", entry["to"] + ".dds"), "rb") as handle:
            data = handle.read()
        self.assertEqual(hashlib.sha256(data).hexdigest(), entry["to"])
        header = ac.dds_info(data)
        self.assertEqual((header["dxgi"], header["width"], header["height"], header["mips"]), (ac.DXGI_BC4, 32, 32, 6))
        self.assertEqual(len(data), 148 + sum(s for *_, s in ac.mip_sizes(32, 32, 6, 8)))
        with open(os.path.join(mod, "mod.usda"), encoding="utf-8") as handle:
            usda = handle.read()
        self.assertNotIn(info["sha"]["ramp"], usda)
        self.assertEqual(usda.count(entry["to"]), 2)
        self.assertEqual(usda, info["usda"].replace(info["sha"]["ramp"], entry["to"]))
        # every mip's red channel close to the BC7 original
        source = info["textures"]["ramp"][0]
        offset, out_offset = 148, 148
        for (w, h, size), (_, _, size4) in zip(ac.mip_sizes(32, 32, 6, 16), ac.mip_sizes(32, 32, 6, 8)):
            red = ac.decode_bc7_mip(w, h, source[offset:offset + size], ac.DXGI_BC7)[..., 0].astype(float)
            mine = ac.bc4_decode(data[out_offset:out_offset + size4], w, h)
            self.assertLessEqual(float(np.abs(mine - red).max()), 10.0, (w, h))
            offset, out_offset = offset + size, out_offset + size4

    def test_low_psnr_keeps_bc7(self):
        gma, info = build_companion(self.tmp)
        code, out = self.run_convert(gma, "--bc4", "--bc4-min-psnr", "99")
        self.assertEqual(code, 0)
        with open(os.path.join(out, "report.json"), encoding="utf-8") as handle:
            report = json.load(handle)
        self.assertEqual(report["bc4"], [])
        self.assertEqual(len(report["bc4_kept"]), 1)
        self.assertTrue(os.path.isfile(os.path.join(out, "mod", "gm_test_map_rtx", "textures", info["sha"]["ramp"] + ".dds")))

    def test_profile_data(self):
        gma, _ = build_companion(self.tmp)
        code, out = self.run_convert(gma)
        self.assertEqual(code, 0)
        with open(os.path.join(out, "addon", "gm_test_map_rtx", "lua", "gm_test_map_rtx", "profile.lua"), encoding="utf-8") as handle:
            text = handle.read()
        self.assertIn('["rtx.skyMode"] = "1"', text)  # the layer's value
        self.assertIn('["rtx.bloom.burnIntensity"] = "1"', text)  # the profile's runtime default
        self.assertIn('"astra/gm_test_map/atlas_0000"', text)  # baked_fallback resolved
        self.assertIn("flag = 16777216", text)
        self.assertIn("flag = 1024", text)
        self.assertNotIn("volume only", text)

    def test_refusals(self):
        for tamper, message in (("payload", "SHA-256"), ("unknown_texture", "startup.json lacks"), ("missing_override", "no override")):
            folder = os.path.join(self.tmp, tamper)
            os.makedirs(folder)
            gma, _ = build_companion(folder, tamper)
            with self.subTest(tamper=tamper):
                with self.assertRaises(ac.Refused) as caught:
                    ac.convert(argparse_namespace(gma, self.profile, os.path.join(folder, "out"), self.layer))
                self.assertIn(message, str(caught.exception))

    def test_output_rules(self):
        gma, _ = build_companion(self.tmp)
        code, out = self.run_convert(gma)
        self.assertEqual(code, 0)
        self.assertEqual(self.run_convert(gma)[0], 1)  # not empty, no --force
        self.assertEqual(self.run_convert(gma, "--force")[0], 0)
        other = os.path.join(self.tmp, "other")
        os.makedirs(os.path.join(other, "keep"))
        self.assertEqual(self.run_convert(gma, "--force", out=other)[0], 1)  # not an earlier conversion
        self.assertTrue(os.path.isdir(os.path.join(other, "keep")))
        wrong = dict(PROFILE, map="gm_other")
        with open(self.profile, "w", encoding="utf-8") as handle:
            json.dump(wrong, handle)
        self.assertEqual(self.run_convert(gma, out=os.path.join(self.tmp, "wrong"))[0], 1)

    def test_shell_files(self):
        gma, _ = build_companion(self.tmp)
        code, out = self.run_convert(gma)
        self.assertEqual(code, 0)
        folder = os.path.join(out, "addon", "gm_test_map_rtx", "materials", "gm_test_map_rtx")
        with open(os.path.join(folder, "shell.vtf"), "rb") as handle:
            vtf = handle.read()
        self.assertEqual(vtf[:4], b"VTF\0")
        self.assertEqual(struct.unpack("<IIIHHI", vtf[4:24]), (7, 2, 80, 4, 4, 0x4 | 0x8 | 0x100 | 0x200))
        self.assertEqual(struct.unpack("<HH", vtf[24:28]), (1, 0))  # one frame
        self.assertEqual(struct.unpack("<IBiBBH", vtf[52:65]), (2, 1, -1, 0, 0, 1))  # RGB888, one mip, no thumbnail
        self.assertEqual(len(vtf), 80 + 4 * 4 * 3)
        self.assertEqual(vtf[80:], bytes([31, 48, 88]) * 16)
        with open(os.path.join(folder, "shell.vmt"), encoding="ascii") as handle:
            vmt = handle.read()
        self.assertIn('"UnlitGeneric"', vmt)
        self.assertIn('"$basetexture" "gm_test_map_rtx/shell"', vmt)
        with open(os.path.join(out, "addon", "gm_test_map_rtx", "lua", "gm_test_map_rtx", "profile.lua"), encoding="utf-8") as handle:
            text = handle.read()
        self.assertIn('material = "gm_test_map_rtx/shell"', text)
        self.assertIn("min = { -100, -200.5, -30 }", text)
        with open(os.path.join(out, "report.json"), encoding="utf-8") as handle:
            self.assertEqual(json.load(handle)["shell"]["max"], [300, 400, 250])

    def test_shell_refusals(self):
        for shell, message in (({"min": [0, 0, 0], "max": [1, 1, 0], "color": [0, 0, 0]}, "below its max"),
                               ({"min": [0, 0], "max": [1, 1, 1], "color": [0, 0, 0]}, "three finite numbers"),
                               ({"min": [0, 0, 0], "max": [1, 1, float("inf")], "color": [0, 0, 0]}, "three finite numbers"),
                               ({"min": [0, 0, 0], "max": [1, 1, 1], "color": [0, 0, 256]}, "0-255"),
                               ({"min": [0, 0, 0], "max": [1, 1, 1], "color": [0, 0, 0], "size": 4}, "takes min, max")):
            with self.subTest(message=message):
                with open(self.profile, "w", encoding="utf-8") as handle:
                    json.dump(dict(PROFILE, shell=shell), handle)
                with self.assertRaises(ac.Refused) as caught:
                    ac.load_profile(self.profile)
                self.assertIn(message, str(caught.exception))

    def test_mod_from_an_earlier_conversion(self):
        gma, info = build_companion(self.tmp)
        code, first = self.run_convert(gma, "--bc4")
        self.assertEqual(code, 0)
        # The archive is gone; an extraction of it kept only the manifests (payloads pruned).
        extracted = os.path.join(self.tmp, "extracted")
        archive = ac.Gma(gma)
        for name in archive.members:
            if name.endswith(".dat"):
                continue
            path = os.path.join(extracted, *name.split("/"))
            os.makedirs(os.path.dirname(path), exist_ok=True)
            with open(path, "wb") as handle:
                handle.write(archive.read(name))
        archive.close()
        self.assertEqual(self.run_convert(extracted, out=os.path.join(self.tmp, "no_mod"))[0], 1)  # payloads needed
        code, second = self.run_convert(extracted, "--mod-from", first, out=os.path.join(self.tmp, "second"))
        self.assertEqual(code, 0)
        for root in ("mod", "addon"):
            a, b = os.path.join(first, root), os.path.join(second, root)
            names = sorted(os.path.relpath(os.path.join(r, n), a) for r, _, ns in os.walk(a) for n in ns)
            self.assertEqual(names, sorted(os.path.relpath(os.path.join(r, n), b) for r, _, ns in os.walk(b) for n in ns))
            for name in names:
                with open(os.path.join(a, name), "rb") as x, open(os.path.join(b, name), "rb") as y:
                    self.assertEqual(x.read(), y.read(), name)
        with open(os.path.join(first, "report.json"), encoding="utf-8") as handle:
            report1 = json.load(handle)
        with open(os.path.join(second, "report.json"), encoding="utf-8") as handle:
            report2 = json.load(handle)
        for key in ("textures", "texture_bytes", "bc4", "overrides", "source_files", "mod_bytes", "hash_aliases"):
            self.assertEqual(report1[key], report2[key], key)
        self.assertEqual(report2["mod_from"], {"folder": "out", "companion": "extracted"})
        # the same folder, another map's conversion
        self.assertEqual(self.run_convert(extracted, "--mod-from", second, out=second)[0], 1)
        report1["map"] = "gm_other"
        with open(os.path.join(first, "report.json"), "w", encoding="utf-8") as handle:
            json.dump(report1, handle)
        self.assertEqual(self.run_convert(extracted, "--mod-from", first, out=os.path.join(self.tmp, "third"))[0], 1)


def argparse_namespace(gma, profile, out, layer):
    class Args:
        pass
    args = Args()
    args.gma, args.profile, args.out, args.defaults_layer = gma, profile, out, layer
    args.bc4, args.bc4_min_psnr, args.force, args.mod_from = False, 36.0, False, None
    return args


@unittest.skipIf(np is None, "numpy is needed")
class Bc4Test(unittest.TestCase):
    def test_exact_blocks(self):
        for values in (np.full((4, 4), 77, np.uint8), (np.indices((8, 8)).sum(0) % 2 * 255).astype(np.uint8),
                       np.array([[0, 255] * 2] * 4, np.uint8), np.full((1, 1), 200, np.uint8)):
            encoded = ac.bc4_encode(values)
            self.assertEqual(len(encoded), ((values.shape[0] + 3) // 4) * ((values.shape[1] + 3) // 4) * 8)
            self.assertEqual(float(np.abs(ac.bc4_decode(encoded, values.shape[1], values.shape[0]) - values).max()), 0.0)

    def test_error_bound(self):
        rng = np.random.default_rng(7)
        values = rng.integers(0, 256, size=(64, 48), dtype=np.uint8)
        decoded = ac.bc4_decode(ac.bc4_encode(values), 48, 64)
        blocks = values.reshape(16, 4, 12, 4).transpose(0, 2, 1, 3).reshape(-1, 16).astype(float)
        bound = (blocks.max(1) - blocks.min(1)) / 14 + 0.5
        errors = np.abs(decoded - values).reshape(16, 4, 12, 4).transpose(0, 2, 1, 3).reshape(-1, 16).max(1)
        self.assertTrue(bool((errors <= bound).all()))

    def test_smooth_maps_are_close(self):
        y, x = np.mgrid[0:64, 0:64]
        values = (127 + 100 * np.sin(x / 9.0) * np.cos(y / 13.0)).astype(np.uint8)
        decoded = ac.bc4_decode(ac.bc4_encode(values), 64, 64)
        mse = float(((decoded - values) ** 2).mean())
        self.assertGreater(10 * math.log10(255 ** 2 / mse), 45)


class LuaTextTest(unittest.TestCase):
    def test_strings_and_numbers(self):
        self.assertEqual(ac.lua_string('a"b\\c'), '"a\\"b\\\\c"')
        self.assertEqual(ac.lua_string("x\n1"), '"x\\0101"')  # three digits: \10 then 1, not \101
        self.assertEqual(ac.lua_value(2.0), "2.0")
        self.assertEqual(ac.lua_value({"end": 1, "ok": [1, 2]}), '{ ["end"] = 1, ok = { 1, 2 } }')
        with self.assertRaises(ac.Refused):
            ac.lua_value(float("nan"))

    @unittest.skipUnless(LUAJIT, "LuaJIT is needed")
    def test_round_trip_in_lua(self):
        text = "café 日光\n1\t\"q\""
        script = "io.write(" + ac.lua_string(text) + ")"
        result = subprocess.run([LUAJIT, "-e", script], capture_output=True, timeout=30)
        # Windows' text-mode stdout writes \n as \r\n
        self.assertEqual(result.stdout.decode("utf-8").replace("\r\n", "\n"), text)


@unittest.skipIf(np is None or not LUAJIT, "numpy, Pillow and LuaJIT are needed")
class RuntimeTest(Base):
    def test_harness_scenarios(self):
        gma, _ = build_companion(self.tmp)
        code, out = self.run_convert(gma)
        self.assertEqual(code, 0)
        addon = os.path.join(out, "addon", "gm_test_map_rtx")
        for scenario in ("lifecycle", "other_map", "no_remix", "disable", "reload", "player_sky", "sky_takeover", "shell"):
            with self.subTest(scenario=scenario):
                result = subprocess.run([LUAJIT, os.path.join(HERE, "astra_companion_harness.lua"), addon, scenario],
                                        capture_output=True, text=True, timeout=60)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertIn("PASS " + scenario, result.stdout)


if __name__ == "__main__":
    unittest.main()
