"""Compare render motion and engine interpolation with same-process authoritative movement."""
from __future__ import annotations
import argparse
import bisect
import csv
import json
import math
from pathlib import Path
import statistics


def pct(values, q):
    a = sorted(values)
    return a[min(len(a) - 1, max(0, math.ceil(q * len(a)) - 1))]


def check(folder, intervals=None, stop_window=(10,11)):
    summary = json.loads((folder / "summary.json").read_text(encoding="utf-8"))
    records = summary["records"]
    frames = sorted([f for r in records if r.get("kind") == "L-motion" for f in r["frames"]], key=lambda f: f["time"])
    server = sorted([f for r in records if r.get("kind") == "L-server-motion" for f in r["frames"]], key=lambda f: f["time"])
    stamps = [f["time"] for f in server]
    result = {"native_success": summary["success"], "frames": len(frames), "server_samples": len(server), "segments": {}}
    for name, start, end, speed in (intervals or (("walk", 5, 7, 200), ("sprint", 9, 10, 400), ("flight", 12, 14, 400))):
        window = [f for f in frames if start + .3 <= f["t"] <= end - .1]
        assert len(window) >= 20, name + ": missing render frames"
        result["segments"][name] = {}
        for source in ("camera", "engine", "base", "network"):
            if any(f.get(source) is None for f in window):
                continue
            pairs = list(zip(window, window[1:]))
            steps = [b[source][0] - a[source][0] for a, b in pairs]
            dt = [b["time"] - a["time"] for a, b in pairs]
            mean_dt = statistics.mean(dt)
            normalized = [s / interval * mean_dt for s, interval in zip(steps, dt)]
            lags = []
            for f in window:
                s = server[max(0, bisect.bisect_right(stamps, f["time"]) - 1)]
                lags.append((s["origin"][0] - f[source][0]) / speed * 1000)
            mean = statistics.mean(steps)
            norm_mean = statistics.mean(normalized)
            result["segments"][name][source] = {
                "frames": len(window), "mean_step": mean, "step_sd": statistics.pstdev(steps),
                "step_min": min(steps), "step_max": max(steps), "step_p05": pct(steps, .05), "step_p95": pct(steps, .95),
                "raw_spread_percent": (pct(steps, .95) - pct(steps, .05)) / mean * 100,
                "normalized_spread_percent": (pct(normalized, .95) - pct(normalized, .05)) / norm_mean * 100,
                "normalized_sd_percent": statistics.pstdev(normalized) / norm_mean * 100,
                "near_zero_steps": sum(abs(s) < .0001 for s in steps),
                "lag_mean_ms": statistics.mean(lags), "lag_p95_ms": pct(lags, .95),
                "mean_render_interval_ms": mean_dt * 1000}
    stop = [f for f in frames if stop_window[0] <= f["t"] <= stop_window[1]]
    result["sprint_stop"] = {source: max([max(0, a[source][0] - b[source][0]) for a, b in zip(stop, stop[1:])], default=0)
                             for source in ("camera", "engine", "base")}
    with (folder / "motion-frames.csv").open("w", newline="", encoding="utf-8") as stream:
        w = csv.writer(stream)
        w.writerow(("time", "game_time", "timeline", "frame", "camera_x", "engine_x", "base_x", "network_x"))
        for f in frames:
            w.writerow((f["time"], f["game_time"], f["t"], f["frame"], f["camera"][0], f["engine"][0], f["base"][0], (f.get("network") or [None])[0]))
    (folder / "motion-analysis.json").write_text(json.dumps(result, indent=2), encoding="utf-8")
    return result


def main():
    p = argparse.ArgumentParser(description=__doc__)
    p.add_argument("folder", type=Path)
    p.add_argument("--require-smooth", action="store_true")
    a = p.parse_args()
    r = check(a.folder)
    r["smooth_pass"] = all(s["camera"]["normalized_spread_percent"] <= 10 for s in r["segments"].values()) and r["sprint_stop"]["camera"] < .1
    (a.folder / "motion-analysis.json").write_text(json.dumps(r, indent=2), encoding="utf-8")
    print(json.dumps(r, indent=2))
    return 0 if r["native_success"] and (not a.require_smooth or r["smooth_pass"]) else 1


if __name__ == "__main__":
    raise SystemExit(main())
