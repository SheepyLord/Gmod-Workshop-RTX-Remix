"""S's short simulated scaffold/page acceptance, on M's production-driver UI fixture."""
from pathlib import Path
import hashlib
import json
import sys
import vr_ui_poc as ui

SOURCE = Path(__file__).with_suffix(".lua").read_bytes()
ORIGINAL = ui.driver.lua_script
LOCK = ui.driver.ExclusiveLock


class ScaffoldLock(LOCK):
    def __init__(self, path, task, timeout=7200):
        super().__init__(path, "VR-V4-S", timeout)


def script(path, config):
    ORIGINAL(path, config)
    with path.open("a", encoding="utf-8") as stream:
        stream.write("\ndo\n" + SOURCE.decode("utf-8") + "\nend\n")


def main(argv=None):
    args = list(sys.argv[1:] if argv is None else argv)
    # S never needs a compositor; M's fixture supplies the standard no-SDK timeline and settings capture.
    if "--simulate" not in args:
        args.append("--simulate")
    if "--settings-probe" not in args:
        args.append("--settings-probe")
    ui.driver.lua_script = script
    ui.driver.ExclusiveLock = ScaffoldLock
    result = ui.main(args)
    folder = Path(args[args.index("--evidence") + 1])
    if not (folder / "summary.json").is_file():
        return result or 1
    summary = json.loads((folder / "summary.json").read_text(encoding="utf-8"))
    records = [r for r in summary["records"] if r.get("kind") == "v4s"]
    starts = [r for r in records if r["name"] == "started"]
    page = next((r for r in records if r["name"] == "weapons-page"), {})
    modules = {m["name"]: m for m in starts[0]["modules"]} if starts else {}
    checks = {"module_slots": all(modules.get(n, {}).get("active") and modules[n]["order"] == order
                                   for n, order in (("weapons", 44), ("reload", 46), ("tools", 48))),
              "core_settings": bool(starts) and starts[0]["settings"] == {
                  "physical_reload": 1, "foregrip": 1, "ammo_counter": 1, "gun_angle": 0},
              "page_canvas": (page.get("width"), page.get("height")) == (1283, 963),
              "weapons_group_scrolled": page.get("scroll", 0) > 0,
              "gui_scaler": page.get("gui_scale") is not None,
              "stopped": any(r["name"] == "stopped" and r["global_absent"] for r in records)}
    receipt = {"checks": checks, "records": records, "lua_sha256": hashlib.sha256(SOURCE).hexdigest(),
               "success": not result and all(checks.values())}
    ui.driver.write_json(folder / "scaffold-acceptance.json", receipt)
    (folder / "scaffold-fixture.lua.snapshot").write_bytes(SOURCE)
    return 0 if receipt["success"] else 1


if __name__ == "__main__":
    sys.exit(main())
