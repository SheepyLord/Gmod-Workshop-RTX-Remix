"""Queued draws (ADR 0192): the fixes' tenth patch's complete files are the patch applied, the shipped studio render
hooks never read a queued draw's renderable, and the SDK-free regression (studio_draw_policy_test.cpp) passes."""
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest

from test_endfield_maps import REPO, SKINNING, apply, text

FOLDER = SKINNING / 'queued-draws'
PATCH = FOLDER / 'queued-draws.patch'
HOOKS = 'source/HardwareSkinningHooks.cpp'
PROPS = 'source/prop_fixes.cpp'
POLICY = 'source/studio_draw_policy.h'
TEST = 'tests/studio_draw_policy_test.cpp'
VS = Path(os.environ.get('ProgramFiles(x86)', 'C:/Program Files (x86)')) / 'Microsoft Visual Studio/2022/BuildTools'
SCRIPT = '''param([string]$Repo, [string]$Source, [string]$Scratch)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $Repo 'tools/lib/VsDevEnv.psm1') -Force
Enter-VsDevEnv | Out-Null
$env:TEMP = $Scratch
$env:TMP = $Scratch
Set-Location -LiteralPath $Scratch
& cl.exe /nologo /EHsc /std:c++17 /W4 /WX /UNDEBUG /utf-8 $Source /Festudio_draw_policy_test.exe /Fostudio_draw_policy_test.obj
if ($LASTEXITCODE -ne 0) { exit $LASTEXITCODE }
& (Join-Path $Scratch 'studio_draw_policy_test.exe')
exit $LASTEXITCODE
'''


def blocks(patch, path):
    """One file's hunks: (new start, old-side lines, new-side lines)."""
    block = patch.split(f'diff --git a/{path} b/{path}\n', 1)[1].split('\ndiff --git ', 1)[0]
    result = []
    for hunk in re.finditer(r'^@@ -\d+(?:,\d+)? \+(\d+)(?:,\d+)? @@[^\n]*\n((?:[ +\\-][^\n]*(?:\n|$))*)', block, re.M):
        old, new = [], []
        for line in hunk[2].splitlines():
            tag, rest = line[:1], line[1:]
            if tag in ' -':
                old.append(rest)
            if tag in ' +':
                new.append(rest)
        result.append((int(hunk[1]) - 1, old, new))
    return result


def added(patch, path):
    """A new file's lines, from its diff."""
    (_, old, new), = blocks(patch, path)
    assert not old, path
    return new


def body(source, signature):
    """The text of one function: from its signature to the first line that is a lone closing brace."""
    return source.split(signature, 1)[1].split('\n}\n', 1)[0]


class QueuedDrawsTests(unittest.TestCase):
    def test_complete_files_are_the_patch_applied(self):
        """The folder's files are the patch applied: HardwareSkinningHooks.cpp to backrooms' copy (unchanged by the
        patches between), prop_fixes.cpp (no earlier copy: the base's) on the patch's new side at every hunk, the
        two new files line for line; pins.json builds the module with it, last."""
        patch = PATCH.read_text(encoding='utf-8')
        self.assertEqual(re.findall(r'^diff --git a/(\S+) b/\1$', patch, re.M), [HOOKS, PROPS, POLICY, TEST])
        self.assertEqual(apply(patch, HOOKS, text(SKINNING / 'backrooms' / HOOKS)), text(FOLDER / HOOKS))
        props = text(FOLDER / PROPS).split('\n')
        for start, _, new in blocks(patch, PROPS):
            self.assertEqual(props[start:start + len(new)], new, f'{PROPS} at line {start + 1}')
        for path in (POLICY, TEST):
            self.assertEqual(added(patch, path), text(FOLDER / path).rstrip('\n').split('\n'), path)
        pins = json.loads((REPO / 'tools/ci/pins.json').read_text(encoding='utf-8'))['fixes']
        self.assertEqual(pins['patches'][-1], PATCH.relative_to(REPO).as_posix())

    def test_the_lighting_hook_never_reads_the_renderable(self):
        """R_StudioSetupSkinAndLighting takes the bone count from studiorender's state (its this) and hands the
        renderable only to the trampoline and to BoneCount, which compares it with null; the lookup that called
        GetModel() through the renderable's vtable is gone."""
        source = text(FOLDER / PROPS)
        for gone in ('GetBoneCountForRenderable', 'vtbl[9]', 'GetModelFn', 'IsLikelyExecutablePtr'):
            self.assertNotIn(gone, source)
        hook = body(source, 'Define_method_Hook(IMaterial*, R_StudioSetupSkinAndLighting,')
        self.assertIn('StudioDrawPolicy::BoneCount(_this, pClientRenderable)', hook)
        self.assertIn('StudioDrawPolicy::ChooseLighting(lighting, boneCount, forceHwLighting, forceHwSkinning)', hook)
        statements = hook.split('{', 1)[1]  # the body, after the parameter list
        uses = [line.strip() for line in statements.split('\n') if 'pClientRenderable' in line and not line.strip().startswith('//')]
        self.assertEqual(len(uses), 4, uses)
        self.assertEqual(sum('R_StudioSetupSkinAndLighting_trampoline()(_this' in use for use in uses), 2, uses)
        self.assertTrue(any(use.startswith('DBG_PRINT("[PropFixes] pClientRenderable = %p') for use in uses), uses)
        policy = text(FOLDER / POLICY)
        count = body(policy, 'inline int BoneCount(const void* studioRender, const void* clientRenderable)')
        self.assertEqual(count.count('clientRenderable'), 1, 'compared with null, nothing else')
        self.assertIn('StudioRenderStudioHdrOffset = 0x108', policy)
        self.assertIn('StudioHdrNumBonesOffset = 0x9C', policy)

    def test_the_model_to_world_read_is_only_for_the_transform_chains(self):
        """ResolveModelToWorld reads the renderable's coordinate frame only after the transform-chain check, and
        nothing else in the skinning hooks reads it."""
        hooks = text(FOLDER / HOOKS)
        resolve = body(hooks, 'static bool ResolveModelToWorld()')
        self.assertLess(resolve.index('TransformChainNeedsModelToWorld(transformMode)'), resolve.index('ReadProcessMemory'))
        outside = hooks.replace(resolve, '')
        for line in outside.split('\n'):
            if 'pClientEntity' in line and not line.strip().startswith('//'):
                self.assertRegex(line, r'void\* pClientEntity,|pClientEntity=%p|skin, boneMask, pClientEntity\)|'
                                       r'g_pPendingModelToWorldRenderable = pClientEntity;|pClientEntity, ppMaterials')

    @unittest.skipUnless(os.name == 'nt' and VS.is_dir(), 'MSVC x64 Build Tools unavailable')
    def test_the_policy_regression_passes(self):
        scratch = REPO / 'out/tmp'
        scratch.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(prefix='queued-draws-', dir=scratch) as directory:
            root = Path(directory)
            script = root / 'run.ps1'
            script.write_text(SCRIPT, encoding='utf-8')
            result = subprocess.run(['powershell', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', str(script),
                                     '-Repo', str(REPO), '-Source', str(FOLDER / TEST), '-Scratch', str(root)],
                                    capture_output=True, text=True, timeout=180)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertIn('PASS studio draw policy:', result.stdout)


if __name__ == '__main__':
    unittest.main()
