"""Tests of the naming rule (model_names.py) and of the scripts that refuse a tagged name.

Run from this folder:  python -I -m unittest -v
(unittest's discovery puts this folder on sys.path; nothing is written outside a temporary folder,
which honours TEMP: point it at the repository's out\\tmp when you run them there.)
"""
from __future__ import annotations

import contextlib
import importlib.util
import io
import json
import os
import sys
import tempfile
import unittest
from pathlib import Path

HERE = Path(__file__).resolve().parent
SIBLING = HERE.parents[1] / "mmd-remix-pbr" / "scripts"
sys.path.insert(0, str(HERE))
import model_names  # noqa: E402
import mmdhl_pack  # noqa: E402
import pbr_mod  # noqa: E402
import check_pack  # noqa: E402

TAGGED_NAMES = (
    "鸣潮-千咲", "星穹铁道-桂乃芬", "阿芙2.0", "Alf 合体7", "Robin R18", "Robin R-18", "HSR Robin",
    "[Arknights] Texas", "【明日方舟】德克萨斯", "Chisa (WuWa)", "Robin ZZZ", "Furina v2", "Kafka Ver.3",
    "风堇1.0by_mobius", "Tda式初音ミクV4X", "Genshin Impact - Furina", "Endfield Laevatain", "千咲2",
    "Robin 2", "New MMD Model", "Chisa RTX", "Firefly NSFW", "库拉蒂—骑士", "三月七 1.0", "By Alicia Chisa",
    "异环-Elyms", "Mizuki 18+", "原神芙宁娜", "白银之城-Alf",
)
CLEAN_NAMES = (
    "Chisa", "Guinaifen", "Alf", "Robin", "March 7th", "Evernight and March 7th", "Guinaifen (桂乃芬)",
    "三月七", "長夜月", "Hiyuki Alt", "Eldreda Sunbringer", "阮·梅", "Ruan Mei", "A2", "2B", "Laevatain",
    "Shorekeeper", "Kafka", "Hu Tao", "Jean-Luc", "Ho-oh", "Dante", "ルーシー", "Silver Wolf", "Topaz",
    "The Herta", "Fu Xuan", "HuoHuo", "Elyms", "Jingliu",
)


def load_sibling(name: str):
    """A script of the mmd-remix-pbr skill, loaded from its file (it imports its own model_names copy)."""
    spec = importlib.util.spec_from_file_location("sibling_" + name, SIBLING / (name + ".py"))
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


def run(main, argv):
    """(exit code, stderr text) of a script's main(argv); SystemExit with a message counts as 1."""
    err = io.StringIO()
    code = 0
    with contextlib.redirect_stderr(err), contextlib.redirect_stdout(io.StringIO()):
        try:
            result = main(argv)
            code = result if isinstance(result, int) else 0
        except SystemExit as stop:
            if isinstance(stop.code, str):
                err.write(stop.code)
                code = 1
            else:
                code = stop.code or 0
    return code, err.getvalue()


class RuleTests(unittest.TestCase):
    def test_tagged_names_are_refused(self):
        for name in TAGGED_NAMES:
            with self.subTest(name=name):
                self.assertTrue(model_names.find(name, "name"), name)
                self.assertIn(repr(name), model_names.refusal("item name", name))

    def test_plain_names_pass(self):
        for name in CLEAN_NAMES:
            with self.subTest(name=name):
                self.assertEqual(model_names.find(name, "name"), [])
                self.assertIsNone(model_names.refusal("item name", name))

    def test_reasons_name_the_tag(self):
        self.assertEqual(model_names.find("鸣潮-千咲"), ["game tag '鸣潮'", "<prefix>-<name> folder form '潮-千'"])
        self.assertEqual(model_names.find("阿芙2.0"), ["version or edition tag '2.0'"])
        self.assertEqual(model_names.find("Alf 合体7"), ["version or edition tag '合体7'"])
        self.assertEqual(model_names.find("Robin 2"), ["version or edition tag '2'"])
        self.assertEqual(model_names.find("Tda式初音ミクV4X"), ["version or edition tag 'v4'", "author tag 'tda式'"])

    def test_titles_allow_the_pack_suffix_but_not_tags(self):
        for title in ("Chisa (Model Hotloader + RTX PBR)", "Evernight and March 7th (Model Hotloader + RTX PBR)",
                      "Modern House RTX (native loader package)", "Chisa RTX PBR, packaged for the Workshop.",
                      "Default"):
            self.assertEqual(model_names.find(title, "title"), [], title)
        for title in ("Robin R18 RTX (native loader package)", "鸣潮-千咲 (Model Hotloader + RTX PBR)",
                      "Robin RTX PBR (rpai layer robin_r18_f9c3e4b4), packaged for the Workshop.",
                      "Chisa v2 (Model Hotloader + RTX PBR)"):
            self.assertTrue(model_names.find(title, "title"), title)

    def test_slugs(self):
        for slug in ("mmdhl_chisa", "pbr_evernight_march7th", "chisa-rtx", "evernight-march7th-rtx", "robin",
                     "march_7th", "modern_house_rtx", "modern-house-rtx", "guinaifen-rtx", "gm_br_rtx"):
            self.assertEqual(model_names.find(slug, "slug"), [], slug)
        for slug in ("mmdhl_robin_r18", "robin-r18-rtx", "pbr_chisa_wuwa", "hsr_robin", "alf_2_0", "chisa_v2",
                     "robin_zzz", "chisa_2", "pbr_genshin_furina"):
            self.assertTrue(model_names.find(slug, "slug"), slug)

    def test_prose_flags_games_only(self):
        self.assertEqual(model_names.find("Chisa (Wuthering Waves), imported with Model Hotloader", "prose"),
                         ["game tag 'wuthering waves'"])
        self.assertEqual(model_names.find("Chisa, made by rpai. Needs loader 0.16.0 or later; MMD model.", "prose"), [])

    def test_unknown_kind(self):
        with self.assertRaises(ValueError):
            model_names.find("Chisa", "label")

    @unittest.skipUnless((SIBLING / "model_names.py").is_file(), "mmd-remix-pbr is not beside this skill")
    def test_the_two_copies_are_identical(self):
        self.assertEqual((HERE / "model_names.py").read_bytes(), (SIBLING / "model_names.py").read_bytes(),
                         "change workshop-content-pack/scripts/model_names.py and mmd-remix-pbr/scripts/model_names.py together")


