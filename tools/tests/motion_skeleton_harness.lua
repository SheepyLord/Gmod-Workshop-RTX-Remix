-- ADR 0259: the Character Motion Importer's build models (sv_skeletons.lua) under LuaJIT, with sh_core.lua's
-- file names, sv_cache.lua's expression mappings and an in-memory DATA folder: a Model Hotloader character's carriers
-- share their builds across sizes, imports and updates, and only when a build would be the same. One scenario per run;
-- prints PASS <scenario>.
-- usage: luajit motion_skeleton_harness.lua <scenario> <the add-on's lua/mmd_vmd_npc folder>
local scenario,folder=arg[1],arg[2]
SERVER,CLIENT=true,false
local function noop() end
local function check(ok,why) if not ok then error('FAIL '..scenario..': '..why,2) end end

-- ---- JSON (util.TableToJSON / JSONToTable) ----
local json={}
function json.encode(v)
 local t=type(v)
 if t=='string' then return '"'..v:gsub('[%c"\\]',function(c) return string.format('\\u%04x',c:byte()) end)..'"' end
 if t=='number' then return v==math.floor(v) and math.abs(v)<1e15 and string.format('%d',v) or string.format('%.17g',v) end
 if t=='boolean' then return tostring(v) end
 if t~='table' then return 'null' end
 if #v>0 or next(v)==nil then local out={} for i=1,#v do out[i]=json.encode(v[i]) end return '['..table.concat(out,',')..']' end
 local keys={} for k in pairs(v) do keys[#keys+1]=tostring(k) end table.sort(keys)
 local out={} for _,k in ipairs(keys) do out[#out+1]=json.encode(k)..':'..json.encode(v[k]~=nil and v[k] or v[tonumber(k)]) end
 return '{'..table.concat(out,',')..'}'
end
function json.decode(s)
 local i=1
 local function ws() i=s:find('[^%s]',i) or #s+1 end
 local value
 local function str()
  local out={} i=i+1
  while true do
   local c=s:sub(i,i)
   if c=='' then error('unterminated string') end
   if c=='"' then i=i+1 return table.concat(out) end
   if c=='\\' then
    local e=s:sub(i+1,i+1)
    if e=='u' then out[#out+1]=string.char(tonumber(s:sub(i+2,i+5),16)%256) i=i+6
    else out[#out+1]=({n='\n',t='\t',r='\r',b='\b',f='\f'})[e] or e i=i+2 end
   else out[#out+1]=c i=i+1 end
  end
 end
 value=function()
  ws() local c=s:sub(i,i)
  if c=='{' then i=i+1 local t={} ws() if s:sub(i,i)=='}' then i=i+1 return t end
   while true do ws() local k=str() ws() i=i+1 t[k]=value() ws() local d=s:sub(i,i) i=i+1 if d=='}' then return t end end end
  if c=='[' then i=i+1 local t={} ws() if s:sub(i,i)==']' then i=i+1 return t end
   while true do t[#t+1]=value() ws() local d=s:sub(i,i) i=i+1 if d==']' then return t end end end
  if c=='"' then return str() end
  if s:sub(i,i+3)=='true' then i=i+4 return true end
  if s:sub(i,i+4)=='false' then i=i+5 return false end
  if s:sub(i,i+3)=='null' then i=i+4 return nil end
  local n=s:match('^-?[%d%.eE+-]+',i) if not n then error('bad JSON at '..i) end i=i+#n return tonumber(n)
 end
 local ok,result=pcall(value) if ok then return result end
 return nil
end

-- ---- the game ----
local clock=1000
function CurTime() return clock end RealTime=CurTime
-- Each call takes 2 ms, so a migration step with a 3 ms budget reads two rigs.
local spent=0
function SysTime() spent=spent+0.002 return clock+spent end
function isnumber(v) return type(v)=='number' end function istable(v) return type(v)=='table' end
function isstring(v) return type(v)=='string' end function isfunction(v) return type(v)=='function' end
function isbool(v) return type(v)=='boolean' end
function IsValid(e) return type(e)=='table' and e.valid~=false end
function Vector(x,y,z) return {x=x or 0,y=y or 0,z=z or 0} end function Angle(p,y,r) return {p=p or 0,y=y or 0,r=r or 0} end
function math.Clamp(v,a,b) return math.max(a,math.min(b,v)) end
function string.Trim(s) return (tostring(s):gsub('^%s*(.-)%s*$','%1')) end
function string.Replace(s,a,b) return (s:gsub(a:gsub('%p','%%%0'),(b:gsub('%%','%%%%')))) end
function string.GetFileFromFilename(p) return p:match('[^/]*$') end
function string.GetPathFromFilename(p) return p:match('^(.*/)') or '' end
local printed={}
local realPrint=print
print=function(...) local parts={} for i=1,select('#',...) do parts[#parts+1]=tostring((select(i,...))) end printed[#printed+1]=table.concat(parts,'\t') end
local errors={}
function ErrorNoHalt(text) errors[#errors+1]=tostring(text) end
local hooks,timers,named={}, {}, {}
hook={Add=function(event,id,fn) hooks[event]=hooks[event] or {} hooks[event][id]=fn end,Remove=noop,
 Run=function(event,...) for _,fn in pairs(hooks[event] or {}) do fn(...) end end}
timer={Simple=function(delay,fn) timers[#timers+1]={at=clock+(delay or 0),fn=fn} end,
 Create=function(name,delay,_,fn) named[name]={at=clock+delay,delay=delay,fn=fn} end,Remove=function(name) named[name]=nil end,
 Exists=function(name) return named[name]~=nil end}
local function tick(seconds)
 clock=clock+(seconds or 0)
 local due=timers timers={} for _,t in ipairs(due) do if t.at<=clock then t.fn() else timers[#timers+1]=t end end
 for name,t in pairs(named) do if t.at<=clock then t.at=clock+math.max(t.delay,0.015) t.fn() end end
end
-- The DATA folder: path -> text; times for file.Time; a glob in the last part of a Find path.
local disk,times={}, {}
local reads=0
local function glob_pattern(glob) return '^'..glob:gsub('[%^%$%(%)%%%.%[%]%+%-%?]','%%%0'):gsub('%*','.*')..'$' end
file={Read=function(p) reads=reads+1 return disk[p] end,
 Write=function(p,v) disk[p]=v times[p]=clock end,
 Exists=function(p) return disk[p]~=nil end,
 Delete=function(p) disk[p]=nil times[p]=nil end,
 Rename=function(a,b) if disk[a]==nil or disk[b]~=nil then return false end disk[b]=disk[a] times[b]=times[a] disk[a]=nil times[a]=nil return true end,
 CreateDir=noop,Size=function(p) return disk[p] and #disk[p] or -1 end,Time=function(p) return disk[p] and (times[p] or 1) or 0 end,
 Find=function(pattern)
  local dir,leaf=pattern:match('^(.*)/([^/]*)$')
  local pat=glob_pattern(leaf)
  local files,dirs,seen={}, {}, {}
  for path in pairs(disk) do
   if path:sub(1,#dir+1)==dir..'/' then
    local rest=path:sub(#dir+2)
    local first=rest:match('^([^/]+)/')
    if first then if not seen[first] and first:match(pat) then seen[first]=true dirs[#dirs+1]=first end
    elseif rest:match(pat) then files[#files+1]=rest end
   end
  end
  table.sort(files) table.sort(dirs)
  return files,dirs
 end}
-- util.CRC: a CRC-32 of the text as decimal digits, as the game's.
local bit=require('bit')
local crcTable={}
for i=0,255 do local c=i for _=1,8 do if bit.band(c,1)==1 then c=bit.bxor(bit.rshift(c,1),0xEDB88320) else c=bit.rshift(c,1) end end crcTable[i]=c end
local function crc32(s) local c=0xFFFFFFFF for i=1,#s do c=bit.bxor(bit.rshift(c,8),crcTable[bit.band(bit.bxor(c,s:byte(i)),0xFF)]) end c=bit.bxor(c,0xFFFFFFFF) if c<0 then c=c+4294967296 end return string.format('%d',c) end
util={CRC=crc32,TableToJSON=function(t) return json.encode(t) end,
 JSONToTable=function(s) local v=type(s)=='string' and json.decode(s) or nil return type(v)=='table' and v or nil end,
 -- Distinct texts give distinct strings (the game's is SHA-256 in hex).
 SHA256=function(s) return 'h'..crc32(s)..'-'..crc32(s:reverse())..'-'..#s end,
 AddNetworkString=noop}

-- ---- the add-on: sh_core (file names), sv_cache (mappings, header index), sv_skeletons ----
local function load_addon()
 hooks,timers,named={}, {}, {}
 MMDVMDNPC=nil mmdhl=nil
 dofile(folder..'/sh_core.lua')
 dofile(folder..'/sv_cache.lua')
 dofile(folder..'/sv_skeletons.lua')
end
local M=function() return MMDVMDNPC end
local S=function() return MMDVMDNPC.Skeletons end

-- ---- carriers: rig manifests as the Hotloader writes them (rig.cpp identify, rig_animation.cpp) ----
local function qmul(a,b)
 local ax,ay,az,aw=a[1],a[2],a[3],a[4] local bx,by,bz,bw=b[1],b[2],b[3],b[4]
 return {aw*bx+ax*bw+ay*bz-az*by,aw*by-ax*bz+ay*bw+az*bx,aw*bz+ax*by-ay*bx+az*bw,aw*bw-ax*bx-ay*by-az*bz}
end
local function qrot(q,v)
 local r=qmul(qmul(q,{v[1],v[2],v[3],0}),{-q[1],-q[2],-q[3],q[4]}) return {r[1],r[2],r[3]}
end
local function axis(x,y,z,deg) local h=math.rad(deg)/2 local s=math.sin(h) local n=math.sqrt(x*x+y*y+z*z) return {x/n*s,y/n*s,z/n*s,math.cos(h)} end
-- A small humanoid: name, parent (0-based), offset from the parent in PMX units, local rotation.
local TEMPLATE={
 {'ValveBiped.Bip01_Pelvis',-1,{0,0.1,10},axis(0,0,1,90)},
 {'ValveBiped.Bip01_Spine',0,{0,0,1.2},axis(1,0,0,5)},
 {'ValveBiped.Bip01_Spine1',1,{0,0.1,1.5},axis(1,0,0,-3)},
 {'ValveBiped.Bip01_Head1',2,{0,0,4},axis(0,1,0,10)},
 {'ValveBiped.Bip01_L_Thigh',0,{1,0,-0.5},axis(0,1,0,175)},
 {'ValveBiped.Bip01_R_Thigh',0,{-1,0,-0.5},axis(0,1,0,185)},
 {'ValveBiped.Bip01_L_Calf',4,{0,0,4.2},axis(1,0,0,2)},
}
local MORPHS={{name='blink',original='まばたき',mmd=0,native=0},{name='smile',original='笑い',mmd=1,native=1},{name='a',original='あ',mmd=2,native=-1}}
local function hex(seed,len) local out={} local x=seed*7919 for i=1,len do x=(x*1103515245+12345)%2147483648 out[i]=string.format('%x',math.floor(x/65536)%16) end return table.concat(out) end
-- o: seed (the key), file, name, scale, role, origin, asset, template edits, morphs, extra fields.
local function make_rig(o)
 local scale=o.scale or 3.2365598678588867
 local origin=o.origin==nil and 2.4000000953674316 or o.origin
 local template={} for i,b in ipairs(o.template or TEMPLATE) do template[i]={b[1],b[2],{b[3][1],b[3][2],b[3][3]},{b[4][1],b[4][2],b[4][3],b[4][4]}} end
 if o.edit then o.edit(template) end
 local bones,world={}, {}
 for i,b in ipairs(template) do
  local parent=b[2]
  local rot,pos
  if parent<0 then rot=b[4] pos={b[3][1]*scale,b[3][2]*scale,b[3][3]*scale+origin}
  else local w=world[parent+1] rot=qmul(w.rot,b[4]) local d=qrot(w.rot,{b[3][1]*scale,b[3][2]*scale,b[3][3]*scale}) pos={w.pos[1]+d[1],w.pos[2]+d[2],w.pos[3]+d[3]} end
  if o.noise then rot={rot[1]+o.noise,rot[2],rot[3],rot[4]} end
  world[i]={rot=rot,pos=pos}
  bones[i]={name=b[1],parent=parent,mmd=i-1,physics=i<=3 and i-1 or -1,mmdAliases={},rotation=rot,position=pos}
 end
 local reference={}
 for i,b in ipairs(template) do
  -- Bones of the profile's skeleton keep its offsets; the others the fitted ones.
  local donor=i<=4 and {0.5*i,-0.25*i,1.5+i} or {b[3][1]*scale,b[3][2]*scale,b[3][3]*scale}
  reference[i]={rotation=b[4],position=donor}
 end
 local key=hex(o.seed or 1,32)
 local rig={
  version=3,generator=o.generator or 31,key=key,model='models/mmd/'..key:sub(1,16)..'/'..(o.file or 'lycia')..'.mdl',
  asset=o.asset or hex((o.seed or 1)+7,64),name=o.name or 'Lycia',role=o.role or 'citizen',scale=scale,scaleMultiplier=scale/3.2365598678588867,
  sourceUnitsPerPmx=scale,actorOrigin=origin,meshYaw=90,referenceYaw=90,
  jointFrameConvention='SCMI fitted limb frames; translation-only animation proportions',
  nativeFlexCount=2,morphs=o.morphs or MORPHS,bones=bones,
  animation={profile=o.profile or 'citizen_female',includes={'models/humans/female_gestures.mdl','models/humans/female_postures.mdl'},
   ikChains={{name='rhand',type=1,links={{bone='ValveBiped.Bip01_Spine',knee={0.707,0.707,0}}}}},ikLocks={0,1,2,3},poseParameters={},
   reference=reference,attachments={{bone='ValveBiped.Bip01_Head1',name='eyes',position={o.eyes or 2.04,-3.5,0},rotation={0,0,0,1}}},
   source='models/Humans/Group01/Female_01.mdl',sourceHash=o.sourceHash or 'abc'},
  materials={{name=o.material or 'face',path='mmd/'..key:sub(1,16)..'/face'}},bodies={{bone=0,center={0,0,0}}},
 }
 if o.extra then for k,v in pairs(o.extra) do rig[k]=v end end
 return rig
end
local function install(rig) disk['mmd_hotloader/rigs/'..rig.key..'/rig.json']=util.TableToJSON(rig) return rig.model end
local function uninstall(rig) disk['mmd_hotloader/rigs/'..rig.key..'/rig.json']=nil end
local OPTS={}
-- A built file for a model, named as sv_commands' finalize_build names it (BuiltPath of the model).
local function build(motion,model,builtOn)
 local path=M().BuiltPath(motion,model,OPTS)
 disk[path]=util.TableToJSON({format=M().BuiltFormat,motion_id=motion,model=M().BuildModelKey(model),built_on=builtOn,frames={}})
 times[path]=clock
 M().NoteBuildModel(model)
 return path
end
local function ids(model) local out={} for id in pairs(M().BuiltMotionIDs(model,OPTS)) do out[#out+1]=id end table.sort(out) return table.concat(out,',') end
-- The old name of a model's build, before ADR 0259 (BuiltTail of the model itself).
local function old_name(motion,model)
 return M().BuiltRoot..'/'..motion..'_'..M().SafeModelName(model)..'_'..util.CRC(string.lower(model))..'_tw0_ht0_eye0_sp0_fm2'..M().CacheExtension
end

load_addon()
-- No migration work in these scenarios unless they ask for it (an empty DATA folder: nothing to adopt).
S().Index().migrated=true

if scenario=='resize' then
 -- The user's report of 2026-11-22: a character resized gets a new carrier; its builds are found again.
 local A=install(make_rig{seed=11,scale=3.2365598678588867})
 local B=install(make_rig{seed=12,scale=3.8838718414306640})
 local C=install(make_rig{seed=13,scale=3.2365598678588867,edit=function(t) t[4][4]=axis(0,1,0,10.5) end})
 check(A~=B and A~=C,'the carriers share a path')
 -- Before any build each carrier is its own build model.
 check(M().BuildModelKey(A)==A and M().BuildModelKey(B)==B,'a carrier without builds took another name')
 local path=build('dance',A)
 check(S().Index().entries[A:lower()]~=nil,'the first build did not keep its build model')
 check(M().BuildModelKey(B)==A,'the resized carrier did not find the build model: '..tostring(M().BuildModelKey(B)))
 check(M().BuiltPath('dance',B,OPTS)==path,'the resized carrier looks under another name')
 check(ids(B)=='dance','the resized carrier lists no built motion: '..ids(B))
 check(M().SameBuildModel(A,B) and M().SameBuildModel(B,A),'the resized carrier does not accept the build')
 -- A head turned half a degree is another skeleton: its builds are its own.
 check(M().BuildModelKey(C)==C and ids(C)=='','a different skeleton took the builds')
 check(not M().SameBuildModel(A,C),'a different skeleton accepts the build')
 -- Float noise of a fit at another size (a millionth) is the same skeleton; a thousandth is not.
 local D=install(make_rig{seed=14,scale=4.1,noise=1e-6})
 local E=install(make_rig{seed=15,scale=4.1,noise=1e-3})
 check(M().BuildModelKey(D)==A,'float noise split the skeleton')
 check(M().BuildModelKey(E)==E,'a changed rotation matched')
 -- The build model's members are the carriers that found it this session.
 local members=table.concat(M().BuildModelMembers(A),',')
 check(members==table.concat({A,B,D},',') or members==table.concat({A,D,B},','),'members: '..members)
 -- A model the Hotloader did not make keeps its own name.
 local alyx='models/player/alyx.mdl'
 check(M().BuildModelKey(alyx)==alyx and M().BuiltPath('dance',alyx,OPTS)==old_name('dance',alyx),'a Source model changed its name')
elseif scenario=='reimport' then
 -- A new import (a new asset), new materials or attachments, another display name: the same skeleton.
 local A=install(make_rig{seed=21})
 build('dance',A)
 local B=install(make_rig{seed=22,asset=string.rep('b',64),name='Lycia 2',material='body',eyes=1.6,sourceHash='def',generator=32})
 check(M().BuildModelKey(B)==A and ids(B)=='dance','a re-import lost the builds')
 -- Different morphs (the flex ids a build drives), another NPC profile, or another role: their own builds.
 local morphs={{name='blink',original='まばたき',mmd=0,native=0},{name='smile',original='笑い',mmd=2,native=1},{name='a',original='あ',mmd=1,native=-1}}
 local C=install(make_rig{seed=23,morphs=morphs})
 local D=install(make_rig{seed=24,profile='combine_female'})
 local E=install(make_rig{seed=25,role='player',profile='player_female'})
 local F=install(make_rig{seed=26,edit=function(t) t[8]={'ValveBiped.Bip01_R_Calf',5,{0,0,4.2},axis(1,0,0,2)} end})
 for _,model in ipairs({C,D,E,F}) do
  check(M().BuildModelKey(model)==model and ids(model)=='','a carrier with another skeleton took the builds: '..model)
 end
 -- Reference offsets: the profile's own bones keep them, fitted ones scale; anything else is another skeleton.
 local G=install(make_rig{seed=27})
 local rigH=make_rig{seed=28}
 rigH.animation.reference[1].position={9,9,9}
 local H=install(rigH)
 check(M().BuildModelKey(G)==A,'an identical carrier did not match')
 check(M().BuildModelKey(H)==H,'a changed Reference offset matched')
elseif scenario=='persist' then
 -- The next session: the build model's numbers are on disk, so carriers match after its rig is gone.
 local rigA=make_rig{seed=31}
 local A=install(rigA)
 build('dance',A) build('wave',A)
 tick(1.5)
 check(disk[S().IndexPath]~=nil,'the skeletons were not saved')
 uninstall(rigA)
 load_addon()
 local B=install(make_rig{seed=32,scale=2.9})
 check(M().BuildModelKey(B)==A and ids(B)=='dance,wave','the next session lost the builds: '..ids(B))
 -- The rig the Hotloader holds for the session is read before its file.
 local rigC=make_rig{seed=33,scale=3.5}
 mmdhl={rigsByModel={[rigC.model]=rigC}}
 local before=reads
 check(M().BuildModelKey(rigC.model)==A,'the session\'s rig was not used')
 check(reads==before,'the rig file was read though the Hotloader held the rig')
 -- A save that did not finish: a broken file is an empty one, and nothing breaks.
 disk[S().IndexPath]='{"format":1,"skeletons":[{"model":'
 load_addon()
 local D=install(make_rig{seed=34})
 check(M().BuildModelKey(D)==D,'a broken index matched something')
 check(#errors==0,'errors: '..table.concat(errors,' | '))
elseif scenario=='migrate' then
 -- Builds and mappings from before: carriers of one skeleton join the one with the most builds.
 local P=install(make_rig{seed=41,scale=3.2365598678588867,file='lycia'})
 local Q=install(make_rig{seed=42,scale=3.7719697952270510,file='lycia'})
 local rigR=make_rig{seed=43,file='topaz',edit=function(t) t[3][3]={0,0.2,1.7} end}
 local R=install(rigR)
 local gone='models/mmd/'..hex(44,16)..'/gone.mdl'
 local alyx='models/player/alyx.mdl'
 local function old(motion,model) local path=old_name(motion,model) disk[path]=util.TableToJSON({format=M().BuiltFormat,motion_id=motion,model=model,frames={}}) return path end
 for _,motion in ipairs({'a','b','c','d','e'}) do old(motion,P) end
 local qOnly=old('f',Q) local qDup=old('a',Q)
 old('g',R) old('h',gone) old('i',alyx)
 -- A build of the format before "_fm2" (the add-on reads none of them): left alone.
 local preFormat=old_name('j',Q):gsub('_fm2%.json$','.json')
 disk[preFormat]='{}'
 -- Mappings: Q's join P's (P's own win), R's stay.
 disk[M().FlexOverridePath]=util.TableToJSON({[P:lower()]={by_mmd={['まばたき']='blink'}},[Q:lower()]={by_mmd={['まばたき']='wink',['笑い']='smile'}},[R:lower()]={by_mmd={['あ']='a'}}})
 load_addon()
 hook.Run('InitPostEntity')
 tick(3.1)
 for _=1,20 do tick(0.02) end
 check(S().Index().migrated==true,'the migration did not finish')
 check(not named.MMDVMDNPCSkeletonMigration,'the migration timer kept running')
 local data=S().Index()
 check(data.entries[P:lower()]~=nil and data.entries[R:lower()]~=nil,'a carrier with builds was not kept')
 check(data.entries[Q:lower()]==nil and data.aliases[Q:lower()]==P,'the carrier with fewer builds did not join the other')
 check(data.entries[gone:lower()]==nil,'a carrier without its rig was kept')
 -- Q's own motion now has P's name; the one both had stays as it was.
 check(disk[qOnly]==nil and disk[old_name('f',P)]~=nil,'the joined carrier\'s build was not renamed')
 check(disk[qDup]~=nil,'a build P has too was renamed over or deleted')
 check(disk[preFormat]=='{}','a build of the earlier format was renamed')
 check(ids(P)=='a,b,c,d,e,f' and ids(Q)=='a,b,c,d,e,f','the builds of both carriers are not found together: '..ids(Q))
 local renamedHeader=util.JSONToTable(disk[old_name('f',P)])
 check(renamedHeader.model==Q and M().SameBuildModel(renamedHeader.model,P),'the renamed build (made on Q) is not accepted for P')
 check(ids(R)=='g' and disk[old_name('h',gone)]~=nil and disk[old_name('i',alyx)]~=nil,'other models\' builds changed')
 -- The mappings.
 local maps=util.JSONToTable(disk[M().FlexOverridePath])
 check(maps[Q:lower()]==nil,'the joined carrier kept its mappings')
 check(maps[P:lower()].by_mmd['まばたき']=='blink' and maps[P:lower()].by_mmd['笑い']=='smile','the mappings did not join (the kept one wins)')
 check(maps[R:lower()].by_mmd['あ']=='a','another skeleton\'s mapping changed')
 check(#printed>0 and printed[#printed]:find('1 other carrier',1,true)~=nil,'no summary: '..tostring(printed[#printed]))
 -- A new size of Lycia finds all six; the next session does nothing again.
 local T=install(make_rig{seed=45,scale=4.4})
 check(ids(T)=='a,b,c,d,e,f','a new size did not find the adopted builds')
 local renamedBefore=disk[old_name('f',P)]
 load_addon()
 check(S().Index().migrated==true and disk[old_name('f',P)]==renamedBefore,'the migration ran again')
 check(M().BuildModelKey(Q)==P,'the alias did not survive the session')
elseif scenario=='migrate_on_demand' then
 -- A lookup before the stepped migration finishes completes it at once.
 local P=install(make_rig{seed=51})
 local Q=install(make_rig{seed=52,scale=4})
 disk[old_name('a',P)]=util.TableToJSON({format=M().BuiltFormat,motion_id='a',model=P,frames={}})
 disk[old_name('b',Q)]=util.TableToJSON({format=M().BuiltFormat,motion_id='b',model=Q,frames={}})
 disk[old_name('c',Q)]=util.TableToJSON({format=M().BuiltFormat,motion_id='c',model=Q,frames={}})
 load_addon()
 check(not S().Index().migrated,'nothing was left to adopt')
 check(M().BuildModelKey(P)==Q,'the lookup did not wait for the migration: '..M().BuildModelKey(P))
 check(ids(P)=='a,b,c' and S().Index().migrated==true,'the on-demand migration did not complete: '..ids(P))
elseif scenario=='mappings' then
 -- Expression mappings follow the character like its builds.
 local A=install(make_rig{seed=61})
 local B=install(make_rig{seed=62,scale=4.2})
 check(M().SetFlexOverrideForModel(A,'まばたき','blink',{'blink'}),'the mapping was not saved')
 check(S().Index().entries[A:lower()]~=nil,'a mapping did not keep its build model')
 local names=M().FlexOverrideTargetsForModel(B,'blink','まばたき')
 check(names and names[1]=='blink','the resized carrier does not find the mapping')
 check(M().SetFlexOverrideForModel(B,'笑い','smile',{'smile'}),'the second mapping was not saved')
 local saved=util.JSONToTable(disk[M().FlexOverridePath])
 check(saved[B:lower()]==nil and saved[A:lower()].by_mmd['笑い']=='smile','the mapping went under the carrier, not its build model')
 check(M().ClearFlexOverrideForModel(B,'まばたき','blink'),'clearing through another carrier failed')
 check(M().FlexOverrideTargetsForModel(A,'blink','まばたき')==nil,'the mapping was not cleared for the build model')
else
 error('unknown scenario '..tostring(scenario))
end
realPrint('PASS '..scenario)
