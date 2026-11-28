-- Run the actual WU pose helper and client probe with a mock Sandbox, two launches and no game.
local qa, scenario = unpack(arg)
local old = "7c6d7e466389899bbdd2c9d614e1dacbf8a1a62bfa1b2af0083742553aeda89c"
local new = "a95c9a34a5eec099b19769e8968b64fa2947e738d34fdb17711dd2ee170bde50"
local helena = "81b3caae0303d15a610ef213bd4c64366c9b9e2f6dda1eae2e5d5fa49a74c80b"
local hashes = {v1 = "663b8b295a042f8e8f448a8d4f4734d1d74b5f062d1368d0340cd38ca1bbae5a",
    v2 = "2747fec1c9ae250309ab6c9a01100d0a10bf874173f9be4d893a0b1c4dd83c59"}
local runId, clock, frame = "mock000000000001", 0, 0
local request, host, npc, hands, selector, approval, subjectData, retired, resumed
local disk, saves, json, rigs = {}, {}, {}, {}
local hooks, commands, mods, npcs, players, later, history, shots
local cache = "mmd_hotloader/"
local savePath = "saves/gm_flatgrass mock.gms"
local function noop() end
function istable(x) return type(x) == "table" end
function isstring(x) return type(x) == "string" end
function table.Copy(t) local r = {} for k,v in pairs(t) do r[k] = v end return r end
local function encode(x)
    if isstring(x) then return string.format("%q", x) end
    if not istable(x) then return tostring(x) end
    local parts = {}
    for k,v in pairs(x) do parts[#parts+1] = encode(k) .. ":" .. encode(v) end
    local raw = "{" .. table.concat(parts, ",") .. "}" json[raw] = x return raw
end
util = {TableToJSON = encode, JSONToTable = function(x) return istable(x) and x or json[x] end,
    SHA256 = function(raw)
        return raw == "Sandbox" and "67fc62497e85d81bc54ea07aa87dca6868cd470e95d7281155a8eb532ce60009" or hashes[raw:sub(1, 2)]
    end}
file = {Read = function(p, realm) return (realm == "MOD" and saves or disk)[p] end,
    Write = function(p, raw) disk[p] = raw end, Delete = function(p) disk[p] = nil end,
    Size = function(p) return saves[p] and #saves[p] or -1 end,
    Find = function(pattern, realm) assert(pattern == "saves/*.gms" and realm == "MOD")
        return saves[savePath] and {"gm_flatgrass mock.gms"} or {} end}
game = {SinglePlayer = function() return true end, GetMap = function() return "gm_flatgrass" end}
engine = {ActiveGamemode = function() return "sandbox" end}
gui = {IsGameUIVisible = function() return false end, IsConsoleVisible = function() return false end}
hook = {Add = function(e,k,f) hooks[e] = hooks[e] or {} hooks[e][k] = f end,
    Remove = function(e,k) if hooks[e] then hooks[e][k] = nil end end}
local function fire(event, ...) for _, f in pairs(hooks[event] or {}) do f(...) end end
concommand = {Add = function(name, f) commands[name] = f end}
duplicator = {RegisterEntityModifier = function(k, f) mods[k] = f end,
    StoreEntityModifier = function(e, k, data) assert(e == npc) subjectData = {name = k, data = data} end}
timer = {Simple = function(_, f) later[#later+1] = f end}
function RealTime() return clock end
function FrameNumber() return frame end
function AddCSLuaFile() end
function include(path) assert(path == "nl_wu/probe.lua") dofile(qa.."/workshop_update_probe.lua") end
local V = {} V.__index = V
function Vector(x,y,z) return setmetatable({x=x or 0,y=y or 0,z=z or 0},V) end
function V.__add(a,b) return Vector(a.x+b.x,a.y+b.y,a.z+b.z) end
function V.__sub(a,b) return Vector(a.x-b.x,a.y-b.y,a.z-b.z) end
function V.__mul(a,n) return Vector(a.x*n,a.y*n,a.z*n) end
function V:Dot(b) return self.x*b.x+self.y*b.y+self.z*b.z end
function V:Length() return math.sqrt(self:Dot(self)) end
function V:DistToSqr(b) local d=self-b return d:Dot(d) end
function Angle() return {y=0,Forward=function() return Vector(1,0,0) end,Right=function() return Vector(0,-1,0) end} end
V.Angle = Angle
util.TraceLine = function() return {Hit=true,HitNormal=Vector(0,0,1),HitPos=Vector(120,0,0)} end

local E = {} E.__index=E
function IsValid(e) return istable(e) and e.index~=nil and not e.removed end
function E:GetModel() return self.rig and self.rig.model or "" end
function E:GetClass() return self.class end
function E:EntIndex() return self.index end
function E:GetHands() return hands end
function E:GetNW2String(k) return self[k] or "" end
function E:SetNW2String(k,v) self[k]=v end
E.GetNW2Vector, E.SetNW2Vector = E.GetNW2String,E.SetNW2String
function E:GetPos() return self == host and Vector() or Vector(120,0,3) end
function E:EyePos() return Vector(0,0,64) end
E.GetEyeTrace, E.EyeAngles, E.SetEyeAngles = util.TraceLine,Angle,noop
E.SetSchedule, E.SetMoveType, E.SetAngles = noop,noop,noop
function E:LookupSequence(name) assert(name=="Reference") return 1 end
function E:GetSequence() return self.seq or 0 end
function E:ResetSequence(seq) self.seq=seq end
function E:GetSequenceName(seq) return seq==1 and "Reference" or "idle" end
function E:SetCycle(c) self.cycle=c end
function E:GetCycle() return self.cycle or 0 end
function E:SetPlaybackRate(rate) assert(rate==0) end
function E:GetNumPoseParameters() return 1 end
function E:GetPoseParameterName() return "aim_yaw" end
function E:SetPoseParameter(_,v) assert(v==0) end
function E:LookupBone(name) return ({["ValveBiped.Bip01_Head1"]=0, Eye_L=1, Eye_R=2})[name] end
function LocalPlayer() return host end
function Entity(i) return i==1 and host or (npc and i==npc.index and npc or nil) end
ents={FindByClass=function(class) assert(class=="npc_citizen") return IsValid(npc) and {npc} or {} end}
list={Get=function() return npcs end}
player_manager={AllValidModels=function() return players end}
function GetConVar(name) assert(name=="cl_playermodel") return {GetString=function() return selector end} end
local function rig(id,role)
    local digit=({citizen="1",player="2",arms="3"})[role]
    local key=string.rep(id==old and "a" or "b",15)..digit..string.rep(digit,16)
    local r={asset=id,role=role,key=key,scaleMultiplier=1.15,model="models/mmd/"..key:sub(1,16).."/carrier.mdl"}
    rigs[r.model]=r disk[cache.."rigs/"..key.."/rig.json"]=r
    return r
end
local function publish(r)
    approval.rigs[r.key]={asset=r.asset,role=r.role}
    if r.role=="citizen" then npcs["mmd_"..r.key:sub(1,16)]={MMDHLAsset=r.asset,MMDHLRig=r.key,Model=r.model} end
end
local function playerRig(id)
    host.rig,hands.rig=rig(id,"player"),rig(id,"arms")
    publish(host.rig) publish(hands.rig)
    host.MMDHLRig,host.MMDHLArms=host.rig.key,hands.rig.key
    approval.rigs[host.rig.key].arms=hands.rig.key
    selector="mmd_"..host.rig.key:sub(1,16) players[selector]=host.rig.model
end
local function citizen(id)
    npc=setmetatable({index=17,class="npc_citizen",rig=rig(id,"citizen")},E)
    local d=id==old and 2.756 or 2.607
    if scenario=="wrong_head" and request.phase=="v2" and id==new then d=2.756 end
    npc.MMDRenderPose={}
    for i,v in ipairs({Vector(120,0,60),Vector(120,-1,60+d),Vector(120,1,60+d)}) do
        npc.MMDRenderPose[i]={GetTranslation=function() return v end}
    end
    return npc
end
local printed=print
function print(line)
    assert(#line<500)
    printed(line)
    if line:sub(1,6)=="NL_WU " then history[#history+1]=json[line:sub(7)]
    elseif line:sub(1,8)=="NL_SHOT " then
        shots[#shots+1]=line:sub(9)
        local n=#shots
        later[#later+1]=function() commands.nl_shot_taken(nil,nil,{tostring(n)}) end
    end
end
function RunConsoleCommand(cmd,...)
    local args={...} assert(#table.concat({cmd,...}," ")<500)
    if cmd=="gm_save" then assert(subjectData and host.rig.asset==old) saves[savePath]="Sandbox"
    elseif cmd=="gm_load" then
        assert(request.phase=="v2" and args[1]==savePath and shots[1]=="wu_v2_head" and not shots[2])
        npc.removed=true
        if scenario=="reset_realm" then resumed=true end
        if scenario~="no_paste" then mods[subjectData.name](host,citizen(old),subjectData.data) end
    elseif cmd=="gmod_spawnnpc" then
        assert(request.phase=="v2" and args[2]=="none" and npcs[args[1]].MMDHLAsset==new)
        fire("PlayerSpawnedNPC",host,citizen(new))
    else assert(cmd=="nl_wu_aim") commands[cmd](host,cmd,args) end
end
local function setup(phase)
    hooks,commands,mods,npcs,players,later,history,shots={},{},{},{},{},{},{},{}
    request={phase=phase,token=runId,package=string.rep(phase=="v1" and "c" or "d",32)}
    local id=phase=="v1" and old or new
    disk["nl_wu/run.json"]=request
    local rel="assets/"..helena.."/manifest.json"
    disk[cache..rel]=phase..string.rep(" ",63245)
    local rows={}
    local w={state={assets={}},Busy=function() return frame<3 end,Key=function(k,a) return k..":"..a end,
        Replacement=function(a) return phase=="v2" and a==old and new or nil end}
    for asset,name in pairs({[id]="Faelynn (Gym Uniform)",[helena]="Helena (Dorm)"}) do
        rows[asset]={name=name,workshop={package=request.package}}
        w.state.assets["character:"..asset]={installed=true,sums={[rel]=hashes[phase]}}
    end
    if scenario=="duplicate" and phase=="v2" then rows[old]={name="Faelynn (Gym Uniform)"} end
    approval={rigs={}} disk[cache.."approved.json"]=approval
    disk[cache.."recent.json"]={uses={{id,1000}}}
    host,hands=setmetatable({index=1,class="player"},E),setmetatable({index=2,class="gmod_hands"},E)
    npc=nil
    if phase=="v2" then
        local before=util.JSONToTable(disk["nl_wu/baseline.json"])
        assert(before.selector==selector)
        publish(rig(new,"citizen")) playerRig(scenario=="old_player" and old or new)
    end
    mmdhl={workshop=w,library={entries=rows,Update=function(asset,settings)
        assert(phase=="v1" and asset==old and settings.spawn.scaleMultiplier==1.17) return true
    end},GetGlobalSettings=function() return {} end,GetArmsParts=noop,
        BodygroupSpawnState=noop,GetRigForModel=function(model) return rigs[model] end,
        GetAsset=function(e) return e.rig and e.rig.asset or "" end,GetRig=function(e) return e.rig end,
        GetInstance=function() return 1 end,
        RequestSpawn=function(asset,options,cb)
            assert(phase=="v1" and asset==old and options.scaleMultiplier==1.17)
            if options.role=="citizen" then citizen(old) publish(npc.rig) fire("MMDHLActorCreated",npc,npc.rig) cb("ready","",17)
            else assert(options.role=="player") playerRig(old) cb("ready","",1) end
            return true
        end}
    SERVER,CLIENT=true,false dofile(qa.."/workshop_update_pose.lua")
    SERVER,CLIENT=false,true dofile(qa.."/workshop_update_pose.lua")
    NL_WU_ACTIVE=nil dofile(qa.."/workshop_update_probe.lua")
end
for _,phase in ipairs({"v1","v2"}) do
    printed("HARNESS "..phase)
    setup(phase)
    for _=1,3200 do
        frame,clock=frame+1,clock+.26
        local due=later later={} for _,f in ipairs(due) do f() end
        if resumed then
            resumed=nil NL_WU_ACTIVE=nil
            hook.Remove("Think","NL.WU.Probe") hook.Remove("PostRender","NL.WU.Probe") hook.Remove("CalcView","NL.WU.Probe")
            fire("InitPostEntity")
        end
        fire("Think")
        if npc then npc.MMDPresentationFrame=(scenario=="stale_pose" and phase=="v2") and frame-1 or frame end
        fire("CalcView") fire("PostRender")
        if history[#history] and history[#history].event=="result" then break end
    end
    local last=assert(history[#history])
    assert(last.event=="result","probe did not finish")
    assert(last.ok==(phase=="v1" or scenario=="good" or scenario=="reset_realm"),last.reason or "unexpected probe verdict")
end
