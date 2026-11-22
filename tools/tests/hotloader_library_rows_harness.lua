-- ADR 0258: the Model Hotloader's library window adds rows for the entries library.Add listed instead of building its
-- whole list again. The shipped library.lua and ui.lua are loaded whole in the client realm, with the disk, the native
-- module and Derma instrumented: a stand-in DListView keeps GMod's lines (Lines in creation order, Sorted in display
-- order, AddLine appends to both). Each check compares a window that took additions as rows with a window built afresh
-- on the same library and in the same view: every row in order (asset, columns, tooltip, badge, fonts, GUI Scaler's
-- mark), the selection, the count line, the details and the folder tree. One scenario per run; prints PASS <scenario>.
local source,scenario=unpack(arg)
SERVER,CLIENT=false,true
local function noop() end
local function eq(a,b,why) if a~=b then error((why or '')..': '..tostring(a)..' ~= '..tostring(b),2) end end
function istable(v) return type(v)=='table' end
function isstring(v) return type(v)=='string' end
function isnumber(v) return type(v)=='number' end
function isbool(v) return type(v)=='boolean' end
function isfunction(v) return type(v)=='function' end
function Color(r,g,b,a) return {r=r,g=g,b=b,a=a or 255} end
color_white=Color(255,255,255)
function ErrorNoHalt(text) error(text) end
function MsgN() end
function string.Trim(s) return (tostring(s):gsub('^%s+',''):gsub('%s+$','')) end
function string.Comma(n)
 local s=tostring(math.floor(tonumber(n) or 0))
 local out=s:reverse():gsub('(%d%d%d)','%1,'):reverse()
 return (out:gsub('^,',''))
end
function string.GetFileFromFilename(p) return p:match('[^/\\]+$') or p end
function string.GetPathFromFilename(p) return p:match('^(.*[/\\])') or '' end
function table.Copy(value)
 if not istable(value) then return value end
 local copy={} for k,v in pairs(value) do copy[k]=table.Copy(v) end return copy
