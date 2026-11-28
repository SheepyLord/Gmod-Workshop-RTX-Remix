-- A character's identity within its mounted pack survives a new export and a new asset hash (ADR 0278).
local W=mmdhl.workshop
local function token(s)
 if not isstring(s) or s=='' or #s>260 or s:find('[%z\1-\31]') then return end
 return (s:lower():gsub('\\','/'))
end
local function sourceKey(item)
 local source=token(item.source) or token(item.terms and item.terms.file)
 if source then return 'source:'..source end
end
local function modelKey(item)
 local key=item.key
 if isnumber(key) and key>=0 and key<2^53 and key%1==0 then key=string.format('%.0f',key) end
 key=token(key)
 return key and 'key:'..key or sourceKey(item)
end
local function unique(index,key,value)
 if index[key]==nil then index[key]=value elseif index[key]~=value then index[key]=false end
end
-- journal.cpp writes one package or file per line in each generation. Decode only the package
-- records and the few Hotloader manifest rows, in bounded slices. The field journal is 16 MiB.
-- Cache only build IDs and owners. A generation number in the header distinguishes same-second writes.
local function journalOwners()
 local path='native-loader/state.json'
 local size=file.Size(path,'BASE_PATH')
 if not size or size<=0 then return end
 local stream=file.Open(path,'rb','BASE_PATH')
 if not stream then return end
 local header=stream:Read(math.min(size,512)) or ''
 local generation=header:match('"next"%s*:%s*(%d+)')
 if not generation or not header:match('"schema"%s*:%s*1%s*,') then stream:Close() return end
 local stamp=generation..'/'..size..'/'..tostring(file.Time(path,'BASE_PATH'))
 local cache=W.state.packJournal
 if istable(cache) and cache.stamp==stamp and istable(cache.current) and istable(cache.previous) then stream:Close() return cache end
 cache={stamp=stamp,current={},previous={}}
 local group,packages,tail=nil,{},header
 local remaining=size-#header local deadline=SysTime()+.002
 while remaining>0 or #tail>0 do
  local chunk=remaining>0 and stream:Read(math.min(65536,remaining)) or ''
  if not chunk or (remaining>0 and #chunk==0) then stream:Close() return end
  remaining=remaining-#chunk
  local block=tail..chunk
  if remaining==0 then block=block..'\n' end
  local at=1
  while true do
   local last=block:find('\n',at,true) if not last then break end
   local line=block:sub(at,last-1) at=last+1
   local section=line:match('^  "([%w_]+)"%s*:')
   if section=='previous_backup' then stream:Close() W.state.packJournal=cache return cache end
   if section then group=cache[section] packages={} end
   if istable(group) then
    local packageRow=line:find('{"id":',1,true)
    if packageRow or line:find('/data_static/mmdhl/packages/',1,true) then
     local raw=line:match('^%s*({.*})%s*,?%s*$')
     local row=raw and util.JSONToTable(raw)
     if row and isstring(row.id) then
      if row.source=='workshop' and isstring(row.location) then
       local wsid=row.location:lower():gsub('\\','/'):match('/workshop/content/4000/(%d+)/')
       packages[row.id]=wsid and 'ws:'..wsid or false
      elseif row.source=='local' or row.source=='dev_folder' then packages[row.id]='local:'..row.id end
     elseif row and isstring(row.path) then
      local dir,id=row.path:lower():match('^garrysmod/addons/([^/]+)/data_static/mmdhl/packages/(%x+)%.json$')
      local owner=packages[row.package]
      if id and #id==32 then unique(group,id,owner and (owner..'/addon:'..dir) or false) end
     end
    end
   end
  end
  tail=block:sub(at)
  if #tail>1024*1024 then break end
  if SysTime()>=deadline then coroutine.yield() deadline=SysTime()+.002 end
 end
 stream:Close()
end
-- For loose add-ons the loader deploys, the physical add-on folder identifies the pack. The random
-- inner manifest id and the title can both change. Look through the folders once per discovery.
function W.FindPackOwners(packages,origins)
 local journal=journalOwners()
 W.previousOwners=journal and journal.previous or {}
 local owners={}
 local _,dirs=file.Find('addons/*','MOD')
 local budget=SysTime()
 for _,dir in ipairs(dirs or {}) do
  local files=file.Find('addons/'..dir..'/data_static/mmdhl/packages/*.json','MOD')
  for _,name in ipairs(files or {}) do
   local id=name:match('^(%x+)%.json$')
   if packages[id] then unique(owners,id,'addon:'..dir:lower()) end
  end
  if SysTime()-budget>.002 then coroutine.yield() budget=SysTime() end
 end
 for id,origin in pairs(origins) do
  origin.owner=owners[id]
  local recorded=journal and journal.current[id]
  if origin.owner and recorded~=nil then
   origin.owner=recorded and recorded:sub(-#origin.owner-1)=='/'..origin.owner and recorded or false
  end
  if owners[id]==nil and not origin.ambiguous and origin.wsid~='0' and origin.wsid:match('^%d+$') then origin.owner='ws:'..origin.wsid end
 end
end
-- Index both ends before changing any old records. A shared asset or an ambiguous slot cannot
-- establish a succession. Pre-0278 records have only the build id: a surviving sibling identifies
-- that build's owner, and the old Workshop terms independently give its title and source filename.
function W.IndexReplacements()
 local slots,assets,builds,titles={},{},{},{}
 for pid,pack in pairs(W.packages) do
  local owner=W.origins[pid] and W.origins[pid].owner
  if pack.install=='workshop' then unique(titles,pack.title,owner or false) end
  if owner and pack.install=='workshop' then
   slots[owner]=slots[owner] or {}
   for _,item in ipairs(pack.items) do
    if item.kind=='character' then
     local id=item.asset local key=W.Key('character',id) local rec=W.state.assets[key]
     local single=#W.provided[key]==1
     local slot=modelKey(item)
     if slot then unique(slots[owner],slot,single and id or false) end
     local source=sourceKey(item)
     if source and source~=slot then unique(slots[owner],source,single and id or false) end
     if single then
      assets[id]={owner=owner,slot=slot}
      if rec and rec.installed and rec.package and not rec.adopted and not rec.ownBefore
       and (rec.owner==nil or rec.owner==owner) then
       unique(builds,rec.package,owner)
      end
     end
    end
   end
  end
 end
 W.identities=assets
 W.candidates={}
 W.waitingForInstall={}
 local prior,dirty={},false
 local sources
 for key,rec in pairs(W.state.assets) do
  local id=key:match('^character:(%x+)$')
  if id and rec.installed and not rec.ownBefore and not rec.adopted then
   local identity=assets[id]
   if W.provided[key] then
    local slot=identity and identity.slot
    if slot and slots[identity.owner][slot]~=id then slot=nil end
    local owner=identity and identity.owner or false
    if rec.owner~=owner or rec.modelKey~=slot or rec.replacement then
     rec.owner,rec.modelKey,rec.replacement,rec.saveRig=owner,slot,nil,nil dirty=true
    end
   else
    local owner=rec.owner
    local previous=W.previousOwners and W.previousOwners[rec.package]
    if owner==nil and (previous~=nil or builds[rec.package]) then
     local terms=util.JSONToTable(file.Read('mmd_hotloader/terms/'..id..'.json','DATA') or '')
     if terms and terms.origin=='workshop' then
      if previous~=nil then owner=previous
      elseif titles[terms.package]==builds[rec.package] then owner=builds[rec.package] end
      if owner~=nil then rec.owner=owner rec.modelKey=modelKey({terms=terms}) dirty=true end
     end
    end
    local target=owner and slots[owner] and slots[owner][rec.modelKey]
    if target then
     if CLIENT and not sources then sources=mmdhl.library.SourcePaths and mmdhl.library.SourcePaths('character') or {} end
     if sources and sources[id] then rec.ownBefore=true rec.replacement=nil dirty=true
     else
      W.candidates[id]=target
      if not rec.replacement then
       local build=rec.package or owner prior[build]=prior[build] or {}
       unique(prior[build],target,id)
      end
     end
    end
   end
  end
 end
 for id,target in pairs(W.candidates) do
  local old=W.state.assets[W.Key('character',id)]
  local earlier=prior[old.package or old.owner]
  if earlier and earlier[target]==false then W.candidates[id]=nil
  else
   local key=W.Key('character',target)
   if not old.replacement and not old.hidden and W.InCache('character',id) then W.waitingForInstall[target]=true end
   if old.hidden and not W.state.assets[key] then
    local identity=assets[target]
    W.state.assets[key]={hidden=true,installed=true,name=old.name,owner=identity.owner,modelKey=identity.slot}
    old.replacement=target dirty=true
   end
  end
 end
 -- Record ambiguity even on the first install, before one of the duplicate items disappears.
 for id,identity in pairs(assets) do
  if identity.slot and slots[identity.owner][identity.slot]~=id then identity.slot=nil end
 end
 return dirty
end
function W.RecordIdentity(rec,item)
 if item.kind~='character' then return end
 local identity=W.identities and W.identities[item.asset]
 rec.owner,rec.modelKey=identity and identity.owner or false,identity and identity.slot
end
-- Commit only after the new asset passed its install. A failed or interrupted replacement leaves the
-- old model selectable. Old copies with carriers stay addressable by the immutable keys in saves.
function W.ApplyReplacements()
 local dirty=false
 for old,id in pairs(W.candidates or {}) do
  local rec=W.state.assets[W.Key('character',old)]
  local new=W.state.assets[W.Key('character',id)]
  if rec and new and new.installed and not new.pending and not new.hidden and rec.replacement~=id and W.InCache('character',id)
   and (not CLIENT or rec.replacement or new.ownBefore or not mmdhl.library.InheritWorkshopSettings or mmdhl.library.InheritWorkshopSettings(old,id,rec.name,new.name)) then
   rec.replacement=id dirty=true
   W.waitingForInstall[id]=nil
   if CLIENT and mmdhl.UnregisterAsset then mmdhl.UnregisterAsset(old) end
  end
 end
 return dirty
end
function W.Replacement(id)
 local rec=W.state.assets[W.Key('character',id)]
 return rec and rec.replacement
end
-- A save may be offline or shared by another player. Its on-disk carrier is evidence that it can
-- name this exact asset, even after approved.json pruned that size. Inspect the rigs once for a
-- batch of retired assets, over several frames. Keep a witness so later starts need just an Exists.
local checking
function W.CheckSaveRigs(wanted,done)
 if checking or not next(wanted) then return end
 checking=true
 local _,dirs=file.Find('mmd_hotloader/rigs/*','DATA')
 local index=1
 local function step()
  local deadline=SysTime()+.002
  while next(wanted) and dirs and dirs[index] do
   local key=dirs[index] index=index+1
   if key:match('^%x+$') and (#key==32 or #key==64) then
    local root='mmd_hotloader/rigs/'..key..'/'
    local raw=file.Read(root..'rig.json','DATA')
    local rig=raw and util.JSONToTable(raw)
    if rig and wanted[rig.asset] and rig.key==key and file.Exists(root..'carrier.gma','DATA') then
     wanted[rig.asset].saveRig=key wanted[rig.asset]=nil
    end
   end
   if SysTime()>=deadline then timer.Simple(0,step) return end
  end
  checking=nil done(wanted)
 end
 step()
end
