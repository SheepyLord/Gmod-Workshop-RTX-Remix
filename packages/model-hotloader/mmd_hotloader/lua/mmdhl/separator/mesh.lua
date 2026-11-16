-- The Mesh Separator's selection engine (ADR 0232): a snapshot of a model's triangles, the pieces it is made of,
-- a grid for rays and brushes, regions drawn on the screen, and the selection itself. Plain Lua over numbers (no
-- engine types), so tools/tests/separator_mesh_harness.lua runs it outside the game.
--
-- A snapshot holds pos (x, y, z of each vertex, flat), tri (the three 1-based vertex numbers of each triangle,
-- flat: triangle t is tri[3t-2], tri[3t-1], tri[3t]) and parts (each {first=<its first triangle>, count=<its
-- triangles>, ...}, in triangle order). The selection is a set of triangle numbers.
local M={}
local floor,ceil,min,max,abs,sqrt,huge=math.floor,math.ceil,math.min,math.max,math.abs,math.sqrt,math.huge
local function clamp(v,lo,hi) if v<lo then return lo elseif v>hi then return hi end return v end

function M.New(pos,tri,parts)
 local s={pos=pos,tri=tri,parts=parts,n=floor(#tri/3),nv=floor(#pos/3),selected={},count=0,revision=0}
 local part={}
 for p,info in ipairs(parts) do for t=info.first,info.first+info.count-1 do part[t]=p end end
 s.part=part
 return s
end

-- The centre of triangle t.
function M.Centroid(s,t)
 local pos,tri=s.pos,s.tri local o=t*3
 local a,b,c=tri[o-2]*3,tri[o-1]*3,tri[o]*3
 return (pos[a-2]+pos[b-2]+pos[c-2])/3,(pos[a-1]+pos[b-1]+pos[c-1])/3,(pos[a]+pos[b]+pos[c])/3
end

function M.Bounds(s)
 local pos=s.pos local x0,y0,z0,x1,y1,z1=huge,huge,huge,-huge,-huge,-huge
 for i=1,#pos,3 do
  local x,y,z=pos[i],pos[i+1],pos[i+2]
  if x<x0 then x0=x end if x>x1 then x1=x end
  if y<y0 then y0=y end if y>y1 then y1=y end
  if z<z0 then z0=z end if z>z1 then z1=z end
 end
 if x0>x1 then x0,y0,z0,x1,y1,z1=0,0,0,0,0,0 end
 s.mins,s.maxs={x0,y0,z0},{x1,y1,z1}
 return s.mins,s.maxs
end

-- Pieces: triangles joined by a corner, corners joined where they lie at the same place (to a thousandth of a
-- unit), so texture seams and material borders do not split a piece, and an inside copy of a layer (a back-face
-- copy) stays with its layer. s.island[t] is t's piece; s.islandTris[i] lists piece i's triangles.
function M.Islands(s,tolerance)
 local inv=1/(tolerance or .001)
 local pos,tri=s.pos,s.tri
 local weld,ids,keys={},{},0
 for v=1,s.nv do
  local i=v*3
  local key=floor(pos[i-2]*inv+.5)..' '..floor(pos[i-1]*inv+.5)..' '..floor(pos[i]*inv+.5)
  local id=ids[key] if not id then keys=keys+1 id=keys ids[key]=id end
  weld[v]=id
 end
 local parent={} for i=1,keys do parent[i]=i end
 local function find(x)
  local r=x while parent[r]~=r do r=parent[r] end
  while parent[x]~=r do local up=parent[x] parent[x]=r x=up end
  return r
 end
 for t=1,s.n do
  local o=t*3
  local a,b=find(weld[tri[o-2]]),find(weld[tri[o-1]])
  if a~=b then parent[b]=a end
  local c=find(weld[tri[o]]) a=find(a)
  if a~=c then parent[c]=a end
 end
 local island,members,index,count={},{},{},0
 for t=1,s.n do
  local r=find(weld[tri[t*3-2]])
  local k=index[r] if not k then count=count+1 k=count index[r]=k members[k]={} end
  island[t]=k local m=members[k] m[#m+1]=t
 end
 s.island,s.islandTris,s.islands=island,members,count
 return count
end

-- A uniform grid over the triangles' bounds, about two triangles a cell, at most 96 cells along an axis.
function M.Grid(s)
 local mins,maxs=M.Bounds(s)
 local pad=1e-3
 local x0,y0,z0=mins[1]-pad,mins[2]-pad,mins[3]-pad
 local dx,dy,dz=maxs[1]-mins[1]+2*pad,maxs[2]-mins[2]+2*pad,maxs[3]-mins[3]+2*pad
 local size=(dx*dy*dz/max(1,s.n/2))^(1/3)
 if not (size>0) then size=max(dx,dy,dz) end
 local nx,ny,nz=clamp(ceil(dx/size),1,96),clamp(ceil(dy/size),1,96),clamp(ceil(dz/size),1,96)
 local cx,cy,cz=dx/nx,dy/ny,dz/nz
 local cells,pos,tri={},s.pos,s.tri
 for t=1,s.n do
  local o=t*3 local a,b,c=tri[o-2]*3,tri[o-1]*3,tri[o]*3
  local ax,ay,az,bx,by,bz,qx,qy,qz=pos[a-2],pos[a-1],pos[a],pos[b-2],pos[b-1],pos[b],pos[c-2],pos[c-1],pos[c]
  local i0,i1=clamp(floor((min(ax,bx,qx)-x0)/cx),0,nx-1),clamp(floor((max(ax,bx,qx)-x0)/cx),0,nx-1)
  local j0,j1=clamp(floor((min(ay,by,qy)-y0)/cy),0,ny-1),clamp(floor((max(ay,by,qy)-y0)/cy),0,ny-1)
  local k0,k1=clamp(floor((min(az,bz,qz)-z0)/cz),0,nz-1),clamp(floor((max(az,bz,qz)-z0)/cz),0,nz-1)
  for k=k0,k1 do for j=j0,j1 do for i=i0,i1 do
   local key=(k*ny+j)*nx+i+1
   local cell=cells[key] if not cell then cell={} cells[key]=cell end
   cell[#cell+1]=t
  end end end
 end
 s.grid={x0=x0,y0=y0,z0=z0,cx=cx,cy=cy,cz=cz,nx=nx,ny=ny,nz=nz,cells=cells}
 return s.grid
end

-- The distance along a unit ray to triangle t, either side (Moller-Trumbore), or nil.
local function hit(s,t,ox,oy,oz,dx,dy,dz)
 local pos,tri=s.pos,s.tri local o=t*3
 local a,b,c=tri[o-2]*3,tri[o-1]*3,tri[o]*3
 local ax,ay,az=pos[a-2],pos[a-1],pos[a]
 local e1x,e1y,e1z=pos[b-2]-ax,pos[b-1]-ay,pos[b]-az
 local e2x,e2y,e2z=pos[c-2]-ax,pos[c-1]-ay,pos[c]-az
 local px,py,pz=dy*e2z-dz*e2y,dz*e2x-dx*e2z,dx*e2y-dy*e2x
 local det=e1x*px+e1y*py+e1z*pz
 if det>-1e-12 and det<1e-12 then return nil end
 local inv=1/det
 local tx,ty,tz=ox-ax,oy-ay,oz-az
 local u=(tx*px+ty*py+tz*pz)*inv if u<0 or u>1 then return nil end
 local qx,qy,qz=ty*e1z-tz*e1y,tz*e1x-tx*e1z,tx*e1y-ty*e1x
 local v=(dx*qx+dy*qy+dz*qz)*inv if v<0 or u+v>1 then return nil end
 local d=(e2x*qx+e2y*qy+e2z*qz)*inv
 if d<0 then return nil end
 return d
end

-- The first triangle along a ray (either side), through the grid: triangle, distance and the point hit.
function M.Raycast(s,ox,oy,oz,dx,dy,dz,limit)
 local g=s.grid or M.Grid(s)
 local len=sqrt(dx*dx+dy*dy+dz*dz) if len<1e-12 then return nil end
 dx,dy,dz=dx/len,dy/len,dz/len
 limit=limit or huge
 local lo={g.x0,g.y0,g.z0} local hi={g.x0+g.cx*g.nx,g.y0+g.cy*g.ny,g.z0+g.cz*g.nz}
 local o,d={ox,oy,oz},{dx,dy,dz}
 local t0,t1=0,limit
 for a=1,3 do
  if abs(d[a])<1e-12 then
   if o[a]<lo[a] or o[a]>hi[a] then return nil end
  else
   local ta,tb=(lo[a]-o[a])/d[a],(hi[a]-o[a])/d[a]
   if ta>tb then ta,tb=tb,ta end
   if ta>t0 then t0=ta end if tb<t1 then t1=tb end
  end
 end
 if t0>t1 then return nil end
 local sx,sy,sz=ox+dx*t0,oy+dy*t0,oz+dz*t0
 local i=clamp(floor((sx-g.x0)/g.cx),0,g.nx-1)
 local j=clamp(floor((sy-g.y0)/g.cy),0,g.ny-1)
 local k=clamp(floor((sz-g.z0)/g.cz),0,g.nz-1)
 local stepX,stepY,stepZ=dx>0 and 1 or -1,dy>0 and 1 or -1,dz>0 and 1 or -1
 local nextX=dx>0 and (g.x0+(i+1)*g.cx-ox)/dx or dx<0 and (g.x0+i*g.cx-ox)/dx or huge
 local nextY=dy>0 and (g.y0+(j+1)*g.cy-oy)/dy or dy<0 and (g.y0+j*g.cy-oy)/dy or huge
 local nextZ=dz>0 and (g.z0+(k+1)*g.cz-oz)/dz or dz<0 and (g.z0+k*g.cz-oz)/dz or huge
 local deltaX,deltaY,deltaZ=dx~=0 and g.cx/abs(dx) or huge,dy~=0 and g.cy/abs(dy) or huge,dz~=0 and g.cz/abs(dz) or huge
 local best,bestD,tested=nil,huge,{}
 local cells,nx,ny,nz=g.cells,g.nx,g.ny,g.nz
 while true do
  local cell=cells[(k*ny+j)*nx+i+1]
  if cell then
   for n=1,#cell do
    local t=cell[n]
    if not tested[t] then
     tested[t]=true
     local dist=hit(s,t,ox,oy,oz,dx,dy,dz)
     if dist and dist<bestD and dist<=limit then best,bestD=t,dist end
    end
   end
  end
  local exit=min(nextX,nextY,nextZ)
  if bestD<=exit or exit>t1 then break end
  if nextX<=nextY and nextX<=nextZ then i=i+stepX if i<0 or i>=nx then break end nextX=nextX+deltaX
  elseif nextY<=nextZ then j=j+stepY if j<0 or j>=ny then break end nextY=nextY+deltaY
  else k=k+stepZ if k<0 or k>=nz then break end nextZ=nextZ+deltaZ end
 end
 if not best then return nil end
 return best,bestD,ox+dx*bestD,oy+dy*bestD,oz+dz*bestD
end

-- Triangles whose centre lies within r of a point (the brush).
function M.Sphere(s,cx,cy,cz,r)
 local g=s.grid or M.Grid(s)
 local i0,i1=clamp(floor((cx-r-g.x0)/g.cx),0,g.nx-1),clamp(floor((cx+r-g.x0)/g.cx),0,g.nx-1)
 local j0,j1=clamp(floor((cy-r-g.y0)/g.cy),0,g.ny-1),clamp(floor((cy+r-g.y0)/g.cy),0,g.ny-1)
 local k0,k1=clamp(floor((cz-r-g.z0)/g.cz),0,g.nz-1),clamp(floor((cz+r-g.z0)/g.cz),0,g.nz-1)
 local out,seen,r2=({}),{},r*r
 for k=k0,k1 do for j=j0,j1 do for i=i0,i1 do
  local cell=g.cells[(k*g.ny+j)*g.nx+i+1]
  if cell then for n=1,#cell do
   local t=cell[n]
   if not seen[t] then
    seen[t]=true
    local x,y,z=M.Centroid(s,t)
    if (x-cx)^2+(y-cy)^2+(z-cz)^2<=r2 then out[#out+1]=t end
   end
  end end
 end end end
 return out
end

-- The piece under a ray, and the triangle hit.
function M.PieceAt(s,ox,oy,oz,dx,dy,dz,limit)
 local t=M.Raycast(s,ox,oy,oz,dx,dy,dz,limit) if not t then return nil end
 if not s.island then M.Islands(s) end
 return s.islandTris[s.island[t]],t
end

function M.PartTriangles(s,p)
 local info=s.parts[p] if not info then return {} end
 local out={} for t=info.first,info.first+info.count-1 do out[#out+1]=t end
 return out
end

-- Point in a polygon (flat x1, y1, x2, y2, ...), by crossings.
local function inside(polygon,x,y)
 local n=#polygon local result=false local jx,jy=polygon[n-1],polygon[n]
 for i=1,n,2 do
  local ix,iy=polygon[i],polygon[i+1]
  if (iy>y)~=(jy>y) and x<(jx-ix)*(y-iy)/(jy-iy)+ix then result=not result end
  jx,jy=ix,iy
 end
 return result
end
M.Inside=inside

-- Triangles a region on the screen covers (a box is its four corners; a lasso its points). project(x, y, z)
-- returns the screen x, y and the depth along the view, or nil behind the camera. through: every triangle whose
-- centre falls inside; otherwise only what the camera sees there: a depth buffer over the region's box (at most
-- resolution pixels along its longer side) keeps the nearest triangle of each pixel, and a triangle counts when
-- it owns a pixel inside, or its centre lies in the region at the buffer's depth (a coincident inside layer).
function M.Region(s,polygon,project,through,resolution)
 local out={}
 if #polygon<6 then return out end
 local px0,py0,px1,py1=huge,huge,-huge,-huge
 for i=1,#polygon,2 do px0=min(px0,polygon[i]) px1=max(px1,polygon[i]) py0=min(py0,polygon[i+1]) py1=max(py1,polygon[i+1]) end
 local pos,tri=s.pos,s.tri
 local sx,sy,sz={},{},{}
 for v=1,s.nv do local i=v*3 local x,y,z=project(pos[i-2],pos[i-1],pos[i]) if x and z and z>0 then sx[v],sy[v],sz[v]=x,y,z end end
 local function centre(t)
  local o=t*3 local a,b,c=tri[o-2],tri[o-1],tri[o]
  if not (sz[a] and sz[b] and sz[c]) then return nil end
  return (sx[a]+sx[b]+sx[c])/3,(sy[a]+sy[b]+sy[c])/3,(sz[a]+sz[b]+sz[c])/3
 end
 if through then
  for t=1,s.n do
   local x,y=centre(t)
   if x and x>=px0 and x<=px1 and y>=py0 and y<=py1 and inside(polygon,x,y) then out[#out+1]=t end
  end
  return out
 end
 local w,h=px1-px0,py1-py0
 if w<1 or h<1 then return out end
 local scale=min(1,(resolution or 384)/max(w,h))
 local W,H=max(1,ceil(w*scale)),max(1,ceil(h*scale))
 local depth,owner={},{}
 for i=1,W*H do depth[i]=0 end -- 1/z: larger is nearer
 for t=1,s.n do
  local o=t*3 local a,b,c=tri[o-2],tri[o-1],tri[o]
  local az,bz,cz=sz[a],sz[b],sz[c]
  if az and bz and cz then
   local ax,ay=(sx[a]-px0)*scale,(sy[a]-py0)*scale
   local bx,by=(sx[b]-px0)*scale,(sy[b]-py0)*scale
   local qx,qy=(sx[c]-px0)*scale,(sy[c]-py0)*scale
   local x0,x1=max(0,floor(min(ax,bx,qx))),min(W-1,ceil(max(ax,bx,qx)))
   local y0,y1=max(0,floor(min(ay,by,qy))),min(H-1,ceil(max(ay,by,qy)))
   if x0<=x1 and y0<=y1 then
    local area=(bx-ax)*(qy-ay)-(by-ay)*(qx-ax)
    local ia,ib,ic=1/az,1/bz,1/cz
    local wrote=false
    if area>1e-9 or area<-1e-9 then
     for y=y0,y1 do
      local cy=y+.5
      for x=x0,x1 do
       local cx=x+.5
       local w0=((bx-cx)*(qy-cy)-(by-cy)*(qx-cx))/area
       local w1=((qx-cx)*(ay-cy)-(qy-cy)*(ax-cx))/area
       local w2=1-w0-w1
       if w0>=0 and w1>=0 and w2>=0 then
        local iz=w0*ia+w1*ib+w2*ic
        local p=y*W+x+1
        if iz>depth[p] then depth[p]=iz owner[p]=t end
        wrote=true
       end
      end
     end
    end
    if not wrote then
     -- Smaller than a pixel: its centre's pixel.
     local x,y=floor((ax+bx+qx)/3),floor((ay+by+qy)/3)
     if x>=0 and x<W and y>=0 and y<H then
      local iz=(ia+ib+ic)/3 local p=y*W+x+1
      if iz>depth[p] then depth[p]=iz owner[p]=t end
     end
    end
   end
  end
 end
 local owned={}
 for y=0,H-1 do for x=0,W-1 do
  local p=y*W+x+1 local t=owner[p]
  if t and not owned[t] and inside(polygon,px0+(x+.5)/scale,py0+(y+.5)/scale) then owned[t]=true end
 end end
 for t=1,s.n do
  if owned[t] then out[#out+1]=t
  else
   local x,y,z=centre(t)
   if x and x>=px0 and x<=px1 and y>=py0 and y<=py1 and inside(polygon,x,y) then
    local bx,by=min(W-1,max(0,floor((x-px0)*scale))),min(H-1,max(0,floor((y-py0)*scale)))
    local near=depth[by*W+bx+1]
    -- At the buffer's depth, to half a percent or a hundredth of a unit: a layer on the visible one.
    if near==0 or z<=(1/near)*1.005+.01 then out[#out+1]=t end
   end
  end
 end
 return out
end

-- The selection.
function M.Add(s,list)
 local sel,n=s.selected,s.count
 for i=1,#list do local t=list[i] if not sel[t] then sel[t]=true n=n+1 end end
 if n~=s.count then s.count=n s.revision=s.revision+1 end
end
function M.Remove(s,list)
 local sel,n=s.selected,s.count
 for i=1,#list do local t=list[i] if sel[t] then sel[t]=nil n=n-1 end end
 if n~=s.count then s.count=n s.revision=s.revision+1 end
end
function M.Clear(s) if s.count>0 then s.selected={} s.count=0 s.revision=s.revision+1 end end
function M.List(s)
 local out={} for t in pairs(s.selected) do out[#out+1]=t end
 table.sort(out) return out
end
-- Selected triangles per part.
function M.PartCounts(s)
 local counts={} for t in pairs(s.selected) do local p=s.part[t] counts[p]=(counts[p] or 0)+1 end
 return counts
end
-- Carries a selection to a new snapshot of the same model (the same parts, so the same triangle numbers).
function M.Adopt(s,old)
 if not old or old.n~=s.n or #old.parts~=#s.parts then return false end
 for p,info in ipairs(s.parts) do local o=old.parts[p] if o.first~=info.first or o.count~=info.count or o.key~=info.key then return false end end
 s.selected,s.count,s.revision=old.selected,old.count,old.revision+1
 if old.island then s.island,s.islandTris,s.islands=old.island,old.islandTris,old.islands end
 return true
end

if mmdhl and mmdhl.separator then mmdhl.separator.Mesh=M end
return M
