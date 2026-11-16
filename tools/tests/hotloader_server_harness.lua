-- R19: Model Hotloader's server and client Lua under LuaJIT, with the game's API stubbed: removing
-- and replacing another player's character (review L-02), the reach of a prop attachment (L-07),
-- the collision mesh pace (L-08) and the remote collision shapes the module drops (MH-05); and the
-- review of 2026-11-16: replace bursts (3), sizes and player models (4), the legacy dupe factory (12),
-- the reset pace and notice (20), the separator's placement (21), saved rigs and arms previews (4).
-- One scenario per run; prints PASS <scenario>.
-- usage: luajit hotloader_server_harness.lua <scenario> <lua/mmdhl folder> <slices file>
-- The slices file holds production code cut out of files this harness cannot load whole:
-- sharing.lua's mmdhl.CanEdit and mmdhl.OwnsEntity, carrier.lua's collision mesh receiver.
local scenario,folder,slices=arg[1],arg[2],arg[3]
local function noop() end
local function check(ok,why) if not ok then error('FAIL '..scenario..': '..why,2) end end
local clock=1000
function CurTime() return clock end RealTime=CurTime SysTime=CurTime
function isnumber(v) return type(v)=='number' end function istable(v) return type(v)=='table' end
function isstring(v) return type(v)=='string' end function isfunction(v) return type(v)=='function' end
local V={} V.__index=V
function Vector(x,y,z) return setmetatable({x=x or 0,y=y or 0,z=z or 0},V) end
V.__sub=function(a,b) return Vector(a.x-b.x,a.y-b.y,a.z-b.z) end
V.__add=function(a,b) return Vector(a.x+b.x,a.y+b.y,a.z+b.z) end
V.__mul=function(a,s) return Vector(a.x*s,a.y*s,a.z*s) end
function V:Length() return math.sqrt(self.x^2+self.y^2+self.z^2) end
function V:DistToSqr(o) local d=self-o return d.x^2+d.y^2+d.z^2 end
function V:Unpack() return self.x,self.y,self.z end
function Angle(p,y,r) return {p=p or 0,y=y or 0,r=r or 0} end
function table.Copy(t) if type(t)~='table' then return t end local c={} for k,v in pairs(t) do c[k]=table.Copy(v) end return c end
local hooks,receivers,sent={}, {}, {}
hook={Add=function(event,id,fn) hooks[event]=hooks[event] or {} hooks[event][id]=fn end,Remove=noop,
 Run=function(event,...) for _,fn in pairs(hooks[event] or {}) do local r=fn(...) if r~=nil then return r end end end}
