"""The mod texture cache (runtime patch 0086, ADR 0195): a later start reads no unchanged texture file again.

Compiles and runs the store's unit test from the committed patch (MSVC, as the runtime builds it), checks that the
runtime's mod loader uses the store, and tests the lab's cache checker and log parser."""
import os
from pathlib import Path
import re
import struct
import subprocess
import sys
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO / 'tools' / 'qa'))
sys.path.insert(0, str(REPO / 'tools'))

import check_mod_texture_cache as checker  # noqa: E402
import mod_load_session  # noqa: E402

PATCHES = sorted((REPO / 'runtime' / 'patches').glob('0086-*.patch'))
VS = Path(os.environ.get('ProgramFiles(x86)', 'C:/Program Files (x86)')) / 'Microsoft Visual Studio/2022/BuildTools'
STORE = 'src/dxvk/rtx_render/rtx_mod_texture_store.h'
TEST = 'tests/rtx/unit/test_mod_texture_store.cpp'


def patch_text() -> str:
    if len(PATCHES) != 1:
        raise AssertionError(f'expected one runtime patch 0086, found {[p.name for p in PATCHES]}')
    return PATCHES[0].read_text(encoding='utf-8')


def postimage(patch: str, path: str) -> str:
    """A file the patch creates, whole (one hunk from line 1 with every line added)."""
    block = patch.split(f'diff --git a/{path} b/{path}\n', 1)[1].split('\ndiff --git ', 1)[0]
    if 'new file mode' not in block.split('@@', 1)[0]:
        raise AssertionError(f'{path}: not a new file in the patch')
    header, body = block.split('@@', 2)[1:]
    match = re.search(r'\+1,(\d+)', header) or re.search(r'\+1 ', header + ' ')
    count = int(match[1]) if match and match.groups() else 1
    lines = [line[1:] for line in body.splitlines()[1:] if line.startswith('+')]
    if len(lines) != count:
        raise AssertionError(f'{path}: hunk length mismatch ({len(lines)} != {count})')
    return '\n'.join(lines) + '\n'


def added_lines(patch: str, path: str) -> str:
    block = patch.split(f'diff --git a/{path} b/{path}\n', 1)[1].split('\ndiff --git ', 1)[0]
    return '\n'.join(line[1:] for line in block.splitlines() if line.startswith('+') and not line.startswith('+++'))


SCRIPT = '''param([string]$Repo, [string]$Scratch)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $Repo 'tools/lib/VsDevEnv.psm1') -Force
Enter-VsDevEnv | Out-Null
$env:TEMP = $env:TMP = $Scratch
Set-Location -LiteralPath $Scratch
& cl.exe /nologo /EHsc /std:c++17 /O2 /W4 /WX /UNDEBUG /utf-8 tests/rtx/unit/test_mod_texture_store.cpp /Festore.exe /Fostore.obj
if ($LASTEXITCODE) { exit $LASTEXITCODE }
& ./store.exe (Join-Path $Scratch 'work')
exit $LASTEXITCODE
'''


def dds(width: int, height: int, levels: int, seed: int) -> tuple[bytes, list[int]]:
    """An uncompressed RGBA8 DDS with a full header and `levels` mips of deterministic bytes."""
    sizes = [max(1, width >> i) * max(1, height >> i) * 4 for i in range(levels)]
    header = bytearray(128)
    header[:4] = b'DDS '
    struct.pack_into('<IIIIIII', header, 4, 124, 0x1 | 0x2 | 0x4 | 0x1000 | 0x20000, height, width, width * 4, 0, levels)
    struct.pack_into('<II4sIIIII', header, 76, 32, 0x41, b'\0\0\0\0', 32, 0xFF0000, 0xFF00, 0xFF, 0xFF000000)
    body = bytes((seed + i * 7) & 0xFF for i in range(sum(sizes)))
    return bytes(header) + body, sizes


