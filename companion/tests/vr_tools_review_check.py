"""Native review-only assertions, additional to the ordinary full features checks."""
import math


def evaluate(records):
    from vr_tools_check import vector, angle_error
    checks, measurements = {}, {}
    clients = [r for r in records if r["name"] == "review-client"]
    samples = [r for r in records if r["name"] == "review-sample"]
    targets = [r for r in records if r["name"] == "target" and r.get("purpose") == "physgun"]
    checks["offcentre_gravity_prop"] = bool(targets) and all(r.get("gravity") is True and
        "props_c17" in r.get("model", "") and math.sqrt(sum(x*x for x in vector(r["mass_center"]))) > 0.1 for r in targets)
    for phase, lo, hi in (("freeze-up", 75.3, 76.4), ("release-down", 85.3, 86.9), ("release-diagonal", 95.3, 96.9)):
        rows = [r for r in clients if lo <= r.get("time", -1) <= hi]
        checks[phase + "_owned"] = len(rows) >= 5 and all(r.get("stick_owner") == "tools" for r in rows)
        checks[phase + "_no_locomotion_edge"] = bool(rows) and all(r.get("arc_visible") == 0 and
            not r.get("movement", {}).get("crouch_toggle") for r in rows)
        yaws = [r.get("movement", {}).get("space", {}).get("yaw") for r in rows]
        yaws = [x for x in yaws if isinstance(x, (int, float))]
        checks[phase + "_no_turn"] = len(yaws) >= 5 and max(yaws) - min(yaws) <= 0.1
        measurements[phase] = {"rows": len(rows), "yaw_range": max(yaws)-min(yaws) if yaws else None}
    held_use = [r for r in records if r["name"] == "review-use-held"]
    final_use = [r for r in records if r["name"] == "review-use-final"]
    checks["wheel_held_trigger_does_not_use"] = bool(held_use) and all(r.get("use_calls") == 0 for r in held_use)
    checks["new_trigger_can_use"] = bool(final_use) and final_use[-1].get("use_calls") == 1
    for phase in ("tracking", "hand", "controller", "creation", "stop"):
        drops = [r for r in records if r["name"] == "force-drop" and r.get("phase") == phase]
        confirms = [r for r in records if r["name"] == "force-drop-confirm" and r.get("phase") == phase]
        checks[phase + "_native_forced_drop"] = any(r.get("before") is True for r in drops) and bool(confirms) and all(r.get("held") is False for r in confirms)
        if drops:
            time = drops[0]["time"]
            after = [r for r in samples if r.get("phase") == phase and time + 0.3 <= r.get("time", -1) <= time + 1.2]
        else:
            after = []
        checks[phase + "_no_regrab"] = len(after) >= 3 and all(r.get("held") is False for r in after)
        measurements[phase] = {"drop_calls": len(drops), "confirmation": [r.get("held") for r in confirms], "sustained_rows": len(after)}
    deaths = [r for r in records if r["name"] == "review-before-fault" and r.get("fault") == "death"]
    dead_after = [r for r in records if r["name"] == "review-fault-confirm" and r.get("fault") == "death"]
    checks["death_releases_native_hold"] = bool(deaths) and deaths[-1].get("held") is True and bool(dead_after) and dead_after[-1].get("held") is False
    params = [r for r in records if r["name"] == "review-shadow-parameters"]
    checks["actual_server_rotation_limits"] = len(params) >= 5 and all(r["angular"] == r["server_angular"] and
        r["damping"] == r["server_damping"] and abs(r["arrive"]-max(0.001,r["server_arrive"])) < 0.000001 and
        r.get("factor") is not None and r.get("factor") == r.get("server_factor") for r in params)
    speed_rows = [r for r in samples if r.get("phase") == "snap" and r.get("command", {}).get("buttons", 0) & 131072 and
                  r.get("hand") and angle_error(r["hand"]["ang"], [0,37,0]) < 0.1][-5:]
    free_rows = [r for r in samples if r.get("phase") == "snap" and not r.get("command", {}).get("buttons", 0) & 131072 and
                 r.get("hand") and angle_error(r["hand"]["ang"], [0,37,0]) < 0.1][-5:]
    checks["speed_snap"] = len(speed_rows) >= 3 and max(angle_error(r["ang"], [0,45,0]) for r in speed_rows) <= 5
    checks["speed_release_continuous"] = len(free_rows) >= 3 and max(angle_error(r["ang"], [0,37,0]) for r in free_rows) <= 5
    measurements["snap"] = {"speed_angles": [r["ang"] for r in speed_rows], "released_angles": [r["ang"] for r in free_rows]}
    refused = [r for r in records if r["name"] == "review-refusal-result" and r.get("switches") == 1]
    notices = [r for r in clients if 145 <= r.get("time", -1) <= 145.8 and r.get("tools", {}).get("wheel", {}).get("notice")]
    checks["one_refused_switch_with_feedback"] = bool(refused) and bool(notices)
    peers = [r.get("peers", {}) for r in records if r["name"] == "beam-draw"]
    checks["native_beam_peer_hooks"] = len(peers) >= 10 and all(r.get("one", 0) == r.get("two", 0) and r.get("one", 0) > 0 for r in peers)
    return checks, measurements
