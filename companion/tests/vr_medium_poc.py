"""Limited real-map ladder/water simulation; no destructible/removable test targets."""
from pathlib import Path
import argparse
import json
import math
import sys
ROOT=Path(__file__).resolve().parents[2]
sys.path[:0]=[str(ROOT/'tools'),str(ROOT/'companion/tests')]
import vr_session as driver
import vr_combined_session as combined
import vr_fixture_frames as frames

BASE_SCRIPT=driver.lua_script


def cases():
    rows=[]
    for medium,directions in (('ladder',('up','down','idle')),('water',('up','down'))):
        for gun in (None,45,-45):
            for direction in directions:
                rows.append({'id':len(rows)+1,'medium':medium,'direction':direction,
                    'weapon':'nlvr_hands' if gun is None else 'weapon_pistol','gun_pitch':gun,
                    'head_pitch':-45 if medium=='ladder' or direction=='up' else 45})
    for gun in (None,45,-45):
        for direction in ('up','down'):
            rows.append({'id':len(rows)+1,'medium':'ladder','direction':direction,'stick_angle':5,
                'weapon':'nlvr_hands' if gun is None else 'weapon_pistol','gun_pitch':gun,'head_pitch':-45})
    for medium in ('noclip_water','noclip_land'):
        for gun in (None,45,-45):
            for throttle in (0,.5):
                rows.append({'id':len(rows)+1,'medium':medium,'direction':'idle' if throttle==0 else 'flight',
                    'weapon':'nlvr_hands' if gun is None else 'weapon_pistol','gun_pitch':gun,'head_pitch':-45,'throttle':throttle})
    return rows


def timeline():
    return frames.natural_timeline({'version':1,'steps':[{'time':t,'hmd':{'pos':[0,0,1.6],'ang':[0,0,0]},
        'left':{'pos':[.3,.25,1.2],'ang':[0,180,0]},'right':{'pos':[.25,-.2,1.25],'ang':[0,90,0]},'actions':{}} for t in (0,400)]})


def write_preferences(addon):
    path=addon/'lua/autorun/client/zz_q_medium_preferences.lua'
    path.parent.mkdir(parents=True,exist_ok=True)
    path.write_text('for _,n in ipairs({"dominant","height","seated","move_dir"}) do RunConsoleCommand("nl_vr_"..n,"0") end\n',encoding='utf-8')
    return path


def write_probe(path,config):
    config.update(q_controller_profiles=frames.profiles(),medium_cases=cases())
    BASE_SCRIPT(path,config)
    text=frames.inject(combined.moving_base(path.read_text(encoding='utf-8')))
    clock=Path(__file__).with_name('vr_combined_clock.lua').read_text(encoding='utf-8')
    text='local QMediumClock=(function()\n'+clock+'\nend)()\nlocal qMediumClock\n'+text
    marker='originalBegin, originalCamera, originalCreate = native.BeginFrame, native.SetFrameCamera, native.OverlayCreate'
    setup='''qMediumClock=QMediumClock.New{Native=native,Steps=util.JSONToTable([==[%s]==]),BeginAt=0,
EngineTime=function() return engine.TickCount()*engine.TickInterval() end,WallTime=SysTime,Paused=function() return gui.IsGameUIVisible() end}
''' % json.dumps(timeline()['steps'],separators=(',',':'))
    text=combined.checked_replace(text,marker,setup+marker)
    text=combined.checked_replace(text,'local t = now - activeAt','local t = qMediumClock and native.TestState().time or now-activeAt')
    marker='native.BeginFrame, native.SetFrameCamera, native.OverlayCreate, native.Capture = originalBegin, originalCamera, originalCreate, originalCapture'
    text=combined.checked_replace(text,marker,marker+'\n        if qMediumClock then emit("medium-clock",qMediumClock.Stats()) qMediumClock.Stop() end')
    text=text.replace('RunConsoleCommand("nlvr_q_hud")','do end').replace('RunConsoleCommand("nlvr_q_hud", "restore")','do end')
    text+='\ndo\n'+Path(__file__).with_name('vr_medium_poc.lua').read_text(encoding='utf-8')+'\nend\n'
    path.write_text(text,encoding='utf-8')


def angle(a,b):
    length=lambda v:math.sqrt(sum(x*x for x in v))
    n=length(a)*length(b)
    return math.degrees(math.acos(max(-1,min(1,sum(x*y for x,y in zip(a,b))/n)))) if n else 180


