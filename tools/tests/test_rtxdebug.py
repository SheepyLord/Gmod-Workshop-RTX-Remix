"""The RTX debug module's source copy (packages/fixes/licenses/rtxdebug): the checkout, its four patches, its provenance
record and the module stored in the fixes part agree, and the module's own regressions pass. Patch 0004 (ADR 0237)
routes Remix option writes: behind the developer gate through the Remix API, otherwise to RemixConfig, whose list
(ADR 0234) refuses debug views to every other Lua."""
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[2]
FOLDER = REPO / 'packages/fixes/licenses/rtxdebug'
CHECKOUT = FOLDER / 'checkout'
RECORD = json.loads((FOLDER / 'provenance.json').read_text(encoding='utf-8'))
PINS = json.loads((REPO / 'tools/ci/pins.json').read_text(encoding='utf-8'))['rtxdebug']
FIXES_INDEX = json.loads((REPO / 'packages/fixes/files.json').read_text(encoding='utf-8'))['files']
STORED = 'modules/gmcl_rtxdebug_win64.dll'
# The checkout keeps the module's .gitattributes under another name (Source.md).
ALIASES = {upstream: stored for stored, upstream in RECORD['checkout_path_aliases'].items()}
INDEX_LINE = re.compile(r'^index ([0-9a-f]{7,40})\.\.([0-9a-f]{7,40})(?: \d+)?$')
VS = Path(os.environ.get('ProgramFiles(x86)', 'C:/Program Files (x86)')) / 'Microsoft Visual Studio/2022/BuildTools'
SCRIPT = '''param([string]$Repo, [string]$Checkout, [string]$Scratch)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $Repo 'tools/lib/VsDevEnv.psm1') -Force
Enter-VsDevEnv | Out-Null
$env:TEMP = $Scratch
$env:TMP = $Scratch
Set-Location -LiteralPath $Scratch
$failed = 0
foreach ($name in 'render_policy_test', 'session_policy_test') {
    & cl.exe /nologo /EHsc /std:c++17 /W4 /WX /UNDEBUG /utf-8 (Join-Path $Checkout "tests/$name.cpp") "/Fe$name.exe" "/Fo$name.obj"
    if ($LASTEXITCODE -ne 0) { "FAIL compile $name"; $failed++; continue }
    & (Join-Path $Scratch "$name.exe")
    if ($LASTEXITCODE -ne 0) { "FAIL run $name"; $failed++ }
}
exit $failed
'''


