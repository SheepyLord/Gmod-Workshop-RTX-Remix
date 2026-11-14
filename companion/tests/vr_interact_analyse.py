"""Reduce task P's retained server records to measured, reviewable V3 checks."""
from pathlib import Path
import argparse
import json
import math
import re


def vector(value):
    if isinstance(value, dict):
        return tuple(float(value[key]) for key in ("x", "y", "z"))
    if isinstance(value, str):
        return tuple(float(x) for x in re.findall(r"[-+]?\d+(?:\.\d+)?(?:[eE][-+]?\d+)?", value))
    return tuple(value) if value is not None else (0., 0., 0.)


def distance(a, b):
    return math.sqrt(sum((x-y)**2 for x, y in zip(vector(a), vector(b))))


# V8 (ADR 0203): a 250 kg crate lags while the hand's motion starts and stops, at the hand's strength, then follows;
# V3's spring kept it over 3 units for a whole second. Over 1 unit for at least 0.1 s (seven ticks, so never a one-tick
# spike) is the V8 hold's perceptible weight. The probe measures it every tick (`heavy`): the lag windows are shorter
# than its 0.25 s samples, which only the sample-based fallback below uses.
HEAVY_LAG_UNITS, HEAVY_LAG_SECONDS = 1.0, 0.1


def axes(angles):
    """Source's forward, left and up of an angle (pitch, yaw, roll in degrees)."""
    p, y, r = (math.radians(v) for v in vector(angles))
    forward = (math.cos(p)*math.cos(y), math.cos(p)*math.sin(y), -math.sin(p))
    right = (-math.sin(r)*math.sin(p)*math.cos(y)+math.cos(r)*math.sin(y),
             -math.sin(r)*math.sin(p)*math.sin(y)-math.cos(r)*math.cos(y), -math.sin(r)*math.cos(p))
    up = (math.cos(r)*math.sin(p)*math.cos(y)+math.sin(r)*math.sin(y),
          math.cos(r)*math.sin(p)*math.sin(y)-math.sin(r)*math.cos(y), math.cos(r)*math.cos(p))
    return forward, tuple(-v for v in right), up


def turn_degrees(a, b):
    """The rotation between two orientations, in degrees."""
    fa, la, ua = axes(a)
    fb, lb, ub = axes(b)
    trace = sum(x*y for x, y in zip(fa, fb)) + sum(x*y for x, y in zip(la, lb)) + sum(x*y for x, y in zip(ua, ub))
    return math.degrees(math.acos(max(-1.0, min(1.0, (trace-1)/2))))