def analyse(summary):
    rows=[r for r in summary['records'] if r.get('kind')=='medium-trial']
    checks={'renderer':summary['success'],'all_33_cases':{r.get('id') for r in rows}==set(range(1,34)),
        'real_ladder':True,'no_ladder_side_button':True,'no_ladder_side_drift':True,'ladder_direction':True,
        'real_water':True,'head_steers_water':True,'water_direction':True,'actual_gun_pitch':True,
        'armed_unarmed_world_parity':True,'moving_head':True}
    checks.update(unfrozen_physics=True,five_degree_ladder_input=True,noclip_underwater=True,noclip_stick_alone_zero=True,noclip_hand_flight=True,noclip_land_water_parity=True)
    metrics=[];groups={}
    for row in rows:
        c=row['case'];probes=row.get('probes',[])
        if row.get('failure') or len(probes)<8:
            checks['real_ladder' if c['medium']=='ladder' else 'real_water']=False;continue
        meta=[p for p in probes if p.get('meta')]
        checks['unfrozen_physics'] &= all(p.get('frozen') is False for p in probes)
        if len(meta)<6:checks['moving_head']=False;continue
        lateral=max(p['pos'][0] for p in probes)-min(p['pos'][0] for p in probes)
        dz=probes[-1]['pos'][2]-probes[0]['pos'][2]
        errors=[];head_yaws=[];sync_deltas=[];physical_errors=[]
        for p in meta:
            m=p['meta'];head_yaws.append(m['head_yaw']);sync_deltas.append(abs((m['head_yaw']-p['sync_yaw']+180)%360-180))
            pitch=m['head_pitch']
            pa,ya=math.radians(pitch),math.radians(m['head_yaw'])
            expected=[math.cos(pa)*math.cos(ya),math.cos(pa)*math.sin(ya),-math.sin(pa)]
            if c['medium']=='ladder':
                turn=math.radians(c.get('stick_angle',0));right=[math.sin(ya),-math.cos(ya),0]
                expected=[v*math.cos(turn)+r*math.sin(turn) for v,r in zip(expected,right)]
                if c['direction']=='down':expected=[-v for v in expected]
                if c.get('stick_angle')==5:
                    checks['five_degree_ladder_input'] &= abs(math.degrees(math.atan2(abs(m.get('stick_x',0)),abs(m.get('stick_y',0))))-5)<.1
            if c['medium'].startswith('noclip_'):
                if m.get('off_pitch') is None or m.get('off_yaw') is None:
                    checks['noclip_hand_flight']=False
                else:
                    op,oy=math.radians(m['off_pitch']),math.radians(m['off_yaw'])
                    expected=[math.cos(op)*math.cos(oy),math.cos(op)*math.sin(oy),-math.sin(op)]
            if c['direction']!='idle':errors.append(angle(p['wish'],expected))
            if c.get('gun_pitch') is not None:
                checks['actual_gun_pitch'] &= m.get('gun_model_pitch') is not None and abs((m['gun_model_pitch']-c['gun_pitch']+180)%360-180)<1 and m['draws']>0 and m['weapon']=='weapon_pistol'
            if c['medium']=='water':physical_errors.append(angle([p['vel'][0],p['vel'][1],0],[expected[0],expected[1],0]))
        checks['moving_head'] &= max(head_yaws)-min(head_yaws)>.1
        if c['medium']=='ladder':
            checks['real_ladder'] &= all(p['move_type']==9 for p in probes)
            checks['no_ladder_side_button'] &= all(p['side_buttons']==0 for p in probes)
            checks['no_ladder_side_drift'] &= lateral<.1
            checks['ladder_direction'] &= abs(dz)<.1 if c['direction']=='idle' else dz*(1 if c['direction']=='up' else -1)>1
        elif c['medium']=='water':
            checks['real_water'] &= all(p['water_level']>=2 and p['move_type']==2 for p in probes)
            checks['head_steers_water'] &= bool(errors) and max(errors)<.2 and max(physical_errors)<3
            checks['water_direction'] &= dz*(1 if c['direction']=='up' else -1)>.1
        else:
            checks['noclip_underwater'] &= all(p['move_type']==8 and (p['water_level']>=2 if c['medium']=='noclip_water' else p['water_level']==0) for p in probes)
            if c['throttle']==0:
                checks['noclip_stick_alone_zero'] &= all(math.sqrt(sum(v*v for v in p['wish']))<.1 and math.sqrt(sum(v*v for v in p['vel']))<.1 for p in probes)
            else:
                checks['noclip_hand_flight'] &= bool(errors) and max(errors)<.2 and all(math.sqrt(sum(v*v for v in p['vel']))>1 for p in probes)
        speed=sum(math.sqrt(sum(v*v for v in p['wish'])) for p in probes)/len(probes)
        velocity=[sum(p['vel'][i] for p in probes)/len(probes) for i in range(3)]
        groups.setdefault((c['medium'],c['direction'],c.get('stick_angle',0)),[]).append({'error':max(errors,default=0),'speed':speed,'velocity':velocity})
        metrics.append({'id':row['id'],'case':c,'samples':len(probes),'lateral_units':lateral,'dz_units':dz,
            'max_wish_head_error_degrees':max(errors,default=0),'head_yaw_span':max(head_yaws)-min(head_yaws),
            'max_accepted_sync_delta_degrees':max(sync_deltas),'wish_speed':speed,'mean_velocity':velocity,
            'physical_head_planar_error_degrees':max(physical_errors,default=0)})
    checks['armed_unarmed_world_parity']=len(groups)==11 and all(len(v)==3 and max(r['error'] for r in v)<.2 and
        max(r['speed'] for r in v)-min(r['speed'] for r in v)<.25 and
        all(math.sqrt(sum((r['velocity'][i]-v[0]['velocity'][i])**2 for i in range(3)))<2 for r in v) for v in groups.values())
    for direction in ('idle','flight'):
        land,water=groups.get(('noclip_land',direction,0),[]),groups.get(('noclip_water',direction,0),[])
        checks['noclip_land_water_parity'] &= len(land)==len(water)==3 and all(abs(a['speed']-b['speed'])<.25 and math.sqrt(sum((a['velocity'][i]-b['velocity'][i])**2 for i in range(3)))<2 for a,b in zip(land,water))
    return {'success':all(checks.values()),'checks':checks,'metrics':metrics,
        'note':'Ladder/water are permanent gm_construct BSP geometry; ordinary weapon switching/Exit cleanup unchanged.'}


