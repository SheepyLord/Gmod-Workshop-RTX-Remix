"""Measure same-frame room camera error, temporal lag and tick stepping from real CalcView rows."""
from __future__ import annotations
import argparse
import bisect
import csv
import json
import math
from pathlib import Path
import statistics


def percentile(values, fraction):
    ordered = sorted(values)
    return ordered[min(len(ordered) - 1, math.ceil(fraction * len(ordered)) - 1)]


def analyse(folder):
    summary = json.loads((folder / "summary.json").read_text(encoding="utf-8"))
    frames = [f for r in summary["records"] if r.get("kind") == "L-latency" for f in r["frames"]]
    frames.sort(key=lambda f: (f["t"], f["frame"]))
    times = [f["t"] for f in frames]
    result = {"native_success": summary["success"], "frames": len(frames), "segments": {}}
    for name, start, end, speed in (("slow", 5, 7, 20), ("fast", 9, 11, 60), ("sway", 13, 16, None)):
        rows = [f for f in frames if start + 0.15 <= f["t"] <= end - 0.1]
        assert len(rows) >= 50, "missing rendered-frame rows: " + name
        errors = [math.hypot(f["ideal"][0] - f["camera"][0], f["ideal"][1] - f["camera"][1]) for f in rows]
        camera_steps = [math.dist(a["camera"][:2], b["camera"][:2]) for a, b in zip(rows, rows[1:])]
        ideal_steps = [math.dist(a["ideal"][:2], b["ideal"][:2]) for a, b in zip(rows, rows[1:])]
        moving = [(c, i) for c, i in zip(camera_steps, ideal_steps) if i > 0.0001]
        metrics = {"frames": len(rows), "mean_error_units": statistics.mean(errors), "p95_error_units": percentile(errors, .95),
                   "max_error_units": max(errors), "mean_step_units": statistics.mean(camera_steps), "p95_step_units": percentile(camera_steps, .95),
                   "max_step_units": max(camera_steps), "ideal_p95_step_units": percentile(ideal_steps, .95),
                   "zero_steps_while_tracking_moves": sum(c < 0.00001 for c, i in moving), "moving_intervals": len(moving),
                   "step_error_max_units": max(abs(c - i) for c, i in moving)}
        if speed:
            metrics["mean_lag_ms"] = statistics.mean((f["ideal"][1] - f["camera"][1]) / speed * 1000 for f in rows)
            metrics["p95_abs_lag_ms"] = percentile(errors, .95) / speed * 1000
        else:
            def ideal_at(t):
                j = max(1, min(len(frames) - 1, bisect.bisect_left(times, t)))
                a, b = frames[j - 1], frames[j]
                u = (t - a["t"]) / max(.0000001, b["t"] - a["t"])
                return a["ideal"][1] + u * (b["ideal"][1] - a["ideal"][1])
            def mse(lag):
                return statistics.mean((f["camera"][1] - ideal_at(f["t"] - lag / 1000)) ** 2 for f in rows)
            lag = min((n / 4 for n in range(-400, 601)), key=mse)
            metrics["cross_correlation_lag_ms"] = lag
            metrics["aligned_rmse_units"] = math.sqrt(mse(lag))
        result["segments"][name] = metrics
    tilted = [f for f in frames if 18.3 < f["t"] < 19.7]
    result["roll"] = {key: max(abs(f.get(key) or 0) for f in tilted) for key in ("head_roll", "camera_roll", "command_roll", "player_roll")}
    result["off_roll"] = [{k: r.get(k) for k in ("player_roll", "flat_view_roll")} for r in summary["records"] if r.get("kind") == "L-roll-off"]
    with (folder / "latency-frames.csv").open("w", newline="", encoding="utf-8") as stream:
        writer = csv.writer(stream)
        writer.writerow(("time", "frame", "sequence", "tick", "camera_x", "camera_y", "camera_z", "ideal_x", "ideal_y", "ideal_z", "head_roll", "command_roll", "player_roll"))
        for f in frames:
            writer.writerow([f["t"], f["frame"], f["sequence"], f["tick"], *f["camera"], *f["ideal"], f["head_roll"], f.get("command_roll"), f.get("player_roll")])
    (folder / "latency-analysis.json").write_text(json.dumps(result, indent=2), encoding="utf-8")
    return result


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("folder", type=Path)
    parser.add_argument("--require-fixed", action="store_true")
    args = parser.parse_args()
    result = analyse(args.folder)
    result["same_frame_pass"] = all(s["max_error_units"] < .05 and s["step_error_max_units"] < .05 and s["zero_steps_while_tracking_moves"] == 0 for s in result["segments"].values())
    result["roll_pass"] = result["roll"]["camera_roll"] > 20 and result["roll"]["command_roll"] == 0 and result["roll"]["player_roll"] == 0
    (args.folder / "latency-analysis.json").write_text(json.dumps(result, indent=2), encoding="utf-8")
    print(json.dumps(result, indent=2))
    return 0 if result["native_success"] and (not args.require_fixed or result["same_frame_pass"] and result["roll_pass"]) else 1


if __name__ == "__main__":
    raise SystemExit(main())
