"""Independent measurements from W's native PoC receipts; does not alter original evidence."""
from __future__ import annotations

import argparse
import json
import math
from pathlib import Path
import re

_barrel_axes=None
def rendered_barrel(row):
    """Use independently measured mesh axes; an attachment marker need not face down its barrel."""
    global _barrel_axes
    if _barrel_axes is None:
        _barrel_axes={}
        for name in ('vr_weapon_grips.json','vr_v4_weapon_grips.json'):
            models=json.loads((Path(__file__).with_name('fixtures')/name).read_text(encoding='utf-8'))['models']
            _barrel_axes.update({path:data['barrel_axis'] for path,data in models.items() if data.get('barrel_axis')})
        from vr_mesh_measure import plane_axis
        measured=json.loads((Path(__file__).with_name('fixtures')/'vr_mesh_witnesses.json').read_text(encoding='utf-8'))['models']
        for path,data in measured.items():
            if data['spec'].get('barrel_caps'):_barrel_axes[path]=plane_axis(data['vertices'])
    debug=row.get('debug',{})
    axis=_barrel_axes.get(debug.get('model','').lower())
    angles=debug.get('model_ang')
    return rotate(axis,angles) if axis is not None and angles is not None else None


def melee_witnesses(server, records):
    """Pair engine damage and a non-solid Impact on this phase's spawned target."""
    hit = server.get("melee") or {}
    target = server.get("target_index")
    phase_id = server.get("phase_id")
    if not server.get("target_valid") or target is None or phase_id is None or hit.get("ent") != target or hit.get("source") != "held":
        return []
    def in_window(r):
        return (r.get("phase_id") == phase_id and r.get("entity") == target
                and server.get("phase_start", float("inf")) <= r.get("time", float("-inf")) <= server.get("time", float("-inf")))
    damage = [r for r in records if r.get("kind") == "melee-engine-damage" and in_window(r)
              and r.get("damage", 0) > 0 and r.get("damage_type", 0) & 128]
    effects = [r for r in records if r.get("kind") == "server-effect" and in_window(r)
               and r.get("name") in ("Impact", "StunstickImpact")]
    if not damage or not effects:
        return []
    paired = []
    for d in damage:
        matches = [e for e in effects if e.get("tick") == d.get("tick")
                   and distance(e["start"], e["origin"]) > .001]
        if not matches:
            return []
        e = matches[0]
        paired.append({"tick": d["tick"], "entity": target, "damage": d["damage"],
                       "start": e["start"], "origin": e["origin"], "ray_units": distance(e["start"], e["origin"])})
    if any(distance(e["start"], e["origin"]) <= .001 or not any(d.get("tick") == e.get("tick") for d in damage) for e in effects):
        return []
    return paired


def held_contact(server, records):
    return bool(melee_witnesses(server, records))


def vector(value):
    if isinstance(value, str):
        value = re.findall(r"[-+]?(?:\d*\.\d+|\d+)(?:[eE][-+]?\d+)?", value)
    elif isinstance(value, dict):
        value = [value[k] for k in (("x", "y", "z") if "x" in value else ("p", "y", "r"))]
    if not isinstance(value, (list, tuple)) or len(value) != 3:
        raise ValueError(f"not a 3-vector: {value!r}")
    result = tuple(float(x) for x in value)
    if not all(math.isfinite(x) for x in result):
        raise ValueError("non-finite receipt")
    return result


def sub(a, b):
    return tuple(x-y for x, y in zip(a, b))


def dot(a, b):
    return sum(x*y for x, y in zip(a, b))


def length(a):
    return math.sqrt(dot(a, a))


def distance(a, b):
    return length(sub(vector(a), vector(b)))


def forward(angles):
    p, y, _ = map(math.radians, vector(angles))
    return math.cos(p)*math.cos(y), math.cos(p)*math.sin(y), -math.sin(p)


def rotate(v, angles):
    p, y, r = map(math.radians, vector(angles))
    cp,sp,cy,sy,cr,sr=math.cos(p),math.sin(p),math.cos(y),math.sin(y),math.cos(r),math.sin(r)
    rows=((cp*cy,cy*sp*sr-sy*cr,cy*sp*cr+sy*sr),
          (cp*sy,sy*sp*sr+cy*cr,sy*sp*cr-cy*sr),(-sp,cp*sr,cp*cr))
    return tuple(dot(row,vector(v)) for row in rows)


