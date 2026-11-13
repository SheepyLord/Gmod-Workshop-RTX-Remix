"""C's natural-hold production session, with a local-only SteamVR OBJ diagnostic fixture."""
from pathlib import Path
import base64
import hashlib
import json
import math
import subprocess
import sys

ROOT = Path(__file__).resolve().parents[2]
sys.path.insert(0, str(ROOT / "tools"))
import vr_session as driver
import poc_session as poc

SLOT = 7
PHASES = [("empty", "nlvr_hands", 0), ("pistol", "weapon_pistol", 0), ("smg", "weapon_smg1", 0),
          ("crowbar", "weapon_crowbar", 0), ("physgun", "weapon_physgun", 0),
          ("empty-left", "nlvr_hands", 1), ("pistol-left", "weapon_pistol", 1), ("smg-left", "weapon_smg1", 1),
          ("crowbar-left", "weapon_crowbar", 1), ("physgun-left", "weapon_physgun", 1), ("laser", "nlvr_hands", 0),
          ("teleport", "nlvr_hands", 0)]


def transpose(m):
    return list(map(list, zip(*m)))


def multiply(a, b):
    return [[sum(x*y for x, y in zip(row, col)) for col in zip(*b)] for row in a]


def mv(m, v):
    return [sum(a*b for a, b in zip(row, v)) for row in m]


def angle(m):
    return [math.degrees(math.atan2(-m[2][0], math.hypot(m[0][0], m[1][0]))),
            math.degrees(math.atan2(m[1][0], m[0][0])), math.degrees(math.atan2(m[2][1], m[2][2]))]


def controller_offsets():
    recorded = json.loads((ROOT / "vr/native/sim/index-v1.json").read_text(encoding="utf-8"))["controllers"]
    basis = [[0, 0, -1], [-1, 0, 0], [0, 1, 0]]
    offsets = {}
    for side, data in recorded.items():
        local = multiply(multiply(basis, [r[:3] for r in data["tip"]]), transpose(basis))
        raw = transpose(local)
        palm = [-.115,.000745696 if side=="left" else -.000745717,-.014331943 if side=="left" else -.013421153]
        offsets[side] = (raw, palm)
    return offsets


def duration(label):
    return 20 if label.startswith("sweep-") else SLOT


def phase_plan(phases):
    result=[];start=0
    for label,cls,dominant in phases:
        size=duration(label)
        result.append({"start":start,"duration":size,"label":label})
        start+=size
    return result


RAW_HANDS=False
MIXED_RAW=False

def timeline(seconds, phases):
    offsets = controller_offsets()
    if RAW_HANDS:offsets={s:([[1,0,0],[0,1,0],[0,0,1]],[0,0,0]) for s in ("left","right")}
    steps = []
    plan=phase_plan(phases)
    for n, (label, weapon_class, dominant) in enumerate(phases):
        phase_offsets=offsets if not label.startswith("raw-") else {s:([[1,0,0],[0,1,0],[0,0,1]],[0,0,0]) for s in ("left","right")}
        pose_label=label[4:] if label.startswith("raw-") else label
        size=plan[n]["duration"]
        points=(0,1,5,6,10,11,15,19.8) if size==20 else (0, .35, 1, 1.75, 2.1, 2.5, 3.5, 3.85, 5.25, 5.5, 6.8)
        for t in points:
            main = "left" if dominant else "right"
            palms = {"left": [.5, .18, 1.3], "right": [.5, -.18, 1.3]}
            fore = pose_label.startswith("smg") or pose_label.startswith("swep")
            if fore:
                palms[main] = [.47, 0, 1.3]
                palms["right" if dominant else "left"] = [.7, 0, 1.3]
            if label == "laser":
                palms["right"] = [.5, 0, 1.4]
            step = {"time": plan[n]["start"]+t, "hmd": {"pos": [0, 0, 1.6], "ang": [0 if label == "laser" else 22, 0, 0]}, "actions": {}}
            if label.endswith(("-side","-top")):
                focus=("right" if main=="left" else "left") if "-fore-" in label else main
                target=palms[focus]
                head=[target[0],target[1]+(.42 if focus=="left" else -.42),target[2]+.02] if label.endswith("-side") else [target[0]-.001,target[1],target[2]+.48]
                d=[p-h for p,h in zip(target,head)]
                step["hmd"]={"pos":head,"ang":[math.degrees(math.atan2(-d[2],math.hypot(d[0],d[1]))),math.degrees(math.atan2(d[1],d[0])),0]}
            for side in ("left", "right"):
                raw, local_palm = phase_offsets[side]
                offset = mv(raw, local_palm)
                step[side] = {"pos": [p-o for p, o in zip(palms[side], offset)], "ang": angle(raw)}
                quarter=size/4;part=min(3,int(t/quarter));f=0 if part==3 else max(0,(t/quarter-part-.2)/.8)
                values=(0,.68,1,.05);curl=values[part]+(values[min(3,part+1)]-values[part])*f
                step["actions"][side+"_skeleton"] = {"curls": [curl]*5, "splay": [0, 0, 0, 0]}
            if fore and t >= 1:
                step["actions"][("right" if dominant else "left")+"_grip"] = True
            if weapon_class=="weapon_physgun" and 1<=t<=6.8:
                step['actions'][main+'_trigger']=True
            if label == "teleport" and 1 <= t <= 5.5:
                step["actions"]["right_stick"] = [0, .95]
            steps.append(step)
    steps.append({**steps[-1], "time": max(seconds+5, sum(duration(p[0]) for p in phases)+3)})
    return {"version": 1, "steps": steps}


