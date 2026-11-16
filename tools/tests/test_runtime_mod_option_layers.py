"""A mod's Remix Logic option layer (runtime patch 0101; the review of 2026-11-16, finding 1): a config file only from
the mod's own folder, only rendering options, and a value that fails to parse refused instead of thrown.

Compiles and runs the policy's unit test from the committed patch (MSVC, as the runtime builds it), checks the
runtime's wiring in the patch (the graph's parser, the option manager, the option layer, readValue's callers, the
Remix API, the graph component, meson), and that no Remix mod the RTX package ships uses Remix Logic graphs, which the
policy would restrict."""
import os
from pathlib import Path
import re
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parent))
import runtime_patch_text as patches  # noqa: E402

REPO = patches.REPO
VS = Path(os.environ.get('ProgramFiles(x86)', 'C:/Program Files (x86)')) / 'Microsoft Visual Studio/2022/BuildTools'
POLICY = 'src/dxvk/rtx_render/rtx_mod_layer_policy.h'
POLICY_TEST = 'tests/rtx/unit/test_mod_layer_policy.cpp'
MANAGER_TEST = 'tests/rtx/unit/test_mod_option_layer.cpp'
PARSER = 'src/dxvk/rtx_render/graph/rtx_graph_usd_parser.cpp'
MANAGER_H = 'src/dxvk/rtx_render/rtx_option_manager.h'
MANAGER = 'src/dxvk/rtx_render/rtx_option_manager.cpp'
LAYER_H = 'src/dxvk/rtx_render/rtx_option_layer.h'
LAYER = 'src/dxvk/rtx_render/rtx_option_layer.cpp'
OPTION_H = 'src/dxvk/rtx_render/rtx_option.h'
OPTION = 'src/dxvk/rtx_render/rtx_option.cpp'
API = 'src/dxvk/rtx_render/rtx_remix_api.cpp'
ACTION = 'src/dxvk/rtx_render/graph/components/rtx_option_layer_action.h'


def patch_text() -> str:
    return patches.read(patches.one_patch(101))


SCRIPT = '''param([string]$Repo, [string]$Scratch)
$ErrorActionPreference = 'Stop'
Import-Module (Join-Path $Repo 'tools/lib/VsDevEnv.psm1') -Force
Enter-VsDevEnv | Out-Null
$env:TEMP = $env:TMP = $Scratch
Set-Location -LiteralPath $Scratch
& cl.exe /nologo /EHsc /std:c++17 /O2 /W4 /WX /UNDEBUG /utf-8 tests/rtx/unit/test_mod_layer_policy.cpp /Fepolicy.exe /Fopolicy.obj
if ($LASTEXITCODE) { exit $LASTEXITCODE }
& ./policy.exe
exit $LASTEXITCODE
'''


