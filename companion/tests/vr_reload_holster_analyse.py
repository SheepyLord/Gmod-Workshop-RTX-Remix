"""Describe native before/after holster evidence without substituting an SDK model."""
import argparse
import json
from pathlib import Path


def analyse(folder, baseline=False):
    rows = json.loads((folder / "reload.json").read_text(encoding="utf-8"))
    summary = json.loads((folder / "summary.json").read_text(encoding="utf-8"))
    receipt = json.loads((folder / "reload-receipt.json").read_text(encoding="utf-8"))
    restoration = json.loads((folder / "restoration.json").read_text(encoding="utf-8"))
    result = {"baseline": baseline, "classes": {}, "bug_reproduced": False}
    for cls in ("weapon_smg1", "weapon_pistol"):
        samples = [r for r in rows if r["kind"] == "holster-watch" and r["class"] == cls]
        empty = [r for r in samples if 2.4 <= r["time"] <= 2.9]
        holstered = [r for r in samples if r["active"] == "nlvr_hands" and 3 <= r["time"] < 7.5]
        returned = [r for r in samples if 7.7 <= r["time"] <= 8.1]
        loaded = [r for r in samples if 11.5 <= r["time"] <= 12.8]
        after = [r for r in samples if 13.4 <= r["time"] <= 14.5]
        duration = holstered[-1]["time"] - holstered[0]["time"] if holstered else 0
        refilled = any(r["clip"] > 0 for r in returned)
        checks = {"observed_empty": bool(empty) and all(r["clip"] == 0 for r in empty),
                  "hands_over_three_seconds": duration >= 3,
                  "returned_weapon": bool(returned) and all(r["active"] == cls for r in returned)}
        if not baseline:
            checks.update(no_holster_refill=bool(holstered + returned) and all(r["clip"] == 0 for r in holstered + returned),
                          reserve_preserved=bool(empty) and all(r["reserve"] == empty[-1]["reserve"] for r in holstered + returned),
                          timer_fresh=bool(holstered) and all(-.75 <= r.get("holster", -100) <= .1 for r in holstered),
                          inserted_and_fired=bool(after) and all(r.get("reload", {}).get("last_insertion") == "inserted" for r in after)
                          and bool(loaded) and after[-1]["clip"] < max(r["clip"] for r in loaded)
                          and after[-1]["reserve"] == loaded[-1]["reserve"])
        result["classes"][cls] = {"checks": checks, "refilled_on_return": refilled, "holstered_seconds": duration,
            "empty": empty[-1] if empty else None, "returned": returned[-1] if returned else None,
            "after": after[-1] if after else None}
        result["bug_reproduced"] |= refilled
    result["success"] = summary["success"] and receipt["success"] and restoration["clean"] and all(
        all(c["checks"].values()) for c in result["classes"].values())
    (folder / "holster-checks.json").write_text(json.dumps(result, indent=2), encoding="utf-8")
    return result


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("folder", type=Path)
    parser.add_argument("--baseline", action="store_true")
    args = parser.parse_args()
    result = analyse(args.folder, args.baseline)
    print(json.dumps({"success": result["success"], "baseline": result["baseline"],
                      "bug_reproduced": result["bug_reproduced"],
                      "checks": {k: v["checks"] for k, v in result["classes"].items()}}, indent=2))
    raise SystemExit(0 if result["success"] else 1)
