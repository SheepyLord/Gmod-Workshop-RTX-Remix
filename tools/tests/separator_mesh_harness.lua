-- LuaJIT harness for the Mesh Separator's selection engine (packages/model-hotloader/mmd_hotloader/lua/mmdhl/
-- separator/mesh.lua, ADR 0232). Usage: luajit separator_mesh_harness.lua <repository> <scenario>
-- Prints "PASS <scenario>" and exits 0, or prints the failed check and exits 1.
local repo,scenario=arg[1],arg[2]
local M=dofile(repo..'/packages/model-hotloader/mmd_hotloader/lua/mmdhl/separator/mesh.lua')
local function check(ok,why) if not ok then io.stderr:write('FAIL '..scenario..': '..why..'\n') os.exit(1) end end

-- A model under construction: boxes and sheets, outward counter-clockwise, with parts.
local function builder()
 local b={pos={},tri={},parts={}}
 function b.vertex(x,y,z) local p=b.pos p[#p+1]=x p[#p+1]=y p[#p+1]=z return #p/3 end
 function b.face(a,c,d) local t=b.tri t[#t+1]=a t[#t+1]=c t[#t+1]=d end
 function b.part(name) b.parts[#b.parts+1]={name=name,first=#b.tri/3+1,count=0} end
 function b.close() local p=b.parts[#b.parts] p.count=#b.tri/3-p.first+1 end
 -- An axis-aligned box: 8 corners, 12 triangles.
 function b.box(x0,y0,z0,x1,y1,z1)
  local v={} for i=0,7 do v[i]=b.vertex(i%2==1 and x1 or x0,math.floor(i/2)%2==1 and y1 or y0,math.floor(i/4)==1 and z1 or z0) end
  for _,f in ipairs({{0,2,1},{1,2,3},{4,5,6},{5,7,6},{0,1,4},{1,5,4},{2,6,3},{3,6,7},{0,4,2},{2,4,6},{1,3,5},{3,7,5}}) do b.face(v[f[1]],v[f[2]],v[f[3]]) end
 end
 -- A square at height z split in two triangles; flipped, its back-face copy (its own corners, the same places).
 function b.sheet(x0,y0,x1,y1,z,flipped)
  local a,c,d,e=b.vertex(x0,y0,z),b.vertex(x1,y0,z),b.vertex(x1,y1,z),b.vertex(x0,y1,z)
  if flipped then b.face(a,d,c) b.face(a,e,d) else b.face(a,c,d) b.face(a,d,e) end
 end
 function b.build() return M.New(b.pos,b.tri,b.parts) end
 return b
end
local function set(list) local out={} for _,t in ipairs(list) do out[t]=true end return out end
local function count(list) return #list end

-- An orthographic camera looking down -Z from above: screen x, y are world x, -y, depth is 100 - z.
local function topDown(x,y,z) return x,-y,100-z end

local scenarios={}

scenarios.islands=function()
 -- Box A (part 1) and box B (part 2), apart; box A's top split along a texture seam (its own corners at the
 -- same places) in part 3; a sheet and its back-face copy (parts 4 and 5).
 local b=builder()
 b.part('a') b.box(0,0,0,1,1,1) b.close()
 b.part('b') b.box(5,0,0,6,1,1) b.close()
 b.part('seam') b.sheet(0,0,1,1,1,false) b.close()
 b.part('sheet') b.sheet(10,10,12,12,0,false) b.close()
 b.part('copy') b.sheet(10,10,12,12,0,true) b.close()
 local s=b.build()
 check(s.n==12+12+2+2+2,'triangle count '..s.n)
 local n=M.Islands(s)
 check(n==3,'three pieces, not '..n)
 check(s.island[1]==s.island[25],'a seam copy stays with its box')
 check(s.island[1]~=s.island[13],'two boxes apart are two pieces')
 check(s.island[27]==s.island[29],'a back-face copy stays with its layer')
 check(#s.islandTris[s.island[1]]==14,'box A with its seam copy has 14 triangles')
 check(s.part[13]==2 and s.part[29]==5,'parts by triangle')
end

scenarios.raycast=function()
 local b=builder()
 b.part('near') b.box(0,0,0,1,1,1) b.close()
 b.part('far') b.box(0,0,-5,1,1,-4) b.close()
 local s=b.build()
 -- Straight down onto the near box's top (z=1).
 local t,dist,x,y,z=M.Raycast(s,.5,.5,10,0,0,-1)
 check(t and s.part[t]==1,'the near box is hit first')
 check(math.abs(dist-9)<1e-6 and math.abs(z-1)<1e-6,'the hit is on its top face: '..tostring(dist))
 -- Beside both boxes: nothing.
 check(M.Raycast(s,3,3,10,0,0,-1)==nil,'a miss is nil')
 -- From inside the grid, upwards from between the boxes: the near box's bottom (z=0).
 local u,d2=M.Raycast(s,.5,.5,-2,0,0,1)
 check(u and s.part[u]==1 and math.abs(d2-2)<1e-6,'a ray from inside the grid')
 -- Downwards from between the boxes: the far box's top (z=-4).
 local w,d3=M.Raycast(s,.5,.5,-2,0,0,-1)
 check(w and s.part[w]==2 and math.abs(d3-2)<1e-6,'the far box below')
 -- A limit shorter than the distance.
 check(M.Raycast(s,.5,.5,10,0,0,-1,5)==nil,'a limit stops the ray')
 -- A slanted ray through several cells.
 local sl=M.Raycast(s,-3,.5,4,1,0,-1)
 check(sl and s.part[sl]==1,'a slanted ray hits the near box')
 local piece,hitT=M.PieceAt(s,.5,.5,10,0,0,-1)
 check(piece and #piece==12 and set(piece)[hitT],'the piece under the ray is the whole box')
end

scenarios.brush=function()
 local b=builder()
 b.part('grid')
 for i=0,9 do for j=0,9 do b.sheet(i,j,i+1,j+1,0,false) end end
 b.close()
 local s=b.build()
 check(s.n==200,'200 triangles')
 local list=M.Sphere(s,5,5,0,1.01)
 -- Centres within 1.01 of (5, 5): the two triangles of each of the four squares around the point, and the
 -- nearer triangle of each of the four squares beside them.
 check(#list>=8 and #list<=16,'a brush of radius 1 takes the triangles around the point: '..#list)
 for _,t in ipairs(list) do local x,y,z=M.Centroid(s,t) check((x-5)^2+(y-5)^2<=1.01^2+1e-9,'every triangle within the radius') end
 check(#M.Sphere(s,50,50,0,1)==0,'a brush beside the model takes nothing')
end

scenarios.region=function()
 -- From above: box A at x 0..1, box B at x 3..4, and box C under A (hidden from above).
 local b=builder()
 b.part('a') b.box(0,0,0,1,1,1) b.close()
 b.part('b') b.box(3,0,0,4,1,1) b.close()
 b.part('c') b.box(0,0,-3,1,1,-2) b.close()
 b.part('inner') b.sheet(0,0,1,1,1,true) b.close()
 local s=b.build()
 -- A box on the screen around A only (screen y is -world y).
 local polygon={-.5,-1.5,1.5,-1.5,1.5,.5,-.5,.5}
 local through=M.Region(s,polygon,topDown,true)
 local parts={} for _,t in ipairs(through) do parts[s.part[t]]=(parts[s.part[t]] or 0)+1 end
 check(parts[1]==12 and parts[3]==12 and not parts[2],'through the model: A and the box under it, not B')
 check(parts[4]==2,'through the model: the inside layer too')
 local visible=M.Region(s,polygon,topDown,false,128)
 parts={} for _,t in ipairs(visible) do parts[s.part[t]]=(parts[s.part[t]] or 0)+1 end
 check(parts[1] and parts[1]>=2,'visible only: A\'s top')
 check(not parts[3],'visible only: not the box under A')
 check(not parts[2],'visible only: not B outside the region')
 check(parts[4]==2,'visible only: the layer on A\'s top (a back-face copy) comes with it')
 -- A lasso (a triangle on the screen) around B only.
 local lasso={2.5,-1.5,5,-1.5,3.5,1}
 local onB=M.Region(s,lasso,topDown,true)
 for _,t in ipairs(onB) do check(s.part[t]==2,'the lasso takes only B') end
 check(#onB>0,'the lasso takes B\'s triangles')
 check(M.Inside({0,0,10,0,10,10,0,10},5,5) and not M.Inside({0,0,10,0,10,10,0,10},15,5),'point in polygon')
end

scenarios.selection=function()
 local b=builder()
 b.part('a') b.box(0,0,0,1,1,1) b.close()
 b.part('b') b.box(3,0,0,4,1,1) b.close()
 local s=b.build()
 local r0=s.revision
 M.Add(s,M.PartTriangles(s,1))
 check(s.count==12 and s.revision==r0+1,'add a part')
 M.Add(s,{1,2,13})
 check(s.count==13,'adding again counts once')
 M.Remove(s,{13,14})
 check(s.count==12,'remove')
 local counts=M.PartCounts(s)
 check(counts[1]==12 and counts[2]==nil,'counts per part')
 local list=M.List(s)
 check(#list==12 and list[1]==1 and list[12]==12,'the sorted list')
 local again=b.build()
 check(M.Adopt(again,s) and again.count==12,'a new snapshot of the same parts keeps the selection')
 local other=builder() other.part('a') other.box(0,0,0,1,1,1) other.close()
 check(not M.Adopt(other.build(),s),'another model does not')
 M.Clear(s)
 check(s.count==0 and next(s.selected)==nil,'clear')
end

local run=scenarios[scenario]
check(run~=nil,'unknown scenario')
run()
print('PASS '..scenario)