def controller_fixture(source, destination, skeleton_reference=None):
    """Read only the real SteamVR install; publish nothing and keep all derived files in out/."""
    steam = Path("C:/Program Files (x86)/Steam/steamapps/common/SteamVR/drivers/indexcontroller/resources/rendermodels")
    addon = destination / "addon/lua/nlvrcprobe"
    addon.mkdir(parents=True, exist_ok=True)
    (addon/'mesh_witness.lua').write_bytes(Path(__file__).with_name('vr_mesh_witness.lua').read_bytes())
    receipt = []
    for side in ("left", "right"):
        name = "valve_controller_knu_1_0_"+side
        obj = steam / name / (name+"_low_res.obj")
        vertices, faces = [], []
        for line in obj.read_text(encoding="utf-8").splitlines():
            fields = line.split()
            if fields and fields[0] == "v":
                vertices.append([round(float(x), 6) for x in fields[1:4]])
            elif fields and fields[0] == "f":
                polygon = [int(x.split("/")[0]) for x in fields[1:]]
                for i in range(1, len(polygon)-1):
                    faces.append([polygon[0], polygon[i], polygon[i+1]])
        if not vertices or not faces:
            raise ValueError("empty controller OBJ")
        lua = "return {vertices={"+",".join("{"+",".join(map(str, v))+"}" for v in vertices)+"},faces={"+",".join("{"+",".join(map(str, f))+"}" for f in faces)+"}}\n"
        (addon / (side+".lua")).write_text(lua, encoding="utf-8")
        receipt.append({"path": str(obj), "sha256": hashlib.sha256(obj.read_bytes()).hexdigest(), "vertices": len(vertices), "triangles": len(faces)})
        from vr_frames_geometry import handle_model
        body=steam/name/"body.obj"
        fit=handle_model(body,side)
        receipt[-1]["handle"]={"path":str(body),"sha256":hashlib.sha256(body.read_bytes()).hexdigest(),**fit}
    if skeleton_reference:
        reference=json.loads(Path(skeleton_reference).read_text(encoding="utf-8"))
        (addon/"skeletons.lua").write_text("return util.JSONToTable([==["+json.dumps(reference,separators=(",",":"))+"]==])\n",encoding="utf-8")
    driver.write_json(destination / "controller-sources.json", receipt)
    commands = [[sys.executable, "tools/package_content.py", "--id", "nlvrc-diagnostic", "--requires-remix", "--addon-as", "nlvrcprobe", str(addon.parents[1]), "--out", str(destination / "part"), "--force"],
                [sys.executable, "tools/package_workshop.py", "--part", str(source.resolve()), "--part", str(destination / "part"), "--id", "gmod-rtx-remix", "--version", "0.0.0-v4c.diagnostic", "--title", "C local controller diagnostic", "--out", str(destination / "package"), "--force"]]
    with (destination / "build.log").open("w", encoding="utf-8") as log:
        for command in commands:
            subprocess.run(command, cwd=ROOT, stdout=log, stderr=subprocess.STDOUT, check=True)
    return destination / "package"


