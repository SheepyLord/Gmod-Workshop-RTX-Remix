"""Game emission (ADR 0138): the fixes' ninth patch's complete files are the patch applied, and the shipped USD
writer enables emission only for imported game materials with an emission map."""
import json
from pathlib import Path
import re
import unittest

from test_endfield_maps import REPO, SKINNING, apply, text

FOLDER = SKINNING / 'game-emission'
PATCH = FOLDER / 'game-emission.patch'
USDA = 'source/material_pipeline/to_pbr/usda.cpp'
TEST = 'tests/to_pbr_test.cpp'


class GameEmissionTests(unittest.TestCase):
    def test_complete_files_are_the_patch_applied(self):
        """The folder's usda.cpp and to_pbr_test.cpp are autopbr's (unchanged by the patches between) with
        game-emission.patch applied, and pins.json builds the module with it."""
        patch = PATCH.read_text(encoding='utf-8')
        self.assertEqual(re.findall(r'^diff --git a/(\S+) b/\1$', patch, re.M), [USDA, TEST])
        for path in (USDA, TEST):
            self.assertEqual(apply(patch, path, text(SKINNING / 'autopbr' / path)), text(FOLDER / path), path)
        pins = json.loads((REPO / 'tools/ci/pins.json').read_text(encoding='utf-8'))['fixes']
        self.assertIn(PATCH.relative_to(REPO).as_posix(), pins['patches'])

    def test_only_game_materials_with_emission_maps_enable_it(self):
        """In WriteOpaqueMaterial the flag sits inside the emission-map block, behind info.importedGame, once."""
        source = text(FOLDER / USDA)
        body = source.split('void WriteOpaqueMaterial(', 1)[1].split('\nvoid ', 1)[0].split('\nstatic ', 1)[0]
        block = body.split('if (!info.emissivePath.empty()) {', 1)[1].split('\n    }\n', 1)[0]
        self.assertEqual(source.count('enable_emission'), 1)
        self.assertRegex(block, r'if \(info\.importedGame\) stream << "\s+bool inputs:enable_emission = 1\\n";')
        regression = text(FOLDER / TEST)
        for words in ('gameGlow.importedGame=true', 'bool inputs:enable_emission = 1', 'find("enable_emission")==std::string::npos'):
            self.assertIn(words, regression)


if __name__ == '__main__':
    unittest.main()