def main(argv=None):
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--package',type=Path,required=True);p.add_argument('--evidence',type=Path,required=True)
    p.add_argument('--depot-manifest',type=Path,action='append');a=p.parse_args(argv)
    original=driver.command
    def command(arguments,evidence,label,**kwargs):
        if label=='game':
            combined.quit_field(evidence)
            code='local QMEDIUM_CASES=util.JSONToTable([==['+json.dumps(cases(),separators=(',',':'))+']==])\n'+Path(__file__).with_name('vr_medium_server.lua').read_text(encoding='utf-8')
            arguments=combined.stage_fixtures(arguments,evidence,code)
            write_preferences(driver.POC/'garrysmod/addons/nlvr_q_tests')
            driver.write_json(evidence/'target-policy.json',{'targets':'gm_construct permanent world ladder brush803 and water brush330','map_bsp_sha256':driver.sha256(driver.POC/'garrysmod/maps/gm_construct.bsp'),'breakable':False,'world_entity_created_or_removed':False,'weapon_switch_and_exit_cleanup':'production unchanged','full_combined':False,'locks':'both'})
            transport=evidence/'game-arguments.json';driver.write_json(transport,[str(v) for v in arguments[1:]])
            arguments=[Path(__file__).resolve(),'--poc-arguments',transport]
        return original(arguments,evidence,label,**kwargs)
    driver.lua_script,driver.command=write_probe,command
    path=a.evidence.with_name(a.evidence.name+'-timeline.json');driver.write_json(path,timeline())
    code=driver.main(['--package',str(a.package),'--evidence',str(a.evidence),'--simulate','--both-locks',
        '--seconds',str(len(cases())*9+10),'--timeline',str(path),'--camera=-2920,-1076,-48,0,90,0','--render-scale','.65',
        *[part for m in a.depot_manifest or () for part in ('--depot-manifest',str(m))]])
    if (a.evidence/'summary.json').exists():
        result=analyse(json.loads((a.evidence/'summary.json').read_text()));driver.write_json(a.evidence/'medium-checks.json',result)
        print(json.dumps({'success':result['success'],'checks':result['checks']}));return code or (0 if result['success'] else 1)
    return code or 1

if __name__=='__main__':
    if len(sys.argv)==3 and sys.argv[1]=='--poc-arguments':raise SystemExit(combined.poc.main(json.loads(Path(sys.argv[2]).read_text())))
    raise SystemExit(main())
