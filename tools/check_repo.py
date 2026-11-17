"""Check the repo's documentation conventions; print every problem and exit 1 if any.

Rules (AGENTS.md explains why):
1. Every script (.ps1 .psm1 .py .bat .cmd .lua .sh) has '<script file name>.md' beside it.
2. Every folder with a CMakeLists.txt (except the repo root) has a README.md naming every
   C/C++ source file below it; sub-folders with their own CMakeLists.txt are their own module.
3. Relative links in Markdown files point at files or folders that exist.
4. CHANGELOG.md has an '## [Unreleased]' section.
5. docs/COMPONENTS.md mentions every folder directly under loader/ and tools/.
6. CLAUDE.md imports AGENTS.md.
7. runtime/base.json "packaged" matches runtime/ and packages/runtime: the stored d3d9.dll is what
   runtime/build_runtime.ps1 builds from this repository.
8. tools/ci/pins.json "repository_builds": each native module this repository compiles and stores in
   packages/ has a "packaged" record, its sources match it, and packages/ holds the recorded file
   (tools/ci/repo_builds.py; ADR 0126).
9. No text file under packages/ names a Windows account's folder (C:\\Users\\<account>\\...): every part is
   published with the repository and the package (a maintainer's path shipped once, review finding 19).
10. No other text file names one either, and no text file anywhere (packages/ included) names the Windows
   account this check runs under: its user name, its profile folder or that folder's 8.3 short name. The
   repository is public (AGENTS.md rule 10); placeholders such as %USERPROFILE% or <user> pass.
"""

import argparse
import hashlib
import json
import os
import re
import sys
from pathlib import Path
from urllib.parse import unquote

sys.path.insert(0, str(Path(__file__).resolve().parent / 'ci'))
import repo_builds  # noqa: E402  (tools/ci/repo_builds.py: the records of this repository's own modules)

SCRIPT_EXTS = {'.ps1', '.psm1', '.py', '.bat', '.cmd', '.lua', '.sh'}
SOURCE_EXTS = {'.c', '.cc', '.cpp', '.cxx', '.h', '.hh', '.hpp', '.inl', '.asm', '.def', '.rc', '.in'}
SKIP_DIRS = {'.git', 'out', 'build', '__pycache__', 'third_party', '.vs', '.venv', 'venv', 'node_modules'}
# Top-level folders of vendored content, kept byte for byte (ADR 0033): the RTX package's inputs, whose
# add-ons bring their own scripts and READMEs.
SKIP_TOP = {'packages'}
COMPONENT_ROOTS = ('loader', 'tools')

LINK_RE = re.compile(r'\[[^\]]*\]\(\s*<?([^)\s>]+)>?(?:\s+"[^"]*")?\s*\)')
# A Windows account's folder, with one or two backslashes (as JSON writes them) or slashes; the account
# name starts with a letter or digit, so placeholders such as <account> or %USERNAME% do not match.
USER_FOLDER_RE = re.compile(r'(?<![A-Za-z])[A-Za-z]:(?:\\{1,2}|/)Users(?:\\{1,2}|/)([A-Za-z0-9][^\\/\s"\'<>|*?:`]*)',
                            re.I)
# Names that stand for any account in an example: an 8.3 short name, a word (the Model Hotloader's installation
# tests use C:\Users\Someone, the render guard's harness C:\Users\private-person).
PLACEHOLDER_ACCOUNTS = {'name~1', 'me', 'name', 'user', 'username', 'yourname', 'you', 'example', 'public',
                        'default', 'someone', 'private-person'}
# Account names too common to look for in text (a build machine's, Windows' own).
COMMON_ACCOUNTS = {'admin', 'administrator', 'runneradmin', 'runner', 'guest', 'owner', 'users', 'test'}
# The tests of the account rules write their fixtures from this file.
ACCOUNT_RULE_TESTS = {'tools/tests/test_check_repo.py'}
FENCE_RE = re.compile(r'^(```|~~~).*?^\1', re.S | re.M)
INLINE_CODE_RE = re.compile(r'`[^`\n]*`')


