-- Test-only probe injected by vr_frames_poc.py; no part of the production package.
weapons.Register({Base="weapon_base",PrintName="C unprofiled SMG",WorldModel="models/weapons/w_smg1.mdl",ViewModel="",Spawnable=false,
    Primary={Ammo="SMG1",ClipSize=45,DefaultClip=45},Secondary={Ammo="none",ClipSize=-1,DefaultClip=-1}},"nlvr_frames_smg")
local reviewModels={crossbow="w_crossbow",pistol="w_pistol",shotgun="w_shotgun",ar2="w_irifle",annabelle="w_annabelle"}
for name,model in pairs(reviewModels) do weapons.Register({Base="weapon_base",WorldModel="models/weapons/"..model..".mdl",ViewModel="",Primary={Ammo="none",ClipSize=-1,DefaultClip=-1},Secondary={Ammo="none",ClipSize=-1,DefaultClip=-1}},"nlvr_frames_"..name) end
local function cPhase(time)
    for i,p in ipairs(CONFIG.frames_plan) do
        if time>=p.start and time<p.start+p.duration then return i-1,CONFIG.frames_phases[i],time-p.start,p.duration end
    end
end
local renderedHands,renderedWeapons={},{}
local Witness=include("nlvrcprobe/mesh_witness.lua")
local renderedBeam
local seen, finished, number, current, requested = false, false, 0, nil, {}
local savedDominant, savedTrim = GetConVar("nl_vr_dominant"):GetString(), GetConVar("nl_vr_gun_angle"):GetString()
local mouseCommands = 0
local function cEmit(value)
    local text = util.TableToJSON(value)
    number = number + 1
    local data = util.Base64Encode(text):gsub("%s", "")
    local count = math.ceil(#data/1600)
    for i=1,count do print("NLVR_C_CHUNK "..number.." "..i.."/"..count.." "..data:sub((i-1)*1600+1,i*1600)) end
end
local function drawnHand(side) return renderedHands[side] and renderedHands[side].hand end
hook.Add("PreRender","nlvr_c_monitor",function()
    if finished then return end
    if NLVR and not NLVR.cFrameProbe then
        seen, NLVR.cFrameProbe = true, true
        hook.Remove("CreateMove",ID)
        local entry=NLVR.Registry:Add({name="frames_probe",order=99,Start=function() end,Stop=function() end})
        local ctx=entry.ctx
        local function refreshWitness(side)
            local weapon,hand=renderedWeapons[side],renderedHands[side]
            if not weapon or not hand or weapon.number~=hand.number then return end
            local spec=CONFIG.frames_mesh_specs[weapon.snapshot.path]
            if not spec then return end
            weapon.point=Witness.Grip(weapon.snapshot,hand.hand,spec)
            weapon.method=weapon.point and (spec.kind=="shaft" and "posed_mesh_and_rendered_hand_bones" or "raw_handle_centreline_and_drawn_fingers")
            weapon.bone_ok,weapon.bone_error=Witness.BoneEnvelope(weapon.snapshot,hand.hand,spec)
            weapon.barrel=Witness.Barrel(weapon.snapshot,spec)
            if spec.kind=="shaft" then weapon.endpoint=Witness.End(weapon.snapshot,Witness.StrikeAxis(weapon.snapshot,spec)) end
        end
        local function handObserver(side,hand,matrices,raw)
            if not raw then return end
            local output={model=hand.model:GetModel(),bones={},tips={}}
            for _,suffix in ipairs({"Hand","Finger0","Finger01","Finger02","Finger1","Finger11","Finger12","Finger2","Finger21","Finger22","Finger3","Finger31","Finger32","Finger4","Finger41","Finger42"}) do
                local id=hand.model:LookupBone("ValveBiped.Bip01_"..(side=="left" and "L" or "R").."_"..suffix)
                local m=id and matrices[id]
                if m then output.bones[suffix]={pos=m:GetTranslation(),ang=m:GetAngles(),forward=m:GetForward():GetNormalized(),up=m:GetUp():GetNormalized()} end
            end
            for finger,tip in pairs(hand.tips or {}) do local m=matrices[tip.bone]
                if m then output.tips[tostring(finger)]={pos=m*tip.pos,method=tip.method} end
            end
            local wrist=matrices[hand.bones.wrist]
            if wrist and hand.frame then
                local up=(hand.frame.anatomy or hand.frame.ang):Up()
                output.palm_up=(wrist*up-wrist:GetTranslation()):GetNormalized()
            end
            local frame=table.Copy(NLVR.Debug.frames[side])
            frame.raw={valid=raw.valid,pos=Vector(raw.pos.x,raw.pos.y,raw.pos.z),ang=Angle(raw.ang.p,raw.ang.y,raw.ang.r)}
            local target=NLVR.Hand[side].target
            frame.hand={pos=target.pos,ang=target.ang}
            renderedHands[side]={hand=output,raw=frame.raw,frame=frame,number=FrameNumber(),shown=table.Copy(hand.shown),sample_time=hand.skeleton and hand.skeleton.sample_time}
            refreshWitness(side)
        end
        local function weaponObserver(active)
            local id=active.model:LookupBone("ValveBiped.Bip01_R_Hand") local wrist=id and active.model:GetBoneMatrix(id)
            renderedWeapons[active.hand]={number=FrameNumber(),snapshot=Witness.Snapshot(active.model),wrist=wrist and wrist:GetTranslation()}
            refreshWitness(active.hand)
        end
        local previousBeam=render.DrawBeam
        local function observeBeam(start,finish,...)
            local active=NLVR and NLVR.Weapon and NLVR.Weapon.Active
            local caller=debug.getinfo(2,"S")
            if active and active.kind=="physgun" and caller and caller.source:find("cl_tools.lua",1,true) then
                renderedBeam={pos=Vector(start.x,start.y,start.z),frame=FrameNumber(),source="observed_addon_cl_tools_beam_draw"}
            end
            return previousBeam(start,finish,...)
        end
        render.DrawBeam=observeBeam
        ctx.cleanup(function() if render.DrawBeam==observeBeam then render.DrawBeam=previousBeam end end)
        assert(not NLVR.HandDrawObserver and not NLVR.WeaponDrawObserver,"foreign draw observer")
        NLVR.HandDrawObserver,NLVR.WeaponDrawObserver=handObserver,weaponObserver
        ctx.cleanup(function()
            if NLVR and NLVR.HandDrawObserver==handObserver then NLVR.HandDrawObserver=nil end
            if NLVR and NLVR.WeaponDrawObserver==weaponObserver then NLVR.WeaponDrawObserver=nil end
        end)

        -- Scripted orthogonal views must not inherit unrelated desktop mouse turns.
        -- CUserCmd deltas are test input; no engine/user sensitivity setting changes.
        ctx.mover(-100,function(cmd)
            cmd:SetMouseX(0) cmd:SetMouseY(0) mouseCommands=mouseCommands+1
        end)
        local recordedSkeletons=file.Exists("nlvrcprobe/skeletons.lua","LUA") and include("nlvrcprobe/skeletons.lua") or nil
        local skeletons,liveSkeletons,buffers,liveBuffers={},{},{},{}
        local function samples(queryLive)
            for _,side in ipairs({"left","right"}) do
                skeletons[side]=skeletons[side] or {} liveSkeletons[side]=liveSkeletons[side] or {}
                buffers[side]=buffers[side] or {} liveBuffers[side]=liveBuffers[side] or {}
                for _,kind in ipairs({"with_controller","fist","grip_limit","open"}) do
                    local sample
                    buffers[side][kind]=buffers[side][kind] or {}
                    local debug=NLVR.Debug.hands and NLVR.Debug.hands[side]
                    local when=debug and (debug.skeletal_source or ""):find(kind,1,true) and debug.skeleton_time or nil
                    if nlvr.Skeleton then sample=nlvr.Skeleton(side,kind,buffers[side][kind],when) end
                    if queryLive and not CONFIG.simulate and cOriginalSkeleton then
                        liveBuffers[side][kind]=liveBuffers[side][kind] or {}
                        liveSkeletons[side][kind]=cOriginalSkeleton(side,kind,liveBuffers[side][kind])
                    end
                    if not sample or not sample.valid then
                        local saved=recordedSkeletons and recordedSkeletons.samples and recordedSkeletons.samples[side] and recordedSkeletons.samples[side][kind]
                        if saved and saved.valid then sample=table.Copy(saved) sample.recorded=true end
                    end
                    skeletons[side][kind]=sample
                end
            end
        end
        samples()
        if CONFIG.frames_recorded_profiles then
            local function pulse(side)
                local ok,detail=nlvr.Haptic(side,.01,100,.05)
                return {ok=ok,detail=detail}
            end
            cEmit({kind="controller-availability",live=NLVR.Frame.controllers_live,left_haptic=pulse("left"),right_haptic=pulse("right")})
        end
        local meshes={}
        local material=CreateMaterial("nlvrc_controller_diagnostic","VertexLitGeneric",{["$basetexture"]="models/debug/debugwhite",
            ["$color"]="[0.2 0.45 0.75]",["$selfillum"]="1",["$selfillumtint"]="[0.2 0.45 0.75]",["$nocull"]="1"})
        for _,side in ipairs({"left","right"}) do
            local data=include("nlvrcprobe/"..side..".lua")
            local vertices,triangles={},{}
            for i,p in ipairs(data.vertices) do vertices[i]=Vector(-p[3],-p[1],p[2]) end
            for _,face in ipairs(data.faces) do
                local a,b,c=vertices[face[1]],vertices[face[2]],vertices[face[3]]
                local normal=(b-a):Cross(c-a):GetNormalized()
                for _,p in ipairs({a,b,c}) do triangles[#triangles+1]={pos=p,normal=normal,u=0,v=0} end
            end
            local object=Mesh(material) object:BuildFromTriangles(triangles) meshes[side]=object
        end
        ctx.cleanup(function() for _,m in pairs(meshes) do m:Destroy() end end)
        ctx.hook("PostDrawTranslucentRenderables",function(depth,sky)
            local sample=nlvr.TestState()
            if depth or sky or not sample then return end
            local _,phase,within=cPhase(sample.time)
            if not phase or not phase[1]:find("sweep-",1,true) and (within<3.5 or within>5.5) then return end
            samples()
            render.SetMaterial(material)
            for side,mesh in pairs(meshes) do
                local raw=renderedHands[side] and renderedHands[side].raw
                if raw and raw.valid then
                    local matrix=Matrix() matrix:SetTranslation(raw.pos) matrix:SetAngles(raw.ang)
                    matrix:Scale(Vector(NLVR.Space.scale,NLVR.Space.scale,NLVR.Space.scale))
                    cam.PushModelMatrix(matrix) mesh:Draw() cam.PopModelMatrix()
                    render.SetMaterial(Material("models/debug/debugwhite"))
                    for _,kind in ipairs({"with_controller","grip_limit","fist"}) do
                        local sample=skeletons[side] and skeletons[side][kind]
                        if sample and sample.valid then
                            for _,id in ipairs({1,2,3,4,5,6,7,8,10,11,12,13,15,16,17,18,20,21,22,23,25}) do
                                local b=sample.bones[id+1]
                                local p=b.pos or Vector(b[1],b[2],b[3])
                                local world=LocalToWorld(p*NLVR.Space.scale,Angle(),raw.pos,raw.ang)
                                render.DrawSphere(world,.0025*NLVR.Space.scale,7,7,kind=="with_controller" and Color(40,240,255) or kind=="grip_limit" and Color(255,70,230) or Color(255,210,30))
                            end
                        end
                    end
                end
            end
        end)
        local aggregate,aggregateLabel,prior={},nil,{}
        local function finishAggregate()
            if aggregateLabel then cEmit({kind="sweep_stats",label=aggregateLabel,data=aggregate}) end
            aggregate,aggregateLabel,prior={},nil,{}
        end
        ctx.cleanup(finishAggregate)
        local function rawVector(v,side,direction)
            local raw=renderedHands[side].raw
            if direction then return WorldToLocal(v,Angle(),Vector(),raw.ang) end
            return WorldToLocal(v,Angle(),raw.pos,raw.ang)/NLVR.Space.scale
        end
        local function stats(label)
            if aggregateLabel~=label then finishAggregate() aggregateLabel=label end
            aggregate.frames=(aggregate.frames or 0)+1
            for _,side in ipairs({"left","right"}) do
                local hand=drawnHand(side) local debug=NLVR.Debug.hands[side]
                if hand and renderedHands[side].number==FrameNumber() and hand.bones.Hand and hand.bones.Finger1 and hand.bones.Finger4 then
                    local wrist=rawVector(hand.bones.Hand.pos,side)
                    local palm=(wrist+(rawVector(hand.bones.Finger1.pos,side)+rawVector(hand.bones.Finger2.pos,side)+rawVector(hand.bones.Finger3.pos,side)+rawVector(hand.bones.Finger4.pos,side))/4)/2
                    local tip=rawVector(hand.tips["3"].pos,side)
                    local a=aggregate[side]
                    if not a then a={wrist=wrist,palm=palm,tip=tip,wrist_m=0,palm_m=0,roll_deg=0,finger_m=0,reads0=debug.skeleton_reads,refits0=debug.grasp_refits,changes0=debug.skeleton_changes,ms0=debug.skeleton_ms,build_ms0=debug.build_ms or 0,sources={},source=debug.skeletal_source} aggregate[side]=a end
                    a.wrist_m=math.max(a.wrist_m,wrist:Distance(a.wrist)) a.palm_m=math.max(a.palm_m,palm:Distance(a.palm)) a.finger_m=math.max(a.finger_m,tip:Distance(a.tip))
                    a.reads=debug.skeleton_reads-a.reads0 a.refits=debug.grasp_refits-a.refits0 a.ms=debug.skeleton_ms-a.ms0 a.build_ms=(debug.build_ms or 0)-a.build_ms0
                    a.changes=debug.skeleton_changes-a.changes0 a.sources[debug.skeletal_source or "none"]=(a.sources[debug.skeletal_source or "none"] or 0)+1
                    local tracking=NLVR.Frame[side] and NLVR.Frame[side].pos
                    local hmd=NLVR.Frame.hmd and NLVR.Frame.hmd.pos
                    if tracking and hmd then
                        a.device0,a.hmd0=a.device0 or tracking,a.hmd0 or hmd
                        a.device_m=math.max(a.device_m or 0,tracking:Distance(a.device0))
                        a.hmd_m=math.max(a.hmd_m or 0,hmd:Distance(a.hmd0))
                    end
                    prior[side]=prior[side] or {}
                    for name,b in pairs(hand.bones) do if name~="Hand" then
                        local f,u=rawVector(b.forward,side,true),rawVector(b.up,side,true)
                        local old=prior[side][name]
                        if old then
                            -- Parallel-transport the previous transverse axis by the shortest swing.
                            local axis=old.forward:Cross(f) local cosine=math.Clamp(old.forward:Dot(f),-1,1)
                            local transported=old.up
                            if axis:LengthSqr()>1e-10 then
                                local k=axis:GetNormalized() local sine=axis:Length()
                                transported=old.up*cosine+k:Cross(old.up)*sine+k*(k:Dot(old.up))*(1-cosine)
                            end
                            transported=transported-f*transported:Dot(f) u=u-f*u:Dot(f)
                            if transported:LengthSqr()>1e-8 and u:LengthSqr()>1e-8 then
                                local roll=math.deg(math.acos(math.Clamp(transported:GetNormalized():Dot(u:GetNormalized()),-1,1)))
                                a.roll_deg=math.max(a.roll_deg,roll)
                            end
                        end
                        prior[side][name]={forward=f,up=u}
                    end end
                    local active=NLVR.Weapon and NLVR.Weapon.Active
                    if active and active.hand==side and IsValid(active.model) then
                        local weapon=renderedWeapons[side]
                        local point=weapon and weapon.number==FrameNumber() and weapon.point
                        if point then
                            local p1,p2,p3=hand.bones.Finger2.pos,hand.bones.Finger21.pos,hand.bones.Finger22.pos
                            local u,v=p2-p1,p3-p1 local n=u:Cross(v)
                            if n:LengthSqr()>1e-12 then
                                local centre=p1+(v:Cross(n)*u:LengthSqr()+n:Cross(u)*v:LengthSqr())/(2*n:LengthSqr())
                                a.grip_m=math.max(a.grip_m or 0,point:Distance(centre)/NLVR.Space.scale)
                                a.grip_samples=(a.grip_samples or 0)+1
                            end
                            a.anchor_m=math.max(a.anchor_m or 0,rawVector(point,side):Distance(palm))
                        end
                    end
                end
            end
            local w=NLVR.Debug.weapons
            if w then
                aggregate.measures0=aggregate.measures0 or w.measures aggregate.measure_ms0=aggregate.measure_ms0 or w.measure_ms
                aggregate.measures=w.measures-aggregate.measures0 aggregate.measure_ms=w.measure_ms-aggregate.measure_ms0
            end
        end
        ctx.hook("PostRender",function()
            local sample=nlvr.TestState()
            if not sample then return end
            local slot,phase,within=cPhase(sample.time)
            if not phase then finishAggregate() return end
            local label,class,dominant=phase[1],phase[2],phase[3]
            if current~=label then
                samples()
                current=label NLVR_C_ACK=nil
                RunConsoleCommand("nl_vr_dominant",tostring(dominant)) RunConsoleCommand("nl_vr_gun_angle","0")
                RunConsoleCommand("nlvr_c_select",class,label=="teleport" and "walk" or "noclip")
                if label=="laser" then NLVR.Emit("ui_toggle","spawn") end
                if label=="teleport" then NLVR.Emit("ui_toggle","spawn") end
            elseif NLVR_C_ACK~=class and (not requested[label.."retry"] or sample.time-requested[label.."retry"]>.4) then
                requested[label.."retry"]=sample.time RunConsoleCommand("nlvr_c_select",class,label=="teleport" and "walk" or "noclip")
            end
            -- Camera tracking moves between views in the last .2 s of a phase.
            -- Measure articulation only after settling and before that transition.
            if NLVR_C_ACK==class and within>=1 and within<(phase[1]:find("sweep-",1,true) and 19.5 or 6.5) then stats(label) end
            local time=within
            local sweep=label:find("sweep-",1,true)~=nil
            local sampleIndex=sweep and math.min(3,math.floor(time/5)) or nil
            local diagnostic=sweep or time>=4.5
            local captureLabel=label..(sweep and "-"..sampleIndex or "")
            local key=captureLabel..(diagnostic and "-controller" or "-hands")
            local due=sweep and (sampleIndex*5+.5) or (diagnostic and 4.5 or 2.5)
            if time<due or time>due+.8 or requested[key] or NLVR_C_ACK~=class then return end
            samples(true)
            local ok=nlvr.Capture("frames-"..key,15)
            if not ok then return end
            requested[key]=true
            local a=NLVR.Weapon and NLVR.Weapon.Active
            local model=a and a.model
            local bone,attachment,modelGrip
            if IsValid(model) then
                local id=model:LookupBone("ValveBiped.Bip01_R_Hand") local m=id and model:GetBoneMatrix(id)
                if m then bone={pos=m:GetTranslation(),ang=m:GetAngles()} end
                if a.geometry.gripOffset then modelGrip=LocalToWorld(a.geometry.gripPos*(NLVR.Space.scale/40),Angle(),model:GetPos(),model:GetAngles()) end
                id=model:LookupAttachment("muzzle")
                if id and id>0 then attachment=model:GetAttachment(id) end
            end
            local rays={}
            for _,side in ipairs({"left","right"}) do local p,d=NLVR.Ray(side) rays[side]={pos=p,dir=d} end
            local muzzlePos,muzzleAng=NLVR.Weapon.Muzzle()
            local witness=a and renderedWeapons[a.hand]
            local barrel,modelUp
            if IsValid(model) then
                barrel=witness and witness.barrel modelUp=model:GetAngles():Up()
            end
            local muzzleWitness
            if a and a.kind=="physgun" then
                -- Read the asset's semantic emitter independently of either W/T's
                -- numeric fallback, then corroborate it against the actual beam draw.
                local coreId=IsValid(model) and model:LookupAttachment("core")
                local core=coreId and coreId>0 and model:GetAttachment(coreId)
                if core and renderedBeam and FrameNumber()-renderedBeam.frame<=1 then
                    muzzleWitness={pos=core.Pos,beam_pos=renderedBeam.pos,source="asset_named_core_and_addon_beam",independent_source="model_attachment_named_core",beam_source=renderedBeam.source}
                end
            elseif attachment then muzzleWitness={pos=attachment.Pos,source="engine_named_muzzle"} end
            cEmit({kind="capture",label=captureLabel,phase=label,diagnostic=diagnostic,time=sample.time,capture="frames-"..key,
                frames={left=renderedHands.left.frame,right=renderedHands.right.frame},hands=NLVR.Debug.hands,left=drawnHand("left"),right=drawnHand("right"),rays=rays,
                shown={left=renderedHands.left.shown,right=renderedHands.right.shown},
                weapon=a and {class=a.class,path=a.path,hand=a.hand,twoHanded=a.twoHanded,geometry=a.geometry},weapon_debug=NLVR.Debug.weapons,
                weapon_bone=bone,product_grip_diagnostic=modelGrip,actual_grip=witness and witness.point,actual_grip_method=witness and witness.method,grip_bone_envelope=witness and witness.bone_ok,grip_bone_residual=witness and witness.bone_error,mesh_end=witness and witness.endpoint,attachment=attachment,muzzle={pos=muzzlePos,ang=muzzleAng},muzzle_witness=muzzleWitness,ui=NLVR.Debug.ui,move=NLVR.Debug.move,
                model_barrel=barrel,model_up=modelUp,
                controllers=NLVR.Frame.controllers,controllers_live=NLVR.Frame.controllers_live,skeletons=skeletons,skeletons_live=liveSkeletons,recorded_input=cRecordedStats and cRecordedStats(),scale=NLVR.Space.scale,head=NLVR.Pose.head,
                mouse_commands=mouseCommands})
        end)
    elseif seen and not NLVR then
        finished=true
        RunConsoleCommand("nl_vr_dominant",savedDominant) RunConsoleCommand("nl_vr_gun_angle",savedTrim)
        cEmit({kind="off",global=NLVR~=nil}) hook.Remove("PreRender","nlvr_c_monitor")
        local deadline=RealTime()+1
        hook.Add("Think","nlvr_c_restoration",function()
            local restored=GetConVar("nl_vr_dominant"):GetString()==savedDominant and GetConVar("nl_vr_gun_angle"):GetString()==savedTrim
            if restored or RealTime()>=deadline then
                cEmit({kind="settings",restored=restored,dominant=GetConVar("nl_vr_dominant"):GetString(),trim=GetConVar("nl_vr_gun_angle"):GetString()})
                hook.Remove("Think","nlvr_c_restoration")
            end
        end)
    end
end)
