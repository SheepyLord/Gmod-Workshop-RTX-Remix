"""The Moon by day (runtime patch 0090, ADR 0207): a moon's light added to the day sky, by the real Moon's phase law.

Compiles and runs the phase laws' unit test from the committed patch (MSVC, as the runtime builds it), checks the
sky composite the patch makes (light added, only what lies beyond hidden, the horizon, the night's look kept), and
checks tools/sky/moon_daylight.py, the offline estimate the decision's numbers come from."""
import math
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(REPO / 'tools' / 'sky'))

import moon_daylight  # noqa: E402

PATCHES = sorted((REPO / 'runtime' / 'patches').glob('0090-*.patch'))
VS = Path(os.environ.get('ProgramFiles(x86)', 'C:/Program Files (x86)')) / 'Microsoft Visual Studio/2022/BuildTools'
HEADER = 'src/dxvk/rtx_render/rtx_moon_daylight.h'
TEST = 'tests/rtx/unit/test_moon_daylight.cpp'
SKY = 'src/dxvk/shaders/rtx/pass/atmosphere/atmosphere_sky.slangh'


def patch_text() -> str:
    if len(PATCHES) != 1:
        raise AssertionError(f'expected one runtime patch 0090, found {[p.name for p in PATCHES]}')
    return PATCHES[0].read_text(encoding='utf-8')


def block(patch: str, path: str) -> str:
    return patch.split(f'diff --git a/{path} b/{path}\n', 1)[1].split('\ndiff --git ', 1)[0]


def postimage(patch: str, path: str) -> str:
    """A file the patch creates, whole (one hunk from line 1 with every line added)."""
    text = block(patch, path)
    if 'new file mode' not in text.split('@@', 1)[0]:
        raise AssertionError(f'{path}: not a new file in the patch')
    header, body = text.split('@@', 2)[1:]
    match = re.search(r'\+1,(\d+)', header)
    count = int(match[1]) if match else 1
    lines = [line[1:] for line in body.splitlines()[1:] if line.startswith('+')]
    if len(lines) != count:
        raise AssertionError(f'{path}: hunk length mismatch ({len(lines)} != {count})')
    return '\n'.join(lines) + '\n'


def added(patch: str, path: str) -> str:
    return '\n'.join(line[1:] for line in block(patch, path).splitlines()
                     if line.startswith('+') and not line.startswith('+++'))


def removed(patch: str, path: str) -> str:
    return '\n'.join(line[1:] for line in block(patch, path).splitlines()
                     if line.startswith('-') and not line.startswith('---'))


SCRIPT = '''param([string]$Repo, [string]$Scratch)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $Repo 'tools/lib/VsDevEnv.psm1') -Force
Enter-VsDevEnv | Out-Null
$env:TEMP = $env:TMP = $Scratch
Set-Location -LiteralPath $Scratch
& cl.exe /nologo /EHsc /std:c++17 /O2 /W4 /WX /UNDEBUG /utf-8 tests/rtx/unit/test_moon_daylight.cpp /Femoon.exe /Fomoon.obj
if ($LASTEXITCODE) { exit $LASTEXITCODE }
& ./moon.exe
exit $LASTEXITCODE
'''