def degrees(a, b):
    return math.degrees(math.acos(max(-1, min(1, dot(a, b)/max(1e-12, length(a)*length(b))))))


def grip_wrist(client):
    """C's shown pose is the palm; compare the world-model bone with the anatomical wrist."""
    shown = client["shown"]
    frame = client.get("hands", {}).get(client.get("active", {}).get("hand"), {}).get("palm_frame")
    if not frame:
        return shown["pos"]  # Legacy W receipts were wrist-centred.
    def rotation(angles):
        p, y, r = map(math.radians, vector(angles))
        cp, sp, cy, sy, cr, sr = math.cos(p), math.sin(p), math.cos(y), math.sin(y), math.cos(r), math.sin(r)
        return ((cp*cy, cy*sp*sr-sy*cr, cy*sp*cr+sy*sr),
                (cp*sy, sy*sp*sr+cy*cr, sy*sp*cr-cy*sr), (-sp, cp*sr, cp*cr))
    offset = tuple(-dot(column, vector(frame["pos"])) for column in zip(*rotation(frame["ang"])))
    delta = tuple(dot(row, offset) for row in rotation(shown["ang"]))
    return tuple(p+d*client.get("scale", 40)/40 for p, d in zip(vector(shown["pos"]), delta))


def hand_grip(shown, frame, scale=40):
    if not frame or not frame.get("grip"):
        return shown["pos"]
    # Reuse independent matrix maths for the local grip offset, retaining palm semantics.
    origin=vector(shown["pos"])
    axes=[rotate(v,frame["ang"]) for v in ((1,0,0),(0,1,0),(0,0,1))]
    delta=sub(vector(frame["grip"]),vector(frame["pos"]))
    local=tuple(dot(axis,delta)*scale/40 for axis in axes)
    offset=rotate(local,shown["ang"])
    return tuple(p+d for p,d in zip(origin,offset))