def sha256(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


def blob_id(path):
    """Git's object id of the file's bytes (the checkout holds the committed bytes)."""
    data = path.read_bytes()
    return hashlib.sha1(b'blob %d\0' % len(data) + data).hexdigest()


def text(path):
    return path.read_bytes().decode('utf-8')


def patches():
    return [FOLDER / entry['file'] for entry in RECORD['patches']]


def checkout_file(name):
    return CHECKOUT / ALIASES.get(name, name)


class SourceCopy(unittest.TestCase):
    def test_the_record_lists_every_checkout_file(self):
        files = {p.relative_to(CHECKOUT).as_posix() for p in CHECKOUT.rglob('*') if p.is_file()}
        self.assertEqual(files, set(RECORD['complete_checkout']))
        for name, entry in RECORD['complete_checkout'].items():
            path = CHECKOUT / name
            self.assertEqual((path.stat().st_size, sha256(path)), (entry['size'], entry['sha256']), name)

    def test_the_patches_are_one_chain_from_the_base_to_the_pinned_commit(self):
        files = sorted(p.name for p in FOLDER.glob('*.patch'))
        self.assertEqual(files, [entry['file'] for entry in RECORD['patches']], 'every patch recorded, in order')
        commit = RECORD['base_commit']
        for number, entry in enumerate(RECORD['patches'], 1):
            path = FOLDER / entry['file']
            self.assertTrue(entry['file'].startswith(f'{number:04d}-'), entry['file'])
            self.assertEqual((path.stat().st_size, sha256(path)), (entry['size'], entry['sha256']), entry['file'])
            self.assertEqual(entry['applies_to'], commit, entry['file'])
            self.assertTrue(text(path).startswith(f"From {entry['result']} "), entry['file'])
            commit = entry['result']
        self.assertEqual(RECORD['source_commit'], commit)
        self.assertEqual(PINS['commit'], commit, 'tools/ci/pins.json builds the recorded source')
        self.assertEqual(PINS['source'], CHECKOUT.relative_to(REPO).as_posix())

    def test_each_file_the_patches_touch_is_their_last_post_image(self):
        """Each patch's index line for a file starts where the one before left it, and the checkout holds the last
        patch's result: an edit of a patched file that no patch carries fails here."""
        last = {}
        for path in patches():
            current = None
            for line in text(path).splitlines():
                if line.startswith('diff --git a/'):
                    current = line.split(' b/', 1)[1]
                elif current and INDEX_LINE.match(line):
                    before, after = INDEX_LINE.match(line).groups()
                    if current in last:
                        self.assertTrue(last[current].startswith(before) or before.startswith(last[current]),
                                        f'{path.name}: {current} does not start where the patch before left it')
                    last[current] = after
                    current = None
        self.assertIn('source/remix/remix_debug.cpp', last)
        for name, after in last.items():
            if set(after) == {'0'}:
                self.assertFalse(checkout_file(name).exists(), f'{name} was deleted')
                continue
            self.assertTrue(blob_id(checkout_file(name)).startswith(after), f'{name} is not the patches\' result')

    def test_the_stored_module_is_the_recorded_build(self):
        built, stored = RECORD['built_artifact'], FIXES_INDEX[STORED]
        self.assertEqual((built['size'], built['sha256']), (stored['size'], stored['sha256']),
                         'packages/fixes stores the module provenance.json records')
        module = text(CHECKOUT / 'source/module.cpp')
        self.assertIn(f'constexpr const char* kVersion = "{built["version"]}";', module)
        self.assertIn(f'RTXDebug {built["version"]} source', text(FOLDER / 'Source.md'))


class RemixWriteRoute(unittest.TestCase):
    """ADR 0237: the module wires the route its regression tests."""

    def test_writes_follow_the_route_and_restores_the_ledger(self):
        remix = text(CHECKOUT / 'source/remix/remix_debug.cpp')
        self.assertIn('Policy::RouteConfig(CanMutate(), lua == Lua() && CanConfigureRendering(), key)', remix)
        self.assertIn('const bool throughApi = route == Policy::ConfigRoute::RemixApi;', remix)
        self.assertIn('existing->throughApi = Policy::RestoreThroughApi(existing->throughApi, route);', remix)
        self.assertEqual(remix.count('Apply(LUA, it->key, it->restoreValue, it->throughApi, error)'), 1, 'RestoreConfig')
        self.assertEqual(remix.count('Apply(lua, it->key, it->restoreValue, it->throughApi, error)'), 2,
                         'RestoreAll and Shutdown')
        # RemixConfig.SetConfigVariable is the only Lua route; the module adds no Lua-visible way around it.
        self.assertEqual(remix.count('"RemixConfig", "SetConfigVariable"'), 1)

    def test_the_api_is_only_asked_for_an_interface_and_set_config_variable(self):
        remix = text(CHECKOUT / 'source/remix/remix_debug.cpp')
        self.assertIn('GetProcAddress(runtime, "remixapi_InitializeLibrary")', remix)
        self.assertIn('REMIXAPI_VERSION_MAKE(REMIXAPI_VERSION_MAJOR, REMIXAPI_VERSION_MINOR, REMIXAPI_VERSION_PATCH)', remix)
        # The headers RTXFixesBinary and RTX Water are built with: the runtime keeps the latest initialize's version.
        self.assertIn('REMIXAPI_VERSION_MAJOR == 0 && REMIXAPI_VERSION_MINOR == 1000\n    && REMIXAPI_VERSION_PATCH == 1', remix)
        calls = set(re.findall(r'g_api\.(\w+)', remix))
        self.assertEqual(calls, {'SetConfigVariable'}, 'never Startup, Shutdown or anything else')

    def test_the_gate_reads_nothing_from_lua(self):
        session = text(CHECKOUT / 'source/session_policy.h')
        self.assertIn('return mainThread && !closing && insecureLaunch && localSinglePlayer && cheats;', session)
        module = text(CHECKOUT / 'source/module.cpp')
        self.assertIn('return Policy::IsLocalSinglePlayer(Engine::ReadSessionFacts());', module)
        self.assertIn('commandLine->FindParm("-insecure")', module)


@unittest.skipUnless(os.name == 'nt' and VS.is_dir(), 'MSVC x64 Build Tools unavailable')
class PolicyRegressions(unittest.TestCase):
    """The module's two standalone regressions, compiled with /W4 /WX and run."""

    @classmethod
    def setUpClass(cls):
        scratch = REPO / 'out/tmp'
        scratch.mkdir(parents=True, exist_ok=True)
        cls.directory = tempfile.TemporaryDirectory(prefix='rtxdebug-', dir=scratch)
        root = Path(cls.directory.name)
        tree = root / 'tree'
        for part in ('source', 'tests'):
            shutil.copytree(CHECKOUT / part, tree / part)
        script = root / 'run.ps1'
        script.write_text(SCRIPT, encoding='utf-8')
        cls.result = subprocess.run(['powershell', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', str(script),
                                     '-Repo', str(REPO), '-Checkout', str(tree), '-Scratch', str(root)],
                                    capture_output=True, text=True, timeout=600)

    @classmethod
    def tearDownClass(cls):
        cls.directory.cleanup()

    def test_the_regressions_pass(self):
        output = self.result.stdout + self.result.stderr
        self.assertEqual(self.result.returncode, 0, output)
        self.assertIn('Rendering policy tests passed', self.result.stdout)
        self.assertIn('Session policy tests passed', self.result.stdout)


if __name__ == '__main__':
    unittest.main()
