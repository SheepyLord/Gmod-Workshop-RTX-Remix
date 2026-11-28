-- ADR 0255: the Model Hotloader installs a Workshop package's models several at once. workshop.lua (and, for one
-- scenario, library.lua) is loaded whole in the client realm under LuaJIT; the native transfer and asset check, the
-- disk, timers, hooks and frames are instrumented. One scenario per run; prints PASS <scenario>.
local source,scenario=unpack(arg)
function include(path) return dofile(source..'/'..path:match('([^/]+)$')) end
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
 W.packages={[package.id]=package} W.origins={[package.id]={pathId='GAME',title='Pack',wsid='1',workshop=true,owner='ws:1'}}
 W.provided={} for _,item in ipairs(package.items) do W.provided[W.Key(item.kind,item.asset)]={package.id} end
end
local function run(limit)
 for _=1,limit do tick() if not mmdhl.workshop.Busy() and next(named)==nil then return frame end end
 error('still installing after '..limit..' frames')
end
-- ADR 0278: a model installed from an earlier build of the package. Its files are on disk as that build had them
-- (`old` maps a path to the hash it had there; the size stays), known good at time 1, and its record names the
-- package it came from and, unless `legacy`, the hashes that build listed for its rewritten files.
local function installedEarlier(asset,old,record)
 local times,sums={}, {}
 for _,path in ipairs(modelFiles[asset]) do
  local f=package.files[path] local sha=old[path] or f.sha256
  disk['mmd_hotloader/'..path]={size=f.size,sha=sha,time=1} times[path]=1
  if path:match('^assets/') then sums[path]=sha end
 end
 local rec={installed=true,times=times,name='Model',package=record.package or hex(2,32)}
 local manifest='mmd_hotloader/'..modelFiles[asset][1]
 text[manifest]=text[manifest] or {}
 text[manifest].sourceHash=sums[modelFiles[asset][2]]
 if not record.legacy then rec.sums=sums end
 if record.pending then rec.pending=true end
 text[StatePath]=text[StatePath] or {version=1,assets={}}
 text[StatePath].assets['character:'..asset]=rec
end
local function record(asset) return lastState and lastState.assets['character:'..asset] end
local function sumsOf(asset)
 local out={} for _,path in ipairs(modelFiles[asset]) do if path:match('^assets/') then out[path]=package.files[path].sha256 end end return out
end
local function sameSums(a,b)
 if not istable(a) or not istable(b) then return false end
 for k,v in pairs(a) do if b[k]~=v then return false end end
 for k in pairs(b) do if a[k]==nil then return false end end
 return true
