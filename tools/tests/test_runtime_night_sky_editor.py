"""The night sky editor (runtime patch 0099, ADR 0227): each layer of the night sky image on its own.

Compiles and runs the layers' unit test from the committed patch (MSVC, as the runtime builds it), and checks
what the patch changes: the options and their ranges, the arguments zeroed in the LUT cache key, the
constellations' texture beside the nebula's and its binding, a layer at 0 neither drawn nor kept, the sky's
per-layer weights and colours, the shooting stars, and RtxOptions.md. Also checks that the RTX package carries
the split layers in every tier."""
import json
import os
from pathlib import Path
import re
import subprocess
import tempfile
import unittest

REPO = Path(__file__).resolve().parents[2]
PATCHES = sorted((REPO / 'runtime' / 'patches').glob('0099-*.patch'))
VS = Path(os.environ.get('ProgramFiles(x86)', 'C:/Program Files (x86)')) / 'Microsoft Visual Studio/2022/BuildTools'
HEADER = 'src/dxvk/rtx_render/rtx_night_sky_layers.h'
TEST = 'tests/rtx/unit/test_night_sky_layers.cpp'
SKY = 'src/dxvk/shaders/rtx/pass/atmosphere/atmosphere_sky.slangh'
ARGS = 'src/dxvk/shaders/rtx/pass/atmosphere/atmosphere_args.h'
OPTIONS = 'src/dxvk/rtx_render/rtx_atmosphere.h'
CPU = 'src/dxvk/rtx_render/rtx_atmosphere.cpp'
LAYERS = ('Star', 'Constellation', 'Galaxy', 'Nebula')


def patch_text() -> str:
    if len(PATCHES) != 1:
        raise AssertionError(f'expected one runtime patch 0099, found {[p.name for p in PATCHES]}')
    return PATCHES[0].read_text(encoding='utf-8')