def v8_checks(records, measure):
    """V8's phases: the wrist turns a hold, two hands hold one plank, the trigger freezes and frees, a bone freezes."""
    def rows(phase):
        return sorted((r for r in records if r.get("phase") == phase and r.get("kind") == "sample"), key=lambda r: r["time"])

    def at(rows_, low, high):
        return next((r for r in rows_ if low < r["time"] < high and r.get("v8")), None)

    p = rows(14)
    worst = (p[-1].get("v8") or {}).get("worst") or {} if p else {}
    measure("v8_turn_held_samples", sum(bool(r["right"]["held"]) for r in p), sum(bool(r["right"]["held"]) for r in p) >= 12)
    hold_error, hold_angle = worst.get("hold_error"), worst.get("hold_angle")
    measure("v8_turn_worst_error_units", hold_error, hold_error is not None and hold_error < 1.5)
    measure("v8_turn_worst_angle_degrees", hold_angle, hold_angle is not None and hold_angle < 6)
    before, after = at(p, 2.6, 3.0), at(p, 4.6, 5.1)
    turned = turn_degrees(before["v8"]["ang"], after["v8"]["ang"]) if before and after and before["v8"].get("ang") and after["v8"].get("ang") else None
    measure("v8_turn_body_degrees", turned, turned is not None and abs(turned-90) < 8)
    p = rows(15)
    both = [r for r in p if r["right"]["held"] and r["v8"].get("left_held") == r["right"]["held"]]
    measure("v8_pair_held_samples", len(both), len(both) >= 12)
    measure("v8_pair_frame", any(r["v8"].get("pair") for r in both), any(r["v8"].get("pair") for r in both))
    start, settled = at(p, 2.2, 2.8), at(p, 2.8, 3.05)
    jump = distance(settled["position"], start["position"]) if start and settled and start.get("position") and settled.get("position") else None
    measure("v8_pair_grab_jump_units", jump, jump is not None and jump < 2)
    raised = at(p, 4.0, 4.5)
    rise = vector(raised["position"])[2]-vector(settled["position"])[2] if raised and settled and raised.get("position") else None
    measure("v8_pair_rise_units", rise, rise is not None and abs(rise-8) < 2.5)
    # The timeline holds the tilted plank level from 4.6 to 5.2 s and turns both wrists from 5.2 to 5.8 s (V8 run 2's
    # first windows sat inside the turn and read 3.9 of its 24.9 degrees).
    level, rolled = at(p, 4.75, 5.15), at(p, 6.0, 6.45)
    roll = turn_degrees(level["v8"]["ang"], rolled["v8"]["ang"]) if level and rolled and level["v8"].get("ang") and rolled["v8"].get("ang") else None
    measure("v8_pair_roll_degrees", roll, roll is not None and abs(roll-25) < 6)
    pair_worst = (p[-1].get("v8") or {}).get("worst") or {} if p else {}
    measure("v8_pair_worst_error_units", pair_worst.get("hold_error"), pair_worst.get("hold_error") is not None and pair_worst["hold_error"] < 2.5)
    p = rows(16)
    held_first = any(r["right"]["held"] for r in p if 2.5 < r["time"] < 3.0)
    frozen = [r for r in p if 3.2 < r["time"] < 4.4]
    frozen_ok = bool(frozen) and all(not r["right"]["held"] and r["v8"].get("motion") == [False] for r in frozen)
    measure("v8_freeze_frozen_samples", len(frozen), held_first and frozen_ok)
    still = max((distance(r.get("position"), frozen[0].get("position")) for r in frozen if r.get("position")), default=None) if frozen else None
    measure("v8_freeze_stays_units", still, still is not None and still < 0.5)
    freed = [r for r in p if 5.3 < r["time"] < 6.5]
    freed_ok = bool(freed) and all(r["right"]["held"] and r["v8"].get("motion") == [True] for r in freed)
    measure("v8_unfreeze_held_samples", len(freed), freed_ok)
    carried = distance(freed[-1].get("position"), freed[0].get("position")) if len(freed) > 1 else None
    measure("v8_unfreeze_carried_units", carried, carried is not None and carried > 6)
    p = rows(17)
    bone = [r for r in p if 3.4 < r["time"] < 5 and r.get("v8", {}).get("motion")]
    one = bool(bone) and all(r["v8"]["motion"].count(False) == 1 and len(r["v8"]["motion"]) > 1 for r in bone)
    measure("v8_freeze_one_bone", [r["v8"]["motion"].count(False) for r in bone[:1]], one)
    client = [r for r in records if r.get("kind") == "v8-client"]
    drawn = [r for r in client if r.get("mode") == "held"]
    gaps = [distance(r.get("drawn"), r.get("physics")) for r in drawn if r.get("drawn") and r.get("physics") and r.get("tracking")]
    measure("v8_drawn_at_hand_samples", len(drawn), len(drawn) >= 4)
    measure("v8_drawn_vs_physics_units", max(gaps, default=None), bool(gaps) and max(gaps) < 2.5)


FG_CHECKS = ("v8_fg_target_switch", "v8_fg_restored", "v8_fg_page_line")


def fg_checks(records, measure):
    """The --fg-check records: Frame generation off doubles Auto's target, back restores it and the setting."""
    states = {r.get("state"): r for r in records if r.get("kind") == "v8-frame-generation"}
    on, off, back = states.get("on"), states.get("off"), states.get("restored")
    targets = [r.get("target") if r else None for r in (on, off, back)]
    switched = all(isinstance(t, (int, float)) for t in targets[:2]) and abs(targets[1] - 2 * targets[0]) < 0.01
    measure("v8_fg_target_switch", targets, switched)
    restored = bool(on and back) and back.get("target") == on.get("target") and back.get("setting") == on.get("setting")
    measure("v8_fg_restored", [back and back.get("setting"), on and on.get("setting")], restored)
    line = next((part for part in str((on or {}).get("status", "")).split("\n\n") if part.startswith("Frame generation")), None)
    measure("v8_fg_page_line", line, line is not None)


