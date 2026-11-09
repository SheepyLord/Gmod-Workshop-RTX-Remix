"""rpai's offline Remix texture hashes: the hash function the game uses, and the hash of a VTF."""
import codecs
import contextlib
import importlib.util
import io
import json
import struct
import sys
import tempfile
import unittest
from pathlib import Path
from types import SimpleNamespace

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO / 'skills' / 'mmd-remix-pbr' / 'tool'))
from rpai import cli, remixhash

HASHING = all(importlib.util.find_spec(name) for name in ('numpy', 'xxhash'))  # rpai's requirements
OPTION = 'rtx.useObsoleteHashOnTextureUpload'
STATUS = 'garrysmod/data/native-loader/status.json'
FIELD_DXVK = ['native-loader/remix/dxvk-1.conf', 'native-loader/remix/dxvk-2.conf',
              'native-loader/remix/memory.conf', 'dxvk.conf']  # the field's list on 2026-11-09


def hotloader_vtf(width, height, mips, flags=0, image_format=0):
    """A VTF laid out as Model Hotloader 2.3.1 writes one (native/assets.cpp): a 7.2 header of 80 bytes,
    no low-resolution image, one frame, then the mip levels, given largest first, stored smallest first."""
    header = bytearray(80)
    header[0:4] = b'VTF\0'
    struct.pack_into('<III', header, 4, 7, 2, 80)
    struct.pack_into('<HHIH', header, 16, width, height, flags, 1)
    struct.pack_into('<3f', header, 32, .5, .5, .5)
    struct.pack_into('<fi', header, 48, 1.0, image_format)
    header[56] = len(mips)
    struct.pack_into('<i', header, 57, -1)
    struct.pack_into('<H', header, 63, 1)
    return bytes(header) + b''.join(reversed(mips))