def cache_bytes(entries: list[dict]) -> bytes:
    """A cache file as the runtime writes one (rtx_mod_texture_store.h, version 1)."""
    payload = bytearray()
    for e in entries:
        key = e['key'].encode('utf-16-le')
        payload += struct.pack('<I', len(e['key'])) + key
        payload += checker.STAMP.pack(e['size'], e['last_write'], e['change'], e['file_id'])
        r = e['record']
        payload += checker.RECORD.pack(r['file_size'], r['data_offset'], r['data_size'], r['size_of_all_levels'],
                                       r['format'], r['width'], r['height'], r['depth'], r['levels'], r['layers'],
                                       r['faces'], r['last_write'])
        payload += struct.pack(f'<{len(r["level_sizes"])}Q', *r['level_sizes'])
        payload += checker.TAIL.pack(e['tail_first'], len(e['tail'])) + e['tail']
    return checker.HEADER.pack(checker.MAGIC, checker.VERSION, len(entries), len(payload),
                               checker.fnv1a(bytes(payload))) + bytes(payload)


class StoreTests(unittest.TestCase):
    @unittest.skipUnless(os.name == 'nt' and VS.is_dir(), 'MSVC x64 Build Tools unavailable')
    def test_store_unit_test_from_the_patch(self):
        patch = patch_text()
        scratch = REPO / 'out' / 'tmp'
        scratch.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(prefix='mod-texture-store-', dir=scratch) as directory:
            root = Path(directory)
            for path in (STORE, TEST):
                file = root / path
                file.parent.mkdir(parents=True, exist_ok=True)
                file.write_text(postimage(patch, path), encoding='utf-8')
            script = root / 'run.ps1'
            script.write_text(SCRIPT, encoding='utf-8')
            result = subprocess.run(['powershell', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', str(script),
                                     '-Repo', str(REPO), '-Scratch', str(root)],
                                    capture_output=True, text=True, timeout=300)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertRegex(result.stdout, r'PASS mod texture store: \d+ checks')

    def test_the_mod_loader_uses_the_store(self):
        patch = patch_text()
        usd = added_lines(patch, 'src/dxvk/rtx_render/rtx_mod_usd.cpp')
        # Every texture a mod's first load names goes through the cache, which is written when the load ends.
        self.assertIn('m_textureCache->find(resolvedTexturePath)', usd)
        self.assertIn('m_textureCache->save();', usd)
        self.assertIn('std::make_unique<ModTextureCache>(m_owner.m_filePath)', usd)
        self.assertIn('[RTX Mod Load] mod=', usd)
        self.assertIn('modTextureCache, true', added_lines(patch, 'src/dxvk/rtx_render/rtx_options.h'))
        self.assertIn("'rtx_render/rtx_mod_texture_cache.cpp'", added_lines(patch, 'src/dxvk/meson.build'))
        glue = postimage(patch, 'src/dxvk/rtx_render/rtx_mod_texture_cache.cpp')
        self.assertIn('restoreDdsAsset(resolvedPath, record, std::move(tail))', glue)
        self.assertIn('loadDdsAssetForCache(resolvedPath', glue)
        store = postimage(patch, STORE)
        # An entry is used only while the file's size, both times and its id match; a stale-capable entry is not kept.
        self.assertIn('size == o.size && lastWriteTime == o.lastWriteTime && changeTime == o.changeTime && fileId == o.fileId', store)
        self.assertIn('info.nNumberOfLinks == 1', store)


