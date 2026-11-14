"""Accept actual per-class reload receipts; never infer native results from setter calls."""
from pathlib import Path
import argparse
import json
import math

# A hold pushes the gun's next shot R.HOLD_SECONDS (3600 s) past the moment it was applied, not past the phase:
# an unloaded RPG from the sandbox loadout is held from the session's start, so in a seven-gun session its phase
# finds ~3477 s left (V8 run 1). Sessions run under ten minutes, so a hold is anything above 3000 s.
HOLD_FLOOR = 3000


def counter_metrics(records, require_motion=False):
    rows = [r for r in records if r["kind"] == "counter"]
    errors, positions, groups = [], [], []
    for r in rows:
        if r.get("main_pos") and r.get("main_ang") and len(r.get("native", {}).get("openvr_matrix34", [])) == 12:
            pitch, yaw, roll = map(math.radians, r["main_ang"])
            sp, cp, sy, cy, sr, cr = math.sin(pitch), math.cos(pitch), math.sin(yaw), math.cos(yaw), math.sin(roll), math.cos(roll)
            axes = ((cp * cy, cp * sy, -sp), (sr * sp * cy - cr * sy, sr * sp * sy + cr * cy, sr * cp),
                    (cr * sp * cy + sr * sy, cr * sp * sy - sr * cy, cr * cp))
            world = [r["main_pos"][i] + sum(axes[j][i] * r["pos"][j] for j in range(3)) for i in range(3)]
            expected = (-world[1], world[2], -world[0])
            matrix = r["native"]["openvr_matrix34"]
            errors.append(math.sqrt(sum((matrix[4 * i + 3] - expected[i]) ** 2 for i in range(3))))
            positions.append(r["main_pos"])
        if r.get("values") is not None and r.get("paints") is not None:
            key = (r.get("class"), tuple(r["values"]))
            if not groups or groups[-1][0] != key:
                groups.append((key, []))
            groups[-1][1].append(r["paints"])
    stable = [g for _, g in groups if len(g) >= 3]
    motion = math.sqrt(sum((max(p[i] for p in positions) - min(p[i] for p in positions)) ** 2 for i in range(3))) if positions else 0
    checks = {"measured_transform": bool(errors), "device_transform": bool(errors) and max(errors) <= .02,
              "unchanged_values_do_not_repaint": bool(stable) and all(len(set(g[1:])) == 1 for g in stable)}
    if require_motion:
        checks["hand_moved"] = motion >= .15
    return {"checks": checks, "success": all(checks.values()), "samples": len(rows), "matrix_samples": len(errors),
            "max_matrix_error_metres": max(errors) if errors else None, "hand_motion_metres": motion,
            "stable_groups": len(stable), "first_paints": rows[0].get("paints") if rows else None,
            "last_paints": rows[-1].get("paints") if rows else None}


def button_commands(records, cls):
    return [r for r in records if r["kind"]=="reload-button" and r["class"]==cls
            and 0<=r["time"]<=18.5]


def button_delivery(records, cls, deploy=False):
    commands=button_commands(records,cls)
    setup=next((r for r in records if r["kind"]=="setup" and r["class"]==cls),{})
    base=setup.get("phase",0)*20
    releases=[r["time"]-base for r in records if r["kind"]=="button-input" and r.get("class")==cls and r.get("released") and r.get("tapped") and 2.8<r["time"]-base<3.6]
    release=max(releases) if releases else 3.15
    one=len({r["tick"] for r in commands})==1
    delivered=commands[0]["time"] if one else None
    # The server's records count SysTime from the phase's start and the client's the fixture's own clock; the two part
    # by tens of milliseconds within a phase (V8 run 1: the server 0.063-0.075 s behind in the first phase, so the
    # server took B "before" the client released it). Both realms count the same ticks in single-player, so the
    # delivery tick is placed on the client's clock where the client recorded that tick, and the server's other times
    # move by the same offset. Without a client record of that tick the server's own time stands.
    offset=0
    if one:
        ticked=sorted((r for r in records if r["kind"]=="button-command" and r.get("class")==cls
                       and isinstance(r.get("tick"),(int,float)) and 0<=r["time"]-base<=18.5),key=lambda r:r["time"])
        at=next((r for r in ticked if r["tick"]>=commands[0]["tick"]),None)
        if at is not None:
            offset=at["time"]-base-delivered
            delivered=at["time"]-base
    deadlines=[];observed=False
    # Readiness is what the game showed before B reached it: the records printed before the class's first reload bit or
    # the server's delivery, whichever came first. The console keeps both realms in order, while one frame runs several
    # commands at one clock reading and those after B already carry the reload's own lock (the 357's 3.66 s in V8 run 1).
    marks=[i for i,r in enumerate(records) if r.get("class")==cls and (r["kind"]=="reload-button" and 0<=r["time"]<=18.5
           or r["kind"]=="button-command" and r.get("reload") and 0<=r["time"]-base<=18.5)]
    if delivered is not None:
        for r in records[:marks[0]]:
            if r.get("class")!=cls:continue
            if r["kind"]=="sample" and r["time"]>=0 and isinstance(r.get("player_next_attack"),(int,float)):
                observed=True
                if r["player_next_attack"]>0:deadlines.append(r["time"]+offset+r["player_next_attack"])
            if r["kind"]=="button-command" and r["time"]-base>=0 and all(isinstance(r.get(k),(int,float)) for k in ("next_attack","client_game_time")):
                observed=True
                remaining=r["next_attack"]-r["client_game_time"]
                if remaining>0:deadlines.append(r["time"]-base+remaining)
    ready=max([release]+deadlines) if observed else None
    latency=delivered-ready if ready is not None else None
    locks=[r for r in records if r["kind"]=="deploy-lock" and r["class"]==cls]
    lock_ok=not deploy or bool(locks) and all(r.get("remaining",0)>.8 for r in locks)
    native_ok=one and all(r.get("player_next_attack",999)<=.015 for r in commands)
    on_time=one and observed and lock_ok and native_ok and latency is not None and -.02<=latency<=.300001
    return {"one_tick":one,"native_lock_observed":lock_ok,"native_ready":native_ok,
            "on_time":on_time,"release":release,"ready":ready,"delivered":delivered,"latency":latency,"bound":.3,
            "server_clock_offset":offset}


