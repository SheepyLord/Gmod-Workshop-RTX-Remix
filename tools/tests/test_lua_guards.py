"""The native loader's review of 2026-11-16 (findings 2, 7 and 24): the RTX fixes' fifteenth native patch, lua-guards.
RemixConfig.SetConfigVariable takes only the Remix options the RTX package's own Lua sets; ToPBR's game-map actions read
only the character's own model and refuse everything else with one text; the model reload runs only while the material
system is single-threaded, at most twice a map. The folder's complete files are the patch applied, every text, key or
hash option a runtime patch declares is reviewed in the option regression's table, every option the package's Lua and
data set stays allowed, and the SDK-free regressions pass."""
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import unittest

from test_endfield_maps import REPO, SKINNING, apply, text
from test_queued_draws import added, body

FOLDER = SKINNING / 'lua-guards'
PATCH = FOLDER / 'lua-guards.patch'
TO_PBR = 'source/material_pipeline/to_pbr'
PINS = json.loads((REPO / 'tools/ci/pins.json').read_text(encoding='utf-8'))['fixes']
# Each file the patch changes and the folder holding its complete copy before it (the last earlier patch to change it).
CHANGED = {
    'source/lua_path_policy.h': 'autopbr',
    f'{TO_PBR}/to_pbr.cpp': 'topbr-scope',
    'source/module.cpp': 'backrooms',
    'source/remixapi/config_lua_bindings.cpp': 'upscaling-state',
    'tests/lua_path_policy_test.cpp': 'autopbr',
}
NEW = [f'{TO_PBR}/game_source.h', 'source/model_reload_policy.h', 'source/remix_option_policy.h',
       'tests/game_source_test.cpp', 'tests/model_reload_policy_test.cpp', 'tests/remix_option_policy_test.cpp']
OPTION_TEST = FOLDER / 'tests/remix_option_policy_test.cpp'
# A runtime option whose value is text, a key binding or a hash list, declared on a line a runtime patch adds.
DECLARATION = re.compile(r'\bRTX_OPTION(?:_FULL|_ENV|_FLAG|_FLAG_ENV|_ARGS)?\s*\(\s*"([^"]+)"\s*,\s*'
                         r'(std::string|VirtualKeys|fast_unordered_set|std::vector<XXH64_hash_t>)\s*,\s*([A-Za-z_]\w*)\s*,')
