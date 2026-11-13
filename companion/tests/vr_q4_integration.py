"""One production all-module session under the shared ULib hook fixture, then restart."""
from pathlib import Path
import argparse
import base64
import copy
import json
import sys
import vr_combined_session as combined
import vr_fixture_frames as frames
import vr_interact_poc as physical
import vr_reload_poc as reloads
import vr_tools_poc as tools
import vr_weapons_poc as weapons
import vr_session as driver

ROOT=Path(__file__).resolve().parents[2]
W_PHASES=['pistol-5','fore-smg','melee-fast','frag-throw']
END=119


def timeline():
    steps=[]
    def add(data,offset,limit):
        for row in data['steps']:
            if row['time']>=limit:continue
            row=copy.deepcopy(row);row['time']+=offset;steps.append(row)
    add(physical.timeline(16),0,16)
    add(weapons.timeline(16,W_PHASES),16,16)
    calibration=[{'kind':'calibration','class':'weapon_pistol','port_tracking':[.55,-.2,1.2],'port_angle':[0,0,0]}]
    add(reloads.timeline(20,['weapon_pistol'],calibration),32,20)
    add(tools.timeline(60,'features'),52,60)
    for time in (112.4,114.5,116.5):
        row=copy.deepcopy(steps[-1]);row['time']=time
        row['actions']={'left_stick':[0,.5] if time<116 else [0,0],'left_trigger_value':.5 if time<116 else 0}
        steps.append(row)
    steps.sort(key=lambda row:row['time'])
    steps.append({**steps[-1],'time':END+5,'actions':{}})
    return frames.natural_timeline({'version':1,'steps':steps})


def source(name):return Path(__file__).with_name(name).read_text(encoding='utf-8')


def client_segment(text,first,last,hook_marker):
    # Each existing module observer keeps its checks and its own local time window.
    # Off branches still execute at real Exit so their cleanup remains observable.
    text=text.replace('nlvr.TestState()',f'QStageState({first},{last})').replace('native.TestState()',f'QStageState({first},{last})')
    if text.count(hook_marker)!=1:raise ValueError('segment hook contract changed: '+hook_marker)
    text=text.replace(hook_marker,hook_marker+f'\n    if NLVR and not QWindow({first},{last}) then return end',1)
    return text


def fixture(text):
    text=combined.moving_base(text)
    text=combined.checked_replace(text,'for _, name in ipairs({"nativeloader_weather",',
        'for _, name in ipairs({"m_yaw", "nativeloader_weather",')
    text=combined.checked_replace(text,'RunConsoleCommand("nativeloader_weather_seconds", "0")',
        'RunConsoleCommand("m_yaw", "0")\nRunConsoleCommand("nativeloader_weather_seconds", "0")')
    text=text.replace('RunConsoleCommand("nlvr_q_hud")','do end').replace('RunConsoleCommand("nlvr_q_hud", "restore")','do end')
    clock=source('vr_combined_clock.lua')
    clock_setup='''qFunctionalClock=QFunctionalClock.New{Native=native,Steps=util.JSONToTable([==[%s]==]),BeginAt=0,
EngineTime=function() return engine.TickCount()*engine.TickInterval() end,WallTime=SysTime,Paused=function() return gui.IsGameUIVisible() end}
'''%json.dumps(timeline()['steps'],separators=(',',':'))
    text=combined.checked_replace(text,'originalBegin, originalCamera, originalCreate = native.BeginFrame, native.SetFrameCamera, native.OverlayCreate',
        clock_setup+'originalBegin, originalCamera, originalCreate = native.BeginFrame, native.SetFrameCamera, native.OverlayCreate')
    text=combined.checked_replace(text,'local t = now - activeAt','local t = qFunctionalClock and native.TestState().time or now-activeAt')
    text=combined.checked_replace(text,'native.BeginFrame, native.SetFrameCamera, native.OverlayCreate, native.Capture = originalBegin, originalCamera, originalCreate, originalCapture',
        'native.BeginFrame, native.SetFrameCamera, native.OverlayCreate, native.Capture = originalBegin, originalCamera, originalCreate, originalCapture\n'
        '        if qFunctionalClock then emit("Q4-functional-clock",qFunctionalClock.Stats()) qFunctionalClock.Stop() end')
    text='local QFunctionalClock=(function()\n'+clock+'\nend)()\nlocal qFunctionalClock\n'+text
    text=frames.inject(text)
    p=client_segment(source('vr_interact_poc_client.lua'),0,16,'hook.Add("PreRender","nlvr_p_probe",function()')
    w=client_segment(source('vr_weapons_poc_client.lua'),16,32,'hook.Add("PreRender","nlvr_w_probe",function()')
    k=client_segment(source('vr_reload_poc_client.lua'),32,52,'hook.Add("PreRender", "nlvr_k_probe", function()')
    t=client_segment(source('vr_tools_poc_client.lua'),52,112,'hook.Add("PreRender", ID, function()')
    t=combined.checked_replace(t,'data = data or {} data.name, data.realm = name, "client"',
        'data = data or {} if name=="menu-selected" and data.actual==data.wanted then QPeers.MenuAction() end data.name, data.realm = name, "client"')
    # T's laser targeting edits a desired palm pose; convert it back into C's raw basis.
    t=combined.checked_replace(t,'if target then frame.right.ang = (target - frame.right.pos):Angle() end',
        'if target then frame.right.ang = (target-frame.right.pos):Angle() qNaturalTarget=target end')
    t=combined.checked_replace(t,'return frame, detail',
        'if timeNow>26 then if qNaturalTarget then QFrames.Aim(frame.right,"right",qNaturalTarget)\n'
        '                        else QFrames.Encode(frame.right,"right") end end\n                    return frame, detail')
    t=combined.checked_replace(t,'local frame, detail = originalFrame(...)',
        'local frame, detail = originalFrame(...)\n                    local qNaturalTarget\n'
        '                    if not QWindow(52,112) then return frame,detail end')
    return text+'\n'+source('vr_q4_integration.lua')+'\ndo\n'+p+'\nend\ndo\n'+w+'\nend\ndo\n'+k+'\nend\ndo\nlocal T_ORIGINAL_MOUSE_YAW=saved.m_yaw\n'+t+'\nend\n'