class ModOptionLayerTests(unittest.TestCase):
    @unittest.skipUnless(os.name == 'nt' and VS.is_dir(), 'MSVC x64 Build Tools unavailable')
    def test_the_policys_unit_test_from_the_patch(self):
        patch = patch_text()
        scratch = REPO / 'out' / 'tmp'
        scratch.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(prefix='mod-layer-policy-', dir=scratch) as directory:
            root = Path(directory)
            for path in (POLICY, POLICY_TEST):
                file = root / path
                file.parent.mkdir(parents=True, exist_ok=True)
                file.write_text(patches.postimage(patch, path), encoding='utf-8')
            script = root / 'run.ps1'
            script.write_text(SCRIPT, encoding='utf-8')
            result = subprocess.run(['powershell', '-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', str(script),
                                     '-Repo', str(REPO), '-Scratch', str(root)],
                                    capture_output=True, text=True, timeout=300)
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            self.assertRegex(result.stdout, r'PASS mod layer policy: \d+ checks')

    def test_the_policy_is_self_contained_and_names_the_reviewed_options(self):
        policy = patches.postimage(patch_text(), POLICY)
        # The gate compiles it with the standard library only.
        self.assertEqual(re.findall(r'#include <([^>]+)>', policy), ['cstddef', 'exception', 'string', 'string_view', 'vector'])
        self.assertNotIn('#include "', policy)
        # The namespaces and single options a mod's layer may set, and the rules every option meets.
        namespaces = re.search(r'kAllowedNamespaces\[\] = \{(.*?)\};', policy, re.S).group(1)
        self.assertEqual(re.findall(r'"([^"]+)"', namespaces), [
            'rtx.atmosphere.', 'rtx.weather.', 'rtx.volumetrics.', 'rtx.tonemap.', 'rtx.autoExposure.', 'rtx.bloom.',
            'rtx.postfx.'])
        self.assertIn('inline constexpr double kMaxIntegerRange = 1024.0;', policy)
        for rule in ('if (option.userSetting) {', 'if (option.noSave) {', 'name.find("debug") != std::string::npos'):
            self.assertIn(rule, policy)
        test = patches.postimage(patch_text(), POLICY_TEST)
        # The review's minimum: ADR 0112's 14 path options, the water rings' texture, the splash, captures, keys, the
        # interface language, the replacement switches and the sky probe, each tested as refused.
        for name in ('rtx.atmosphere.moonAlbedoTexture', 'rtx.neuralRadianceCache.cudaDllDepsDirectoryPath',
                     'rtx.nsight.graphicsCaptureOutputFile', 'rtx.cameraSequence.filePath', 'rtx.baseGameModRegex',
                     'rtx.captureTimestampReplacement', 'rtx.waterSim.rings.texture', 'rtx.welcomeMessage',
                     'rtx.splashMessageDisplayTimeSeconds', 'rtx.captureHotKey', 'rtx.gui.language',
                     'rtx.enableReplacementAssets', 'rtx.skyProbeSide', 'rtx.ignoreTextures'):
            self.assertIn(f'"{name}"', test)

    def test_the_parser_refuses_a_path_before_resolving_it_and_keeps_it_in_the_mod(self):
        patch = patch_text()
        block = patches.file_block(patch, PARSER)
        added = patches.added_lines(patch, PARSER)
        self.assertIn('#include "../rtx_mod_layer_policy.h"', added)
        self.assertIn('const std::string modFolder = modFolderOf(attr);', added)
        self.assertIn('mod_layer_policy::authoredPathAllowed(pathStr, &reason)', added)
        self.assertIn('mod_layer_policy::insideFolder(candidate, modFolder, &reason)', added)
        # Refused before ArResolver looks for it: resolving \\host\share opens a network session.
        self.assertLess(block.index('mod_layer_policy::authoredPathAllowed(pathStr, &reason)'),
                        block.index('auto propertyStack = attr.GetPropertyStack();'))
        self.assertLess(block.index('auto propertyStack = attr.GetPropertyStack();'),
                        block.index('pxr::ArResolvedPath resolvedPath = resolver.Resolve(identifier);'))
        self.assertLess(block.index('pxr::ArResolvedPath resolvedPath = resolver.Resolve(identifier);'),
                        block.index('mod_layer_policy::insideFolder(candidate, modFolder, &reason)'))
        # The mod's folder is its stage's root layer's; a string-typed asset path resolves as a token does.
        self.assertIn('const pxr::SdfLayerHandle rootLayer = stage->GetRootLayer();', added)
        self.assertIn('if (value.IsHolding<std::string>()) {', added)

    def test_the_graph_acquires_a_mods_layer_and_throws_nothing(self):
        patch = patch_text()
        added, removed = patches.added_lines(patch, ACTION), patches.removed_lines(patch, ACTION)
        self.assertIn('layer = RtxOptionManager::acquireModLayer(', added)
        self.assertIn('} catch (const std::exception& e) {', added)
        self.assertIn('const RtxOptionLayer* layer = RtxOptionManager::acquireLayer(', removed)

    def test_the_option_manager_checks_the_path_and_marks_the_layer(self):
        patch = patch_text()
        header = patches.added_lines(patch, MANAGER_H)
        self.assertIn('bool isSystemLayer = false, const Config* config = nullptr, bool modLayer = false);', header)
        self.assertIn('static RtxOptionLayer* acquireModLayer(', header)
        block = patches.file_block(patch, MANAGER)
        added = patches.added_lines(patch, MANAGER)
        self.assertIn('util::RtxFileSys::path(util::RtxFileSys::Mods)', added)
        self.assertIn('if (!mod_layer_policy::configPathAllowed(configPath, modsRoot, &reason)) {', added)
        self.assertLess(block.index('mod_layer_policy::configPathAllowed(configPath, modsRoot, &reason)'),
                        block.index('return acquireLayer(configPath, layerKey, blendStrength, blendThreshold, false, nullptr, true);'))
        # A mod's graph never shares a layer of another kind; the layer is marked before it first applies.
        self.assertIn('if (it->second->isModLayer() != modLayer) {', added)
        self.assertLess(block.index('layer->m_modLayer = modLayer;'), block.index('result->applyToAllOptions();'))
        self.assertIn('const auto refused = result->getRejectedEntries("");', added)
        layer_h = patches.added_lines(patch, LAYER_H)
        self.assertIn('bool isModLayer() const { return m_modLayer; }', layer_h)
        self.assertIn('bool m_modLayer = false;', layer_h)
        # A mod's layer creates no dynamic options (the per-GPU namespaces are the player's choices).
        layer = patches.added_lines(patch, LAYER)
        self.assertIn('if (!m_modLayer) {', layer)
        self.assertIn('RtxOptionManager::discoverDynamicOptions(*this);', layer)

    def test_a_mods_layer_applies_only_allowed_options_and_no_value_throws(self):
        patch = patch_text()
        added, removed = patches.added_lines(patch, OPTION), patches.removed_lines(patch, OPTION)
        self.assertIn('if (optionLayer.isModLayer() && !allowedInModLayer()) {', added)
        self.assertIn('return mod_layer_policy::optionAllowed(facts);', added)
        self.assertIn('mod_layer_policy::parsedWithoutThrow([&]() { readValue(options, fullName, parsed.data); }, error)', added)
        # readOptionLayer and readOption read through readValueWithoutThrow now, never readValue directly.
        self.assertIn('if (!readValueWithoutThrow(optionLayer.getConfig(), fullName, value.data, &error)) {', added)
        self.assertIn('if (!readValueWithoutThrow(options, fullName, *layerValue, &error)) {', added)
        self.assertIn('readValue(optionLayer.getConfig(), fullName, value.data);', removed)
        self.assertIn('readValue(options, fullName, *layerValue);', removed)
        self.assertIn('bool readOption(const Config& options, const RtxOptionLayer* layer);', patches.added_lines(patch, OPTION_H))
        api = patches.added_lines(patch, API)
        self.assertIn('if (!option->readOption(newSetting, option->getTargetLayer(dxvk::RtxOptionLayer::getUserLayer()))) {', api)
        self.assertIn('return REMIXAPI_ERROR_CODE_INVALID_ARGUMENTS;', api)

    def test_an_empty_value_through_the_api_stays_a_success(self):
        """Patch 0104: Config::findOption takes "" for no value, so readOption reads nothing for it; the Remix API
        answers success for it as before patch 0101 (the RTX package's Lua sets its session lists to "" often, and each
        call had printed a failure), and still refuses a value that fails to parse."""
        patch = patches.read(patches.one_patch(104))
        self.assertEqual(sorted(patches.file_blocks(patch)), [API])
        added, removed = patches.added_lines(patch, API), patches.removed_lines(patch, API)
        self.assertIn("const bool emptyValue = value[0] == '\\0';", added)
        self.assertIn('if (!option->readOption(newSetting, option->getTargetLayer(dxvk::RtxOptionLayer::getUserLayer())) '
                      '&& !emptyValue) {', added)
        self.assertIn('if (!option->readOption(newSetting, option->getTargetLayer(dxvk::RtxOptionLayer::getUserLayer()))) {',
                      removed)
        # Patch 0101's readOption returns false before reading for an option the config does not hold (upstream's
        # findOption, which an empty value fails): that is the case the API answers success for again.
        self.assertIn('if (!options.findOption(fullName.c_str())) {', patch_text())

    def test_meson_lists_the_header_and_both_unit_tests(self):
        patch = patch_text()
        self.assertIn("'rtx_render/rtx_mod_layer_policy.h',", patches.added_lines(patch, 'src/dxvk/meson.build'))
        tests = patches.added_lines(patch, 'tests/rtx/unit/meson.build')
        self.assertIn("executable('test_mod_layer_policy'", tests)
        self.assertIn("executable('test_mod_option_layer'", tests)
        manager_test = patches.postimage(patch, MANAGER_TEST)
        self.assertIn('RtxOptionManager::acquireModLayer(path, key, 1.0f, 0.1f) == nullptr', manager_test)
        self.assertIn('"\\\\\\\\host.invalid\\\\share\\\\opts.conf"', manager_test)

    def test_no_shipped_remix_mod_uses_logic_graphs(self):
        # The policy restricts what a Remix Logic graph's option layer may do; nothing the package ships has one.
        found = []
        for path in (REPO / 'packages').rglob('*'):
            if path.is_file() and path.suffix.lower() in ('.usda', '.usd', '.usdc'):
                data = path.read_bytes()
                if b'OmniGraph' in data or b'RtxOptionLayer' in data:
                    found.append(str(path.relative_to(REPO)))
        self.assertEqual(found, [])


if __name__ == '__main__':
    unittest.main()