TABLE = re.compile(r'\{"(rtx\.[^"]+)", Expect::(Refused|HashList|Text)\}')
QUOTED = re.compile(r'''["'](rtx\.[A-Za-z0-9_]+(?:\.[A-Za-z0-9_]+)*)["']''')
# Where the RTX package's Lua lives, and the data its Lua reads options from.
LUA_ROOTS = ['packages', 'companion/nativeloader', 'vr/addon', 'glass/addon', 'fs_accel/addon']
WEATHER = 'companion/nativeloader/lua/nativeloader/weather_presets.lua'
EYE_WHITES = 'companion/nativeloader/lua/autorun/client/nativeloader_eye_whites.lua'
# Names in those files that are read (RemixConfig.GetConfigVariable), not set.
READ_ONLY = {
    'rtx.sceneScale': 'the sky reads it (nativeloader_sky.lua)',
    'rtx.volumetrics': "the RTX Remix tab's fog choice; its presets set rtx.volumetrics.* (nativeloader_menu.lua)",
    'rtx.opacityMicromap.enable': "the bullet break simulator's probe text",
    'rtx.opacityMicromap.enableBinding': "the bullet break simulator's probe text",
    'rtx.keepTexturesForTagging': "the bullet break simulator's probe text",
    'rtx.hashCollisionDetection.enable': "the bullet break simulator's probe text",
}
VS = Path(os.environ.get('ProgramFiles(x86)', 'C:/Program Files (x86)')) / 'Microsoft Visual Studio/2022/BuildTools'
SCRIPT = '''param([string]$Repo, [string]$Tree, [string]$Scratch, [string]$Keys)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $Repo 'tools/lib/VsDevEnv.psm1') -Force
Enter-VsDevEnv | Out-Null
$env:TEMP = $Scratch
$env:TMP = $Scratch
Set-Location -LiteralPath $Scratch
$failed = 0
foreach ($name in 'lua_path_policy_test', 'remix_option_policy_test', 'model_reload_policy_test', 'game_source_test') {
    & cl.exe /nologo /EHsc /std:c++17 /W4 /WX /UNDEBUG /DWIN32_LEAN_AND_MEAN /DNOMINMAX /utf-8 (Join-Path $Tree "tests/$name.cpp") "/Fe$name.exe" "/Fo$name.obj"
    if ($LASTEXITCODE -ne 0) { "FAIL compile $name"; $failed++; continue }
    if ($name -eq 'game_source_test') {
        $folder = Join-Path $Scratch 'game-source'
        New-Item -ItemType Directory -Force $folder | Out-Null
        & (Join-Path $Scratch "$name.exe") $folder
    } else { & (Join-Path $Scratch "$name.exe") }
    if ($LASTEXITCODE -ne 0) { "FAIL run $name"; $failed++ }
}
& (Join-Path $Scratch 'remix_option_policy_test.exe') --verdicts $Keys | Set-Content -Encoding utf8 (Join-Path $Scratch 'verdicts.txt')
if ($LASTEXITCODE -ne 0) { "FAIL verdicts"; $failed++ }
exit $failed
'''


def folders():
    """The patch folders in pins.json's order, each once (autopbr holds two patches)."""
    result = []
    for patch in PINS['patches']:
        folder = (REPO / patch).parent
        if folder not in result:
            result.append(folder)
    return result


def runtime_declarations():
    """Every text, key-binding or hash-list option a runtime patch declares: name -> types."""
    found = {}
    for patch in sorted((REPO / 'runtime/patches').glob('*.patch')):
        for line in patch.read_text(encoding='utf-8', errors='replace').splitlines():
            if line.startswith('+') and not line.startswith('+++'):
                for m in DECLARATION.finditer(line):
                    found.setdefault(f'{m[1]}.{m[3]}', set()).add(m[2])
    return found


def shipped_options():
    """The option names the RTX package's Lua and data set: the quoted names in each Lua file that calls
    SetConfigVariable (with its data in a sh_config.lua beside it and the weather presets the sky sets), the eye whites'
    names, the default map config's rtx: lines and the content packs' profiles. Read-only names are left out."""
    found = {}
    files = []
    for root in LUA_ROOTS:
        for path in sorted((REPO / root).rglob('*.lua')):
            if 'SetConfigVariable' in path.read_text(encoding='utf-8', errors='replace'):
                files.append(path)
                files += [p for p in path.parent.glob('sh_config.lua') if p not in files]
    files.append(REPO / WEATHER)
    for path in files:
        for name in QUOTED.findall(path.read_text(encoding='utf-8', errors='replace')):
            found.setdefault(name, set()).add(path.relative_to(REPO).as_posix())
    eyes = text(REPO / EYE_WHITES)
    prefix = re.search(r'local PREFIX = "(rtx\.[\w.]+)"', eyes)[1]
    for name in re.findall(r'\bwrite\("(\w+)"', eyes):
        found.setdefault(prefix + name, set()).add(EYE_WHITES)
    for path in sorted((REPO / 'packages').rglob('remix_map_configs/*.txt')):
        for name in re.findall(r'^\s*rtx:(\S+)\s*=', text(path), re.M):
            found.setdefault(name, set()).add(path.relative_to(REPO).as_posix())
    for path in sorted((REPO / 'skills').rglob('astra_companion/*.json')):
        for name, _ in json.loads(text(path)).get('remix', []):
            found.setdefault(name, set()).add(path.relative_to(REPO).as_posix())
    return {name: where for name, where in found.items() if name not in READ_ONLY}, found