def main(argv=None):
    argv = list(sys.argv[1:] if argv is None else argv)
    global RAW_HANDS,MIXED_RAW
    RAW_HANDS="--raw-hands" in argv
    if RAW_HANDS:argv.remove("--raw-hands")
    MIXED_RAW="--merge-check" in argv
    if MIXED_RAW:argv.remove("--merge-check")
    phases = PHASES
    sdk_pose="--sdk-pose" in argv
    if sdk_pose:
        argv.remove("--sdk-pose")
        if "--simulate" in argv:raise ValueError("--sdk-pose requires the real SDK")
    if "--orthogonal" in argv:
        argv.remove("--orthogonal")
        phases=[]
        for name,cls in [("empty","nlvr_hands"),("pistol","weapon_pistol"),("smg","weapon_smg1"),("swep","nlvr_frames_smg")]:
            for side,dominant in [("right",0),("left",1)]:
                for view in ("side","top"):
                    phases.append((name+"-"+side+"-"+view,cls,dominant))
                    if name=="smg":phases.append((name+"-"+side+"-fore-"+view,cls,dominant))
    if "--curl-sweep" in argv:
        argv.remove("--curl-sweep")
        phases=[("sweep-"+side+"-"+view,"nlvr_hands",dominant) for side,dominant in (("right",0),("left",1)) for view in ("side","top")]
    if "--review-left" in argv:
        argv.remove("--review-left")
        phases=[(name+"-"+side+"-"+view,cls,dominant) for name,cls in (("empty","nlvr_hands"),("pistol","weapon_pistol"),("smg","weapon_smg1")) for side,dominant in (("right",0),("left",1)) for view in ("side","top")]
        phases += [("smg-"+side+"-fore-"+view,"weapon_smg1",dominant) for side,dominant in (("right",0),("left",1)) for view in ("side","top")]
        phases += [("generic-"+name,"nlvr_frames_"+name,0) for name in ("crossbow","pistol","shotgun","ar2","annabelle")]
    if "--review-index" in argv:
        argv.remove("--review-index")
        phases=[("sweep-"+side+"-"+view,"nlvr_hands",dominant) for side,dominant in (("right",0),("left",1)) for view in ("side","top")]
        phases += [(name+"-left-"+view,cls,1) for name,cls in (("empty","nlvr_hands"),("pistol","weapon_pistol"),("smg","weapon_smg1")) for view in ("side","top")]
        phases += [("smg-left-fore-"+view,"weapon_smg1",1) for view in ("side","top")]
    if "--review-final" in argv:
        argv.remove("--review-final")
        phases=[("sweep-"+side+"-"+view,"nlvr_hands",dominant) for side,dominant in (("right",0),("left",1)) for view in ("side","top")]
        phases += [(name+"-"+side+"-"+view,cls,dominant) for name,cls in (("pistol","weapon_pistol"),("smg","weapon_smg1")) for side,dominant in (("right",0),("left",1)) for view in ("side","top")]
        phases += [("smg-"+side+"-fore-"+view,"weapon_smg1",dominant) for side,dominant in (("right",0),("left",1)) for view in ("side","top")]
    if MIXED_RAW:
        phases=[(prefix+name+"-"+side+"-"+view,cls,dominant) for prefix in ("","raw-") for name,cls in (("pistol","weapon_pistol"),("smg-fore","weapon_smg1")) for side,dominant in (("right",0),("left",1)) for view in ("side","top")]
    skeleton_reference=None
    if "--skeleton-reference" in argv:
        n=argv.index("--skeleton-reference");skeleton_reference=Path(argv[n+1]).resolve();del argv[n:n+2]
    recorded = "--recorded-controllers" in argv
    if recorded:
        argv.remove("--recorded-controllers")
        if "--simulate" in argv:
            raise ValueError("simulation already supplies recorded controller components")
    reuse = "--reuse-fixture" in argv
    if reuse:
        argv.remove("--reuse-fixture")
    if "--frames-short" in argv:
        argv.remove("--frames-short")
        phases = PHASES[:5]
    evidence = Path(argv[argv.index("--evidence")+1]).resolve()
    evidence.relative_to(ROOT / "out")
    i = argv.index("--package")+1
    if reuse:
        package = Path(argv[i]).resolve()
        package.relative_to(ROOT / "out")
        fixture = package.parent
        sources = json.loads((fixture / "controller-sources.json").read_text(encoding="utf-8"))
        for source in sources:
            if hashlib.sha256(Path(source["path"]).read_bytes()).hexdigest() != source["sha256"]:
                raise ValueError("SteamVR controller model changed; build a fresh fixture")
        if not package.is_dir():
            raise ValueError("--reuse-fixture requires C's existing development package folder")
        argv[i] = str(package)
    else:
        fixture = evidence.with_name(evidence.name+"-fixture")
        if fixture.exists():
            raise ValueError("use a fresh frame fixture folder")
        argv[i] = str(controller_fixture(Path(argv[i]), fixture,skeleton_reference))
    original_script, original_command, original_lock = driver.lua_script, driver.command, driver.ExclusiveLock

    class TaskLock(original_lock):
        def __init__(self, path, task, timeout=7200):
            super().__init__(path, "VR-V4-C controller frames", timeout)

    def script(path, settings):
        driver.write_json(path.parent / "frames-fixture.json", {"package": argv[i], "reused": reuse,
            "manifest_sha256": driver.sha256(Path(argv[i]) / "native/manifest.json"),
            "controllers": str(fixture / "controller-sources.json"), "raw_hands":RAW_HANDS,"mixed_raw":MIXED_RAW})
        settings["frames_phases"], settings["frames_slot"] = phases, SLOT
        settings["frames_query_reference"]=sdk_pose
        settings["frames_raw_hands"]=RAW_HANDS
        settings["frames_mixed_raw"]=MIXED_RAW
        settings["frames_mesh_specs"]={path:row['spec'] for path,row in json.loads((ROOT/'companion/tests/fixtures/vr_mesh_witnesses.json').read_text())['models'].items()}
        settings["frames_plan"]=phase_plan(phases)
        if skeleton_reference:
            snapshot=json.loads(skeleton_reference.read_text(encoding="utf-8"))
            settings["frames_source_poses"]=snapshot["samples"]
        if recorded:
            source=json.loads((ROOT / "vr/native/sim/index-v1.json").read_text(encoding="utf-8"))["controllers"]
            profiles={}
            basis=[[0,0,-1],[-1,0,0],[0,1,0]]
            for side,(natural,palm) in controller_offsets().items():
                data=source[side]
                profiles[side]={"model":data["model"],"aim":{"pos":mv(basis,[r[3] for r in data["tip"]]),"ang":angle(transpose(natural))},
                    "hand":{"pos":palm,"ang":angle(transpose(natural))},
                    "wrist":{"pos":mv(basis,[r[3] for r in data["wrist"]]),"ang":angle(multiply(multiply(basis,[r[:3] for r in data["wrist"]]),transpose(basis)))}}
            settings["frames_recorded_profiles"]=profiles
        original_script(path, settings)
        text = path.read_text(encoding="utf-8")
        if RAW_HANDS or MIXED_RAW:
            marker='local f, detail = originalBegin(...)'
            text=text.replace(marker,marker+'''
        local forceRaw=CONFIG.frames_raw_hands
        local state=native.TestState()
        if CONFIG.frames_mixed_raw and state then
            for _,phase in ipairs(CONFIG.frames_plan) do
                if state.time>=phase.start and state.time<phase.start+phase.duration then forceRaw=phase.label:sub(1,4)=="raw-" break end
            end
        end
        if f and forceRaw then
            f.controllers_live=f.controllers
            f.controllers={}
            for _,side in ipairs({"left","right"}) do
                f.controllers[side]={valid=false,model="raw_test_controller_"..side,source="raw_test",revision=1,device=4294967295,
                    aim={valid=false,pos=Vector(),ang=Angle()},hand={valid=false,pos=Vector(),ang=Angle()},wrist={valid=false,pos=Vector(),ang=Angle()}}
            end
        end''')

        if skeleton_reference:
            factory=Path(__file__).with_name("vr_frames_recorded.lua").read_text(encoding="utf-8")
            prelude="local cOriginalSkeleton,cRecordedStats\nlocal cRecordedFactory=(function()\n"+factory+"\nend)()\n"
            text=text.replace('local function restore_probe()',prelude+'local function restore_probe()')
            text=text.replace('originalCapture = native.Capture','originalCapture = native.Capture\n    cOriginalSkeleton=native.Skeleton\n    native.Skeleton,cRecordedStats=cRecordedFactory(CONFIG,native)')
            text=text.replace('native.BeginFrame, native.SetFrameCamera, native.OverlayCreate, native.Capture = originalBegin, originalCamera, originalCreate, originalCapture','native.BeginFrame, native.SetFrameCamera, native.OverlayCreate, native.Capture = originalBegin, originalCamera, originalCreate, originalCapture\n        if cOriginalSkeleton then native.Skeleton=cOriginalSkeleton end')
        if recorded:
            old='local f, detail = originalBegin(...)'
            if text.count(old)!=1:
                raise RuntimeError("shared BeginFrame probe site changed")
            replacement=old+'''
        if f then
            f.controllers_live=f.controllers
            local controllers={}
            for side,profile in pairs(CONFIG.frames_recorded_profiles) do
                local live=f.controllers and f.controllers[side]
                if live and live.valid then controllers[side]=live
                else
                    local data={valid=true,skeleton=false,revision=1,device=4294967295,
                        model=profile.model,source="recorded_index_controllers_absent",detail="test-only profile; live controller unavailable"}
                    for _,key in ipairs({"aim","hand","wrist"}) do
                        local p,a=profile[key].pos,profile[key].ang
                        data[key]={valid=true,pos=Vector(p[1],p[2],p[3]),ang=Angle(a[1],a[2],a[3])}
                    end
                    controllers[side]=data
                end
            end
            f.controllers=controllers
        end'''
            text=text.replace(old,replacement)

        for label in ("yaw-plus20", "yaw-minus20", "lean-left"):
            text = text.replace('capture("'+label+'")', 'do end')
        text += "\n"+Path(__file__).with_name("vr_frames_poc.lua").read_text(encoding="utf-8")
        path.write_text(text, encoding="utf-8")

    def command(args, folder, label, **kwargs):
        if label == "game":
            field = poc.game_processes(driver.FIELD)
            if field:
                main_root = driver.main_checkout()
                helper = main_root / "out/vr/v2/quit_field_game.py"
                with (folder / "field-quit.log").open("w", encoding="utf-8") as log:
                    code = subprocess.call([sys.executable, str(helper)], cwd=main_root, stdout=log, stderr=subprocess.STDOUT)
                driver.write_json(folder / "field-quit.json", {"pids": field, "helper": str(helper), "exit": code})
                if code or poc.game_processes(driver.FIELD):
                    raise RuntimeError("authorised normal field quit did not finish")
            extra_models={"crossbow":"w_crossbow","pistol":"w_pistol","shotgun":"w_shotgun","ar2":"w_irifle","annabelle":"w_annabelle"}
            registrations="\n".join('weapons.Register({Base="weapon_base",WorldModel="models/weapons/'+model+'.mdl",ViewModel="",Primary={Ammo="none",ClipSize=-1,DefaultClip=-1},Secondary={Ammo="none",ClipSize=-1,DefaultClip=-1}},"nlvr_frames_'+name+'")' for name,model in extra_models.items())
            server = registrations+"\n"+'''weapons.Register({Base="weapon_base",PrintName="C unprofiled SMG",WorldModel="models/weapons/w_smg1.mdl",ViewModel="",Spawnable=false,Primary={Ammo="SMG1",ClipSize=45,DefaultClip=45},Secondary={Ammo="none",ClipSize=-1,DefaultClip=-1}},"nlvr_frames_smg")
concommand.Add("nlvr_c_select",function(_,_,a)
local p=Entity(1) if not NLVR_SV or not NLVR_SV.Players[p] then return end
local c=a[1] if not p:HasWeapon(c) then p:Give(c,true) end p:SelectWeapon(c)
p:SetMoveType(a[2]=="walk" and MOVETYPE_WALK or MOVETYPE_NOCLIP)
p:SetHealth(87) p:SetArmor(43) p:SendLua("NLVR_C_ACK="..string.format("%q",c)) end)'''
            from vr_combined_session import stage_fixtures
            args=stage_fixtures(args,folder,server)
            arguments = folder / "game-arguments.json"
            driver.write_json(arguments, [str(v) for v in args[1:]])
            args = [Path(__file__).resolve(), "--poc-arguments", arguments]
        return original_command(args, folder, label, **kwargs)

    driver.ExclusiveLock, driver.lua_script, driver.command = TaskLock, script, command
    driver.timeline = lambda seconds: timeline(seconds, phases)
    result = driver.main(argv)
    console = evidence / "poc/game/console.log"
    if console.exists():
        rows, chunks = [], {}
        for line in console.read_text(encoding="utf-8", errors="replace").splitlines():
            if line.startswith("NLVR_C "):
                rows.append(json.loads(line[7:]))
            elif line.startswith("NLVR_C_CHUNK "):
                key, part, data = line[13:].split(" ", 2)
                index, count = map(int, part.split("/"))
                bucket = chunks.setdefault(key, {})
                bucket[index] = data
                if len(bucket) == count:
                    rows.append(json.loads(base64.b64decode("".join(bucket[n] for n in range(1, count+1)))))
                    del chunks[key]
        driver.write_json(evidence / "frames.json", rows)
        if chunks:
            raise RuntimeError("incomplete controller-frame records")
        from vr_frames_analyse import analyse
        checks = analyse(evidence, phases)
        driver.write_json(evidence / "frames-checks.json", checks)
        if not checks["success"]:
            print("C frame checks failed: "+"; ".join(checks["issues"]), file=sys.stderr)
            return 1
    return result


if __name__ == "__main__":
    if len(sys.argv) == 3 and sys.argv[1] == "--poc-arguments":
        raise SystemExit(poc.main(json.loads(Path(sys.argv[2]).read_text(encoding="utf-8"))))
    raise SystemExit(main())
