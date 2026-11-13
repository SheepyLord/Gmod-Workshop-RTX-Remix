-- Task-H-only fixture, prepended to a generated production probe, never shipped in the add-on.
local handsModels, handsOriginalModel, handsBegan = {}, ClientsideModel, SysTime()
local handsCaptureFrame
ClientsideModel = function(path, ...)
    local model = handsOriginalModel(path, ...)
    if IsValid(model) and path:find("c_arms", 1, true) then handsModels[#handsModels + 1] = model end
    return model
end
local handsSaved = {}
for _, name in ipairs({"nl_vr_dominant", "nl_vr_ghost_hands"}) do handsSaved[name] = GetConVar(name):GetString() end
RunConsoleCommand("nl_vr_dominant", "0") RunConsoleCommand("nl_vr_ghost_hands", "1")
-- Find a real map wall rather than introducing a prop that H deliberately does not collide with.
local handsOrigin = Vector(unpack(CONFIG.camera, 1, 3))
local handsHit
for _, yaw in ipairs({180, 90, 0, -90}) do
    local trace = util.TraceLine{start = handsOrigin, endpos = handsOrigin + Angle(0,yaw,0):Forward()*1500, mask = MASK_SOLID_BRUSHONLY}
    if trace.Hit and not trace.StartSolid and math.abs(trace.HitNormal.z)<0.1 then handsHit=trace break end
end
assert(handsHit, "The hands fixture needs a vertical world wall near its camera")
local handsEye = handsHit.HitPos + handsHit.HitNormal * 26
local handsAngle = (-handsHit.HitNormal):Angle()
CONFIG.camera = {handsEye.x,handsEye.y,handsEye.z,0,handsAngle.y,0}
RunConsoleCommand("nlvr_h_fixture",tostring(handsEye.x),tostring(handsEye.y),tostring(handsEye.z),tostring(handsAngle.y))
local handsActions, handsPhase, handsStopped
local function handsCurls(t)
    local curls={0,0,0,0,0}
    if t>=5 and t<30 then curls[math.min(5,math.floor((t-5)/5)+1)]=1
    elseif t>=30 and t<35 then curls={1,1,1,1,1} end
    return curls
end
hook.Add("PreRender","nlvr_hands_probe",function()
    if not NLVR or not nlvr or not nlvr.TestState then return end
    local timeline=nlvr.TestState()
    if not timeline then return end -- real SDK startup is asynchronous, unlike the fast virtual backend
    local t=timeline.time or 0
    if CONFIG.hands_legacy and not handsActions then
        handsActions=nlvr.Actions
        nlvr.Actions=function(...)
            local actions,err=handsActions(...)
            actions=actions or {}
            local sample=nlvr.TestState()
            local time=sample and sample.time or 0
            for _,side in ipairs({"left","right"}) do
                actions[side.."_skeleton"]={active=true,curls=handsCurls(time),splay={0.4,0.4,0.4,0.4}}
            end
            return actions,err
        end
    end
    local phase=t>=72 and 3 or t>=62 and 2 or t>=56 and 1 or 0
    if phase~=handsPhase then
        handsPhase=phase
        RunConsoleCommand("nl_vr_ghost_hands",phase==1 and "0" or "1")
        RunConsoleCommand("nl_vr_dominant",phase>=2 and "1" or "0")
        if phase==3 then RunConsoleCommand("nlvr_h_model") end
    end
end)
local function handsTestRecord(label)
    local value={label=label,debug=NLVR and NLVR.Debug.hands,dominant=NLVR and NLVR.Input.mainHand,
        player_model=LocalPlayer():GetModel(),
        wall={pos=handsHit.HitPos,normal=handsHit.HitNormal},models={},hands={}}
    if NLVR then
        for _,side in ipairs({"left","right"}) do
            local state=NLVR.Hand[side]
            if state then value.hands[side]={metres=(state.target.pos-NLVR.Pose.head.pos):Length()/NLVR.Space.scale,
                target={state.target.pos.x,state.target.pos.y,state.target.pos.z},
                shown={state.shown.pos.x,state.shown.pos.y,state.shown.pos.z}} end
        end
    end
    for _,ent in ipairs(handsModels) do
        if IsValid(ent) then
            local data={model=ent:GetModel(),skin=ent:GetSkin(),body={},bones={}}
            for _,side in ipairs({"L","R"}) do
                for _,suffix in ipairs({"Hand","Forearm","Finger0","Finger02","Finger1","Finger12","Finger22","Finger32","Finger42"}) do
                    local id=ent:LookupBone("ValveBiped.Bip01_"..side.."_"..suffix)
                    local m=id and ent:GetBoneMatrix(id)
                    if m then
                        local bone={pos=m:GetTranslation(),ang=m:GetAngles(),scale=m:GetScale()}
                        if suffix=="Finger0" or suffix=="Finger02" then
                            local applied=ent:GetManipulateBoneAngles(id)
                            bone.applied={applied.p,applied.y,applied.r}
                        end
                        data.bones[side..suffix]=bone
                    end
                end
            end
            for _,group in ipairs(ent:GetBodyGroups()) do data.body[tostring(group.id)]=ent:GetBodygroup(group.id) end
            value.models[#value.models+1]=data
        end
    end
    return value
end
local function handsTestStop()
    if handsStopped then return end
    handsStopped=true hook.Remove("PreRender","nlvr_hands_probe")
    if handsActions and nlvr then nlvr.Actions=handsActions end
    ClientsideModel=handsOriginalModel
    for name,value in pairs(handsSaved) do RunConsoleCommand(name,value) end
    local live=0 for _,ent in ipairs(handsModels) do if IsValid(ent) then live=live+1 end end
    print("NLVR_Q " .. util.TableToJSON({kind="hands-cleanup",seconds=SysTime()-handsBegan,
        models_live=live,models_created=#handsModels}))
end