def analyse(folder, button=False, empty=False):
    records = json.loads((folder / "reload.json").read_text(encoding="utf-8"))
    classes = list(dict.fromkeys(r["class"] for r in records if r["kind"] == "setup"))
    config = json.loads((folder / "sources.json").read_text(encoding="utf-8"))["config"]
    checks, measurements = {}, {}
    for cls in classes:
        samples = [r for r in records if r["kind"] == "sample" and r["class"] == cls]
        # A second Start may begin phase 0 again; keep the uninterrupted first phase.
        selected = []
        for r in samples:
            if selected and r["time"] < selected[-1]["time"]:
                break
            selected.append(r)
        samples = selected
        setup = next((r for r in records if r["kind"] == "setup" and r["class"] == cls), {})
        if empty:
            hold = [r for r in samples if 2.5 <= r["time"] <= 7.5]
            checks[cls] = {"empty_reserve": bool(hold) and all(r["reserve"] == 0 for r in hold),
                           "no_pickup": bool(samples) and all(r.get("reload", {}).get("held", 0) == 0 for r in samples),
                           "held": bool(hold) and all(r.get("reload", {}).get("command_primary", 0) > HOLD_FLOOR and r["active"] == cls for r in hold)}
            measurements[cls] = {"samples": len(samples), "hold": hold[-1] if hold else None}
            continue
        if button:
            before = [r for r in samples if 2 <= r["time"] <= 2.8]
            after = [r for r in samples if 6 <= r["time"] <= 8]
            reload_seen = any(r.get("swep_reloads", 0) for r in samples) if cls == "nlvr_k_swep" else bool(before and after and after[-1]["clip"] > before[0]["clip"])
            delivery=button_delivery(records,cls,config.get("reload_deploy",False))
            commands=button_commands(records,cls)
            buttons={r["tick"] for r in commands}
            # For a native single-shot gun auto-reload may already have completed
            # before B; its ordinary behavior and exactly one B command are recorded.
            if cls in ("weapon_crossbow", "weapon_rpg"):
                reload_seen = bool(after and before and (after[-1]["clip"]==-1 and after[-1]["reserve"]==setup.get("reserve",0)-1 and before[-1]["reserve"]==after[-1]["reserve"] if cls=="weapon_rpg" else after[-1]["clip"]==1))
            if cls in ("gmod_tool", "weapon_physgun"):
                kind = "tool-reload" if cls == "gmod_tool" else "physgun-reload"
                reload_seen = any(r["kind"] == kind and r["class"] == cls and 2.8 < r["time"] < 3.5 for r in records)
            checks[cls]={"ordinary_reload":reload_seen,"one_tick":len(buttons)==1,
                         "bounded_delivery":delivery["on_time"],"native_ready":delivery["native_ready"]}
            if config.get("reload_deploy"):checks[cls]["native_lock_observed"]=delivery["native_lock_observed"]
            measurements[cls]={"before":before[-1] if before else None,"after":after[-1] if after else None,"B":delivery}
            continue
        hold = [r for r in samples if 2.5 <= r["time"] <= 7.5]
        held = [r for r in samples if 8.2 <= r["time"] <= 9.2]
        insert = [r for r in samples if 10.7 <= r["time"] <= 11.3]
        after = [r for r in samples if 16.4 <= r["time"] <= 18.5]
        logical = lambda r: r.get("reload", {}).get("clip", r["clip"])
        early = [r for r in samples if 1.15 <= r["time"] <= 1.9]
        fired_initially = bool(early) and any(r["reserve"] < setup.get("reserve", 0) if cls == "weapon_rpg"
                                               else r["clip"] < setup.get("clip", 0) for r in early)
        held_seconds = hold[-1].get("hold_wall_seconds", 0) if hold else 0
        check = {"initial_fire": fired_initially, "five_seconds": held_seconds >= 5,
                 "empty_fire_attempt": any(r["kind"] == "attack-button" and r.get("class") == cls and 3 <= r["time"] <= 7 for r in records),
                 "native_attempt_deadline": any(r["primary"] > HOLD_FLOOR for r in hold if 3.4 <= r["time"] <= 3.55 or 6.2 <= r["time"] <= 6.35),
                 "empty_held": bool(hold) and all(logical(r) == 0 and r.get("reload", {}).get("command_primary", 0) > HOLD_FLOOR for r in hold),
                 "no_engine_reload": bool(hold) and all(not r["native"].get("in_reload") and not r["native"].get("must_reload") for r in hold),
                 "same_weapon": bool(hold) and all(r["active"] == cls for r in samples if 0.5 <= r["time"] <= 18.5),
                 "reserve_constant": bool(hold) and len({r["reserve"] for r in hold}) == 1,
                 "taken": any(r.get("reload", {}).get("held", 0) > 0 for r in held),
                 "inserted": bool(insert) and any(logical(r) > 0 and not r.get("reload", {}).get("holding") for r in insert),
                 "fired_again": bool(insert and after) and logical(after[-1]) < max(logical(r) for r in samples if 10 <= r["time"] <= 16),
                 "captures": all(any(r["kind"] == "capture" and r["class"] == cls and r["label"] == cls + "-" + suffix for r in records) for suffix in ("held", "well", "after"))}
        if cls == "weapon_shotgun":
            check["three_single_shells"] = all(any(logical(r) == i for r in samples if 9.5 <= r["time"] < 16) for i in (1, 2, 3))
        if cls in ("weapon_pistol", "weapon_357", "weapon_smg1", "weapon_ar2"):
            drop_rows = [r for r in records if r["kind"] == "counter" and r.get("class") == cls and (r.get("drop_physics") or 0) > 0]
            check["ejected_physics"] = bool(drop_rows)
            check["eject_returns_rounds"] = bool(early and hold) and hold[-1]["reserve"] == setup["reserve"] + max(0, early[-1]["clip"])
            expected = min(setup["max_clip"], hold[-1]["reserve"]) if hold else 0
            check["clip_arithmetic"] = bool(expected) and any(r["clip"] == expected and r["reserve"] == hold[-1]["reserve"] - expected for r in insert)
        elif cls in ("weapon_shotgun", "weapon_crossbow"):
            check["clip_arithmetic"] = bool(hold) and any(r["clip"] == 1 and r["reserve"] == hold[-1]["reserve"] - 1 for r in insert)
        elif cls == "weapon_rpg":
            check["one_native_charge_per_shot"] = bool(hold and insert and after) and hold[-1]["reserve"] == setup["reserve"] - 1 and any(
                r["clip"] == -1 and logical(r) == 1 and r["reserve"] == hold[-1]["reserve"] for r in insert) and after[-1]["reserve"] == hold[-1]["reserve"] - 1
        checks[cls] = check
        measurements[cls] = {"hold_samples": len(hold), "hold_seconds": held_seconds,
            "engine_hold_seconds": hold[-1]["server_time"] - hold[-1].get("reload", {}).get("hold_since", hold[-1]["server_time"]) if hold else 0,
            "empty": hold[0] if hold else None, "held": held[-1] if held else None,
            "insert": insert[-1] if insert else None, "after": after[-1] if after else None}
    summary = json.loads((folder / "summary.json").read_text(encoding="utf-8"))
    receipt = json.loads((folder / "reload-receipt.json").read_text(encoding="utf-8"))
    config = json.loads((folder / "sources.json").read_text(encoding="utf-8"))["config"]
    counter = counter_metrics(records, config.get("reload_counter_motion", False)) if any(
        c not in ("gmod_tool", "weapon_physgun") for c in classes) else {
            "success": not any(r.get("visible") for r in records if r["kind"] == "counter" and r.get("class") in classes
                               and r["time"] % 20 >= .5), "no_ammo": True}
    result = {"success": bool(classes) and summary["success"] and receipt["success"] and counter["success"] and all(all(c.values()) for c in checks.values()),
              "classes": classes, "checks": checks, "measurements": measurements, "counter": counter}
    (folder / "reload-checks.json").write_text(json.dumps(result, indent=2), encoding="utf-8")
    return result


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("folder", type=Path)
    parser.add_argument("--button", action="store_true")
    parser.add_argument("--empty", action="store_true")
    args = parser.parse_args()
    result = analyse(args.folder, args.button, args.empty)
    print(json.dumps({"success": result["success"], "checks": result["checks"]}, indent=2))
    raise SystemExit(0 if result["success"] else 1)
