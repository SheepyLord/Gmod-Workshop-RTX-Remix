"""Five plus five alternating VR-off launches against the exact published package."""
from __future__ import annotations
import argparse
import json
import re
from pathlib import Path
import statistics
import subprocess
import sys
import time

ROOT = Path(__file__).resolve().parents[1]
sys.path[:0] = [str(ROOT/'tools'),str(ROOT/'companion/tests')]
import vr_session as driver


def timer_inventory(folder):
    path=folder/'poc/game/console.log'
    if not path.exists():return {'success':False,'missing':'console.log'}
    text=path.read_text(encoding='utf-8',errors='replace');result={}
    for realm in ('CL','SV'):
        start='NLVR_Q_TIMERS_BEGIN_'+realm;end='NLVR_Q_TIMERS_END_'+realm
        a=text.rfind(start);b=text.rfind(end)
        raw=text[a+len(start):b] if a>=0 and b>a else ''
        named=[{'name':m[0],'source':m[1],'line':int(m[2])} for m in
               re.findall(r"Timer '([^']+)'.*?@(.+?) \(line (\d+)\)",raw)]
        sources=[t['name']+'@'+t['source'] for t in named]
        result[realm]={'available':a>=0 and b>a and 'Unknown command' not in raw,
                       'raw':raw,'named_timers':named,'named_sources':sorted(sources),
                       'vr_timer_present':any('nlvr.' in line or 'nativeloader_vr_session' in line for line in raw.splitlines())}
    result['success']=all(r['available'] and not r['vr_timer_present'] for r in result.values())
    return result


def preparation_only(folder):
    history=folder/'poc/session.json'
    if (folder/'game.log').exists() or (folder/'summary.json').exists() or not history.exists():
        return False
    rows=json.loads(history.read_text(encoding='utf-8'))
    return any(r.get('step')=='install' and r.get('failed') for r in rows) and not any(r.get('step')=='run' for r in rows)


def run_folder(root,label):
    path=root/'attempt-selection.json'
    selection=json.loads(path.read_text(encoding='utf-8')) if path.exists() else {}
    if label not in selection:return root/label
    item=selection[label]
    for name in item['previous_preparations']+[item['selected']]:
        p=(root/name).resolve()
        if p.parent!=root.resolve() or not (name==label or re.fullmatch(re.escape(label)+r'-retry-\d+',name)):
            raise ValueError('attempt selection escapes its canonical flat launch')
    if not all(preparation_only(root/name) for name in item['previous_preparations']):
        raise ValueError('a launched game cannot be replaced in the alternating batch')
    return root/item['selected']


def retry_preparation(root,label):
    current=run_folder(root,label)
    if not preparation_only(current):raise ValueError('retry is allowed only when installation failed before a game launch')
    path=root/'attempt-selection.json'
    selection=json.loads(path.read_text(encoding='utf-8')) if path.exists() else {}
    previous=selection.get(label,{}).get('previous_preparations',[])+[current.name]
    name=label+'-retry-'+str(len(previous))
    if (root/name).exists():raise ValueError('preserve existing retry evidence')
    selection[label]={'selected':name,'previous_preparations':previous,
        'reason':'Failed installation never reached the game command; actual game launch alternation is retained.'}
    driver.write_json(path,selection)
    return root/name