class PackerTests(unittest.TestCase):
    """The packers refuse before they read or write anything: the cache and sources need not exist."""

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="test-names-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def test_mmdhl_pack_refuses_a_tagged_item_name(self):
        out = self.root / "mmdhl_chisa"
        code, err = run(mmdhl_pack.main, [str(self.root / "no-cache"), "deadbeef", str(out),
                                          "Chisa (Model Hotloader + RTX PBR)", "鸣潮-千咲", "SheepyLord",
                                          str(self.root / "no-description.txt")])
        self.assertEqual(code, 1)
        self.assertIn("item name '鸣潮-千咲'", err)
        self.assertIn("game tag '鸣潮'", err)
        self.assertFalse(out.exists())
        self.assertEqual(list(self.root.iterdir()), [])

    def test_mmdhl_pack_refuses_tagged_item_title_preset_and_folder(self):
        cases = (
            (["--item", "cafebabe=Alf 合体7"], "mmdhl_chisa", "Chisa (Model Hotloader + RTX PBR)", "--item cafebabe name"),
            (["--default-preset-name", "Default v2"], "mmdhl_chisa", "Chisa (Model Hotloader + RTX PBR)", "default preset name"),
            ([], "mmdhl_chisa_wuwa", "Chisa (Model Hotloader + RTX PBR)", "out folder"),
            ([], "mmdhl_chisa", "Chisa R18 (Model Hotloader + RTX PBR)", "title"),
        )
        for extra, folder, title, label in cases:
            with self.subTest(label=label):
                code, err = run(mmdhl_pack.main, [str(self.root / "no-cache"), "deadbeef", str(self.root / folder),
                                                  title, "Chisa", "SheepyLord", str(self.root / "d.txt"), *extra])
                self.assertEqual(code, 1)
                self.assertIn(label, err)
                self.assertEqual(list(self.root.iterdir()), [])

    def test_mmdhl_pack_clean_names_reach_the_next_check(self):
        code, err = run(mmdhl_pack.main, [str(self.root / "no-cache"), "deadbeef", str(self.root / "mmdhl_chisa"),
                                          "Chisa (Model Hotloader + RTX PBR)", "Chisa", "SheepyLord",
                                          str(self.root / "d.txt"), "--item", "cafebabe=March 7th"])
        self.assertEqual(code, 1)
        self.assertIn("has no assets folder", err)
        self.assertNotIn("carries", err)

    def test_pbr_mod_refuses_a_tagged_label_or_folder_even_in_a_dry_run(self):
        for label, folder, expect in (("阿芙2.0", "pbr_alf", "label"), ("Alf", "pbr_alf_2_0", "out folder")):
            with self.subTest(expect=expect):
                code, err = run(pbr_mod.main, [str(self.root / "no-mod"), "alf_f68499a5", str(self.root / folder),
                                               label, "--dry-run"])
                self.assertEqual(code, 1)
                self.assertIn(expect, err)
                self.assertEqual(list(self.root.iterdir()), [])


