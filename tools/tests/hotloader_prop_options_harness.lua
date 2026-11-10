-- Runs the Model Hotloader's actual props/library.lua (arg[1]) and the static import starters of
-- library.lua (arg[2]) with the game instrumented: detailed collision (CoACD, slow) is no longer
-- a remembered default. A remembered choice goes back to the single hull once, a chosen detailed
-- collision serves one import, a .blend listing does not use it up, and a reimport keeps a
-- prop's own detailed collision.
local function fail(text) io.stderr:write('FAIL: '..text..'\n') os.exit(1) end
local function check(ok,text) if not ok then fail(text) end end

local saved -- what the game remembered (client.vdf), by convar name
local convars
local function makeConVar(name,default)
 local cv={name=name,value=saved[name] or default}
 function cv:GetString() return self.value end
 function cv:SetString(v) self.value=tostring(v) end
 function cv:GetInt() return math.floor(tonumber(self.value) or 0) end
 function cv:SetInt(v) self.value=tostring(math.floor(v)) end
 function cv:GetBool() return (tonumber(self.value) or 0)~=0 end
 convars[name]=cv return cv
end
local catalog
local function stubs()
 convars={}
 CreateClientConVar=function(name,default) return convars[name] or makeConVar(name,default) end
 GetConVar=function(name) return convars[name] end
 cvars={AddChangeCallback=function() end}
 RunConsoleCommand=function(name,value) convars[name]:SetString(value) end
 file={Read=function() return nil end,Write=function() end,CreateDir=function() end}
 util={JSONToTable=function(text) if text=='CATALOG' then return catalog end return nil end,TableToJSON=function(v) return v end}
 hook={Add=function() end,Run=function() end,Remove=function() end}
 net={Receive=function() end,Start=function() end,WriteString=function() end,WriteUInt=function() end,SendToServer=function() end}
 timer={Create=function() end,Remove=function() end,Simple=function() end}
 game={SinglePlayer=function() return true end}
 notification={AddLegacy=function() end}
 string.Trim=function(s) return (s:gsub('^%s+',''):gsub('%s+$','')) end
 utf8=utf8 or {len=function(s) return #s end}
 table.GetKeys=function(t) local keys={} for k in pairs(t) do keys[#keys+1]=k end return keys end
 math.Clamp=function(v,lo,hi) return math.min(math.max(v,lo),hi) end
 math.Round=function(v) return math.floor(v+.5) end
 function isfunction(v) return type(v)=='function' end
 function istable(v) return type(v)=='table' end
 function isnumber(v) return type(v)=='number' end
 function IsValid(v) return v~=nil end
 function RealTime() return 0 end
 ents={FindByClass=function() return {} end}
 local P={native={PropCatalog=function() return 'CATALOG' end,GetCapabilities=function() return nil end},Placeholder='x'}
 function P.ValidID(id) return type(id)=='string' and #id==64 end
 mmdhl={props=P,L=function(key) return key end,Decode=function(v) return v end}
 return P
end
local propsLibrary=assert(io.open(arg[1],'rb')):read('*a')
local function loadProps()
 local P=stubs()
 assert(loadstring(propsLibrary,'@props/library.lua'))()
 return P
end
local A,B=string.rep('a',64),string.rep('b',64)
catalog={[A]={name='detailed',collision_hulls=7},[B]={name='single',collision_hulls=1}}

-- 1. A game that remembered detailed collision: once back to the single hull.
saved={mmdhl_prop_import_collision='balanced'}
local P=loadProps()
check(convars.mmdhl_prop_import_collision:GetString()=='hull','a remembered detailed choice goes back to the single hull')
check(convars.mmdhl_prop_import_collision_version:GetInt()==1,'the reset is recorded')
check(P.ImportOptions().collision=='hull','an ordinary import uses the single hull')

-- 2. Chosen again after that: kept until an import uses it.
saved={mmdhl_prop_import_collision='balanced',mmdhl_prop_import_collision_version='1'}
P=loadProps()
check(convars.mmdhl_prop_import_collision:GetString()=='balanced','a choice made after the reset is the player\'s')
local options=P.ImportOptions()
check(options.collision=='balanced','the next import is detailed')
P.ImportStarted(options)
check(convars.mmdhl_prop_import_collision:GetString()=='hull','after it started, the single hull again')
check(P.ImportOptions().collision=='hull','so the import after it is fast')

-- 3. Reimport keeps a prop's detailed collision; a single-hull prop stays fast.
check(P.ReimportOptions(A).collision=='balanced','a detailed prop is reimported with detailed collision')
check(P.ReimportOptions(B).collision=='hull','a single-hull prop is reimported with the single hull')
convars.mmdhl_prop_import_collision:SetString('balanced')
check(P.ReimportOptions(B).collision=='balanced','an explicit choice still applies to a reimport')

-- 4. The starters in library.lua: StartStaticImport and ReimportProp use the choice up, a .blend listing does not.
local library=assert(io.open(arg[2],'rb')):read('*a')
local function slice(from,to)
 local a=library:find(from,1,true) check(a,'library.lua has '..from)
 local b=library:find(to,a,true) check(b,'library.lua has '..to..' after '..from)
 return library:sub(a,b-1)
end
local code='local library,native,L,isBlend=...\n'..slice('function library.StartStaticImport(source,objects)','local function startImport(')
 ..slice('function library.ReimportProp(id)','-- Reload a character from its recorded source')
local started={}
local lib={StartImport=function(handle) started[#started+1]=handle return handle~=nil end,StartError=function(e) return e end}
local native={BeginImport=function(source,options) return {source=source,options=options} end,PropReload=function(id,options) return {id=id,options=options} end}
local function blend(source) return source:sub(-6)=='.blend' end
assert(loadstring(code,'@library.lua'))(lib,native,function(k) return k end,blend)

convars.mmdhl_prop_import_collision:SetString('balanced')
check(lib.StartStaticImport('E:/x/scene.blend'),'a .blend listing starts')
check(started[#started].options.kind=='blend_scene' and convars.mmdhl_prop_import_collision:GetString()=='balanced','listing a .blend keeps the choice for its import')
check(lib.StartStaticImport('E:/x/scene.blend',{'Cube'}),'the chosen objects import')
check(started[#started].options.collision=='balanced' and convars.mmdhl_prop_import_collision:GetString()=='hull','the import of the objects uses the choice up')
convars.mmdhl_prop_import_collision:SetString('balanced')
check(lib.StartStaticImport('E:/x/flower.pmx'),'a PMX imports')
check(started[#started].options.collision=='balanced' and convars.mmdhl_prop_import_collision:GetString()=='hull','one import per choice')
check(lib.StartStaticImport('E:/x/flower.pmx') and started[#started].options.collision=='hull','the next import is the single hull')
check(lib.ReimportProp(A) and started[#started].options.collision=='balanced','Reimport keeps the detailed prop detailed')
check(lib.ReimportProp(B) and started[#started].options.collision=='hull','and the single-hull prop fast')
print('PASS: detailed collision serves one import')
