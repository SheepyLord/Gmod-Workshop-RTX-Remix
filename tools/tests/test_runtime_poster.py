"""GMod's poster command under RTX (runtime patch 0095, ADR 0226, GitHub issue 3): the runtime renders it in tiles.

Compiles and runs the poster's unit test from the committed patch (MSVC, as the runtime builds it), checks that the
engine guard's copy of the API header is the patch's, and that the patch narrows the cameras, resets each tile's
history, keeps the tile's picture before its UI, holds exposure, the lens effects and the clock, fits the sky's
screen-aligned passes to the tile and exports the API."""
import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[2]
PATCHES = sorted((REPO / 'runtime' / 'patches').glob('0095-*.patch'))
VS = Path(os.environ.get('ProgramFiles(x86)', 'C:/Program Files (x86)')) / 'Microsoft Visual Studio/2022/BuildTools'
MATH = 'src/dxvk/rtx_render/rtx_poster_math.h'
API = 'src/dxvk/rtx_render/rtx_poster_api.h'
TEST = 'tests/rtx/unit/test_poster_math.cpp'


def patch_text() -> str:
    if len(PATCHES) != 1:
        raise AssertionError(f'expected one runtime patch 0095, found {[p.name for p in PATCHES]}')
    return PATCHES[0].read_text(encoding='utf-8')


def file_block(patch: str, path: str) -> str:
    return patch.split(f'diff --git a/{path} b/{path}\n', 1)[1].split('\ndiff --git ', 1)[0]


def postimage(patch: str, path: str) -> str:
    """A file the patch creates, whole (one hunk from line 1 with every line added)."""
    block = file_block(patch, path)
    if 'new file mode' not in block.split('@@', 1)[0]:
        raise AssertionError(f'{path}: not a new file in the patch')
    header, body = block.split('@@', 2)[1:]
    match = re.search(r'\+1,(\d+)', header)
    count = int(match[1]) if match else 1
    lines = [line[1:] for line in body.splitlines()[1:] if line.startswith('+')]
    if len(lines) != count:
        raise AssertionError(f'{path}: hunk length mismatch ({len(lines)} != {count})')
    return '\n'.join(lines) + '\n'


def added_lines(patch: str, path: str) -> str:
    return '\n'.join(line[1:].rstrip('\r') for line in file_block(patch, path).splitlines()
                     if line.startswith('+') and not line.startswith('+++'))


SCRIPT = '''param([string]$Repo, [string]$Scratch)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $Repo 'tools/lib/VsDevEnv.psm1') -Force
Enter-VsDevEnv | Out-Null
$env:TEMP = $env:TMP = $Scratch
Set-Location -LiteralPath $Scratch
& cl.exe /nologo /EHsc /std:c++17 /O2 /W4 /WX /UNDEBUG /utf-8 tests/rtx/unit/test_poster_math.cpp /Feposter.exe /Foposter.obj
if ($LASTEXITCODE) { exit $LASTEXITCODE }
& ./poster.exe
exit $LASTEXITCODE
'''


