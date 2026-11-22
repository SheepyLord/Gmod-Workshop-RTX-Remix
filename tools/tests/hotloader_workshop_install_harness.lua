-- ADR 0255: the Model Hotloader installs a Workshop package's models several at once. workshop.lua (and, for one
-- scenario, library.lua) is loaded whole in the client realm under LuaJIT; the native transfer and asset check, the
-- disk, timers, hooks and frames are instrumented. One scenario per run; prints PASS <scenario>.
local source,scenario=unpack(arg)
SERVER,CLIENT=false,true
local function noop() end
local function eq(a,b,why) assert(a==b,(why or '')..': '..tostring(a)..' ~= '..tostring(b)) end
function istable(v) return type(v)=='table' end
function isstring(v) return type(v)=='string' end
function isnumber(v) return type(v)=='number' end
function isbool(v) return type(v)=='boolean' end
function isfunction(v) return type(v)=='function' end
function IsValid(v) return istable(v) and v.valid~=false end
local errors={}
function ErrorNoHalt(text) errors[#errors+1]=text end
function MsgN() end
function string.Trim(s) return (tostring(s):gsub('^%s+',''):gsub('%s+$','')) end
function string.GetPathFromFilename(path) return path:match('^(.*[/\\])[^/\\]*$') or '' end
function table.Copy(value)
 if not istable(value) then return value end
 local copy={} for k,v in pairs(value) do copy[k]=table.Copy(v) end return copy
end
function table.HasValue(t,v) for _,x in pairs(t) do if x==v then return true end end return false end
function table.RemoveByValue(t,v) for i,x in ipairs(t) do if x==v then table.remove(t,i) return i end end return false end
function table.Count(t) local n=0 for _ in pairs(t) do n=n+1 end return n end
function math.Clamp(v,low,high) return math.min(math.max(v,low),high) end
utf8=utf8 or {len=function(s) return #s end}
NOTIFY_GENERIC,NOTIFY_ERROR=0,1
-- Frames and time: SysTime moves a little at each call within a frame, so the install's per-frame budget holds.
local frame,now=0,1000
function SysTime() now=now+.0003 return now end
function RealTime() return now end
function CurTime() return now end
local hooks,named,simple={}, {}, {}
hook={Add=function(event,key,fn) hooks[event]=hooks[event] or {} hooks[event][key]=fn end,
 Run=function(event,...) for _,fn in pairs(hooks[event] or {}) do fn(...) end end,Remove=noop}
timer={Simple=function(delay,fn) simple[#simple+1]={due=now+delay,fn=fn} end,
 Create=function(name,delay,_,fn) named[name]={due=now+delay,fn=fn} end,Remove=function(name) named[name]=nil end,
 Exists=function(name) return named[name]~=nil end}
local function tick()
 frame=frame+1 now=1000+frame/60
 for _,fn in pairs(hooks.Think or {}) do fn() end
 local due={} for name,t in pairs(named) do if t.due<=now then due[#due+1]=name end end
 for _,name in ipairs(due) do local t=named[name] if t and t.due<=now then named[name]=nil t.fn() end end
 local pending=simple simple={}
 for _,t in ipairs(pending) do if t.due<=now then t.fn() else simple[#simple+1]=t end end
end
-- The disk: files the natives wrote (size, hash, time) and what scripts wrote (settings, state).
local disk,text,fileClock={}, {}, 1
local stateWrites,lastState=0,nil
local StatePath='mmd_hotloader/workshop/state.json'
local deleted={}
local reads={}
file={Read=function(p) reads[p]=(reads[p] or 0)+1 return text[p] end,
 Exists=function(p) return text[p]~=nil or disk[p]~=nil end,
 Write=function(p,v) text[p]=v if p==StatePath then stateWrites=stateWrites+1 lastState=v end end,
 CreateDir=noop,Delete=function(p) deleted[#deleted+1]=p text[p]=nil disk[p]=nil end,
 Time=function(p) local d=disk[p] return d and d.time or (text[p] and 1 or 0) end,
 Size=function(p) local d=disk[p] return d and d.size or -1 end,
 Find=function() return {},{} end}
-- A package's file read from the mounted addon: its packed size.
local packed={}
function file.Open(path)
 local size=packed[path] if not size then return nil end
 local offset=0
 return {Size=function() return size end,Read=function(_,n) n=math.min(n,size-offset) offset=offset+n return string.rep('x',n) end,Close=noop}
end
util={JSONToTable=function(v) if istable(v) then return table.Copy(v) end return nil end,
 TableToJSON=function(v) return table.Copy(v) end,AddNetworkString=noop}
game={SinglePlayer=function() return true end,IsDedicated=function() return false end}
function LocalPlayer() return {valid=true,IsListenServerHost=function() return false end} end
ents={FindByClass=function() return {} end}
net={Start=noop,SendToServer=noop,Receive=noop}
local notices={}
notification={AddProgress=noop,Kill=noop,AddLegacy=function(text) notices[#notices+1]=text end}
-- The package: models with a manifest, a model and textures; textures 1-3 are shared by several models.
local function hex(n,width) return string.format('%0'..width..'x',n) end
local models,modelFiles,owners={}, {}, {}
local package={id=hex(1,32),install='workshop',title='Pack',author='',description='',created=0,folder='',items={},files={}}
local function addFile(path,size)
 package.files[path]=package.files[path] or {size=size,sha256=hex(#path*7919+size,64),packed=size+80}
 packed['data_static/mmdhl/files/'..package.files[path].sha256..'.dat']=package.files[path].packed
end
local function addModel(n,textures,size)
 local asset=hex(1000+n,64)
 local files={'assets/'..asset..'/manifest.json','assets/'..asset..'/model.bin'}
 addFile(files[1],2000) addFile(files[2],(size or 3)*1000000)
 for _,t in ipairs(textures) do local path='textures/'..hex(t,64)..'.png' files[#files+1]=path addFile(path,1500000+t*1000) end
 for _,path in ipairs(files) do owners[path]=owners[path] or {} table.insert(owners[path],asset) end
 package.items[#package.items+1]={kind='character',asset=asset,name='Model '..n,files=files}
 models[#models+1]=asset modelFiles[asset]=files
 return asset
end
-- Instrumented natives: a transfer's commit ends after a few polls (more for larger files), an asset check after
-- `checkPolls`; failures and checks that need to run alone are chosen per scenario.
local seq=0
local transfers,checks={}, {}
local live={commits=0,checks=0}
local stats={begins={},matches={},maxCommits=0,maxChecks=0,checkStarts=0}
local failPaths,checkMode,checkPolls={}, {}, {}
local function recorded(path)
 for _,asset in ipairs(owners[path] or {}) do
  local rec=lastState and lastState.assets and lastState.assets['character:'..asset]
  if rec then return true end
 end
 return false
end
local native={}
function native.GetWorkerCapabilities() return {logicalThreads=24} end
function native.SharedFileMatches(path,size,sha)
 stats.matches[path]=(stats.matches[path] or 0)+1
 local d=disk['mmd_hotloader/'..path] return d~=nil and d.size==size and d.sha==sha
end
function native.BeginSharedFile(path,size,sha,wire)
 assert(table.Count(transfers)<16,'transfer queue full')
 seq=seq+1 transfers[seq]={path=path,size=size,sha=sha,packed=wire,written=0}
 stats.begins[path]=(stats.begins[path] or 0)+1
 return seq
end
function native.AppendSharedChunk(handle,offset,bytes)
 local t=assert(transfers[handle],'unknown transfer') eq(offset,t.written,'chunk offset') t.written=t.written+#bytes
 assert(t.written<=t.packed,'chunk past the end') return true
end
function native.CommitSharedFile(handle)
 local t=assert(transfers[handle],'unknown transfer') eq(t.written,t.packed,'commit of an incomplete transfer')
 assert(recorded(t.path),'a file written before its model recorded its install: '..t.path)
 t.polls=2+math.floor(t.size/1000000) t.committing=true
 live.commits=live.commits+1 stats.maxCommits=math.max(stats.maxCommits,live.commits)
 return true
end
function native.PollSharedCommit(handle)
 local t=assert(transfers[handle],'poll of an unknown commit')
 t.polls=t.polls-1 if t.polls>0 then return false end
 t.committing=false live.commits=live.commits-1
 if failPaths[t.path] then failPaths[t.path]=nil return nil,'commit failed' end
 transfers[handle]=nil fileClock=fileClock+1
 disk['mmd_hotloader/'..t.path]={size=t.size,sha=t.sha,time=fileClock}
 return true
end
function native.CancelSharedFile(handle)
 local t=transfers[handle] if t and t.committing then live.commits=live.commits-1 end transfers[handle]=nil
end
function native.StartAssetCheck(kind,asset)
 for _,path in ipairs(modelFiles[asset]) do assert(disk['mmd_hotloader/'..path],'checked before its file arrived: '..path) end
 live.checks=live.checks+1 stats.maxChecks=math.max(stats.maxChecks,live.checks) stats.checkStarts=stats.checkStarts+1
 assert(live.checks<=8,'native check limit')
 seq=seq+1 checks[seq]={asset=asset,polls=checkPolls[asset] or 40,crowded=live.checks>1}
 if live.checks>1 then for _,c in pairs(checks) do c.crowded=true end end
 return seq
end
function native.PollAssetCheck(handle)
 local c=assert(checks[handle],'poll of an unknown check')
 c.polls=c.polls-1 if c.polls>0 then return false end
 checks[handle]=nil live.checks=live.checks-1
 if checkMode[c.asset]=='invalid' then return nil,'not a model','invalid' end
 if checkMode[c.asset]=='alone' and c.crowded then return nil,'This model needs about 900 MB of memory to load','invalid' end
 return true
end
-- The libraries workshop.lua lists installed models in.
local adds,refreshes,propRefreshes={}, 0, 0
mmdhl={native=native,L=function(v) return v end,Localize=function(v) return v end,Decode=function(v) return v end,
 CleanArmsParts=function() return {} end,Entities=function() return {} end,GetAsset=function() end,
 library={entries={},Add=function(ids) adds[#adds+1]=table.Copy(ids) end,Refresh=function() refreshes=refreshes+1 end},
 props={library={Refresh=function() propRefreshes=propRefreshes+1 end}}}
local installedNames={}
local function load()
 dofile(source..'/workshop.lua')
 mmdhl.workshop.OnInstalled(function(item) installedNames[#installedNames+1]=item.name end)
end
local function provide()
 local W=mmdhl.workshop
 W.packages={[package.id]=package} W.origins={[package.id]={pathId='GAME',title='Pack',wsid='1',workshop=true}}
 W.provided={} for _,item in ipairs(package.items) do W.provided[W.Key(item.kind,item.asset)]={package.id} end
end
local function run(limit)
 for _=1,limit do tick() if not mmdhl.workshop.Busy() and next(named)==nil then return frame end end
 error('still installing after '..limit..' frames')
end
if scenario=='parallel' then
 -- Eight models, three textures shared among them, checks of different lengths.
 for n=1,8 do addModel(n,{n%3+1,(n+1)%3+1,100+n,200+n},n%4+1) checkPolls[models[n]]=20+n*15 end
 load() provide()
 mmdhl.workshop.Reconcile(true)
 assert(mmdhl.workshop.Busy(),'nothing queued')
 run(20000)
 eq(#installedNames,8,'models installed') eq(#errors,0,'errors: '..table.concat(errors,' | '))
 for path in pairs(package.files) do eq(stats.begins[path],1,'transfers of '..path) end
 eq(stats.maxChecks,4,'checks side by side (24 threads)') assert(stats.maxCommits<=4,'commits at once: '..stats.maxCommits)
 assert(stats.maxCommits>=2,'commits never overlapped')
 eq(stats.checkStarts,8,'asset checks')
 -- One write records the models taken at once; the installed records follow in a few coalesced writes.
 assert(stateWrites<=10,'state written '..stateWrites..' times')
 for _,asset in ipairs(models) do assert(lastState.assets['character:'..asset].installed,'not recorded installed') end
 -- Installed models are added to the library on their own, a few at a time: never a rebuild per model.
 local listed={} for _,ids in ipairs(adds) do for _,id in ipairs(ids) do eq(listed[id],nil,'listed twice') listed[id]=true end end
 for _,asset in ipairs(models) do assert(listed[asset],'never listed') end
 assert(#adds<8,'one library update per model ('..#adds..')')
 eq(refreshes,1,'full rebuilds (one for the scan)')
 eq(notices[#notices],'workshop.installed','the closing notice')
elseif scenario=='failures' then
 -- The first commit of shared texture 1 fails: whichever of models 1 and 2 moves it first fails, and the other (which
 -- waits for that texture) moves it itself. Which one goes first follows the queue's order, W.provided's pairs order,
 -- and LuaJIT 2.1 seeds its string hashes per run, so either may.
 -- Model 3's check fails beside others and passes alone; model 4 is no model at all: refused after its check alone.
 local a=addModel(1,{1,11}) local b=addModel(2,{1,12}) local c=addModel(3,{13}) local d=addModel(4,{14})
 for n=5,6 do addModel(n,{20+n}) end
 failPaths['textures/'..hex(1,64)..'.png']=true
 checkMode[c]='alone' checkMode[d]='invalid'
 load() provide()
 mmdhl.workshop.Reconcile(true)
 run(20000)
 local names={} for _,name in ipairs(installedNames) do names[name]=true end
 eq((names['Model 1'] and 1 or 0)+(names['Model 2'] and 1 or 0),1,'models installed of the two sharing the failed texture (the failed one counted, or the waiting one never installed)')
 assert(names['Model 3'],'the model that needed its check alone') assert(not names['Model 4'],'the invalid model counted')
 assert(names['Model 5'] and names['Model 6'],'the other models')
 eq(stats.begins['textures/'..hex(1,64)..'.png'],2,'the failed shared texture moved again')
 eq(#errors,2,'errors reported: '..table.concat(errors,' | '))
 local manifestGone=false for _,p in ipairs(deleted) do if p=='mmd_hotloader/assets/'..d..'/manifest.json' then manifestGone=true end end
 assert(manifestGone,'the invalid model\'s manifest stayed')
 eq(live.checks,0,'checks left running') eq(table.Count(transfers),0,'transfers left open')
 assert(not mmdhl.workshop.Busy(),'still busy')
elseif scenario=='replace' then
 -- An installed model one of whose files changed since it was last known good: verify hashes the files up to the
 -- changed one, and the install replaces that file without checking it again, then finds the rest in place.
 local a=addModel(1,{1,2,3})
 for _,path in ipairs(modelFiles[a]) do local f=package.files[path] disk['mmd_hotloader/'..path]={size=f.size,sha=f.sha256,time=1} end
 local changed=modelFiles[a][4]
 disk['mmd_hotloader/'..changed].sha='damaged' disk['mmd_hotloader/'..changed].time=5
 local times={} for _,path in ipairs(modelFiles[a]) do times[path]=1 end
 text[StatePath]={version=1,assets={['character:'..a]={installed=true,times=times,name='Model 1',package=package.id}}}
 load() provide()
 mmdhl.workshop.Reconcile(true)
 assert(not mmdhl.workshop.Busy(),'an intact model queued at once')
 run(20000)
 eq(stats.begins[changed],1,'the changed file replaced') eq(table.Count(stats.begins),1,'files moved')
 eq(#installedNames,1,'installed again') eq(disk['mmd_hotloader/'..changed].sha,package.files[changed].sha256,'replaced')
 eq(#errors,0,'errors: '..table.concat(errors,' | '))
elseif scenario=='library_add' then
 -- library.Add lists new characters as a rebuild would, reading only their files.
 local entries={}
 local function put(n,name)
  local id=hex(5000+n,64)
  text['mmd_hotloader/assets/'..id..'/manifest.json']={name='Manifest '..n,vertices=n}
  disk['mmd_hotloader/assets/'..id..'/manifest.json']={size=100,time=1}
  text['mmd_hotloader/library/'..id..'.json']={version=1,name=name}
  return id
 end
 for n=1,30 do put(n) end
 file.Find=function(pattern)
  local dirs={} if pattern=='mmd_hotloader/assets/*' then for p in pairs(text) do local id=p:match('^mmd_hotloader/assets/(%x+)/manifest%.json$') if id then dirs[#dirs+1]=id end end end
  table.sort(dirs) return {},dirs
 end
 mmdhl.library=nil mmdhl.native.GetSourcePaths=function() return {} end mmdhl.native.DeleteAssets=function() return {} end
 concommand={Add=noop} cvars={AddChangeCallback=noop}
 local function cvar(value) return {GetBool=function() return value~=0 end,GetInt=function() return value end,GetString=function() return tostring(value) end} end
 CreateClientConVar=function(_,value) return cvar(tonumber(value) or 0) end GetConVar=function() return cvar(0) end
 mmdhl.workshop={IsHidden=function() return false end,Origin=function(_,id) return {package='p',title='Pack '..id:sub(-2)} end}
 dofile(source..'/library.lua')
 local library=mmdhl.library
 library.Refresh()
 local changedRuns=0 hook.Add('MMDHL.LibraryChanged','harness',function() changedRuns=changedRuns+1 end)
 local revision=library.revision
 local new={put(31,'Named'),put(32)}
 text['mmd_hotloader/library/'..put(33)..'.json']={version=1,deleted=true}
 local hidden=put(34)
 reads={}
 library.Add({new[1],new[2],hex(5033,64),hidden,'not-an-id'})
 eq(library.revision,revision+1,'one revision for the batch') eq(changedRuns,1,'LibraryChanged once')
 eq(library.entries[new[1]].name,'Named') eq(library.entries[new[2]].name,'Manifest 32')
 eq(library.entries[hex(5033,64)],nil,'a deleted character listed')
 for path,count in pairs(reads) do
  local id=path:match('^mmd_hotloader/library/(%x+)%.json$')
  if id then assert(id==new[1] or id==new[2] or id==hex(5033,64) or id==hidden,'read another model\'s settings: '..path) end
 end
 -- The same entries as a full rebuild.
 local added={[new[1]]=library.entries[new[1]],[new[2]]=library.entries[new[2]]}
 library.Refresh()
 for id,entry in pairs(added) do
  for key,value in pairs(library.entries[id]) do if not istable(value) then eq(entry[key],value,'entry field '..key) end end
 end
 -- Nothing new: no revision, no hook.
 revision=library.revision changedRuns=0
 library.Add({hex(5033,64)}) eq(library.revision,revision,'a revision for nothing') eq(changedRuns,0,'LibraryChanged for nothing')
 -- Prime decodes a new character's manifest at once, and the update that lists it decodes nothing again.
 local primed=put(40) local decodes=0
 local decode=util.JSONToTable
 util.JSONToTable=function(v) if istable(v) and v.vertices then decodes=decodes+1 end return decode(v) end
 library.Prime(primed) eq(decodes,1,'Prime decodes the manifest') eq(changedRuns,0,'Prime changed the library')
 library.Add({primed}) eq(decodes,1,'the update decoded the primed manifest again') eq(library.entries[primed].name,'Manifest 40')
 library.Prime('not-an-id') eq(decodes,1,'Prime of an invalid id')
 util.JSONToTable=decode
else
 error('unknown scenario '..scenario)
end
print('PASS '..scenario)