def one_colour_vtf(width, height, rgba, flags=0):
    """Every level of a single-colour sheet is that colour (Model Hotloader's 2x2 box filter keeps it)."""
    levels = [(width, height)]
    while levels[-1] != (1, 1):
        levels.append((max(1, levels[-1][0] // 2), max(1, levels[-1][1] // 2)))
    return hotloader_vtf(width, height, [bytes(rgba) * (w * h) for w, h in levels], flags)


class GameRootTests(unittest.TestCase):
    def setUp(self):
        scratch = REPO / 'out' / 'tmp'
        scratch.mkdir(parents=True, exist_ok=True)
        self.temp = tempfile.TemporaryDirectory(dir=scratch, prefix='remix-hash-')
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)

    def write(self, relative, text, encoding='utf-8'):
        path = self.root / relative
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_bytes(text if isinstance(text, bytes) else text.encode(encoding))
        return path

    def status(self, dxvk, rtx=('rtx.conf',), outcome='active'):
        self.write(STATUS, json.dumps({'schema': 1, 'activation': {
            'outcome': outcome, 'layers': {'rtx': list(rtx), 'dxvk': list(dxvk)}}}))

    def field(self):
        """The field install's layout: the package's classic defaults as dxvk-1.conf, line 139 included;
        rtx.conf and user.conf without the option (the case rpai read as XXH3 since 2026-10-29)."""
        self.status(FIELD_DXVK)
        lines = [f'rtx.line{n} = 1' for n in range(1, 139)] + [f'{OPTION} = True']
        self.write('native-loader/remix/dxvk-1.conf', '\r\n'.join(lines) + '\r\n')
        self.write('native-loader/remix/dxvk-2.conf', 'dxvk.numCompilerThreads = 0\n')
        self.write('native-loader/remix/memory.conf', 'd3d9.textureMemory = 0\n')
        self.write('rtx.conf', 'rtx.graphicsPreset = 4\n')
        self.write('user.conf', 'rtx.enableRaytracing = True\n')

    def resolve(self, env=None):
        return remixhash.resolve_obsolete_hash_option(self.root, {} if env is None else env)


class ConfReaderTests(GameRootTests):
    def test_lines_read_as_the_runtime_reads_them(self):
        path = self.write('a.conf', '\r\n'.join([
            '# comment', '  rtx.a = True', 'rtx.b=  "1"', 'rtx.c = True  ', 'rtx.d =', 'RTX.E = True',
            'rtx.f = False', 'rtx.f = True', 'rtx.g True', '[hl2.exe]', 'rtx.h = True', '[gmod.exe]',
            'rtx.i = x "y" z']))
        self.assertEqual(remixhash.read_conf(path), {
            'rtx.a': ('True', 2), 'rtx.b': ('1', 3), 'rtx.c': ('True  ', 4), 'rtx.d': ('', 5),
            'RTX.E': ('True', 6), 'rtx.f': ('True', 8), 'rtx.i': ('x y z', 13)})

    def test_byte_order_mark_hides_the_first_line_and_missing_files_are_empty(self):
        path = self.write('bom.conf', codecs.BOM_UTF8 + f'{OPTION} = True\nrtx.x = 1\n'.encode())
        self.assertEqual(remixhash.read_conf(path), {'rtx.x': ('1', 2)})
        self.assertEqual(remixhash.read_conf(self.root / 'missing.conf'), {})

    def test_values_as_the_runtime_parses_a_bool(self):
        self.status(['dxvk.conf'])
        for value, expected in (('True', True), ('TRUE', True), ('1', True), ('"True"', True), ('False', False),
                                ('0', False), ('yes', False), ('True ', False), ('True # comment', False)):
            with self.subTest(value=value):
                self.write('rtx.conf', f'{OPTION} = {value}\n')
                self.assertIs(self.resolve().obsolete, expected)


class OptionTests(GameRootTests):
    def test_field_layout_reads_the_packages_layer(self):
        self.field()
        option = self.resolve()
        self.assertIs(option.obsolete, True)
        self.assertTrue(option.source.startswith('native-loader/remix/dxvk-1.conf line 139 (DXVK Config'))
        self.assertIs(remixhash.read_obsolete_hash_option(self.root), True)

    def test_first_listed_dxvk_file_wins(self):
        self.field()
        self.write('dxvk.conf', f'{OPTION} = False\n')
        self.assertIs(self.resolve().obsolete, True)  # the root dxvk.conf comes last
        self.status(['dxvk.conf', *FIELD_DXVK[:-1]])
        self.assertIs(self.resolve().obsolete, False)

    def test_remix_config_beats_dxvk_config_unless_its_value_is_empty(self):
        self.field()
        self.write('rtx.conf', f'{OPTION} =\n')
        self.assertIs(self.resolve().obsolete, True)  # Config::findOption: an empty value is none
        self.write('rtx.conf', f'{OPTION} = False\n')
        self.assertEqual((self.resolve().obsolete, self.resolve().source[:16]), (False, 'rtx.conf line 1 '))
        self.write('rtx.conf', f'[hl2.exe]\n{OPTION} = False\n')
        self.assertIs(self.resolve().obsolete, True)  # a section for another executable

    def test_user_conf_is_strongest_and_only_read(self):
        self.field()
        self.write('rtx.conf', f'{OPTION} = True\n')
        user = self.write('user.conf', f'rtx.enableRaytracing = True\n{OPTION} = False\n')
        before = user.read_bytes()
        option = self.resolve()
        self.assertEqual((option.obsolete, option.source[:17]), (False, 'user.conf line 2 '))
        self.assertEqual(user.read_bytes(), before)

    def test_journal_when_the_latest_start_was_not_active(self):
        self.field()
        self.status(FIELD_DXVK, outcome='failed')
        payload = 'native-loader/packages/gmod-rtx-remix/1.0_3'
        self.write('native-loader/state.json', json.dumps({'schema': 1, 'current': {'generation': 3, 'packages': [
            {'id': 'a-map', 'version': '1', 'payload': ''},
            {'id': 'gmod-rtx-remix', 'version': '1.0', 'payload': payload, 'remix': {
                'rtx_conf_layers': [], 'dxvk_conf_layers': ['config/dxvk/01.conf', 'config/dxvk/02.conf']}}]}}))
        self.write(f'{payload}/config/dxvk/02.conf', f'{OPTION} = True\n')
        option = self.resolve()
        self.assertIs(option.obsolete, True)
        self.assertIn(f'{payload}/config/dxvk/02.conf line 1 (DXVK Config; the deployed runtime package', option.source)
        self.write('mine.conf', f'{OPTION} = False\n')
        self.assertIs(self.resolve({'DXVK_CONFIG_FILE': 'mine.conf'}).obsolete, True)  # after the package's
        self.assertIs(self.resolve({'DXVK_RTX_CONFIG_FILE': 'none.conf,mine.conf'}).obsolete, False)

    def test_without_the_loader(self):
        self.assertEqual((self.resolve().obsolete, self.resolve().source),
                         (False, "Remix's default: no layer sets it (no native loader)"))
        self.write('rtx.conf', f'{OPTION} = True\n')
        self.assertIs(self.resolve().obsolete, True)
        self.assertIs(self.resolve({'DXVK_RTX_CONFIG_FILE': ','}).obsolete, False)  # a list of no files
        self.write('dxvk.conf', f'{OPTION} = 1\n')
        self.assertIs(self.resolve({'DXVK_RTX_CONFIG_FILE': ','}).obsolete, True)

    def test_lists_the_runtime_cannot_read_leave_the_root_conf(self):
        self.write('dxvk.conf', f'{OPTION} = True\n')
        self.write('long.conf', f'{OPTION} = False\n')
        fits = ','.join(['long.conf'] * 26)  # 259 characters: the runtime reads the list
        self.assertIs(self.resolve({'DXVK_CONFIG_FILE': fits}).obsolete, False)
        self.assertIs(self.resolve({'DXVK_CONFIG_FILE': fits + ','}).obsolete, True)  # 260: read as empty
        self.status(fits.split(','))
        self.assertIs(self.resolve().obsolete, False)
        self.status((fits + ',x').split(','))  # the loader reports the list it set, however long
        self.assertIs(self.resolve().obsolete, True)

    def test_a_base_game_mod_leaves_it_unknown(self):
        self.field()
        self.write('rtx.conf', 'rtx.baseGameModRegex = portal\n')
        self.assertIs(self.resolve().obsolete, True)  # without a path regex there is no mod folder
        self.write('rtx.conf', 'rtx.baseGameModRegex = portal\nrtx.baseGameModPathRegex = (.*)\n')
        self.assertIsNone(self.resolve().obsolete)
        self.write('user.conf', f'{OPTION} = True\n')
        self.assertIs(self.resolve().obsolete, True)  # User Settings outrank a mod's rtx.conf


@unittest.skipUnless(HASHING, 'numpy and xxhash (rpai requirements.txt) are not installed')
class PredictionTests(GameRootTests):
    # Live hashes the game reported through `rpai hashes` (%USERPROFILE%\.rpai\work\<key>\hashes.json):
    # single-colour, opaque sheets many MMD models share. Recorded for 0x84168AFC8CF54915 in 9 models
    # (fu_xuan_19c0edc5, huohuo_effd51e1, ...), for 0x37B3BC9B48184AA9 in 4 (huohuo_effd51e1, ...).
    RECORDED = [((1024, 1024, (228, 118, 118, 255)), '0x84168AFC8CF54915'),
                ((520, 520, (69, 69, 69, 255)), '0x37B3BC9B48184AA9')]

    def test_reproduces_recorded_live_hashes(self):
        self.field()
        option = self.resolve()
        for (width, height, rgba), live in self.RECORDED:
            with self.subTest(live=live):
                self.assertEqual(remixhash.predict(one_colour_vtf(width, height, rgba), option.obsolete), [live])

    def test_one_candidate_per_hash_function(self):
        blob = one_colour_vtf(520, 520, (69, 69, 69, 255))
        xxh64, xxh3 = remixhash.predict(blob, True), remixhash.predict(blob, False)
        self.assertEqual((len(xxh64), len(xxh3)), (1, 1))
        self.assertNotEqual(xxh64, xxh3)
        self.assertEqual(remixhash.predict(blob, None), xxh64 + xxh3)

    def test_texel_order_alpha_and_blocks(self):
        import xxhash

        def h64(data):
            return [f'0x{xxhash.xxh64_intdigest(data, seed=0):016X}']

        top = bytes(range(1, 17))  # 2x2 RGBA texels (1,2,3,4), (5,6,7,8), ...
        bgra = b''.join(bytes((top[i + 2], top[i + 1], top[i], top[i + 3])) for i in range(0, 16, 4))
        bgr0 = b''.join(bgra[i:i + 3] + b'\0' for i in range(0, 16, 4))
        self.assertEqual(remixhash.predict(hotloader_vtf(2, 2, [top, bytes(4)], flags=0x2000)), h64(bgra))
        self.assertEqual(remixhash.predict(hotloader_vtf(2, 2, [top, bytes(4)])), h64(bgr0))
        blocks = bytes(range(64))  # DXT5 8x8: four 16-byte blocks, uploaded unchanged
        dxt5 = hotloader_vtf(8, 8, [blocks, bytes(16), bytes(16), bytes(16)], image_format=15)
        self.assertEqual(remixhash.predict(dxt5), h64(blocks))

    def test_hashes_command_logs_and_records_the_decision(self):
        """`rpai hashes` without the game: the field's decision in its log and hashes.json, one predicted hash,
        and earlier live hashes reused only from a record made under the same decision."""
        self.field()
        key, live = 'b0d75d0b692bd65c', '0x37B3BC9B48184AA9'
        texture = SimpleNamespace(vtf=f'mmd/t/{key}', source=None, width=520, height=520, materials=[0])
        blob = one_colour_vtf(520, 520, (69, 69, 69, 255))
        asset = SimpleNamespace(asset_id='0' * 40, mdl=None, vmts={0: f'mmd/0000/{key}_1'}, textures={key: texture},
                                iter_vtf_data=lambda: iter([(key, texture, blob)]))
        for earlier_rule, reused in ((True, True), (False, False)):
            with self.subTest(earlier_obsolete_hash=earlier_rule):
                earlier = {'obsolete_hash': earlier_rule, 'textures': {key: {
                    'vtf': texture.vtf, 'live': ['0x0123456789ABCDEF'], 'verified': True}}}
                files = {'hashes.json': earlier}
                ctx = SimpleNamespace(asset=asset, game_root=self.root, bridge=None, args=SimpleNamespace(no_live=True),
                                      read=lambda name: files.get(name, {}), write=files.__setitem__)
                with contextlib.redirect_stdout(io.StringIO()) as out:
                    table = cli.cmd_hashes(ctx)
                self.assertIn('hash    XXH64: native-loader/remix/dxvk-1.conf line 139 (DXVK Config;', out.getvalue())
                record = files['hashes.json']
                self.assertIs(record['obsolete_hash'], True)
                self.assertTrue(record['obsolete_hash_source'].startswith('native-loader/remix/dxvk-1.conf line 139'))
                self.assertEqual(table[key]['predicted'], [live])
                self.assertEqual(table[key]['use'], ['0x0123456789ABCDEF'] if reused else [live])
                self.assertEqual(table[key]['verified'], reused)


if __name__ == '__main__':
    unittest.main()