def block(patch: str, path: str) -> str:
    text = patch.split(f'diff --git a/{path} b/{path}\n', 1)[1].split('\ndiff --git ', 1)[0]
    return text.split('\n-- \n', 1)[0]


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
& cl.exe /nologo /EHsc /std:c++latest /O2 /W4 /WX /UNDEBUG /utf-8 tests/rtx/unit/test_night_sky_layers.cpp /Fenight.exe /Fonight.obj
if ($LASTEXITCODE) { exit $LASTEXITCODE }
& ./night.exe
exit $LASTEXITCODE
'''


class RuntimePatchTests(unittest.TestCase):
    @unittest.skipUnless(os.name == 'nt' and VS.is_dir(), 'MSVC x64 Build Tools unavailable')
    def test_the_layers_unit_test_from_the_patch(self):
        patch = patch_text()
        scratch = REPO / 'out' / 'tmp'
        scratch.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(prefix='night-sky-', dir=scratch) as directory:
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
            self.assertRegex(result.stdout, r'PASS night sky layers: \d+ checks')

    def test_the_options_and_their_ranges(self):
        options = added(patch_text(), OPTIONS)
        # Each option up to its own range line (descriptions may hold a semicolon).
        for layer in LAYERS:
            self.assertRegex(options, r'RTX_OPTION_ARGS\("rtx\.atmosphere", float, starMap%sBrightness, 1\.0f,[\s\S]*?'
                                      r'args\.minValue = 0\.0f, args\.maxValue = 8\.0f\);' % layer)
            self.assertRegex(options, r'RTX_OPTION_ARGS\("rtx\.atmosphere", float, starMap%sSaturation, 1\.0f,[\s\S]*?'
                                      r'args\.minValue = 0\.0f, args\.maxValue = 2\.0f\);' % layer)
        # 1.2 a minute is the sky's former fixed 8 % of four-second slots.
        self.assertRegex(options, r'shootingStarsPerMinute, 1\.2f,[\s\S]*?args\.minValue = 0\.0f, args\.maxValue = 15\.0f\);')
        self.assertRegex(options, r'shootingStarBrightness, 1\.0f,[\s\S]*?args\.minValue = 0\.0f, args\.maxValue = 8\.0f\);')
        # No new path option: Lua cannot choose the constellations' file any more than the nebula's.
        self.assertNotRegex(options, r'std::string, \w*[Cc]onstellation')
        self.assertIn('SkyTexture        m_starMapConstellations;', options)

    def test_the_arguments_are_per_pixel_and_zeroed_in_the_lut_key(self):
        patch = patch_text()
        args = added(patch, ARGS)
        fields = re.findall(r'^\s*float (\w+);', args, re.M)
        self.assertEqual(fields, [f'starMap{layer}Weight' for layer in LAYERS]
                         + [f'starMap{layer}Saturation' for layer in LAYERS]
                         + ['starMapCeiling', 'shootingStarChance', 'shootingStarBrightness', 'nightSkyEditorPad0'])
        self.assertEqual(len(fields) % 4, 0, 'whole 16-byte rows')
        cpu = added(patch, CPU)
        for field in fields:
            self.assertRegex(cpu, r'args\.%s\s*= 0\.0f;' % field)
        self.assertIn('#define SKY_TEXTURE_CONSTELLATIONS 64u', args)
        self.assertIn('#define SKY_TEXTURE_NIGHT_IMAGE   128u', args)

    def test_the_constellations_are_a_layer_beside_the_nebula(self):
        patch = patch_text()
        indices = added(patch, 'src/dxvk/shaders/rtx/pass/common_binding_indices.h')
        self.assertIn('#define BINDING_ATMOSPHERE_STAR_MAP_CONSTELLATIONS 222', indices)
        self.assertIn('#define BINDING_ATMOSPHERE_MAX                   BINDING_ATMOSPHERE_STAR_MAP_CONSTELLATIONS', indices)
        self.assertIn('TEXTURE2D(BINDING_ATMOSPHERE_STAR_MAP_CONSTELLATIONS)', indices)
        self.assertIn('Texture2D<float4> AtmosphereStarMapConstellations;',
                      added(patch, 'src/dxvk/shaders/rtx/pass/common_bindings.slangh'))
        cpu = added(patch, CPU)
        self.assertIn('nightsky::constellationTexturePath(RtxAtmosphere::starMapNebulaTexture())', cpu)
        self.assertIn('ctx.bindResourceView(BINDING_ATMOSPHERE_STAR_MAP_CONSTELLATIONS,', cpu)
        # A layer at 0 is neither drawn nor kept; every layer off is a night without stars, not the procedural one.
        self.assertIn('return (starMap && nightsky::layerWeight(brightness) > 0.0f) ? path : std::string();', cpu)
        self.assertIn('if (anyLayer || allOff) {', cpu)

    def test_the_sky_weighs_each_layer(self):
        patch = patch_text()
        sky_added, sky_removed = added(patch, SKY), removed(patch, SKY)
        self.assertIn('layers += s.rgb * s.a;', sky_removed)
        self.assertIn('return pow(min(layers, vec3(1.0f)), vec3(2.2f)) * args.starMapBrightness;', sky_removed)
        self.assertIn('layers += nightSkyLayerColour(s.rgb * s.a, args.starMapStarSaturation) * args.starMapStarWeight;',
                      sky_added)
        self.assertIn('nightSkyLayerColour(g.rgb * g.a, args.starMapGalaxySaturation) * (args.starMapGalaxyWeight * deepNight)',
                      sky_added)
        self.assertIn('nightSkyLayerColour(nebula, args.starMapNebulaSaturation) * (args.starMapNebulaWeight * deepNight)',
                      sky_added)
        # The constellations come out with the stars: no deepNight on their layer.
        self.assertIn('nightSkyLayerColour(constellations, args.starMapConstellationSaturation) * args.starMapConstellationWeight;',
                      sky_added)
        self.assertIn('return pow(min(layers, vec3(args.starMapCeiling)), vec3(2.2f)) * args.starMapBrightness;', sky_added)
        self.assertIn('if ((args.skyTextureFlags & SKY_TEXTURE_NIGHT_IMAGE) != 0u) {', sky_added)
        # The shooting stars: the fixed 8 % and brightness 2 become the options'.
        self.assertIn('if (slotHash > 0.92f) {', sky_removed)
        self.assertIn('if (slotHash > 1.0f - args.shootingStarChance) {', sky_added)
        self.assertIn('(2.0f * args.shootingStarBrightness)', sky_added)

    def test_rtx_options_md_has_the_new_rows(self):
        rows = added(patch_text(), 'RtxOptions.md')
        for layer in LAYERS:
            self.assertIn(f'|rtx.atmosphere.starMap{layer}Brightness|float|1|0|8|', rows)
            self.assertIn(f'|rtx.atmosphere.starMap{layer}Saturation|float|1|0|2|', rows)
        self.assertIn('|rtx.atmosphere.shootingStarsPerMinute|float|1.2|0|15|', rows)
        self.assertIn('|rtx.atmosphere.shootingStarBrightness|float|1|0|8|', rows)
        self.assertIn('\\<name\\>\\_constellations\\.dds', rows)


class PackageTests(unittest.TestCase):
    def test_the_package_carries_the_split_layers_in_every_tier(self):
        index = json.loads((REPO / 'packages' / 'runtime' / 'files.json').read_text(encoding='utf-8'))['files']
        sizes = {rel: entry['size'] for rel, entry in index.items() if rel.startswith('files/atmosphere/nebula')}
        # The nebula alone (BC7) and its constellations beside it (BC1), at 8192 and, for the low tier, 4096.
        self.assertEqual(sizes, {'files/atmosphere/nebula.dds': 89478660,
                                 'files/atmosphere/nebula_constellations.dds': 44739404,
                                 'files/atmosphere/nebula_4096.dds': 22369796,
                                 'files/atmosphere/nebula_4096_constellations.dds': 11184972})
        low = (REPO / 'packages' / 'runtime' / 'layers' / 'low.conf').read_text(encoding='utf-8')
        # The low tier names the nebula; its constellations follow from that name.
        self.assertIn('rtx.atmosphere.starMapNebulaTexture = atmosphere/nebula_4096.dds', low)
        self.assertNotIn('onstellation', low)


if __name__ == '__main__':
    unittest.main()