class CheckPackTests(unittest.TestCase):
    ASSET = "1c2ed2fc" + "0" * 56
    FILES = {"assets/%s/manifest.json" % ASSET: {"sha256": "0" * 64},
             "assets/%s/model.bin" % ASSET: {"sha256": "1" * 64}}

    def item(self, name):
        return {"kind": "character", "asset": self.ASSET, "name": name, "files": sorted(self.FILES),
                "terms": {"file": "x.pmx", "embedded": {"nameEnglish": "x"}, "readmes": []}}

    def report(self, name, keep=()):
        r = check_pack.Report()
        with contextlib.redirect_stdout(io.StringIO()) as out:
            check_pack.check_item(r, self.item(name), self.FILES, keep)
        return r, out.getvalue()

    def test_a_tagged_display_name_is_an_error(self):
        r, out = self.report("Robin R18")
        self.assertGreaterEqual(r.errors, 1)
        self.assertIn("rating tag 'r18'", out)

    def test_keep_name_turns_it_into_a_warning(self):
        r, out = self.report("Robin R18", keep=("1c2ed2fc",))
        self.assertEqual(r.errors, 0)
        self.assertIn("kept as published", out)

    def test_a_plain_name_passes(self):
        r, out = self.report("Chisa")
        self.assertEqual(r.errors, 0)
        self.assertIn("plain ASCII display name", out)

    def test_folders_and_package_id(self):
        r = check_pack.Report()
        with contextlib.redirect_stdout(io.StringIO()) as out:
            check_pack.check_names(r, "x/mmdhl_robin_r18", "x/pbr_robin_r18", "robin-r18-rtx", True)
        self.assertEqual(r.errors, 3, out.getvalue())

    def test_description_naming_a_game_is_an_error(self):
        with tempfile.TemporaryDirectory(prefix="test-names-") as folder:
            path = Path(folder) / "description.txt"
            path.write_text("Chisa (Wuthering Waves), RTX package 3829070317, the native loader winmm.dll; "
                            "GMod cannot mount it.", encoding="utf-8")
            r = check_pack.Report()
            with contextlib.redirect_stdout(io.StringIO()) as out:
                check_pack.check_description(r, str(path))
        self.assertEqual(r.errors, 1, out.getvalue())
        self.assertIn("names a game", out.getvalue())


@unittest.skipUnless(SIBLING.is_dir(), "mmd-remix-pbr is not beside this skill")
class SiblingScriptTests(unittest.TestCase):
    """mmd-remix-pbr's scripts refuse a tagged name before they touch the game, rpai or the disk."""

    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="test-names-")
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def test_stage_pbr_mod(self):
        stage = load_sibling("stage_pbr_mod")
        for dest, doc, expect in (("pbr_robin_r18", "Robin RTX PBR, packaged for the Workshop.", "--dest folder"),
                                  ("pbr_robin", "Robin R18 RTX PBR, packaged for the Workshop.", "--doc")):
            with self.subTest(expect=expect):
                code, err = run(stage.main, ["--src", str(self.root / "no-mod"), "--dest", str(self.root / dest),
                                             "--layer", "robin_r18_f9c3e4b4", "--doc", doc])
                self.assertEqual(code, 1)
                self.assertIn(expect, err)
                self.assertEqual(list(self.root.iterdir()), [])

    def test_package_characters(self):
        package = load_sibling("package_characters")
        code, err = run(package.main, ["--dest", str(self.root / "package"), "--character", "鸣潮-千咲=chisa_0123abcd"])
        self.assertEqual(code, 1)
        self.assertIn("--character name", err)
        self.assertEqual(list(self.root.iterdir()), [])

    def test_hotloader_export_title_and_library_names(self):
        export = load_sibling("hotloader_export")
        game = self.root / "game"
        asset = "cf3eec2f" + "1" * 56
        data = game / "garrysmod" / "data" / "mmd_hotloader"
        (data / "assets" / asset).mkdir(parents=True)
        (data / "library").mkdir(parents=True)
        (data / "library" / (asset + ".json")).write_text(json.dumps({"name": "星穹铁道-長夜月"}), encoding="utf-8")
        gmapack = self.root / "gmapack.py"
        gmapack.write_text("", encoding="utf-8")
        common = ["--game-root", str(game), "--asset", "cf3eec2f", "--description-file", str(self.root / "d.txt"),
                  "--file-name", "evernight", "--gmapack", str(gmapack)]
        code, err = run(export.main, common + ["--title", "Evernight R18 (Model Hotloader + RTX PBR)",
                                               "--out", str(self.root / "mmdhl_evernight")])
        self.assertEqual(code, 1)
        self.assertIn("--title", err)
        code, err = run(export.main, common + ["--title", "Evernight (Model Hotloader + RTX PBR)",
                                               "--out", str(self.root / "mmdhl_evernight")])
        self.assertEqual(code, 1)
        self.assertIn("library name of cf3eec2f", err)
        self.assertIn("game tag '星穹铁道'", err)
        self.assertFalse((self.root / "mmdhl_evernight").exists())
        self.assertFalse((game / "garrysmod" / "data" / "rpai").exists())


if __name__ == "__main__":
    unittest.main()
