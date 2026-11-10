-- Runs the Seamless Portals entity's shipped client file (arg[1], seamless_portal/cl_init.lua) under LuaJIT with
-- the engine instrumented, and draws portals in every branch of ENT:Draw / ENT:DrawStenciled: no ENT:GetRenderMesh,
-- no DrawModel (the path that crashes queued rendering at studiorender.dll+0x6603b), and the frame drawn as its
-- mesh with the portal's material, under the portal's transform scaled by its size, as GetRenderMesh's matrix did.
local function fail(text) io.stderr:write('FAIL: '..text..'\n') os.exit(1) end
local function check(ok,text) if not ok then fail(text) end end
local function near(a,b) return math.abs(a-b)<1e-6 end

local V={} V.__index=V
function Vector(x,y,z) return setmetatable({x or 0,y or 0,z or 0},V) end
function V:Mul(o) for i=1,3 do self[i]=self[i]*(type(o)=='number' and o or o[i]) end return self end
function V.__eq(a,b) return a[1]==b[1] and a[2]==b[2] and a[3]==b[3] end
local state={material=nil,cull=0,matrix=nil,stencil=false,draws={},textures=0}
local drawMat
function Material(name) local m={name=name} if name=='models/dav0r/hoverball' then drawMat=m end return m end
function CreateClientConVar() return {GetFloat=function() return 250 end} end
function include() end
function ScrW() return 1920 end
function ScrH() return 1080 end
function GetRenderTarget(name) return {name=name} end
function IsValid(v) return v~=nil and v~=false end
game={SinglePlayer=function() return false end}
hook={Add=function() end,Remove=function() end}
timer={Simple=function() end}
table.RemoveByValue=function() end
halo={rendered=nil,RenderedEntity=function() return halo.rendered end}
local M={} M.__index=M
-- A portal's world transform; SetScale keeps rotation and position (GMod's VMatrix:SetScale).
local function worldMatrix(entity) return setmetatable({entity=entity,scale={1,1,1}},M) end
function M:SetScale(v) self.scale={v[1],v[2],v[3]} end
function Matrix() return setmetatable({scale={1,1,1}},M) end
cam={PushModelMatrix=function(m) check(state.matrix==nil,'model matrices are not nested') state.matrix=m end,
 PopModelMatrix=function() check(state.matrix~=nil,'pop without push') state.matrix=nil end}
render={SetMaterial=function(m) state.material=m end,CullMode=function(c) state.cull=c end,ClearStencil=function() end,
 SetStencilWriteMask=function() end,SetStencilTestMask=function() end,SetStencilReferenceValue=function() end,
 SetStencilFailOperation=function() end,SetStencilZFailOperation=function() end,SetStencilPassOperation=function() end,
 SetStencilCompareFunction=function() end,SetStencilEnable=function(e) state.stencil=e end,
 DrawTextureToScreenRect=function() state.textures=state.textures+1 end}
STENCIL_KEEP,STENCIL_REPLACE,STENCIL_ALWAYS,STENCIL_EQUAL=1,3,8,3
local Msh={} Msh.__index=Msh
function Mesh() return setmetatable({},Msh) end
function Msh:BuildFromTriangles(t) self.triangles=#t/3 end
function Msh:Draw()
 check(state.matrix~=nil,'the portal mesh is drawn under the portal model matrix')
 state.draws[#state.draws+1]={material=state.material,cull=state.cull,entity=state.matrix.entity,
  scale={state.matrix.scale[1],state.matrix.scale[2],state.matrix.scale[3]},stencil=state.stencil}
end
SeamlessPortals={Portals={},Rendering=false,claimed={}}
SeamlessPortals.IsRemixPortalClaimed=function(p) return SeamlessPortals.claimed[p]==true end
ENT={}
assert(loadfile(arg[1]))()
check(ENT.GetRenderMesh==nil,'the portal must not define ENT:GetRenderMesh (DrawModel would draw it through studiorender)')
check(type(SeamlessPortals.GetRenderMesh)=='function','the mesh builder stays (SeamlessPortals.GetRenderMesh)')

local function portal(size,exit,backface)
 local p={size=size,sides=4,exit=exit,noBackface=backface or false}
 function p:GetSize() return Vector(self.size[1],self.size[2],self.size[3]) end
 function p:GetSidesInternal() return self.sides end
 function p:GetDisableBackface() return self.noBackface end
 function p:GetExitPortal() return self.exit end
 function p:GetWorldTransformMatrix() return worldMatrix(self) end
 function p:DrawModel() fail('DrawModel must not draw a portal (GetRenderMesh + DrawModel crashes queued rendering)') end
 return setmetatable(p,{__index=ENT})
end
local function draw(p) state.draws={} state.textures=0 state.material=nil p:Draw(0) return state.draws end
local r2=math.sqrt(2)
local function scaled(d,size,z) return near(d.scale[1],size[1]*r2) and near(d.scale[2],size[2]*r2) and near(d.scale[3],z) end

-- An unlinked portal: the frame (backface), then the flat face, both with the portal's material.
local alone=portal({50,40,8})
local d=draw(alone)
check(#d==2,'an unlinked portal draws its frame and its flat face: '..#d)
check(d[1].material==drawMat and d[1].cull==0 and d[1].entity==alone and scaled(d[1],alone.size,8),'the frame: the whole mesh, scaled by the portal size, portal material, normal culling')
check(d[2].material==drawMat and d[2].cull==1 and scaled(d[2],alone.size,0),'the flat face: flattened, reversed culling, the same material')
check(state.cull==0,'culling is put back')

-- A linked portal outside a portal view: the frame, then the stencilled inside and the view texture.
local exit=portal({50,50,8})
local linked=portal({50,50,8},exit)
d=draw(linked)
check(#d==2 and d[1].cull==0 and not d[1].stencil and scaled(d[1],linked.size,8),'a linked portal draws its frame first')
check(d[2].stencil and d[2].cull==1 and d[2].material==drawMat and scaled(d[2],linked.size,8),'then its inside into the stencil')
check(state.textures==1 and not state.stencil,'then the other side through the stencil, which is switched off after')
-- Inside a portal view the linked portal draws as the unlinked one.
SeamlessPortals.Rendering=true
d=draw(linked)
check(#d==2 and d[2].cull==1 and scaled(d[2],linked.size,0) and state.textures==0,'inside a portal view: frame and flat face')
SeamlessPortals.Rendering=false

-- No backface: no frame; the stencilled inside still draws with the portal's material.
local bare=portal({30,30,4},exit,true)
d=draw(bare)
check(#d==1 and d[1].stencil and d[1].material==drawMat,'a portal without backface draws only its inside')

-- A portal the Remix runtime renders, and a halo pass, draw nothing.
SeamlessPortals.claimed[linked]=true
check(#draw(linked)==0,'a portal claimed by the Remix runtime draws nothing')
SeamlessPortals.claimed[linked]=nil
halo.rendered=linked
check(#draw(linked)==0,'a halo pass draws nothing')
halo.rendered=nil

-- The mesh: one per number of sides, kept.
check(SeamlessPortals.GetRenderMesh(4)==SeamlessPortals.GetRenderMesh(4),'the mesh of a side count is built once')
check(SeamlessPortals.GetRenderMesh(6).triangles==18,'six sides: a cap triangle and two wall triangles each')
print('PASS: portals draw their mesh directly')
