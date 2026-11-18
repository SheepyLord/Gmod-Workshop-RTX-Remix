-- ADR 0245: the Model Hotloader's hair and clothing scene capture (secondary_collision.lua, its server part,
-- loaded whole) under LuaJIT with the game's API stubbed. Each scenario places entities around a character,
-- runs the capture's Tick hook and checks which physics bodies the natives are handed as excluded: entities
-- nobody can see are left out, visible ones and the world stay in. One scenario per run; prints PASS <scenario>.
-- usage: luajit hotloader_scene_visibility_harness.lua <scenario> <lua/mmdhl folder>
local scenario,folder=arg[1],arg[2]
local function noop() end
local function check(ok,why) if not ok then error('FAIL '..scenario..': '..why,2) end end
SERVER,CLIENT=true,false
RENDERMODE_NORMAL,RENDERMODE_TRANSCOLOR,RENDERMODE_TRANSALPHA,RENDERMODE_NONE=0,1,4,10
bit=require('bit')
function CurTime() return 1000 end
function Vector(x,y,z) return {x=x or 0,y=y or 0,z=z or 0} end
function ErrorNoHalt(text) error(text) end
function IsValid(v) return type(v)=='table' and v.valid~=false end
local hooks={}
hook={Add=function(event,id,fn) hooks[event]=hooks[event] or {} hooks[event][id]=fn end,Remove=noop}
net={Receive=noop,Start=noop,WriteString=noop,WriteBool=noop,Broadcast=noop,SendToServer=noop,ReadBool=function() return true end}
util={AddNetworkString=noop,TableToJSON=function() return '{}' end}
game={SinglePlayer=function() return true end,GetMap=function() return 'gm_construct' end}

