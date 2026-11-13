"""One-command frozen-package full VR sequence, gated until Claude reviews the fixes repair."""
from pathlib import Path
import argparse
import json
import subprocess
import sys
import vr_session as driver

ROOT=Path(__file__).resolve().parents[2]


def plan(root,simulate,inspect_dll=None):
    import vr_weapons_poc as w
    import vr_reload_poc as k
    base=ROOT/'companion/tests'
    inspect_dll=inspect_dll or ROOT/'out/vr/v2q/inspect/gmcl_nlvrqinspect_win64.dll'
    steps=[('v2v3','combined','vr_combined_session.py',['--case','combined','--fixes-reviewed','--inspect-dll',str(inspect_dll)]),
           ('motion','allmotion','vr_combined_session.py',['--case','allmotion','--fixes-reviewed','--inspect-dll',str(inspect_dll)]),
           ('temporal','temporal','vr_combined_session.py',['--case','temporal','--fixes-reviewed','--inspect-dll',str(inspect_dll)]),
           ('flight','flight','vr_q4_flight.py',[]),
           ('hooks','integration','vr_q4_integration.py',['--fixes-reviewed'])]
    phases=[p for p in w.PHASES[len(w.CLASSES):] if p!='left']
    classes=','.join(k.CLASSES)
    for hand in ('right','left'):
        suffix='r' if hand=='right' else 'l';flag=['--left-hand'] if hand=='left' else []
        geometry=flag+['--seconds','130','--skeleton-reference',str(base/'fixtures/vr_index_skeletons.json')]
        if not simulate:geometry+=['--recorded-controllers']
        steps.append(('geo-'+suffix,'geometry','vr_v4_geometry.py',geometry))
        steps.append(('guns-'+suffix,'weapons','vr_weapons_poc.py',flag+['--weapons-phases',','.join(phases),'--seconds',str(len(phases)*4+5)]))
        steps.append(('cal-'+suffix,'calibration','vr_reload_poc.py',flag+['--calibrate','--classes',classes,'--seconds','15']))
        calibration=str(root/('cal-'+suffix)/'reload.json')
        for name,role,extra,seconds,selected in (
            ('reload','reload',['--counter-motion'],156,classes),('button','button',['--button'],165,classes+',nlvr_k_swep'),
            ('empty','empty',['--empty'],145,classes)):
            steps.append((name+'-'+suffix,role,'vr_reload_poc.py',flag+['--classes',selected,'--calibration',calibration,'--seconds',str(seconds),*extra]))
        steps.append(('tools-'+suffix,'tools','vr_tools_poc.py',flag+['--tools-case','features','--seconds','60']))
    return steps


def semantic(folder,role):
    if role=='weapons':
        import vr_weapons_analyse as check
        result=check.analyse(folder);driver.write_json(folder/'weapons-checks.json',result);return result['success']
    if role in ('reload','button','empty'):
        import vr_reload_analyse as check
        return check.analyse(folder,button=role=='button',empty=role=='empty')['success']
    if role=='tools':
        import vr_tools_check as check
        result=check.evaluate(folder);driver.write_json(folder/'tools-acceptance.json',result);return result['success']
    filename={'combined':'combined-acceptance.json','allmotion':'allmotion-acceptance.json','temporal':'temporal-acceptance.json',
        'flight':'flight-checks.json','integration':'integration-checks.json','geometry':'muzzle-checks.json','calibration':'reload-receipt.json'}[role]
    return json.loads((folder/filename).read_text())['success']


def resolved_attempt(folder):
    while (folder/'crash.json').exists():
        data=json.loads((folder/'crash.json').read_text())
        retry=data.get('retry',{})
        if retry.get('exit')==0 and retry.get('evidence'):folder=Path(retry['evidence'])
        else:break
    return folder


def main(argv=None):
    p=argparse.ArgumentParser(description=__doc__);p.add_argument('--package',type=Path,required=True);p.add_argument('--evidence',type=Path,required=True)
    p.add_argument('--simulate',action='store_true');p.add_argument('--fixes-reviewed',action='store_true')
    p.add_argument('--inspect-dll',type=Path,default=ROOT/'out/vr/v2q/inspect/gmcl_nlvrqinspect_win64.dll');args=p.parse_args(argv)
    if not args.fixes_reviewed:p.error('full sequence disabled until Claude confirms the fixes repair; no game prepared')
    if not args.inspect_dll.is_file():p.error('build the read-only clock helper with tools/vr_measure_build.ps1 before the full sequence')
    package=args.package.resolve();root=driver.inside_out(args.evidence,driver.main_checkout())
    if root.exists():raise ValueError('full sequence needs a fresh evidence folder')
    root.mkdir(parents=True)
    identity={'package':str(package),'sha256':driver.sha256(package),'simulate':args.simulate,'cases':[],'success':False,
        'scope':'operator-reviewed fixed package only; no old package measurements transferred'}
    driver.write_json(root/'sequence.json',identity)
    for name,role,script,extra in plan(root,args.simulate,args.inspect_dll):
        folder=root/name
        extra=list(extra)
        if '--calibration' in extra:
            index=extra.index('--calibration')+1;path=Path(extra[index]);extra[index]=str(resolved_attempt(path.parent)/path.name)
        command=[sys.executable,'-B',str(ROOT/'companion/tests'/script),'--package',str(package),'--evidence',str(folder),*extra]
        if args.simulate:command.append('--simulate')
        with (root/(name+'.log')).open('w',encoding='utf-8') as log:run=subprocess.run(command,cwd=ROOT,stdout=log,stderr=subprocess.STDOUT)
        actual=resolved_attempt(folder)
        result={'name':name,'role':role,'original':str(folder),'actual':str(actual),'exit':run.returncode,'success':False}
        if run.returncode==0:
            try:result['success']=bool(semantic(actual,role))
            except (OSError,KeyError,ValueError) as error:result['error']=str(error)
        identity['cases'].append(result);driver.write_json(root/'sequence.json',identity)
        print(name, 'PASS' if result['success'] else 'FAIL',flush=True)
        if not result['success']:return 1
    identity['success']=True;driver.write_json(root/'sequence.json',identity);return 0


if __name__=='__main__':raise SystemExit(main())