class LuaGuardTests(unittest.TestCase):
    def test_complete_files_are_the_patch_applied(self):
        """The patch touches exactly its files; each changed one is the last earlier copy with the patch applied (no
        patch between changed it), each new one the patch's added lines. pins.json builds the module with it last,
        right after topbr-scope."""
        patch = PATCH.read_text(encoding='utf-8')
        self.assertEqual(re.findall(r'^diff --git a/(\S+) b/\1$', patch, re.M), sorted(list(CHANGED) + NEW))
        order = [folder.name for folder in folders()]
        for path, before in CHANGED.items():
            self.assertEqual(apply(patch, path, text(SKINNING / before / path)), text(FOLDER / path), path)
            later = [name for name in order[order.index(before) + 1:] if name != FOLDER.name and (SKINNING / name / path).exists()]
            self.assertEqual(later, [], path)
        for path in NEW:
            self.assertEqual(added(patch, path), text(FOLDER / path).rstrip('\n').split('\n'), path)
        self.assertEqual(PINS['patches'][-1], PATCH.relative_to(REPO).as_posix())
        self.assertEqual(PINS['patches'][-2], 'packages/fixes/licenses/oversized-skinning/topbr-scope/topbr-scope.patch')
        self.assertIn('source/*', PINS['patch_paths'])

    def test_set_config_variable_takes_only_the_packages_options(self):
        """The one generic setter asks the policy before the Remix API; every other setter of the binding names its
        option; the review's list is refused by name; the policy needs no SDK."""
        binding = text(FOLDER / 'source/remixapi/config_lua_bindings.cpp')
        setter = body(binding, 'LUA_FUNCTION(RemixConfig_SetConfigVariable) {')
        self.assertIn('RemixOptionPolicy::LuaMaySet(key, value, &reason)', setter)
        self.assertLess(setter.index('LuaMaySet'), setter.index('configManager.SetConfigVariable(key, value)'))
        keys = re.findall(r'configManager\.SetConfigVariable\(([^,]+),', binding)
        self.assertEqual([key for key in keys if not key.startswith('"rtx.')], ['key'])
        policy = text(FOLDER / 'source/remix_option_policy.h')
        refused = body(policy, 'inline bool Refused(std::string_view key) {')
        for name in ('"rtx.capture"', '"rtx.enablereplacement"', '"rtx.profiler."', '"rtx.automation."', '"rtx.freecam."',
                     '"rtx.skyprobeside"', '"rtx.welcomemessage"', '"rtx.splashmessagedisplaytimeseconds"',
                     '"rtx.enablecrashhotkey"', '"rtx.crashhotkey"', '"rtx.gpucrashhotkey"',
                     '"rtx.enablebreakintodebuggeronpressingb"', '"rtx.remixmenukeybinds"', 'RemixPathOption(name)'):
            self.assertIn(name, refused)
        self.assertLess(body(policy, 'inline bool LuaMaySet(').index('Refused(key)'),
                        body(policy, 'inline bool LuaMaySet(').index('Allowed(key)'))
        self.assertIn('"rtx.watersim.rings.texture"', body(text(FOLDER / 'source/lua_path_policy.h'),
                                                          'inline bool RemixPathOption(std::string_view key) {'))
        self.assertNotIn('#include <windows', policy.lower())

    def test_every_runtime_text_key_and_hash_option_is_reviewed(self):
        """Every option of text, key-binding or hash-list type a runtime patch declares has a verdict in the option
        regression's table (which checks the policy gives it), so a merge that adds one cannot slip past."""
        declared = runtime_declarations()
        self.assertGreaterEqual(len(declared), 27)
        for name in ('rtx.waterSim.rings.texture', 'rtx.gmod.eyeWhiteAliases', 'rtx.gmod.particleTexturesForSession'):
            self.assertIn(name, declared)
        table = dict(TABLE.findall(text(OPTION_TEST)))
        self.assertGreaterEqual(len(table), 80)
        self.assertEqual(sorted(set(declared) - set(table)), [], 'add these to kRuntimeOptions in ' + OPTION_TEST.name)
        self.assertEqual(table['rtx.waterSim.rings.texture'], 'Refused')
        self.assertEqual(table['rtx.captureHotKey'], 'Refused')

    def test_the_shipped_options_are_found(self):
        """The collection the compiled check below judges finds every kind of source (no compiler needed)."""
        options, everything = shipped_options()
        self.assertGreaterEqual(len(options), 150)
        for name, source in (('rtx.ignoreGamePointLights', 'cl_rtx_settings.lua'),
                             ('rtx.legacyEmissiveColorsString', 'cl_physgun_color_sync.lua'),
                             ('rtx.raytracedRenderTargetTextures', 'cl_arc9.lua'),
                             ('rtx.translucentMaterial.normalIntensity', 'cl_core.lua'),
                             ('rtx.volumetrics.enableAtmosphere', 'sh_config.lua'),
                             ('rtx.opacityMicromapIgnoreTextures', 'cl_40_damage.lua'),
                             ('rtx.atmosphere.cloudCoverageMean', 'weather_presets.lua'),
                             ('rtx.atmosphere.starMapConstellationBrightness', 'nativeloader_sky.lua'),
                             ('rtx.gmod.eyeWhiteAliases', 'nativeloader_eye_whites.lua'),
                             ('rtx.gmod.legacyEffectTexturesForSession', '_nativeloader_effect_categories.lua'),
                             ('rtx.tonemap.psycho17.purityScale', 'nativeloader_menu.lua'),
                             ('rtx.ignoreTextures', 'cl_weapons_model.lua'),
                             ('rtx.di.spatialSamples', 'default.txt'),
                             ('rtx.bloom.burnIntensity', 'gm_korolevskiy_theater.json')):
            self.assertTrue(any(where.endswith(source) for where in options.get(name, ())), (name, source))
        for name in READ_ONLY:
            self.assertIn(name, everything, 'a read-only exemption no shipped file names any more: ' + name)

    def test_game_material_actions_read_only_the_characters_model(self):
        """"options" lists through ListOptions and "maps" scans through SourceFolder, both after the source check;
        "maps" takes only images the folder lists; an automatic resolution counts only a usable model as its source;
        no worker path opens a model folder otherwise."""
        source = text(FOLDER / f'{TO_PBR}/to_pbr.cpp')
        worker = body(source, 'void TextureProcessor::WorkerThreadFunc() {')
        self.assertIn('GamePBR::SourceModels sources;', worker)
        self.assertNotIn('discovery.Get(', worker)
        options = worker.split('if(gameJob.action=="options") {', 1)[1].split('continue;', 1)[0]
        self.assertIn('GamePBR::ListOptions(sources,discovery,gameJob.source,gameJob.base,why)', options)
        self.assertIn('view.error=options.error;', options)
        maps = worker.split('if(choice.mode=="maps") {', 1)[1].split('choice.record=*r;', 1)[0]
        self.assertLess(maps.index('GamePBR::SourceFolder(sources,discovery,gameJob.source,gameJob.base,why)'),
                        maps.index('folder.Families()'))
        self.assertLess(maps.index('throw std::runtime_error("choose maps from the lists of this model\'s folder");'),
                        maps.index('convert(&selected)'))
        self.assertNotIn('std::ifstream source(std::filesystem::u8path(gameJob.source)', worker)
        self.assertIn('const bool sourceReadable = check.usable;', worker)
        header = text(FOLDER / f'{TO_PBR}/game_source.h')
        self.assertIn('throw std::runtime_error(SourceRefusal);', body(header, 'inline Discovery& SourceFolder('))
        self.assertIn('options.error = SourceRefusal;', body(header, 'inline Options ListOptions('))
        self.assertIn('ParsePMX(Read(pmx, 256ull * 1024 * 1024))', header)

    def test_the_model_reload_runs_single_threaded_twice_a_map(self):
        """The binding asks the material system's thread mode and the allowance before it flushes; the allowance
        starts again when the module opens for a map; cl_rtx.lua's last call still switches queued rendering off."""
        module = text(FOLDER / 'source/module.cpp')
        binding = body(module, 'LUA_FUNCTION(ReloadModelsAfterHardwareSkinningSettings_Lua) {')
        self.assertIn('materials && materials->GetThreadMode() == MATERIAL_SINGLE_THREADED', binding)
        self.assertLess(binding.index('g_modelReloads.Take(singleThreaded, &reason)'),
                        binding.index('ModelLoadHooks::Instance().ReloadModelsAfterSettings();'))
        self.assertIn('g_modelReloads.Reset();', body(module, 'GMOD_MODULE_OPEN() {'))
        self.assertIn('constexpr int ReloadsPerLuaState = 2;', text(FOLDER / 'source/model_reload_policy.h'))
        lua = text(REPO / 'packages/fixes/garrysmod/garrysmod/addons/remixbinary/lua/autorun/cl_rtx.lua')
        self.assertIn('RunConsoleCommand("mat_queue_mode", "0")', lua)