class CheckerTests(unittest.TestCase):
    def setUp(self):
        scratch = REPO / 'out' / 'tmp'
        scratch.mkdir(parents=True, exist_ok=True)
        self.directory = tempfile.TemporaryDirectory(prefix='mod-texture-check-', dir=scratch)
        self.root = Path(self.directory.name)
        data, sizes = dds(64, 32, 7, 3)
        self.texture = self.root / 'textures' / 'a.dds'
        self.texture.parent.mkdir()
        self.texture.write_bytes(data)
        info = os.stat(self.texture)
        last_write = info.st_mtime_ns // 100 + 116444736000000000
        first = 7 - 5
        start = 128 + sum(sizes[:first])
        self.entry = {
            'key': str(self.texture).lower(), 'size': len(data), 'last_write': last_write, 'change': last_write,
            'file_id': 1, 'tail_first': first, 'tail': data[start:start + sum(sizes[first:])],
            'record': {'file_size': len(data), 'data_offset': 128, 'data_size': sum(sizes),
                       'size_of_all_levels': sum(sizes), 'format': 37, 'width': 64, 'height': 32, 'depth': 0,
                       'levels': 7, 'layers': 1, 'faces': 1, 'last_write': last_write, 'level_sizes': sizes}}
        self.cache = self.root / 'cache'
        self.cache.mkdir()

    def tearDown(self):
        self.directory.cleanup()

    def test_a_right_entry_passes(self):
        (self.cache / 'mod-0.bin').write_bytes(cache_bytes([self.entry]))
        result = checker.check(self.cache)
        self.assertEqual((result['entries'], result['checked'], result['with_tail'], result['problem_count'],
                          result['damaged']), (1, 1, 1, 0, []))

    def test_moved_mods_are_checked_where_they_went(self):
        (self.cache / 'mod-0.bin').write_bytes(cache_bytes([self.entry]))
        moved = self.root / 'moved'
        self.texture.parent.rename(moved)
        self.assertEqual(checker.check(self.cache)['missing'], 1)
        old = str(self.root / 'textures').lower()
        result = checker.check(self.cache, (old, str(moved)))
        self.assertEqual((result['checked'], result['problem_count']), (1, 0))

    def test_a_wrong_tail_or_header_is_found(self):
        wrong = dict(self.entry, tail=bytes(len(self.entry['tail'])))
        (self.cache / 'mod-0.bin').write_bytes(cache_bytes([wrong]))
        self.assertEqual(checker.check(self.cache)['problem_count'], 1)
        record = dict(self.entry['record'], width=32)
        (self.cache / 'mod-0.bin').write_bytes(cache_bytes([dict(self.entry, record=record)]))
        self.assertEqual(checker.check(self.cache)['problem_count'], 1)

    def test_a_changed_file_is_not_judged(self):
        (self.cache / 'mod-0.bin').write_bytes(cache_bytes([dict(self.entry, size=self.entry['size'] + 1)]))
        result = checker.check(self.cache)
        self.assertEqual((result['changed'], result['checked'], result['problem_count']), (1, 0, 0))

    def test_a_damaged_file_is_reported(self):
        data = bytearray(cache_bytes([self.entry]))
        data[-1] ^= 0xFF
        (self.cache / 'mod-0.bin').write_bytes(bytes(data))
        self.assertEqual(len(checker.check(self.cache)['damaged']), 1)


class LogTests(unittest.TestCase):
    def test_the_lab_reads_the_runtimes_lines(self):
        log = '\n'.join([
            '[10:00:00.000] info:  Game: gmod.exe',
            '[10:00:05.000] info:  Adding asset search path: h:\\g\\rtx-remix\\mods\\gm_x\\',
            '[10:00:06.500] info:  [RTX Mod Load] mod=gm_x ms=1500 stage_ms=20 materials=540 materials_ms=1400 '
            'textures=1812 usd_ms=80 find_ms=900 preload_ms=300 meshes=0 meshes_ms=0 lights=0 lights_ms=0',
            '[10:00:06.500] info:  [RTX Mod Texture Cache] mod=gm_x lookups=1812 repeats=60 hits=1752 misses=0 '
            'unkept=0 unlisted=0 folders=1 list_ms=4 read_ms=2 save_ms=0 loaded=1 ignored=0 saved=0 save_failed=0',
            '[10:00:06.600] info:  [RTX Mod Load] all mods=1 ms=1600',
        ])
        parsed = mod_load_session.parse_log(log)
        self.assertEqual(parsed['total'], {'mods': 1, 'ms': 1600.0, 'at': 6.6})
        self.assertEqual(parsed['mods'][0]['textures'], 1812.0)
        self.assertEqual(parsed['cache_sum']['hits'], 1752)
        self.assertEqual(parsed['mod_order'], ['gm_x'])


if __name__ == '__main__':
    unittest.main()