class PosterTests(unittest.TestCase):
    @unittest.skipUnless(os.name == 'nt' and VS.is_dir(), 'MSVC x64 Build Tools unavailable')
    def test_the_posters_unit_test_from_the_patch(self):
        patch = patch_text()
        scratch = REPO / 'out' / 'tmp'
        scratch.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(prefix='poster-', dir=scratch) as directory:
            root = Path(directory)
            for path in (MATH, TEST):
                file = root / path
                file.parent.mkdir(parents=True, exist_ok=True)
                file.write_text(postimage(patch, path), encoding='utf-8')
            script = root / 'run.ps1'
            script.write_text(SCRIPT, encoding='utf-8')
            result = subprocess.run(['powershell', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', str(script),
                                     '-Repo', str(REPO), '-Scratch', str(root)],
                                    capture_output=True, text=True, timeout=300)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertRegex(result.stdout, r'PASS poster math: \d+ checks')

    def test_the_engine_guard_calls_the_api_the_patch_exports(self):
        patch = patch_text()
        copy = (REPO / 'engine_guard' / 'rtxposter_api.h').read_text(encoding='utf-8').replace('\r\n', '\n')
        self.assertEqual(copy, postimage(patch, API))
        exports = added_lines(patch, 'src/d3d9/d3d9.def')
        api = added_lines(patch, 'src/dxvk/rtx_render/rtx_remix_api.cpp')
        for name in ('rtxposter_GetApiVersion', 'rtxposter_Start', 'rtxposter_Cancel', 'rtxposter_GetStatus'):
            self.assertIn(name, exports)
            self.assertIn(f'REMIXAPI int REMIXAPI_CALL {name}(' if name not in ('rtxposter_GetApiVersion', 'rtxposter_Cancel')
                          else name, api)
        # GMod never registers its device with the Remix API: the exports reach the poster through its own instance,
        # not s_dxvkDevice (the first PoC run answered RTXPOSTER_E_NO_DEVICE that way).
        self.assertIn('return dxvk::poster::apiStart(request);', api)
        poster_exports = api.split('rtxposter_GetApiVersion', 1)[1]
        self.assertNotIn('s_dxvkDevice ?', poster_exports)
        self.assertNotIn('s_dxvkDevice->', poster_exports)
        poster = postimage(patch, 'src/dxvk/rtx_render/rtx_poster.cpp')
        self.assertIn('g_instance = this;', poster)
        self.assertEqual(poster.count('if (g_instance == this) { g_instance = nullptr; }'), 2)  # teardown and destructor

    def test_the_cameras_look_through_the_tiles_window(self):
        patch = patch_text()
        cameras = added_lines(patch, 'src/dxvk/rtx_render/rtx_camera_manager.cpp')
        self.assertIn('cameraType == CameraType::Main || cameraType == CameraType::ViewModel || cameraType == CameraType::Sky',
                      cameras)
        self.assertIn('metaPoster().narrow(viewToProjection);', cameras)
        # The narrowed matrix goes to the camera's update, which keeps the game's own field of view and aspect (the
        # decomposition of the game's matrix, unchanged): the culling frustum and the view model's detection keep the
        # whole view.
        hunk = file_block(patch, 'src/dxvk/rtx_render/rtx_camera_manager.cpp')
        self.assertLess(hunk.index('metaPoster().narrow(viewToProjection);'), hunk.index('isCameraCut = camera.update('))
        self.assertIn("Their field of view and aspect stay the game's", cameras)

    def test_each_tile_starts_afresh_and_keeps_its_picture_before_its_ui(self):
        context = file_block(patch_text(), 'src/dxvk/rtx_render/rtx_context.cpp')
        self.assertIn('+        if (poster.beginFrame(*this, outputExtent)) { m_resetHistory = true; }', context)
        self.assertIn('+        poster.endFrame(*this, srcImage);', context)
        self.assertLess(context.index('Rc<DxvkImage> srcImage = traceView(-1, linearViewZ);'),
                        context.index('poster.endFrame(*this, srcImage);'))
        # One exposure, no lens effects or motion blur, textures sampled for the poster's pixel.
        self.assertIn('dispatchToneMapping(rtOutput, !dlssNrEnabled && eye != 1 && !poster.holdsEffects());', context)
        self.assertEqual(context.count('if (m_common->metaPoster().holdsEffects()) {'), 2)
        self.assertIn('constants.screenSpacePixelSpreadHalfAngle /= m_common->metaPoster().pixelScale();', context)
        # The sky matte: its viewport stretched to the tile's window, its jitter kept at a pixel.
        self.assertIn('viewport.width = static_cast<float>(skyMatteExt.width) * posterScaleX;', context)
        self.assertIn('modified.jitterX = clipSpaceJitter.x / posterScaleX;', context)
        self.assertIn('modified.Projection[2][0] += jitter.x / posterScaleX;', context)

    def test_the_sky_and_the_clock_hold_for_the_tiles(self):
        patch = patch_text()
        atmosphere = added_lines(patch, 'src/dxvk/rtx_render/rtx_atmosphere.cpp')
        self.assertIn('poster::windowBasis(cf, cr, cu, tanHalfFovX, tanHalfFovY, posterWindow);', atmosphere)
        self.assertIn('m_apCameraForward = Vector3(float(aerial.forward[0])', atmosphere)
        self.assertIn('m_skyPixelAngle /= ctx.getCommonObjects()->metaPoster().pixelScale();', atmosphere)
        poster = postimage(patch, 'src/dxvk/rtx_render/rtx_poster.cpp')
        self.assertIn('GlobalTime::get().setAdvanceTime(false);', poster)
        self.assertIn('GlobalTime::get().setAdvanceTime(RtxOptions::advanceTime());', poster)
        # Written beside as .part and renamed; the writer holds the job, never the device's objects.
        self.assertIn('const std::wstring part = job->path + L".part";', poster)
        self.assertIn('std::thread(writePoster, job).detach();', poster)
        png = postimage(patch, 'src/dxvk/rtx_render/rtx_poster_png.cpp')
        self.assertIn('LoadLibraryW(L"ole32.dll")', png)  # nothing new linked into d3d9.dll
        self.assertIn("'rtx_render/rtx_poster.cpp',", added_lines(patch, 'src/dxvk/meson.build'))
        self.assertIn("executable('test_poster_math'", added_lines(patch, 'tests/rtx/unit/meson.build'))


if __name__ == '__main__':
    unittest.main()