def analyse(records, selected=None):
    selected = list(range(14)) if selected is None else selected
    phases = {i: [r for r in records if r.get("phase") == i and r.get("kind") == "sample"] for i in range(14)}
    metrics, checks = {}, {}

    def measure(name, value, passed):
        metrics[name], checks[name] = value, bool(passed)

    p = phases[0]
    displacement = max((distance(r.get("position"), r.get("initial")) for r in p if r.get("position")), default=0)
    measure("barrel_displacement_units", displacement, displacement > 2)
    p = phases[1]
    measure("grab_samples", sum(bool(r["right"]["held"]) for r in p), any(r["right"]["held"] for r in p))
    throws = [r["right"] for r in p if r["right"].get("hand_throw")]
    speed = max((distance(r["hand_throw"], None) for r in throws), default=0)
    measure("throw_hand_speed_units_s", speed, abs(speed-120) <= 24)
    spin = max((distance(r.get("spin"), None) for r in throws), default=0)
    measure("throw_spin_radians_s", spin, 0.7 < spin < 1.5)
    released=next((r for r in p if r['time']>4.4 and not r['right']['held'] and r['right'].get('hand_throw') and r.get('phys_velocity')),None)
    actual=vector(released['phys_velocity']) if released else (0,0,0)
    wanted=vector(released['right']['hand_throw']) if released else (120,0,0)
    error=distance(actual,wanted)/max(distance(wanted,None),1)
    measure('throw_engine_velocity_units_s',actual,bool(released))
    measure('throw_engine_error_fraction',error,bool(released) and error<=.2)
    engine_spin=distance(released.get('phys_spin'),None)*math.pi/180 if released else 0
    measure('throw_engine_spin_radians_s',engine_spin,bool(released) and abs(engine_spin-spin)<=spin*.2)
    p = phases[2]
    gap = max((distance(r["right"].get("proxy"), r["right"].get("hand")) for r in p), default=0)
    measure("blocked_hand_separation_units", gap, gap > 5)
    alignments = [r["alignment"] for r in phases[3] if "alignment" in r and 4.5 < r["time"] < 6.2]
    alignment = max(alignments, default=-1)
    measure("two_hand_alignment_dot", alignment, alignment > .9)
    lag = max((r["right"].get("grip_error", 0) for r in phases[4] if r["time"] > 3), default=0)
    measure("heavy_crate_lag_units", lag, math.isfinite(lag) and lag > HEAVY_LAG_UNITS)
    # One consecutive second, not a spike or disjoint bursts. Actual game seconds
    # survive compressed fixtures; the standalone fixture's time is already real.
    start = previous = None
    duration = 0.0
    for row in sorted(phases[4], key=lambda r: r.get('elapsed_seconds', r['time'])):
        seconds = row.get('elapsed_seconds', row['time'])
        error = row['right'].get('grip_error', 0)
        high = row['time'] > 3 and row['right'].get('held') and math.isfinite(error) and error > HEAVY_LAG_UNITS
        if high and math.isfinite(seconds):
            if start is None or previous is None or not 0 < seconds-previous <= .30:
                start = seconds
            duration = max(duration, seconds-start)
            previous = seconds
        else:
            start = previous = None
    ticked = [r['heavy'] for r in phases[4] if isinstance(r.get('heavy'), dict)]
    if ticked:
        duration = max(float(h.get('above', 0)) for h in ticked)
        lag = max([lag] + [float(h.get('peak', 0)) for h in ticked])
        measure("heavy_crate_lag_units", lag, math.isfinite(lag) and lag > HEAVY_LAG_UNITS)
    measure('heavy_crate_lag_duration_seconds', duration, duration >= HEAVY_LAG_SECONDS)
    bones = sorted({(r["left"].get("bone", -1), r["right"].get("bone", -1)) for r in phases[5]
                    if r["left"]["held"] and r["right"]["held"]})
    measure("two_hand_ragdoll_bones", bones, any(a != b and a >= 0 and b >= 0 for a, b in bones))
    climb = [r for r in phases[6] if r["right"].get("climb") or r["left"].get("climb")]
    rise = max((vector(r["feet"])[2]-vector(r["initial"])[2] for r in climb), default=0)
    measure("ledge_climb_rise_units", rise, abs(rise-12)<=2)
    measure("button_activated", any(r.get("button") for r in phases[7]), any(r.get("button") for r in phases[7]))
    for key, baseline in (("health", 50), ("armor", 10), ("ammo", 20)):
        maximum = max((r.get(key, 0) for r in phases[7]), default=0)
        measure("kit_" + key, maximum, maximum > baseline)
    melon = phases[8]
    measure("melon_broken", any(not r.get("entity_alive", True) for r in melon), any(not r.get("entity_alive", True) for r in melon))
    held_cases=phases[13] if phases[13] else melon
    held_hits=[r for r in held_cases if r.get("right",{}).get("hit",{}).get("source")=="held"]
    measure("held_object_hit_samples", len(held_hits), bool(held_hits))
    held_broken=any(r.get("held_melon_alive") is False for r in held_cases)
    measure("held_object_melon_broken", held_broken, held_broken)
    gloves = phases[9]
    measure("glove_marked", any(r["right"]["target"] for r in gloves), any(r["right"]["target"] for r in gloves))
    measure("glove_launched", any(r["right"]["pull"] for r in gloves), any(r["right"]["pull"] for r in gloves))
    measure("glove_caught", any(r["right"]["held"] for r in gloves), any(r["right"]["held"] for r in gloves))
    npc_health = [r["npc_health"] for r in phases[10] if "npc_health" in r and r["time"] < 4.7]
    minimum = min(npc_health, default=100)
    measure("npc_min_health_before_fixture_kill", minimum, minimum < 100)
    deaths = [r for r in records if r.get("kind") == "death-ragdoll"]
    measure("npc_server_death_ragdoll", len(deaths), bool(deaths))
    ragids = {r["entity"] for r in deaths}
    measure("death_ragdoll_grabbed", any(r["right"]["held"] in ragids for r in phases[10]),
            any(r["right"]["held"] in ragids for r in phases[10]))
    clean_death = [r for r in records if r.get("kind") == "player-death"]
    measure("death_releases_with_vr_active", bool(clean_death) and all(r["vr_active"] and not r["held"] and not r["proxy"] for r in clean_death),
            bool(clean_death) and all(r["vr_active"] and not r["held"] and not r["proxy"] for r in clean_death))
    doors = {r["door"] for r in phases[11] if "door" in r}
    measure("door_states", sorted(doors), any(value != 0 for value in doors))
    ladder = [r for r in phases[12] if r["right"].get("climb") or r["left"].get("climb")]
    measure("ladder_grip_samples", len(ladder), bool(ladder))
    ladder_base=next((r['feet'] for r in records if r.get('phase')==12 and r.get('kind')=='begin'),None)
    ladder_rise=max((vector(r['feet'])[2]-vector(ladder_base)[2] for r in ladder),default=0) if ladder_base else 0
    measure('ladder_climb_rise_units',ladder_rise,abs(ladder_rise-12)<=2)
    kinds = {r["right"]["kind"] for p in phases.values() for r in p if r["right"].get("kind")}
    for r in records:
        counts=r.get("haptic_counts", {})
        if isinstance(counts, dict): kinds.update(int(k) for k,v in counts.items() if v)
        elif isinstance(counts, list): kinds.update(i+1 for i,v in enumerate(counts) if v)
    required=set()
    if any(phase in selected for phase in (0,2,3,4,5,7,9,11)): required.add(1)
    if 1 in selected or 3 in selected or 4 in selected or 5 in selected: required.update((2,3))
    if 9 in selected: required.update((2,3,4))
    if 8 in selected or 10 in selected or 13 in selected: required.add(5)
    if 13 in selected: required.update((2,3))
    if any(phase in selected for phase in (14, 15, 16, 17)):
        v8_checks(records, measure)
        required.add(2)
    if 16 in selected: required.update((6, 7))
    if 17 in selected: required.add(6)
    measure("haptic_event_kinds", sorted(kinds), required.issubset(kinds))
    cleanup = [r for r in records if r.get("kind") == "cleanup"]
    measure("exit_restored", bool(cleanup) and all(not r["active"] and not r["custom"] and r["ragdolls"] == r["saved_ragdolls"] for r in cleanup),
            bool(cleanup) and all(not r["active"] and not r["custom"] and r["ragdolls"] == r["saved_ragdolls"] for r in cleanup))
    by_phase={0:["barrel_displacement_units"],1:["grab_samples","throw_hand_speed_units_s","throw_spin_radians_s",
              'throw_engine_velocity_units_s','throw_engine_error_fraction','throw_engine_spin_radians_s'],
              2:["blocked_hand_separation_units"],3:["two_hand_alignment_dot"],4:["heavy_crate_lag_units","heavy_crate_lag_duration_seconds"],
              5:["two_hand_ragdoll_bones"],6:["ledge_climb_rise_units"],
              7:["button_activated","kit_health","kit_armor","kit_ammo"],
              8:["melon_broken"],
              9:["glove_marked","glove_launched","glove_caught"],
              10:["npc_min_health_before_fixture_kill","npc_server_death_ragdoll","death_ragdoll_grabbed","death_releases_with_vr_active"],
              11:["door_states"],12:["ladder_grip_samples","ladder_climb_rise_units"],13:["held_object_hit_samples","held_object_melon_broken"],
              14:["v8_turn_held_samples","v8_turn_worst_error_units","v8_turn_worst_angle_degrees","v8_turn_body_degrees",
                  "v8_drawn_at_hand_samples","v8_drawn_vs_physics_units"],
              15:["v8_pair_held_samples","v8_pair_frame","v8_pair_grab_jump_units","v8_pair_rise_units","v8_pair_roll_degrees",
                  "v8_pair_worst_error_units"],
              16:["v8_freeze_frozen_samples","v8_freeze_stays_units","v8_unfreeze_held_samples","v8_unfreeze_carried_units"],
              17:["v8_freeze_one_bone"]}
    keys={"haptic_event_kinds","exit_restored"}
    for phase in selected: keys.update(by_phase[phase])
    if any(r.get("kind") == "v8-frame-generation" for r in records):
        fg_checks(records, measure)
        keys.update(FG_CHECKS)
    checks={k:v for k,v in checks.items() if k in keys}
    return {"selected_phases":selected,"metrics":metrics,"checks":checks,"success":all(checks.values()),"records":len(records)}


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("evidence", type=Path)
    parser.add_argument("--phases", help="explicit subset, e.g. 1,9 for the short Index acceptance")
    args = parser.parse_args()
    records=json.loads((args.evidence / "interaction.json").read_text(encoding="utf-8"))
    selected=[int(v) for v in args.phases.split(",")] if args.phases else None
    result = analyse(records, selected)
    problems=[]
    files=("centre.png","centre_depth.png","left.png","right.png","mirror.png","timings.json")
    for phase in result["selected_phases"]:
        folder=args.evidence/"captures"/("interact-"+str(phase))
        for name in files:
            path=folder/name
            if not path.is_file() or path.stat().st_size==0: problems.append(str(path))
        if not list(folder.glob("overlay_*.png")): problems.append(str(folder/"overlay_*.png"))
    result["capture_problems"]=problems
    result["checks"]["eye_captures_complete"]=not problems
    result["success"]=all(result["checks"].values())
    (args.evidence / "interaction-checks.json").write_text(json.dumps(result, indent=2), encoding="utf-8")
    print(json.dumps(result, indent=2))
    raise SystemExit(0 if result["success"] else 1)