local reads={}
local function read(default) if #reads>0 then return table.remove(reads,1) end return default end
net={Receive=function(name,fn) receivers[name]=fn end,Start=function(name) sent[#sent+1]=name end,Send=noop,SendToServer=noop,Broadcast=noop,
 ReadString=function() return read('') end,ReadBool=function() return read(false) end,ReadFloat=function() return read(0) end,
 ReadUInt=function() return read(0) end,ReadInt=function() return read(0) end,ReadEntity=function() return read(NULL) end,
 ReadVector=function() return read(Vector()) end,ReadAngle=function() return read(Angle()) end,ReadData=function() return read('') end}
for _,name in ipairs({'WriteString','WriteBool','WriteFloat','WriteUInt','WriteInt','WriteEntity','WriteData','WriteVector','WriteAngle'}) do net[name]=noop end
net.SendOmit=noop
local function receive(name,ply,...) reads={...} receivers[name](0,ply) reads={} end
local function count(name) local n=0 for _,s in ipairs(sent) do if s==name then n=n+1 end end return n end
util={AddNetworkString=noop,TableToJSON=function() return '[]' end,JSONToTable=function() return {} end,Compress=function(s) return s end,Decompress=function(s) return s end}
duplicator={RegisterEntityClass=noop,RegisterConstraint=noop,DoGeneric=noop}
cleanup={Register=noop} timer={Create=noop,Remove=noop,Simple=noop}
undo={Create=noop,AddEntity=noop,SetPlayer=noop,Finish=noop,SetCustomUndoText=noop}
function include() end function GetConVar() return {GetBool=function() return true end,GetInt=function() return 1 end} end
local properties={}
gamemode={Call=function(name,p,property) if name=='CanProperty' then properties[#properties+1]=property end return nil end}
local E={} E.__index=function(_,k) local v=rawget(E,k) if v~=nil then return v end if type(k)=='string' and k:find('^[A-Z]') and not k:find('^MMD') then return noop end end
function IsValid(e) return type(e)=='table' and e.valid~=false end
NULL=setmetatable({valid=false},E)
local registry={}
local function entity(kind,fields) local e=setmetatable(fields or {},E) e.kind=kind registry[#registry+1]=e e.index=#registry e.pos=e.pos or Vector() return e end
function Entity(i) return registry[i] or NULL end
function E:IsPlayer() return self.kind=='player' end function E:IsWorld() return false end
function E:GetClass() return self.kind end function E:IsAdmin() return self.admin==true end
function E:GetCreator() return self.creator end function E:Remove() self.removed=true end
function E:EyePos() return self.pos end function E:GetPos() return self.pos end function E:NearestPoint() return self.pos end
function E:WorldSpaceCenter() return self.pos end function E:GetBoneCount() return 4 end function E:EntIndex() return self.index end
mmdhl={native={},L=function(key) return key end,IsMMD=function() return true end,GetInstance=function() return 0 end}
local function cut(name)
 local text=assert(io.open(slices,'rb')):read('*a')
 return text:match('%-%- slice '..name..'\r?\n(.-)%-%- end '..name)
end
assert(loadstring(cut('sharing')))() -- mmdhl.CanEdit and mmdhl.OwnsEntity
local owner,other,admin=entity('player'),entity('player'),entity('player',{admin=true})

if scenario=='remove' then
 dofile(folder..'/server.lua')
 local spawned={}
 mmdhl.Spawn=function(_,id) spawned[#spawned+1]=id end
 local ragdoll=entity('prop_ragdoll',{creator=owner,MMDOptions={}})
 -- Another player: neither removed nor replaced, and the remover property is what is asked.
 receive('mmdhl_action',other,'remove','',ragdoll.index,'')
 check(not ragdoll.removed,'another player removed a character they do not own')
 check(table.concat(properties,','):find('remover',1,true),'remove was not checked as the remover property: '..table.concat(properties,','))
 receive('mmdhl_action',other,'replace',string.rep('a',64),ragdoll.index,'')
 check(#spawned==0,'another player replaced a character they do not own')
 -- Its owner and an admin may.
 receive('mmdhl_action',owner,'replace',string.rep('a',64),ragdoll.index,'') check(#spawned==1,'the owner could not replace their character')
 receive('mmdhl_action',owner,'remove','',ragdoll.index,'') check(ragdoll.removed,'the owner could not remove their character')
 local second=entity('prop_ragdoll',{creator=owner})
 receive('mmdhl_action',admin,'remove','',second.index,'') check(second.removed,'an admin could not remove a character')
 -- Prop protection's owner (CPPI) decides where it is installed.
 local guarded=entity('prop_ragdoll',{creator=other}) function guarded:CPPIGetOwner() return owner end
 receive('mmdhl_action',other,'remove','',guarded.index,'') check(not guarded.removed,'the creator removed what prop protection says another player owns')
 -- Other edits stay with CanProperty, as before: a pose change is still applied.
 local posed={} mmdhl.SetManualBonePose=function(ent) posed[#posed+1]=ent end
 local third=entity('prop_ragdoll',{creator=owner})
 receive('mmdhl_action',other,'bone','',third.index,'{}') check(#posed==1,'an edit other than remove or replace was refused')
elseif scenario=='attach' then
 local loads,notices={}, {}
 local P={native={},Info={},Pins={},Loading={},LastUse={},Notice=noop,CanonicalScale=function(s) return s end,ValidScale=function() return true end,
  FiniteVector=function() return true end,FiniteAngle=function() return true end,ValidID=function() return true end,CanUse=function() return true end,
  Load=function(id) loads[#loads+1]=id end}
 game={SinglePlayer=function() return false end}
 mmdhl.props=P mmdhl.approved={props={[string.rep('b',64)]={name='Prop'}}} mmdhl.cleanupGeneration=0
 dofile(folder..'/props/server.lua')
 -- The notice's text is the one string the refusal writes.
 local lastNotice net.WriteString=function(text) lastNotice=text end
 owner.pos=Vector(0,0,0)
 local near=entity('npc',{pos=Vector(1000,0,0)}) local far=entity('npc',{pos=Vector(5000,0,0)})
 receive('mmdhl_prop_attach',owner,'attach',far,NULL,string.rep('b',64),-1,Vector(),Angle(),1)
 check(#loads==0 and lastNotice=='props.attach.aim_target','a prop was attached to a target out of reach')
 clock=clock+1
 receive('mmdhl_prop_attach',owner,'attach',near,NULL,string.rep('b',64),-1,Vector(),Angle(),1)
 check(#loads==1,'a prop could not be attached to a target within reach')
elseif scenario=='mesh' then
 assert(loadstring(cut('carrier')))() -- the collision mesh receiver
 local function body() return {GetMeshConvexes=function() return {} end} end
 local function ragdoll() local e=entity('prop_ragdoll') function e:GetPhysicsObjectCount() return 18 end function e:GetPhysicsObjectNum() return body() end
  function e:GetNW2String() return '' end return e end
 local a,b=ragdoll(),ragdoll()
 for _=1,5 do receive('mmdhl_collision_mesh',owner,a) end
 check(count('mmdhl_collision_mesh')==1,'collision meshes were not paced: '..count('mmdhl_collision_mesh'))
 clock=clock+.3 receive('mmdhl_collision_mesh',owner,a) check(count('mmdhl_collision_mesh')==1,'the same entity was answered again within 1.5 s')
 receive('mmdhl_collision_mesh',owner,b) check(count('mmdhl_collision_mesh')==2,'another entity was not answered')
 receive('mmdhl_collision_mesh',owner,a) check(count('mmdhl_collision_mesh')==2,'a player was answered faster than four times a second')
 clock=clock+1.6 receive('mmdhl_collision_mesh',owner,a) check(count('mmdhl_collision_mesh')==3,'the entity was not answered after its pause')
 receive('mmdhl_collision_mesh',other,b) check(count('mmdhl_collision_mesh')==4,'one player\'s pace held up another')
elseif scenario=='scene' then
 -- The client: shapes the module dropped are asked for again when a frame names them.
 SERVER,CLIENT=false,true
 game={SinglePlayer=function() return false end}
 -- Shape requests are the client's command 1 (net.WriteUInt(1,2)).
 local requested={} local publish={true}
 net.WriteUInt=function(value,bits) if bits==2 and value==1 then requested[#requested+1]=true end end
 local accepted={}
 mmdhl.native={AcceptSceneGeometry=function(id) accepted[#accepted+1]=id return publish.accept~=false or nil,publish.accept==false and 'refused' or nil end,
  PublishRemoteScene=function() return publish[1],publish[2] end,ClearRemoteScene=noop}
 local character=entity('mmdhl_ragdoll') character.pos=Vector()
 function character:BoundingRadius() return 10 end
 mmdhl.Entities=function() return {character} end mmdhl.SceneKinds=function() return 1 end mmdhl.GetCollisionFlags=function() return 1 end
 mmdhl.GetInstance=function() return 1 end
 function LocalPlayer() return owner end
 function V:Distance(o) return math.sqrt(self:DistToSqr(o)) end
 dofile(folder..'/scene_sharing.lua')
 local key=string.rep('c',64)
 local frames={}
 util.JSONToTable=function(s) if frames[s] then return frames[s] end local k=s:match('^%["(%x+)"%]$') if k then return {k} end end
 local function deliver(sequence)
  frames['f'..sequence]={timestamp=sequence,sequence=sequence,objects={{id=1,shape=key,bytes=48,position={0,0,0},rotation={0,0,0,1}}}}
  local data='f'..sequence
  reads={0,sequence,1,1,#data,data} receivers.mmdhl_scene() reads={}
 end
 local function chunk() reads={1,key,0,true,48,string.rep('x',48)} receivers.mmdhl_scene() reads={} end
 hooks.Think['MMDHL.SceneSubscription']() -- subscribes: active
 deliver(1) check(#requested==1,'the named shape was not asked for')
 chunk() check(#accepted==1,'the shape did not reach the module')
 -- The module answers that it dropped the shape: the next frame naming it asks again.
 publish={true,'["'..key..'"]'} mmdhl.UpdateRemoteScene() publish={true}
 deliver(2) check(#requested==2,'a shape the module dropped was not asked for again')
 -- A shape the module refuses waits ten seconds before it is asked for again.
 publish.accept=false chunk() publish.accept=nil
 deliver(3) check(#requested==2,'a refused shape was asked for again at once')
 clock=clock+11 deliver(4) check(#requested==3,'a refused shape was never asked for again')
elseif scenario=='replace_burst' then
 -- Review finding 3: one replacement at a time per player and per character, under the gamemode's rules; a replacement
 -- whose original went meanwhile goes too.
 dofile(folder..'/server.lua')
 local spawns={}
 mmdhl.Spawn=function(p,id,options,done) spawns[#spawns+1]={options=options,done=done} end
 mmdhl.ActorClass=function() return 'npc_citizen' end
 local asset=string.rep('a',64)
 local ragdoll=entity('prop_ragdoll',{creator=owner,MMDOptions={role='ragdoll'}})
 receive('mmdhl_action',owner,'replace',asset,ragdoll.index,'')
 receive('mmdhl_action',owner,'replace',asset,ragdoll.index,'')
 check(#spawns==1,'two replaces in one tick made '..#spawns..' spawns')
 local replacement=entity('prop_ragdoll',{creator=owner})
 spawns[1].done(replacement)
 check(ragdoll.removed and not replacement.removed,'the replacement did not take the original\'s place')
 local second=entity('prop_ragdoll',{creator=owner,MMDOptions={}})
 receive('mmdhl_action',owner,'replace',asset,second.index,'')
 check(#spawns==2,'the next replace was refused after the first finished')
 second.valid=false
 local late=entity('prop_ragdoll',{creator=owner})
 spawns[2].done(late)
 check(late.removed,'a replacement outlived the character it replaced')
 gamemode.Call=function(name) if name=='PlayerSpawnRagdoll' then return false end end
 local third=entity('prop_ragdoll',{creator=owner,MMDOptions={}})
 receive('mmdhl_action',owner,'replace',asset,third.index,'')
 check(#spawns==2,'a replace went past the gamemode\'s refusal')
elseif scenario=='reset' then
 -- Review finding 20: one reset a second per player; every client resets but only the requester is told; one
 -- character at most once a second.
 dofile(folder..'/server.lua')
 local resets={}
 mmdhl.ResetPhysics=function(ent,requester) resets[#resets+1]={requester=requester} end
 local ragdoll=entity('prop_ragdoll',{creator=owner})
 for _=1,10 do receive('mmdhl_action',owner,'reset','',ragdoll.index,'') end
 check(#resets==1 and resets[1].requester==owner,'ten resets in a second: '..#resets)
 clock=clock+1.1 receive('mmdhl_action',owner,'reset','',ragdoll.index,'')
 check(#resets==2,'the next second\'s reset was refused')
 SERVER,CLIENT=true,false
 local bools,targets={}, {}
 net.WriteBool=function(v) bools[#bools+1]=v end
 net.Send=function() targets[#targets+1]='send' end net.SendOmit=function() targets[#targets+1]='omit' end
 net.Broadcast=function() targets[#targets+1]='all' end
 rawset(_G,'properties',{Add=noop})
 dofile(folder..'/physics_reset.lua')
 local character=entity('prop_ragdoll')
 check(mmdhl.ResetPhysics(character,owner)==true,'the reset failed')
 check(#bools==2 and bools[1]==true and bools[2]==false and targets[1]=='send' and targets[2]=='omit',
  'the notice went beyond the requester: '..table.concat(targets,','))
 mmdhl.ResetPhysics(character,other)
 check(#bools==2,'one character was reset twice within a second')
 clock=clock+1.1 mmdhl.ResetPhysics(character)
 check(#bools==3 and bools[3]==false and targets[3]=='all','a reset without a requester told someone')
elseif scenario=='dupe_factory' then
 -- Review finding 12: a pasted character takes only its look and place, under the gamemode's rules, through the
 -- asynchronous spawn (no fit on the main thread).
 local factory
 file={Read=function() return nil end}
 duplicator.RegisterEntityClass=function(class,fn) if class=='mmdhl_ragdoll' then factory=fn end end
 dofile(folder..'/server.lua')
 local spawns={}
 mmdhl.Spawn=function(p,id,options,done) spawns[#spawns+1]={id=id,options=options} end
 mmdhl.SpawnNative=function() error('the factory fitted on the main thread') end
 mmdhl.CanUseAsset=function() return true end mmdhl.CleanBodygroups=function(b) return b end
 mmdhl.ValidSecondaryBackend=function() return nil end mmdhl.ValidCollisionFlags=function() return nil end mmdhl.CollideDefault=1
 local asset=string.rep('a',64)
 local data={Pos=Vector(10,0,0),EntityMods={MMDHL={asset=asset,state={center={0,0,0},frozen=true},options={role='citizen',
  excludedMaterials={0},height=500,animationReference={bones={}},physicsOverrides={x=1},scaleMultiplier=1.000001,mass=12.4,
  position={0,0,0},gender='male'}}}}
 local made=factory(owner,data)
 check(made==nil and #spawns==1,'the paste was not handed to the spawn')
 local o=spawns[1].options
 check(o.role=='ragdoll' and o.excludedMaterials==nil and o.height==nil and o.animationReference==nil and o.physicsOverrides==nil,
  'a pasted fitting option reached the spawn')
 check(o.scaleMultiplier==1 and o.mass==12 and o.gender=='male' and o.frozen==true,'the look was not kept: '..tostring(o.scaleMultiplier)..' '..tostring(o.mass))
 check(o.position[1]==10,'the paste\'s place was lost')
 gamemode.Call=function(name) if name=='PlayerSpawnRagdoll' then return false end end
 factory(owner,data)
 check(#spawns==1,'a paste went past the gamemode\'s refusal')
elseif scenario=='spawn_quantize' then
 -- Review finding 4: nearby sizes share one carrier; a player model takes no mass from the client and waits ten
 -- seconds between carriers on a server; the server's rule is asked before any carrier is made.
 dofile(folder..'/server.lua')
 local spawns={}
 mmdhl.Spawn=function(p,id,options,done) spawns[#spawns+1]=options if done then done(nil,'test') end end
 mmdhl.CanUseAsset=function() return true end mmdhl.NPCWeapon=function() return 'none' end mmdhl.CleanBodygroups=function(b) return b end
 mmdhl.FacingPlayerAngles=function() return Vector() end mmdhl.ValidSecondaryBackend=function() end mmdhl.ValidCollisionFlags=function() end
 mmdhl.WithSpawnDefaults=function(_,s) return s end mmdhl.ActorClass=function() return 'npc_citizen' end
 game={SinglePlayer=function() return false end}
 math.Clamp=math.Clamp or function(v,a,b) return math.max(a,math.min(b,v)) end
 local settings={}
 util.JSONToTable=function(text) return settings[text] end
 function owner:GetEyeTrace() return {Hit=true,HitPos=Vector(),HitNormal=Vector(0,0,1)} end
 local serial=0
 local function spawn(s) serial=serial+1 local key='settings'..serial settings[key]=s receive('mmdhl_action',owner,'spawn',string.rep('a',64),0,key) end
 spawn({role='ragdoll',scaleMultiplier=1.000001,mass=12.4})
 spawn({role='ragdoll',scaleMultiplier=1.000002,mass=12.45})
 check(#spawns==2 and spawns[1].scaleMultiplier==1 and spawns[2].scaleMultiplier==1,'nearby sizes did not share a carrier')
 check(spawns[1].mass==12 and spawns[2].mass==12,'masses were not whole kilograms')
 spawn({role='ragdoll',scaleMultiplier=0/0,mass=1/0})
 check(spawns[3].scaleMultiplier==1 and spawns[3].mass==nil,'NaN or infinity reached the fit')
 spawn({role='player',scaleMultiplier=1.2,mass=300})
 check(#spawns==4 and spawns[4].mass==nil and math.abs(spawns[4].scaleMultiplier-1.2)<1e-9,'a player model took the client\'s mass')
 spawn({role='player',scaleMultiplier=1.25})
 check(#spawns==4,'a second player model within ten seconds')
 clock=clock+11 spawn({role='player',scaleMultiplier=1.25})
 check(#spawns==5,'the wait did not end')
 hook.Add('MMDHLCanSetPlayerModel','test',function() return false end)
 clock=clock+11 spawn({role='player'})
 check(#spawns==5,'a refused player model was built')
elseif scenario=='separator_place' then
 -- Review finding 21: a piece placed where it was must be at its model (within 64 units of the model's box).
 local placed={}
 mmdhl.separator={Enabled={GetBool=function() return true end},Reach=4096,MayUse=function() return true end}
 mmdhl.props={ValidID=function() return true end,CanUse=function() return true end,FiniteVector=function() return true end,
  Load=function(id) placed[#placed+1]=id end,PlaceAt=noop,SurfaceMaterialIds={},CollisionModeIds={},DefaultCollision='normal'}
 mmdhl.cleanupGeneration=0
 game={SinglePlayer=function() return false end}
 function owner:GetInfo() return '' end function owner:GetInfoNum(_,d) return d end
 dofile(folder..'/separator/server.lua')
 owner.pos=Vector()
 local source=entity('prop_ragdoll',{pos=Vector(100,0,0)})
 function source:NearestPoint(p)
  local function clamp(v,c) return math.max(c-20,math.min(c+20,v)) end
  return Vector(clamp(p.x,self.pos.x),clamp(p.y,self.pos.y),clamp(p.z,self.pos.z))
 end
 receive('mmdhl_separator_place',owner,string.rep('a',64),source,true,Vector(1100,0,0),true)
 check(#placed==0,'a piece was placed 1000 units from its model')
 clock=clock+1
 receive('mmdhl_separator_place',owner,string.rep('a',64),source,true,Vector(110,5,0),true)
 check(#placed==1,'a piece at its model was refused')
elseif scenario=='rigs' then
 -- Review finding 4: of a model's saved rigs the newest 16 per role and voice stay and the newest 4 are registered at
 -- a map's start; arms rigs stay while a kept rig names them; arms previews are never saved (64 kept this session).
 local A=string.rep('a',64)
 local rigs,times={}, {}
 approved={assets={[A]={name='A'}},rigs={}}
 local saved=0
 function save() saved=saved+1 end
 local function hex(i) return string.format('%032x',i) end
 for i=1,20 do
  approved.rigs[hex(i)]={asset=A,role='player',arms=hex(100+i)}
  approved.rigs[hex(100+i)]={asset=A,role='arms'}
  rigs['mmd_hotloader/rigs/'..hex(i)..'/rig.json']={key=hex(i),asset=A,role='player',animation={profile='player_female'}}
  rigs['mmd_hotloader/rigs/'..hex(100+i)..'/rig.json']={key=hex(100+i),asset=A,role='arms'}
  times['mmd_hotloader/rigs/'..hex(i)..'/rig.json']=i
 end
 for i=1,3 do approved.rigs[hex(200+i)]={asset=A,role='arms'} end
 file={Read=function(path) return rigs[path] and path or nil end,Time=function(path) return times[path] end,Exists=function() return true end}
 util.JSONToTable=function(text) return rigs[text] end
 mmdhl.IsLoadableRig=function(r) return istable(r) end
 local restored
 mmdhl.RestoreActors=function(entries) restored=entries end
 assert(loadstring(cut('rigs')))()
 hooks.InitPostEntity['MMDHL.RestorePublishedActors']()
 local players,arms=0,0
 for _,entry in pairs(approved.rigs) do if entry.role=='player' then players=players+1 elseif entry.role=='arms' then arms=arms+1 end end
 check(players==16 and arms==16 and saved==1,'saved rigs: '..players..' player, '..arms..' arms, saved '..saved)
 check(approved.rigs[hex(20)]~=nil and approved.rigs[hex(4)]==nil,'the oldest rigs were kept instead of the newest')
 check(restored and #restored==4,'registered at the map start: '..tostring(restored and #restored))
 for _,e in ipairs(restored) do check(times['mmd_hotloader/rigs/'..e.rig.key..'/rig.json']>=17,'an older rig was registered') end
 for i=1,70 do clock=clock+.01 mmdhl.PublishPreviewRig({key=hex(1000+i),asset=A}) end
 local n=0 for _ in pairs(mmdhl.previewRigs) do n=n+1 end
 check(n==64 and saved==1 and approved.rigs[hex(1001)]==nil and mmdhl.previewRigs[hex(1001)]==nil and mmdhl.previewRigs[hex(1070)]~=nil,
  'previews were saved or not bounded: '..n)
else
 error('unknown scenario '..tostring(scenario))
end
print('PASS '..scenario)