end
function table.GetKeys(t) local out={} for k in pairs(t) do out[#out+1]=k end return out end
function table.Count(t) local n=0 for _ in pairs(t) do n=n+1 end return n end
function math.Clamp(v,lo,hi) return math.min(math.max(v,lo),hi) end
function math.Round(v,d) local m=10^(d or 0) return math.floor(v*m+.5)/m end
utf8={len=function(s) return #s end,sub=function(s,i,j) return s:sub(i,j) end}
function RealTime() return 1000 end function CurTime() return 1000 end function SysTime() return 1000 end
function FrameNumber() return 1 end
function ScrW() return 1920 end function ScrH() return 1080 end
FILL,LEFT,RIGHT,TOP,BOTTOM=1,2,3,4,5
TEXT_ALIGN_CENTER,TEXT_ALIGN_LEFT,MOUSE_RIGHT,MOUSE_LEFT,FCVAR_ARCHIVE=1,0,108,107,128
function Vector(x,y,z) return {x=x or 0,y=y or 0,z=z or 0} end
function Angle(p,y,r) return {p=p or 0,y=y or 0,r=r or 0} end
bit={bor=function() return 0 end}
local hooks,timers={}, {}
hook={Add=function(event,key,fn) hooks[event]=hooks[event] or {} hooks[event][key]=fn end,
 Run=function(event,...) for _,fn in pairs(hooks[event] or {}) do fn(...) end end,Remove=noop}
timer={Simple=function(_,fn) timers[#timers+1]=fn end,Create=noop,Remove=noop,Exists=function() return false end}
local function cvar(value) return {GetBool=function() return value~=0 end,GetInt=function() return tonumber(value) or 0 end,
 GetFloat=function() return tonumber(value) or 0 end,GetString=function() return tostring(value) end} end
local guiScaler=false
function CreateClientConVar(_,value) return cvar(tonumber(value) or 0) end
function CreateConVar(_,value) return cvar(tonumber(value) or 0) end
function GetConVar(name)
 if name=='guiscaler_scale_multiplier' then return guiScaler and cvar(1) or nil end
 if name=='nativeloader_imported_model_normals' then return nil end
 return cvar(0)
end
cvars={AddChangeCallback=noop}
RunConsoleCommand=noop
-- The disk: manifests and settings as tables (util.JSONToTable hands out copies).
local disk={}
file={Read=function(p) return disk[p] end,Exists=function(p) return disk[p]~=nil end,
 Write=function(p,v) disk[p]=v end,CreateDir=noop,Delete=function(p) disk[p]=nil end,
 Time=function(p) return disk[p]~=nil and 1 or 0 end,Size=function(p) return disk[p]~=nil and 100 or -1 end,
 Find=function(pattern)
  local dirs,seen={},{}
  if pattern=='mmd_hotloader/assets/*' then
   for p in pairs(disk) do local id=p:match('^mmd_hotloader/assets/(%x+)/') if id and not seen[id] then seen[id]=true dirs[#dirs+1]=id end end
  end
  table.sort(dirs) return {},dirs
 end}
util={JSONToTable=function(v) if not istable(v) then return nil end return table.Copy(v) end,
 TableToJSON=function(v) return table.Copy(v) end,AddNetworkString=noop}
game={SinglePlayer=function() return true end,IsDedicated=function() return false end}
net={Receive=noop,Start=noop,WriteString=noop,WriteUInt=noop,WriteBool=noop,SendToServer=noop,
 ReadString=function() return '' end,ReadUInt=function() return 0 end,ReadBool=function() return false end}
function LocalPlayer() return nil end
notification={AddLegacy=noop,AddProgress=noop,Kill=noop}
concommand={Add=noop}
chat={AddText=noop}
system={IsWindowed=function() return true end}
include=noop
function DermaMenu() return setmetatable({},{__index=function() return function() return setmetatable({},{__index=function() return noop end}) end end}) end
Derma_Query,Derma_StringRequest,SetClipboardText=noop,noop,noop
-- Painting: a badge's PaintOver records its pill's colour and text.
local painted
surface={CreateFont=noop,SetFont=noop,GetTextSize=function(t) return #tostring(t)*7,14 end,SetDrawColor=noop,
 DrawRect=noop,SetMaterial=noop,DrawTexturedRectUV=noop,PlaySound=noop}
draw={RoundedBox=function(_,_,_,_,_,color) if painted then painted.color=color end end,
 SimpleText=function(text) if painted then painted.text=text end end}

-- Derma: panels are tables. Base holds what every panel answers; a class's own methods are copied into the panel when
-- it is made (as GMod's vgui.Create merges a control table). Any other method name a panel is asked for does nothing,
-- while fields stay nil (IsValid answers true only for a live panel).
local created,byClass=0,{}
local Base={}
local Meta={__index=function(_,k)
 local m=Base[k] if m~=nil then return m end
 if type(k)=='string' and k:match('^%u') then return noop end
end}
local builtin,registered={}, {}
local function newPanel(class,parent)
 created=created+1 byClass[class]=(byClass[class] or 0)+1
 local p=setmetatable({__panel=true,__class=class,__children={},__visible=true,__enabled=true,__w=100,__h=24,__text=''},Meta)
 if parent then p:SetParent(parent) end
 if builtin[class] then builtin[class](p) end
 return p
end
function IsValid(v) return istable(v) and rawget(v,'__panel')==true and not rawget(v,'__removed') end
vgui={}
function vgui.Create(class,parent)
 local reg=registered[class]
 if reg then
  local p=vgui.Create(reg.base,parent)
  for k,v in pairs(reg.tbl) do p[k]=v end
  p.ClassName=class
  if p.Init then p:Init() end
  return p
 end
 return newPanel(class,parent)
end
function vgui.Register(name,tbl,base) registered[name]={tbl=tbl,base=base or 'Panel'} return tbl end
function vgui.GetControlTable(name) return registered[name] and registered[name].tbl end
function Base:SetParent(parent)
 local old=rawget(self,'__parent')
 if old then for i,c in ipairs(old.__children) do if c==self then table.remove(old.__children,i) break end end end
 rawset(self,'__parent',parent) if parent then table.insert(parent.__children,self) end
end
function Base:GetParent() return rawget(self,'__parent') end
function Base:Add(class) return vgui.Create(class,self) end
function Base:GetChildren() local out={} for i,c in ipairs(self.__children) do out[i]=c end return out end
function Base:Remove() rawset(self,'__removed',true) self:SetParent(nil) end
function Base:Dock(d) self.__dock=d end
function Base:DockMargin(l,t,r,b) self.__margin={l,t,r,b} end
function Base:GetDockMargin() local m=self.__margin or {0,0,0,0} return m[1],m[2],m[3],m[4] end
function Base:SetTall(h) self.__h=h end function Base:GetTall() return self.__h end
function Base:SetWide(w) self.__w=w end function Base:GetWide() return self.__w end
function Base:SetSize(w,h) self.__w,self.__h=w,h end function Base:GetSize() return self.__w,self.__h end
function Base:SetPos(x,y) self.__x,self.__y=x,y end function Base:GetPos() return self.__x or 0,self.__y or 0 end
function Base:GetX() return self.__x or 0 end function Base:GetY() return self.__y or 0 end
function Base:SetText(t) self.__text=t end function Base:GetText() return self.__text end
function Base:SetFont(f) self.__font=f end function Base:GetFont() return self.__font end
function Base:SetTooltip(t) self.__tooltip=t end function Base:GetTooltip() return self.__tooltip end
function Base:SetVisible(v) self.__visible=v and true or false end function Base:IsVisible() return self.__visible end
function Base:SetEnabled(v) self.__enabled=v and true or false end function Base:IsEnabled() return self.__enabled end
function Base:SetValue(v) self.__value=v end function Base:GetValue() return self.__value end
function Base:IsHovered() return false end
function Base:LocalToScreen(x,y) return x,y end
function Base:InvalidateLayout() self.__layouts=(self.__layouts or 0)+1 end
builtin.DNumSlider=function(p) p.Label=newPanel('DLabel',p) p.__value=0 end
builtin.DCheckBoxLabel=function(p) p.Label=newPanel('DLabel',p) p.Button=newPanel('DCheckBox',p) end
-- DTree: nodes with their names, icons and children; Clear removes them.
local function addNode(owner,name,icon)
 local node=newPanel('DTree_Node',owner) node.Label=newPanel('DLabel',node) node.__name=name node.__icon=icon node.nodes={}
 node.AddNode=function(self,n,i) return addNode(self,n,i) end
 node.SetExpanded=function(self,b) self.__expanded=b end
 node.SetText=function(self,text) self.__name=text self.Label:SetText(text) end
 owner.nodes[#owner.nodes+1]=node
 return node
end
builtin.DTree=function(p)
 p.nodes={} p.clears=0
 p.AddNode=function(self,name,icon) return addNode(self,name,icon) end
 p.Clear=function(self) for _,n in ipairs(self.nodes) do n:Remove() end self.nodes={} self.clears=self.clears+1 end
 p.SetSelectedItem=function(self,node) self.selectedNode=node end
end
-- DListView as GMod's: Lines in creation order, Sorted in display order; AddLine appends to both.
local ListView={}
function ListView:AddColumn(name)
 local column=newPanel('DListView_Column',self) column.Header=newPanel('DButton',column) column.__name=name
 self.Columns[#self.Columns+1]=column column.ColumnID=#self.Columns
 return column
end
function ListView:AddLine(...)
 self.dirty=true
 local line=vgui.Create('DListView_Line',self.pnlCanvas)
 table.insert(self.Lines,line) line.m_iID=#self.Lines line.m_pListView=self
 for k in pairs(self.Columns) do line:SetColumnText(k,'') end
 for k,v in pairs({...}) do line:SetColumnText(k,v) end
 table.insert(self.Sorted,line)
 self.added=self.added+1
 return line
end
function ListView:Clear()
 for _,v in pairs(self.Lines) do v:Remove() end
 self.Lines={} self.Sorted={} self.dirty=true self.clears=self.clears+1
end
function ListView:GetLines() return self.Lines end
function ListView:GetSelected() local out={} for _,v in pairs(self.Lines) do if v:IsLineSelected() then out[#out+1]=v end end return out end
function ListView:SelectItem(item) if not item then return end item:SetSelected(true) self:OnRowSelected(item:GetID(),item) end
function ListView:OnRowSelected() end
function ListView:SetDirty(b) self.dirty=b end
function ListView:GetDirty() return self.dirty end
function ListView:ClearSelection() for _,l in pairs(self.Lines) do l:SetSelected(false) end end
function ListView:SortByColumn(column,descending)
 table.sort(self.Sorted,function(a,b) if descending then a,b=b,a end return tostring(a:GetColumnText(column))<tostring(b:GetColumnText(column)) end)
 self.dirty=true
end
builtin.DListView=function(p)
 for k,v in pairs(ListView) do p[k]=v end
 p.Columns,p.Lines,p.Sorted,p.clears,p.added={}, {}, {},0,0
 p.pnlCanvas=newPanel('Panel',p)
end
local Line={}
function Line:SetColumnText(i,text)
 if not self.Columns[i] then self.Columns[i]=newPanel('DListViewLabel',self) end
 self.Columns[i]:SetText(tostring(text)) self.Columns[i].Value=text
 return self.Columns[i]
end
function Line:GetColumnText(i) return self.Columns[i] and self.Columns[i].Value or '' end
function Line:SetSelected(b) self.m_bSelected=b end
function Line:IsLineSelected() return self.m_bSelected==true end
function Line:GetID() return self.m_iID end
builtin.DListView_Line=function(p) for k,v in pairs(Line) do p[k]=v end p.Columns={} end

-- The Model Hotloader around library.lua and ui.lua.
local function L(key,params)
 if not params then return key end
 local keys=table.GetKeys(params) table.sort(keys)
 local parts={} for _,k in ipairs(keys) do parts[#parts+1]=k..'='..tostring(params[k]) end
 return key..'{'..table.concat(parts,',')..'}'
end
local origins,deleted,sources={}, {}, {}
mmdhl={native={DeleteAssets=function() return '{}' end,GetSourcePaths=function() return sources end,ClearPreview=noop,
  RequestAsset=noop},
 L=L,Localize=function(v) return v end,
 Decode=function(v,err) if v==nil then return nil,err end if v=='{}' then return {} end return v end,
 I18n={FontFace=function() return 'Face' end,FontData=function(size,weight) return {size=size,weight=weight} end,
  Language=function() return 'en' end,LanguageName=function(code) return code end,Chosen=function() return '' end,
  GameLanguage=function() return 'en' end,Languages={},Translated=function() return true end,Token=function(v) return v end},
 PanelVisible=function() return true end,Entities=function() return {} end,
 RenderAvailable=function() return false,'no preview in the harness' end,
 MaxNPCHealth=1000,
 workshop={IsHidden=function() return false end,Origin=function(_,id) return origins[id] end,
  Deleted=function() return deleted end,Provided=function() return false end},
 names={revision=0,NeedsNotice=function() return false end,Forget=noop,
  EntryName=function(_,entry) local t=entry.settings.translated if t then return t,entry.name end return entry.name,nil end},
 props={library={entries={},revision=1,Folders=function() return {} end,Refresh=noop},
  CollisionModes={{id='all',label='All'}},SurfaceMaterials={{id='plastic',label='Plastic'}},RenderCache={},AssetStatus={}}}
local function hex(n) return string.format('%064x',n) end
-- A character in the cache: its manifest and settings; a package's model has a Workshop origin.
local function put(n,spec)
 local id=hex(n)
 disk['mmd_hotloader/assets/'..id..'/manifest.json']={name=spec.authored or spec.name,vertices=spec.vertices or n*137,warnings={}}
 disk['mmd_hotloader/library/'..id..'.json']={version=1,name=spec.name,favorite=spec.favorite,folder=spec.folder,
  fit=spec.fit,translated=spec.translated}
 origins[id]=spec.package and {package=spec.package,title='Package '..spec.package,workshop=true,wsid='42'} or nil
 if spec.source then sources[id]={source=spec.source} end
 return id
end
local base={
 {name='Ayaka'},{name='ayaka'},{name='Zhongli',favorite=true},{name='Hu Tao',folder='Heroes'},
 {name='Keqing',folder='Heroes/Sub'},{name='Mona',package='A'},{name='Raiden',package='A',favorite=true},
 {name='Nahida',package='B'},{name='Bennett',fit={ok=false,missing={'arm'}}},{name='Venti',translated='Venti EN'},
 {name='枪',source='C:/models/spear/spear.pmx'},{name='Ayaka',folder='Heroes'},{name='Diluc',source='D:/pmx/diluc.pmx'},
 {name='Eula',favorite=true,folder='Heroes'},{name='Fischl'},{name='Ganyu',package='B',folder='Ignored'},
}
local added={
 {name='Albedo'},{name='Zhongli'},{name='ayaka',favorite=true},{name='Hu Tao',package='A'},{name='Kazuha',folder='Heroes/Sub'},
 {name='Yelan',package='C'},{name='Mavuika',fit={ok=false,missing={'leg'}},package='C'},{name='Xiao',folder='Heroes'},
 {name='Columbina',translated='Columbina EN',source='E:/x/columbina.pmx'},{name='Ayaka'},{name='Zz Last'},{name='Aaa First',favorite=true},
}
for i,spec in ipairs(base) do put(i,spec) end
dofile(source..'/library.lua')
-- GMod's continue (one, in the scene tab's loop) as LuaJIT's goto.
local f=assert(io.open(source..'/ui.lua','rb')) local ui=f:read('*a'):gsub('\r\n','\n') f:close()
local hits
ui,hits=ui:gsub('if ent%.MMDHLCopyOf then continue end','if ent.MMDHLCopyOf then goto mmdhl_skip end',1) eq(hits,1,'continue')
ui,hits=ui:gsub('(original=original,entity=ent})\n  end','%1\n  ::mmdhl_skip::\n  end',1) eq(hits,1,'continue label')
assert(not ui:find('%f[%w]continue%f[%W]'),'another continue in ui.lua')
assert(loadstring(ui,'@ui.lua'))()
local library=mmdhl.library
local WORKSHOP,DELETED='\2workshop','\2deleted'

-- What a window shows: every row in display order, the selection, the count, the details and the folder tree.
local function row(line,selection)
 painted={} if line.PaintOver then line.PaintOver(line,300,40) end local badge=painted painted=nil
 local c=badge.color
 return table.concat({line.asset,tostring(line:GetColumnText(1)),tostring(line:GetColumnText(2)),tostring(line:GetTooltip()),
  tostring(badge.text),c and (c.r..','..c.g..','..c.b) or '',tostring(line.Columns[1]:GetFont()),tostring(line.Columns[2]:GetFont()),
  tostring(line.gScF),tostring(line.entry==library.entries[line.asset]),selection and tostring(line:IsLineSelected()) or ''},' | ')
end
local function tree(node,depth,out)
 for _,n in ipairs(node.nodes) do
  out[#out+1]=string.rep(' ',depth)..tostring(n.__name)..' '..tostring(n.__icon)..(n.__expanded and ' +' or '')
  tree(n,depth+1,out)
 end
 return out
end
local function snapshot(panel,selection)
 local list=panel.Models
 eq(#list.Lines,#list.Sorted,'every line in the order')
 local rows={} for i,line in ipairs(list.Sorted) do rows[i]=row(line,selection) end
 local selectedNode=panel.Folders.selectedNode
 return {rows=rows,count=panel.Count:GetText(),details=panel.Details:GetText(),name=panel.Name:GetText(),
  selected=selection and tostring(panel.selected) or '',tree=table.concat(tree(panel.Folders,0,{}),'\n'),
  node=tostring(selectedNode and selectedNode.__name),folderTall=panel.FolderPanel:GetTall(),
  buttons=selection and table.concat({tostring(panel.Delete:IsEnabled()),tostring(panel.Rename:IsEnabled()),tostring(panel.Favorite:IsEnabled()),
   tostring(panel.Move:IsEnabled()),tostring(panel.Export:IsEnabled())},',') or ''}
end
local function same(a,b,why)
 for _,key in ipairs({'count','details','name','selected','tree','node','folderTall','buttons'}) do eq(a[key],b[key],why..' '..key) end
 for i=1,math.max(#a.rows,#b.rows) do eq(a.rows[i],b.rows[i],why..' row '..i) end
end
-- A window in a view (folder, search, selected entry), as the player would have left it.
local function window(view)
 local panel=mmdhl.CreateLibrary(nil)
 panel.folder=view.folder panel.Search:SetText(view.query or '') panel.selected=view.selected
 panel:Refresh() panel:Think()
 return panel
end
-- A fresh window in the view, with the entry the window chose (a rebuild keeps the chosen entry, not the first one).
local function fresh(panel,view) return window({folder=view.folder,query=view.query,selected=panel.selected}) end
-- The window took the changes as rows (no rebuild, one line made per new row), and shows what a fresh one shows.
local function check(panel,view,why,expectRows)
 local clears,lines=panel.Models.clears,byClass.DListView_Line or 0
 panel:Think()
 eq(panel.Models.clears,clears,why..': the list was built again')
 if expectRows then eq((byClass.DListView_Line or 0)-lines,expectRows,why..': rows made') end
 same(snapshot(panel,true),snapshot(fresh(panel,view),true),why)
end
local function rebuilt(panel,view,why)
 local clears=panel.Models.clears
 panel:Think()
 eq(panel.Models.clears,clears+1,why..': not built again')
 same(snapshot(panel,true),snapshot(fresh(panel,view),true),why)
end
local nextId=100
local function install(specs)
 local ids={} for _,spec in ipairs(specs) do nextId=nextId+1 ids[#ids+1]=put(nextId,spec) end
 return ids
end
-- A package's model over a character the library has (the same asset): new settings and a Workshop origin.
local NONE={}
local function relist(id,changes)
 local settings=disk['mmd_hotloader/library/'..id..'.json']
 for key,value in pairs(changes) do
  if key=='package' then origins[id]=value~=NONE and {package=value,title='Package '..value,workshop=true,wsid='42'} or nil
  else settings[key]=value~=NONE and value or nil end
 end
 return id
end
-- Whether the window must build its list again for these listed ids: a row whose entry left its folder or search.
local function mustRebuild(panel,ids,query)
 local rows={} for _,line in ipairs(panel.Models:GetLines()) do rows[line.asset]=true end
 for _,id in ipairs(ids) do
  local entry=library.entries[id]
  if rows[id] then
   if not panel:FolderShows(entry) then return true end
   local item=panel:RowItem(id,entry)
   local q=query or ''
   if q~='' and not (item.name..' '..(item.original or '')..' '..entry.source..' '..id):lower():find(q,1,true) then return true end
  end
 end
 return false
end

if scenario=='rows_like_a_rebuild' then
 -- All models, a selected row: two additions before the window's next frame, then one more.
 local view={selected=hex(4)}
 local panel=window(view)
 eq(panel.Models:GetSelected()[1].asset,hex(4),'selected row')
 library.Add(install({added[1],added[2],added[3],added[4]}))
 library.Add(install({added[5],added[6],added[7]}))
 check(panel,view,'two additions',7)
 library.Add(install({added[8],added[9],added[10],added[11],added[12]}))
 check(panel,view,'a third addition',5)
 eq(panel.Models:GetSelected()[1].asset,hex(4),'the selection kept')
 eq(#panel.Models:GetSelected(),1,'one row selected')
 -- Only a package's count changes: its node's label again, not the folder tree; a new package builds the tree again.
 local trees=panel.Folders.clears
 library.Add(install({{name='Kirara',package='A'}}))
 check(panel,view,'a package count',1)
 eq(panel.Folders.clears,trees,'the folder tree built again for a count')
 library.Add(install({{name='Chiori',package='Z'}}))
 check(panel,view,'a new package',1)
 eq(panel.Folders.clears,trees+1,'the folder tree kept for a new package')
 -- Nothing selected: the details still ask to choose a row.
 local plain=window({})
 library.Add(install({{name='Lynette'},{name='Freminet',favorite=true}}))
 check(plain,{},'no selection',2)
 eq(plain.selected,nil,'nothing chosen')
elseif scenario=='views' then
 -- Each folder and search: only the rows the view lists are made; the total counts the folder's.
 local views={
  {folder=''},{folder='Heroes'},{folder='Heroes/Sub'},{folder=WORKSHOP},{folder=WORKSHOP..':A'},{folder=WORKSHOP..':C'},
  {query='ayaka'},{query='hu'},{query='zz'},{query=hex(3):sub(1,12)},{query='models/spear'},{query='en'},{query='nothing'},
  {folder='Heroes',query='a'},{folder=WORKSHOP,query='a',selected=hex(6)},
 }
 for i,view in ipairs(views) do
  local panel=window(view)
  local ids=install({added[1+(i%12)],added[1+((i+3)%12)],added[1+((i+7)%12)]})
  library.Add(ids)
  local listed=0
  for _,id in ipairs(ids) do
   local entry=library.entries[id]
   if panel:FolderShows(entry) then
    local item=panel:RowItem(id,entry)
    local q=view.query or ''
    if q=='' or (item.name..' '..(item.original or '')..' '..entry.source..' '..id):lower():find(q,1,true) then listed=listed+1 end
   end
  end
  check(panel,view,'view '..i,listed)
 end
elseif scenario=='empty_view' then
 -- A view with no rows says why; rows added to it ask to choose one, and the count follows.
 assert(library.CreateFolder('Later'))
 local view={folder='Later'}
 local panel=window(view)
 eq(#panel.Models:GetLines(),0,'empty') eq(panel.Details:GetText(),'ui.empty.models','why the list is empty')
 library.Add(install({{name='Arlecchino',folder='Later'},{name='Clorinde'}}))
 check(panel,view,'into an empty folder',1)
 eq(panel.Details:GetText(),'ui.select_row','choose a row')
 local workshop={folder=WORKSHOP}
 for id,origin in pairs(origins) do if library.entries[id] then origins[id]=nil end end
 library.Refresh()
 local none=window(workshop)
 eq(none.Details:GetText(),'ui.empty.workshop','no Workshop models')
 library.Add(install({{name='Chasca',package='D'}}))
 check(none,workshop,'a first Workshop model',1)
elseif scenario=='multi_selection' then
 -- Rows the player selected stay selected (a rebuild kept only the row chosen last).
 local panel=window({})
 local picks={}
 for _,line in ipairs(panel.Models.Sorted) do
  if line.asset==hex(1) or line.asset==hex(5) or line.asset==hex(9) then panel.Models:SelectItem(line) picks[line.asset]=true end
 end
 eq(#panel.Models:GetSelected(),3,'three selected')
 local chosen=panel.selected
 library.Add(install({added[1],added[3],added[11]}))
 local clears=panel.Models.clears panel:Think() eq(panel.Models.clears,clears,'built again')
 local still={} for _,line in ipairs(panel.Models:GetSelected()) do still[line.asset]=true end
 eq(table.Count(still),3,'still three selected') for id in pairs(picks) do assert(still[id],'selection lost') end
 eq(panel.selected,chosen,'the chosen row')
 same(snapshot(panel,false),snapshot(window({selected=chosen}),false),'rows beside a selection')
elseif scenario=='rebuilds' then
 -- Anything but additions builds the list again, as before.
 local view={selected=hex(2)}
 local panel=window(view)
 library.Update(hex(7),{name='Raiden Shogun'}) rebuilt(panel,view,'a rename')
 library.Refresh() rebuilt(panel,view,'a full rebuild')
 library.Update(hex(9),{favorite=true}) rebuilt(panel,view,'a favourite')
 assert(library.CreateFolder('Moved')) panel:Think()
 assert(library.MoveToFolder({hex(10)},'Moved')) rebuilt(panel,view,'a move')
 -- A row whose entry, listed again, left the folder the window shows.
 local heroes={folder='Heroes'}
 local folderPanel=window(heroes)
 library.Add({relist(hex(4),{folder='Elsewhere'})}) rebuilt(folderPanel,heroes,'listed again into another folder')
 -- A row whose entry, listed again, is no longer what the search finds.
 local search={query='fischl'}
 local searchPanel=window(search)
 library.Add({relist(hex(15),{name='Prinzessin'})}) rebuilt(searchPanel,search,'listed again out of the search')
 -- An addition and a rebuild before the window's next frame.
 library.Add(install({added[1]})) library.Refresh() rebuilt(panel,view,'an addition then a rebuild')
 -- Names translated meanwhile.
 library.Add(install({added[2]})) mmdhl.names.revision=mmdhl.names.revision+1 rebuilt(panel,view,'names')
 -- More additions than the record keeps.
 for i=1,17 do library.Add(install({{name='Batch '..i}})) end
 rebuilt(panel,view,'seventeen additions')
 -- A column header sorted the list: the next change builds it again, in its own order.
 panel.Models:SortByColumn(1,true) eq(panel.built,nil,'a sorted list kept')
 library.Add(install({added[3]})) rebuilt(panel,view,'after a column sort')
 -- The view changed behind the window's back.
 panel.folder='Heroes' library.Add(install({added[4]}))
 view.folder='Heroes' rebuilt(panel,view,'another folder')
 -- Deleted Workshop models: their own rows.
 deleted[1]={id=hex(999),name='Gone',title='Package A',workshop=true}
 local gone={folder=DELETED}
 local bin=window(gone) library.Add(install({added[5]})) rebuilt(bin,gone,'the deleted view')
 deleted[1]=nil
 -- Nothing listed: no revision, no update.
 local revision=library.revision local clears=panel.Models.clears
 library.Add({'bad',hex(5000),hex(0xabc):upper()}) eq(library.revision,revision,'nothing listed made a revision')
 panel:Think() eq(panel.Models.clears,clears,'built again without a change')
 -- The props tab and the scene tab build their lists as before.
 local props=window({}) props:SetMode('static') props:Think()
 local clearsProps=props.Models.clears mmdhl.props.library.revision=mmdhl.props.library.revision+1 props:Think()
 eq(props.Models.clears,clearsProps+1,'the props tab')
 local scene=window({}) scene:SetMode('scene') scene:Think()
 local clearsScene=scene.Models.clears library.Add(install({added[6]})) scene:Think()
 eq(scene.Models.clears,clearsScene+1,'the scene tab')
elseif scenario=='listed_again' then
 -- A package's model over a character the library has (the same asset): its row's text, badge and place again, the
 -- chosen entry's details again, rows joining a folder or a search; no rebuild while no row has to go.
 local view={selected=hex(6)}
 local panel=window(view)
 library.Add({relist(hex(3),{name='Morax',favorite=NONE,package='P'})})
 check(panel,view,'an own model listed again',0)
 library.Add({relist(hex(6),{name='Astrologist',fit={ok=false,missing={'arm'}}})})
 check(panel,view,'the chosen entry listed again',0)
 eq(panel.Name:GetText(),'Astrologist','the chosen entry renamed in the details')
 local new=install({added[1],added[11]})
 library.Add({new[1],relist(hex(1),{name='Shirasagi'}),relist(hex(10),{translated='Barbatos'})})
 library.Add({new[2],relist(hex(15),{favorite=true})})
 check(panel,view,'new and listed again',2)
 -- A folder with a search: an entry without a row leaves the folder (the total), another joins it with a row, one
 -- now found by the search gets a row, one with a row moves.
 local heroesView={folder='Heroes',query='u'}
 local heroes=window(heroesView)
 eq(#heroes.Models:GetLines(),2,'Hu Tao and Eula')
 library.Add({relist(hex(12),{folder='Elsewhere'}),relist(hex(2),{folder='Heroes',name='Aether Lumine'}),
  relist(hex(5),{name='Keqing Yuheng'}),relist(hex(4),{name='Walnut'})})
 check(heroes,heroesView,'a folder and a search',2)
 eq(#heroes.Models:GetLines(),4,'four rows')
 -- Several rows selected: listed again, they stay selected.
 local multi=window({})
 for _,line in ipairs(multi.Models.Sorted) do if line.asset==hex(7) or line.asset==hex(9) then multi.Models:SelectItem(line) end end
 library.Add({relist(hex(7),{name='Ei'}),relist(hex(9),{fit=NONE})})
 local clears=multi.Models.clears multi:Think() eq(multi.Models.clears,clears,'built again')
 eq(#multi.Models:GetSelected(),2,'still two selected')
 same(snapshot(multi,false),snapshot(fresh(multi,{}),false),'rows beside a selection')
elseif scenario=='gui_scaler' then
 -- GUI Scaler present: new rows carry its mark as rows of a rebuild do.
 guiScaler=true
 local panel=window({})
 library.Add(install({added[1],added[7],added[12]}))
 check(panel,{},'GUI Scaler',3)
 for _,line in ipairs(panel.Models.Sorted) do eq(line.gScF,true,'GUI Scaler mark') end
elseif scenario=='record' then
 -- library.added: the ids each library.Add listed (new ones and ones listed again), once each, by revision; a rebuild
 -- and old revisions leave none.
 local a,b,c=unpack(install({added[1],added[2],added[3]}))
 library.Add({a,a,'bad',b}) local r=library.revision
 eq(#library.added[r],2,'ids recorded') eq(library.added[r][1],a) eq(library.added[r][2],b)
 library.Add({c}) eq(library.added[r+1][1],c,'next revision')
 library.Add({c,hex(5000)}) eq(#library.added[r+2],1,'a listing again') eq(library.added[r+2][1],c)
 library.Refresh() eq(next(library.added),nil,'a rebuild clears the record')
 for i=1,20 do library.Add(install({{name='Record '..i}})) end
 eq(table.Count(library.added),16,'the last sixteen revisions')
 for revision in pairs(library.added) do assert(revision>library.revision-16,'old revision kept') end
elseif scenario=='random' then
 -- Random libraries, views, selections and additions: always what a fresh window shows.
 local names={'Ayaka','ayaka','Hu Tao','hu tao','Zhongli','Albedo','Xiao','Yelan','枪','Ganyu','Keqing','Mona','Zz','A','b'}
 local folders={nil,'','Heroes','Heroes/Sub','Other'}
 local packages={nil,nil,'A','B','C'}
 local queries={'','a','hu','zz','en','src','x'}
 local counts={rows=0,rebuilt=0}
 for seed=1,150 do
  math.randomseed(seed)
  guiScaler=math.random()<.3
  local function spec()
   return {name=names[math.random(#names)],favorite=math.random()<.25,folder=folders[math.random(5)],
    package=packages[math.random(5)],fit=math.random()<.15 and {ok=false,missing={}} or nil,
    translated=math.random()<.2 and 'T'..math.random(9) or nil,source=math.random()<.3 and 'C:/src/m'..math.random(99)..'.pmx' or nil}
  end
  for p in pairs(disk) do if p:find('^mmd_hotloader/') then disk[p]=nil end end
  origins,sources={}, {} mmdhl.native.GetSourcePaths=function() return sources end
  for _=1,math.random(0,40) do nextId=nextId+1 put(nextId,spec()) end
  library.Refresh()
  local viewFolders={nil,'','Heroes','Heroes/Sub',WORKSHOP,WORKSHOP..':A',WORKSHOP..':C'}
  local view={folder=viewFolders[math.random(7)],query=queries[math.random(#queries)]}
  local ids=table.GetKeys(library.entries) table.sort(ids)
  if #ids>0 and math.random()<.6 then view.selected=ids[math.random(#ids)] end
  local panel=window(view)
  -- Batches of new characters and of characters listed again with other settings; the window takes them as rows,
  -- unless a row has to go.
  local pending={}
  local function settle()
   local expect=mustRebuild(panel,pending,view.query)
   if expect then counts.rebuilt=counts.rebuilt+1 elseif #pending>0 then counts.rows=counts.rows+1 end
   local clears=panel.Models.clears panel:Think()
   eq(panel.Models.clears,clears+(expect and 1 or 0),'seed '..seed..(expect and ' not built again' or ' built again'))
   same(snapshot(panel,true),snapshot(fresh(panel,view),true),'seed '..seed)
   pending={}
  end
  for _=1,math.random(1,4) do
   local batch={} for _=1,math.random(0,6) do nextId=nextId+1 batch[#batch+1]=put(nextId,spec()) end
   local existing=table.GetKeys(library.entries) table.sort(existing)
   for _=1,(#existing>0 and math.random(0,3) or 0) do
    local s=spec()
    batch[#batch+1]=relist(existing[math.random(#existing)],{name=s.name,favorite=s.favorite or NONE,folder=s.folder or NONE,
     package=s.package or NONE,fit=s.fit or NONE,translated=s.translated or NONE})
   end
   if #batch>0 and math.random()<.2 then batch[#batch+1]=batch[1] end
   library.Add(batch)
   for _,id in ipairs(batch) do pending[#pending+1]=id end
   if math.random()<.5 then settle() end
  end
  settle()
 end
 print(string.format('random: %d updates as rows, %d that had to build the list again',counts.rows,counts.rebuilt))
 assert(counts.rows>100 and counts.rebuilt>10,'the random batches cover both kinds of update')
else
 error('unknown scenario '..tostring(scenario))
end
print('PASS '..scenario)