-- Little-endian studio model files, as much of them as the capture reads: the header's bodypart count and
-- offset, each bodypart's submodels, each submodel's mesh and vertex counts (mstudiomodel_t, 148 bytes).
local function le(v) return string.char(v%256,math.floor(v/256)%256,math.floor(v/65536)%256,math.floor(v/16777216)%256) end
local function mdl(parts,version)
 local headerSize,cursor=408,408+#parts*16
 local bodyparts,models={},{}
 for i,part in ipairs(parts) do
  bodyparts[#bodyparts+1]=le(0)..le(#part)..le(1)..le(cursor-(408+(i-1)*16))
  for _,m in ipairs(part) do models[#models+1]=string.rep('\0',72)..le(m[1])..le(0)..le(m[2])..string.rep('\0',148-84) cursor=cursor+148 end
 end
 local head='IDST'..le(version or 48)..string.rep('\0',224)..le(#parts)..le(headerSize)
 return head..string.rep('\0',headerSize-#head)..table.concat(bodyparts)..table.concat(models)
end
local mesh,blank={1,500},{0,0}
local files={
 ['models/props_c17/oildrum001.mdl']=mdl({{mesh}}),
 -- Enhanced Death Animations' model: one bodypart, "barney", whose first submodel is blank.
 ['models/brutal_deaths/model_anim_modify.mdl']=mdl({{blank,mesh}}),
 ['models/test/two_parts.mdl']=mdl({{blank,mesh},{mesh,blank}}),
 ['models/test/no_parts.mdl']=mdl({}),
 ['models/test/no_vertices.mdl']=mdl({{{1,0}}}),
 ['models/test/version.mdl']=mdl({{blank}},37),
 ['models/test/not_a_model.mdl']=string.rep('x',600),
}
local opened={}
file={Open=function(path) opened[path]=(opened[path] or 0)+1 local data=files[path] if not data then return nil end
  local f={pos=0}
  function f:Size() return #data end
  function f:Seek(p) self.pos=p end
  function f:Read(n) local s=data:sub(self.pos+1,self.pos+n) self.pos=self.pos+n return s end
  function f:ReadLong() local a,b,c,d=data:byte(self.pos+1,self.pos+4) self.pos=self.pos+4 local v=a+b*256+c*65536+d*16777216 if v>=2^31 then v=v-2^32 end return v end
  function f:Close() end
  return f end,
 CreateDir=noop,Write=noop}

-- Entities: their fields say how they are drawn.
local E={} E.__index=E
local all,players,characters={}, {}, {}
local function entity(fields)
 local e=setmetatable(fields or {},E)
 e.class=e.class or 'prop_physics' e.index=#all+1 all[#all+1]=e
 if e.model==nil then e.model='models/props_c17/oildrum001.mdl' end
 e.color=e.color or {r=255,g=255,b=255,a=255} e.groups=e.groups or {} e.nw2=e.nw2 or {}
 e.bodies=e.bodies or {{name='body '..e.index}}
 return e
end
function E:EntIndex() return self.index end function E:GetClass() return self.class end
function E:IsWorld() return self.world==true end function E:IsPlayer() return self.class=='player' end
function E:IsNPC() return self.npc==true end function E:IsNextBot() return false end
function E:Alive() return true end function E:Health() return self.health or 0 end
function E:GetNoDraw() return self.nodraw==true end function E:GetOwner() return self.owner end
function E:GetRenderMode() return self.mode or RENDERMODE_NORMAL end function E:GetColor() return self.color end
function E:GetModel() return self.model~=false and self.model or nil end function E:IsScripted() return self.scripted==true end
function E:GetModelScale() return self.scale or 1 end function E:GetBodygroup(i) return self.groups[i] or 0 end
function E:GetNW2Bool(k,d) local v=self.nw2[k] if v==nil then return d end return v end
function E:GetNW2Int(k,d) local v=self.nw2[k] if v==nil then return d end return v end
function E:GetPhysicsObjectCount() return #self.bodies end function E:GetPhysicsObjectNum(i) return self.bodies[i+1] end
function E:GetChildren() return self.children or {} end

local captured
mmdhl={L=function(key) return key end,I18n={Lazy=function(t) return t end},GetInstance=function() return 0 end,
 IsMMD=function(e) return e.mmd==true end,Entities=function() return characters end,Decode=function() return {} end,SetCollisionFlags=noop,
 native={SetSecondaryCollisionFlags=noop,SceneInterest=function() return {-100,-100,-100,100,100,100} end,
  CaptureSecondaryScene=function(owners,_,excluded,ply,npc) captured={owners=owners,excluded=excluded,players=ply,npcs=npc} return '{}' end}}
ents={FindInBox=function() return all end,GetAll=function() return all end}
player={GetAll=function() return players end}
dofile(folder..'/secondary_collision.lua')
local tick=hooks.Tick and hooks.Tick['MMDHL.SecondaryScene']
check(tick,'the capture registered no Tick hook')
local function capture()
 captured=nil tick() check(captured,'the capture did not run')
 local set={} for _,body in ipairs(captured.excluded) do set[body]=true end
 return set
end
-- Whether all of an entity's bodies are excluded (true), none (false) or some (nil).
local function excluded(set,e)
 local n=0 for _,body in ipairs(e.bodies) do if set[body] then n=n+1 end end
 if n==#e.bodies then return true elseif n==0 then return false end
end
local function listed(list,e) for _,body in ipairs(list) do for _,own in ipairs(e.bodies) do if body==own then return true end end end return false end

-- The character whose hair and clothing collide: an MMD ragdoll, drawn by the add-on.
local character=entity({class='prop_ragdoll',mmd=true,model='models/mmd/0123456789abcdef/carrier.mdl'})
characters[1]=character

if scenario=='hidden' then
 local prop=entity()
 local nodraw=entity({nodraw=true})
 local none=entity({class='prop_ragdoll',mode=RENDERMODE_NONE,bodies={{},{},{}}})
 local clear=entity({mode=RENDERMODE_TRANSALPHA,color={r=255,g=255,b=255,a=0}})
 local opaque=entity({mode=RENDERMODE_NORMAL,color={r=255,g=255,b=255,a=0}})
 local faint=entity({mode=RENDERMODE_TRANSCOLOR,color={r=255,g=255,b=255,a=1}})
 local set=capture()
 check(excluded(set,prop)==false,'a visible prop was left out')
 check(excluded(set,character)==false,'the character itself was left out')
 check(excluded(set,nodraw)==true,'a no-draw prop was kept')
 check(excluded(set,none)==true,'a ragdoll with render mode none was not left out whole')
 check(excluded(set,clear)==true,'a fully transparent prop (alpha render mode) was kept')
 check(excluded(set,opaque)==false,'alpha 0 under the normal render mode, which draws it opaque, was left out')
 check(excluded(set,faint)==false,'a prop at alpha 1 was left out')
 check(mmdhl.sceneDiagnostics.hiddenEntities==3,'hiddenEntities is '..tostring(mmdhl.sceneDiagnostics.hiddenEntities)..', not 3')
elseif scenario=='visible_again' then
 local prop=entity({nodraw=true})
 local animator=entity({class='prop_dynamic',model='models/brutal_deaths/model_anim_modify.mdl'})
 local set=capture()
 check(excluded(set,prop)==true and excluded(set,animator)==true,'the hidden entities were kept')
 prop.nodraw=false animator.groups[0]=1
 set=capture()
 check(excluded(set,prop)==false,'a prop drawn again was still left out')
 check(excluded(set,animator)==false,'a model showing its mesh bodygroup was still left out')
 prop.mode=RENDERMODE_NONE set=capture()
 check(excluded(set,prop)==true,'a prop hidden again was kept')
elseif scenario=='models' then
 local addon=entity({class='prop_dynamic',model='models/brutal_deaths/model_anim_modify.mdl'})
 local shown=entity({class='prop_dynamic',model='models/brutal_deaths/model_anim_modify.mdl',groups={[0]=1}})
 local someMesh=entity({class='prop_dynamic',model='models/test/two_parts.mdl',groups={[0]=0,[1]=0}})
 local allBlank=entity({class='prop_dynamic',model='models/test/two_parts.mdl',groups={[0]=0,[1]=1}})
 local noParts=entity({class='prop_dynamic',model='models/test/no_parts.mdl'})
 local noVertices=entity({model='models/test/no_vertices.mdl'})
 local missing=entity({model='models/test/missing.mdl'})
 local garbage=entity({model='models/test/not_a_model.mdl'})
 local oldVersion=entity({model='models/test/version.mdl'})
 local tiny=entity({scale=0})
 local small=entity({scale=.05})
 local set=capture()
 check(excluded(set,addon)==true,"Enhanced Death Animations' blank-bodygroup animator was kept")
 check(excluded(set,shown)==false,'the same model with its mesh bodygroup was left out')
 check(excluded(set,someMesh)==false,'a model drawing one of its two bodyparts was left out')
 check(excluded(set,allBlank)==true,'a model with every selected bodypart blank was kept')
 check(excluded(set,noParts)==true,'a model without bodyparts was kept')
 check(excluded(set,noVertices)==true,'a model whose only mesh has no vertices was kept')
 check(excluded(set,missing)==false and excluded(set,garbage)==false and excluded(set,oldVersion)==false,'a model the capture cannot read was left out')
 check(excluded(set,tiny)==true,'a model scaled to nothing was kept')
 check(excluded(set,small)==false,'a model at 5 % was left out')
 capture() capture()
 check(opened['models/brutal_deaths/model_anim_modify.mdl']==1,'a model file was read again: '..tostring(opened['models/brutal_deaths/model_anim_modify.mdl']))
 check(opened['models/test/missing.mdl']==1,'a missing model was looked for again')
elseif scenario=='followers' then
 local strider=entity({class='npc_strider',npc=true,health=350,bodies={}})
 local leg=entity({class='phys_bone_follower',nodraw=true,owner=strider})
 local animator=entity({class='prop_dynamic',model='models/brutal_deaths/model_anim_modify.mdl',bodies={}})
 local hiddenLeg=entity({class='phys_bone_follower',nodraw=true,owner=animator})
 local cloaked=entity({class='prop_dynamic',nodraw=true,bodies={}})
 local cloakedLeg=entity({class='phys_bone_follower',nodraw=true,owner=cloaked})
 local orphan=entity({class='phys_bone_follower',nodraw=true})
 local set=capture()
 check(excluded(set,leg)==false,"a visible NPC's bone follower was left out")
 check(excluded(set,hiddenLeg)==true,'the bone follower of a model drawing no mesh was kept')
 check(excluded(set,cloakedLeg)==true,'the bone follower of a no-draw model was kept')
 check(excluded(set,orphan)==false,'a bone follower without an owner was left out')
elseif scenario=='characters' then
 -- Another character near this one: its carrier's own mesh does not matter, the add-on draws it.
 local other=entity({class='prop_ragdoll',mmd=true,model='models/test/no_parts.mdl'})
 local suppressed=entity({class='prop_ragdoll',mmd=true,nw2={MMDHLNoDraw=true}})
 local faded=entity({class='prop_ragdoll',mmd=true,color={r=255,g=255,b=255,a=0}})
 local unrendered=entity({class='prop_ragdoll',mmd=true,mode=RENDERMODE_NONE})
 local hiddenCharacter=entity({class='prop_ragdoll',mmd=true,nodraw=true})
 local set=capture()
 check(excluded(set,other)==false,'a character drawn by the add-on was left out for its carrier model')
 check(excluded(set,suppressed)==true,'a character the add-on does not draw (MMDHLNoDraw) was kept')
 check(excluded(set,faded)==true,'a fully transparent character was kept')
 check(excluded(set,unrendered)==false,'a character the add-on draws whatever its render mode was left out')
 check(excluded(set,hiddenCharacter)==true,'a no-draw character was kept')
elseif scenario=='stand_ins' then
 local hand=entity({class='base_anim',nodraw=true,model='models/props_junk/PopCan01a.mdl',scripted=true,MMDHLSceneStandIn=true})
 local dancer=entity({class='prop_physics',MMDHLSceneExcluded=true})
 local world=entity({class='worldspawn',world=true,nodraw=true,model='maps/gm_construct.bsp'})
 local set=capture()
 check(excluded(set,hand)==false,"the VR hand's stand-in sphere was left out")
 check(excluded(set,dancer)==true,'an MMDHLSceneExcluded collider was kept')
 check(excluded(set,world)==false,'the world was left out')
 check(mmdhl.sceneDiagnostics.hiddenEntities==0,'an explicitly excluded collider was counted as hidden')
elseif scenario=='living' then
 local me=entity({class='player'}) players[1]=me
 local ghost=entity({class='player',nodraw=true}) players[2]=ghost
 local guard=entity({class='npc_combine_s',npc=true,health=50})
 local target=entity({class='npc_bullseye',npc=true,health=1000,nodraw=true})
 local set=capture()
 check(excluded(set,me)==false and listed(captured.players,me),'a visible player was not tagged as a player')
 check(excluded(set,ghost)==true and not listed(captured.players,ghost),'an invisible player was not left out')
 check(excluded(set,guard)==false and listed(captured.npcs,guard),'a visible NPC was not tagged as an NPC')
 check(excluded(set,target)==true and not listed(captured.npcs,target),'an invisible NPC was not left out')
 check(mmdhl.sceneDiagnostics.livingEntities==2,'livingEntities is '..tostring(mmdhl.sceneDiagnostics.livingEntities)..', not 2')
elseif scenario=='children' then
 -- The sandbox bonemerge look: a hidden ragdoll wearing models merged onto its bones.
 local outfit=entity({class='prop_dynamic',model='models/props_c17/oildrum001.mdl',bodies={}})
 local dressed=entity({class='prop_ragdoll',mode=RENDERMODE_TRANSALPHA,color={r=255,g=255,b=255,a=0},children={outfit}})
 local ghostOutfit=entity({class='prop_dynamic',nodraw=true,bodies={}})
 local bare=entity({class='prop_ragdoll',nodraw=true,children={ghostOutfit}})
 local animatorOutfit=entity({class='prop_dynamic',model='models/brutal_deaths/model_anim_modify.mdl',bodies={}})
 local blankDressed=entity({class='prop_ragdoll',mode=RENDERMODE_NONE,children={animatorOutfit}})
 local set=capture()
 check(excluded(set,dressed)==false,'a transparent ragdoll wearing a drawn bonemerged model was left out')
 check(excluded(set,bare)==true,'a hidden ragdoll whose only child is hidden too was kept')
 check(excluded(set,blankDressed)==true,'a hidden ragdoll whose child draws no mesh was kept')
elseif scenario=='no_model' then
 local engine=entity({class='prop_physics',model=''})
 local nothing=entity({class='prop_physics',model=false})
 local shard=entity({class='procedural_shard',model=false,scripted=true})
 local brush=entity({class='func_brush',model='*3'})
 local hiddenBrush=entity({class='func_brush',model='*4',nodraw=true})
 local set=capture()
 check(excluded(set,engine)==true and excluded(set,nothing)==true,'an engine entity without a model was kept')
 check(excluded(set,shard)==false,'a scripted entity without a model (it may draw its own mesh) was left out')
 check(excluded(set,brush)==false,'a drawn brush entity was left out')
 check(excluded(set,hiddenBrush)==true,'a no-draw brush entity was kept')
else
 error('unknown scenario '..tostring(scenario))
end
print('PASS '..scenario)