def rows(console,prefix):
    result=[];parts={}
    for line in console.splitlines():
        if line.startswith(prefix+' '):result.append(json.loads(line[len(prefix)+1:]))
        elif line.startswith(prefix+'_CHUNK '):
            tail=line[len(prefix)+7:]
            fields=tail.split(' ',3) if prefix=='NLVR_T' else tail.split(' ',2)
            if prefix=='NLVR_T':realm,key,part,data=fields;key=realm+'_'+key
            else:key,part,data=fields
            i,n=map(int,part.split('/'));parts.setdefault(key,{})[i]=data
            if len(parts[key])==n:result.append(json.loads(base64.b64decode(''.join(parts[key][i] for i in range(1,n+1)))));del parts[key]
    if parts:raise ValueError('incomplete '+prefix+' records')
    return result


def analyse(summary,console,folder=None,driver_exit=None):
    p,w,k,t=(rows(console,prefix) for prefix in ('NLVR_P','NLVR_W','NLVR_K','NLVR_T'))
    starts=[r for r in summary['records'] if r.get('kind')=='Q4-integration-start']
    off=[r for r in summary['records'] if r.get('kind')=='Q4-integration-off']
    stages=[r for r in summary['records'] if r.get('kind')=='Q4-integration-stage']
    module_names={'core','hands','move','ui','weapons','reload','tools','interact'}
    # These are integration witnesses, not a replacement for the full Done-point suite.
    checks={'renderer':summary['success'], 'two_starts':len(starts)==2 and all(r.get('ulib') for r in starts),
        'two_exits':len(off)==2 and all(r.get('ulib') for r in off),
        'all_modules_healthy':len(stages)==4 and all(all(r.get('modules',{}).get(n) for n in module_names) for r in starts+stages),
        'physics_records':bool(p), 'weapon_records':bool(w), 'reload_records':bool(k),'tools_records':bool(t)}
    peer=next((r for r in summary['records'] if r.get('kind')=='peer-final'),{})
    checks['exercised_peer_callbacks']=combined.exercised_peers(summary['records'],menus=True)
    semantic={}
    if folder:
        import vr_weapons_analyse,vr_reload_analyse,vr_tools_check
        for name,data in (('weapons.json',w),('reload.json',k),('tools-records.json',t)):
            driver.write_json(folder/name,data)
        native_exit=driver_exit if driver_exit is not None else (0 if summary['success'] else 1)
        metadata=reloads.validate_records(folder,k,['weapon_pistol'],False,console)
        metadata['renderer_exit']=native_exit
        metadata['success'] &= native_exit==0
        driver.write_json(folder/'reload-receipt.json',metadata)
        driver.write_json(folder/'tools-provenance.json',{'case':'features','driver_exit':native_exit,
            'driver_scope':'shared native renderer driver, before subsystem acceptance',
            'integration':True,'sources':{name:driver.sha256(folder/name) for name in ('probe.lua','server-fixture.lua')}})
        reducers={'physics':lambda:combined.physical_check.analyse(p,selected=[0,1]),
            'weapons':lambda:vr_weapons_analyse.analyse(folder),
            'reload':lambda:vr_reload_analyse.analyse(folder),
            'reload_assets':lambda:metadata,
            'tools':lambda:vr_tools_check.evaluate(folder)}
        for name,reduce in reducers.items():
            try:semantic[name]=reduce()
            except Exception as exc:semantic[name]={'success':False,'error':str(exc)}
            driver.write_json(folder/('integration-'+name+'.json'),semantic[name])
    for name in ('physics','weapons','reload','reload_assets','tools'):
        checks[name+'_features']=semantic.get(name,{}).get('success') is True
    return {'success':all(checks.values()),'checks':checks,'records':{'physics':len(p),'weapons':len(w),'reload':len(k),'tools':len(t)},
        'starts':starts,'stages':stages,'off':off,
        'semantic':{name:value.get('success') for name,value in semantic.items()},
        'note':'Every subsystem semantic reducer is required; record presence alone cannot pass.'}


