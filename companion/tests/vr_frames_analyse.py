"""Numeric validation and reproducible hand crops for C's natural-hold receipts."""
from pathlib import Path
import json
import math
from vr_weapons_analyse import vector, distance, degrees, forward, sub, dot, rotate
from vr_frames_geometry import line,axis_error,source,cylinder

def palm_axis_distance(hand,raw,scale,handle):
    wrist=vector(hand["bones"]["Hand"]["pos"])
    heads=[vector(hand["bones"]["Finger"+str(i)]["pos"]) for i in range(1,5)]
    palm=tuple((wrist[j]+sum(p[j] for p in heads)/4)/2 for j in range(3))
    delta=tuple((x-y)/scale for x,y in zip(palm,vector(raw["pos"])))
    point=tuple(dot(rotate(v,raw["ang"]),delta) for v in ((1,0,0),(0,1,0),(0,0,1)))
    d=sub(point,handle["pos"]);axis=handle["axis"]
    return math.sqrt(sum((x-a*dot(d,axis))**2 for x,a in zip(d,axis)))


def left_axis(ang):
    p, y, r = map(math.radians, vector(ang))
    return (math.sin(r)*math.sin(p)*math.cos(y)-math.cos(r)*math.sin(y),
            math.sin(r)*math.sin(p)*math.sin(y)+math.cos(r)*math.cos(y), math.sin(r)*math.cos(p))


def grasp_circle(hand):
    a,b,c = (vector(hand["bones"][name]["pos"]) for name in ("Finger2","Finger21","Finger22"))
    u,v=sub(b,a),sub(c,a)
    def cross(x,y):
        return (x[1]*y[2]-x[2]*y[1], x[2]*y[0]-x[0]*y[2], x[0]*y[1]-x[1]*y[0])
    n=cross(u,v)
    denom=2*dot(n,n)
    if denom < 1e-10:
        raise ValueError("collinear grasp joints")
    x,y=cross(v,n),cross(n,u)
    return tuple(p+(i*dot(u,u)+j*dot(v,v))/denom for p,i,j in zip(a,x,y))


def grip_checks(actual,closed,mount,shaft=False):
    # The bonemerge mount and avatar wrist are different rig landmarks. Keep their
    # distance as metrology, not a proxy for the selected physical handle region.
    return {'independent_grip':actual is not None and actual<.005,
            'closed_grasp':closed is None or closed<.005,
            'finite_mount':math.isfinite(mount),'shaft_wrist_envelope':not shaft or mount<.12}


