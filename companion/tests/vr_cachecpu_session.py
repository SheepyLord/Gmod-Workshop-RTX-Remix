"""Stationary simulated CPU control using the unchanged production VR driver/rollback."""
from pathlib import Path
import argparse
import json
import sys

ROOT=Path(__file__).resolve().parents[2]
sys.path[:0]=[str(ROOT/'tools'),str(Path(__file__).parent)]
import vr_combined_session as q


def fixture(base):
    base=q.moving_base(base)
    base=q.checked_replace(base,'if t >= math.min(48, CONFIG.seconds - 5) and not changed then','if t >= 33 and not changed then')
    base=q.checked_replace(base,'if changed and t >= math.min(50, CONFIG.seconds - 3) then','if changed and t >= 34 then')
    return base+'\ndo\n'+Path(__file__).with_name('vr_cachecpu_probe.lua').read_text(encoding='utf-8')+'\nend\n'


SERVER='''
concommand.Add("nlvr_cachecpu_begin",function(p)
 if not IsValid(p) then p=Entity(1) end
 p:SelectWeapon("nlvr_hands") p:SetMoveType(MOVETYPE_NOCLIP) p:SetVelocity(-p:GetVelocity())
end)
concommand.Add("nlvr_cachecpu_health",function(p,_,a)
 if not IsValid(p) then p=Entity(1) end
 local sv=NLVR_SV local s=sv and sv.Players[p] if not s then return end
 local active=true for _,entry in ipairs(sv.Registry.entries) do active=active and entry.active and not entry.stopped end
 print("NLVR_Q "..util.TableToJSON{kind="Q-cachecpu-health",label=a[1],modules_live=active,
  proxies=IsValid(s.interact.left.phys) and IsValid(s.interact.right.phys),sync_age=CurTime()-(s.lastSync or 0),
  weapon=IsValid(p:GetActiveWeapon()) and p:GetActiveWeapon():GetClass()})
end)
'''


def analyse(summary):
    record=next((r for r in summary['records'] if r.get('kind')=='Q-cachecpu'),{})
    rows=record.get('rows',{})
    health={r['label']:r for r in summary['records'] if r.get('kind')=='Q-cachecpu-health'}
    checks={'renderer':summary['success'],'samples':all(rows.get(k,{}).get('frames',0)>=200 for k in ('cached','uncached')),
            'healthy':all(health.get(k,{}).get('modules_live') is True and health[k].get('proxies') is True and
                          health[k].get('sync_age',100)<.3 and health[k].get('weapon')=='nlvr_hands' for k in ('begin','end'))}
    for r in rows.values():
        if r.get('frames'):
            r['cpu_ms_per_frame']=r['cpu_ms']/r['frames']
            r['cycles_per_frame']=r['cycles']/r['frames']
    checks['actual_cache_control']=(rows.get('uncached',{}).get('passes',0)>.95*rows.get('uncached',{}).get('calls',1) and
                                    rows.get('cached',{}).get('passes',1)<.5*rows.get('cached',{}).get('calls',0))
    return {'success':all(checks.values()),'checks':checks,'measurement':record,'health':health}


def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--package',type=Path,required=True)
    p.add_argument('--evidence',type=Path,required=True)
    p.add_argument('--inspect-dll',type=Path,required=True)
    args=p.parse_args()
    driver=q.driver
    original_script,original_command=driver.lua_script,driver.command
    def script(path,config):
        original_script(path,config)
        path.write_text(fixture(path.read_text(encoding='utf-8'))+'\ndo\n'+
            Path(__file__).with_name('vr_measure_probe.lua').read_text(encoding='utf-8')+'\nend\n',encoding='utf-8')
    def command(arguments,evidence,label,**kwargs):
        if label=='game':
            q.quit_field(evidence)
            server=SERVER+'\ndo\n'+Path(__file__).with_name('vr_measure_server.lua').read_text(encoding='utf-8')+'\nend\n'
            arguments=q.stage_fixtures(arguments,evidence,server)
            transport=evidence/'game-arguments.json'
            driver.write_json(transport,[str(v) for v in arguments[1:]])
            arguments=[Path(q.__file__).resolve(),'--poc-arguments',transport]
        return original_command(arguments,evidence,label,**kwargs)
    driver.lua_script,driver.command=script,command
    timeline=driver.inside_out(args.evidence,driver.main_checkout()).with_name(args.evidence.name+'-timeline.json')
    pose={'hmd':{'pos':[0,0,1.6],'ang':[0,0,0]},'left':{'pos':[.25,.2,1.2],'ang':[0,0,0]},
          'right':{'pos':[.25,-.2,1.2],'ang':[0,0,0]},'actions':{}}
    driver.write_json(timeline,{'version':1,'steps':[{'time':t,**pose} for t in (0,40)],'events':[]})
    code=driver.main(['--package',str(args.package),'--evidence',str(args.evidence),'--simulate','--seconds','35',
                      '--timeline',str(timeline),'--camera','823,-657,-79,0,0,0','--inspect-dll',str(args.inspect_dll)])
    if not (args.evidence/'summary.json').exists():return code or 1
    summary=json.loads((args.evidence/'summary.json').read_text(encoding='utf-8'))
    result=analyse(summary)
    from vr_measure import accounting,accounting_checks
    accounting_data=accounting(summary)
    observed_checks=accounting_checks(accounting_data)
    # This stationary control deliberately generates no changed server state after
    # attachment. Dynamic state sends are required by the combined acceptance instead.
    result['checks']['accounting_callbacks']=all(v for k,v in observed_checks.items() if k!='server_state_observed')
    result['accounting_checks']=observed_checks
    result['accounting_scope']='Stationary callback/sync/off evidence; changed-state sends may be zero. Combined acceptance requires them.'
    result['success']=all(result['checks'].values())
    driver.write_json(args.evidence/'cpu-network.json',accounting_data)
    driver.write_json(args.evidence/'cachecpu-acceptance.json',result)
    print(json.dumps({'success':result['success'],'checks':result['checks']}))
    return code or (0 if result['success'] else 1)


if __name__=='__main__':raise SystemExit(main())
