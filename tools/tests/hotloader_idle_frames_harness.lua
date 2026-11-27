-- ADR 0273: the Model Hotloader's per-frame work with no character model, and with a few. Loads client.lua and
-- carrier.lua (which includes native_render.lua) in the client realm under LuaJIT, with the game's API stubbed, and
-- runs frames: the entity list, the natives' idle check and the per-frame hooks; a server_ scenario loads carrier.lua
-- in the server realm and runs its ticks. One scenario per run; prints PASS <scenario>, and for measure the counts of
-- a frame.
-- usage: luajit hotloader_idle_frames_harness.lua <scenario> <lua/mmdhl folder>
local scenario,folder=arg[1],arg[2]
local function noop() end
local function check(ok,why) if not ok then error('FAIL '..scenario..': '..why,2) end end
local serverRealm=scenario:sub(1,7)=='server_'
SERVER,CLIENT=serverRealm,not serverRealm
bit=require('bit')
EF_NODRAW=32 STUDIO_SHADOWDEPTHTEXTURE=1073741824 STUDIO_SSAODEPTHTEXTURE=536870912 RENDERGROUP_BOTH=9
RT_SIZE_NO_CHANGE=0 MATERIAL_RT_DEPTH_SEPARATE=1 NOTIFY_ERROR=1 VERSIONSTR='test' FCVAR_ARCHIVE=128
local now,frame=100,1
function RealTime() return now end
function SysTime() return now end
function CurTime() return now end
function FrameNumber() return frame end
function RealFrameTime() return 1/60 end
engine={TickCount=function() return frame end}
function ErrorNoHalt(text) error(text) end
function math.Clamp(v,low,high) return math.min(math.max(v,low),high) end
function istable(v) return type(v)=='table' end
function isstring(v) return type(v)=='string' end
function isnumber(v) return type(v)=='number' end
function isfunction(v) return type(v)=='function' end
function IsValid(v) return type(v)=='table' and v.valid~=false end
-- Vectors and angles, as much of them as the files use while these frames run.
local V={} V.__index=V
function Vector(x,y,z) return setmetatable({x=x or 0,y=y or 0,z=z or 0},V) end
V.__unm=function(a) return Vector(-a.x,-a.y,-a.z) end
V.__add=function(a,b) return Vector(a.x+b.x,a.y+b.y,a.z+b.z) end
V.__sub=function(a,b) return Vector(a.x-b.x,a.y-b.y,a.z-b.z) end
V.__mul=function(a,b) if type(a)=='number' then a,b=b,a end return Vector(a.x*b,a.y*b,a.z*b) end
function V:GetNormalized() local l=math.sqrt(self.x^2+self.y^2+self.z^2) return Vector(self.x/l,self.y/l,self.z/l) end
function V:Angle() return {Right=function() return Vector(1,0,0) end,Up=function() return Vector(0,0,1) end,Forward=function() return Vector(0,1,0) end} end
function V:DistToSqr(o) return (self.x-o.x)^2+(self.y-o.y)^2+(self.z-o.z)^2 end
function EyePos() return Vector() end
function EyeAngles() return Vector():Angle() end
local function convar(default) local value=default return {GetBool=function() return tonumber(value)~=0 end,GetInt=function() return tonumber(value) or 0 end,
 GetFloat=function() return tonumber(value) or 0 end,SetInt=function(_,v) value=tostring(v) end,SetBool=function(_,v) value=v and '1' or '0' end} end
local convars={mat_queue_mode=convar('2')}
function CreateClientConVar(name,default) convars[name]=convars[name] or convar(default) return convars[name] end
CreateConVar=CreateClientConVar
function GetConVar(name) return convars[name] end
function RunConsoleCommand(name,value) if convars[name] then convars[name]=convar(value) end end
cvars={AddChangeCallback=noop}
scripted_ents={Register=noop}
function GetRenderTargetEx(name) return {GetName=function() return name end} end
net={Receive=noop,Start=noop,WriteString=noop,WriteUInt=noop,SendToServer=noop}
notification={AddLegacy=noop}
util={TableToJSON=function() return '{}' end,JSONToTable=function() return nil end,AddNetworkString=noop}
file={Exists=function() return false end,Read=function() return nil end,CreateDir=noop,Write=noop}

