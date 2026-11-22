"""ADR 0258: the Model Hotloader's library window brings the rows of the entries library.Add listed up to date (new rows,
rows of entries listed again) instead of building its whole list again, and shows exactly what a rebuild shows;
anything else still builds the list again.
Runs the shipped library.lua and ui.lua under LuaJIT with Derma, the disk and the native module instrumented."""
import os
from pathlib import Path
import shutil
import subprocess
import unittest

REPO = Path(__file__).resolve().parents[2]
LUA = REPO / 'packages/model-hotloader/mmd_hotloader/lua'
LUAJIT = shutil.which('luajit') or next((str(p) for p in [
    Path(os.environ.get('LOCALAPPDATA', '')) / 'Programs/LuaJIT/bin/luajit.exe'
] if p.is_file()), None)
SCENARIOS = ('record', 'rows_like_a_rebuild', 'views', 'empty_view', 'multi_selection', 'listed_again', 'rebuilds',
             'gui_scaler', 'random')


@unittest.skipUnless(LUAJIT, 'LuaJIT is not installed')
class LibraryRowsTests(unittest.TestCase):
    def test_scenarios(self):
        for scenario in SCENARIOS:
            with self.subTest(scenario=scenario):
                result = subprocess.run([LUAJIT, str(Path(__file__).with_name('hotloader_library_rows_harness.lua')),
                                         str(LUA / 'mmdhl'), scenario], cwd=REPO, capture_output=True,
                                        encoding='utf8', errors='replace', timeout=120)
                self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
                self.assertIn('PASS ' + scenario, result.stdout)


class LibraryRowsSourceTests(unittest.TestCase):
    def test_the_window_adds_rows_or_builds_its_list(self):
        ui = (LUA / 'mmdhl/ui.lua').read_text(encoding='utf8')
        think = ui[ui.index('function PANEL:Think()'):]
        think = think[:think.index('\nend\n')]
        self.assertIn('local added=self:AddedSince() if added then self:AddRows(added) else self:Refresh() end', think)
        refresh = ui[ui.index('function PANEL:Refresh()'):]
        refresh = refresh[:refresh.index('\nend\n')]
        self.assertIn('self.built={', refresh)
        self.assertIn('self.Models:Clear()', refresh)
        self.assertNotIn('self.Models:Clear()', ui[ui.index('function PANEL:AddRows('):ui.index('function PANEL:Refresh()')])

    def test_the_library_records_what_add_listed(self):
        library = (LUA / 'mmdhl/library.lua').read_text(encoding='utf8')
        add = library[library.index('function library.Add('):]
        add = add[:add.index('\nend\n')]
        self.assertIn('added[library.revision]=listed', add)
        self.assertIn('not seen[id]', add)
        refresh = library[library.index('function library.Refresh()'):]
        refresh = refresh[:refresh.index('\nend\n')]
        self.assertIn('library.added={}', refresh)

    def test_the_pack_probe_measures_both_updates(self):
        probe = (REPO / 'tools/qa/pack_install_probe.lua').read_text(encoding='utf8')
        self.assertIn('wrap_field(panel, "AddRows", "ui.Library.AddRows")', probe)
        self.assertIn('library_updates = P.updates', probe)
        session = (REPO / 'tools/qa/pack_install_session.py').read_text(encoding='utf8')
        self.assertIn("OVERRIDE = ('library.lua', 'workshop.lua', 'ui.lua')", session)


if __name__ == '__main__':
    unittest.main()
