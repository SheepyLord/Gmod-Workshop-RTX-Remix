"""The shared VR ABI must stay identical in the module and the exported runtime patches."""
import re
import unittest
from pathlib import Path

ROOT = Path(__file__).resolve().parents[2]
HEADER = 'src/dxvk/rtx_render/rtx_vr_api.h'


def patched_header(patches, target=HEADER):
    """Replay just the target's unified hunks, including later edits, without a runtime clone."""
    result = []
    found = False
    for patch in patches:
        lines = patch.read_text(encoding='utf-8').splitlines(keepends=True)
        active = False
        output = None
        old = 0
        for line in lines:
            if line.startswith('diff --git '):
                if output is not None:
                    result = output + result[old:]
                    output = None
                active = line.rstrip() == f'diff --git a/{target} b/{target}'
                continue
            if not active:
                continue
            match = re.match(r'@@ -(\d+)(?:,\d+)? \+\d+(?:,\d+)? @@', line)
            if match:
                if output is None:
                    output = []
                    old = 0
                    found = True
                start = max(0, int(match[1]) - 1)
                output.extend(result[old:start])
                old = start
            elif output is not None and line.startswith(('+', '-', ' ')):
                if line.startswith('-- '):  # format-patch trailer
                    active = False
                    continue
                if line[0] in ' -':
                    if old >= len(result) or result[old] != line[1:]:
                        raise ValueError(f'{patch.name}: header hunk does not apply at line {old + 1}')
                    old += 1
                if line[0] in ' +':
                    output.append(line[1:])
        if output is not None:
            result = output + result[old:]
    if not found:
        raise ValueError('runtime patches do not contain the shared VR API header')
    return ''.join(result).encode('utf-8')


class SharedApiTests(unittest.TestCase):
    def test_module_and_runtime_export_the_same_header(self):
        actual = patched_header(sorted((ROOT / 'runtime/patches').glob('*.patch')))
        expected = (ROOT / 'vr/native/include/rtxvr_api.h').read_bytes().replace(b'\r\n', b'\n')
        self.assertEqual(actual, expected, 'change both copies of the versioned VR ABI together')


if __name__ == '__main__':
    unittest.main()