def _files(root):
    stack = [root]
    while stack:
        current = stack.pop()
        for entry in sorted(current.iterdir()):
            if entry.is_dir():
                if (entry / '.git').exists():
                    continue  # another checkout: a worktree (the app keeps them in .claude/worktrees) or a clone
                if entry.name not in SKIP_DIRS and not (current == root and entry.name in SKIP_TOP):
                    stack.append(entry)
            else:
                yield entry


def _rel(path, root):
    return path.relative_to(root).as_posix()


def check_script_docs(root, files):
    return [f'{_rel(f, root)}: missing {f.name}.md beside it'
            for f in files if f.suffix.lower() in SCRIPT_EXTS and not f.with_name(f.name + '.md').exists()]


def check_module_readmes(root, files):
    problems = []
    modules = sorted({f.parent for f in files if f.name == 'CMakeLists.txt' and f.parent != root})
    for module in modules:
        sources = [f for f in files if f.suffix.lower() in SOURCE_EXTS and module in f.parents
                   and not any(m != module and module in m.parents and m in f.parents for m in modules)]
        readme = module / 'README.md'
        if not readme.exists():
            problems.append(f'{_rel(module, root)}/: module folder has no README.md')
            continue
        text = readme.read_text(encoding='utf-8')
        for src in sources:
            if src.name not in text:
                problems.append(f'{_rel(readme, root)}: does not mention {_rel(src, module)}')
    return problems


def check_markdown_links(root, files):
    problems = []
    for md in (f for f in files if f.suffix.lower() == '.md'):
        text = INLINE_CODE_RE.sub('', FENCE_RE.sub('', md.read_text(encoding='utf-8')))
        for target in LINK_RE.findall(text):
            if re.match(r'^[a-z][a-z0-9+.-]*:', target, re.I) or target.startswith('#'):
                continue  # URL, mailto: or in-page anchor
            path = unquote(target.split('#', 1)[0].split('?', 1)[0])
            if not path:
                continue
            resolved = (root / path.lstrip('/')) if path.startswith('/') else (md.parent / path)
            if not resolved.exists():
                problems.append(f'{_rel(md, root)}: broken link -> {target}')
    return problems


def check_changelog(root):
    changelog = root / 'CHANGELOG.md'
    if not changelog.exists():
        return ['CHANGELOG.md is missing']
    if not re.search(r'^## \[Unreleased\]', changelog.read_text(encoding='utf-8'), re.M):
        return ['CHANGELOG.md has no "## [Unreleased]" section']
    return []


def check_components(root):
    components = root / 'docs' / 'COMPONENTS.md'
    if not components.exists():
        return ['docs/COMPONENTS.md is missing']
    text = components.read_text(encoding='utf-8')
    problems = []
    for top in COMPONENT_ROOTS:
        base = root / top
        if not base.is_dir():
            continue
        for child in sorted(p for p in base.iterdir() if p.is_dir() and p.name not in SKIP_DIRS):
            if f'{top}/{child.name}' not in text:
                problems.append(f'docs/COMPONENTS.md does not mention {top}/{child.name}')
    return problems


def check_claude_md(root):
    claude = root / 'CLAUDE.md'
    if not (root / 'AGENTS.md').exists():
        return ['AGENTS.md is missing']
    if not claude.exists() or '@AGENTS.md' not in claude.read_text(encoding='utf-8'):
        return ['CLAUDE.md must exist and import @AGENTS.md']
    return []


