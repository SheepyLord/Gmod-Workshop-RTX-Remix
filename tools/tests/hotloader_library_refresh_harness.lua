-- Load-speedup round 2 (ADR 0238): the Model Hotloader's library rebuilds under LuaJIT. library.lua and sharing.lua
-- are loaded whole in the client realm; the disk, the native module, timers and network messages are instrumented,
-- and every util.JSONToTable of a character's manifest.json is counted. One scenario per run; prints PASS <scenario>.
local source,scenario=unpack(arg)
SERVER,CLIENT=false,true
local function noop() end
local function eq(a,b,why) assert(a==b,(why or '')..' '..tostring(a)..' ~= '..tostring(b)) end
function istable(v) return type(v)=='table' end
function isstring(v) return type(v)=='string' end
function isnumber(v) return type(v)=='number' end
function isbool(v) return type(v)=='boolean' end
function isfunction(v) return type(v)=='function' end
function IsValid(v) return istable(v) and v.valid~=false end
function Color(...) return {...} end
function ErrorNoHalt(text) error(text) end
function MsgN() end
function string.Trim(s) return (tostring(s):gsub('^%s+',''):gsub('%s+$','')) end
function table.Copy(value)
 if not istable(value) then return value end
 local copy={} for k,v in pairs(value) do copy[k]=table.Copy(v) end return copy