class RuntimePatchTests(unittest.TestCase):
    @unittest.skipUnless(os.name == 'nt' and VS.is_dir(), 'MSVC x64 Build Tools unavailable')
    def test_the_phase_laws_unit_test_from_the_patch(self):
        patch = patch_text()
        scratch = REPO / 'out' / 'tmp'
        scratch.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(prefix='moon-daylight-', dir=scratch) as directory:
            root = Path(directory)
            for path in (HEADER, TEST):
                file = root / path
                file.parent.mkdir(parents=True, exist_ok=True)
                file.write_text(postimage(patch, path), encoding='utf-8')
            script = root / 'run.ps1'
            script.write_text(SCRIPT, encoding='utf-8')
            result = subprocess.run(['powershell', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', str(script),
                                     '-Repo', str(REPO), '-Scratch', str(root)],
                                    capture_output=True, text=True, timeout=300)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertRegex(result.stdout, r'PASS moon daylight: \d+ checks')

    def test_the_sky_adds_a_moons_light_and_hides_only_what_lies_beyond(self):
        patch = patch_text()
        sky_added, sky_removed = added(patch, SKY), removed(patch, SKY)
        # The disc no longer replaces the background, nor fades in with the sunset.
        self.assertIn('radiance = mix(radiance, moonContrib * cirrusT + cirrusLight, coverage);', sky_removed)
        self.assertIn('coverage *= moonFade;', sky_removed)
        # Its light is added; its coverage hides what lies beyond it (airglow, halos, earlier moons).
        self.assertIn('vec3 beyondMoons = airglowLayer * cirrusT;', sky_added)
        self.assertIn('beyondMoons += glowColor * cirrusT;', sky_added)
        self.assertIn('radiance += coverage * (moonSeen - beyondMoons);', sky_added)
        self.assertIn('beyondMoons = lerp(beyondMoons, moonSeen, coverage);', sky_added)
        # By day the real Moon's light for its phase, at night the drawn look: the old fade hands it over.
        self.assertIn('const float moonLight = lerp(moonDaytimeScale(i, args), 1.0f, moonFade);', sky_added)
        # The horizon hides a disc below it, unless the sky has none; the sun disc lies beyond the moons.
        self.assertIn('coverage *= moonHorizon;', sky_added)
        self.assertRegex(sky_added, r'\(args\.noHorizon != 0u\)\s*\n\s*\? 1\.0f')
        self.assertIn('evalSunDisc(viewDirYUp, args) * (cirrusT * sunThroughMoons)', sky_added)

    def test_the_option_and_the_arguments(self):
        patch = patch_text()
        options = added(patch, 'src/dxvk/rtx_render/rtx_atmosphere.h')
        self.assertIn('RTX_OPTION_ARGS("rtx.atmosphere", float, daytimeMoonBrightness, 1.0f,', options)
        self.assertIn('args.minValue = 0.0f, args.maxValue = 4.0f', options)
        cpu = added(patch, 'src/dxvk/rtx_render/rtx_atmosphere.cpp')
        # Per pixel only: zeroed in the LUT cache key, so a change re-bakes nothing.
        for i in range(4):
            self.assertIn(f'args.moonDaytimeScale{i}           = 0.0f;', cpu)
            self.assertIn(f'args.moonDaytimeScale{i} = daytime * moondaylight::daytimeLightScale(args.moons[{i}].phase);',
                          cpu)
        # One whole 16-byte row of plain floats at the end of the arguments.
        args = added(patch, 'src/dxvk/shaders/rtx/pass/atmosphere/atmosphere_args.h')
        self.assertEqual(re.findall(r'^\s*float moonDaytimeScale(\d);', args, re.M), ['0', '1', '2', '3'])
        self.assertIn('|rtx.atmosphere.daytimeMoonBrightness|float|1|0|4|', added(patch, 'RtxOptions.md'))
        for language in ('fr', 'ja', 'ko', 'ru', 'zh-CN', 'zh-TW'):
            catalog = added(patch, f'i18n/{language}.po')
            self.assertIn('#. option rtx.atmosphere.daytimeMoonBrightness', catalog)
            self.assertNotIn('msgstr ""', catalog, language)


class EstimateTests(unittest.TestCase):
    def test_the_day_scale_matches_the_runtime(self):
        # The same numbers test_moon_daylight.cpp holds the runtime to.
        self.assertEqual(moon_daylight.daytime_light_scale(0.5), 1.0)
        self.assertAlmostEqual(moon_daylight.daytime_light_scale(0.35), 0.397, delta=0.005)
        self.assertAlmostEqual(moon_daylight.daytime_light_scale(0.25), 0.2485, delta=0.005)
        self.assertAlmostEqual(moon_daylight.daytime_light_scale(0.85), 0.146, delta=0.005)
        self.assertAlmostEqual(moon_daylight.daytime_light_scale(0.0), 0.107, delta=0.003)
        self.assertEqual(moon_daylight.night_look(10.0), 0.0)
        self.assertEqual(moon_daylight.night_look(-6.0), 1.0)

    def test_by_day_the_moon_shows_as_the_real_one_would(self):
        atmosphere = moon_daylight.Atmosphere('partlyCloudy')
        rows = {(r['hours'], r['phase']): r for r in moon_daylight.rows(atmosphere, 172, [9, 16, 18])}
        # The first-quarter Moon of a summer afternoon at 16:00, 44 degrees up: the sky around it about 0.23 of the
        # sun's 19, the lit half some 40 % brighter than that, as a real Moon would be.
        quarter = rows[(16, 'first quarter')]
        self.assertAlmostEqual(quarter['sky'], 0.23, delta=0.03)
        self.assertTrue(0.3 < quarter['contrast'] < 0.55, quarter)
        for r in rows.values():
            if r['moon_elevation'] < 10:
                continue
            # Within 20 % of a real Moon's contrast, and far below the night's look by day (a gibbous Moon's
            # light is 0.40 of it, a quarter's 0.25, a crescent's 0.15).
            self.assertAlmostEqual(r['contrast'] / r['real_contrast'], 1.0, delta=0.2)
            self.assertGreater(r['night_contrast'], 2.4 * r['contrast'])


if __name__ == '__main__':
    unittest.main()
