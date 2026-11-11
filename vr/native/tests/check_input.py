"""Cross-check the shipped SteamVR Input manifest, bindings and native action readers."""
import json
import hashlib
from pathlib import Path
import re
import sys
import unittest


ROOT = Path(__file__).resolve().parents[2]


def validate_installed_profiles(steamvr):
    """Read-only optional check against Valve's installed physical input-source names."""
    files = {"knuckles": "indexcontroller/resources/input/index_controller_profile.json",
             "oculus_touch": "oculus/resources/input/touch_profile.json",
             "vive_controller": "htc/resources/input/vive_controller_profile.json"}
    manifest = json.loads((ROOT / "input/nlvr_actions.json").read_text(encoding="utf-8"))
    report = []
    for default in manifest["default_bindings"]:
        profile_path = Path(steamvr) / "drivers" / files[default["controller_type"]]
        raw = profile_path.read_bytes()
        profile = json.loads(raw)
        assert profile["controller_type"] == default["controller_type"]
        sources = profile["input_source"]
        binding = json.loads((ROOT / "input" / default["binding_url"]).read_text(encoding="utf-8"))
        checked = 0
        for main in binding["bindings"].values():
            for item in main["sources"] + main["haptics"] + main["skeleton"]:
                side, path = re.fullmatch(r"/user/hand/(left|right)(/.*)", item["path"]).groups()
                physical = sources[path]
                assert physical.get("side", side) == side, (item["path"], "wrong hand")
                mode = item.get("mode")
                compatible = {"button": {"button", "trigger", "joystick", "trackpad"},
                              "trigger": {"trigger"}, "joystick": {"joystick"},
                              "trackpad": {"trackpad"}, "grab": {"force_sensor", "trigger"},
                              "force_sensor": {"force_sensor", "trigger"}}
                if mode:
                    assert physical["type"] in compatible[mode], (item["path"], mode, physical["type"])
                    if mode == "force_sensor":
                        assert physical.get("force"), (item["path"], "no force component")
                checked += 1
        report.append({"controller": default["controller_type"], "profile": str(profile_path),
                       "profile_sha256": hashlib.sha256(raw).hexdigest(), "sources_checked": checked})
    return report


class InputFiles(unittest.TestCase):
    def test_manifest_matches_native_readers(self):
        manifest = json.loads((ROOT / "input/nlvr_actions.json").read_text(encoding="utf-8"))
        actions = {a["name"]: a for a in manifest["actions"]}
        self.assertEqual(len(actions), len(manifest["actions"]), "duplicate action names")
        native = (ROOT / "native/input_actions.h").read_text(encoding="utf-8")
        specs = re.findall(r'\{"(\w+)",\s*\x27([bvsh])\x27(?:,\d+)?\}', native)
        self.assertEqual(len(specs), 20)
        native_paths = set()
        for name, kind in specs:
            path = f'/actions/main/{"out" if kind == "h" else "in"}/{name}'
            native_paths.add(path)
            action = actions[path]
            allowed = {"b": {"boolean"}, "v": {"vector1", "vector2"},
                       "s": {"skeleton"}, "h": {"vibration"}}[kind]
            self.assertIn(action["type"], allowed)
            if kind == "s":
                self.assertEqual(action["skeleton"], "/skeleton/hand/" + name.split("_")[0])
        self.assertEqual(native_paths, set(actions))
        self.assertEqual(manifest["action_sets"], [{"name": "/actions/main", "usage": "leftright"}])
        labels = manifest["localization"][0]
        for path in actions:
            self.assertTrue(labels[path])

    def test_bindings_reference_existing_correctly_typed_actions(self):
        manifest = json.loads((ROOT / "input/nlvr_actions.json").read_text(encoding="utf-8"))
        actions = {a["name"]: a for a in manifest["actions"]}
        controllers = set()
        for default in manifest["default_bindings"]:
            name = default["binding_url"]
            self.assertEqual(Path(name).name, name, "binding must be beside the manifest")
            binding = json.loads((ROOT / "input" / name).read_text(encoding="utf-8"))
            controller = default["controller_type"]
            self.assertEqual(binding["controller_type"], controller)
            controllers.add(controller)
            main = binding["bindings"]["/actions/main"]
            outputs = set()
            for source in main["sources"]:
                self.assertTrue(source["path"].startswith("/user/hand/"))
                for component, value in source["inputs"].items():
                    action = actions[value["output"]]
                    outputs.add(action["name"])
                    expected = {"click": "boolean", "grab": "boolean", "pull": "vector1",
                                "force": "vector1", "position": "vector2"}[component]
                    self.assertEqual(action["type"], expected)
            for item in main["haptics"]:
                self.assertEqual(actions[item["output"]]["type"], "vibration")
                self.assertTrue(item["path"].endswith("/output/haptic"))
            for item in main["skeleton"]:
                self.assertEqual(actions[item["output"]]["type"], "skeleton")
            for hand in ("left", "right"):
                for suffix in ("grip", "trigger", "stick", "stick_click", "b"):
                    self.assertIn(f"/actions/main/in/{hand}_{suffix}", outputs)
                if controller != "vive_controller":
                    self.assertIn(f"/actions/main/in/{hand}_a", outputs)
        self.assertEqual(controllers, {"knuckles", "oculus_touch", "vive_controller"})

    def test_touch_uses_physical_joystick_and_left_xy_buttons(self):
        # Valve's touch_profile.json distinguishes the left X/Y buttons from right A/B.
        binding = json.loads((ROOT / "input/nlvr_bindings_touch.json").read_text(encoding="utf-8"))
        sources = binding["bindings"]["/actions/main"]["sources"]
        by_action = {value["output"].rsplit("/", 1)[1]: item["path"]
                     for item in sources for value in item["inputs"].values()}
        for hand in ("left", "right"):
            self.assertEqual(by_action[hand + "_stick"], f"/user/hand/{hand}/input/joystick")
        self.assertEqual(by_action["left_a"], "/user/hand/left/input/x")
        self.assertEqual(by_action["left_b"], "/user/hand/left/input/y")
        self.assertEqual(by_action["right_a"], "/user/hand/right/input/a")
        self.assertEqual(by_action["right_b"], "/user/hand/right/input/b")


if __name__ == "__main__":
    if len(sys.argv) == 3 and sys.argv[1] == "--profiles":
        print(json.dumps(validate_installed_profiles(sys.argv[2]), indent=2))
    else:
        unittest.main()
