-- The Mesh Separator's editor (ADR 0232): the model the tool works on, in the pose it was read in, alone in a 3D
-- view that turns (right drag), pans (middle drag) and zooms (wheel). Left click or drag adds with the chosen way
-- (a piece, a whole part, the brush, a box, a lasso; boxes and lassos through the model or only what is seen);
-- right click, or Ctrl with the left button, takes away. The parts list ticks whole parts; the piece's name,
-- shape (current or rest pose) and physics; Detach. The model is drawn with UnlitGeneric vgui/ materials, which
-- RTX Remix draws as interface rather than in the scene (as the Hotloader's own previews are).
local S=mmdhl.separator
local M=S.Mesh
local L=mmdhl.L
local base=CreateMaterial('mmdhl_separator_preview_v1','UnlitGeneric',{['$basetexture']='vgui/white',['$vertexcolor']='1',['$nocull']='1'})
local palette={Color(196,205,214),Color(214,196,184),Color(186,206,190),Color(206,190,214),Color(214,210,178),Color(178,204,214),Color(214,184,198),Color(194,194,174)}
local light=Vector(.35,-.45,.82) light:Normalize()
local function setting(name,fallback) local c=GetConVar('mmdhl_separator_'..name) return c and c:GetString() or fallback end
-- The model's triangles, flat shaded in its part's colour, built a chunk at a time (about 4 ms a frame).
local function startBuild(view,s)
 for _,m in ipairs(view.meshes or {}) do mmdhl.props.RetireMesh(m) end
 view.meshes={} view.build={s=s,next=1}
end
local function buildStep(view)
 local job=view.build if not job then return end
 local s=job.s local pos,tri=s.pos,s.tri
 local deadline=SysTime()+.004
 while job.next<=s.n and SysTime()<deadline do
  local last=math.min(s.n,job.next+5999)
  local verts={}
  for t=job.next,last do
   local o=t*3 local a,b,c=tri[o-2]*3,tri[o-1]*3,tri[o]*3
   local ax,ay,az=pos[a-2],pos[a-1],pos[a]
   local e1=Vector(pos[b-2]-ax,pos[b-1]-ay,pos[b]-az) local e2=Vector(pos[c-2]-ax,pos[c-1]-ay,pos[c]-az)
   local n=e1:Cross(e2) n:Normalize()
   local shade=.38+.62*math.abs(n:Dot(light))
   local pc=palette[(s.part[t]-1)%#palette+1]
   local color=Color(pc.r*shade,pc.g*shade,pc.b*shade,255)
   verts[#verts+1]={pos=Vector(ax,ay,az),color=color}
   verts[#verts+1]={pos=Vector(pos[b-2],pos[b-1],pos[b]),color=color}
   verts[#verts+1]={pos=Vector(pos[c-2],pos[c-1],pos[c]),color=color}
  end
  local m=Mesh(base) m:BuildFromTriangles(verts) view.meshes[#view.meshes+1]=m
  job.next=last+1
 end
 if job.next>s.n then view.build=nil end
end

function S.OpenEditor()
 local target=S.target
 if not target or not IsValid(target.ent) then notification.AddLegacy(L'separator.error.no_target',NOTIFY_ERROR,5) return end
 if IsValid(S.editor) then S.editor:Close() end
 local UI=mmdhl.UI local s,f=UI.metrics()
 local frame=vgui.Create('DFrame') S.editor=frame
 frame:SetTitle('') frame:SetSize(math.min(ScrW()-s(60),s(1240)),math.min(ScrH()-s(60),s(780))) frame:Center() frame:MakePopup()
 frame:DockPadding(s(12),s(10),s(12),s(12)) frame.btnMinim:SetVisible(false) frame.btnMaxim:SetVisible(false)
 frame.Paint=function(_,w,h) draw.RoundedBox(6,0,0,w,h,Color(246,248,251,250)) end
 local title=UI.label(frame,L'separator.editor.title',f.Title,s(34)) title:Dock(TOP)
 -- The side: settings that scroll, above a footer (the status, Clear and Detach) that is always in view.
 local column=frame:Add('DPanel') column:Dock(RIGHT) column:SetWide(s(330)) column:DockMargin(s(10),0,0,0) column:SetPaintBackground(false)
 local foot=column:Add('DPanel') foot:Dock(BOTTOM) foot:SetTall(s(88)) foot:SetPaintBackground(false)
 local side=column:Add('DScrollPanel') side:Dock(FILL)
 local view=frame:Add('DPanel') view:Dock(FILL)
 view.tool='piece' view.through=false

 -- The camera: around the model's centre, from where the player looks.
 local snapRef=target.snap
 local mins,maxs=M.Bounds(snapRef)
 local centre=Vector((mins[1]+maxs[1])/2,(mins[2]+maxs[2])/2,(mins[3]+maxs[3])/2)
 local radius=math.max(Vector(maxs[1]-mins[1],maxs[2]-mins[2],maxs[3]-mins[3]):Length()/2,4)
 local orbit={centre=centre,yaw=LocalPlayer():EyeAngles().y,pitch=10,fov=45,dist=radius/math.sin(math.rad(22.5))*1.05}
 local function camera()
  local ang=Angle(orbit.pitch,orbit.yaw,0)
  return orbit.centre-ang:Forward()*orbit.dist,ang
 end
 -- Rays and the projection in the view's own coordinates, from util.AimVector's pixel rays: Vector:ToScreen is
 -- inaccurate inside a cam.Start3D viewport of a panel (the Advanced Bodygroup Tool's cut editor inverts
 -- util.AimVector the same way).
 local function project(x,y,z)
  local p=view.proj if not p then return nil end
  local dx,dy,dz=x-p.pos.x,y-p.pos.y,z-p.pos.z
  local depth=dx*p.f.x+dy*p.f.y+dz*p.f.z
  if depth<=.01 then return nil end
  return p.hw+(dx*p.r.x+dy*p.r.y+dz*p.r.z)/depth/p.rpp,p.hh+(dx*p.u.x+dy*p.u.y+dz*p.u.z)/depth/p.upp,depth
 end
 local function ray(lx,ly)
  local p=view.proj if not p then return nil end
  return p.pos,util.AimVector(p.ang,p.fov,lx,ly,p.w,p.h)
 end
 -- Diagnostics and tests reach the view's projection and camera through the frame (frame.View.Project, .Ray, .Orbit).
 view.Project,view.Ray,view.Orbit=project,ray,orbit frame.View=view
 local function current() local t=S.target if t and IsValid(t.ent) then return t.snap end end
 local function apply(list,add)
  local snap=current() if not snap or not list then return end
  if add then M.Add(snap,list) else M.Remove(snap,list) end
  hook.Run('MMDHL.SeparatorChanged')
 end
 local function pickAt(mx,my,add,part)
  local snap=current() local o,d=ray(mx,my) if not snap or not o then return end
  local list
  if part then local t=M.Raycast(snap,o.x,o.y,o.z,d.x,d.y,d.z) list=t and M.PartTriangles(snap,snap.part[t])
  else list=M.PieceAt(snap,o.x,o.y,o.z,d.x,d.y,d.z) end
  apply(list,add)
 end
 local function brushAt(mx,my,add)
  local snap=current() local o,d=ray(mx,my) if not snap or not o then return end
  local t,_,x,y,z=M.Raycast(snap,o.x,o.y,o.z,d.x,d.y,d.z)
  if t then apply(M.Sphere(snap,x,y,z,math.Clamp(tonumber(setting('brush','4')) or 4,.25,64)),add) end
 end
 local selection={meshes={}}
 local hoverState={meshes={}}
 view.Paint=function(self,w,h)
  draw.RoundedBox(4,0,0,w,h,Color(42,47,56))
  local snap=current()
  if not snap then draw.SimpleText(L'separator.error.no_target','DermaDefault',w/2,h/2,color_white,1,1) return end
  if snap~=self.built then self.built=snap startBuild(self,snap) end
  buildStep(self)
  local x,y=self:LocalToScreen(0,0)
  local pos,ang=camera()
  local f,r,u=ang:Forward(),ang:Right(),ang:Up()
  local hw,hh=w*.5,h*.5
  local right,down=util.AimVector(ang,orbit.fov,hw+1,hh,w,h),util.AimVector(ang,orbit.fov,hw,hh+1,w,h)
  local rd,dd=right:Dot(f),down:Dot(f)
  local rpp,upp=math.abs(rd)>1e-7 and right:Dot(r)/rd or 0,math.abs(dd)>1e-7 and down:Dot(u)/dd or 0
  if math.abs(rpp)>1e-9 and math.abs(upp)>1e-9 then self.proj={pos=pos,ang=ang,fov=orbit.fov,w=w,h=h,hw=hw,hh=hh,f=f,r=r,u=u,rpp=rpp,upp=upp} end
  cam.Start3D(pos,ang,orbit.fov,x,y,w,h,1,orbit.dist+radius*4)
   render.ClearDepth()
   render.SuppressEngineLighting(true)
   render.SetMaterial(base) for _,m in ipairs(self.meshes or {}) do m:Draw() end
   if selection.snap~=snap or selection.revision~=snap.revision then
    for _,m in ipairs(selection.meshes) do mmdhl.props.RetireMesh(m) end
    selection={snap=snap,revision=snap.revision,meshes=S.BuildMeshes(snap,M.List(snap),Color(255,140,30,200))}
   end
   render.SetMaterial(S.HighlightMaterial)
   render.DepthRange(0,.9995)
   for _,m in ipairs(selection.meshes) do m:Draw() end
   local hov=self.hover
   if hov then
    if hoverState.snap~=snap or hoverState.key~=hov.key then
     for _,m in ipairs(hoverState.meshes) do mmdhl.props.RetireMesh(m) end
     local list=hov.list()
     hoverState={snap=snap,key=hov.key,meshes=list and #list<=60000 and S.BuildMeshes(snap,list,Color(90,200,255,110)) or {}}
    end
    for _,m in ipairs(hoverState.meshes) do m:Draw() end
   end
   render.DepthRange(0,1)
   render.SuppressEngineLighting(false)
  cam.End3D()
  -- The region being drawn, the brush, and how to use the view.
  local region=self.region
  if region and #region.points>=2 then
   surface.SetDrawColor(255,190,90,255)
   local pts=region.points
   if region.box then
    local ax,ay,bx,by=pts[1],pts[2],pts[3],pts[4]
    surface.DrawOutlinedRect(math.min(ax,bx),math.min(ay,by),math.abs(bx-ax),math.abs(by-ay),2)
   else
    for i=1,#pts-3,2 do surface.DrawLine(pts[i],pts[i+1],pts[i+2],pts[i+3]) end
    surface.DrawLine(pts[#pts-1],pts[#pts],pts[1],pts[2])
   end
  end
  if self.build then draw.SimpleText(L('separator.editor.building',{percent=math.floor(((self.build.next-1)/math.max(1,snap.n))*100)}),'DermaDefault',s(10),s(10),Color(220,230,240)) end
  draw.SimpleText(L'separator.editor.hint','DermaDefault',s(10),h-s(10),Color(200,210,222),0,4)
 end
 -- Mouse: left adds (Ctrl takes away), right takes away or turns the view when dragged, middle pans, wheel zooms.
 local function remove() return input.IsKeyDown(KEY_LCONTROL) or input.IsKeyDown(KEY_RCONTROL) end
 view.OnMousePressed=function(self,code)
  self:MouseCapture(true)
  local mx,my=self:CursorPos()
  self.press={code=code,x=mx,y=my,moved=false,add=code==MOUSE_LEFT and not remove()}
  if code==MOUSE_LEFT then
   if self.tool=='box' then self.region={box=true,points={mx,my,mx,my}}
   elseif self.tool=='lasso' then self.region={points={mx,my}}
   elseif self.tool=='brush' then brushAt(mx,my,self.press.add) self.nextBrush=RealTime()+1/30 end
  end
 end
 view.OnCursorMoved=function(self)
  local mx,my=self:CursorPos()
  local p=self.press
  if p then
   local dx,dy=mx-(p.lx or p.x),my-(p.ly or p.y)
   if math.abs(mx-p.x)+math.abs(my-p.y)>4 then p.moved=true end
   if p.code==MOUSE_RIGHT and p.moved then orbit.yaw=orbit.yaw-dx*.4 orbit.pitch=math.Clamp(orbit.pitch+dy*.4,-89,89)
   elseif p.code==MOUSE_MIDDLE then
    local _,ang=camera() local k=orbit.dist*.0016
    orbit.centre=orbit.centre-ang:Right()*dx*k+ang:Up()*dy*k
   elseif p.code==MOUSE_LEFT then
    local region=self.region
    if region and region.box then region.points[3],region.points[4]=mx,my
    elseif region then local pts=region.points if math.abs(mx-pts[#pts-1])+math.abs(my-pts[#pts])>=3 then pts[#pts+1]=mx pts[#pts+1]=my end
    elseif self.tool=='brush' and (self.nextBrush or 0)<=RealTime() then brushAt(mx,my,p.add) self.nextBrush=RealTime()+1/30 end
   end
   p.lx,p.ly=mx,my
  end
 end
 view.OnMouseReleased=function(self,code)
  self:MouseCapture(false)
  local p=self.press self.press=nil
  if not p or p.code~=code then self.region=nil return end
  local mx,my=self:CursorPos()
  if code==MOUSE_LEFT then
   local region=self.region self.region=nil
   if region then
    local polygon=region.points
    if region.box then local ax,ay,bx,by=polygon[1],polygon[2],polygon[3],polygon[4] polygon={ax,ay,bx,ay,bx,by,ax,by} end
    local snap=current()
    if snap and #polygon>=6 then apply(M.Region(snap,polygon,project,self.through,384),p.add) end
   elseif self.tool=='piece' or self.tool=='part' then pickAt(mx,my,p.add,self.tool=='part') end
  elseif code==MOUSE_RIGHT and not p.moved then
   if self.tool=='brush' then brushAt(mx,my,false) else pickAt(mx,my,false,self.tool=='part') end
  end
 end
 view.OnMouseWheeled=function(_,delta) orbit.dist=math.Clamp(orbit.dist*(.9^delta),radius*.05,radius*40) return true end
 view.Think=function(self)
  -- The piece or part under the cursor, for the piece and part tools.
  if (self.nextHover or 0)>RealTime() then return end self.nextHover=RealTime()+.05
  self.hover=nil
  if self.press or (self.tool~='piece' and self.tool~='part') or not self:IsHovered() then return end
  local snap=current() local mx,my=self:CursorPos() local o,d=ray(mx,my)
  if not snap or not o then return end
  local t=M.Raycast(snap,o.x,o.y,o.z,d.x,d.y,d.z)
  if not t then return end
  if self.tool=='part' then local part=snap.part[t] self.hover={key='part'..part,list=function() return M.PartTriangles(snap,part) end}
  else
   if not snap.island then M.Islands(snap) end
   local i=snap.island[t] self.hover={key='piece'..i,list=function() return snap.islandTris[i] end}
  end
 end

 -- The side: the way to select, the parts, the piece, Detach.
 local function heading(text) local l=UI.label(side,text,f.Strong,s(26)) l:Dock(TOP) l:DockMargin(0,s(8),0,s(2)) return l end
 local name=UI.label(side,'',f.Small,s(22)) name:Dock(TOP) name:SetTextColor(UI.colors.muted)
 heading(L'separator.editor.select_with')
 local tools=side:Add('DPanel') tools:Dock(TOP) tools:SetTall(s(66)) tools:SetPaintBackground(false)
 local buttons={}
 local function choose(tool) view.tool=tool for id,b in pairs(buttons) do b.Selected=id==tool end end
 local labels={piece=L'separator.editor.tool_piece',part=L'separator.editor.tool_part',brush=L'separator.editor.tool_brush',box=L'separator.editor.tool_box',lasso=L'separator.editor.tool_lasso'}
 for _,t in ipairs({'piece','part','brush','box','lasso'}) do buttons[t]=UI.button(tools,labels[t],function() choose(t) end,s(30),f.Body) end
 tools.PerformLayout=function(_,w)
  local order={'piece','part','brush','box','lasso'} local third=math.floor((w-s(12))/3)
  for i,t in ipairs(order) do local row,col=math.floor((i-1)/3),(i-1)%3 buttons[t]:SetPos(col*(third+s(6)),row*s(36)) buttons[t]:SetSize(third,s(30)) end
 end
 choose(setting('mode','piece')=='brush' and 'brush' or setting('mode','piece')=='part' and 'part' or 'piece')
 local through=UI.checkbox(side,L'separator.editor.through',nil,f.Body,s(26)) through:Dock(TOP)
 through.OnChange=function(_,v) view.through=v==true end
 local brush=side:Add('DNumSlider') brush:Dock(TOP) brush:SetTall(s(30)) brush:SetText(L'tool.separator.brush_size') brush:SetMinMax(.25,32) brush:SetDecimals(2) brush:SetConVar('mmdhl_separator_brush') brush:SetDark(true) brush.Label:SetFont(f.Body)
 heading(L'separator.editor.parts')
 local partsBox=side:Add('DPanel') partsBox:Dock(TOP) partsBox:SetTall(s(220)) partsBox:SetPaintBackground(false)
 local list=partsBox:Add('DScrollPanel') list:Dock(FILL)
 local rows={}
 local function fillParts()
  list:Clear() rows={}
  local snap=current() if not snap then return end
  for p,info in ipairs(snap.parts) do
   local row=list:Add('DCheckBoxLabel') row:Dock(TOP) row:DockMargin(0,0,0,s(3)) row:SetTextColor(UI.colors.ink) row.Label:SetFont(f.Small)
   row.OnChange=function(_,v) apply(M.PartTriangles(snap,p),v==true) end
   rows[p]={row=row,info=info}
  end
 end
 local function refreshParts()
  local snap=current() if not snap then return end
  if rows.snap~=snap then fillParts() rows.snap=snap end
  local counts=M.PartCounts(snap)
  for p,r in pairs(rows) do if istable(r) and r.row then
   local n=counts[p] or 0
   r.row:SetText(string.format('%s  (%s/%s)',r.info.name~='' and r.info.name or '#'..p,string.Comma(n),string.Comma(r.info.count)))
   r.row.Button:SetChecked(n==r.info.count and n>0)
  end end
 end
 heading(L'separator.editor.piece')
 local entry=side:Add('DTextEntry') entry:Dock(TOP) entry:SetTall(s(30)) entry:SetFont(f.Body) entry:SetConVar('mmdhl_separator_name') entry:SetUpdateOnType(true)
 local function combo(label,cvar,options)
  local l=UI.label(side,label,f.Small,s(20)) l:Dock(TOP) l:DockMargin(0,s(4),0,0)
  local box=side:Add('DComboBox') box:Dock(TOP) box:SetTall(s(28)) box:SetFont(f.Body)
  local value=setting(cvar,options[1][2])
  for _,o in ipairs(options) do box:AddChoice(o[1],o[2],value==o[2]) end
  box.OnSelect=function(_,_,_,data) RunConsoleCommand('mmdhl_separator_'..cvar,data) end
  return box
 end
 combo(L'tool.separator.pose','pose',{{L'tool.separator.pose_current','current'},{L'tool.separator.pose_rest','rest'}})
 combo(L'tool.separator.physics','collision',{{L'tool.separator.physics_auto','auto'},{L'tool.separator.physics_hull','hull'},{L'tool.separator.physics_detailed','balanced'}})
 local freeze=UI.checkbox(side,L'tool.separator.freeze','mmdhl_separator_freeze',f.Body,s(26)) freeze:Dock(TOP) freeze:DockMargin(0,s(6),0,0)
 local place=UI.checkbox(side,L'tool.separator.place','mmdhl_separator_place',f.Body,s(26)) place:Dock(TOP)
 local status=UI.label(foot,'',f.Small,s(40)) status:Dock(TOP) status:SetWrap(true) status:DockMargin(0,s(4),0,0)
 local row=foot:Add('DPanel') row:Dock(BOTTOM) row:SetTall(s(36)) row:SetPaintBackground(false)
 local clear=UI.button(row,L'tool.separator.clear',function() S.Clear() end,s(34),f.Body)
 local detach=UI.button(row,L'tool.separator.detach',function()
  local ok,err=S.Detach({name=entry:GetValue(),pose=setting('pose','current'),collision=setting('collision','auto'),frozen=setting('freeze','1')~='0',place=setting('place','1')~='0'})
  if not ok then notification.AddLegacy(tostring(err),NOTIFY_ERROR,6) status:SetText(tostring(err)) end
 end,s(34),f.Strong,true)
 row.PerformLayout=function(_,w,h) local third=math.floor(w/3) clear:SetPos(0,0) clear:SetSize(third-s(6),h) detach:SetPos(third,0) detach:SetSize(w-third,h) end
 local function update()
  if not IsValid(frame) then return end
  local t=S.target
  if not t or not IsValid(t.ent) then name:SetText(L'tool.separator.no_model') status:SetText('') return end
  local snap=t.snap
  name:SetText(S.DefaultName(t))
  entry:SetPlaceholderText(S.DefaultName(t))
  refreshParts()
  local library=mmdhl.library
  if S.pending and library.job then status:SetText((library.status or '')..(library.progress and ('  '..math.floor(library.progress*100)..'%') or ''))
  else status:SetText(L('tool.separator.selected',{count=string.Comma(snap.count),total=string.Comma(snap.n)})) end
  detach:SetEnabled(snap.count>0 and not library.job)
 end
 hook.Add('MMDHL.SeparatorChanged',frame,update)
 hook.Add('MMDHL.ImportChanged',frame,update)
 update()
 frame.OnRemove=function()
  for _,m in ipairs(view.meshes or {}) do mmdhl.props.RetireMesh(m) end
  for _,m in ipairs(selection.meshes) do mmdhl.props.RetireMesh(m) end
  for _,m in ipairs(hoverState.meshes) do mmdhl.props.RetireMesh(m) end
  if S.editor==frame then S.editor=nil end
 end
 UI.ownScale(frame)
 return frame
end
concommand.Add('mmdhl_separator_editor',function() S.OpenEditor() end)