def check_runtime_record(root):
    """runtime/base.json "packaged" names the d3d9.dll packages/runtime holds and what it was built from:
    the fork's commit, the submodule settings, the clones and every patch file's SHA-256. While runtime/
    differs from that record, the stored DLL is not what runtime/ builds (R3-014)."""
    base_path = root / 'runtime' / 'base.json'
    if not base_path.is_file():
        return []
    base = json.loads(base_path.read_text(encoding='utf-8'))
    record = base.get('packaged') or {}

    def settings(table):  # what builds: everything but the explanations
        return {k: {kk: vv for kk, vv in v.items() if kk != 'why'} for k, v in (table or {}).items()}

    files = {p.relative_to(root / 'runtime').as_posix(): hashlib.sha256(p.read_bytes()).hexdigest()
             for folder in ('patches', 'submodules') for p in sorted((root / 'runtime' / folder).glob('*.patch'))}
    now = {'commit': base.get('commit'), 'submodules': settings(base.get('submodules')), 'clones': settings(base.get('clones')),
           'files': files}
    built = {'commit': record.get('commit'), 'submodules': settings(record.get('submodules')),
             'clones': settings(record.get('clones')), 'files': record.get('files')}
    # Parallel runtime tasks build locally; integration imports their combined DLL once (R20-E).
    # Only explicitly hashed, newly appended patches may wait. Existing inputs remain immutable.
    pending = base.get('pending_patches')
    pending_problems = []
    if pending is not None:
        if (not isinstance(pending, dict) or set(pending) != {'why', 'files'}
                or not isinstance(pending.get('why'), str) or not pending['why'].strip()
                or not isinstance(pending.get('files'), dict) or not pending['files']):
            pending_problems.append('runtime/base.json: pending_patches needs a reason and nonempty files map')
        else:
            last_built = max((name for name in (built['files'] or {}) if name.startswith('patches/')), default='')
            for name, digest in pending['files'].items():
                if (not re.fullmatch(r'patches/[0-9]{4}-[^/]+\.patch', name)
                        or name <= last_built or name in (built['files'] or {})
                        or not isinstance(digest, str) or not re.fullmatch(r'[0-9a-f]{64}', digest)
                        or files.get(name) != digest):
                    pending_problems.append(f'runtime/base.json: invalid or changed pending patch {name}')
                else:
                    del now['files'][name]
    problems = pending_problems + [f'runtime/: the {key} differ from what the stored d3d9.dll was built from (runtime/base.json "packaged"); '
                'run runtime/build_runtime.ps1 to build and store it again' for key in now if now[key] != built[key]]
    index = root / 'packages' / 'runtime' / 'files.json'
    if index.is_file():
        entry = json.loads(index.read_text(encoding='utf-8'))['files'].get('files/d3d9.dll') or {}
        if entry.get('sha256') != record.get('d3d9.dll'):
            problems.append('packages/runtime/files/d3d9.dll is not the d3d9.dll runtime/base.json "packaged" records')
    return problems


def check_package_user_paths(root):
    """packages/ is published twice, with the repository and in the package every player installs: no text
    file there may name a Windows account's folder (rtx_agent's README carried a maintainer's
    C:\\Users\\<account>\\ harness path, review finding 19). Binary files (a NUL byte) and the xz-compressed
    inputs are not text."""
    base = root / 'packages'
    if not base.is_dir():
        return []
    problems = []
    for path in _files(base):
        if path.suffix.lower() == '.xz':
            continue
        data = path.read_bytes()
        if b'\0' in data:
            continue
        text = data.decode('utf-8', errors='replace')
        for match in USER_FOLDER_RE.finditer(text):
            if _names_an_account(match):
                line = text.count('\n', 0, match.start()) + 1
                problems.append(f'{_rel(path, root)}:{line}: names a Windows account folder ({match.group(0)}); '
                                'packages/ is published, write a placeholder or leave the path out')
    return problems


def _names_an_account(match):
    """Whether a USER_FOLDER_RE match names an account: not a placeholder, not one character (C:\\Users\\J\\xFC...
    in a C string), punctuation after it left out (C:\\Users\\Someone).)."""
    account = match.group(1).rstrip(').,;:]}\'"').lower()
    return len(account) > 1 and account not in PLACEHOLDER_ACCOUNTS


