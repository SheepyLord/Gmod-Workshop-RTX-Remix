"""Run R's controlled scenes through the current production VR session driver."""
import argparse
import json
from pathlib import Path
import sys

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / 'tools'))
import vr_session as driver


def sweep_timeline():
    steps = []
    for start, depth in ((0,.15),(16,.2),(32,.3),(48,.4),(64,.6)):
        for t in (start, start+15):
            steps.append({'time':t,'hmd':{'pos':[0,0,1.6],'ang':[0,0,0]},
                          'left':{'pos':[depth+.03,0,1.6],'ang':[0,0,0]},
                          'right':{'pos':[.8,-.4,1.2],'ang':[0,0,0]}})
    steps.append({**steps[-1], 'time':100})
    return {'version':1,'steps':steps}


def main(argv=None):
    parser=argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--case',choices=('barrel','ghost','near','sweep'),required=True)
    parser.add_argument('--distance',type=float,default=.4)
    parser.add_argument('--steady-neutral',action='store_true')
    args,options=parser.parse_known_args(argv)
    if args.case=='sweep':
        if '--timeline' in options:parser.error('sweep supplies its own timeline')
        driver.timeline=lambda seconds:sweep_timeline()
    original=driver.lua_script
    def script(path,settings):
        settings['v2r_case']='near' if args.case=='sweep' else args.case
        settings['v2r_near']=args.distance
        original(path,settings)
        text=path.read_text(encoding='utf-8')
        prefix='''
local rCleanupTasks={}
local rHandDraw,rNoHandDraw
rNoHandDraw=function() end
hook.Add("PreRender","v2r.mask_hands",function()
    local hooks=hook.GetTable().PreDrawTranslucentRenderables or {}
    local current=hooks["nlvr.hands"]
    if current and current~=rNoHandDraw then
        rHandDraw=current hook.Add("PreDrawTranslucentRenderables","nlvr.hands",rNoHandDraw)
    end
end)
local function rSceneStop()
    hook.Remove("PreRender","v2r.mask_hands") hook.Remove("Think","v2r.range")
    local hooks=hook.GetTable().PreDrawTranslucentRenderables or {}
    if hooks["nlvr.hands"]==rNoHandDraw then
        hook.Remove("PreDrawTranslucentRenderables","nlvr.hands")
        if rHandDraw and NativeLoaderVR.state~="off" then hook.Add("PreDrawTranslucentRenderables","nlvr.hands",rHandDraw) end
    end
    for _,fn in ipairs(rCleanupTasks) do fn() end
end
'''
        # The production driver owns every lock, setup stage, screenshot, quit and rollback.
        marker='-- Real-package V1 acceptance probe,'
        assert text.count(marker)==1,'production probe marker changed'
        text=text.replace(marker,prefix+'\n'+marker,1)
        text=text.replace('local function finish(success)\n','local function finish(success)\n    rSceneStop()\n',1)
        if args.case=='sweep':
            for label in ('yaw-plus20','yaw-minus20','lean-left'):
                text=text.replace('capture("'+label+'")','do end')
            marker='        if t >= 3 then capture("neutral") end'
            assert text.count(marker)==1
            text=text.replace(marker,marker+'''
        local state=native.TestState()
        local time=state and state.time or 0
        for _,item in ipairs({{10,"near-015"},{26,"near-020"},{42,"near-030"},{58,"near-040"},{74,"far-060"}}) do
            if time>=item[1] and not captures[item[2]] then capture(item[2]) break end
        end
''',1)
        if args.steady_neutral:
            if args.case!='ghost':raise ValueError('steady-neutral requires the ghost scene')
            marker='        if t >= 3 then capture("neutral") end'
            assert text.count(marker)==1
            text=text.replace(marker,marker+'''
        local steadyState=native.TestState()
        local steadyTime=steadyState and steadyState.time or 0
        if steadyTime>=8 and steadyTime<10 and not captures["neutral-steady"] then capture("neutral-steady") end
''',1)
        text+='\n'+(ROOT/'runtime/vr_v2_scene.lua').read_text(encoding='utf-8')
        text+='''
local rNextSample=0
hook.Add("Think","v2r.range",function()
    if not native or not native.TestState or SysTime()<rNextSample then return end
    rNextSample=SysTime()+1
    local state=native.TestState()
    if state and lastCamera then emit("r-range",{time=state.time,sequence=lastCamera.sequence,phase=phase}) end
end)
'''
        path.write_text(text,encoding='utf-8')
    driver.lua_script=script
    class SceneLock(driver.ExclusiveLock):
        def __init__(self,path,task,timeout=3600):
            super().__init__(path,'VR-V2-R',timeout=timeout)
    driver.ExclusiveLock=SceneLock
    return driver.main(options)


if __name__=='__main__':
    raise SystemExit(main())
