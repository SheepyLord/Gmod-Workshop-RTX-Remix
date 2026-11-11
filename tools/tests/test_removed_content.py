"""Content the user took out of the RTX package stays out of its inputs (packages/), also after a part is
imported again from its source repository, which still has it."""
import json
import unittest
from pathlib import Path

REPO = Path(__file__).resolve().parents[2]

# (part, paths in the part or prefixes ending in "*", the reason)
REMOVED = (
    ('fixes',
     ('garrysmod/garrysmod/addons/remixbinary/maps/gm_construct_rtx.*',
      'garrysmod/rtx-remix/mods/base_mod/maps/gm_construct_rtx.usda'),
     'the gm_construct_rtx map, beside the gm_construct RTX remaster, left players unsure which to use '
     '(the user, 2026-11-10; ADR 0154)'),
    ('fixes',
     ('garrysmod/garrysmod/addons/remixbinary/maps/gm_construct_in_flatgrass_rtx.*',),
     'the gm_construct_in_flatgrass_rtx map went for the same reason, beside the gm_construct and gm_flatgrass '
     'RTX remasters (the user, 2026-11-10; ADR 0155)'),
)
# a mod layer that must not list a removed file as a sublayer
LAYERS = {
    'fixes': {'garrysmod/rtx-remix/mods/base_mod/mod.usda': 'maps/gm_construct_rtx.usda'},
}


def matches(path: str, pattern: str) -> bool:
    return path.lower().startswith(pattern[:-1].lower()) if pattern.endswith('*') else path.lower() == pattern.lower()


class RemovedContentTests(unittest.TestCase):
    def test_removed_files_are_not_indexed_or_stored(self):
        for part, patterns, reason in REMOVED:
            index = json.loads((REPO / 'packages' / part / 'files.json').read_text(encoding='utf-8'))
            back = [p for p in index['files'] if any(matches(p, pat) for pat in patterns)]
            self.assertEqual(back, [], f'{part}: {reason}; remove these from the index again')
            for pattern in patterns:
                folder = REPO / 'packages' / part / Path(pattern).parent
                if folder.is_dir():
                    stem = Path(pattern).name
                    stored = [f.name for f in folder.iterdir()
                              if matches(f.name, stem) or matches(f.name, stem + '.xz')]
                    self.assertEqual(stored, [], f'{part}: {reason}; stored files left in {folder}')

    def test_no_layer_lists_a_removed_file(self):
        for part, layers in LAYERS.items():
            for layer, sublayer in layers.items():
                text = (REPO / 'packages' / part / layer).read_text(encoding='utf-8')
                self.assertNotIn(sublayer, text, f'{part}/{layer} still lists {sublayer}')


if __name__ == '__main__':
    unittest.main()