def _text(path):
    """A file's text, or None for a binary file (a NUL byte) or an xz-compressed input."""
    if path.suffix.lower() == '.xz':
        return None
    data = path.read_bytes()
    return None if b'\0' in data else data.decode('utf-8', errors='replace')


def check_user_paths(root, files):
    """No text file outside packages/ (which check_package_user_paths reads) names a Windows account's folder:
    the repository is public (AGENTS.md rule 10)."""
    problems = []
    for path in files:
        rel = _rel(path, root)
        text = None if rel in ACCOUNT_RULE_TESTS else _text(path)
        if text is None:
            continue
        for match in USER_FOLDER_RE.finditer(text):
            if _names_an_account(match):
                line = text.count('\n', 0, match.start()) + 1
                problems.append(f'{rel}:{line}: names a Windows account folder ({match.group(0)}); the repository '
                                'is public, write %USERPROFILE%, ~ or a placeholder')
    return problems


def _account_names():
    """The Windows account this check runs under, as it appears in text: its user name, its profile folder and
    that folder's 8.3 short name, lower case. Placeholders, common names and names under five characters are
    left out: they would match ordinary words."""
    home = Path.home()
    names = {os.environ.get('USERNAME', ''), home.name}
    try:
        import ctypes
        buffer = ctypes.create_unicode_buffer(32768)
        if ctypes.windll.kernel32.GetShortPathNameW(str(home), buffer, len(buffer)):
            names.add(Path(buffer.value).name)
    except (AttributeError, OSError):
        pass  # not Windows
    return {n.lower() for n in names
            if len(n) >= 5 and n.lower() not in PLACEHOLDER_ACCOUNTS and n.lower() not in COMMON_ACCOUNTS}


def check_account_names(root, files):
    """No text file, packages/ included, names the account this check runs under: the repository is public
    (AGENTS.md rule 10). The problem names the file and line, not the account."""
    names = _account_names()
    if not names:
        return []
    pattern = re.compile('|'.join(r'(?<![a-z0-9])' + re.escape(name) + r'(?![a-z0-9])' for name in sorted(names)),
                         re.I)
    packages = root / 'packages'
    problems = []
    for path in list(files) + (list(_files(packages)) if packages.is_dir() else []):
        rel = _rel(path, root)
        text = None if rel in ACCOUNT_RULE_TESTS else _text(path)
        if text is None:
            continue
        for match in pattern.finditer(text):
            line = text.count('\n', 0, match.start()) + 1
            problems.append(f'{rel}:{line}: names the Windows account this check runs under; the repository is '
                            'public, write %USERPROFILE%, ~ or <user>')
    return problems


def check_repository_builds(root):
    """tools/ci/pins.json "repository_builds" "packaged" says what each module this repository compiles and
    stores in packages/ was built from: the SHA-256 of the stored file and of each of its sources. While a
    source differs, the stored module is not what this repository builds (R20-Q: the client module built
    in R4 shipped in every local package until R20, after R6 had changed the configuration it reads)."""
    return repo_builds.problems(root)


def check(root):
    root = Path(root).resolve()
    files = list(_files(root))
    return (check_script_docs(root, files) + check_module_readmes(root, files) + check_markdown_links(root, files)
            + check_changelog(root) + check_components(root) + check_claude_md(root) + check_runtime_record(root)
            + check_repository_builds(root) + check_package_user_paths(root) + check_user_paths(root, files)
            + check_account_names(root, files))


def main(argv=None):
    ap = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    ap.add_argument('--root', default=Path(__file__).resolve().parent.parent, help='repo root (default: this repo)')
    a = ap.parse_args(argv)
    problems = check(a.root)
    for problem in problems:
        print(problem)
    print(f'{len(problems)} problem(s)' if problems else 'repo conventions OK')
    return 1 if problems else 0


if __name__ == '__main__':
    sys.exit(main())