def main(argv=None):
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--package',type=Path,required=True);p.add_argument('--evidence',type=Path,required=True);p.add_argument('--simulate',action='store_true');p.add_argument('--fixes-reviewed',action='store_true');args=p.parse_args(argv)
    if not args.fixes_reviewed:p.error('all-module destructive fixture disabled until Claude confirms the fixes repair; use the limited vr_review_safe.py check')
    original_script,original_command=driver.lua_script,driver.command
    def script(path,config):
        config.update(q_controller_profiles=frames.profiles(),interact_phases=[0,1],weapons_phases=W_PHASES,reload_classes=['weapon_pistol'],
            reload_calibrate=False,reload_button=False,reload_counter_motion=False,reload_motion_start=0,reload_holster=False,reload_deploy=False,tools_case='features')
        original_script(path,config);path.write_text(fixture(path.read_text(encoding='utf-8')),encoding='utf-8')
    def command(arguments,evidence,label,**kwargs):
        if label=='game':
            combined.quit_field(evidence)
            chunks=[]
            for name in ('vr_interact_poc.lua','vr_weapons_poc.lua','vr_reload_poc_server.lua','vr_tools_poc_server.lua'):
                text=source(name)
                if name=='vr_weapons_poc.lua':
                    text=combined.checked_replace(text,'previous=previous or ply:GetActiveWeapon():GetClass()',
                        'previous=previous or "weapon_pistol"')
                if name=='vr_tools_poc_server.lua':
                    text=combined.checked_replace(text,'oldPos, oldMove, began = ply:GetPos(), ply:GetMoveType(), CurTime()',
                        'ply:SetPos(Vector(0,0,448)) ply:SetMoveType(MOVETYPE_NOCLIP)\n'
                        '    oldPos, oldMove, began = ply:GetPos(), ply:GetMoveType(), CurTime()')
                chunks.append('do\n'+text+'\nend')
            server='''local p=Entity(1)
if IsValid(p) then if not p:HasWeapon("weapon_pistol") then p:Give("weapon_pistol",true) end p:SelectWeapon("weapon_pistol") end
'''+ '\n'.join(chunks)
            arguments=combined.stage_fixtures(arguments,evidence,server)
            transport=evidence/'game-arguments.json';driver.write_json(transport,[str(x) for x in arguments[1:]])
            arguments=[Path(__file__).resolve(),'--poc-arguments',transport]
        return original_command(arguments,evidence,label,**kwargs)
    driver.lua_script,driver.command=script,command
    path=args.evidence.with_name(args.evidence.name+'-timeline.json');driver.write_json(path,timeline())
    code=driver.main(['--package',str(args.package),'--evidence',str(args.evidence),'--seconds',str(END),'--timeline',str(path),'--camera','823,-657,-79,0,0,0',*(['--simulate'] if args.simulate else [])])
    if (args.evidence/'summary.json').exists():
        result=analyse(json.loads((args.evidence/'summary.json').read_text()),(args.evidence/'poc/game/console.log').read_text(errors='replace'),args.evidence,code)
        driver.write_json(args.evidence/'integration-checks.json',result);print(json.dumps({'success':result['success'],'checks':result['checks']}))
        return code or (0 if result['success'] else 1)
    return code or 1


if __name__=='__main__':
    if len(sys.argv)==3 and sys.argv[1]=='--poc-arguments':raise SystemExit(combined.poc.main(json.loads(Path(sys.argv[2]).read_text())))
    raise SystemExit(main())
