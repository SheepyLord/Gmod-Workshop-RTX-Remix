"""Read-only bounded AMD64 minidump classification for the shared VR driver."""
from __future__ import annotations
import argparse
import hashlib
import json
import mmap
from pathlib import Path
import shutil
import struct
import datetime as dt
import subprocess

WER_SOURCE=Path(r'H:\SteamLibrary\steamapps\common\GarrysMod_RTX_c\_debug_tools\hangdumps\wer')
FIXES_NAME='gmcl_rtxfixesbinary_win64.dll'
FIXES_STAMP=0x6af185ec
FIXES_RETURN=0x41605b
MAX_STACK=8*1024*1024


def digest(path):
    h=hashlib.sha256()
    with Path(path).open('rb') as stream:
        for block in iter(lambda:stream.read(1024*1024),b''):h.update(block)
    return h.hexdigest()


def copy_wer_dump(source,evidence,pid):
    if not isinstance(pid,int) or isinstance(pid,bool) or not 0<pid<2**32:raise ValueError('invalid game PID')
    original=Path(source)/f'gmod.exe.{pid}.dmp'
    if not original.is_file():return {'source':str(original),'available':False}
    target=Path(evidence)/'crash-reports/wer'/original.name
    if target.resolve().is_relative_to(Path(source).resolve()) or target.resolve().is_relative_to(WER_SOURCE.parents[2].resolve()):
        raise ValueError('crash evidence must never write below the legacy install or WER source')
    if target.exists():raise ValueError('WER evidence destination already exists')
    target.parent.mkdir(parents=True,exist_ok=True)
    before=original.stat()
    shutil.copyfile(original,target)  # The source is opened only for reading.
    after=original.stat();copied=digest(target)
    if (before.st_size,before.st_mtime_ns)!=(after.st_size,after.st_mtime_ns) or copied!=digest(original):
        raise ValueError('WER dump changed during copy; partial evidence retained')
    return {'source':str(original),'copy':str(target),'available':True,'bytes':target.stat().st_size,'sha256':copied}


class Dump:
    def __init__(self,data):
        self.data=data;self.streams={}
        if self.bytes(0,4)!=b'MDMP':raise ValueError('not a minidump')
        count,directory=self.unpack('<II',8)
        if count>65536:raise ValueError('too many streams')
        self.bytes(directory,count*12)
        for index in range(count):
            kind,size,rva=self.unpack('<III',directory+index*12)
            if kind==0:continue
            self.bytes(rva,size)
            if kind in self.streams:raise ValueError('duplicate stream')
            self.streams[kind]=(rva,size)
    def bytes(self,at,size):
        if at<0 or size<0 or at>len(self.data) or size>len(self.data)-at:raise ValueError('dump range outside file')
        return self.data[at:at+size]
    def unpack(self,fmt,at):return struct.unpack(fmt,self.bytes(at,struct.calcsize(fmt)))
    def stream(self,kind,minimum):
        at,size=self.streams[kind]
        if size<minimum:raise ValueError('short stream')
        return at,size
    def modules(self):
        at,size=self.stream(4,4);count,=self.unpack('<I',at)
        if count>65536 or count*108>size-4:raise ValueError('invalid module count')
        out=[]
        for i in range(count):
            base,length,checksum,stamp,name=self.unpack('<QIIII',at+4+i*108)
            n,=self.unpack('<I',name)
            if n>65536 or n%2:raise ValueError('invalid module name')
            path=self.bytes(name+4,n).decode('utf-16-le')
            out.append({'name':path.replace('\\','/').rsplit('/',1)[-1].lower(),'base':base,'size':length,'timestamp':stamp})
        return out
    def stack(self,tid,rsp):
        at,size=self.stream(3,4);count,=self.unpack('<I',at)
        if count>65536 or count*48>size-4:raise ValueError('invalid thread count')
        bounds=None
        for i in range(count):
            thread=at+4+i*48;identity,=self.unpack('<I',thread)
            if identity==tid:
                start,length,rva=self.unpack('<QII',thread+24)
                bounds=(start,length,rva);break
        if bounds is None:raise ValueError('faulting thread absent')
        if rsp%8:raise ValueError('unaligned exception RSP')
        start,length,rva=bounds
        if length and not start<=rsp<start+length:raise ValueError('exception RSP outside faulting thread stack')
        limit=start+length if length else rsp+MAX_STACK
        segments=[]
        if 9 in self.streams:
            at,size=self.stream(9,16);count,base=self.unpack('<QQ',at)
            if count>1000000 or count*16>size-16:raise ValueError('invalid memory64 count')
            for i in range(count):
                address,n=self.unpack('<QQ',at+16+i*16)
                if address<=rsp<address+n:segments.append((address,n,base))
                base+=n
        if 5 in self.streams:
            at,size=self.stream(5,4);count,=self.unpack('<I',at)
            if count>1000000 or count*16>size-4:raise ValueError('invalid memory count')
            for i in range(count):
                address,n,file_at=self.unpack('<QII',at+4+i*16)
                if address<=rsp<address+n:segments.append((address,n,file_at))
        for address,n,file_at in segments:
            size=min(address+n,limit,rsp+MAX_STACK)-rsp
            if size>0:return self.bytes(file_at+rsp-address,size),size
        if length and rva:
            size=min(start+length-rsp,MAX_STACK)
            return self.bytes(rva+rsp-start,size),size
        raise ValueError('exception stack memory not captured')


