-- The Mesh Separator on the client (ADR 0232): the model being taken apart (a snapshot of its triangles in the pose
-- it had when it was clicked), the selection the tool and the editor share, the selection drawn on the model, the
-- detach (a Model Hotloader prop job through the import worker) and the request to place the new prop.
local S=mmdhl.separator
local M=S.Mesh
local P=mmdhl.props
local L=mmdhl.L
local native=mmdhl.native
local function cvar(name) local c=GetConVar('mmdhl_separator_'..name) return c end
local function setting(name,fallback) local c=cvar(name) return c and c:GetString() or fallback end
local function toolActive()
 local ply=LocalPlayer() if not IsValid(ply) then return false end
 local weapon=ply:GetActiveWeapon()
 return IsValid(weapon) and weapon:GetClass()=='gmod_tool' and ply:GetInfo('gmod_toolmode')=='mmdhl_separator'
end
S.ToolActive=toolActive
local function shortName(path)
 path=tostring(path or ''):gsub('\\','/')
 local name=path:match('([^/]+)$') or path
 return (name:gsub('%.[mv][dm][lt]$',''))
end
-- At most limit code points, trimmed.
local function clip(text,limit)
 text=string.Trim(tostring(text or ''))
 if not utf8.len(text) then text=text:gsub('[\128-\255]','?') end
 if utf8.len(text)>limit then text=text:sub(1,(utf8.offset(text,limit+1) or #text+1)-1) end
 return text
end
S.Clip=clip

-- The packed bodygroup number the engine keeps (m_nBody): each group's choice times the product of the earlier
-- groups' option counts.
function S.BodyMask(ent)
 local mask,scale=0,1
 for i=0,(ent:GetNumBodyGroups() or 1)-1 do
  local count=math.max(ent:GetBodygroupCount(i) or 1,1)
  mask=mask+(ent:GetBodygroup(i) or 0)*scale scale=scale*count
 end
 return mask
end
-- Linear blend skinning to the entity's current bones (GetModelMeshes' bind matrices already take a vertex into
-- the bone's space; see the Advanced Material Editor's meshuv). Returns position(pos, weights), normal(pos,
-- normal, weights) and whether bones were found; a model without them uses the entity's transform.
function S.Skinning(ent,binds)
 if ent.SetupBones then ent:SetupBones() end
 local scale=ent:GetModelScale() or 1
 local skin,found={},false
 local bones=ent:GetBoneCount() or 0
 if istable(binds) and bones>1 then
  for b=0,bones-1 do
   local bind,live=binds[b],ent:GetBoneMatrix(b)
   if istable(bind) and bind.matrix and live then skin[b]=live*bind.matrix found=true end
  end
 end
 local angles=ent:GetAngles()
 local function position(p,weights)
  if found and istable(weights) then
   local acc,total=Vector(0,0,0),0
   for _,bw in ipairs(weights) do local m=skin[bw.bone] if m then acc=acc+(m*p)*bw.weight total=total+bw.weight end end
   if total>.001 then return acc/total end
  end
  return ent:LocalToWorld(p*scale)
 end
 local function normal(p,n,weights)
  if not isvector(n) then return Vector(0,0,0) end
  if found and istable(weights) then
   local acc,total=Vector(0,0,0),0
   for _,bw in ipairs(weights) do local m=skin[bw.bone] if m then acc=acc+(m*(p+n)-m*p)*bw.weight total=total+bw.weight end end
   if total>.001 then acc:Normalize() return acc end
  end
  local r=Vector(n) r:Rotate(angles) return r
 end
 return position,normal,found
end
-- A material path as the engine compares them: lower case, forward slashes, without materials/ and .vmt.
local function normalPath(path)
 path=tostring(path or ''):lower():gsub('\\','/'):gsub('^/+','')
 path=path:gsub('^materials/',''):gsub('%.vmt$','')
 return path
end
-- The material a vanilla part is drawn with: the entity's material override, its sub-material for that slot, or the
-- model's own. A mesh names its material, not its slot: the slot is the model's material with the same path, else
-- one ending like it, else the only one (as the Advanced Bodygroup Tool maps them). A procedural override ("!name",
-- made by CreateMaterial in this session) is not kept: the prop outlives it, so the model's own material is.
local function overrides(ent)
 local whole=ent:GetMaterial() or ''
 if whole~='' and whole:sub(1,1)~='!' then return function() return whole end end
 local list=ent:GetMaterials() or {}
 local index={} for i,m in ipairs(list) do local key=normalPath(m) if index[key]==nil then index[key]=i-1 end end
 return function(material)
  local key=normalPath(material)
  local i=index[key]
  if i==nil and key~='' then for j,m in ipairs(list) do local other=normalPath(m) if other~='' and (string.EndsWith(other,key) or string.EndsWith(key,other)) then i=j-1 break end end end
  if i==nil and #list==1 then i=0 end
  local sub=i and ent:GetSubMaterial(i) or ''
  return (sub~='' and sub:sub(1,1)~='!') and sub or material
 end
end
-- RTX Remix sessions: a model's util.GetModelMeshes result that is let go passes two garbage-collector cycles before
-- the next is read (the destruction tool found that heavy work over a large dead result crashed client.dll under the
-- runtime: bullet_break_simulator cl_29_mesh_preparation.lua, cl_32_mesh_persistence.lua). Incremental steps, never a
-- full collection; at most half a second.
local function settle()
 if not (mmdhl.UsesRemixPreview and mmdhl.UsesRemixPreview()) then return end
 local cycles,probe=0,setmetatable({{}},{__mode='v'})
 local deadline=SysTime()+.5
 while cycles<2 and SysTime()<deadline do
  collectgarbage('step',256)
  if not probe[1] then cycles=cycles+1 probe=setmetatable({{}},{__mode='v'}) end
 end
end
local translucentFlag=2097152 -- MATERIAL_VAR_TRANSLUCENT
local function isTranslucent(path)
 local mat=Material(path)
 return mat and not mat:IsError() and bit.band(mat:GetInt('$flags') or 0,translucentFlag)~=0
end

-- A character's snapshot from the native module: its visible parts (JSON), the drawn positions (world) and the
-- triangles' corners as tables.
local function characterSnapshot(ent)
 local instance=tonumber(mmdhl.GetInstance(ent)) or 0
 if instance==0 then return nil,L'separator.error.no_character' end
 if not isfunction(native.SeparatorMesh) then return nil,L'separator.error.module' end
 local meta,pos,tri=native.SeparatorMesh(instance,true)
 if not meta then return nil,tostring(pos or L'separator.error.read') end
 local data=util.JSONToTable(meta,true)
 if not istable(data) or not istable(pos) or not istable(tri) or #pos~=(tonumber(data.vertices) or -1)*3 or #tri~=(tonumber(data.triangles) or -1)*3 then return nil,L'separator.error.read' end
 local parts={}
 for i,p in ipairs(data.parts or {}) do
  parts[i]={first=(tonumber(p.first) or 0)+1,count=tonumber(p.count) or 0,modelFirst=tonumber(p.modelFirst) or 0,key=tonumber(p.slot) or i,slot=p.slot,name=tostring(p.name or ''),path=p.path}
 end
 if #tri==0 or #parts==0 then return nil,L'separator.error.no_mesh' end
 local s=M.New(pos,tri,parts)
 s.kind='character' s.asset=data.asset
 return s
end
-- A vanilla model's snapshot: util.GetModelMeshes with its bodygroups and skin, skinned to its bones now.
local function modelSnapshot(ent)
 local model=ent:GetModel()
 local mask,skin=S.BodyMask(ent),ent:GetSkin() or 0
 local meshes,binds=util.GetModelMeshes(model,0,mask,skin)
 if not istable(meshes) or #meshes==0 then return nil,L'separator.error.no_mesh' end
 local position,_,skinned=S.Skinning(ent,binds)
 -- Bones that do not exist yet (a model still loading) would give its rest pose for the pose it is drawn in.
 if not skinned and istable(binds) and (ent:GetBoneCount() or 0)>1 then return nil,L'separator.error.not_ready' end
 local material=overrides(ent)
 local pos,tri,parts,verts={}, {}, {}, {}
 local nv=0
 for _,data in ipairs(meshes) do
  local tris=data.triangles
  if istable(tris) and #tris>=3 then
   local ids={} local first=#tri/3+1
   for i=1,#tris-2,3 do
    -- Source's clockwise front faces, made counter-clockwise as the props pipeline keeps them.
    for _,vt in ipairs({tris[i],tris[i+2],tris[i+1]}) do
     local id=ids[vt]
     if not id then
      nv=nv+1 id=nv ids[vt]=id verts[id]=vt
      local p=position(vt.pos,vt.weights) local o=nv*3 pos[o-2]=p.x pos[o-1]=p.y pos[o]=p.z
     end
     tri[#tri+1]=id
    end
   end
   local path=tostring(data.material or ''):gsub('\\','/')
   parts[#parts+1]={first=first,count=#tri/3-first+1,key=path,name=shortName(path),material=material(path)}
  end
 end
 if #tri==0 then return nil,L'separator.error.no_mesh' end
 local s=M.New(pos,tri,parts)
 s.kind='model' s.model=model s.mask=mask s.skin=skin s.verts=verts s.binds=binds
 return s
end
-- Where the model is: its origin, angles and first bones. A model that moved is read again at the next click.
local function poseKey(ent)
 local key={ent:GetPos(),ent:GetAngles()}
 if ent.SetupBones then ent:SetupBones() end
 for b=0,math.min((ent:GetBoneCount() or 0)-1,3) do local m=ent:GetBoneMatrix(b) if m then key[#key+1]=m:GetTranslation() end end
 return key
end
local function moved(a,b)
 if not a or not b or #a~=#b then return true end
 if a[1]:DistToSqr(b[1])>.04 then return true end
 local d=a[2]-b[2]
 if math.abs(math.NormalizeAngle(d.p))+math.abs(math.NormalizeAngle(d.y))+math.abs(math.NormalizeAngle(d.r))>.2 then return true end
 for i=3,#a do if a[i]:DistToSqr(b[i])>.04 then return true end end
 return false
end
-- The model the tool works on: a fresh snapshot when it is another model or it moved; the selection is kept for
-- the same model with the same parts.
function S.Target(ent,force)
 local kind=S.Kind(ent)
 if not kind then return nil,L'separator.error.target' end
 local current=S.target
 local key=poseKey(ent)
 if current and current.ent==ent and not force and not moved(current.key,key) then return current end
 -- The previous snapshot's mesh result is let go before another is read (settle).
 local dropped=S.dropped
 if current and current.snap.verts then current.snap.verts=nil current.snap.binds=nil dropped=true end
 if dropped then S.dropped=nil settle() end
 local started=SysTime()
 local snap,err
 if kind=='character' then snap,err=characterSnapshot(ent) else snap,err=modelSnapshot(ent) end
 if not snap then
  if current and current.snap.kind=='model' and not current.snap.verts then S.target=nil hook.Run('MMDHL.SeparatorChanged') end
  return nil,err
 end
 local kept=current and current.ent==ent and M.Adopt(snap,current.snap)
 if current and not kept and current.snap.count>0 then notification.AddLegacy(L'separator.selection_cleared',NOTIFY_HINT,5) end
 S.target={ent=ent,snap=snap,key=key,kind=kind,read=SysTime()-started}
 hook.Run('MMDHL.SeparatorChanged')
 return S.target
end
function S.Clear() local t=S.target if t then M.Clear(t.snap) hook.Run('MMDHL.SeparatorChanged') end end
function S.Count() local t=S.target return t and IsValid(t.ent) and t.snap.count or 0 end
-- The server's answer to a click: the model to work on (the one aimed at, or the one being worked on when the aim
-- passes its body), opened in the editor, where the selection is made. Nothing is drawn on the model in the world:
-- drawn on the screen under RTX Remix it cost 20 to 50 ms a frame with a few thousand triangles (ADR 0233).
net.Receive('mmdhl_separator_target',function()
 local ent=net.ReadEntity() net.ReadUInt(2)
 if not IsValid(ent) then return end
 local target,err=S.Target(ent)
 if not target then notification.AddLegacy(tostring(err),NOTIFY_ERROR,6) return end
 if S.OpenEditor then S.OpenEditor() end
end)
-- A model that is gone takes its snapshot with it (its mesh result settles before the next model is read).
hook.Add('Think','MMDHL.SeparatorTarget',function()
 local target=S.target
 if not target or IsValid(target.ent) then return end
 S.target=nil S.dropped=target.snap.verts~=nil
 hook.Run('MMDHL.SeparatorChanged')
end)

-- The selection's meshes for the editor's view: translucent triangles, with the same material the Advanced Bodygroup
-- Tool's highlight uses.
local highlight=CreateMaterial('mmdhl_separator_highlight_v1','UnlitGeneric',{['$basetexture']='vgui/white',['$vertexcolor']='1',['$vertexalpha']='1',['$translucent']='1',['$nocull']='1'})
S.HighlightMaterial=highlight
local function buildMeshes(s,list,color)
 local meshes={} local pos,tri=s.pos,s.tri
 for first=1,#list,20000 do
  local verts={}
  for i=first,math.min(#list,first+19999) do
   local o=list[i]*3
   for k=o-2,o do local v=tri[k]*3 verts[#verts+1]={pos=Vector(pos[v-2],pos[v-1],pos[v]),color=color} end
  end
  local m=Mesh(highlight) m:BuildFromTriangles(verts) meshes[#meshes+1]=m
 end
 return meshes
end
S.BuildMeshes=buildMeshes

-- The name a piece gets: its model's and the part most of it comes from.
function S.DefaultName(target)
 local s=target.snap
 local best,most=nil,0
 for p,c in pairs(M.PartCounts(s)) do if c>most then best,most=p,c end end
 local part=best and s.parts[best]
 local model
 if s.kind=='character' then
  local entry=mmdhl.library and mmdhl.library.entries and mmdhl.library.entries[s.asset]
  model=entry and (mmdhl.names and isfunction(mmdhl.names.EntryName) and mmdhl.names.EntryName('character',entry) or entry.name) or L'separator.character'
 else model=shortName(s.model) end
 local piece=part and part.name~='' and part.name or L'separator.piece'
 return clip(tostring(model)..' · '..tostring(piece),60)
end

-- A character's request: the model's triangle numbers; the module reads the vertices itself.
local function characterRequest(s,list,options)
 local triangles={}
 for i,t in ipairs(list) do local part=s.parts[s.part[t]] triangles[i]=part.modelFirst+(t-part.first) end
 return {name=options.name,collision=options.collision,pose=options.pose,triangles=triangles}
end
-- A vanilla model's request: its vertices around their centre (world positions now, or the model's at its
-- scale), normals, texture coordinates, a material per triangle that names the Source material it is drawn with.
local function modelRequest(s,ent,list,options)
 local current=options.pose~='rest'
 local position,normal=S.Skinning(ent,s.binds)
 local scale=ent:GetModelScale() or 1
 local points,indices,triMaterials,materials,remap,materialOf={}, {}, {}, {}, {}, {}
 local lo,hi=Vector(math.huge,math.huge,math.huge),Vector(-math.huge,-math.huge,-math.huge)
 for _,t in ipairs(list) do
  local p=s.part[t] local m=materialOf[p]
  if not m then
   local part=s.parts[p] m=#materials materialOf[p]=m
   materials[#materials+1]={name=part.name,source_material=part.material,color={1,1,1,1},two_sided=false,alpha_mode=isTranslucent(part.material) and 'blend' or 'opaque'}
  end
  triMaterials[#triMaterials+1]=m
  local o=t*3
  for k=o-2,o do
   local v=s.tri[k] local r=remap[v]
   if not r then
    local vt=s.verts[v] local q,n
    if current then q=position(vt.pos,vt.weights) n=normal(vt.pos,vt.normal,vt.weights) else q=vt.pos*scale n=vt.normal or Vector(0,0,0) end
    points[#points+1]={q,n,tonumber(vt.u) or 0,tonumber(vt.v) or 0} r=#points-1 remap[v]=r
    lo.x,lo.y,lo.z=math.min(lo.x,q.x),math.min(lo.y,q.y),math.min(lo.z,q.z)
    hi.x,hi.y,hi.z=math.max(hi.x,q.x),math.max(hi.y,q.y),math.max(hi.z,q.z)
   end
   indices[#indices+1]=r
  end
 end
 local centre=(lo+hi)*.5
 local vertices={}
 for _,pt in ipairs(points) do
  local q,n=pt[1]-centre,pt[2]
  vertices[#vertices+1]=q.x vertices[#vertices+1]=q.y vertices[#vertices+1]=q.z
  vertices[#vertices+1]=n.x vertices[#vertices+1]=n.y vertices[#vertices+1]=n.z
  vertices[#vertices+1]=pt[3] vertices[#vertices+1]=pt[4]
 end
 return {name=options.name,collision=options.collision,vertices=vertices,indices=indices,triangle_materials=triMaterials,materials=materials,
  separated_from={kind='model',model=s.model,pose=options.pose,skin=s.skin,bodygroups=s.mask}},centre
end
-- Detach: the selection becomes a prop in the props library (the import worker builds it, with its collision),
-- then appears where it was (current pose) or where the player aims (rest pose). options: name, pose
-- ('current' or 'rest'), collision ('auto', 'hull' or 'balanced'), frozen, place.
function S.Detach(options)
 options=options or {}
 local target=S.target
 if not target or not IsValid(target.ent) then return false,L'separator.error.no_target' end
 local s=target.snap
 if s.count==0 then return false,L'separator.error.empty' end
 if not S.Enabled:GetBool() then return false,L'separator.error.disabled' end
 local library=mmdhl.library
 if library.job then return false,L'props.library.import_busy' end
 if mmdhl.FeatureAvailable and not mmdhl.FeatureAvailable('imports') then return false,L'separator.error.no_worker' end
 if not isfunction(native.PropFromMesh) then return false,L'separator.error.module' end
 local list=M.List(s)
 if #list>S.MaxTriangles then return false,L('separator.error.too_large',{count=string.Comma(#list),limit=string.Comma(S.MaxTriangles)}) end
 local pose=options.pose=='rest' and 'rest' or 'current'
 local name=clip(options.name,60) if name=='' then name=S.DefaultName(target) end
 local collision=(options.collision=='hull' or options.collision=='balanced') and options.collision or 'auto'
 local request={name=name,pose=pose,collision=collision}
 local handle,second,origin
 if s.kind=='character' then
  local instance=tonumber(mmdhl.GetInstance(target.ent)) or 0
  if instance==0 then return false,L'separator.error.no_character' end
  handle,second=native.PropFromMesh(util.TableToJSON(characterRequest(s,list,request)),instance)
  if handle then
   local o=istable(second) and second or util.JSONToTable(tostring(second or ''))
   if istable(o) then origin=Vector(tonumber(o[1]) or 0,tonumber(o[2]) or 0,tonumber(o[3]) or 0) end
  end
 else
  local body,centre=modelRequest(s,target.ent,list,request)
  handle,second=native.PropFromMesh(util.TableToJSON(body))
  origin=centre
 end
 if not library.StartImport(handle,second,'static') then return false,tostring(second or L'separator.error.no_worker') end
 library.status=L('separator.status.detaching',{name=name}) hook.Run('MMDHL.ImportChanged')
 S.pending={job=handle,pose=pose,origin=origin,ent=target.ent,frozen=options.frozen~=false,place=options.place~=false,name=name}
 hook.Run('MMDHL.SeparatorChanged')
 return true
end
-- Placing a detached piece: on a server a new prop must be shared first (an administrator's), as for any prop.
function S.Place(id,pending)
 local function send()
  net.Start('mmdhl_separator_place') net.WriteString(id) net.WriteEntity(IsValid(pending.ent) and pending.ent or NULL)
  net.WriteBool(pending.pose=='current' and pending.origin~=nil) net.WriteVector(pending.origin or vector_origin) net.WriteBool(pending.frozen==true)
  net.SendToServer()
 end
 if game.SinglePlayer() or P.library.approved[id] then send() return end
 if not LocalPlayer():IsAdmin() then notification.AddLegacy(L'separator.saved_not_shared',NOTIFY_HINT,8) return end
 local ok,err=mmdhl.PublishProp(id)
 if not ok then notification.AddLegacy(tostring(err),NOTIFY_ERROR,8) return end
 local name='MMDHL.SeparatorPlace'..id
 local function done() hook.Remove('MMDHL.PropApproved',name) hook.Remove('MMDHL.ShareUploadFailed',name) end
 hook.Add('MMDHL.PropApproved',name,function(approved) if approved~=id then return end done() send() end)
 hook.Add('MMDHL.ShareUploadFailed',name,function(failed,why) if failed~=id then return end done() notification.AddLegacy(tostring(why or L'share.cancelled'),NOTIFY_ERROR,8) end)
end
-- The server's answer to a placement: a notice in the right colour; a refusal also in the console, with its reason.
net.Receive('mmdhl_separator_result',function()
 local ok=net.ReadBool() local message=mmdhl.Localize(net.ReadString())
 notification.AddLegacy(message,ok and NOTIFY_GENERIC or NOTIFY_ERROR,ok and 5 or 8)
 if not ok then MsgN('[Mesh Separator] '..message) end
 hook.Run('MMDHL.SeparatorPlaced',ok,message)
end)
hook.Add('MMDHL.PropImported','MMDHL.Separator',function(id)
 local pending=S.pending if not pending then return end
 S.pending=nil S.last=id
 hook.Run('MMDHL.SeparatorChanged')
 if pending.place then S.Place(id,pending) end
end)
-- A job that ended without a prop (failed, cancelled) leaves nothing pending.
hook.Add('MMDHL.ImportChanged','MMDHL.SeparatorJob',function()
 local pending=S.pending
 if pending and mmdhl.library.job~=pending.job then S.pending=nil hook.Run('MMDHL.SeparatorChanged') end
end)
concommand.Add('mmdhl_separator_clear',function() S.Clear() end)
concommand.Add('mmdhl_separator_detach',function()
 local ok,err=S.Detach({name=setting('name',''),pose=setting('pose','current'),collision=setting('collision','auto'),frozen=setting('freeze','1')~='0',place=setting('place','1')~='0'})
 if not ok then notification.AddLegacy(tostring(err),NOTIFY_ERROR,6) end
end)
