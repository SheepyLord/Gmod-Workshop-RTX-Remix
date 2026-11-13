"""Exercise the real --look path in a fresh Python venv with no Pillow or pip."""
from __future__ import annotations
import argparse
import importlib.util
import json
from pathlib import Path
import subprocess
import sys

ROOT=Path(__file__).resolve().parents[1]
sys.path[:0]=[str(ROOT/'tools'),str(ROOT/'companion/tests')]
import vr_session as driver


def child(package,evidence):
    if importlib.util.find_spec('PIL') is not None:
        raise RuntimeError('The look validation interpreter unexpectedly has Pillow')
    import vr_combined_session as combined
    original_script,original_command,lock=driver.lua_script,driver.command,driver.ExclusiveLock
    def script(path,config):
        original_script(path,config)
        extra='''
local lookStart,lookRunning,lookCaptured,lookEndingAt
hook.Add("PreRender","q_no_pillow_look",function()
 if not lookStart and SysTime()-began>=5 then
  lookStart=SysTime() RunConsoleCommand("nl_vr_start")
 elseif lookStart and NativeLoaderVR.state=="running" then
  lookRunning=lookRunning or SysTime()
  local info=nlvr.Info()
  if SysTime()-lookRunning>=5 and not lookCaptured then
   lookCaptured=true local ok,detail=nlvr.Capture("no-pillow-look",15)
   emit("capture",{label="no-pillow-look",ok=ok,detail=detail})
   emit("Q-look-proof",{info=info,python_has_pillow=false})
   if info.framesSubmitted<10 or info.submitErrors~=0 or info.posesUnmatched~=0 then errors[#errors+1]="manual look counters failed" end
  end
  if lookCaptured and SysTime()-lookRunning>=7 and not lookEndingAt then
   lookEndingAt=SysTime() RunConsoleCommand("nl_vr_demo_done") hook.Remove("PreRender","q_no_pillow_look")
  end
 elseif lookStart and NativeLoaderVR.state=="failed" then
  errors[#errors+1]="look start failed: "..tostring(NativeLoaderVR.detail)
  RunConsoleCommand("nl_vr_demo_done") hook.Remove("PreRender","q_no_pillow_look")
 elseif lookStart and SysTime()-lookStart>45 then
  errors[#errors+1]="look start timeout" RunConsoleCommand("nl_vr_demo_done") hook.Remove("PreRender","q_no_pillow_look")
 end
end)
'''
        with path.open('a',encoding='utf-8') as stream:stream.write('\ndo\n'+extra+'\nend\n')
    def command(arguments,folder,label,**kwargs):
        if label=='game':combined.quit_field(folder)
        return original_command(arguments,folder,label,**kwargs)
    class LookLock(lock):
        def __init__(self,path,task,timeout=7200):super().__init__(path,'VR-V2V3-Q no-Pillow look',timeout)
    driver.lua_script,driver.command,driver.ExclusiveLock=script,command,LookLock
    code=driver.main(['--package',str(package),'--evidence',str(evidence),'--look','--seconds','70'])
    if (evidence/'summary.json').exists():
        summary=json.loads((evidence/'summary.json').read_text(encoding='utf-8'))
        proof=[r for r in summary['records'] if r.get('kind')=='Q-look-proof']
        result={'success':summary['success'] and bool(proof),'python':sys.executable,'pillow_present':False,
                'pip_present':importlib.util.find_spec('pip') is not None,'proof':proof,
                'termination':'nl_vr_demo_done, then standard normal quit and rollback'}
        driver.write_json(evidence/'no-pillow-look.json',result)
        return code or (0 if result['success'] else 1)
    return code or 1


def main(argv=None):
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--package',type=Path,required=True)
    p.add_argument('--evidence',type=Path,required=True)
    p.add_argument('--venv',type=Path,required=True,help='new venv folder below out')
    a=p.parse_args(argv)
    venv=driver.inside_out(a.venv,driver.main_checkout())
    if venv.exists():p.error('use a fresh venv folder; this validation installs no packages')
    subprocess.run([sys.executable,'-m','venv','--without-pip',str(venv)],cwd=ROOT,check=True)
    python=venv/'Scripts/python.exe'
    run=subprocess.run([str(python),str(Path(__file__).resolve()),'--child',str(a.package.resolve()),str(a.evidence.resolve())],cwd=ROOT)
    return run.returncode


if __name__=='__main__':
    if len(sys.argv)==4 and sys.argv[1]=='--child':raise SystemExit(child(Path(sys.argv[2]),Path(sys.argv[3])))
    raise SystemExit(main())