def analyse(evidence, phases):
    rows = json.loads((evidence / "frames.json").read_text(encoding="utf-8"))
    captures = {(r["label"], r["diagnostic"]): r for r in rows if r["kind"] == "capture"}
    issues, metrics = [], {}
    fixture=json.loads((evidence/"frames-fixture.json").read_text(encoding="utf-8"))
    raw_hands=fixture.get("raw_hands",False)
    models=json.loads(Path(fixture["controllers"]).read_text(encoding="utf-8"))
    handles={"left" if "_left" in m["path"] else "right":m.get("handle") for m in models}

    def require(value, message):
        if not value:
            issues.append(message)

    require(any(r["kind"] == "off" and not r["global"] for r in rows), "missing clean C probe Exit")
    require(any(r["kind"] == "settings" and r["restored"] for r in rows), "C probe settings not restored")
    expanded=[]
    for label,cls,dominant in phases:
        expanded.extend([(label+"-"+str(i),cls,dominant) for i in range(4)] if label.startswith("sweep-") else [(label,cls,dominant)])
    for label, cls, dominant in expanded:
        raw_hands=fixture.get("raw_hands",False) or (fixture.get("mixed_raw",False) and label.startswith("raw-"))
        for diagnostic in ((True,) if label.startswith("sweep-") else (False, True)):
            row = captures.get((label, diagnostic))
            key = label + ("-controller" if diagnostic else "-hands")
            require(row is not None, key+": missing receipt")
            if row is None:
                continue
            require(row.get("mouse_commands",1)>0,key+": scripted camera input fixture did not run")
            folder = evidence / "captures" / row["capture"]
            for file in ("left.png", "right.png", "centre.png", "mirror.png", "timings.json"):
                require((folder / file).is_file(), key+": missing "+file)
            metrics[key] = result = {}
            for side in ("left", "right"):
                f = row["frames"][side]
                require(not f["valid"] if raw_hands else f["valid"], key+": wrong "+side+" controller-component mode")
                ray = vector(row["rays"][side]["dir"])
                level = math.degrees(math.asin(min(1, abs(ray[2]))))
                require(level < .5, key+": "+side+" ray not level")
                hand = row.get(side)
                require(hand is not None, key+": no drawn "+side+" wrist")
                result[side] = {"ray_level_deg": level, "source": f["source"], "model": f["model"], "skeleton": f["skeleton"]}
                if hand:
                    if raw_hands:
                        result[side]["palm_up_z"]=vector(hand["palm_up"])[2]
                        require(result[side]["palm_up_z"]>.95,key+": "+side+" raw palm thumb side points down")
                    result[side]["wrist_error_m"] = distance(hand["bones"]["Hand"]["pos"], f["wrist"]["pos"])/row["scale"]
                    result[side]["palm_offset_m"] = distance(f["hand"]["pos"], f["raw"]["pos"])/row["scale"]
                    normal = tuple(x*(1 if side == "right" else -1) for x in left_axis(row["shown"][side]["ang"]))
                    frame = row["hands"][side].get("palm_frame")
                    if frame:
                        normal = rotate(rotate((0, 1 if side == "right" else -1, 0), frame.get("anatomy",frame["ang"])), hand["bones"]["Hand"]["ang"])
                    target_normal = tuple(x*(1 if side == "right" else -1) for x in left_axis(f["hand"]["ang"]))
                    normal_angle = degrees(normal, target_normal)
                    result[side]["palm_normal_from_target_deg"] = normal_angle
                    require(normal_angle < 60, key+": "+side+" palm faces away from the controller grip")
                    if f["skeleton"]:
                        result[side]["skeleton_palm_normal_deg"] = degrees(normal, rotate(f["skeleton_normal"], f["raw"]["ang"]))
                    curls = row["hands"][side]["curls"]
                    inward = {}
                    for i in range(1, 5):
                        start, end = hand["bones"].get("Finger"+str(i)), hand["bones"].get("Finger"+str(i)+"2")
                        if start and end and curls[i] > .45:
                            amount = dot(sub(vector(end["pos"]), vector(start["pos"])), normal)/row["scale"]
                            inward[str(i)] = amount
                            require(amount > .005, key+": "+side+" finger "+str(i)+" curls away from the palm")
                    result[side]["finger_inward_m"] = inward
                    def raw_point(p):
                        delta=tuple((a-b)/row["scale"] for a,b in zip(vector(p),vector(f["raw"]["pos"])))
                        axes=[rotate(v,f["raw"]["ang"]) for v in ((1,0,0),(0,1,0),(0,0,1))]
                        return tuple(dot(a,delta) for a in axes)
                    handle=handles.get(side)
                    if handle and not raw_hands:
                        target={"pos":source(handle["pos"]),"axis":source(handle["axis"])}
                        palm_distance=palm_axis_distance(hand,f["raw"],row["scale"],target)
                        result[side]["palm_handle_axis_m"]=palm_distance
                        require(palm_distance<.05,key+": "+side+" rendered palm is too far from handle")
                        refs=row.get("skeletons",{}).get(side,{})
                        if not isinstance(refs,dict):refs={}
                        kind="grip_limit" if "grip_limit" in row["hands"][side].get("skeletal_source","") else "with_controller"
                        selected=refs.get(kind)
                        require(bool(selected and selected.get("valid")),key+": "+side+" matching SDK source missing")
                        closed=kind=="grip_limit" or bool(selected and selected.get("pose_from")=="grip_limit" and selected.get("blend",0)==0)
                        result[side]["axis_required"]=closed
                        if closed:
                            points=[raw_point(hand["bones"]["Finger"+str(i)+joint]["pos"]) for i in range(1,5) for joint in ("","1")]
                            centres=[]
                            for i in range(1,5):
                                single={"bones":{"Finger2":hand["bones"]["Finger"+str(i)],"Finger21":hand["bones"]["Finger"+str(i)+"1"],"Finger22":hand["bones"]["Finger"+str(i)+"2"]}}
                                centres.append(raw_point(grasp_circle(single)))
                            tube=line(centres)
                            result[side]["arc_centre_axis"]=axis_error(tube,target)
                            fitted=cylinder(points,tube["axis"])
                            error=axis_error(fitted,target);error["radius_m"]=fitted["radius"]
                            result[side]["handle_axis"]=error
                            require(error["max_m"]<.015,key+": "+side+" closed grip misses handle")
                        if selected and selected.get("valid"):
                            def joint(id):
                                b=selected["bones"][id]
                                return vector(b["pos"]) if isinstance(b,dict) else tuple(b[:3])
                            meta={str(i):distance(raw_point(hand["bones"]["Finger"+str(i)]["pos"]),joint(7+(i-1)*5)) for i in range(1,5)}
                            meta["thumb"]=distance(raw_point(hand["bones"]["Finger01"]["pos"]),joint(3))
                            tips={str(i):distance(raw_point(hand["tips"][str(i+1)]["pos"]),joint(10+(i-1)*5)) for i in range(1,5) if str(i+1) in hand.get("tips",{})}
                            if "1" in hand.get("tips",{}):tips["thumb"]=distance(raw_point(hand["tips"]["1"]["pos"]),joint(5))
                            result[side]["sdk_reference"]={"source":selected.get("source"),"kind":kind,"recorded":selected.get("recorded",False),"pose_from":selected.get("pose_from"),"metacarpal_heads_m":meta,"fingertips_m":tips}
                            require(len(tips)==5,key+": "+side+" mesh tips missing")
                            require(max(list(meta.values())+list(tips.values()) or [1])<.02,key+": "+side+" joint/tip error exceeds 2 cm")
            a = row.get("weapon") or {}
            require(a.get("class") == cls and a.get("hand") == ("left" if dominant else "right"), key+": wrong active weapon/hand")
            if cls == "weapon_fists":
                require(row.get("weapon",{}).get("path")=="", key+": stock fists unexpectedly acquired a weapon model")
                require(row.get("weapon_debug",{}).get("model") in (None,""), key+": fist avatar replaced by a gun model")
            if cls not in ("nlvr_hands", "weapon_fists"):
                muzzle = row["muzzle"]
                gun_level = math.degrees(math.asin(min(1, abs(forward(muzzle["ang"])[2]))))
                angles = vector(muzzle["ang"])
                gun_roll = abs((angles[2]+180)%360-180)
                result["gun_level_deg"], result["gun_roll_deg"] = gun_level, gun_roll
                require(gun_level < 5 and gun_roll < 5, key+": gun not level/upright")
                if row.get("model_barrel"):
                    barrel_error=degrees(vector(row["model_barrel"]),vector(row["rays"]["left" if dominant else "right"]["dir"]))
                    up_error=degrees(vector(row["model_up"]),(0,0,1))
                    result["actual_barrel_deg"],result["actual_up_deg"]=barrel_error,up_error
                    require(barrel_error<5 and up_error<5,key+": actual model barrel/up is misaligned")
                main = row.get("left" if dominant else "right")
                if row.get("weapon_bone") and main:
                    error = distance(row["weapon_bone"]["pos"], main["bones"]["Hand"]["pos"])/row["scale"]
                    result["weapon_wrist_error_m"] = error
                    if row.get("actual_grip"):
                        method=row.get('actual_grip_method')
                        require(method in ('posed_mesh_and_rendered_hand_bones','raw_handle_centreline_and_drawn_fingers'),key+': independent holding-bone/mesh witness missing')
                        target=grasp_circle(main)
                        if method=='raw_handle_centreline_and_drawn_fingers':require(row.get('grip_bone_envelope') is True,key+': independent bone/handle envelope failed')
                        actual_error=distance(row["actual_grip"],target)/row["scale"]
                        result["actual_grip_error_m"]=actual_error
                        require(actual_error<.005,key+": actual model grip is outside the drawn grasp")
                    else:
                        require(False,key+": actual model grip evidence missing")
                    if row.get("weapon_grip"):
                        grip_error=distance(row["weapon_grip"],grasp_circle(main))/row["scale"]
                        result["closed_grip_error_m"]=grip_error
                        require(grip_error < .005,key+": weapon grip is outside the curled fingers")
                    for check,ok in grip_checks(result.get("actual_grip_error_m"),None,error,cls in ('weapon_crowbar','weapon_stunstick')).items():
                        require(ok,key+": "+check+" failed")
                if label.startswith(("smg","swep","raw-smg","raw-swep")):
                    require(a.get("twoHanded"), key+": absent SMG foregrip")
            if label == "laser":
                require(any(p["key"] == "spawn" for p in row["ui"]["panels"]), key+": spawn panel absent")
            # Fixed camera/poses make these reproducible without selecting a lucky frame.
            if (folder / "centre.png").is_file():
                from PIL import Image
                with Image.open(folder / "centre.png") as image:
                    w, h = image.size
                    target = evidence / "crops" / (key+".png")
                    target.parent.mkdir(parents=True, exist_ok=True)
                    image.crop((int(w*.30), int(h*.40), int(w*.72), int(h*.65))).resize((int(w*.84), int(h*.5))).save(target)
                    for side, bounds in {"left": (.34,.47,.51,.60), "right": (.49,.43,.67,.60)}.items():
                        cropped=image.crop(tuple(int(value*(w if i%2==0 else h)) for i,value in enumerate(bounds)))
                        cropped.resize((cropped.width*3,cropped.height*3)).save(target.with_name(key+"-"+side+".png"))
    model_equivalence={}
    for side in ("left","right"):
        for view in ("side","top"):
            label="swep-"+side+"-"+view
            a=captures.get(("smg-"+side+"-"+view,False));b=captures.get((label,False))
            if not a or not b:continue
            def local_model(row):
                hand=row["frames"][side]["hand"];debug=row["weapon_debug"]
                axes=[rotate(v,hand["ang"]) for v in ((1,0,0),(0,1,0),(0,0,1))]
                p=tuple((x-y)/row["scale"] for x,y in zip(vector(debug["model_pos"]),vector(hand["pos"])))
                f=forward(debug["model_ang"]);u=rotate((0,0,1),debug["model_ang"])
                return tuple(dot(x,p) for x in axes),tuple(dot(x,f) for x in axes),tuple(dot(x,u) for x in axes)
            ap,af,au=local_model(a);bp,bf,bu=local_model(b)
            error={"position_m":distance(ap,bp),"barrel_deg":degrees(af,bf),"up_deg":degrees(au,bu)}
            model_equivalence[label]=error
            require(a["weapon_debug"]["model"]==b["weapon_debug"]["model"]=="models/weapons/w_smg1.mdl",label+": wrong model in equivalence fixture")
            require(error["position_m"]<.001 and error["barrel_deg"]<.1 and error["up_deg"]<.1,label+": unprofiled placement differs from profiled SMG")
    sweeps={}
    for row in rows:
        if row.get("kind")!="sweep_stats":continue
        label=row["label"];d=row["data"];sweeps[label]=d
        require(d.get("frames",0)>30,label+": too few rendered sweep samples")
        for side in ("left","right"):
            a=d.get(side,{})
            require(all(k in a for k in ("reads","refits","ms","build_ms","changes")),label+": "+side+" missing sampler/cost evidence")
            require(a.get("anchor_m",0)<.1,label+": "+side+" gun anchor escaped own palm")
            require(a.get("grip_m",0)<.02,label+": "+side+" actual model grip escaped drawn fingers")
            require(a.get("refits",0)<=1,label+": "+side+" grasp refit per frame")
            seconds=20 if label.startswith("sweep-") else 7
            require(a.get("reads",0)<=d.get("frames",0)+4,label+": "+side+" duplicate skeletal reads in a render frame")
            if label.startswith("sweep-"):
                require(a.get("device_m",0)<.0001 and a.get("hmd_m",0)<.0001,label+": tracking moved during curl interval")
                require(a.get("wrist_m",1)<.005 and a.get("palm_m",1)<.005,label+": "+side+" wrist/palm moved with curl")
                require(a.get("roll_deg",180)<30,label+": "+side+" joint roll discontinuity")
                require(a.get("finger_m",0)>.02 and a.get("changes",0)>20,label+": "+side+" fingers were frozen")
                require(any("with_controller" in k for k in a.get("sources",{})),label+": unarmed live read path absent")
        require(d.get("measures",0)<=3,label+": repeated weapon model measurement")
    for label,cls,dominant in phases:
        require(label in sweeps,label+": missing per-frame checks")
        if cls not in ("nlvr_hands", "weapon_fists") and label in sweeps:
            holding=sweeps[label].get("left" if dominant else "right",{})
            require("anchor_m" in holding,label+": missing holding-hand anchor evidence")
            require("grip_m" in holding and holding.get("grip_samples",0)>30,label+": missing independent rendered grip samples")
    sources=sorted({r["frames"][side]["source"] for r in captures.values() for side in ("left","right")})
    reference_count=sum("sdk_reference" in r.get(s,{}) for r in metrics.values() for s in ("left","right"))
    return {"success": not issues, "issues": issues, "metrics": metrics, "capture_records": len(captures),
        "joint_comparison_complete":reference_count==len(captures)*2 and bool(captures),"joint_reference_count":reference_count,
        "controller_sources":sources,"sweeps":sweeps,"model_equivalence":model_equivalence,"live_controller_skeleton":all(r["frames"][s]["skeleton"] for r in captures.values() for s in ("left","right")) if captures else False}
