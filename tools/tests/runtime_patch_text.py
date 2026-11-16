"""Reads the runtime fork's patches (runtime/patches/*.patch) as text, for the gate tests that check them without the
fork's 3.6 GB tree: one file's block of a patch, a file a patch creates whole, a file rebuilt from the patches that
created and changed it, and the lines the patches add that no later patch removes."""
from collections import Counter
from pathlib import Path
import re

REPO = Path(__file__).resolve().parents[2]
PATCHES = REPO / 'runtime' / 'patches'
HUNK = re.compile(r'^@@ -(\d+)(?:,(\d+))? \+(\d+)(?:,(\d+))? @@')


def patch_paths() -> list:
    return sorted(PATCHES.glob('*.patch'))


def one_patch(number: int) -> Path:
    found = sorted(PATCHES.glob(f'{number:04d}-*.patch'))
    if len(found) != 1:
        raise AssertionError(f'expected one runtime patch {number:04d}, found {[p.name for p in found]}')
    return found[0]


def read(path: Path) -> str:
    return path.read_text(encoding='utf-8')


def file_blocks(patch: str) -> dict:
    """{path: its diff block (from the line after 'diff --git' up to the next one)} of every file in a patch."""
    blocks = {}
    for chunk in re.split(r'^diff --git ', patch, flags=re.M)[1:]:
        header = chunk.split('\n', 1)[0]
        match = re.match(r'a/(.+?) b/(.+)$', header)
        if match:
            blocks[match.group(2)] = chunk.split('\n', 1)[1] if '\n' in chunk else ''
    return blocks


def file_block(patch: str, path: str) -> str:
    blocks = file_blocks(patch)
    if path not in blocks:
        raise AssertionError(f'{path} is not in the patch')
    return blocks[path]


def hunks(block: str) -> list:
    """[(old start, [lines with their ' ', '-' or '+' mark])] of a file's block, each hunk as long as its header says."""
    out = []
    old_left = new_left = 0
    for line in block.split('\n'):
        if old_left == 0 and new_left == 0:
            match = HUNK.match(line)
            if match:
                old_left = int(match.group(2)) if match.group(2) is not None else 1
                new_left = int(match.group(4)) if match.group(4) is not None else 1
                out.append((int(match.group(1)), []))
            continue
        if line.startswith('\\'):
            continue  # "\ No newline at end of file"
        mark = line[:1] if line else ' '  # an empty context line whose space an editor dropped
        if mark == ' ':
            old_left -= 1
            new_left -= 1
        elif mark == '-':
            old_left -= 1
        elif mark == '+':
            new_left -= 1
        else:
            raise AssertionError(f'unexpected line in a hunk: {line[:60]!r}')
        out[-1][1].append(line if line else ' ')
    return out


def added_lines(patch: str, path: str) -> str:
    return '\n'.join(line[1:] for _, lines in hunks(file_block(patch, path)) for line in lines if line.startswith('+'))


def removed_lines(patch: str, path: str) -> str:
    return '\n'.join(line[1:] for _, lines in hunks(file_block(patch, path)) for line in lines if line.startswith('-'))


def postimage(patch: str, path: str) -> str:
    """A file the patch creates, whole."""
    block = file_block(patch, path)
    if 'new file mode' not in block.split('@@', 1)[0]:
        raise AssertionError(f'{path}: not a new file in the patch')
    return apply(None, block, path)


def apply(text, block: str, path: str) -> str:
    """`text` (None for a new file) with the hunks of a file's block applied, each found by its context."""
    lines = [] if text is None else text.split('\n')
    if lines and lines[-1] == '':
        lines.pop()
    shift = 0
    for start, body in hunks(block):
        old = [line[1:] for line in body if line[0] in (' ', '-')]
        new = [line[1:] for line in body if line[0] in (' ', '+')]
        at = max(start - 1 + shift, 0) if old else min(max(start + shift, 0), len(lines))
        if lines[at:at + len(old)] != old:
            found = [i for i in range(len(lines) - len(old) + 1) if lines[i:i + len(old)] == old]
            if len(found) != 1:
                raise AssertionError(f'{path}: a hunk at line {start} does not apply')
            at = found[0]
        lines[at:at + len(old)] = new
        shift += len(new) - len(old)
    return '\n'.join(lines) + '\n'


def rebuilt(path: str) -> str:
    """A file the fork's own tree lacks, as the patches create and change it (every patch that touches it, in order)."""
    text = None
    for patch_path in patch_paths():
        blocks = file_blocks(read(patch_path))
        if path in blocks:
            block = blocks[path]
            if text is None and 'new file mode' not in block.split('@@', 1)[0]:
                raise AssertionError(f'{path}: {patch_path.name} changes it before any patch creates it')
            text = apply(text, block, path)
    if text is None:
        raise AssertionError(f'no runtime patch creates {path}')
    return text


def live_added_lines() -> dict:
    """{path: Counter of line texts} the patches add and no later patch removes again (the series' own code)."""
    live = {}
    for patch_path in patch_paths():
        for path, block in file_blocks(read(patch_path)).items():
            counts = live.setdefault(path, Counter())
            for _, body in hunks(block):
                for line in body:
                    if line.startswith('-') and counts[line[1:]] > 0:
                        counts[line[1:]] -= 1
                    elif line.startswith('+'):
                        counts[line[1:]] += 1
    return live
