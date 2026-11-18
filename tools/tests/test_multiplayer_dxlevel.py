"""ADR 0246: the DirectX level a server sees from an RTX start (the companion's nativeloader/prelude/dxlevel.lua),
run under LuaJIT in a stand-in client realm by dxlevel_harness.lua."""
import os
from pathlib import Path
import shutil
import subprocess
import unittest

REPO = Path(__file__).resolve().parents[2]
PRELUDE = REPO / "companion/nativeloader/lua/nativeloader/prelude/dxlevel.lua"
LUAJIT = shutil.which("luajit") or next((str(p) for p in [
    Path(os.environ.get("LOCALAPPDATA", "")) / "Programs/LuaJIT/bin/luajit.exe"
] if p.is_file()), None)


@unittest.skipUnless(LUAJIT, "LuaJIT is not installed")
class MultiplayerDXLevelTests(unittest.TestCase):
    def run_case(self, scenario):
        done = subprocess.run([LUAJIT, str(Path(__file__).with_name("dxlevel_harness.lua")), str(PRELUDE), scenario],
                              cwd=REPO, capture_output=True, encoding="utf-8", errors="replace", timeout=20)
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        self.assertIn("PASS " + scenario, done.stdout)

    def test_multiplayer_reports_the_level_the_game_was_started_at(self):
        self.run_case("multiplayer")

    def test_single_player_keeps_the_engines_level(self):
        self.run_case("single_player")

    def test_the_render_guards_route_after_includes_init(self):
        self.run_case("guard_route")

    def test_never_lower_than_the_engine_and_the_same_as_the_mat_dxlevel_convar(self):
        for scenario in ("never_lower", "agrees"):
            with self.subTest(scenario=scenario):
                self.run_case(scenario)

    def test_unreadable_or_missing_settings_keep_the_engines_level(self):
        for scenario in ("bad_values", "missing_dxlevel", "switch_error"):
            with self.subTest(scenario=scenario):
                self.run_case(scenario)

    def test_installed_once(self):
        self.run_case("idempotent")

    def test_server_and_menu_realms_and_a_realm_without_the_engine_functions_are_untouched(self):
        for scenario in ("realm_server", "realm_menu", "missing_functions"):
            with self.subTest(scenario=scenario):
                self.run_case(scenario)

    def test_metamethods_a_server_set_on_the_globals_do_not_stop_it(self):
        self.run_case("server_metatable")


if __name__ == "__main__":
    unittest.main()