end
local function noticed(text) for _,n in ipairs(notices) do if n==text then return true end end return false end
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
elseif scenario=='update_same_size' or scenario=='update_in_use' then
 -- ADR 0278: the package's new build rewrote one model's model.bin in place at the same size (vertices moved), so
 -- every file has the size the package lists and its time when last known good. Sizes and times alone say installed;
 -- the record's hashes say the package changed it. The model is installed again: model.bin moves, the rest is found
 -- in place. Loaded in this session already (update_in_use), it is shown as updated only after a restart, and the
 -- closing notice says so.
 local a=addModel(1,{1,2}) local b=addModel(2,{3})
 local model=modelFiles[a][2]
 installedEarlier(a,{[model]='old-model'},{package=hex(2,32)})
 installedEarlier(b,{},{package=hex(2,32)})
 local loaded={}
 if scenario=='update_in_use' then loaded[a]=true end
 native.AssetInfo=function(id) return loaded[id] and {name='loaded'} or nil end
 load() provide()
 mmdhl.workshop.Reconcile(true)
 assert(mmdhl.workshop.Busy(),'the updated model was not queued')
 eq(record(a).pending,true,'the update recorded before any file moved')
 run(20000)
 eq(stats.begins[model],1,'model.bin replaced') eq(table.Count(stats.begins),1,'files moved')
 eq(disk['mmd_hotloader/'..model].sha,package.files[model].sha256,'the new model.bin')
 eq(#installedNames,1,'models installed again') eq(installedNames[1],'Model 1','the updated model')
 local rec=record(a)
 assert(sameSums(rec.sums,sumsOf(a)),'the new build\'s hashes recorded') eq(rec.pending,nil,'pending after the update')
 eq(rec.package,package.id,'the package recorded') eq(rec.installed,true,'installed')
 assert(sameSums(record(b).sums,sumsOf(b)),'the unchanged model\'s hashes')
 eq(stats.matches[modelFiles[b][1]],nil,'the unchanged model hashed')
 eq(noticed('workshop.restart_to_update'),scenario=='update_in_use','the restart notice')
 eq(#errors,0,'errors: '..table.concat(errors,' | '))
elseif scenario=='unchanged' then
 -- A model whose record holds the package's hashes and whose files kept their times: no file is read.
 local a=addModel(1,{1,2})
 installedEarlier(a,{},{package=package.id})
 load() provide()
 mmdhl.workshop.Reconcile(true)
 assert(not mmdhl.workshop.Busy(),'an up-to-date model queued')
 run(2000)
 eq(table.Count(stats.matches),0,'files hashed') eq(table.Count(stats.begins),0,'files moved')
elseif scenario=='legacy_same_package' then
 -- A record from before ADR 0278 that this very package installed: its files are this package's, so the hashes are
 -- recorded at once, without reading a file.
 local a=addModel(1,{1})
 installedEarlier(a,{},{package=package.id,legacy=true})
 load() provide()
 mmdhl.workshop.Reconcile(true)
 assert(not mmdhl.workshop.Busy(),'queued')
 run(2000)
 eq(table.Count(stats.matches),0,'files hashed')
 assert(sameSums(record(a).sums,sumsOf(a)),'hashes adopted')
elseif scenario=='legacy_other_package' or scenario=='legacy_other_stale' or scenario=='legacy_other_binary' then
 -- A record from before ADR 0278 that an earlier build installed (every update gives a package a new id): its
 -- manifest.json, which names the source model's hash, is hashed once. If it matches, the package's hashes are the
 -- model's (legacy_other_package); if not, the model is installed again from that file (legacy_other_stale).
 local a=addModel(1,{1,2})
 local manifest=modelFiles[a][1]
 local old=scenario=='legacy_other_stale' and {[manifest]='old-manifest'} or scenario=='legacy_other_binary' and {[modelFiles[a][2]]='old-binary'} or {}
 installedEarlier(a,old,{package=hex(2,32),legacy=true})
 load() provide()
 mmdhl.workshop.Reconcile(true)
 run(20000)
 eq(stats.matches[manifest],scenario=='legacy_other_binary' and 2 or 1,'manifest.json hashed')
 eq(stats.matches[modelFiles[a][2]] or 0,scenario=='legacy_other_package' and 0 or 1,'model.bin hashed')
 for _,path in ipairs(modelFiles[a]) do if path:match('^textures/') and scenario=='legacy_other_package' then eq(stats.matches[path],nil,'texture hashed') end end
 assert(sameSums(record(a).sums,sumsOf(a)),'hashes recorded')
 if scenario=='legacy_other_stale' then
  eq(stats.begins[manifest],1,'manifest.json replaced') eq(table.Count(stats.begins),1,'files moved')
  eq(record(a).pending,nil,'pending') eq(record(a).package,package.id,'package')
 elseif scenario=='legacy_other_binary' then eq(stats.begins[modelFiles[a][2]],1,'model.bin replaced') eq(table.Count(stats.begins),1)
 else eq(table.Count(stats.begins),0,'files moved') end
 eq(#errors,0,'errors: '..table.concat(errors,' | '))
elseif scenario=='resume' then
 -- An update a closed game left part way: its record says so (pending), and the next scan installs it whatever the
 -- hashes say; the update's files found in place are not moved again.
 local a=addModel(1,{1})
 installedEarlier(a,{},{package=package.id,pending=true})
 load() provide()
 mmdhl.workshop.Reconcile(true)
 assert(mmdhl.workshop.Busy(),'the interrupted update was not resumed')
 run(20000)
 eq(table.Count(stats.begins),0,'files moved') eq(record(a).pending,nil,'pending') eq(#installedNames,1,'installed')
elseif scenario=='server_update' then
 -- A dedicated server installs into its own cache and keeps records of times and, now, the hashes: the same update
 -- is installed again before the model is approved again.
 local a=addModel(1,{1})
 local model=modelFiles[a][2]
 installedEarlier(a,{[model]='old-model'},{package=hex(2,32)})
 text[StatePath].assets['character:'..a].installed=nil
 SERVER,CLIENT=true,false
 game={SinglePlayer=function() return false end,IsDedicated=function() return true end}
 load() provide()
 mmdhl.workshop.Reconcile()
 assert(mmdhl.workshop.Busy(),'the server did not install the update')
 run(20000)
 eq(stats.begins[model],1,'model.bin replaced') eq(table.Count(stats.begins),1,'files moved')
 assert(sameSums(record(a).sums,sumsOf(a)),'the server recorded the hashes') eq(record(a).pending,nil,'pending')
 eq(#errors,0,'errors: '..table.concat(errors,' | '))
elseif scenario:match('^supersede_') then
 -- Two real reconciliation passes with different build ids and asset ids. Both models have the
 -- same source and different library names; a second pack and a local import use that source too.
 local old=addModel(1,{1}) local sibling=addModel(2,{2}) local other=addModel(3,{3}) local own=addModel(4,{4})
 local oldBuild=package.id
 local first,siblingItem,otherItem=unpack(package.items)
 local function slot(item,name)
  item.terms={file='Gym.pmx'} item.name=name
  if scenario=='supersede_key' then item.key='characters/172' end
 end
 slot(first,'Old name') slot(otherItem,'Old name') siblingItem.terms={file='Other.pmx'}
 package.items={first,siblingItem}
 local legacy=scenario=='supersede_legacy' or scenario=='supersede_field'
 local foreign={id=hex(8,32),title=legacy and 'Other pack' or 'Pack',install='workshop',items={otherItem},files=package.files}
 local function mount()
  provide() local W=mmdhl.workshop
  W.packages[foreign.id]=foreign W.origins[foreign.id]={owner='addon:other',wsid='0',pathId='GAME'}
  W.provided[W.Key('character',other)]={foreign.id}
 end
 local dirs={}
 file.Find=function(pattern)
  if pattern=='mmd_hotloader/assets/*' then
   local ids={} for _,id in ipairs(models) do if file.Exists('mmd_hotloader/assets/'..id..'/manifest.json','DATA') then ids[#ids+1]=id end end
   return {},ids
  end
  if pattern=='mmd_hotloader/rigs/*' then return {},dirs end
  return {},{}
 end
 concommand={Add=noop} cvars={AddChangeCallback=noop}
 CreateClientConVar=function() return {GetBool=function() return false end} end
 native.GetSourcePaths=function() return {[own]={source='Gym.pmx'}} end
 native.DeleteAssets=function(ids)
  if istable(ids) then for _,id in ipairs(ids) do
   for _,p in ipairs(modelFiles[id]) do if p:match('^assets/') then file.Delete('mmd_hotloader/'..p) end end
  end end
  return {pendingFiles=0}
 end
 mmdhl.terms={Forget=noop,SaveFromPackage=function(_,id,terms,title)
  text['mmd_hotloader/terms/'..id..'.json']={file=terms.file,package=title,origin='workshop'}
 end}
 mmdhl.assets={} mmdhl.rigs={} mmdhl.UnregisterAsset=noop net.WriteString=noop
 -- The native check has decoded the manifest. Supply its JSON alongside the instrumented bytes.
 for _,id in ipairs(models) do text['mmd_hotloader/assets/'..id..'/manifest.json']={name='Old name'} end
 local beforeOwn={name='Old name',favorite=true}
 text['mmd_hotloader/library/'..own..'.json']=beforeOwn
 mmdhl.library=nil dofile(source..'/library.lua')
 load() mount() local W=mmdhl.workshop
 W.Reconcile(true) run(20000)
 assert(W.state.assets[W.Key('character',old)].installed,'old did not install')
 local new=addModel(5,{5}) local updated=package.items[#package.items]
 slot(updated,'New name')
 if scenario=='supersede_key' then updated.terms.file='Renamed.pmx' end
 text['mmd_hotloader/assets/'..new..'/manifest.json']={name='New name'}
 local rk=hex(323,32)
 if scenario=='supersede_save' then
  dirs={rk} text['mmd_hotloader/rigs/'..rk..'/rig.json']={key=rk,asset=old}
  text['mmd_hotloader/rigs/'..rk..'/carrier.gma']=true
 end
 if scenario=='supersede_owned' then W.state.assets[W.Key('character',old)].ownBefore=true end
 if scenario=='supersede_demo' then W.state.assets[W.Key('character',old)].adopted=true end
 if scenario=='supersede_settings' then text['mmd_hotloader/library/'..old..'.json']={name='My character',favorite=true,folder='Favourites'} end
 if scenario=='supersede_failure' then checkMode[new]='invalid' end
 if scenario=='supersede_private' then native.GetSourcePaths=function() return {[old]={source='Gym.pmx'},[own]={source='Gym.pmx'}} end end
 if legacy or scenario=='supersede_legacy_collision' or scenario=='supersede_previous' then
  for _,rec in pairs(W.state.assets) do rec.owner=nil rec.modelKey=nil rec.sums=nil end
 end
 package.id=hex(2,32) package.items={updated,siblingItem}
 if scenario=='supersede_previous' then
  -- No sibling or unique title. The loader recorded exactly which pack owned the old export.
  W.previousOwners={[oldBuild]='ws:1'} package.items={updated}
 end
 if scenario=='supersede_field' then
  -- The reported case: both builds finished under the old Hotloader before this code ever ran.
  text[StatePath]=table.Copy(W.state)
  installedEarlier(new,{},{package=package.id,legacy=true})
  W.state=util.JSONToTable(text[StatePath])
  text['mmd_hotloader/library/'..new..'.json']={name=updated.name}
 end
 if scenario=='supersede_ambiguous' then siblingItem.terms.file='Gym.pmx' end
 if scenario=='supersede_shared' then foreign.items={otherItem,first} end
 mount()
 if scenario=='supersede_shared' then W.provided[W.Key('character',old)]={foreign.id} end
 if scenario=='supersede_save' then hook.Add('MMDHL.LibraryChanged','noDuplicate',function()
  assert(not (mmdhl.library.entries[old] and mmdhl.library.entries[new]),'both revisions were offered together')
 end) end
 W.Reconcile(true)
 if scenario=='supersede_field' then eq(W.Replacement(old),new,'existing duplicate survived the first scan')
 else eq(W.Replacement(old),nil,'retired before new asset check') end
 run(20000) mmdhl.library.Refresh()
 local lib=mmdhl.library.entries
 assert(lib[other] and lib[own],'a different pack or personal import was lost')
 eq(text['mmd_hotloader/library/'..own..'.json'],beforeOwn,'own settings rewritten')
 if scenario=='supersede_owned' or scenario=='supersede_private' or scenario=='supersede_shared' or scenario=='supersede_demo' then
  assert(lib[old] and lib[new],'a still-provided or personally owned model was retired') eq(W.Replacement(old),nil)
 elseif scenario=='supersede_ambiguous' or scenario=='supersede_legacy_collision' then
  eq(W.Replacement(old),nil,'ambiguous source or legacy owner matched')
 elseif scenario=='supersede_failure' then
  eq(W.Replacement(old),nil,'failed successor adopted') assert(lib[old],'failure removed last good character')
  checkMode[new]=nil W.Reconcile(true) run(20000) eq(W.Replacement(old),new,'failed install could not retry')
 else
  eq(W.Replacement(old),new,'replacement') eq(lib[old],nil,'old library entry')
  if scenario=='supersede_settings' then
   eq(lib[new].name,'My character') eq(lib[new].settings.favorite,true) eq(lib[new].settings.folder,'Favourites')
  else eq(lib[new].name,'New name') end
  eq(W.InCache('character',old),scenario=='supersede_save','obsolete files retained only for the saved carrier')
  if scenario=='supersede_save' then eq(W.state.assets[W.Key('character',old)].saveRig,rk,'save carrier') end
  W.Reconcile(true) run(20000) eq(W.Replacement(old),new,'second reconciliation')
  if scenario=='supersede_rollback' then
   package.id=oldBuild package.items={first,siblingItem}
   -- A later installation of the original build uses the same cached identity again.
   text['mmd_hotloader/assets/'..old..'/manifest.json']={name='Old name'}
   mount() W.Reconcile(true) run(20000)
   eq(W.Replacement(old),nil,'rollback left a cycle') eq(W.Replacement(new),old,'rollback successor')
   mmdhl.library.Refresh() assert(mmdhl.library.entries[old] and not mmdhl.library.entries[new],'rollback library')
  end
 end
elseif scenario=='pack_owners' or scenario=='journal_owners' then
 load() local W=mmdhl.workshop local id=package.id local id2=hex(2,32) local id3=hex(3,32)
 file.Find=function(pattern,where)
  eq(where,'MOD')
  if pattern=='addons/*' then return {},{'mmdhl_test','another'} end
  if pattern:find('mmdhl_test',1,true) then return {id..'.json',id3..'.json'},{} end
  return {id3..'.json'},{}
 end
 local priorId=hex(4,32)
 if scenario=='journal_owners' then
  local journalPath='native-loader/state.json' local decoded={}
  local function row(raw,values) decoded[raw]=values return '      '..raw end
  local function pkg(owner)
   local v={id='fixture',source='workshop',location='steamapps/workshop/content/4000/'..owner..'/test.gma'}
   return row('{"id": "fixture", "source": "workshop", "location": "'..v.location..'"}',v)
  end
  local function entry(build)
   local p='garrysmod/addons/mmdhl_test/data_static/mmdhl/packages/'..build..'.json'
   return row('{"path": "'..p..'", "package": "fixture"}',{path=p,package='fixture'})
  end
  -- Different Workshop items successively deploy the same folder and outer package id.
  local journal=table.concat({'{','  "schema": 1,','  "next": 7,','  "current": {','    "packages": [',pkg('234'),'    ],',
   '    "files": [',entry(id),'    ]','  },','  "previous": {','    "packages": [',pkg('123'),'    ],',
   '    "files": [',entry(priorId),'    ]','  },','  "previous_backup": "",','  "pending": null','}'},'\n')
  local decode=util.JSONToTable
  util.JSONToTable=function(raw) return decoded[raw] or decode(raw) end
  local size=file.Size file.Size=function(p,where) if p==journalPath and where=='BASE_PATH' then return #journal end return size(p,where) end
  file.Open=function(p,mode,where)
   eq(p,journalPath) eq(where,'BASE_PATH') local at=1
   return {Read=function(_,n) local part=journal:sub(at,at+n-1) at=at+#part return part end,Close=noop}
  end
 end
 local origins={[id]={wsid='0'},[id2]={wsid='123'},[id3]={wsid='0'}}
 local co=coroutine.create(function() W.FindPackOwners({[id]=true,[id2]=true,[id3]=true},origins) end)
 repeat assert(coroutine.resume(co)) until coroutine.status(co)=='dead'
 eq(origins[id].owner,scenario=='journal_owners' and 'ws:234/addon:mmdhl_test' or 'addon:mmdhl_test')
 eq(origins[id2].owner,'ws:123') eq(origins[id3].owner,false,'ambiguous folder')
 if scenario=='journal_owners' then eq(W.previousOwners[priorId],'ws:123/addon:mmdhl_test','previous owner') end
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
