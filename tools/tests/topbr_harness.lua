-- Regression for the packaged client driver and independent imported-game setting.
SERVER=false BRANCH="x86-64"
file={Exists=function() return false end}
local vars,callbacks,commands,hooks,events={},{},{},{},{}
local calls={}
function Color(...) return {...} end
function MsgC(...) end
function tobool(v) return v==true or v==1 or v=="1" end
function isstring(v) return type(v)=="string" end
function istable(v) return type(v)=="table" end
function RealTime() return 100 end
function CreateClientConVar(name,value)
    if not vars[name] then
        local cv={value=value}
        function cv:GetBool() return tobool(self.value) end
        function cv:GetFloat() return tonumber(self.value) end
        function cv:GetInt() return math.floor(tonumber(self.value) or 0) end
        vars[name]=cv
    end
end
function GetConVar(name) return vars[name] end
function RunConsoleCommand(name,value)
    assert(vars[name],name)
    local old=vars[name].value vars[name].value=value
    if callbacks[name] then callbacks[name](name,old,value) end
end
cvars={AddChangeCallback=function(name,fn) callbacks[name]=fn end}
concommand={Add=function(name,fn) assert(not vars[name],"convar/command collision: "..name) commands[name]=fn end}
hook={Add=function(event,name,fn) hooks[name]=fn events[name]=event end}
-- The player's range (ADR 0229): a map with three BSP materials, one static prop model and one physics prop.
function IsValid(v) return v~=nil end
function math.Clamp(v,lo,hi) return math.min(math.max(v,lo),hi) end
local timers={}
timer={Simple=function(delay,fn) timers[#timers+1]=fn end}
local mapName="gm_scope"
local world={GetMaterials=function() return {"CONCRETE/FLOOR01","maps/gm_scope/nature/blend_grass_wvt_patch"} end}
game={GetWorld=function() return world end,GetMap=function() return mapName end}
NikNaks={CurrentMap={GetTextures=function() return {"glass/window01","CONCRETE/FLOOR01"} end,
    GetStaticPropModels=function() return {"models/props_c17/oildrum001.mdl"} end}}
RTXMaterialPipeline={ModelMaterialNames=function(model)
    assert(model=="models/props_c17/oildrum001.mdl") return {"models/props_c17/oildrum001"} end}
local crate={GetModel=function() return "models/props_junk/wood_crate001a.mdl" end,
    GetMaterials=function() return {"models/props_junk/wood_crate001a"} end,
    GetSubMaterial=function() return "" end}
ents={FindByClass=function(pattern) return pattern=="prop_physics*" and {crate} or {} end}
local enabled,gameEnabled=false,false
local tries,accepted=0,0
local p={}
p.IsInitialized=function() return true end
p.SetEnabled=function(v) enabled=v end
p.SetGameEnabled=function(v) gameEnabled=v end
p.SetDebugOutput=function(v) calls.debug=v end
p.SetMetallicGeneration=function(v) calls.metal=v end
p.SetAutoDiscover=function(v) calls.discover=v end
p.SetParseCommentedProperties=function(v) calls.comments=v end
p.GetStats=function() return {} end
p.PumpSnapshots=function() calls.pump=(calls.pump or 0)+1 end
p.IsProcessingInBackground=function() return false end
p.GetQueuedMaterialCount=function() return 0 end
p.GetLastProcessedCount=function() return 0 end
p.ClearCache=function() calls.clear=true end
p.QueueMaterialsForProcessing=function() calls.queue=true calls.queueAtScope=calls.scopeSent end
local scopeNames={}
p.ClearScope=function() scopeNames={} calls.scopeCleared=(calls.scopeCleared or 0)+1 end
p.AllowScopeMaterials=function(names)
    for _,name in ipairs(names) do scopeNames[name]=true end
    calls.scopeSent=(calls.scopeSent or 0)+1
    return #names
end
p.QueueGameMaterial=function(name,source,base)
    assert(name=="mmd/0123456789abcdef/material_0")
    assert(source=="E:/models/test.pmx" and base=="tex/test_D.png")
    tries=tries+1
    if tries>1 then accepted=accepted+1 return true end
    return false
end
MaterialPipeline={ToPBR=p}
dofile(arg[1])
assert(vars.rtx_topbr_enabled.value=="0")
assert(vars.rtx_topbr_parse_commented_properties.value=="0")
assert(vars.rtx_topbr_game_maps:GetBool())
commands.rtx_topbr_stats() -- Removed APIs must never be called.
RunConsoleCommand("rtx_topbr_debug","1") assert(calls.debug==true)
RunConsoleCommand("rtx_topbr_autodiscover","0") assert(calls.discover==false)
RunConsoleCommand("rtx_topbr_enabled","1") assert(enabled)
-- Issue 6 (ADR 0212): turning ToPBR on queues the materials already drawn; no map reload is needed.
assert(calls.queue, "enabling queues the tracked materials") calls.queue=nil
RunConsoleCommand("rtx_topbr_enabled","0") assert(not enabled and not calls.queue)
RunConsoleCommand("rtx_topbr_enabled","1") assert(enabled and calls.queue)
RunConsoleCommand("rtx_topbr_game_maps","0") assert(not gameEnabled and enabled)
RunConsoleCommand("rtx_topbr_game_maps","1") assert(gameEnabled)
local id=string.rep("a",64)
mmdhl = {assets = {}, library = {entries = {}}}
mmdhl.assets[id] = {materials = {{path = "mmd/0123456789abcdef/material_0"}}}
mmdhl.library.entries[id] = {source = "E:/models/test.pmx", info = {materials = {{base = "tex/test_D.png"}}}}

for _=1,3 do hooks.RTXToPBR_GameMaps() end
assert(tries==1 and accepted==0)
-- Advance the sweep interval: unavailable live hashes must retry.
function RealTime() return 106 end
hooks.RTXToPBR_GameMaps()
assert(tries==2 and accepted==1)
function RealTime() return 112 end
hooks.RTXToPBR_GameMaps()
assert(tries==2 and accepted==1) -- successful requests are one-time per client session
-- Missing source/base metadata still reaches the native texture-identity registry.
local missingTries=0
p.QueueGameMaterial=function(name,source,base)
    assert(name=="mmd/0123456789abcdef/material_0")
    assert(source=="" and base=="")
    missingTries=missingTries+1
    return true
end
mmdhl.library.entries[id]=nil
commands.rtx_topbr_clear() assert(calls.clear)
hooks.RTXToPBR_GameMaps() assert(missingTries==1)
RunConsoleCommand("rtx_topbr_game_maps","0")
commands.rtx_topbr_clear()
hooks.RTXToPBR_GameMaps() assert(missingTries==1)
RunConsoleCommand("rtx_topbr_game_maps","1")
hooks.RTXToPBR_GameMaps() assert(missingTries==2)
hooks.RTXToPBR_Snapshots() assert(calls.pump==1)
-- R23 (the user's item 3): imported game materials still converting, for the companion's progress notice.
local states={}
p.GetGameMaterial=function(name) return {state=states[name] or "waiting"} end
local queued=0
p.QueueGameMaterial=function() queued=queued+1 return true end
commands.rtx_topbr_clear()
mmdhl.library.entries[id]={source="E:/models/test.pmx",info={materials={{base="tex/test_D.png"}}}}
hooks.RTXToPBR_GameMaps() assert(queued==1)
local pending,total=RTXGamePBRProgress() assert(pending==1 and total==1, "one converting")
pending,total=RTXGamePBRProgress() assert(pending==1 and total==1, "still waiting")
states["mmd/0123456789abcdef/material_0"]="automatic"
pending,total=RTXGamePBRProgress() assert(pending==0 and total==0, "the batch ends once its view is final")
p.GetGameMaterial=function() error("native view failed") end
commands.rtx_topbr_clear() hooks.RTXToPBR_GameMaps() assert(queued==2)
pending,total=RTXGamePBRProgress() assert(pending==0 and total==0, "an unreadable view counts as finished")

-- The player's range (the user's request of 2026-11-16, ADR 0229).
assert(vars.rtx_topbr_scope and vars.rtx_topbr_scope.value=="0", "the map's own surfaces by default")
calls.queue,calls.scopeSent,calls.scopeCleared,calls.clear=nil,nil,nil,nil
hooks.RTXToPBR_Scope()
assert(calls.scopeCleared==1 and calls.scopeSent==1, "a map's start sends a fresh list")
assert(scopeNames["CONCRETE/FLOOR01"] and scopeNames["maps/gm_scope/nature/blend_grass_wvt_patch"], "the world's materials")
assert(scopeNames["glass/window01"], "the BSP's whole texture list (brush entities, overlays)")
assert(not scopeNames["models/props_c17/oildrum001"] and not scopeNames["models/props_junk/wood_crate001a"], "no props by default")
assert(calls.queue and calls.queueAtScope==1, "with ToPBR on, the drawn materials are queued after the names")
assert(#timers==1, "a second pass once NikNaks has read the BSP") timers[1]() timers={}
-- Props in range: static prop models and prop entities; a narrower range clears what the wider one converted.
calls.clear=nil
RunConsoleCommand("rtx_topbr_scope","1")
assert(not calls.clear, "a wider range keeps what was converted")
assert(scopeNames["models/props_c17/oildrum001"] and scopeNames["models/props_junk/wood_crate001a"], "props named")
assert(scopeNames["CONCRETE/FLOOR01"], "and the map's surfaces")
local sent=calls.scopeSent
function RealTime() return 200 end
hooks.RTXToPBR_ScopeProps()
assert(calls.scopeSent==sent, "a prop seen before is not sent again")
crate.GetModel=function() return "models/props_junk/wood_crate002a.mdl" end
crate.GetMaterials=function() return {"models/props_junk/wood_crate002a"} end
function RealTime() return 203 end
hooks.RTXToPBR_ScopeProps()
assert(scopeNames["models/props_junk/wood_crate002a"], "a prop whose model changed is named again")
RunConsoleCommand("rtx_topbr_scope","2")
assert(not calls.clear and next(scopeNames)==nil, "everything: no names, nothing cleared")
RunConsoleCommand("rtx_topbr_scope","0")
assert(calls.clear, "back to the map's surfaces: the cache is cleared")
assert(scopeNames["CONCRETE/FLOOR01"] and not scopeNames["models/props_junk/wood_crate001a"], "only the map's surfaces again")
-- Turning ToPBR on in a new map sends that map's names before it queues.
mapName="gm_other"
calls.scopeSent=nil
RunConsoleCommand("rtx_topbr_enabled","0") RunConsoleCommand("rtx_topbr_enabled","1")
assert(calls.scopeSent==1 and calls.queueAtScope==1, "names first, then the queue")

-- A character imported again in the same game (ADR 0263). The Model Hotloader runs MMDHL.Imported with the full asset
-- id (64 hex digits); the character's material names start with "mmd/" and its first 16.
assert(events.RTXToPBR_GameRescan=="MMDHL.Imported", "the import hook listens to the Model Hotloader's import event")
local idA="0123456789abcdef"..string.rep("0",48)
local idB=string.rep("b",64)
local nameA1,nameA2,nameB="mmd/0123456789abcdef/skin_1","mmd/0123456789abcdef/hair_2","mmd/bbbbbbbbbbbbbbbb/body_1"
mmdhl={assets={},library={entries={}}}
mmdhl.assets[idA]={materials={{path=nameA1},{path=nameA2}}}
mmdhl.assets[idB]={materials={{path=nameB}}}
mmdhl.library.entries[idA]={source="E:\\models\\a\\a.pmx",info={materials={{base="tex/a_D.png"},{base="tex/hair_D.png"}}}}
mmdhl.library.entries[idB]={source="E:\\models\\b\\b.pmx",info={materials={{base="tex/b_D.png"}}}}
local submitted,rescans,rescanAnswer={},{},true
p.QueueGameMaterial=function(name) submitted[#submitted+1]=name return true end
p.GetGameMaterial=function() return {state="waiting"} end
p.RescanGameSource=function(source,prefix) rescans[#rescans+1]={source,prefix} return rescanAnswer end
local function sorted(list) local copy={} for i,v in ipairs(list) do copy[i]=v end table.sort(copy) return table.concat(copy,",") end
commands.rtx_topbr_clear()
function RealTime() return 300 end
for _=1,3 do hooks.RTXToPBR_GameMaps() end
assert(sorted(submitted)==sorted({nameA1,nameA2,nameB}), "each material submitted once: "..sorted(submitted))
pending,total=RTXGamePBRProgress() assert(pending==3 and total==3, "three converting")
submitted={}
assert(select("#",hooks.RTXToPBR_GameRescan(idA))==0, "the hook returns nothing (hook.Run stops at a returned value)")
assert(#rescans==1 and rescans[1][1]=="E:\\models\\a\\a.pmx" and rescans[1][2]=="mmd/0123456789abcdef/",
    "the native converter looks at the model's folder again, with the full id's library source and its 16-digit prefix")
pending,total=RTXGamePBRProgress() assert(pending==1 and total==1, "the character's materials leave the batch until submitted again")
hooks.RTXToPBR_GameMaps() -- the same moment: the pass starts at once, not five seconds later
assert(sorted(submitted)==sorted({nameA1,nameA2}), "the character's materials submitted again, the other's not: "..sorted(submitted))
pending,total=RTXGamePBRProgress() assert(pending==3 and total==3, "each counts once in the batch")
submitted={}
function RealTime() return 310 end
for _=1,3 do hooks.RTXToPBR_GameMaps() end
assert(#submitted==0, "once again, not at every pass")
-- A refused or failing rescan changes nothing in the driver.
rescanAnswer=false
hooks.RTXToPBR_GameRescan(idA)
assert(#rescans==2, "asked")
function RealTime() return 320 end
for _=1,3 do hooks.RTXToPBR_GameMaps() end
assert(#submitted==0, "a refused rescan: nothing submitted again")
p.RescanGameSource=function() error("native failure") end
hooks.RTXToPBR_GameRescan(idA)
function RealTime() return 330 end
for _=1,3 do hooks.RTXToPBR_GameMaps() end
assert(#submitted==0, "a failing rescan: nothing submitted again")
-- A module without RescanGameSource: the submissions start again, nothing else.
p.RescanGameSource=nil
hooks.RTXToPBR_GameRescan(idB)
hooks.RTXToPBR_GameMaps()
assert(sorted(submitted)==nameB, "an older module: the character's materials submitted again")
-- Ids and library entries it does not take: nothing asked, nothing submitted again.
submitted={}
p.RescanGameSource=function(source,prefix) rescans[#rescans+1]={source,prefix} return true end
local asked=#rescans
hooks.RTXToPBR_GameRescan(nil)
for _,bad in ipairs({42,"","0123456789abcdef",string.rep("a",63),string.rep("a",65),string.rep("A",64),
    string.rep("g",64),"0123456789abcdef/"..string.rep("0",47)}) do hooks.RTXToPBR_GameRescan(bad) end
assert(#rescans==asked, "a 16-digit, 63- or 65-digit, upper-case or non-hex id is refused")
local idC=string.rep("c",64)
hooks.RTXToPBR_GameRescan(idC) -- not in the library
mmdhl.library.entries[idC]={info={}} hooks.RTXToPBR_GameRescan(idC)
mmdhl.library.entries[idC]={source=""} hooks.RTXToPBR_GameRescan(idC)
mmdhl.library.entries[idC]={source=7} hooks.RTXToPBR_GameRescan(idC)
mmdhl.library.entries[idC]="broken" hooks.RTXToPBR_GameRescan(idC)
mmdhl.library.entries=nil hooks.RTXToPBR_GameRescan(idA)
mmdhl.library=nil hooks.RTXToPBR_GameRescan(idA)
assert(#rescans==asked, "no library entry or no source: nothing asked")
function RealTime() return 400 end
for _=1,3 do hooks.RTXToPBR_GameMaps() end
assert(#submitted==0, "and nothing submitted again")
mmdhl=nil hooks.RTXToPBR_GameRescan(idA) assert(#rescans==asked, "without the Model Hotloader: nothing")
print("PASS ToPBR driver: diagnostics, settings, bounded metadata discovery, hash retry, source-less queue, clear/requeue, conversion progress, the player's range and a character imported again")
