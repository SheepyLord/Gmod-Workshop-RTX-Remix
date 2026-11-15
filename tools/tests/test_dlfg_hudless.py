"""DLSS frame generation keeps the UI in place (runtime patch 0094, ADR 0223): it is given the frame before its UI.

Compiles and runs the handoff's unit test from the committed patch (MSVC, as the runtime builds it), and checks
that the patch fills the HUD-less copy at injection, blits it beside the frame generation back buffer with the back
buffer's own blit, and passes it to NGX only for a frame that filled it."""
import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[2]
PATCHES = sorted((REPO / 'runtime' / 'patches').glob('0094-*.patch'))
VS = Path(os.environ.get('ProgramFiles(x86)', 'C:/Program Files (x86)')) / 'Microsoft Visual Studio/2022/BuildTools'
HANDOFF = 'src/dxvk/rtx_render/rtx_dlfg_hudless.h'
TEST = 'tests/rtx/unit/test_dlfg_hudless.cpp'


def patch_text() -> str:
    if len(PATCHES) != 1:
        raise AssertionError(f'expected one runtime patch 0094, found {[p.name for p in PATCHES]}')
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
& cl.exe /nologo /EHsc /std:c++17 /O2 /W4 /WX /UNDEBUG /utf-8 tests/rtx/unit/test_dlfg_hudless.cpp /Fehudless.exe /Fohudless.obj
if ($LASTEXITCODE) { exit $LASTEXITCODE }
& ./hudless.exe
exit $LASTEXITCODE
'''


class HudlessTests(unittest.TestCase):
    @unittest.skipUnless(os.name == 'nt' and VS.is_dir(), 'MSVC x64 Build Tools unavailable')
    def test_the_handoffs_unit_test_from_the_patch(self):
        patch = patch_text()
        scratch = REPO / 'out' / 'tmp'
        scratch.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(prefix='dlfg-hudless-', dir=scratch) as directory:
            root = Path(directory)
            for path in (HANDOFF, TEST):
                file = root / path
                file.parent.mkdir(parents=True, exist_ok=True)
                file.write_text(postimage(patch, path), encoding='utf-8')
            script = root / 'run.ps1'
            script.write_text(SCRIPT, encoding='utf-8')
            result = subprocess.run(['powershell', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', str(script),
                                     '-Repo', str(REPO), '-Scratch', str(root)],
                                    capture_output=True, text=True, timeout=300)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertRegex(result.stdout, r'PASS dlfg hudless: \d+ checks')

    def test_the_handoff_forgets_a_replaced_copy(self):
        handoff = postimage(patch_text(), HANDOFF)
        # A frame counts only for the copy it filled; a new or dropped copy forgets every frame.
        self.assertIn('if (frameId == kNoFrame || generation != m_generation || m_source == nullptr)', handoff)
        self.assertEqual(handoff.count('++m_generation;'), 2)
        self.assertEqual(handoff.count('forget();'), 3)  # the constructor, setSource and dropSource
        self.assertIn('m_frames[frameId % kCapacity].load(std::memory_order_acquire) == frameId', handoff)

    def test_injection_fills_the_copy_after_the_game_target(self):
        patch = patch_text()
        context = added_lines(patch, 'src/dxvk/rtx_render/rtx_context.cpp')
        self.assertIn('if (isDLFGEnabled()) {', context)
        for condition in ('hudless->info().extent == targetImage->info().extent',
                          'hudless->info().format == targetImage->info().format',
                          'hudless->info().sampleCount == VK_SAMPLE_COUNT_1_BIT'):
            self.assertIn(condition, context)
        self.assertIn('blitImageHelper(this, srcImage, hudless, VkFilter::VK_FILTER_NEAREST);', context)
        self.assertIn('hudlessHandoff.mark(m_device->getCurrentFrameId(), hudlessGeneration);', context)
        # The same image, the same blit as the game target's, and after it: no UI has been drawn yet.
        hunk = file_block(patch, 'src/dxvk/rtx_render/rtx_context.cpp')
        self.assertLess(hunk.index('blitImageHelper(this, srcImage, targetImage, VkFilter::VK_FILTER_NEAREST);'),
                        hunk.index('blitImageHelper(this, srcImage, hudless, VkFilter::VK_FILTER_NEAREST);'))

    def test_the_present_blits_the_copy_beside_the_back_buffer(self):
        swapchain = added_lines(patch_text(), 'src/d3d9/d3d9_swapchain.cpp')
        self.assertIn('UpdateDlfgHudless(swapImageView);', swapchain)
        # The back buffer's create info and sampled view, so a pixel without UI comes out identical.
        self.assertIn('DxvkImageCreateInfo info = backBuffer->info();', swapchain)
        self.assertIn('m_device->createImageView(m_dlfgHudless, backBufferView->info());', swapchain)
        self.assertIn('m_blitter->presentImage(m_context.ptr(), hudless, dstRect, m_dlfgHudlessView, srcRect);', swapchain)
        self.assertIn('m_dlfgPresenter->getHudlessView(imageIndex)', swapchain)
        self.assertIn('metaDLFG().hudless().dropSource(m_dlfgHudless);', swapchain)  # the destructor

    def test_frame_generation_gets_it_only_for_a_filled_frame(self):
        patch = patch_text()
        dlfg = added_lines(patch, 'src/dxvk/rtx_render/rtx_dlfg.cpp')
        self.assertIn('if (dlfg.hudless().has(present.frameInterpolation.frameId) && present.acquiredImageIndex < m_hudlessViews.size()) {', dlfg)
        self.assertIn('interpolateFrame(commandList, swapchainImage, present, fgInterpolateIndex, hudless);', dlfg)
        # Its barriers mirror the back buffer's: present layout to shader read for NGX, and back for the next blit.
        self.assertIn('VK_IMAGE_LAYOUT_PRESENT_SRC_KHR,\n                                VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL);', dlfg)
        self.assertIn('VK_IMAGE_LAYOUT_SHADER_READ_ONLY_OPTIMAL,\n                                  VK_IMAGE_LAYOUT_PRESENT_SRC_KHR);', dlfg)
        self.assertIn('DxvkDLFGImageBarrierSet<5> barriers;', dlfg)  # room for the fourth pre-evaluation barrier
        self.assertIn('"DLFG HUD-less"', dlfg)
        ngx = added_lines(patch, 'src/dxvk/rtx_render/rtx_ngx_wrapper.cpp')
        self.assertIn('ngxHudless = ViewToResourceVK(hudlessColorBuffer, false);', ngx)
        self.assertIn('evalParams.pHudless = &ngxHudless;', ngx)
        self.assertIn("'rtx_render/rtx_dlfg_hudless.h',", added_lines(patch, 'src/dxvk/meson.build'))
        self.assertIn("executable('test_dlfg_hudless'", added_lines(patch, 'tests/rtx/unit/meson.build'))


if __name__ == '__main__':
    unittest.main()