def classify_dump(path,startup=False):
    result={'classification':'unknown','dump':str(path),'startup':bool(startup),'context_source':'exception_stream'}
    try:
        with Path(path).open('rb') as stream:
            if Path(path).stat().st_size<32:raise ValueError('short header')
            with mmap.mmap(stream.fileno(),0,access=mmap.ACCESS_READ) as mapped:
                d=Dump(mapped);system,_=d.stream(7,2)
                if d.unpack('<H',system)[0]!=9:raise ValueError('not AMD64')
                ex,_=d.stream(6,168);tid,=d.unpack('<I',ex)
                code,=d.unpack('<I',ex+8);address,=d.unpack('<Q',ex+24)
                size,context=d.unpack('<II',ex+160)
                if size<256:raise ValueError('short exception context')
                if not d.unpack('<I',context+48)[0]&0x100000:raise ValueError('not AMD64 context')
                rsp,=d.unpack('<Q',context+152);rip,=d.unpack('<Q',context+248)
                result.update(thread_id=tid,exception_code=hex(code),exception_address=hex(address),rsp=rsp,rip=hex(rip))
                modules=d.modules()
                fault=next((m for m in modules if m['base']<=rip<m['base']+m['size']),None)
                if fault:result['fault']={'module':fault['name'],'offset':hex(rip-fault['base']),'timestamp':hex(fault['timestamp'])}
                if startup and fault and fault['name']=='nvoglv64.dll' and rip-fault['base']==0xe622f8:
                    result['classification']='known_nvidia_startup'
                try:stack,scanned=d.stack(tid,rsp)
                except (ValueError,KeyError) as error:
                    result['stack_error']=str(error)
                    return result
                result['stack_bytes_scanned']=scanned
                fixes=next((m for m in modules if m['name']==FIXES_NAME and m['size']>FIXES_RETURN),None)
                if fixes:
                    marker=struct.pack('<Q',fixes['base']+FIXES_RETURN)
                    hit=next((i for i in range(0,len(stack)-7,8) if stack[i:i+8]==marker),None)
                    if hit is not None:
                        result.update(classification='known_fixes_render_entity' if fixes['timestamp']==FIXES_STAMP else 'fixes_render_stack_signature',stack_match={'address':rsp+hit,'module':FIXES_NAME,'offset':hex(FIXES_RETURN),'timestamp':hex(fixes['timestamp'])})
                if result['classification']=='unknown' and startup and fault and fault['name']=='nvoglv64.dll' and rip-fault['base']==0xe622f8:
                    result['classification']='known_nvidia_startup'
    except (OSError,ValueError,KeyError,struct.error,UnicodeError) as error:result['error']=str(error)
    return result


def retry_allowed(result,prior_crash=False):
    return not prior_crash and result.get('classification')=='known_nvidia_startup'