end
function table.GetKeys(t) local out={} for k in pairs(t) do out[#out+1]=k end return out end
function table.Count(t) local n=0 for _ in pairs(t) do n=n+1 end return n end
utf8=utf8 or {len=function(s) return #s end}
local clock=1000
function RealTime() return clock end function CurTime() return clock end function SysTime() return clock end
FCVAR_ARCHIVE=128
local hooks,timers,named={}, {}, {}
hook={Add=function(event,key,fn) hooks[event]=hooks[event] or {} hooks[event][key]=fn end,
 Run=function(event,...) for _,fn in pairs(hooks[event] or {}) do fn(...) end end,Remove=noop}
timer={Simple=function(_,fn) timers[#timers+1]=fn end,
 Create=function(name,_,_,fn) named[name]=fn end,Remove=function(name) named[name]=nil end,
 Exists=function(name) return named[name]~=nil end}
local function tick()
 local pending=timers timers={} for _,fn in ipairs(pending) do fn() end
 local due=named named={} for _,fn in pairs(due) do fn() end
end
local function cvar(value) return {GetBool=function() return value~=0 end,GetInt=function() return value end,
 GetFloat=function() return value end,GetString=function() return tostring(value) end} end
function CreateClientConVar(_,value) return cvar(tonumber(value) or 0) end
function CreateConVar(_,value) return cvar(tonumber(value) or 0) end
function GetConVar() return cvar(0) end
cvars={AddChangeCallback=noop}
-- Disk: manifests and settings as tables (util.JSONToTable copies them), with sizes and times.
local disk,times,sizes={}, {}, {}
local decodes=0
file={Read=function(p) return disk[p] end,Exists=function(p) return disk[p]~=nil end,
 Write=function(p,v) disk[p]=v end,CreateDir=noop,Delete=function(p) disk[p]=nil end,
 Time=function(p) return disk[p]~=nil and (times[p] or 1) or 0 end,
 Size=function(p) return disk[p]~=nil and (sizes[p] or 100) or -1 end,
 Find=function(pattern)
  local dirs,seen={},{}
  if pattern=='mmd_hotloader/assets/*' then
   for p in pairs(disk) do local id=p:match('^mmd_hotloader/assets/(%x+)/') if id and not seen[id] then seen[id]=true dirs[#dirs+1]=id end end
  end
  table.sort(dirs) return {},dirs
 end}
util={JSONToTable=function(v)
  if not istable(v) then return nil end
  if v.manifest then decodes=decodes+1 end
  return table.Copy(v)
 end,TableToJSON=function(v) return table.Copy(v) end,AddNetworkString=noop}
local singlePlayer=true
game={SinglePlayer=function() return singlePlayer end,IsDedicated=function() return false end}
local received,reads={}, {}
net={Receive=function(name,fn) received[name]=fn end,Start=noop,WriteString=noop,WriteUInt=noop,WriteBool=noop,
 WriteData=noop,SendToServer=noop,Send=noop,Broadcast=noop,
 ReadString=function() return table.remove(reads,1) end,ReadUInt=function() return table.remove(reads,1) end,
 ReadBool=function() return table.remove(reads,1) end}
function LocalPlayer() return {valid=true,IsAdmin=function() return true end,IsListenServerHost=function() return false end} end
notification={AddLegacy=noop}
concommand={Add=noop}
NOTIFY_GENERIC,NOTIFY_ERROR=0,1
local function hex(n) return string.format('%064x',n) end
local function addAsset(n,time)
 local id=hex(n)
 disk['mmd_hotloader/assets/'..id..'/manifest.json']={manifest=true,name='Character '..n,vertices=n}
 times['mmd_hotloader/assets/'..id..'/manifest.json']=time or 1
 disk['mmd_hotloader/library/'..id..'.json']={version=1}
 return id
end
for n=1,50 do addAsset(n) end
mmdhl={native={DeleteAssets=function() return '{}' end,GetSourcePaths=function() return '{}' end,
 ReleaseSharedExport=noop},
 L=function(v) return v end,Localize=function(v) return v end,
 Decode=function(v,err) if v==nil then return nil,err end return v end,
 I18n={Token=function(v) return v end}}
dofile(source..'/library.lua')
dofile(source..'/sharing.lua')
local library=mmdhl.library
local changed=0
hook.Add('MMDHL.LibraryChanged','harness',function() changed=changed+1 end)
eq(decodes,50,'the include-time build decodes each manifest once')
eq(table.Count(library.entries),50,'entries after the first build')
local function catalog(ids)
 for _,id in ipairs(ids) do reads={id,'Shared '..id:sub(-4)} received['mmdhl_catalog']() end
end
local shared={} for n=101,193 do shared[#shared+1]=hex(n) end
if scenario=='single_player_catalog' then
 -- A single-player server's catalog: the library leaves it out, so no message builds it again.
 local revision=library.revision
 catalog(shared)
 tick()
 eq(library.revision,revision,'a single-player catalog rebuilt the library')
 eq(decodes,50,'manifests decoded again')
 eq(changed,0,'LibraryChanged without a change')
 eq(table.Count(mmdhl.sharedAssets),93,'the catalog is still kept')
elseif scenario=='multiplayer_catalog' then
 -- Another server's catalog: 93 messages, one rebuild on the next tick, no manifest decoded again.
 singlePlayer=false
 local revision=library.revision
 catalog(shared)
 eq(library.revision,revision,'rebuilt before the tick')
 tick()
 eq(library.revision,revision+1,'one rebuild for the whole catalog')
 eq(changed,1,'LibraryChanged once')
 eq(decodes,50,'cached manifests decoded again')
 eq(table.Count(library.entries),50+93,'server-approved entries listed')
 eq(library.entries[shared[1]].source,'library.server_approved')
 -- Approvals withdrawn: again one rebuild for the message.
 reads={false,2,shared[1],shared[2]} received['mmdhl_catalog_forget']()
 tick()
 eq(library.revision,revision+2,'one rebuild after the withdrawal')
 eq(table.Count(library.entries),50+91,'withdrawn entries still listed')
 -- RequestRefresh coalesces whoever asks: many asks, one rebuild.
 for _=1,20 do library.RequestRefresh() end
 tick() eq(library.revision,revision+3,'asks before a tick are one rebuild')
elseif scenario=='manifest_cache' then
 local revision=library.revision
 library.Refresh() eq(decodes,50,'a second build decoded unchanged manifests')
 -- A manifest written again (its time changes): only that one is decoded.
 times['mmd_hotloader/assets/'..hex(7)..'/manifest.json']=2
 disk['mmd_hotloader/assets/'..hex(7)..'/manifest.json']={manifest=true,name='Renamed',vertices=7}
 library.Refresh() eq(decodes,51,'the rewritten manifest') eq(library.entries[hex(7)].info.name,'Renamed')
 -- Same time, another size: decoded again too.
 sizes['mmd_hotloader/assets/'..hex(8)..'/manifest.json']=200
 library.Refresh() eq(decodes,52,'a manifest of another size')
 -- A new character: decoded once; a removed one: gone from the entries and from the cache.
 local new=addAsset(60) library.Refresh() eq(decodes,53,'the new manifest') assert(library.entries[new],'new entry')
 disk['mmd_hotloader/assets/'..hex(3)..'/manifest.json']=nil
 library.Refresh() eq(library.entries[hex(3)],nil,'removed entry listed')
 disk['mmd_hotloader/assets/'..hex(3)..'/manifest.json']={manifest=true,name='Back',vertices=3}
 library.Refresh() eq(decodes,54,'a manifest back after its folder went is decoded again') eq(library.entries[hex(3)].info.name,'Back')
 -- Settings are read at every build (small; written with the same size within a second by renames).
 disk['mmd_hotloader/library/'..hex(4)..'.json']={version=1,name='Chosen name'}
 library.Refresh() eq(library.entries[hex(4)].name,'Chosen name','settings not read again')
 -- A deleted character's settings hide it at once.
 disk['mmd_hotloader/library/'..hex(5)..'.json']={version=1,deleted=true}
 library.Refresh() eq(library.entries[hex(5)],nil,'deleted character listed')
 assert(library.revision>revision)
else
 error('unknown scenario '..scenario)
end
print('PASS '..scenario)
