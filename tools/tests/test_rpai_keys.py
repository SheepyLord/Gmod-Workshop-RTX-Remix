"""Offline tests of rpai's model keys: the naming rule's tags stay out of them, and a model keyed before
2026-11-17 moves to its new key (work folder, preset, published layer)."""
import contextlib
import io
import re
import sys
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

REPO = Path(__file__).resolve().parents[2]
SKILL = REPO / 'skills' / 'mmd-remix-pbr'
sys.path.insert(0, str(SKILL / 'tool'))
from rpai import cli, config, dds  # noqa: E402

ASSET = 'f9c3e4b4' + '0' * 32
OLD, NEW = 'robin_r18_f9c3e4b4', 'robin_f9c3e4b4'


def quiet():
    return contextlib.redirect_stdout(io.StringIO())


class KeyTests(unittest.TestCase):
    def test_keys_carry_no_tags(self):
        for english, key in (('Robin R18', NEW), ('New MMD Model', 'model_f9c3e4b4'),
                             ('Topaz R18Ver1.4', 'topaz_f9c3e4b4'), ('Silver Wolf R18', 'silver_wolf_f9c3e4b4'),
                             ('HSR Robin', NEW), ('Kafka', 'kafka_f9c3e4b4'), ('March 7th', 'march_7th_f9c3e4b4'),
                             ('', 'model_f9c3e4b4'), ('桂乃芬', 'model_f9c3e4b4'), ('Elyms Alt2', 'elyms_alt2_f9c3e4b4')):
            self.assertEqual(config.model_key(ASSET, english), key, english)

    def test_the_legacy_key_is_the_old_formula(self):
        self.assertEqual(config.legacy_model_key(ASSET, 'Robin R18'), OLD)
        self.assertEqual(config.legacy_model_key(ASSET, 'New MMD Model'), 'new_mmd_model_f9c3e4b4')
        self.assertEqual(config.legacy_model_key(ASSET, 'Kafka'), config.model_key(ASSET, 'Kafka'))

    def test_the_skills_presets_are_named_by_keys_without_tags(self):
        # A preset's name is <slug>_<asset id8>[_<variant>]: making a key from the slug again gives it back.
        named = 0
        for preset in (SKILL / 'tool' / 'presets').rglob('*.json'):
            match = re.fullmatch(r'(.+)_([0-9a-f]{8})(?:_.+)?', preset.stem)
            if not match:
                continue
            slug, id8 = match.groups()
            self.assertEqual(config.model_key(id8 + '0' * 32, slug.replace('_', ' ')), f'{slug}_{id8}', preset.name)
            named += 1
        self.assertGreater(named, 10)


class MoveTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)

    def tearDown(self):
        self.tmp.cleanup()

    def test_the_old_work_folder_moves_to_the_new_key(self):
        (self.root / OLD).mkdir()
        (self.root / OLD / 'hashes.json').write_text('{}')
        self.assertTrue(cli.adopt_legacy_work(self.root, NEW, OLD))
        self.assertTrue((self.root / NEW / 'hashes.json').exists())
        self.assertFalse((self.root / OLD).exists())
        # the new folder exists already, or there is no old key: nothing moves
        (self.root / OLD).mkdir()
        self.assertFalse(cli.adopt_legacy_work(self.root, NEW, OLD))
        self.assertTrue((self.root / OLD).exists())
        self.assertFalse(cli.adopt_legacy_work(self.root, 'kafka_00000000', None))

    def test_a_preset_named_after_the_old_key_is_still_read(self):
        with patch.object(config, 'model_presets', lambda key: self.root / f'{key}.json'):
            self.assertEqual(cli.model_preset(NEW, OLD), self.root / f'{NEW}.json')
            (self.root / f'{OLD}.json').write_text('{}')
            self.assertEqual(cli.model_preset(NEW, OLD), self.root / f'{OLD}.json')
            (self.root / f'{NEW}.json').write_text('{}')
            self.assertEqual(cli.model_preset(NEW, OLD), self.root / f'{NEW}.json')
            self.assertEqual(cli.model_preset('kafka_00000000', None), self.root / 'kafka_00000000.json')

    def mod_with_old_layer(self):
        mod = self.root / 'mod'
        (mod / 'models').mkdir(parents=True)
        (mod / 'models' / f'{OLD}.usda').write_text('#usda 1.0\n')
        (mod / 'textures' / OLD).mkdir(parents=True)
        (mod / 'textures' / OLD / 'old.a.rtex.dds').write_bytes(b'DDS')
        return mod

    def context(self, mod, **extra):
        png = self.root / 'work' / 'map.png'
        png.parent.mkdir(exist_ok=True)
        png.write_bytes(b'generated fixture; no image decoder needed')
        generated = {'sheet': {'emissive_scale': 0.0, 'classes': {'cloth': 1}, 'maps': {'roughness': str(png)}}}
        hashes = {'sheet': {'use': ['00000000000000AA']}}
        return SimpleNamespace(key=NEW, legacy_key=OLD, settings=config.Settings(),
                               args=SimpleNamespace(no_prune=True), asset=SimpleNamespace(asset_id=ASSET),
                               read=lambda name: generated if name == 'generated.json' else {'textures': hashes},
                               mod_dir=lambda: mod, **extra)

    def test_publish_replaces_the_old_keys_layer(self):
        mod = self.mod_with_old_layer()

        def encode(jobs, **kwargs):
            for _source, dest, _kind in jobs:
                dest.parent.mkdir(parents=True, exist_ok=True)
                dest.write_bytes(b'DDS fixture')

        with patch.object(dds, 'encode', side_effect=encode), quiet():
            cli.cmd_publish(self.context(mod))
        self.assertTrue((mod / 'models' / f'{NEW}.usda').exists())
        self.assertFalse((mod / 'models' / f'{OLD}.usda').exists())
        self.assertEqual(list((mod / 'textures' / OLD).glob('*.dds')), [])
        listed = (mod / 'mod.usda').read_text(encoding='utf-8')
        self.assertIn(f'{NEW}.usda', listed)
        self.assertNotIn(OLD, listed)

    def test_remove_takes_out_both_keys_layers(self):
        mod = self.mod_with_old_layer()
        (mod / 'models' / f'{NEW}.usda').write_text('#usda 1.0\n')
        with quiet():
            cli.cmd_remove(self.context(mod))
        self.assertEqual(list((mod / 'models').glob('*.usda')), [])
        self.assertEqual(list((mod / 'textures' / OLD).glob('*.dds')), [])


if __name__ == '__main__':
    unittest.main()
