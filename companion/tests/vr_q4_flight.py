"""Q4 armed +/-45 degree noclip flight under natural controller frames and ULib."""
from pathlib import Path
import argparse
import json
import sys
import vr_combined_session as combined
import vr_fixture_frames as frames
import vr_session as driver


def timeline():
    steps=[]
    for index in range(4):
        main='left' if index>=2 else 'right'
        off='right' if index>=2 else 'left'
        for t in (0,.8,1,3.9,4.1,4.8):
            poses={'left':{'pos':[.3,.25,1.2],'ang':[0,0,0]},'right':{'pos':[.4,-.25,1.2],'ang':[0,0,0]}}
            poses[main]['ang'][0]=45 if index%2==0 else -45
            steps.append({'time':index*5+t,'hmd':{'pos':[0,0,1.6],'ang':[0,0,0]},**poses,
                'actions':{off+'_stick':[0,.7 if 1<=t<4 else 0],off+'_trigger_value':.75 if 1<=t<4 else 0}})
    steps.append({**steps[-1],'time':30})
    return frames.natural_timeline({'version':1,'steps':steps})


def analyse(summary):
    rows=summary['records']
    travel=[r for r in rows if r.get('kind')=='Q4-flight-travel']
    command=[r for r in rows if r.get('kind')=='Q4-flight-command']
    hooks=[r for r in rows if r.get('kind') in ('peer-start','peer-exit','peer-final')]
    peer=next((r for r in hooks if r.get('kind')=='peer-final'),{})
    checks={'renderer':summary['success'], 'all_trials':{r['case'] for r in travel}==set(range(4)),
        'flight_direction':len(travel)==4 and all(r['units'][0]>20 and abs(r['units'][1])<.4 and abs(r['units'][2])<.4 for r in travel),
        'command_direction':all(sum(r['case']==i for r in command)>=5 for i in range(4)) and all(r['cosine']>.99999 and abs(r['up'])<.02 and abs(r['gun_pitch'])>30 for r in command),
        'ulib_two_cycles':combined.exercised_peers(rows)}
    return {'success':all(checks.values()),'checks':checks,'travel':travel,'command_samples':len(command),'hook_lifecycle':hooks}


def main(argv=None):
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--package',type=Path,required=True);p.add_argument('--evidence',type=Path,required=True)
    p.add_argument('--simulate',action='store_true');args=p.parse_args(argv)
    original_script,original_command=driver.lua_script,driver.command
    def script(path,config):
        config['q_controller_profiles']=frames.profiles()
        original_script(path,config)
        text=frames.inject(combined.moving_base(path.read_text(encoding='utf-8')))
        text+='\ndo\n'+Path(__file__).with_suffix('.lua').read_text(encoding='utf-8')+'\nend\n'
        path.write_text(text,encoding='utf-8')
    def command(arguments,evidence,label,**kwargs):
        if label=='game':
            combined.quit_field(evidence)
            server='''concommand.Add("nlvr_q4_flight",function(_,_,args)
local p=Entity(1) if not IsValid(p) or not NLVR_SV or not NLVR_SV.Players[p] then return end
p:SetMoveType(MOVETYPE_NOCLIP)
if not p:HasWeapon("weapon_pistol") then p:Give("weapon_pistol",true) end
p:SelectWeapon("weapon_pistol")
end)'''
            arguments=combined.stage_fixtures(arguments,evidence,server)
            transport=evidence/'game-arguments.json';driver.write_json(transport,[str(x) for x in arguments[1:]])
            arguments=[Path(__file__).resolve(),'--poc-arguments',transport]
        return original_command(arguments,evidence,label,**kwargs)
    driver.lua_script,driver.command=script,command
    path=args.evidence.with_name(args.evidence.name+'-timeline.json');driver.write_json(path,timeline())
    result=driver.main(['--package',str(args.package),'--evidence',str(args.evidence),'--seconds','22','--timeline',str(path),
        '--camera','823,-657,-79,0,0,0',*(['--simulate'] if args.simulate else [])])
    if (args.evidence/'summary.json').exists():
        checked=analyse(json.loads((args.evidence/'summary.json').read_text()))
        driver.write_json(args.evidence/'flight-checks.json',checked)
        print(json.dumps({'success':checked['success'],'checks':checked['checks']}))
        return result or (0 if checked['success'] else 1)
    return result or 1


if __name__=='__main__':
    if len(sys.argv)==3 and sys.argv[1]=='--poc-arguments':
        raise SystemExit(combined.poc.main(json.loads(Path(sys.argv[2]).read_text())))
    raise SystemExit(main())
