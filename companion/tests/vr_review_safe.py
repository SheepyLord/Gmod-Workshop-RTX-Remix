"""Permitted limited hook/overlay review witness; never runs combined physics acceptance."""
from pathlib import Path
import argparse
import json
import sys
import vr_combined_session as combined
import vr_fixture_frames as frames
import vr_session as driver


def timeline():
    steps=[]
    for t in (0,1.8,2,4.5,4.7,6,6.2,8.5,8.8,10,12.9,13,16.9,17,18,26):
        steps.append({'time':t,'hmd':{'pos':[0,0,1.6],'ang':[0,0,0]},
            'left':{'pos':[.25,.3,1.2],'ang':[0,0,-90]},'right':{'pos':[.3,-.25,1.2],'ang':[0,0,0]},
            'actions':{'left_stick':[0,.6] if 2<=t<4.7 or 13<=t<17 else [0,0],'left_trigger_value':.5 if 2<=t<4.7 or 13<=t<17 else 0,
                'left_b':6<=t<6.2,'right_trigger':8.5<=t<8.8}})
    return frames.natural_timeline({'version':1,'steps':steps})


def analyse(summary):
    row=next((r for r in summary['records'] if r.get('kind')=='safe-overlays'),{})
    roles=row.get('roles',{});peaks=row.get('peaks',{})
    checks={'renderer':summary['success'],'actual_peers_hands_movement_menu':combined.exercised_peers(summary['records'],True),
        'all_21_roles':row.get('visible')==21 and len(roles)==21 and all(r.get('visible') and r.get('handle') for r in roles.values()),
        'v4_roles':all(roles.get(key,{}).get('visible') for key in ('ammo','tool','wheel')),
        'native_bound_32':0<peaks.get('native',0)<=32,'pending_request_bound_16':0<peaks.get('pending_sources',0)<=16,
        'menu_action':row.get('menu_action') is True}
    return {'success':all(checks.values()),'checks':checks,'overlays':row,
        'note':'21-role diagnostic resource composition; not full combined acceptance or a production simultaneous-menu state.'}


def main(argv=None):
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--package',type=Path,required=True);p.add_argument('--evidence',type=Path,required=True)
    p.add_argument('--simulate',action='store_true');p.add_argument('--render-scale',type=float,default=.65);args=p.parse_args(argv)
    original_script,original_command=driver.lua_script,driver.command
    def script(path,config):
        config['q_controller_profiles']=frames.profiles();original_script(path,config)
        text=frames.inject(combined.moving_base(path.read_text(encoding='utf-8')))
        clock=Path(__file__).with_name('vr_combined_clock.lua').read_text(encoding='utf-8')
        text='local QSafeClock=(function()\n'+clock+'\nend)()\nlocal qSafeClock\n'+text
        marker='originalBegin, originalCamera, originalCreate = native.BeginFrame, native.SetFrameCamera, native.OverlayCreate'
        setup='''qSafeClock=QSafeClock.New{Native=native,Steps=util.JSONToTable([==[%s]==]),BeginAt=0,
EngineTime=function() return engine.TickCount()*engine.TickInterval() end,WallTime=SysTime,Paused=function() return gui.IsGameUIVisible() end}
''' % json.dumps(timeline()['steps'],separators=(',',':'))
        text=combined.checked_replace(text,marker,setup+marker)
        text=combined.checked_replace(text,'local t = now - activeAt','local t = qSafeClock and native.TestState().time or now-activeAt')
        marker='native.BeginFrame, native.SetFrameCamera, native.OverlayCreate, native.Capture = originalBegin, originalCamera, originalCreate, originalCapture'
        text=combined.checked_replace(text,marker,marker+'\n        if qSafeClock then emit("safe-clock",qSafeClock.Stats()) qSafeClock.Stop() end')
        text=text.replace('RunConsoleCommand("nlvr_q_hud")','do end').replace('RunConsoleCommand("nlvr_q_hud", "restore")','do end')
        text+='\ndo\n'+Path(__file__).with_suffix('.lua').read_text(encoding='utf-8')+'\nend\n'
        path.write_text(text,encoding='utf-8')
    def command(arguments,evidence,label,**kwargs):
        if label=='game':
            combined.quit_field(evidence)
            server='''local W=include("nlvr/modules/sh_weapons.lua") W.RegisterHands()
local p=Entity(1) if not p:HasWeapon("nlvr_hands") then p:Give("nlvr_hands",true) end p:SelectWeapon("nlvr_hands")'''
            arguments=combined.stage_fixtures(arguments,evidence,server)
            driver.write_json(evidence/'limited-review-policy.json',{'full_combined':False,'targets':'none','damage':False,'world_entity_removal':False,'production_vr_cleanup':'unchanged'})
            transport=evidence/'game-arguments.json';driver.write_json(transport,[str(a) for a in arguments[1:]])
            arguments=[Path(__file__).resolve(),'--poc-arguments',transport]
        return original_command(arguments,evidence,label,**kwargs)
    driver.lua_script,driver.command=script,command
    path=args.evidence.with_name(args.evidence.name+'-timeline.json');driver.write_json(path,timeline())
    code=driver.main(['--package',str(args.package),'--evidence',str(args.evidence),'--seconds','22','--timeline',str(path),
        '--camera','0,0,512,0,0,0','--render-scale',str(args.render_scale),*(['--simulate'] if args.simulate else [])])
    if (args.evidence/'summary.json').exists():
        result=analyse(json.loads((args.evidence/'summary.json').read_text()));driver.write_json(args.evidence/'safe-acceptance.json',result)
        print(json.dumps({'success':result['success'],'checks':result['checks']}));return code or (0 if result['success'] else 1)
    return code or 1


if __name__=='__main__':
    if len(sys.argv)==3 and sys.argv[1]=='--poc-arguments':raise SystemExit(combined.poc.main(json.loads(Path(sys.argv[2]).read_text())))
    raise SystemExit(main())