def crashed(run):
    value=run.get('exit')
    if not isinstance(value,int):return False
    value &= 0xffffffff
    return value&0xc0000000==0xc0000000 or value==0x60d0dead


def application_event(evidence,run):
    """Keep matching Windows Application/1000 events; no event-log changes."""
    out=Path(evidence)/'application-1000.json'
    if out.exists():return {'path':str(out),'already_retained':True}
    def quote(value):return "'"+str(value).replace("'","''")+"'"
    try:
        start=dt.datetime.fromisoformat(run['started'].replace('Z','+00:00'))-dt.timedelta(seconds=5)
        end=dt.datetime.now(dt.timezone.utc)+dt.timedelta(seconds=5)
        pid=int(run['pid'])
        script=f'''$a=[DateTimeOffset]::Parse({quote(start.isoformat())}).LocalDateTime
$b=[DateTimeOffset]::Parse({quote(end.isoformat())}).LocalDateTime
$rows=@(Get-WinEvent -FilterHashtable @{{LogName='Application';Id=1000;StartTime=$a;EndTime=$b}} -ErrorAction SilentlyContinue | ForEach-Object {{
 [xml]$x=$_.ToXml();$data=@{{}};foreach($item in $x.Event.EventData.Data){{$data[$item.Name]=$item.'#text'}}
 if($data.ProcessId -and [Convert]::ToInt64(($data.ProcessId -replace '^0x',''),16) -eq {pid}){{
 [pscustomobject]@{{Utc=$_.TimeCreated.ToUniversalTime().ToString('o');RecordId=$_.RecordId;Data=$data;Message=$_.Message}}
 }}
}})
ConvertTo-Json -InputObject $rows -Depth 6 | Set-Content -LiteralPath {quote(out)} -Encoding UTF8'''
        r=subprocess.run(['powershell','-NoProfile','-Command',script],capture_output=True,timeout=20)
        return {'path':str(out),'exit':r.returncode}
    except (OSError,ValueError,KeyError,subprocess.TimeoutExpired) as error:return {'error':str(error)}


def record_crash(evidence,run,records=(),prior_crash=False,wer_copy=None):
    evidence=Path(evidence)
    if not crashed(run):return None
    receipt={'pid':run.get('pid'),'exit':run.get('exit_hex',hex(run['exit']&0xffffffff)),
        'classification':'unknown','prior_crash':bool(prior_crash),'dump_results':[]}
    try:receipt['wer']=wer_copy if wer_copy is not None else copy_wer_dump(WER_SOURCE,evidence,int(run['pid']))
    except (OSError,ValueError,KeyError) as error:receipt['wer']={'error':str(error)}
    candidates=[]
    if receipt['wer'].get('available'):candidates.append(Path(receipt['wer']['copy']))
    candidates+=sorted((evidence/'poc/game/crash-reports').rglob('*.dmp'))
    startup=not any(r.get('kind')=='running' or r.get('page')=='running' or r.get('info',{}).get('framesRendered',0)>0 for r in records)
    for path in candidates:
        result=classify_dump(path,startup);result['sha256']=digest(path);receipt['dump_results'].append(result)
    match=next((r for r in receipt['dump_results'] if r['classification'] in ('known_fixes_render_entity','fixes_render_stack_signature')),None)
    match=match or next((r for r in receipt['dump_results'] if r['classification']=='known_nvidia_startup'),None)
    if match:receipt.update(classification=match['classification'],matched_dump=match['dump'],signature=match.get('stack_match',match.get('fault')))
    receipt['retry_eligible']=retry_allowed(receipt,prior_crash)
    receipt['event1000']=application_event(evidence,run)
    (evidence/'crash.json').write_text(json.dumps(receipt,indent=2)+'\n',encoding='utf-8')
    return receipt


if __name__=='__main__':
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('dump',type=Path);p.add_argument('--startup',action='store_true');p.add_argument('--out',type=Path,required=True)
    a=p.parse_args();r=classify_dump(a.dump,a.startup);a.out.parent.mkdir(parents=True,exist_ok=True);a.out.write_text(json.dumps(r,indent=2)+'\n',encoding='utf-8')
    print(json.dumps({k:r[k] for k in ('classification','thread_id','rsp','stack_match','fault','error') if k in r}))
