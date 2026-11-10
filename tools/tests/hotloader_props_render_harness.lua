-- Runs the Model Hotloader's actual props/render.lua (arg[1]) with the engine instrumented:
-- builds a static prop through the real preparation hooks, draws it, and checks that no
-- entity draws it through GetRenderMesh/DrawModel (the queued-rendering crash), the model
-- matrix, the colour materials and that released meshes outlive the frames that may draw them.
local function fail(text) io.stderr:write('FAIL: '..text..'\n') os.exit(1) end
local function check(ok,text) if not ok then fail(text) end end
local function near(a,b) return math.abs(a-b)<1e-4 end

-- Vectors, angles and matrices with Source's conventions.
local V={} V.__index=V
function Vector(x,y,z) return setmetatable({x=x or 0,y=y or 0,z=z or 0},V) end
function V.__add(a,b) return Vector(a.x+b.x,a.y+b.y,a.z+b.z) end
function V.__sub(a,b) return Vector(a.x-b.x,a.y-b.y,a.z-b.z) end
function V.__mul(a,b) if type(a)=='number' then a,b=b,a end return Vector(a.x*b,a.y*b,a.z*b) end
function V.__unm(a) return Vector(-a.x,-a.y,-a.z) end
function V:Dot(b) return self.x*b.x+self.y*b.y+self.z*b.z end
function V:DistToSqr(b) local d=self-b return d:Dot(d) end
local A={} A.__index=A
function Angle(p,y,r) return setmetatable({p=p or 0,y=y or 0,r=r or 0},A) end
local function trig(a) local rad=math.pi/180 return math.sin(a.p*rad),math.cos(a.p*rad),math.sin(a.y*rad),math.cos(a.y*rad),math.sin(a.r*rad),math.cos(a.r*rad) end
function A:Forward() local sp,cp,sy,cy=trig(self) return Vector(cp*cy,cp*sy,-sp) end
function A:Right() local sp,cp,sy,cy,sr,cr=trig(self) return Vector(-sr*sp*cy+cr*sy,-sr*sp*sy-cr*cy,-sr*cp) end
function A:Up() local sp,cp,sy,cy,sr,cr=trig(self) return Vector(cr*sp*cy+sr*sy,cr*sp*sy-sr*cy,cr*cp) end
angle_zero=Angle(0,0,0) vector_origin=Vector(0,0,0)
function LocalToWorld(lp,_,pos,ang) return pos+ang:Forward()*lp.x-ang:Right()*lp.y+ang:Up()*lp.z,ang end
function WorldToLocal(wp,_,pos,ang) local d=wp-pos return Vector(d:Dot(ang:Forward()),-d:Dot(ang:Right()),d:Dot(ang:Up())),angle_zero end
local M={} M.__index=M
function Matrix(rows) check(type(rows)=='table' and #rows==4,'the model matrix is built from its four rows') return setmetatable({rows=rows},M) end
function M:apply(v) local r=self.rows return Vector(r[1][1]*v.x+r[1][2]*v.y+r[1][3]*v.z+r[1][4],r[2][1]*v.x+r[2][2]*v.y+r[2][3]*v.z+r[2][4],r[3][1]*v.x+r[3][2]*v.y+r[3][3]*v.z+r[3][4]) end
local C={} C.__index=C
function Color(r,g,b,a) return setmetatable({r=r,g=g,b=b,a=a or 255},C) end
color_white=Color(255,255,255,255)

-- The engine and GMod libraries the file uses.
local FRAME,NOW=1,0
function FrameNumber() return FRAME end
function SysTime() return NOW end
function RealTime() return NOW end
function IsValid(v) return v~=nil and v~=false and (type(v)~='table' or not v.removed) end
function istable(v) return type(v)=='table' end
function isnumber(v) return type(v)=='number' end
function EyeAngles() return Angle(0,0,0) end
math.Clamp=function(v,lo,hi) return math.min(math.max(v,lo),hi) end
local bitlib=require('bit') bit={bor=bitlib.bor,band=bitlib.band,bnot=bitlib.bnot}
local hooks={}
hook={Add=function(event,name,fn) hooks[event]=hooks[event] or {} hooks[event][name]=fn end,Run=function() end}
local function run(event,...) for _,fn in pairs(hooks[event] or {}) do fn(...) end end
cvars={AddChangeCallback=function() end}
concommand={Add=function() end}
net={Receive=function() end}
util={JSONToTable=function() return nil end}
CreateClientConVar=function() return {GetBool=function() return true end} end
ents={CreateClientside=function() fail('a static prop piece must not be an entity (GetRenderMesh + DrawModel crashes queued rendering)') end}
scripted_ents={Register=function() fail('no proxy entity class may be registered') end}
local Mat={} Mat.__index=Mat
local created={}
function Mat:GetTexture() return {GetName=function() return 'texture/'..self.name end} end
function Mat:SetVector(k,v) self.params[k]=v end
function Mat:SetFloat(k,v) self.params[k]=v end
function Mat:SetInt(k,v) self.params[k]=v end
function Mat:GetInt(k) return self.params[k] end
function Mat:Recompute() self.recomputed=(self.recomputed or 0)+1 end
function Material(path) return setmetatable({name=path,params={}},Mat) end
function CreateMaterial(name,shader,params)
 check(shader=='VertexLitGeneric','prop materials stay VertexLitGeneric')
 if created[name] then return created[name] end
 local copy={['$flags']=params['$translucent']==1 and 2097152 or 0} for k,v in pairs(params) do copy[k]=v end
 created[name]=setmetatable({name=name,params=copy},Mat) return created[name]
end
local meshes,draws,destroyed={}, {}, 0
local Msh={} Msh.__index=Msh
function Mesh(mat) local m=setmetatable({material=mat},Msh) meshes[#meshes+1]=m return m end
function Msh:BuildFromTriangles(vertices) self.count=#vertices end
local state={matrix=nil,material=nil,modulation={.25,.5,.75},blend=.6,pushes=0}
function Msh:Draw()
 check(not self.destroyed,'a destroyed mesh was drawn')
 check(state.matrix~=nil,'a piece is drawn under the prop model matrix')
 check(state.modulation[1]==1 and state.modulation[2]==1 and state.modulation[3]==1 and state.blend==1,'the caller modulation does not tint the meshes twice')
 draws[#draws+1]={mesh=self,material=state.material,matrix=state.matrix}
end
function Msh:Destroy() check(not self.destroyed,'a mesh was destroyed twice') self.destroyed=true destroyed=destroyed+1 end
cam={PushModelMatrix=function(m) check(state.matrix==nil,'model matrices are not nested') state.matrix=m state.pushes=state.pushes+1 end,
 PopModelMatrix=function() check(state.matrix~=nil,'pop without push') state.matrix=nil end}
render={SetMaterial=function(m) state.material=m end,SuppressEngineLighting=function() end,SetModelLighting=function() end,
 ComputeLighting=function() return Vector(.5,.5,.5) end,RenderFlashlights=function(fn) state.flashlight=true fn() state.flashlight=false end,
 GetColorModulation=function() return unpack(state.modulation) end,SetColorModulation=function(r,g,b) state.modulation={r,g,b} end,
 GetBlend=function() return state.blend end,SetBlend=function(b) state.blend=b end}
local Ent={} Ent.__index=Ent
function Ent:DrawModel() fail('DrawModel must not draw a static prop') end

-- The prop: three materials (opaque, blended, a masked one that is fully cut out), one part each.
local ID=string.rep('a',64)
local info={name='Fixture',format='pmx',mins={-10,-10,0},maxs={10,10,20},render_origin={1,2,3},
 materials={{base_texture='',color={1,.5,.25,1},alpha_mode='opaque'},{base_texture='',color={1,1,1,.5},alpha_mode='blend'},
  {base_texture='',color={1,1,1,.1},alpha_mode='mask',alpha_cutoff=.5}},
 parts={{count=6,material=0},{count=3,material=1},{count=3,material=2}}}
local native={PropHas=function(id) return id==ID end,PropCollisionBlob=function() return nil end,
 PropReadMeshBatch=function(_,part,offset,count) local batch={} for i=1,count do batch[i]={pos=Vector(i,0,0)} end return batch end,
 PropRelease=function() end}
local P={native=native,MinScale=.01,MaxScale=100,Info={}}
function P.ValidID(id) return type(id)=='string' and #id==64 end
function P.Vector(v) return Vector(v[1],v[2],v[3]) end
function P.Load(id,cb) cb(info) end
function P.Forget(id) P.Info[id]=nil end
mmdhl={props=P,L=function(k) return k end}

assert(loadfile(arg[1]))()
check(P.RetireFrames and P.RetireFrames>=2,'released meshes wait for queued frames')

-- Build through the real preparation hooks (AcquireRender of a fresh id starts it).
local entry=P.AcquireRender(ID)
for _=1,20 do run('Think') if entry.state=='ready' then break end end
check(entry.state=='ready','the prop prepares through its Think hooks: '..tostring(entry.state)..' '..tostring(entry.error))
check(#entry.pieces==3 and #entry.opaque==2 and #entry.blended==1,'three pieces, two opaque and one blended')
for _,piece in ipairs(entry.pieces) do check(piece.entity==nil,'no piece holds an entity') check(piece.mesh~=nil,'each piece keeps its mesh') end

-- Opaque pass: one push, every visible opaque piece with its own material, under the right matrix.
local pos,ang,scale=Vector(100,-50,25),Angle(10,90,5),2
check(P.DrawAsset(ID,pos,ang,false,nil,scale,false),'a ready prop draws')
check(#draws==1,'the fully cut-out masked piece is skipped; the opaque piece is drawn: '..#draws)
check(draws[1].material==entry.materials[1],'the plain material for a white prop')
check(state.modulation[1]==.25 and state.modulation[2]==.5 and state.modulation[3]==.75 and state.blend==.6,'the caller modulation is restored')
local m=draws[1].matrix
local origin=LocalToWorld(Vector(1,2,3)*scale,angle_zero,pos,ang)
for _,v in ipairs({Vector(0,0,0),Vector(1,0,0),Vector(0,1,0),Vector(0,0,1),Vector(3,-4,5)}) do
 local want=origin+ang:Forward()*(v.x*scale)-ang:Right()*(v.y*scale)+ang:Up()*(v.z*scale)
 local got=m:apply(v)
 check(near(got.x,want.x) and near(got.y,want.y) and near(got.z,want.z),'model matrix places a vertex as the proxy entity did')
end

-- Lighting and flashlights: with lighting the pieces are drawn twice (colour, flashlight pass).
draws={}
check(P.DrawAsset(ID,pos,ang,true,nil,1,{}),'translucent pass draws')
check(#draws==2 and draws[1].material==entry.materials[2],'the blended piece in the colour pass and again in the flashlight pass')

-- A colour: its own translucent material, made once and reused.
draws={}
local ghost=Color(160,220,255,150)
P.DrawAsset(ID,pos,ang,false,ghost,1,false)
local tinted=draws[1].material
check(tinted~=entry.materials[1],'a coloured prop draws with a material of its colour')
check(bitlib.band(tinted.params['$flags'],2097152)~=0 and near(tinted.params['$alpha'],150/255),'alpha below one makes the colour material translucent')
local c2=tinted.params['$color2']
check(type(c2)=='table' and near(c2.x,160/255) and near(c2.y,.5*220/255) and near(c2.z,.25*255/255),'$color2 is the base colour times the prop colour')
draws={}
P.DrawAsset(ID,pos,ang,false,ghost,1,false)
check(draws[1].material==tinted,'the same colour reuses its material')
-- Nine colours: the least recently used of eight takes the ninth.
for i=1,9 do FRAME=FRAME+1 draws={} P.DrawAsset(ID,pos,ang,false,Color(i,i,i,255),1,false) end
check(#entry.tints==P.MaxTints,'at most eight colours per prop: '..#entry.tints)
local reused=draws[1].material
check(near(reused.params['$color2'].x,9/255) and bitlib.band(reused.params['$flags'],2097152)==0,'a reused colour material takes the new colour and opacity')

-- Release: meshes outlive the frames a queued renderer may still draw.
local before=destroyed
P.DestroyRender(ID)
check(destroyed==before,'a released mesh is not destroyed at once')
for _=1,P.RetireFrames-1 do FRAME=FRAME+1 run('Think') end
check(destroyed==before,'released meshes wait '..P.RetireFrames..' frames')
FRAME=FRAME+1 run('Think')
check(destroyed==before+3,'then all three are destroyed: '..(destroyed-before))
check(P.DrawAsset(ID,pos,ang,false,nil,1,false)==false,'a released prop no longer draws')

-- A frame counter that goes back (a new map) still releases a retired mesh.
entry=P.AcquireRender(ID)
for _=1,20 do run('Think') if entry.state=='ready' then break end end
P.DestroyRender(ID)
FRAME=1 run('Think')
check(destroyed==before+6,'meshes retired before a frame counter reset are destroyed')
print('PASS: static props draw their meshes directly')
