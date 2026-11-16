"""Source eyes under Remix (GitHub issue 1, ADR 0220): the fixes' thirteenth native patch (eye-texgen) asserts the eye
shaders' camera-space TexGen at the eye's draw, its complete files are the patch applied, its SDK-free regression
(eye_texgen_state_test.cpp) passes, and the package's Remix defaults turn the runtime's eye shading on."""
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest

from test_endfield_maps import REPO, SKINNING, apply, text
from test_queued_draws import added, body

FOLDER = SKINNING / 'eye-texgen'
PATCH = FOLDER / 'eye-texgen.patch'
HOOKS = 'source/HardwareSkinningHooks.cpp'
STATE = 'source/eye_texgen_state.h'
TEST = 'tests/eye_texgen_state_test.cpp'
LAYER = REPO / 'packages/runtime/layers/classic_remix_defaults.conf'
VS = Path(os.environ.get('ProgramFiles(x86)', 'C:/Program Files (x86)')) / 'Microsoft Visual Studio/2022/BuildTools'
SCRIPT = '''param([string]$Repo, [string]$Source, [string]$Scratch)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $Repo 'tools/lib/VsDevEnv.psm1') -Force
Enter-VsDevEnv | Out-Null
$env:TEMP = $Scratch
$env:TMP = $Scratch
Set-Location -LiteralPath $Scratch
& cl.exe /nologo /EHsc /std:c++17 /W4 /WX /UNDEBUG /DWIN32_LEAN_AND_MEAN /DNOMINMAX /utf-8 $Source /Feeye_texgen_state_test.exe /Foeye_texgen_state_test.obj
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& (Join-Path $Scratch 'eye_texgen_state_test.exe')
exit $LASTEXITCODE
'''


class EyeTexGenTests(unittest.TestCase):
    def test_complete_files_are_the_patch_applied(self):
        """HardwareSkinningHooks.cpp is queued-draws' copy (no patch after it changes the file) with this patch
        applied; the header and the regression are its added lines. pins.json builds the module with it right after
        player-categories."""
        patch = PATCH.read_text(encoding='utf-8')
        self.assertEqual(re.findall(r'^diff --git a/(\S+) b/\1$', patch, re.M), [HOOKS, STATE, TEST])
        self.assertEqual(apply(patch, HOOKS, text(SKINNING / 'queued-draws' / HOOKS)), text(FOLDER / HOOKS))
        for path in (STATE, TEST):
            self.assertEqual(added(patch, path), text(FOLDER / path).rstrip('\n').split('\n'), path)
        patches = json.loads((REPO / 'tools/ci/pins.json').read_text(encoding='utf-8'))['fixes']['patches']
        player = 'packages/fixes/licenses/oversized-skinning/player-categories/player-categories.patch'
        self.assertEqual(patches.index(PATCH.relative_to(REPO).as_posix()), patches.index(player) + 1)

    def test_the_draw_writes_the_eye_request_again(self):
        """The request is kept per thread, set before RTX_SetEyeTexGenState's device check, and written again at
        the top of the draw hook, before anything else the hook does."""
        hooks = text(FOLDER / HOOKS)
        self.assertIn('static thread_local EyeTexGen::Request g_eyeTexGenRequest;', hooks)
        helper = body(hooks, 'extern "C" __declspec(dllexport) void RTX_SetEyeTexGenState(int enable)\n{')
        self.assertLess(helper.index('g_eyeTexGenRequest.Set(enable != 0);'), helper.index('if (!g_pD3DDevice) return;'))
        draw = body(hooks, 'static HRESULT STDMETHODCALLTYPE Hook_DrawIndexedPrimitive(\n'
                           '    IDirect3DDevice9* pDevice,\n')
        apply_at = draw.index('g_eyeTexGenRequest.ApplyBeforeDraw(eyeDevice);')
        self.assertLess(apply_at, draw.index('if (g_PerStripState.active) {'))
        self.assertLess(apply_at, draw.index('g_OriginalDIP('))
        state = text(FOLDER / STATE)
        self.assertIn('device.SetTextureStageState(kIrisStage, kTexCoordIndex, kCameraSpacePosition);', state)
        self.assertNotIn('#include <', state)

    def test_the_package_turns_remix_eye_shading_on(self):
        """The runtime's own default leaves rtx.eye.enable off; the package's defaults layer turns it on."""
        lines = LAYER.read_text(encoding='utf-8').splitlines()
        self.assertIn('rtx.eye.enable = True', lines)

    @unittest.skipUnless(os.name == 'nt' and VS.is_dir(), 'MSVC x64 Build Tools unavailable')
    def test_the_regression_passes(self):
        scratch = REPO / 'out/tmp'
        scratch.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(prefix='eye-texgen-', dir=scratch) as directory:
            root = Path(directory)
            script = root / 'run.ps1'
            script.write_text(SCRIPT, encoding='utf-8')
            result = subprocess.run(['powershell', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', str(script),
                                     '-Repo', str(REPO), '-Source', str(FOLDER / TEST), '-Scratch', str(root)],
                                    capture_output=True, text=True, timeout=180)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn('PASS eye texgen:', result.stdout)


if __name__ == '__main__':
    unittest.main()
