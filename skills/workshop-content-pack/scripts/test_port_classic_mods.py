"""Unit tests of usd_refs.py and port_classic_mods.py on synthetic mods (layers and a crate file written
here; nothing from a game)."""
import io
import os
import struct
import sys
import tempfile
import unittest
from contextlib import redirect_stdout

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import port_classic_mods as P  # noqa: E402
import usd_refs as U  # noqa: E402

HEADER = '#usda 1.0\n(\n    metersPerUnit = 0.01\n    subLayers = [\n        @./replacements.usda@\n    ]\n    upAxis = "Z"\n)\n'


def write(path, data):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    mode = "wb" if isinstance(data, bytes) else "w"
    with open(path, mode, **({} if isinstance(data, bytes) else {"encoding": "utf-8", "newline": "\n"})) as fh:
        fh.write(data)


def read(path):
    with open(path, "rb") as fh:
        return fh.read()


def literal_block(raw: bytes) -> bytes:
    """An LZ4 block of one literal-only sequence (valid, if not compressed)."""
    n = len(raw)
    token = min(n, 15) << 4
    extra = b""
    if n >= 15:
        rest = n - 15
        extra = b"\xff" * (rest // 255) + bytes([rest % 255])
    return bytes([token]) + extra + raw


def crate(tokens):
    """A minimal USD crate: header, a TOKENS section (TfFastCompression, one chunk), a TOC."""
    raw = b"".join(t.encode() + b"\0" for t in tokens)
    packed = b"\0" + literal_block(raw)
    section = struct.pack("<QQQ", len(tokens), len(raw), len(packed)) + packed
    start = 24
    toc = start + len(section)
    head = b"PXR-USDC" + bytes([0, 8, 0, 0, 0, 0, 0, 0]) + struct.pack("<Q", toc)
    entry = b"TOKENS".ljust(16, b"\0") + struct.pack("<qq", start, len(section))
    return head + section + struct.pack("<Q", 1) + entry


def material(digest, body):
    return '        over "mat_%s"\n        {\n            over "Shader"\n            {\n%s            }\n        }\n' % (digest, body)


def layer(*blocks, meshes=""):
    text = '#usda 1.0\n(\n    upAxis = "Z"\n)\n\nover "RootNode"\n{\n    over "Looks"\n    {\n'
    text += "".join(blocks) + "    }\n"
    if meshes:
        text += '    over "meshes"\n    {\n' + meshes + "    }\n"
    return text + "}\n"


class Refs(unittest.TestCase):
    def test_text_references(self):
        text = ('asset a = @./t/a.dds@ (\n  customData = { asset default = @@ }\n  doc = "mail @me@ here"\n)\n'
                '# a comment @./x.dds@\nasset b = @@@./t/b c.dds@@@\nasset c = @AperturePBR_Opacity.mdl@\n')
        self.assertEqual([r for _, _, r in U.text_references(text)],
                         ["./t/a.dds", "./t/b c.dds", "AperturePBR_Opacity.mdl"])

    def test_blank_missing_only_files(self):
        with tempfile.TemporaryDirectory() as d:
            write(os.path.join(d, "t", "ok.dds"), b"x")
            text = ("asset a = @./t/ok.dds@\nasset b = @./t/gone.dds@ (\n)\n"
                    "subLayers = [@./gone.usda@]\nasset s = @AperturePBR_Opacity.mdl@\n")
            new, missing = U.blank_missing(text, d)
            self.assertEqual(missing, ["./t/gone.dds"])
            self.assertIn("asset b = @@ (", new)
            self.assertIn("@./t/ok.dds@", new)
            self.assertIn("@./gone.usda@", new)
            self.assertIn("@AperturePBR_Opacity.mdl@", new)

    def test_lz4_literals_and_overlapping_match(self):
        self.assertEqual(U.lz4_block(literal_block(b"hello"), 100), b"hello")
        long = bytes(range(256)) * 2
        self.assertEqual(U.lz4_block(literal_block(long), 1000), long)
        # 'abc' then a match of 9 at offset 3 (overlapping copy), then an empty last sequence.
        self.assertEqual(U.lz4_block(b"\x35abc\x03\x00\x00", 100), b"abcabcabcabc")
        chunks = b"\x02" + struct.pack("<i", 4) + literal_block(b"abc") + struct.pack("<i", 3) + literal_block(b"de")
        self.assertEqual(U.fast_decompress(chunks, 10), b"abcde")
        with self.assertRaises(ValueError):
            U.lz4_block(b"\x10a\x05\x00", 100)  # offset past the output

    def test_crate_tokens_and_references(self):
        with tempfile.TemporaryDirectory() as d:
            path = os.path.join(d, "m.usd")
            write(path, crate(["", "Looks", "./SubUSDs/textures/a.dds", "AperturePBR_Opacity.mdl", "inputs:x"]))
            self.assertTrue(U.is_crate(path))
            self.assertEqual(U.crate_tokens(path)[2], "./SubUSDs/textures/a.dds")
            self.assertEqual(U.layer_references(path), ["./SubUSDs/textures/a.dds", "AperturePBR_Opacity.mdl"])

    def test_walk_nested_crate_missing_outside_and_shader_beside(self):
        with tempfile.TemporaryDirectory() as d:
            mod = os.path.join(d, "mod")
            write(os.path.join(mod, "mod.usda"), '#usda 1.0\n(\n    subLayers = [\n        @./a/mod.usda@\n    ]\n)\n')
            write(os.path.join(mod, "a", "mod.usda"), HEADER)
            write(os.path.join(mod, "a", "replacements.usda"),
                  'over "x" (\n references = @./models/m.usd@\n)\n{\n asset t = @./t.dds@\n asset g = @./gone.dds@\n'
                  ' asset o = @../../outside.dds@\n asset s = @Shader.mdl@\n asset b = @textures/bare.dds@\n}\n')
            write(os.path.join(mod, "a", "t.dds"), b"t")
            write(os.path.join(mod, "a", "Shader.mdl"), b"mdl")
            write(os.path.join(mod, "a", "models", "m.usd"), crate(["./tex/m.dds"]))
            write(os.path.join(mod, "a", "models", "tex", "m.dds"), b"m")
            write(os.path.join(mod, "a", "unused.dds"), b"u")
            w = U.walk(mod)
            self.assertEqual(w.layers, ["mod.usda", "a/mod.usda", "a/replacements.usda", "a/models/m.usd"])
            self.assertEqual(w.crate, ["a/models/m.usd"])
            self.assertEqual(sorted(w.files), ["a/Shader.mdl", "a/models/tex/m.dds", "a/t.dds"])
            self.assertEqual(w.missing, [("a/replacements.usda", "./gone.dds")])
            self.assertEqual(w.outside, [("a/replacements.usda", "../../outside.dds")])
            self.assertEqual(w.bare, [("a/replacements.usda", "textures/bare.dds")])
            self.assertEqual(w.shaders, {"Shader.mdl"})
            unused = [f for f in U.mod_files(mod) if f.lower() not in w.used()]
            self.assertEqual(unused, ["a/unused.dds"])


class Port(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.d = self.tmp.name

    def tearDown(self):
        self.tmp.cleanup()

    def source(self, name, text, files=()):
        root = os.path.join(self.d, "src", name)
        write(os.path.join(root, "mod.usda"), HEADER)
        write(os.path.join(root, "replacements.usda"), text)
        for rel in files:
            write(os.path.join(root, rel), rel.encode())
        return root

    def run_port(self, *args):
        buf = io.StringIO()
        with redirect_stdout(buf):
            code = P.main(list(args))
        return code, buf.getvalue()

    def test_merge_keeps_runtime_order_and_files(self):
        main = self.source("Main", layer(
            material("AAAAAAAAAAAAAAAA", '                asset inputs:diffuse_texture = @./tex/a.dds@ (\n'
                     '                    customData = {\n                        asset default = @@\n'
                     '                    }\n                )\n                float inputs:metallic_constant = 0\n'
                     '                float inputs:reflection_roughness_constant = 1\n')),
            files=["tex/a.dds", "tex/dead.dds"])
        fix = self.source("Main_fix", layer(
            material("AAAAAAAAAAAAAAAA", "                float inputs:metallic_constant = 0\n"
                     "                float inputs:reflection_roughness_constant = 0.5\n"),
            material("BBBBBBBBBBBBBBBB", "                float inputs:metallic_constant = 1\n")))
        water = self.source("water_fix", layer(material("CCCCCCCCCCCCCCCC", "                float inputs:ior_constant = 1.33\n")))
        dest = os.path.join(self.d, "out", "map_rtx")
        code, text = self.run_port("--dest", dest, "--source", water, "--source", fix, "--source", main,
                                   "--drop-unreferenced")
        self.assertEqual(code, 0, text)
        self.assertIn("runtime order (strongest first): Main, Main_fix, water_fix", text)
        self.assertIn("owned by Main, the others add nothing", text)
        root = read(os.path.join(dest, "mod.usda")).decode()
        self.assertLess(root.index("./Main/mod.usda"), root.index("./Main_fix/mod.usda"))
        self.assertLess(root.index("./Main_fix/mod.usda"), root.index("./water_fix/mod.usda"))
        self.assertEqual(read(os.path.join(dest, "Main", "replacements.usda")), read(os.path.join(main, "replacements.usda")))
        self.assertTrue(os.path.isfile(os.path.join(dest, "Main", "tex", "a.dds")))
        self.assertFalse(os.path.exists(os.path.join(dest, "Main", "tex", "dead.dds")))
        self.assertFalse(U.walk(dest).missing)

    def test_later_source_adding_attributes_is_refused(self):
        main = self.source("Main", layer(material("AAAAAAAAAAAAAAAA", "                float inputs:metallic_constant = 0\n")))
        fix = self.source("Main_fix", layer(material("AAAAAAAAAAAAAAAA",
                                                     "                float inputs:reflection_roughness_constant = 0.5\n")))
        code, text = self.run_port("--dest", os.path.join(self.d, "out", "m"), "--source", main, "--source", fix)
        self.assertEqual(code, 1)
        self.assertIn("Main owned it, but Main_fix also sets Shader.inputs:reflection_roughness_constant", text)
        self.assertFalse(os.path.exists(os.path.join(self.d, "out", "m")))

    def test_empty_prim_does_not_own_a_mesh(self):
        main = self.source("Main", layer(meshes='        over "mesh_DDDDDDDDDDDDDDDD"\n        {\n        }\n'))
        fix = self.source("Main_fix", layer(meshes='        over "mesh_DDDDDDDDDDDDDDDD"\n        {\n'
                                            '            over "mesh"\n            {\n'
                                            '                custom uniform bool remix_category:decal_Static = 0\n'
                                            '            }\n        }\n'))
        code, text = self.run_port("--dest", os.path.join(self.d, "out", "m"), "--source", main, "--source", fix, "--dry-run")
        self.assertEqual(code, 0, text)
        self.assertIn("mesh_DDDDDDDDDDDDDDDD in Main, Main_fix: owned by Main_fix", text)

    def test_missing_files_need_blank_missing(self):
        main = self.source("Main", layer(material("AAAAAAAAAAAAAAAA",
                                                  "                asset inputs:metallic_texture = @./tex/gone.dds@ (\n"
                                                  "                    colorSpace = \"auto\"\n                )\n")))
        dest = os.path.join(self.d, "out", "m")
        code, text = self.run_port("--dest", dest, "--source", main)
        self.assertEqual(code, 1)
        self.assertIn("names 1 files it does not have", text)
        code, text = self.run_port("--dest", dest, "--source", main, "--blank-missing")
        self.assertEqual(code, 0, text)
        self.assertIn("1 references blanked", text)
        self.assertIn("asset inputs:metallic_texture = @@ (", read(os.path.join(dest, "replacements.usda")).decode())

    def test_single_source_is_a_byte_identical_rename(self):
        main = self.source("SafeHouse", layer(material("AAAAAAAAAAAAAAAA", "                asset inputs:diffuse_texture = @./a.dds@\n")),
                           files=["a.dds"])
        write(os.path.join(main, "models", "m.usd"), crate(["./t.dds"]))
        write(os.path.join(main, "models", "t.dds"), b"t")
        with open(os.path.join(main, "replacements.usda"), "a", encoding="utf-8") as fh:
            fh.write('over "m" (\n references = @./models/m.usd@\n)\n{\n}\n')
        dest = os.path.join(self.d, "out", "safehouse_rtx")
        code, text = self.run_port("--dest", dest, "--source", main)
        self.assertEqual(code, 0, text)
        for rel in U.mod_files(main):
            self.assertEqual(read(os.path.join(dest, rel)), read(os.path.join(main, rel)), rel)
        self.assertEqual(U.mod_files(dest), U.mod_files(main))
        code, text = self.run_port("--dest", dest, "--source", main)
        self.assertEqual(code, 1)
        self.assertIn("exists (--force replaces it)", text)


if __name__ == "__main__":
    unittest.main()