def aggregate(root):
    runs=[]
    for i in range(10):
        label=('published' if i%2==0 else 'candidate')+'-'+str(i//2+1)
        folder=completed_run_folder(root,label)
        if not (folder/'summary.json').exists():
            runs.append({'label':label,'success':False,'missing':True})
            continue
        summary=json.loads((folder/'summary.json').read_text(encoding='utf-8'))
        history=json.loads((folder/'poc/session.json').read_text(encoding='utf-8'))
        window=next((r for r in summary['records'] if r.get('kind')=='flat-window'),{})
        inventory=[r for r in summary['records'] if r.get('kind')=='Q-flat-inventory']
        server=[r for r in summary['records'] if r.get('kind')=='Q-flat-server']
        timers=timer_inventory(folder)
        image=next(iter((folder/'poc/game').glob('*flat-after.png')),None)
        runs.append({'label':label,'success':summary['success'] and bool(window) and bool(inventory) and bool(server) and bool(image) and timers['success'],
                     'median_frame_interval_ms':window.get('intervals',{}).get('median_ms'),
                     'seconds_to_map':history[-1].get('seconds_to_map'),'inventory':inventory,'server':server,
                     'image':str(image) if image else None,'folder':str(folder),'timer_inventory':timers})
    selection=root/'attempt-selection.json'
    result={'runs':runs,'success':all(r['success'] for r in runs),'order':[r['label'] for r in runs],
            'preparation_attempts':json.loads(selection.read_text()) if selection.exists() else {},
            'note':'Frame medians use the timed VR-off window; seconds_to_map is launch to the PoC map-ready predicate.'}
    if not result['success']:
        return result
    groups={name:[r for r in runs if r['label'].startswith(name)] for name in ('published','candidate')}
    result['groups']={name:{'median_of_launch_frame_medians_ms':statistics.median(r['median_frame_interval_ms'] for r in rows),
                             'frame_medians_ms':[r['median_frame_interval_ms'] for r in rows],
                             'start_to_map_seconds':[r['seconds_to_map'] for r in rows],
                             'start_to_map_median_seconds':statistics.median(r['seconds_to_map'] for r in rows)}
                      for name,rows in groups.items()}
    from PIL import Image,ImageChops,ImageStat
    pictures=[]
    for n in range(5):
        a,b=groups['published'][n],groups['candidate'][n]
        with Image.open(a['image']) as left,Image.open(b['image']) as right:
            left,right=left.convert('RGB'),right.convert('RGB')
            if left.size!=right.size:
                pictures.append({'pair':n+1,'success':False,'reason':'different extent'})
                continue
            difference=ImageChops.difference(left,right)
            path=root/('difference-'+str(n+1)+'.png');difference.save(path)
            pictures.append({'pair':n+1,'success':True,'size':left.size,'mean_absolute_rgb':ImageStat.Stat(difference).mean,
                             'rms_rgb':ImageStat.Stat(difference).rms,'difference':str(path)})
    result['screenshot_comparisons']=pictures
    within=[]
    for a,b in zip(groups['published'],groups['published'][1:]):
        with Image.open(a['image']) as left,Image.open(b['image']) as right:
            within.append(statistics.mean(ImageStat.Stat(ImageChops.difference(left.convert('RGB'),right.convert('RGB'))).mean))
    base=result['groups']['published'];candidate=result['groups']['candidate']
    frame_delta=candidate['median_of_launch_frame_medians_ms']-base['median_of_launch_frame_medians_ms']
    startup_delta=candidate['start_to_map_median_seconds']-base['start_to_map_median_seconds']
    image_tolerance=max(within,default=0)+1
    result['comparisons']={'frame_interval_delta_ms':frame_delta,'frame_interval_tolerance_ms':max(.25,base['median_of_launch_frame_medians_ms']*.05),
                           'start_to_map_delta_seconds':startup_delta,'start_to_map_tolerance_seconds':max(1,base['start_to_map_median_seconds']*.10),
                           'published_within_rgb_mean_difference':within,'paired_image_tolerance_rgb_dn':image_tolerance}
    result['numeric_checks']={
        'frame_interval':frame_delta<=result['comparisons']['frame_interval_tolerance_ms'],
        'start_to_map':startup_delta<=result['comparisons']['start_to_map_tolerance_seconds'],
        'screenshots':all(p['success'] and statistics.mean(p['mean_absolute_rgb'])<=image_tolerance for p in pictures)}
    result['full_inventory_differences']=[]
    result['full_timer_differences']=[]
    for a,b in zip(groups['published'],groups['candidate']):
        for realm in ('inventory','server'):
            for field in ('hooks','timers','receivers'):
                before=set(a[realm][0].get(field,[]));after=set(b[realm][0].get(field,[]))
                result['full_inventory_differences'].append({'pair':a['label'].split('-')[-1], 'realm':realm,'field':field,
                                                              'added':sorted(after-before),'removed':sorted(before-after)})
        for realm in ('CL','SV'):
            before=set(a['timer_inventory'][realm]['named_sources']);after=set(b['timer_inventory'][realm]['named_sources'])
            result['full_timer_differences'].append({'pair':a['label'].split('-')[-1],'realm':realm,
                                                    'added':sorted(after-before),'removed':sorted(before-after)})
    result['inventory_controls']=[]
    fields=[(realm,field) for realm in ('inventory','server') for field in ('hooks','receivers')]+[('CL','timers'),('SV','timers')]
    for realm,field in fields:
        def values(row):
            return (row['timer_inventory'][realm]['named_sources'] if field=='timers' else row[realm][0][field])
        controls=[set(values(r)) for r in groups['published']]
        common=set.intersection(*controls);union=set.union(*controls)
        allowed={'nlvr'} if (realm,field)==('server','receivers') else set()
        # V1 already owns this page hook. It is also the one permitted page addition for
        # an older publication, never an allowance for a running session callback.
        if (realm,field)==('inventory','hooks'):allowed.add('PopulateToolMenu:nativeloader_vr')
        candidates=[]
        for r in groups['candidate']:
            actual=set(values(r))
            candidates.append({'label':r['label'],'unexpected':sorted(actual-union-allowed),'missing_common':sorted(common-actual)})
        result['inventory_controls'].append({'realm':realm,'field':field,'published_common':sorted(common),
            'published_variable':sorted(union-common),'candidates':candidates,
            'success':all(not r['unexpected'] and not r['missing_common'] for r in candidates)})
    # Preserve paired differences and baseline variation; only measured baseline variation
    # and the declared dormant additions are allowed, not arbitrary non-nlvr callbacks.
    result['vr_inventory_checks']={r['label']:all(not x.get('vr_global') and not x.get('vr_hooks') and not x.get('vr_timers') and
                                                not x.get('vr_receiver') for x in r['inventory']) and
                                               all(not x.get('vr_global') and not x.get('vr_hooks') and not x.get('vr_timers') and
                                                   x.get('vr_receiver')==(r['label'].startswith('candidate')) for x in r['server'])
                                    for r in runs}
    result['success'] &= (all(p['success'] for p in pictures) and all(result['vr_inventory_checks'].values()) and
                          all(result['numeric_checks'].values()) and all(r['success'] for r in result['inventory_controls']))
    return result


def completed_run_folder(root,label):
    """A known, restored crash may select exactly its recorded successful retry."""
    folder=run_folder(root,label)
    crash=folder/'crash.json'
    if not crash.exists():return folder
    data=json.loads(crash.read_text(encoding='utf-8'));retry=data.get('retry',{})
    if retry.get('exit')!=0 or not retry.get('evidence'):return folder
    target=Path(retry['evidence']).resolve()
    if not driver.vr_crash.retry_allowed(data) or data.get('prior_crash') or not data.get('retry_eligible'):
        raise ValueError('flat retry is not an authorized first known crash')
    if target.parent!=root.resolve() or not re.fullmatch(re.escape(folder.name)+r'-retry1(?:-\d+)?',target.name):
        raise ValueError('flat runtime retry escapes its original launch')
    restored=json.loads((folder/'restoration.json').read_text(encoding='utf-8'))
    claim=json.loads((folder/'crash-retry-used.json').read_text(encoding='utf-8'))
    if not restored.get('clean') or Path(claim.get('evidence','')).resolve()!=target or (target/'crash.json').exists():
        raise ValueError('flat runtime retry lacks clean restoration or is another crash')
    return target


def main(argv=None):
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--package',type=Path,required=True,help='candidate GMA')
    parser.add_argument('--published',type=Path,help='exact main published GMA (defaults to main out/workshop/published.json)')
    parser.add_argument('--evidence',type=Path,required=True)
    parser.add_argument('--run',type=int,choices=range(1,11),help='run one selected launch, useful after investigating a failed attempt')
    parser.add_argument('--analyse',action='store_true')
    parser.add_argument('--retry-preparation',action='store_true',help='with --run, preserve a failed installation that never launched the game and use a fresh attempt folder')
    parser.add_argument('--single',action='store_true',help=argparse.SUPPRESS)
    args=parser.parse_args(argv)
    if args.single:return one(args.package,args.evidence)
    if args.retry_preparation and (args.run is None or args.analyse):parser.error('--retry-preparation requires --run and a new actual launch')
    root=driver.inside_out(args.evidence,driver.main_checkout())
    root.mkdir(parents=True,exist_ok=True)
    published=json.loads((driver.main_checkout()/'out/workshop/published.json').read_text(encoding='utf-8'))
    baseline=args.published or Path(published['gma'])
    if not baseline.exists() or driver.sha256(baseline)!=published['gma_sha256']:
        parser.error('published baseline is missing or differs from its publication receipt')
    driver.write_json(root/'baseline-identity.json',published)
    if not args.analyse:
        for i in ([args.run-1] if args.run else range(10)):
            name=('published' if i%2==0 else 'candidate')+'-'+str(i//2+1)
            folder=retry_preparation(root,name) if args.retry_preparation else run_folder(root,name)
            if folder.exists():
                parser.error('preserve existing evidence; use a fresh batch or analyse the existing one')
            package=baseline if i%2==0 else args.package
            command=[sys.executable,str(Path(__file__).resolve()),'--single','--package',str(package),'--evidence',str(folder)]
            with (root/(folder.name+'-driver.log')).open('w',encoding='utf-8') as stream:
                run=subprocess.run(command,cwd=ROOT,stdout=stream,stderr=subprocess.STDOUT)
            if run.returncode:
                driver.write_json(root/('parity-recovered.json' if (root/'attempt-selection.json').exists() else 'parity.json'),aggregate(root))
                return run.returncode
    result=aggregate(root)
    driver.write_json(root/('parity-recovered.json' if (root/'attempt-selection.json').exists() else 'parity.json'),result)
    print(json.dumps(result,indent=2))
    return 0 if result['success'] else 1


def one(package,folder):
    import vr_combined_session as combined
    original_script,original_command,lock=driver.lua_script,driver.command,driver.ExclusiveLock
    inventory='''
local function q_inventory(kind)
 local out={hooks={},timers={},receivers={},vr_hooks={},vr_timers={},vr_global=NLVR~=nil or NLVR_SV~=nil,vr_receiver=net.Receivers.nlvr~=nil}
 for event,entries in pairs(hook.GetTable()) do for key in pairs(entries) do
  local value=event..":"..tostring(key) out.hooks[#out.hooks+1]=value
  if tostring(key):match("^nlvr%.") then out.vr_hooks[#out.vr_hooks+1]=value end
 end end
 out.timer_inventory_source="lua_dumptimers_cl/sv after the timed window"
 if timer.Exists("nativeloader_vr_session") then out.vr_timers[#out.vr_timers+1]="nativeloader_vr_session" end
 for key in pairs(net.Receivers) do out.receivers[#out.receivers+1]=key end
 table.sort(out.hooks) table.sort(out.timers) table.sort(out.receivers)
 out.kind=kind
 return out
end
'''
    def script(path,config):
        original_script(path,config)
        extra=inventory+'''
local qflatAt
hook.Add("PreRender","q_flat_inventory",function()
 if phase=="flat-control" and not qflatAt then
  qflatAt=true emit("Q-flat-inventory",q_inventory("Q-flat-inventory")) RunConsoleCommand("nlvr_q_flat_server")
  hook.Remove("PreRender","q_flat_inventory")
 end
end)
'''
        with path.open('a',encoding='utf-8') as stream: stream.write('\ndo\n'+extra+'\nend\n')
    def command(arguments,evidence,label,**kwargs):
        if label=='game':
            combined.quit_field(evidence)
            driver.write_json(evidence/'limited-flat-policy.json',{'VR':'never started','targets':'none','damage':False,'world_entity_removal':False,'driver_decorative_model':'static until normal game quit'})
            code=inventory+'''local record=900000
concommand.Add("nlvr_q_flat_server",function()
 local text=util.TableToJSON(q_inventory("Q-flat-server"))
 if #text<3000 then print("NLVR_Q "..text) else
  record=record+1 local encoded=util.Base64Encode(text):gsub("%s","") local count=math.ceil(#encoded/1600)
  for i=1,count do print("NLVR_Q_CHUNK "..record.." "..i.."/"..count.." "..encoded:sub((i-1)*1600+1,i*1600)) end
 end
 concommand.Remove("nlvr_q_flat_server") end)'''
            extra=[]
            import poc_session as poc
            for line in poc.client_lua_lines('q_flat_server',code):extra+=['--console',line.replace('lua_run_cl','lua_run',1)]
            index=arguments.index('--lua');arguments[index:index]=extra
            for command in ('echo NLVR_Q_TIMERS_BEGIN_CL','lua_dumptimers_cl','echo NLVR_Q_TIMERS_END_CL',
                            'echo NLVR_Q_TIMERS_BEGIN_SV','lua_dumptimers_sv','echo NLVR_Q_TIMERS_END_SV'):
                arguments+=['--before-quit-console',command]
        return original_command(arguments,evidence,label,**kwargs)
    class FlatLock(lock):
        def __init__(self,path,task,timeout=7200):super().__init__(path,'VR-V2V3-Q flat parity',timeout)
    driver.lua_script,driver.command,driver.ExclusiveLock=script,command,FlatLock
    code=driver.main(['--package',str(package),'--evidence',str(folder),'--flat','--seconds','20'])
    timers=timer_inventory(folder)
    driver.write_json(folder/'timer-inventory.json',timers)
    time.sleep(3.2)  # outside all locks: allow an already-waiting lab to acquire between launches
    return code or (0 if timers['success'] else 1)


if __name__=='__main__':
    if len(sys.argv)==4 and sys.argv[1]=='--one':
        sys.argv=[sys.argv[0],'--single','--package',sys.argv[2],'--evidence',sys.argv[3]]
    raise SystemExit(main())