local hooks={}
hook={Add=function(event,id,fn) hooks[event]=hooks[event] or {} hooks[event][id]=fn end,
 Remove=function(event,id) if hooks[event] then hooks[event][id]=nil end end,
 Run=function(event,...) for _,fn in pairs(hooks[event] or {}) do fn(...) end end}
local function callHook(event,id,...) local fn=hooks[event] and hooks[event][id] check(fn,'no '..event..' hook '..id) return fn(...) end

-- Entities: an asset read is a check of whether the entity carries a model.
local reads,findByClass,getAll=0,0,0
local E={} E.__index=E
local all,nextIndex={},1
local function entity(fields)
 local e=setmetatable(fields or {},E)
 e.class=e.class or 'prop_physics' e.nw2=e.nw2 or {}
 if e.index==nil then e.index=nextIndex nextIndex=nextIndex+1 end
 return e
end
function E:EntIndex() return self.index end
function E:GetClass() return self.class end
function E:GetModel() return self.model or 'models/props_c17/oildrum001.mdl' end
function E:GetNW2String(k,d) if k=='MMDHLAsset' then reads=reads+1 end local v=self.nw2[k] if v==nil then return d end return v end
function E:GetNW2Bool(k,d) local v=self.nw2[k] if v==nil then return d end return v end
function E:GetNW2Int(k,d) local v=self.nw2[k] if v==nil then return d end return v end
function E:GetNoDraw() return false end
function E:IsEffectActive() return false end
function E:IsDormant() return false end
function E:GetPhysicsObjectCount() return 0 end
function E:GetInstance() return 0 end
function E:GetAsset() return '' end
function E:GetPos() return Vector() end
function E:GetFlexScale() return 1 end
function E:GetFlexWeight(i) return self.flex and self.flex[i] or 0 end
function E:GetNW2Float(k,d) local v=self.nw2[k] if v==nil then return d end return v end
-- In the game: OnEntityCreated runs as each entity is made; EntityRemoved as it goes.
local function spawn(fields) local e=entity(fields) all[#all+1]=e callHook('OnEntityCreated','MMDHL.CarrierCandidates',e) return e end
local function remove(e)
 callHook('EntityRemoved','MMDHL.CarrierCandidates',e,false) e.valid=false
 for i,o in ipairs(all) do if o==e then table.remove(all,i) break end end
end
-- The server gives an entity a model; with announce, the change hook runs as the game's does (before the value).
local function setAsset(e,asset,announce)
 if announce then hook.Run('EntityNetworkedVarChanged',e,'MMDHLAsset',e.nw2.MMDHLAsset,asset) end
 e.nw2.MMDHLAsset=asset
end
ents={GetAll=function() getAll=getAll+1 local out={} for i,e in ipairs(all) do out[i]=e end return out end,
 FindByClass=function(class) findByClass=findByClass+1 local out={} for _,e in ipairs(all) do if e.class==class then out[#out+1]=e end end return out end,
 CreateClientside=function(class) return entity({class=class,index=-1}) end}
local localPlayer=entity({class='player',GetFOV=function() return 75 end}) all[#all+1]=localPlayer
function LocalPlayer() return localPlayer end

-- The natives: the frame step and the render-cache sweep counted, the morphs sent recorded.
local natives={PrepareFrame=0,PruneRenderCache=0}
local sent={}
mmdhl={L=function(key) return key end,Localize=function(text) return text end,Decode=function(v) return v end,
 native={SetNativeVertexCache=noop,CheckRenderer=function() return true end,RenderStats=function() return {} end,
  PrepareFrame=function() natives.PrepareFrame=natives.PrepareFrame+1 return 0 end,
  PruneRenderCache=function() natives.PruneRenderCache=natives.PruneRenderCache+1 end,
  GetBounds=function() end,GetBoundsValues=function() end,GetDrawAge=function() return 0 end,SubmitPresentationMatrixBatch=function() return true end,
  SetMorphs=function(handle,json) sent[#sent+1]={handle=handle,json=json} return true end}}
local instancesHeld=false
-- instances.lua's part of the render boundary: a fresh list.
function mmdhl.UpdateClientInstances() mmdhl.InvalidateEntityList() mmdhl.Entities() end
function mmdhl.HasClientInstances() return instancesHeld end
-- GMod's continue as LuaJIT's goto: each continue jumps to a label put before the end of its innermost loop (a label
-- at the end of a block is outside the scope of the block's locals). Strings and comments are copied as they are.
local keywords={['function']=true,['if']=true,['do']=true,['for']=true,['while']=true,['repeat']=true,['end']=true,['until']=true,['continue']=true}
local function glua(path)
 local f=assert(io.open(path,'rb')) local src=f:read('*a') f:close()
 local out,stack,labels,i,n,previous={},{},0,1,#src,''
 local function loop() for k=#stack,1,-1 do local b=stack[k] if b.kind=='loop' then return b end if b.kind=='function' then return end end end
 while i<=n do
  local c=src:sub(i,i)
  local long=src:match('^%-%-%[(=*)%[',i)
  if long then local _,j=src:find(']'..long..']',i,true) j=j or n out[#out+1]=src:sub(i,j) i=j+1
  elseif src:sub(i,i+1)=='--' then local j=src:find('\n',i,true) or n out[#out+1]=src:sub(i,j) i=j+1
  elseif src:match('^%[=*%[',i) then local eq=src:match('^%[(=*)%[',i) local _,j=src:find(']'..eq..']',i,true) j=j or n out[#out+1]=src:sub(i,j) i=j+1 previous='string'
  elseif c=='"' or c=="'" then
   local j=i+1 while j<=n and src:sub(j,j)~=c do if src:sub(j,j)=='\\' then j=j+1 end j=j+1 end
   out[#out+1]=src:sub(i,j) i=j+1 previous='string'
  elseif c:match('[%a_]') then
   local word=src:match('^[%w_]+',i) i=i+#word
   if keywords[word] and previous~='.' and previous~=':' then
    if word=='function' or word=='if' or word=='repeat' then stack[#stack+1]={kind=word=='repeat' and 'loop' or word}
    elseif word=='for' or word=='while' then stack[#stack+1]={kind='header'}
    elseif word=='do' then local top=stack[#stack] if top and top.kind=='header' then top.kind='loop' else stack[#stack+1]={kind='do'} end
    elseif word=='end' or word=='until' then local top=table.remove(stack) if top and top.label then out[#out+1]='::'..top.label..':: ' end
    elseif word=='continue' then local b=assert(loop(),path..': continue outside a loop') if not b.label then labels=labels+1 b.label='mmdhl_continue'..labels end word='goto '..b.label end
   end
   out[#out+1]=word previous=word
  else out[#out+1]=c if not c:match('%s') then previous=c end i=i+1 end
 end
 return table.concat(out)
end
local function run(path) return assert(loadstring(glua(path),'@'..path))() end
function include(path)
 if path=='mmdhl/native_render.lua' then run(folder..'/native_render.lua') end
end
if not serverRealm then run(folder..'/client.lua') end
run(folder..'/carrier.lua')
-- measure also runs against the files before ADR 0273, which have neither; the server has no native_render.lua.
if scenario~='measure' and not serverRealm then check(mmdhl.HasLegacyRagdolls and mmdhl.NativeIdle,'carrier.lua or native_render.lua lacks the idle helpers') end

local function step(seconds) now=now+(seconds or 1/60) frame=frame+1 end
-- One frame of the hooks that run whatever the map holds.
local function runFrame(seconds)
 step(seconds)
 callHook('Think','MMDHL.NativeVisuals') callHook('Think','MMDHL.RenderMode')
 callHook('PreRender','MMDHL.Shadows')
 callHook('PostDrawOpaqueRenderables','MMDHL.PendingVisuals',false,false)
 callHook('PostDrawTranslucentRenderables','MMDHL.PendingVisuals',false,false)
 callHook('PostDrawTranslucentRenderables','MMDHL.Models',false,false)
end
local function listed(e) for _,o in ipairs(mmdhl.Entities()) do if o==e then return true end end return false end
local function count() return #mmdhl.Entities() end
-- A busy map: 600 props, 40 ragdolls and 20 NPCs, none of them a character model.
local function busyMap() for i=1,600 do spawn() end for i=1,40 do spawn({class='prop_ragdoll'}) end for i=1,20 do spawn({class='npc_citizen'}) end end
-- Counts over frames.
local function measure(frames)
 local r,f,g,p,q=reads,findByClass,getAll,natives.PrepareFrame,natives.PruneRenderCache
 for _=1,frames do runFrame() end
 return (reads-r)/frames,(findByClass-f)/frames,(getAll-g)/frames,(natives.PrepareFrame-p)/frames,(natives.PruneRenderCache-q)/frames
end

if scenario=='idle' then
 busyMap()
 runFrame() check(count()==0,'a prop was listed as a character model')
 -- Past the fresh window and the first full scan: what a frame costs from then on.
 for _=1,200 do runFrame() end
 local reads,finds,_,prepare,prune=measure(600)
 check(reads<=2,'with no character model each frame still read '..reads..' assets (of 661 candidates)')
 check(finds==0,'with no legacy entity each frame still searched the map for one ('..finds..' a frame)')
 check(prepare==0 and prune==0,'with nothing to draw the natives still prepared a frame ('..prepare..') and swept their caches ('..prune..')')
 check(count()==0,'the list was not empty')
elseif scenario=='measure' then
 -- The counts of a frame, for the record (also run against the files before ADR 0273).
 busyMap()
 for _=1,400 do runFrame() end
 local idleReads,idleFinds,idleScans,idlePrepare,idlePrune=measure(600)
 local characters={}
 for i=1,3 do characters[i]=spawn({class='prop_ragdoll',nw2={MMDHLAsset=('%064d'):format(i)}}) end
 for _=1,400 do runFrame() end
 local busyReads,busyFinds,busyScans,busyPrepare,busyPrune=measure(600)
 print(('idle: %.2f asset reads, %.2f legacy searches, %.4f full scans, %.2f frame steps, %.2f cache sweeps a frame'):format(idleReads,idleFinds,idleScans,idlePrepare,idlePrune))
 print(('3 characters: %.2f asset reads, %.2f legacy searches, %.4f full scans, %.2f frame steps, %.2f cache sweeps a frame'):format(busyReads,busyFinds,busyScans,busyPrepare,busyPrune))
elseif scenario=='spawn' then
 busyMap() for _=1,200 do runFrame() end
 -- The server makes a ragdoll and gives it a model in the same tick: listed in that frame.
 local ragdoll=spawn({class='prop_ragdoll',nw2={MMDHLAsset=('a'):rep(64)}})
 check(listed(ragdoll),'a new character model was not listed at once')
 runFrame() check(listed(ragdoll),'the character model left the list')
 check(natives.PrepareFrame>0,'the natives prepared no frame with a character model')
 local before=natives.PrepareFrame runFrame() check(natives.PrepareFrame==before+1,'the natives did not prepare each frame with a character model')
 -- Its value arriving frames after the entity, without the change hook: within the fresh window.
 local late=spawn({class='prop_ragdoll'})
 for _=1,5 do runFrame() end
 check(not listed(late),'an entity without a model was listed')
 setAsset(late,('b'):rep(64),false)
 runFrame() check(listed(late),'a model arriving frames after its entity was not listed in the next frame')
elseif scenario=='change' then
 busyMap()
 local player=spawn({class='player',index=2})
 for _=1,300 do runFrame(1/60) end
 -- A player choosing a character model long after joining: the change hook names it.
 setAsset(player,('c'):rep(64),true)
 runFrame() check(listed(player),'a player given a model was not listed in the next frame')
 -- The hook runs before the value; a value read (and kept for the frame) before it arrives is read again.
 local prop=all[10] check(not listed(prop),'a prop was listed')
 mmdhl.IsMMD(prop)
 hook.Run('EntityNetworkedVarChanged',prop,'MMDHLAsset','',('d'):rep(64))
 prop.nw2.MMDHLAsset=('d'):rep(64)
 mmdhl.InvalidateEntityList() mmdhl.Entities()
 runFrame() check(listed(prop),'a model announced after its entity was read this frame was not listed in the next frame')
 -- Taken away again: out in the next frame (this frame keeps the value it read, as before).
 setAsset(player,'',true)
 runFrame() check(not listed(player),'a player whose model was taken away stayed listed')
elseif scenario=='missed' then
 -- A change no hook announced (another add-on's handler answered first, or the game did not run it): found in turn.
 busyMap()
 for _=1,300 do runFrame() end
 local prop=all[123]
 setAsset(prop,('e'):rep(64),false)
 local frames=0
 while not listed(prop) and frames<2000 do runFrame() frames=frames+1 end
 check(listed(prop),'an unannounced model was never found')
 -- 661 candidates, at least two a frame: within one turn of 600 frames.
 check(frames<=600,'an unannounced model took '..frames..' frames to be found')
 print(('found after %d frames'):format(frames))
elseif scenario=='transmit' then
 busyMap()
 for _=1,300 do runFrame() end
 local npc=all[650]
 -- Out of view the entity got a model; back in view, the game says so.
 npc.nw2.MMDHLAsset=('f'):rep(64)
 callHook('NotifyShouldTransmit','MMDHL.CarrierCandidates',npc,true)
 runFrame() check(listed(npc),'an entity back in view with a model was not listed in the next frame')
elseif scenario=='removed' then
 local a=spawn({class='prop_ragdoll',nw2={MMDHLAsset=('1'):rep(64)}})
 runFrame() check(listed(a),'a character model was not listed')
 remove(a)
 check(not listed(a),'a removed character model stayed listed')
 runFrame() check(count()==0,'the list was not empty after the removal')
elseif scenario=='order' then
 local c=spawn({class='prop_ragdoll',index=30,nw2={MMDHLAsset=('3'):rep(64)}})
 local a=spawn({class='npc_citizen',index=10,nw2={MMDHLAsset=('1'):rep(64)}})
 local b=spawn({class='player',index=20,nw2={MMDHLAsset=('2'):rep(64)}})
 runFrame()
 local list=mmdhl.Entities()
 check(#list==3 and list[1]==a and list[2]==b and list[3]==c,'the list was not in entity index order')
 -- Client ragdolls and other add-ons' copies follow, each once.
 local corpse=entity({class='class C_ClientRagdoll',index=-1,MMDHLLocalAsset=('4'):rep(64)})
 local copy=entity({class='class C_BaseFlex',index=-1,MMDHLLocalAsset=('5'):rep(64)})
 mmdhl.clientRagdolls={[corpse]=true} mmdhl.playerCopies={[copy]=true,[a]=true}
 mmdhl.InvalidateEntityList() list=mmdhl.Entities()
 check(#list==5 and list[4]==corpse and list[5]==copy,'client ragdolls and copies were not listed after the candidates, each once')
elseif scenario=='preview' then
 -- An editor preview: a client-side entity the add-on gives a model and notes.
 for _=1,10 do runFrame() end
 local preview=entity({class='class C_BaseFlex',index=-1})
 preview.MMDHLPreviewRig={asset=('9'):rep(64)}
 mmdhl.NoteCarrier(preview)
 check(listed(preview),'a noted preview was not listed')
elseif scenario=='full_update' then
 local a=spawn({class='prop_ragdoll',nw2={MMDHLAsset=('1'):rep(64)}})
 busyMap()
 for _=1,300 do runFrame() end
 check(listed(a),'a character model was not listed')
 -- A full update removes every entity; the game may make them again as new objects without OnEntityCreated.
 local before=all all={}
 for _,e in ipairs(before) do callHook('EntityRemoved','MMDHL.CarrierCandidates',e,true) e.valid=false end
 for _,e in ipairs(before) do local copy=entity({class=e.class,index=e.index,nw2=e.nw2}) all[#all+1]=copy end
 local again for _,e in ipairs(all) do if e.index==a.index then again=e end end
 runFrame() check(listed(again),'a character model made again by a full update was not listed in the next frame')
elseif scenario=='legacy' then
 busyMap() for _=1,200 do runFrame() end
 check(not mmdhl.HasLegacyRagdolls(),'a legacy entity was reported on a map without one')
 local legacy=spawn({class='mmdhl_ragdoll'})
 check(mmdhl.HasLegacyRagdolls(),'a legacy entity was not reported')
 local finds=findByClass runFrame()
 check(findByClass-finds==3,'with a legacy entity the frame did not look for them as before (searched '..(findByClass-finds)..' times)')
 check(listed(legacy),'the legacy entity was not listed')
 remove(legacy)
 check(not mmdhl.HasLegacyRagdolls(),'a removed legacy entity was still reported')
 -- One made before the add-on's hooks (no OnEntityCreated): the full scan finds it.
 local early=entity({class='mmdhl_ragdoll'}) all[#all+1]=early
 for _=1,400 do runFrame() end
 check(mmdhl.HasLegacyRagdolls(),'a legacy entity made before the hooks was never reported')
elseif scenario=='native_idle' then
 -- Nothing at all from the first frame.
 runFrame() check(mmdhl.NativeIdle(),'an empty map was not idle')
 local a=spawn({class='prop_ragdoll',nw2={MMDHLAsset=('1'):rep(64)}})
 check(not mmdhl.NativeIdle(),'a map with a character model was idle')
 remove(a) runFrame(.5)
 -- The grace: the natives release what the last character used.
 check(not mmdhl.NativeIdle(),'the natives went idle at once after the last character model')
 local before=natives.PruneRenderCache
 for _=1,3 do runFrame(.5) end
 check(natives.PruneRenderCache>before,'the render caches were not swept after the last character model')
 runFrame(.6) check(mmdhl.NativeIdle(),'two seconds after the last character model the natives were not idle')
 -- Each of these keeps the natives working.
 instancesHeld=true check(not mmdhl.NativeIdle(),'a held instance did not keep the natives working') instancesHeld=false
 for _=1,10 do runFrame(.5) end
 mmdhl.editorPreviews={[1]={}} check(not mmdhl.NativeIdle(),'an editor preview did not keep the natives working') mmdhl.editorPreviews={}
 for _=1,10 do runFrame(.5) end
 mmdhl.previewOwner={valid=true} check(not mmdhl.NativeIdle(),'the library preview did not keep the natives working') mmdhl.previewOwner=nil
 for _=1,10 do runFrame(.5) end
 mmdhl.RequestFrameProfile(1) check(not mmdhl.NativeIdle(),'a reader of the frame profile did not keep the natives working')
 for _=1,10 do runFrame(.5) end
 check(mmdhl.NativeIdle(),'the natives did not go idle again')
 local legacy=spawn({class='mmdhl_ragdoll'}) check(not mmdhl.NativeIdle(),'a legacy entity did not keep the natives working')
 remove(legacy)
elseif scenario=='server_pose' or scenario=='server_pose_unannounced' then
 -- The server's tick that sends a server-side world's morphs (MMDHLInstance): nothing gives one any more.
 local tick=hooks.Tick and hooks.Tick['MMDHL.NativePose'] check(tick,'the server registered no NativePose tick')
 for i=1,200 do spawn() end for i=1,20 do spawn({class='prop_ragdoll'}) end
 local function ticks(seconds) for _=1,math.floor(seconds*66+.5) do now=now+1/66 tick() end end
 local before=findByClass ticks(10)
 check(findByClass-before<=3,'with no server-side world ten seconds of ticks searched the map '..(findByClass-before)..' times')
 -- A ragdoll given one: its morphs are sent as before, every tick a weight changed, and every tick searches.
 local rag=all[#all] local key=('a'):rep(32)
 mmdhl.rigs[key]={key=key,morphs={{native=0,mmd=0}}}
 rag.nw2.MMDHLRig=key rag.MMDMorphs={} rag.flex={[0]=.5}
 rag.nw2.MMDHLInstance=7
 if scenario=='server_pose' then
  hook.Run('EntityNetworkedVarChanged',rag,'MMDHLInstance',0,7)
  ticks(1/66) check(#sent==1 and sent[1].handle==7,'a ragdoll given a server-side world did not have its morphs sent in the next tick')
 else
  -- Without the change hook (set some other way): the search every five seconds finds it.
  ticks(5.1) check(#sent==1 and sent[1].handle==7,'an unannounced server-side world was not found within five seconds')
 end
 before=findByClass ticks(1/66) check(findByClass-before==1,'once a server-side world existed the tick did not search as before')
 rag.flex[0]=.75 ticks(1/66) check(#sent==2,'a changed weight was not sent in the next tick')
 ticks(1) check(#sent==2,'an unchanged weight was sent again')
else
 error('unknown scenario '..tostring(scenario))
end
print('PASS '..scenario)
