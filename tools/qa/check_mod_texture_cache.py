"""check_mod_texture_cache.py: checks the Remix runtime's mod texture cache (rtx-remix\\cache\\mod-textures, runtime
patch 0086, ADR 0195) against the DDS files it describes: every entry whose file is unchanged must hold that file's
DDS header values and, byte for byte, the file's bytes of the smallest mips it keeps. Reads only. See
check_mod_texture_cache.py.md."""
from __future__ import annotations

import argparse
import json
import os
import struct
import sys
from pathlib import Path

MAGIC = b'NLMODTEX'
VERSION = 1
MAX_TAIL = 64 * 1024
HEADER = struct.Struct('<8sIIQQ')
STAMP = struct.Struct('<QqqQ')
RECORD = struct.Struct('<QQQQIIIIiiiq')
TAIL = struct.Struct('<II')
NO_TAIL = 0xFFFFFFFF


def fnv1a(data: bytes) -> int:
    value = 14695981039346656037
    for byte in data:
        value = ((value ^ byte) * 1099511628211) & 0xFFFFFFFFFFFFFFFF
    return value


class Damaged(Exception):
    pass


def read_cache(path: Path, verify_hash: bool = True) -> list[dict]:
    data = path.read_bytes()
    if len(data) < HEADER.size:
        raise Damaged('shorter than its header')
    magic, version, count, size, digest = HEADER.unpack_from(data, 0)
    payload = data[HEADER.size:]
    if magic != MAGIC or version != VERSION:
        raise Damaged(f'magic {magic!r} version {version}')
    if size != len(payload) or (verify_hash and fnv1a(payload) != digest):
        raise Damaged('payload size or checksum')
    entries, at = [], 0

    def take(n: int) -> bytes:
        nonlocal at
        if at + n > len(payload):
            raise Damaged('entry runs past the end')
        chunk = payload[at:at + n]
        at += n
        return chunk

    for _ in range(count):
        (chars,) = struct.unpack('<I', take(4))
        key = take(chars * 2).decode('utf-16-le')
        stamp = dict(zip(('size', 'last_write', 'change', 'file_id'), STAMP.unpack(take(STAMP.size))))
        values = RECORD.unpack(take(RECORD.size))
        record = dict(zip(('file_size', 'data_offset', 'data_size', 'size_of_all_levels', 'format', 'width', 'height',
                           'depth', 'levels', 'layers', 'faces', 'last_write'), values))
        if not 0 < record['levels'] <= 32:
            raise Damaged(f'{key}: {record["levels"]} levels')
        record['level_sizes'] = list(struct.unpack(f'<{record["levels"]}Q', take(8 * record['levels'])))
        first, tail_bytes = TAIL.unpack(take(TAIL.size))
        if tail_bytes > MAX_TAIL:
            raise Damaged(f'{key}: tail of {tail_bytes} bytes')
        entries.append({'key': key, 'stamp': stamp, 'record': record, 'tail_first': first, 'tail': take(tail_bytes)})
    if at != len(payload):
        raise Damaged('bytes after the last entry')
    return entries


def dds_header(data: bytes) -> dict:
    """The fields of a DDS file's headers that the runtime's partial loader records."""
    if data[:4] != b'DDS ' or len(data) < 128:
        raise ValueError('not a DDS file')
    height, width, _, depth, mips = struct.unpack_from('<IIIII', data, 12)
    flags = struct.unpack_from('<I', data, 80)[0]
    fourcc = data[84:88]
    offset = 128
    layers = 1
    if flags & 0x4 and fourcc in (b'DX10', b'GLI1'):
        offset += 20
        layers = max(1, struct.unpack_from('<I', data, 128 + 12)[0])
    return {'width': width, 'height': height, 'depth': depth or 1, 'levels': mips or 1, 'data_offset': offset,
            'layers': layers}


def check_entry(entry: dict, remap: tuple[str, str] | None = None) -> tuple[str, list[str]]:
    """('checked', its problems) for an entry whose file is unchanged since the entry was made; ('missing', []) or
    ('changed', []) otherwise: the runtime never uses such an entry (its folder listing shows the difference)."""
    key = entry['key']
    if remap and key.startswith(remap[0]):
        key = remap[1] + key[len(remap[0]):]
    path = Path(key)
    record, stamp = entry['record'], entry['stamp']
    try:
        info = os.stat(path)
    except OSError:
        return 'missing', []
    if info.st_size != stamp['size'] or info.st_mtime_ns // 100 + 116444736000000000 != stamp['last_write']:
        return 'changed', []
    problems = []
    data = path.read_bytes()
    header = dds_header(data)
    for key in ('width', 'height', 'levels', 'data_offset', 'layers'):
        if header[key] != record[key]:
            problems.append(f'{key} {record[key]} != the file\'s {header[key]}')
    if max(1, record['depth']) != header['depth']:
        problems.append(f'depth {record["depth"]} != the file\'s {header["depth"]}')
    if record['file_size'] != len(data) or record['last_write'] != stamp['last_write']:
        problems.append('size or write time of the record')
    if sum(record['level_sizes']) * record['layers'] * record['faces'] > len(data) - record['data_offset']:
        problems.append('levels larger than the file')
    if entry['tail_first'] != NO_TAIL:
        first = entry['tail_first']
        if record['layers'] != 1 or record['faces'] != 1 or not 0 <= first < record['levels']:
            problems.append(f'tail from level {first} of a {record["layers"]}-layer image')
        else:
            start = record['data_offset'] + sum(record['level_sizes'][:first])
            expected = data[start:start + sum(record['level_sizes'][first:])]
            if entry['tail'] != expected:
                problems.append(f'tail from level {first} ({len(entry["tail"])} bytes) differs from the file\'s '
                                f'{len(expected)} bytes at {start}')
    return 'checked', problems


def check(folder: Path, remap: tuple[str, str] | None = None) -> dict:
    result = {'folder': str(folder), 'files': 0, 'entries': 0, 'checked': 0, 'with_tail': 0, 'missing': 0,
              'changed': 0, 'problems': [], 'damaged': []}
    for cache in sorted(folder.glob('*.bin')):
        result['files'] += 1
        try:
            entries = read_cache(cache)
        except Damaged as error:
            result['damaged'].append(f'{cache.name}: {error}')
            continue
        for entry in entries:
            result['entries'] += 1
            status, problems = check_entry(entry, remap)
            result[status] += 1
            if status == 'checked':
                result['with_tail'] += entry['tail_first'] != NO_TAIL
            result['problems'] += [f'{entry["key"]}: {p}' for p in problems]
    result['problem_count'] = len(result['problems'])
    result['problems'] = result['problems'][:50]
    return result


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument('folder', type=Path, help='the cache folder (<game>\\rtx-remix\\cache\\mod-textures)')
    parser.add_argument('--remap', metavar='OLD=NEW',
                        help='read the file of an entry whose path starts with OLD (any case) below NEW instead: mods '
                             'moved away whole, as a PoC rollback moves them (a move keeps size and times)')
    parser.add_argument('--require-checked', action='store_true', help='exit 1 also when no entry could be checked')
    args = parser.parse_args(argv)
    remap = None
    if args.remap:
        old, _, new = args.remap.partition('=')
        remap = (old.lower(), new)
    result = check(args.folder, remap)
    print(json.dumps(result, indent=2))
    failed = result['problem_count'] or result['damaged'] or (args.require_checked and not result['checked'])
    return 1 if failed else 0


if __name__ == '__main__':
    sys.exit(main())
