"""purge_file_cache.py: drops files from Windows' file cache without administrator rights, so the next read of each
comes from the disk, as at a game's first start after a reboot. Opening a file without buffering
(FILE_FLAG_NO_BUFFERING) makes NTFS flush and purge the file's cached pages while nothing has the file mapped.
Reads nothing and writes nothing. See purge_file_cache.py.md."""
from __future__ import annotations

import argparse
import ctypes
import json
import os
import sys
import time
from ctypes import wintypes
from pathlib import Path

GENERIC_READ = 0x80000000
FILE_SHARE_ALL = 0x1 | 0x2 | 0x4
OPEN_EXISTING = 3
FILE_FLAG_NO_BUFFERING = 0x20000000
INVALID_HANDLE_VALUE = ctypes.c_void_p(-1).value

kernel32 = ctypes.WinDLL('kernel32', use_last_error=True)
kernel32.CreateFileW.restype = wintypes.HANDLE
kernel32.CreateFileW.argtypes = (wintypes.LPCWSTR, wintypes.DWORD, wintypes.DWORD, wintypes.LPVOID, wintypes.DWORD,
                                 wintypes.DWORD, wintypes.HANDLE)
kernel32.CloseHandle.argtypes = (wintypes.HANDLE,)


def purge(paths) -> dict:
    """Opens each file once without buffering; returns how many were purged and which could not be opened."""
    done, failed = 0, []
    for path in paths:
        handle = kernel32.CreateFileW(str(path), GENERIC_READ, FILE_SHARE_ALL, None, OPEN_EXISTING,
                                      FILE_FLAG_NO_BUFFERING, None)
        if handle == INVALID_HANDLE_VALUE or handle is None:
            failed.append(str(path))
            continue
        kernel32.CloseHandle(handle)
        done += 1
    return {'purged': done, 'failed': failed[:20], 'failed_count': len(failed)}


def files_below(folders) -> list[Path]:
    result = []
    for folder in folders:
        for base, _, names in os.walk(folder):
            result.extend(Path(base) / name for name in names)
    return result


def tail_read_seconds(paths, size=4096) -> float:
    """Opens each file and reads its last `size` bytes (as the runtime reads a texture's smallest mips)."""
    started = time.perf_counter()
    for path in paths:
        with open(path, 'rb') as stream:
            stream.seek(max(0, path.stat().st_size - size))
            stream.read(size)
    return time.perf_counter() - started


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument('folders', nargs='+', type=Path, help='every file below these folders is purged')
    parser.add_argument('--check', action='store_true',
                        help='also time a tail read of every file before and after the purge (it reads the files)')
    args = parser.parse_args(argv)
    paths = files_below(args.folders)
    result = {'files': len(paths)}
    if args.check:
        tail_read_seconds(paths)
        result['warm_s'] = round(tail_read_seconds(paths), 3)
    started = time.perf_counter()
    result.update(purge(paths))
    result['purge_s'] = round(time.perf_counter() - started, 3)
    if args.check:
        result['after_purge_s'] = round(tail_read_seconds(paths), 3)
    print(json.dumps(result))
    return 0 if not result['failed_count'] else 1


if __name__ == '__main__':
    sys.exit(main())