@unittest.skipUnless(os.name == 'nt' and VS.is_dir(), 'MSVC x64 Build Tools unavailable')
class LuaGuardRegressions(unittest.TestCase):
    """The patch's four regressions, compiled with /W4 /WX on the module's headers as the fifteen patches leave them
    (every folder's files in pins.json's order, later over earlier), and the option policy's verdict on every option
    the package's Lua and data set."""

    @classmethod
    def setUpClass(cls):
        scratch = REPO / 'out/tmp'
        scratch.mkdir(parents=True, exist_ok=True)
        cls.directory = tempfile.TemporaryDirectory(prefix='lua-guards-', dir=scratch)
        root = Path(cls.directory.name)
        tree = root / 'tree'
        for folder in folders():
            for part in ('source', 'tests'):
                if (folder / part).is_dir():
                    shutil.copytree(folder / part, tree / part, dirs_exist_ok=True)
        cls.options, _ = shipped_options()
        keys = root / 'keys.txt'
        keys.write_text(''.join(name + '\n' for name in sorted(cls.options)), encoding='utf-8')
        script = root / 'run.ps1'
        script.write_text(SCRIPT, encoding='utf-8')
        cls.result = subprocess.run(['powershell', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', str(script),
                                     '-Repo', str(REPO), '-Tree', str(tree), '-Scratch', str(root), '-Keys', str(keys)],
                                    capture_output=True, text=True, timeout=600)
        verdicts = root / 'verdicts.txt'
        cls.verdicts = verdicts.read_text(encoding='utf-8-sig').splitlines() if verdicts.exists() else []

    @classmethod
    def tearDownClass(cls):
        cls.directory.cleanup()

    def test_the_regressions_pass(self):
        output = self.result.stdout + self.result.stderr
        self.assertEqual(self.result.returncode, 0, output)
        for line in ('PASS lua path policy:', 'PASS remix option policy:', 'PASS model reload policy:', 'PASS game source:'):
            self.assertIn(line, self.result.stdout)

    def test_what_the_packages_lua_sets_stays_allowed(self):
        verdicts = dict(line.split(' ', 1)[::-1] for line in self.verdicts if line.strip())
        self.assertEqual(set(verdicts), set(self.options), self.result.stdout + self.result.stderr)
        refused = {name: sorted(self.options[name]) for name, verdict in verdicts.items() if verdict != 'allow'}
        self.assertEqual(refused, {}, 'the option policy refuses options the package sets')


if __name__ == '__main__':
    unittest.main()