def analyse(evidence: Path):
    summary = json.loads((evidence / "summary.json").read_text(encoding="utf-8"))
    source = json.loads((evidence / "sources.json").read_text(encoding="utf-8"))
    phases = source["config"]["weapons_phases"]
    rows = json.loads((evidence / "weapons.json").read_text(encoding="utf-8"))
    issues, metrics = [], {"models": {}, "bullets": {}, "foregrips": {}, "projectiles": {}}

    def require(condition, message):
        if not condition:
            issues.append(message)

    require(summary["success"], "production driver rejected this run")
    require(summary.get("lua_errors") == 0, "Lua errors")
    clients = {r["phase"]: r for r in rows if r.get("kind") == "client"}
    servers = {r["phase"]: r for r in rows if r.get("kind") == "server"}
    for phase in phases:
        c, s = clients.get(phase), servers.get(phase)
        require(c is not None and s is not None, phase + ": missing client/server capture receipts")
        if not c or not s:
            continue
        folder = evidence / "captures" / c["label"]
        for name in ("centre.png", "centre_depth.png", "left.png", "right.png", "mirror.png", "timings.json"):
            require((folder / name).is_file(), phase + ": missing " + name)
        if phase == "death":
            require(not c.get("active") and not s["alive"] and not s.get("proxy") and not s["holding"], "death did not clear weapons/proxies/holds")
            continue
        active = c.get("active") or {}
        require(active.get("valid") is True, phase + ": invalid weapon tracking")
        if phase.startswith("weapon_") or phase.startswith("gmod_"):
            require(active.get("class") == phase, phase + ": wrong active class")
        if c.get("grip"):
            frame=c.get("hands",{}).get(active.get("hand"),{}).get("palm_frame")
            actual=c["debug"].get("grip_pos") if frame and frame.get("grip") else c["grip"]["pos"]
            expected=hand_grip(c["shown"],frame) if frame and frame.get("grip") else grip_wrist(c)
            error = distance(actual,expected) / 40
            item = {"grip_error_m": error, "model": c["debug"].get("model"), "model_angles": c["debug"].get("model_ang"),
                    "capture": str(folder), "muzzle_m": [v / 40 for v in vector(c["muzzle"]["pos"])]}
            require(error < .005, phase + ": wrist/grip mismatch over 5 mm")
            if c.get("attachment"):
                error = distance(c["attachment"]["Pos"], c["muzzle"]["pos"]) / 40
                item["muzzle_error_m"] = error
                require(error < .005, phase + ": rendered muzzle and API differ over 5 mm")
                actual_barrel=rendered_barrel(c)
                item['attachment_marker_error_deg']=degrees(forward(c["attachment"]["Ang"]),vector(c['ray']['dir']))
                if actual_barrel is not None or active["class"] != "weapon_crossbow":
                    angle = degrees(actual_barrel if actual_barrel is not None else forward(c["attachment"]["Ang"]), vector(c["ray"]["dir"]))
                    item["barrel_error_deg"] = angle
                    require(angle < 2, phase + ": barrel/ray direction differs over 2 degrees")
            metrics["models"][phase] = item
        require(c.get("debug", {}).get("draws", 0) > 0 or active.get("class") in ("nlvr_hands", "weapon_fists"), phase + ": no world draws")
        if phase.startswith("fore-"):
            require(active.get("twoHanded") and s.get("weapon", {}).get("twoHanded"), phase + ": foregrip absent in a realm")
            line = sub(vector(c["fore_hand"]["target"]["pos"]), vector(c["shown"]["pos"]))
            angle = degrees(vector(c["ray"]["dir"]), line)
            off="left" if active["hand"]=="right" else "right"
            off_frame=c.get("hands",{}).get(off,{}).get("palm_frame")
            main_frame=c.get("hands",{}).get(active["hand"],{}).get("palm_frame")
            off_grip=c["fore_hand"]["shown"]["pos"] if off_frame and off_frame.get("calibrated") else hand_grip(c["fore_hand"]["shown"],off_frame)
            main_grip=c["shown"]["pos"] if main_frame and main_frame.get("calibrated") else hand_grip(c["shown"],main_frame)
            snap = distance(off_grip, c["debug"]["foregrip"]) / 40
            shown_angle = degrees(vector(c["ray"]["dir"]), sub(vector(off_grip), vector(main_grip)))
            metrics["foregrips"][phase] = {"aim_error_deg": angle, "shown_aim_error_deg": shown_angle, "snap_error_m": snap}
            require(angle < 2 and shown_angle < 2 and snap < .005, phase + ": foregrip line/snap tolerance")
        if phase == "hands":
            require(active.get("class") == "nlvr_hands" and bool(s["holding"]), "Hands did not free the main hand for a native grab")
        if phase == "respawn":
            require(s["alive"] and s["hands"], "respawn did not give Hands while VR stayed active")
        if phase == "left":
            require(active.get("hand") == "left", "left-handed setting did not move the weapon")
            pitch = degrees(forward(c["muzzle"]["ang"]), forward(c["controller"]["ang"]))
            metrics["gun_angle_deg"] = pitch
            require(abs(pitch-30) < .1, "gun-angle setting did not rotate the actual gun by 30 degrees")

    for phase in [p for p in phases if re.fullmatch(r"(?:pistol|357|smg1|ar2|shotgun)-(?:5|20)", p)]:
        bullets = [r for r in rows if r.get("kind") == "bullet" and r.get("phase") == phase]
        exact = [r for r in bullets if r.get("zero_spread")]
        native = [r for r in bullets if not r.get("zero_spread")]
        require(bool(exact) and bool(native), phase + ": missing native trigger shots or labelled zero-spread diagnostic")
        result = {"native_bullets": len(native), "zero_spread_bullets": len(exact), "shots": []}
        target = int(phase.split("-")[-1])
        c = clients.get(phase)
        for b in bullets:
            tr, muzzle = b["trace"], b.get("muzzle")
            if not muzzle:
                require(False, phase + ": native bullet bypassed a valid host muzzle")
                continue
            start, hit, direction = vector(tr["StartPos"]), vector(tr["HitPos"]), forward(muzzle["ang"])
            delta = sub(hit, start)
            along = dot(delta, direction)
            error = length(sub(delta, tuple(v*along for v in direction))) / 40
            source_error = distance(start, muzzle["pos"]) / 40
            rendered_error = distance(start, c["muzzle"]["pos"]) / 40 if c else None
            result["shots"].append({"zero_spread": b["zero_spread"], "range_m": along/40, "impact_error_m": error,
                                    "source_error_m": source_error, "rendered_muzzle_error_m": rendered_error})
            require(source_error < .05, phase + ": native bullet did not start at checked muzzle")
            if b["zero_spread"]:
                require(tr["Hit"] and abs(along/40-target) < .03, phase + ": target face is not at the required range")
                require(error <= (.05 if target == 5 else .1), phase + ": zero-spread native impact misses the gun ray")
                require(rendered_error is not None and rendered_error < .05, phase + ": native source differs from rendered muzzle")
        if c:
            result["head_away_deg"] = degrees(forward(c["head"]["ang"]), vector(c["ray"]["dir"]))
            require(abs(result["head_away_deg"]-45) < .1, phase + ": head is not 45 degrees away")
        metrics["bullets"][phase] = result

    projectiles = {"bolt": "crossbow_bolt", "bolt-eye": "crossbow_bolt", "rocket": "rpg_missile", "smg-grenade": "grenade_ar2", "ar2-orb": "prop_combine_ball",
                   "frag-throw": "npc_grenade_frag", "bugbait-throw": "npc_grenade_bugbait"}
    for phase, classname in projectiles.items():
        if phase not in phases:
            continue
        launches = [r for r in rows if r.get("kind") == "projectile" and r.get("phase") == phase and r.get("class") == classname]
        require(bool(launches), phase + ": native projectile not redirected")
        if not launches:
            continue
        b = launches[0]
        expected, velocity = vector(b["requested"]["velocity"]), vector(b["velocity"])
        result = {"class": classname, "ticks": b["requested"]["ticks"], "native_velocity": velocity,
                  "requested_velocity": expected, "elapsed": b["elapsed"],
                  "launch_error_m": distance(b["requested"].get("nativePos", b["requested"]["pos"]), b["requested"]["pos"])/40,
                  "distance_since_launch_m": distance(b["pos"], b["requested"]["pos"])/40}
        require(b["requested"]["ticks"] <= (1 if phase=="bugbait-throw" else 0), phase + ": projectile was not redirected at its first ready launch boundary")
        require(b["requested"].get("nointerp") is True, phase + ": projectile relocation lacked EF_NOINTERP")
        if phase.endswith("-throw"):
            late = next((r for r in rows if r.get("kind") == "projectile-late" and r.get("phase") == phase and r.get("class") == classname), None)
            require(late is not None, phase + ": missing actual post-physics throw measurement")
            require(length(expected) > 40, phase + ": release did not retain the scripted 2 m/s throw")
            if late:
                actual = vector(late["velocity"])
                horizontal_error = math.hypot(actual[0]-expected[0], actual[1]-expected[1])/max(1e-6, math.hypot(expected[0],expected[1]))
                result.update(late_velocity=actual, late_elapsed=late["elapsed"], horizontal_error=horizontal_error)
                require(horizontal_error <= .2, phase + ": native throw velocity differs by more than 20% after physics")
        else:
            s = servers.get(phase)
            if s and s.get("weapon"):
                initial = b["requested"].get("nativeVelocity", b["requested"]["velocity"])
                launch = b["requested"].get("launchRay", {}).get("dir")
                result["angle_error_deg"] = degrees(vector(initial), vector(launch) if launch else forward(s["weapon"]["muzzle"]["ang"]))
                require(result["angle_error_deg"] < 2, phase + ": projectile direction differs from gun")
        metrics["projectiles"][phase] = result
        if phase=="bugbait-throw":
            first=next((r for r in rows if r.get("kind")=="projectile-first-visible" and r.get("class")==classname),None)
            require(first is not None,"bugbait: missing first visible client snapshot")
            if first:
                result["first_visible_error_m"]=distance(first["pos"],b["requested"]["pos"])/40
                require(result["first_visible_error_m"]<.15,"bugbait: first visible client snapshot was still at the eye")

    if "bolt-eye" in phases:
        obstacle = next((r for r in rows if r.get("kind") == "eye-obstacle"), {})
        require(obstacle.get("eye_blocked") and obstacle.get("muzzle_clear"), "bolt-eye: obstacle did not separate eye and muzzle rays")
        require(any(r.get("kind") == "projectile" and r.get("phase") == "bolt-eye" and not r.get("hit_eye_obstacle") for r in rows), "bolt-eye: bolt hit the eye-line obstacle")
        metrics["eye_obstacle"] = obstacle
    if "bullet-passes" in phases:
        records = [r for r in rows if r.get("kind") == "review-bullet"]
        require({r["label"] for r in records} == {"primary", "penetration", "missing-geometry"}, "bullet-passes: missing native pass")
        for r in records:
            require(distance(r["trace"]["StartPos"], r["expected_src"]) < .01, "bullet-passes: " + r["label"] + " source changed")
            direction = sub(vector(r["trace"]["HitPos"]), vector(r["trace"]["StartPos"]))
            require(degrees(direction, vector(r["expected_dir"])) < .01, "bullet-passes: " + r["label"] + " direction changed")
        require(any(r.get("kind") == "review-bullet-hook" for r in rows), "bullet-passes: downstream hook never ran")
        metrics["bullet_passes"] = records
    for phase in ("fore-smg", "fore-shotgun"):
        burst = [r for r in rows if r.get("kind") == "burst-command" and r.get("phase") == phase]
        if burst:
            require(all(r["attack"] and r["ready"] for r in burst), phase + ": foregrip interrupted an automatic burst")
            metrics[phase + "_burst"] = {"commands": len(burst), "dropped": sum(not r["attack"] for r in burst)}

    for phase in ("melee-slow", "melee-fast", "melee-stun", "melee-walk", "melee-lunge"):
        if phase not in phases or phase not in servers:
            continue
        s = servers[phase]
        metrics[phase] = {k: s.get(k) for k in ("target_valid", "target_health", "melee")}
        witnesses=melee_witnesses(s, [r for r in rows if r.get("phase")==phase])
        metrics[phase]["witnesses"]=witnesses
        if phase == "melee-slow":
            require(s.get("target_health") == 100 and not witnesses, "slow melee touch damaged the target")
        else:
            require(bool(witnesses), phase + ": missing engine/target/tick-bound outside-surface damage witness")
    if "melee-walk" in phases and "melee-walk" in servers:
        walk=servers["melee-walk"].get("walk") or {}
        metrics["melee-walk"]["walk"]=walk
        require(walk.get("max_speed",0)>=190 and walk.get("displacement",0)>10,
                "melee-walk: actual Source body movement was not exercised")
    if "melee-lunge" in phases and "melee-lunge" in servers:
        room=servers["melee-lunge"].get("room") or {}
        metrics["melee-lunge"]["room"]=room
        require(room and distance(room["applied_total"],room["from"])>5,
                "melee-lunge: actual room-follow body movement was not exercised")
    if "wall" in phases:
        bullets = [r for r in rows if r.get("kind") == "bullet" and r.get("phase") == "wall"]
        require(bool(bullets), "wall: no native bullets")
        require(any(r.get("blocked") for r in bullets), "wall: eye-to-muzzle guard not exercised")
        metrics["wall"] = bullets
    switches = [r for r in rows if r.get("kind") == "switch"]
    if switches:
        metrics["max_switch_frames"] = max(r["frames"] for r in switches)
        require(metrics["max_switch_frames"] <= 1, "weapon switch exceeded one frame")
    punches = [r for r in rows if r.get("kind") == "punch"]
    if "pistol-5" in phases:
        require(bool(punches), "missing nonzero view-punch camera witness")
        metrics["punch"] = punches
        for r in punches:
            require(r.get("camera") and degrees(forward(r["camera"]["angles"]), forward(r["head"]["ang"])) < .01,
                    "view punch moved the actual pushed camera")
    off = [r for r in rows if r.get("kind") == "client-off"]
    require(bool(off) and all("models_live" in r for r in off), "missing owned model cleanup measurement")
    require(all(r.get("models_live", 0) == 0 and not r.get("global") for r in off), "owned weapon models remain after Exit")
    require(any(r.get("kind") == "server-off" and not r.get("vr") and not r.get("hands") for r in rows), "Hands or server module remains after Exit")
    for r in rows:
        if r.get("kind") == "weapon-restored":
            require(r.get("restored"), "Exit weapon selection did not match the pre-Stop selection before fixture cleanup")
    if "left" in phases:
        require(any(r.get("kind") == "fixture-settings" and r.get("restored") for r in rows), "fixture gun angle/dominance did not restore live")
    for r in rows:
        if r.get("kind") == "camera-scope":
            require(r.get("cleared"), "camera visibility override remained after Exit")
    return {"success": not issues, "issues": issues, "phases": phases, "metrics": metrics,
            "counters": summary.get("counters"), "steady": summary.get("steady"), "production_success": summary["success"]}


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("evidence", type=Path)
    args = parser.parse_args(argv)
    result = analyse(args.evidence)
    (args.evidence / "weapons-checks.json").write_text(json.dumps(result, indent=2), encoding="utf-8")
    print(json.dumps({k: result[k] for k in ("success", "issues")}, indent=2))
    return 0 if result["success"] else 1


if __name__ == "__main__":
    raise SystemExit(main())
