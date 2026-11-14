"""Combined fixture contracts and fail-closed acceptance; no game or OpenVR starts."""
from pathlib import Path
import json
import subprocess
import sys
import tempfile
import unittest
from unittest import mock
from types import SimpleNamespace

ROOT = Path(__file__).resolve().parents[2]
sys.path[:0] = [str(ROOT/'companion/tests'), str(ROOT/'tools')]
import vr_combined_session as q
import vr_session as driver
from test_mmd_alpha import LUAJIT


class CombinedTests(unittest.TestCase):
    def test_field_quit_crash_exit5_stops_before_any_game_launch(self):
        scratch=ROOT/'out/tmp';scratch.mkdir(parents=True,exist_ok=True)
        with tempfile.TemporaryDirectory(dir=scratch) as tmp:
            with mock.patch.object(q.poc,'game_processes',return_value=[77]),mock.patch.object(q.driver,'main_checkout',return_value=ROOT),mock.patch.object(q.subprocess,'run',return_value=SimpleNamespace(returncode=5)) as helper:
                with self.assertRaisesRegex(RuntimeError,'field quit'):
                    q.quit_field(Path(tmp))
            self.assertEqual(json.loads((Path(tmp)/'field-quit.json').read_text())['exit'],5)
            self.assertEqual(helper.call_count,1)

    @unittest.skipUnless(LUAJIT, 'LuaJIT is not installed')
    def test_quit_native_deadline_after_page_off(self):
        source=(ROOT/'tools/vr_session.lua').read_text(encoding='utf-8')
        branch=source.split('        if CONFIG.test_quit then\n',1)[1].split('        if t >= 3 then',1)[0]
        lua='''local native={State=function() return "stopping" end,Info=function() return {} end}
local NativeLoaderVR={state="off"} local errors={} local t,changed,now=26,true,26
local finished=false local function finish(ok) assert(ok==false) finished=true end
local function flat_settled() return false end local function emit() end
local gui={HideGameUI=function() end} local function CurTime() return now end
local function step() if true then %s end
step() assert(finished and #errors==1,"native stopping outlived the 25-second quit deadline")
''' % branch
        run=subprocess.run([LUAJIT,'-e',lua],capture_output=True,text=True)
        self.assertEqual(run.returncode,0,run.stdout+run.stderr)

    def test_release_bridge_includes_the_complete_ulib_core_suite(self):
        import test_companion_vr as bridge
        loader=unittest.TestLoader()
        ulib=bridge.VRULibTests
        self.assertEqual(loader.loadTestsFromTestCase(ulib).countTestCases(),loader.loadTestsFromTestCase(bridge.VRTests).countTestCases())
        self.assertIn('test_f_movers_ladder_water',loader.getTestCaseNames(ulib))
        self.assertIn('test_f_competing_addon_lifecycle',loader.getTestCaseNames(ulib))

    def test_full_sequence_is_blocked_before_any_native_preparation(self):
        from unittest import mock
        import vr_full_sequence
        with mock.patch.object(driver,'main',side_effect=AssertionError('native preparation must stay blocked')):
            for run in (q.main,vr_full_sequence.main):
                with self.subTest(entry=run.__module__),self.assertRaises(SystemExit):
                    run(['--case','combined','--package','not-used','--evidence','out/tmp/not-prepared'] if run is q.main else ['--package','not-used','--evidence','out/tmp/not-prepared'])

    def test_full_sequence_requires_cpu_observation_and_each_hand_matrix(self):
        import vr_full_sequence
        steps=vr_full_sequence.plan(ROOT/'out/tmp/full-plan',True,Path('clock-observer.dll'))
        first=steps[0][3]
        self.assertEqual(first[first.index('--inspect-dll')+1],'clock-observer.dll')
        self.assertTrue({'allmotion','temporal','flight'}<={s[1] for s in steps})
        for hand in ('r','l'):
            self.assertTrue({name+'-'+hand for name in ('geo','guns','cal','reload','button','empty','tools')}<={s[0] for s in steps})
        self.assertTrue(all('--left-hand' in s[3] for s in steps if s[0].endswith('-l')))

    def test_full_sequence_missing_clock_refuses_before_creating_evidence(self):
        import vr_full_sequence
        scratch=ROOT/'out/tmp';scratch.mkdir(parents=True,exist_ok=True)
        with tempfile.TemporaryDirectory(dir=scratch) as tmp:
            target=Path(tmp)/'never-prepared'
            with self.assertRaises(SystemExit):
                vr_full_sequence.main(['--fixes-reviewed','--package','not-used','--inspect-dll',str(Path(tmp)/'missing.dll'),'--evidence',str(target)])
            self.assertFalse(target.exists())

    @unittest.skipUnless(LUAJIT, 'LuaJIT is not installed')
    def test_natural_handed_wkt_observers_generate_valid_chunks(self):
        import vr_v4_fixture as adapter
        scratch=ROOT/'out/tmp';scratch.mkdir(parents=True,exist_ok=True)
        with tempfile.TemporaryDirectory(dir=scratch,prefix='q4r-adapted-') as tmp:
            path=Path(tmp)/'chunk.lua'
            for role in ('weapons','reload','tools'):
                for left in (False,True):
                    config={'seconds':60,'simulate':True}
                    adapter.configure(config,role,left,{'steps':[]})
                    driver.lua_script(path,config)
                    text=path.read_text(encoding='utf-8')+'\ndo\n'+(ROOT/'companion/tests'/adapter.CLIENTS[role]).read_text(encoding='utf-8')+'\nend\n'
                    text=adapter.prepare(text,role,left);path.write_text(text,encoding='utf-8')
                    run=subprocess.run([LUAJIT,'-e','assert(loadfile([=['+path.as_posix()+']=]))'],capture_output=True,text=True)
                    self.assertEqual(run.returncode,0,run.stdout+run.stderr)
                    self.assertIn('live_selectors_checked',text)

    @unittest.skipUnless(LUAJIT,'LuaJIT not installed')
    def test_moving_probe_initializes_neutral_yaw_without_overwriting_live_movers(self):
        source=q.moving_base((ROOT/'tools/vr_session.lua').read_text())
        marker='if not CONFIG.look then\n    hook.Add("CreateMove",ID,'
        start=source.find(marker)
        block='' if start<0 else source[start:source.index('\nif CONFIG.flat then',start)]
        lua='''local root=[=[%s]=]
local hook={} HOOK_MONITOR_HIGH=-2
assert(loadfile(root.."/companion/tests/vr_hook_fixture.lua"))().New("ulib",nil,hook)
local CONFIG={look=false} local ID="fixture" local angles={y=90} local NLVR
%s
local c={angle={y=118.5},x=1295,y=17,forward=99,buttons=16}
function c:SetViewAngles(a) self.angle=a end
function c:ClearMovement() self.forward=0 end function c:ClearButtons() self.buttons=0 end
function c:SetMouseX(n) self.x=n end function c:SetMouseY(n) self.y=n end
hook.Run("CreateMove",c)
assert(c.angle.y==90 and c.x==0 and c.y==0,"fixture neutral yaw/physical input not initialized")
NLVR={} c.angle={y=123};c.x=40
hook.Add("CreateMove","core",function(cmd)
 assert(cmd.x==0,"physical mouse reached core before scripted movers")
 cmd.forward=112;cmd.buttons=8;cmd.x=77
end)
hook.Run("CreateMove",c)
assert(c.angle.y==123 and c.forward==112 and c.buttons==8 and c.x==77,"probe overwrote live/scripted movement")
''' % (ROOT.as_posix(),block)
        run=subprocess.run([LUAJIT,'-e',lua],capture_output=True,text=True)
        self.assertEqual(run.returncode,0,run.stdout+run.stderr)

    @unittest.skipUnless(LUAJIT,'LuaJIT not installed')
    def test_finger_witness_reads_engine_cache_not_command_angles(self):
        lua='''local root=[=[%s]=]
assert(loadfile(root.."/companion/tests/vr_stubs.lua"))().Math()
IsValid=function(e) return e and e.valid end
local witness=assert(loadfile(root.."/companion/tests/vr_finger_witness.lua"))().New()
local parent=Angle(20,30,40)
local function matrix(a) return {GetAngles=function() return a end} end
local model={valid=true,cache={},reads=0}
function model:GetModel() return "generated" end
function model:LookupBone(n) if n:match("_Hand$") then return 0 end local f=tonumber(n:match("_Finger([0-4])$")) return f and f+1 end
function model:GetBoneMatrix(id) self.reads=self.reads+1 return self.cache[id] end
function model:GetManipulateBoneAngles() error("commanded angles are not a draw witness") end
model.cache[0]=matrix(parent)
for f=0,4 do local _,a=LocalToWorld(Vector(),Angle(),Vector(),parent) model.cache[f+1]=matrix(a) end
witness.Observe("right",model,62.3,10,true)
-- Commands may change without the engine pose changing; rereading must still see open bones.
model.commanded=Angle(0,0,75) witness.Observe("right",model,63,20,false)
local stale=witness.Snapshot("right") assert(math.abs(stale.current[5][3])<.001)
for f=0,4 do local _,a=LocalToWorld(Vector(),Angle(0,0,(f==0 and 40 or 75)),Vector(),parent) model.cache[f+1]=matrix(a) end
witness.Observe("right",model,63.2,21,false)
local good=witness.Snapshot("right") assert(model.reads>=18)
for i=1,5 do assert(math.abs(good.current[i][3]-(i==1 and 40 or 75))<.001,"global hand rotation contaminated finger motion") end
''' % ROOT.as_posix()
        run=subprocess.run([LUAJIT,'-e',lua],capture_output=True,text=True)
        self.assertEqual(run.returncode,0,run.stdout+run.stderr)

    @unittest.skipUnless(LUAJIT,'LuaJIT not installed')
    def test_review_carry_setup_requires_grip_not_trigger_bit(self):
        source=(ROOT/'companion/tests/vr_combined_review_server.lua').read_text()
        start=source.index('    if qSpawnPending and')
        block=source[start:source.index('    if qPhase=="wall" and elapsed>.9',start)]
        lua='''local root=[=[%s]=]
assert(loadfile(root.."/companion/tests/vr_stubs.lua"))().Math()
bit=require("bit") IsValid=function(e) return e and e.valid end
local calls=0 local qSpawnPending=true local qCarried
local ply={} local qPhase="blink" local elapsed=.6
local s={hands={right={pos=Vector(),buttons=0}},interact={right={phys={valid=true,GetPos=function() return Vector() end}},controls={right={grip=true}}}}
local function qSpawn() return {EntIndex=function() return 99 end} end
local function qOut() end
local NLVR_SV={Grab=function() calls=calls+1 return true end}
local function step()
%s
end
step() assert(calls==0,"no-input carry setup ran")
s.hands.right.buttons=2 step() assert(calls==0,"trigger-only input prepared carry")
s.hands.right.buttons=1 step() assert(calls==1 and not qSpawnPending,"real grip did not prepare carry")
''' % (ROOT.as_posix(),block)
        run=subprocess.run([LUAJIT,'-e',lua],capture_output=True,text=True)
        self.assertEqual(run.returncode,0,run.stdout+run.stderr)

    def test_tracked_curls_use_actual_axis_independent_bone_rotations(self):
        data={}
        for side,wanted in (('left',[1,.8,.6,.4,.2]),('right',[.2,.4,.6,.8,1])):
            angles=[[0,0,(40 if i==0 else 75)*v] for i,v in enumerate(wanted)]
            data[side]={'grip':False,'curls':wanted,'splay':[0]*4,
                'rendered':{'method':'engine_bone_parent_rotations','reference_model':'generated','current_model':'generated',
                    'reference_frame':10,'current_frame':20,'reference':[[0,0,0] for _ in range(5)],'current':angles}}
        self.assertTrue(q.tracked_curls_check(data))
        import copy
        for mutant in ('missing','no_draw_bend','wrong_amount','same_frame'):
            bad=copy.deepcopy(data)
            if mutant=='missing':bad['left'].pop('rendered')
            elif mutant=='no_draw_bend':bad['right']['rendered']['current']=[[0,0,0] for _ in range(5)]
            elif mutant=='wrong_amount':bad['right']['rendered']['current'][2][2]+=2
            else:bad['right']['rendered']['current_frame']=10
            self.assertFalse(q.tracked_curls_check(bad),mutant)

    @unittest.skipUnless(LUAJIT,'LuaJIT not installed')
    def test_review_carry_releases_grip_before_each_hands_setup(self):
        source=(ROOT/'companion/tests/vr_combined_review.lua').read_text()
        block='nlvr.Actions=function'+source.split('nlvr.Actions=function',1)[1].split('    qCtx.On("frame"',1)[0]
        lua='''local nlvr={} local now=0 local function qTime() return now end
local function qOldActions() return {} end
%s
for _,t in ipairs({23,23.1,23.3,27,27.1,27.3}) do
 now=t assert(not nlvr.Actions().right_grip.state,"grip pressed while Hands selection may still be pending")
end
for _,t in ipairs({23.6,24,27.6,28}) do now=t assert(nlvr.Actions().right_grip.state,"carry grip never presses") end
''' % block
        run=subprocess.run([LUAJIT,'-e',lua],capture_output=True,text=True)
        self.assertEqual(run.returncode,0,run.stdout+run.stderr)

    def test_natural_geometry_matrix_includes_annabelle_in_both_hands(self):
        import vr_v4_geometry as geometry
        self.assertTrue(hasattr(geometry,'phases'))
        for side,dominant in (('right',0),('left',1)):
            phases=geometry.phases(side)
            self.assertTrue(any(cls=='nlvr_frames_annabelle' and hand==dominant for _,cls,hand in phases))

    def test_missing_annabelle_attachment_cannot_certify_all_gun_muzzles(self):
        import vr_v4_geometry as geometry
        rows=[]
        for cls in (*geometry.weapons.CLASSES,'nlvr_frames_annabelle'):
            row={'kind':'capture','weapon':{'class':cls,'hand':'right'},'scale':40,'muzzle':{'pos':[0,0,0]}}
            if cls!='nlvr_frames_annabelle':
                row['muzzle_witness']={'pos':[0,0,0],'source':'engine_named_muzzle'}
                if cls=='weapon_physgun':row['muzzle_witness'].update(source='asset_named_core_and_addon_beam',independent_source='model_attachment_named_core',beam_pos=[0,0,0])
            rows.append(row)
        self.assertFalse(geometry.muzzle_checks(rows)['success'])

    def test_physgun_muzzle_uses_asset_emitter_and_observed_beam_not_its_own_index(self):
        import vr_v4_geometry as geometry
        row={'kind':'capture','weapon':{'class':'weapon_physgun','hand':'right'},'scale':40,
            'attachment':{'Pos':[40,0,0]},'muzzle':{'pos':[40,0,0]},
            'muzzle_witness':{'pos':[0,0,0],'beam_pos':[0,0,0],'source':'asset_named_core_and_addon_beam','independent_source':'model_attachment_named_core'}}
        result=geometry.muzzle_checks([row])
        self.assertFalse(result['checks']['muzzle_within_1cm'])
        row['muzzle']['pos']=[0,0,0]
        self.assertTrue(geometry.muzzle_checks([row])['checks']['muzzle_within_1cm'])
        row['muzzle_witness']['beam_pos']=[40,0,0]
        self.assertFalse(geometry.muzzle_checks([row])['checks']['muzzle_within_1cm'])
        row['muzzle']['pos']=[40,0,0]  # Even W and T agreeing must not certify a wrong emitter.
        self.assertFalse(geometry.muzzle_checks([row])['checks']['muzzle_within_1cm'])
        row['muzzle_witness']['source']='hardcoded_attachment'
        self.assertFalse(geometry.muzzle_checks([row])['checks']['independent_emitters'])

    @unittest.skipUnless(LUAJIT, 'LuaJIT is not installed')
    def test_poc_ulib_import_is_detached_from_old_stock_registry(self):
        from unittest import mock
        scratch=ROOT/'out/tmp';scratch.mkdir(parents=True,exist_ok=True)
        with tempfile.TemporaryDirectory(dir=scratch,prefix='q4r-hook-import-') as tmp:
            root=Path(tmp);poc=root/'poc';evidence=root/'evidence';evidence.mkdir();(evidence/'probe.lua').write_text('return true\n')
            with mock.patch.object(driver,'POC',poc):q.stage_fixtures(['poc_session.py','--lua','unused'],evidence,'return true')
            lua_root=poc/'garrysmod/addons/nlvr_q_tests/lua'
            code='local root='+json.dumps(lua_root.as_posix())+'\n'+'''
SERVER=false
local F=assert(loadfile(root.."/nlvr_q_tests/hook_fixture.lua"))()
hook=F.New("stock") hook.Add("Tick","old",function() end)
local stock=hook.GetTable()
include=function(path) return assert(loadfile(root.."/"..path))() end
assert(loadfile(root.."/autorun/nlvr_q_hook_fixture.lua"))()
hook.Add("Tick","late",function() end)
assert(not stock.Tick.late,"fixture still writes to the original stock registry")
assert(hook.GetTable()~=hook.GetTable(),"PoC ULib query did not return a fresh snapshot")
'''
            run=subprocess.run([LUAJIT,'-e',code],capture_output=True,text=True)
            self.assertEqual(run.returncode,0,run.stdout+run.stderr)

    @unittest.skipUnless(LUAJIT, 'LuaJIT is not installed')
    def test_ulib_gettable_is_a_fresh_detached_snapshot(self):
        code='local root='+json.dumps(ROOT.as_posix())+'\n'+'''local H=assert(loadfile(root.."/companion/tests/vr_hook_fixture.lua"))().New("ulib")
local original=function() return 1 end
H.Add("event","peer",original)
local first,second=H.GetTable(),H.GetTable()
assert(first~=second and first.event~=second.event,"ULib compatibility queries reused a live table")
first.event.peer=function() return 2 end
assert(H.GetTable().event.peer==original and H.Run("event")==1,"snapshot mutation changed dispatch")
'''
        run=subprocess.run([LUAJIT,'-e',code],capture_output=True,text=True)
        self.assertEqual(run.returncode,0,run.stdout+run.stderr)

    @unittest.skipUnless(LUAJIT, 'LuaJIT is not installed')
    def test_natural_laser_aim_uses_tip_origin_after_palm_conversion(self):
        import vr_fixture_frames as frames
        def value(v):
            if isinstance(v,dict):return '{'+','.join('['+json.dumps(k)+']='+value(x) for k,x in v.items())+'}'
            if isinstance(v,list):return '{'+','.join(map(value,v))+'}'
            return json.dumps(v)
        code='local root='+json.dumps(ROOT.as_posix())+'\nlocal profiles='+value(frames.profiles())+'\n'
        code+='''local S=assert(loadfile(root.."/companion/tests/vr_stubs.lua"))() S.Math()
local V=getmetatable(Vector())
function V:Angle() return Angle(math.deg(math.atan2(-self.z,math.sqrt(self.x*self.x+self.y*self.y))),math.deg(math.atan2(self.y,self.x)),0) end
local F=assert(loadfile(root.."/companion/tests/vr_fixture_frames.lua"))().New(profiles)
local target=Vector(1.2,-.1,1.5)
for _,side in ipairs({"left","right"}) do
 local p={pos=Vector(.4,.2,1.2),ang=Angle()}
 F.Aim(p,side,target)
 local data=profiles[side].aim
 local tip,ang=LocalToWorld(Vector(unpack(data.pos)),Angle(unpack(data.ang)),p.pos,p.ang)
 assert(ang:Forward():Dot((target-tip):GetNormalized())>.999999999,"laser missed after tip parallax")
end
'''
        run=subprocess.run([LUAJIT,'-e',code],capture_output=True,text=True)
        self.assertEqual(run.returncode,0,run.stdout+run.stderr)

    @unittest.skipUnless(LUAJIT, 'LuaJIT is not installed')
    def test_integration_frame_writer_survives_later_writer_restore(self):
        lua='''phase="active"
table.Copy=function(t) local out={} for k,v in pairs(t) do out[k]=v end return out end
local hooks={}
hook={Add=function(event,id,fn) hooks[id]=fn end,Remove=function() end,GetULibTable=function() return {} end}
emit=function() end RunConsoleCommand=function() end
include=function() return {New=function() return {} end} end
NLVR={Registry={entries={}}}
nlvr={TestState=function() return {time=33} end,BeginFrame=function() return {valid=true} end}
assert(loadfile(%s))()
hooks.q4_integration_lifecycle() hooks.q4_integration_stage()
local cached=nlvr.BeginFrame
NLVR=nil hooks.q4_integration_lifecycle()
assert(cached().valid,"later frame writer restored a dead predecessor")
''' % json.dumps((ROOT/'companion/tests/vr_q4_integration.lua').as_posix())
        run=subprocess.run([LUAJIT,'-e',lua],capture_output=True,text=True)
        self.assertEqual(run.returncode,0,run.stdout+run.stderr)
        source=(ROOT/'companion/tests/vr_q4_integration.lua').read_text(encoding='utf-8')
        self.assertEqual(source.count('local f,detail=previous(...)'),1)
        mutant=source.replace('local f,detail=previous(...)','local f,detail=qOldPortFrame(...)')
        broken=lua.replace('assert(loadfile('+json.dumps((ROOT/'companion/tests/vr_q4_integration.lua').as_posix())+'))()',
            'assert(loadstring('+json.dumps(mutant)+'))()')
        run=subprocess.run([LUAJIT,'-e',broken],capture_output=True,text=True)
        self.assertNotEqual(run.returncode,0,'later writer accepted a dead predecessor')
        self.assertIn('qOldPortFrame',run.stderr)

    @unittest.skipUnless(LUAJIT, 'LuaJIT is not installed')
    def test_all_module_integration_fixture_compiles_and_requires_semantics(self):
        import vr_q4_integration as integration
        scratch=ROOT/'out/tmp';scratch.mkdir(parents=True,exist_ok=True)
        with tempfile.TemporaryDirectory(dir=scratch,prefix='q4-combined-') as tmp:
            path=Path(tmp)/'probe.lua'
            driver.lua_script(path,{'simulate':True,'seconds':integration.END,'q_controller_profiles':q.controller_frames.profiles()})
            text=integration.fixture(path.read_text(encoding='utf-8'))
            path.write_text(text,encoding='utf-8')
            run=subprocess.run([LUAJIT,'-e','assert(loadfile([=['+path.as_posix()+']=]))'],capture_output=True,text=True)
            self.assertEqual(run.returncode,0,run.stdout+run.stderr)
            self.assertIn('live_selectors_checked',text)
            self.assertIn('QFrames.Encode(frame.right',text)
        result=integration.analyse({'success':True,'records':[]},'')
        self.assertFalse(result['success'])
        self.assertFalse(result['checks']['reload_features'])
        self.assertFalse(result['checks']['tools_features'])

    @unittest.skipUnless(LUAJIT, 'LuaJIT is not installed')
    def test_flight_fixture_preserves_flat_baseline_preferences(self):
        lua='''GetConVar=function() return {GetString=function() return "0.6" end} end
RunConsoleCommand=function() error("fixture changed preferences before flat baseline") end
hook={Add=function() end}
include=function() return {New=function() return {} end} end
assert(loadfile(%s))()
''' % json.dumps((ROOT/'companion/tests/vr_q4_flight.lua').as_posix())
        run=subprocess.run([LUAJIT,'-e',lua],capture_output=True,text=True)
        self.assertEqual(run.returncode,0,run.stdout+run.stderr)

    def test_armed_flight_missing_trial_or_bent_flight_fails(self):
        import vr_q4_flight as flight
        rows=[{'kind':'Q4-flight-travel','case':i,'units':[100,0,0]} for i in range(4)]
        rows += [{'kind':'Q4-flight-command','case':i,'cosine':1,'up':0,'gun_pitch':45 if i%2==0 else -45} for i in range(4) for _ in range(5)]
        rows += [{'kind':'peer-final','success':True,'cycles':2,'exits':2,'views':2,'bad_views':0,'hands':2,
            'counts':{'think_vr':3,'input_vr':3,'think_flat':3,'input_flat':2,'moving':5,'view_vr':0,'view_flat':2}}]
        source={'success':True,'records':rows}
        self.assertTrue(flight.analyse(source)['success'])
        rows[0]['units'][2]=20
        self.assertFalse(flight.analyse(source)['success'])
        rows[0]['units'][2]=0
        rows.pop(0)
        self.assertFalse(flight.analyse(source)['success'])

    @unittest.skipUnless(LUAJIT, 'LuaJIT is not installed')
    def test_natural_controller_fixture_roundtrips_both_hands(self):
        import vr_fixture_frames as frames
        def lua(v):
            if isinstance(v,dict):return '{'+','.join('['+json.dumps(k)+']='+lua(x) for k,x in v.items())+'}'
            if isinstance(v,list):return '{'+','.join(map(lua,v))+'}'
            return json.dumps(v)
        code='local root='+json.dumps(ROOT.as_posix())+'\n'
        code+='local S=assert(loadfile(root.."/companion/tests/vr_stubs.lua"))() S.Math()\n'
        code+='local F=assert(loadfile(root.."/companion/tests/vr_fixture_frames.lua"))().New('+lua(frames.profiles())+')\n'
        code+='''for _,side in ipairs({"left","right"}) do for _,pitch in ipairs({45,-45}) do
local p={pos=Vector(.4,.2,1.2),ang=Angle(pitch,30,10)}
F.Encode(p,side) assert((p.pos-Vector(.4,.2,1.2)):Length()>.1,"identity controller substituted")
F.Decode(p,side) assert((p.pos-Vector(.4,.2,1.2)):Length()<1e-6)
assert((p.ang:Forward()-Angle(pitch,30,10):Forward()):Length()<1e-6)
end end
'''
        run=subprocess.run([LUAJIT,'-e',code],capture_output=True,text=True)
        self.assertEqual(run.returncode,0,run.stdout+run.stderr)

    @unittest.skipUnless(LUAJIT, 'LuaJIT is not installed')
    def test_shared_ulib_fixture_priority_and_backward_contract(self):
        lua='''local root=... IsValid=function(o) return o.valid end
local target={}
local H,back,levels=assert(loadfile(root.."/companion/tests/vr_hook_fixture.lua"))().New("ulib",nil,target)
assert(H==target,"install replaced the engine's hook table")
local seen={}
for p=-2,2 do H.Add("event",tostring(p),function() seen[#seen+1]=p if p==-2 or p==2 then return "ignored" end end,p) end
assert(H.Run("event")==nil) assert(table.concat(seen,",")=="-2,-1,0,1,2")
H.Add("event","ret",function() return false,2,3,4,5,6 end,-1)
local a,b,c,d,e,f=H.Run("event") assert(a==false and b==2 and f==6)
H.Add("event","ret",function() end,1) assert(not levels.event[-1].ret and levels.event[1].ret)
back.event=nil
assert(not pcall(H.Remove,"event","ret"),"Remove concealed missing backwards table")
assert(not pcall(H.Add,"event","new",function() end),"Add skipped Remove")
'''
        lua=lua.replace('local root=...', 'local root='+json.dumps(ROOT.as_posix()))
        run=subprocess.run([LUAJIT,'-e',lua],capture_output=True,text=True)
        self.assertEqual(run.returncode,0,run.stdout+run.stderr)

    @unittest.skipUnless(LUAJIT, 'LuaJIT is not installed')
    def test_shared_probe_settles_flat_cache_after_second_stop(self):
        source=(ROOT/'tools/vr_session.lua').read_text(encoding='utf-8')
        branches={
            'second':source.split('elseif phase == "stopping-second" then',1)[1].split('\n    end\nend)',1)[0],
            'look':source.split('    if CONFIG.look then\n        if not captures.look_ready',1)[1].split('    if phase == "flat-before" then',1)[0],
            'test_quit':source.split('        if CONFIG.test_quit then\n',1)[1].split('        if t >= 3 then',1)[0]}
        branches['look']='if not captures.look_ready'+branches['look']
        # Each extracted branch had one outer if removed by the split.
        branches['look']='if true then '+branches['look']
        branches['test_quit']='if true then '+branches['test_quit']
        helper=''
        if 'local flatSettledAt' in source:
            begin=source.index('local flatSettledAt');helper=source[begin:source.index('\nend',begin)+4]
        for name,branch in branches.items():
            lua='''local native={State=function() return "off" end,Info=function() return {} end}
local NativeLoaderVR={state="off",Stop=function() end}
local CONFIG={seconds=0} local captures={look_ready=true}
local phaseAt,now,finished,secondStoppedAt=0,0,false,nil
local began,lookEnding,t,changed=0,true,0,true
local errors={} local function finish() finished=true end
local function emit() end local gui={HideGameUI=function() end}
local function CurTime() return now end
%s
local function step(time) now=time %s end
step(0) assert(not finished,"flat cache checked on Stop's frame")
step(.9) assert(not finished,"flat cache has not settled for one second")
step(1.01) assert(finished,"settled Stop never completes")
''' % (helper,branch)
            with self.subTest(path=name):
                run=subprocess.run([LUAJIT,'-e',lua],capture_output=True,text=True)
                self.assertEqual(run.returncode,0,run.stdout+run.stderr)
                broken=lua.replace(branch,branch.replace('flat_settled(now)','true'))
                run=subprocess.run([LUAJIT,'-e',broken],capture_output=True,text=True)
                self.assertNotEqual(run.returncode,0)
                self.assertIn("flat cache checked on Stop's frame",run.stdout+run.stderr)

    def test_heavy_lag_requires_continuous_native_duration(self):
        def result(values):
            rows=[{'kind':'sample','phase':4,'time':3.01+2*t,'elapsed_seconds':t,
                   'right':{'held':1,'grip_error':lag}} for t,lag in values]
            return q.physical_check.analyse(rows,selected=[4])['checks']
        sustained=[(i*.03,8) for i in range(43)]
        self.assertTrue(result(sustained)['heavy_crate_lag_duration_seconds'])
        spike=[(i*.03,8 if i==20 else 0) for i in range(43)]
        self.assertFalse(result(spike)['heavy_crate_lag_duration_seconds'])
        self.assertFalse(result([(0,8),(1.26,8)])['heavy_crate_lag_duration_seconds'])
        # V8 needs 0.1 s above 1 unit: two 0.06 s bursts split by a gap do not add up.
        split=[(i*.03,8 if i<=2 or 6<=i<=8 else 0) for i in range(9)]
        self.assertFalse(result(split)['heavy_crate_lag_duration_seconds'])
        self.assertFalse(result([(i*.03,0.9) for i in range(43)])['heavy_crate_lag_duration_seconds'])
        self.assertTrue(result([(i*.03,1.2) for i in range(5)])['heavy_crate_lag_duration_seconds'])
        # The probe's per-tick record wins over the 0.25 s samples, which miss V8's short lag windows.
        def ticked(above,peak):
            rows=[{'kind':'sample','phase':4,'time':3.2,'right':{'held':1,'grip_error':0.1},'heavy':{'above':above,'peak':peak}}]
            return q.physical_check.analyse(rows,selected=[4])['checks']
        self.assertTrue(ticked(0.18,1.5)['heavy_crate_lag_duration_seconds'])
        self.assertTrue(ticked(0.18,1.5)['heavy_crate_lag_units'])
        self.assertFalse(ticked(0.03,1.5)['heavy_crate_lag_duration_seconds'])
        self.assertFalse(ticked(0.18,0.8)['heavy_crate_lag_units'])

    @unittest.skipUnless(LUAJIT, 'LuaJIT is not installed')
    def test_temporal_probes_observe_rendered_view_with_owned_calcview(self):
        run=subprocess.run([LUAJIT,str(ROOT/'tools/tests/vr_temporal_probe_cases.lua'),str(ROOT)],capture_output=True,text=True)
        self.assertEqual(run.returncode,0,run.stdout+run.stderr)
        self.assertIn('PASS rendered temporal probes',run.stdout)

    @unittest.skipUnless(LUAJIT, 'LuaJIT is not installed')
    def test_controller_typing_keeps_each_target_through_release(self):
        run=subprocess.run([LUAJIT,str(ROOT/'tools/tests/vr_fixture_typing_cases.lua'),str(ROOT)],capture_output=True,text=True)
        self.assertEqual(run.returncode,0,run.stdout+run.stderr)
        self.assertIn('PASS controller typing',run.stdout)

    @unittest.skipUnless(LUAJIT, 'LuaJIT is not installed')
    def test_functional_clock_survives_capture_stalls_without_skipping_inputs(self):
        run=subprocess.run([LUAJIT,str(ROOT/'tools/tests/vr_combined_clock_cases.lua'),str(ROOT)],capture_output=True,text=True)
        self.assertEqual(run.returncode,0,run.stdout+run.stderr)
        self.assertIn('PASS functional clock',run.stdout)

    @unittest.skipUnless(LUAJIT, 'LuaJIT is not installed')
    def test_cachecpu_fixture_compiles_and_missing_measurement_fails(self):
        import vr_cachecpu_session as c
        scratch=ROOT/'out/tmp'
        scratch.mkdir(parents=True,exist_ok=True)
        with tempfile.TemporaryDirectory(dir=scratch) as tmp:
            path=Path(tmp)/'probe.lua'
            driver.lua_script(path,{'simulate':True,'seconds':35})
            source=c.fixture(path.read_text(encoding='utf-8'))
            path.write_text(source,encoding='utf-8')
            run=subprocess.run([LUAJIT,'-e','assert(loadfile([=['+path.as_posix()+']=]))'],capture_output=True,text=True)
            self.assertEqual(run.returncode,0,run.stdout+run.stderr)
        self.assertFalse(c.analyse({'success':True,'records':[]})['success'])

    def test_stationary_empty_lua_message_table_is_a_failed_dynamic_witness(self):
        from vr_measure import accounting_checks
        result=accounting_checks({'server_network':[{'messages':[],'elapsed':1}]})
        self.assertFalse(result['server_state_observed'])

    def test_expected_close_exception_needs_exact_source_and_menu_survival(self):
        import copy,vr_combined_review as r
        line='[nlvr] UI close hook: addons/nlvr_q_tests/lua/nlvr_q_tests/client.lua:123: Q deliberately throwing close hook'
        ui={'checks':{'menus':True},'ui_errors':[line],'images':[],'open':[]}
        proof=[{'kind':'Q-review-menu-after-exit','valid':True,'parent_world':True,'opens':True,'caught':1}]
        self.assertTrue(r.expected_close_error(copy.deepcopy(ui),proof)['full_acceptance'])
        self.assertFalse(r.expected_close_error(copy.deepcopy(ui),[])['full_acceptance'])
        ui['ui_errors'].append('[nlvr] module ui: unexpected')
        self.assertFalse(r.expected_close_error(copy.deepcopy(ui),proof)['full_acceptance'])

    @unittest.skipUnless(LUAJIT, 'LuaJIT is not installed')
    def test_capture_queue_waits_for_paint_and_never_overwrites_requests(self):
        run=subprocess.run([LUAJIT,str(ROOT/'tools/tests/vr_capture_queue_cases.lua'),str(ROOT)],capture_output=True,text=True)
        self.assertEqual(run.returncode,0,run.stdout+run.stderr)
        self.assertIn('PASS capture readiness',run.stdout)

    def test_independent_review_fails_closed_without_witnesses(self):
        import vr_combined_review
        result=vr_combined_review.analyse([],[])
        self.assertFalse(result['success'])
        self.assertGreaterEqual(len(result['checks']),14)
        self.assertFalse(any(result['checks'].values()))

    def test_timeline_is_monotonic_bounded_and_preserves_throw_derivatives(self):
        timeline = q.timeline()
        rows = timeline['steps']
        times = [r['time'] for r in rows]
        self.assertEqual(times, sorted(set(times)))
        self.assertLess(len(json.dumps(timeline).encode()), 1048576)
        self.assertLess(q.END, 180)
        throw = [r for r in rows if 6 <= r['time'] <= 6.25]
        a, b = throw[:2]
        from vr_fixture_frames import mv,rotation,controller_offsets
        def palm(row):
            pose=row['right'];delta=mv(rotation(pose['ang']),controller_offsets()['right'][1])
            return [x+y for x,y in zip(pose['pos'],delta)]
        self.assertAlmostEqual((palm(b)[0]-palm(a)[0])/(b['time']-a['time'])*40, 120)
        self.assertEqual(timeline['events'][0]['time'], q.L_END+18/q.UI_RATE)
        punch=[r for r in rows if 41.49<=r['time']<=41.71]
        self.assertEqual(len(punch),2)
        self.assertAlmostEqual(punch[1]['time']-punch[0]['time'],.2)
        self.assertAlmostEqual((punch[1]['right']['pos'][0]-punch[0]['right']['pos'][0])*40/.2,160)
        # Physical slots must use the same Source clock as movement/UI: a screenshot
        # must not advance the recording beyond the death-ragdoll grip window.
        source=q.client_fixture((ROOT/'tools/vr_session.lua').read_text(encoding='utf-8'))
        self.assertIn('BeginAt=0',source)

    @unittest.skipUnless(LUAJIT, 'LuaJIT is not installed')
    def test_every_generated_chunk_compiles_with_all_production_checks_retained(self):
        scratch = ROOT/'out/tmp'
        scratch.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=scratch) as tmp:
            path = Path(tmp)/'base.lua'
            driver.lua_script(path, {'simulate': True, 'seconds': 173})
            base = path.read_text(encoding='utf-8')
            for name, text in (('combined', q.client_fixture(base)), ('allmotion', q.allmotion_fixture(base)), ('temporal',q.temporal_fixture(base)),
                               ('server', q.server_fixture())):
                chunk = Path(tmp)/(name+'.lua')
                chunk.write_text(text, encoding='utf-8')
                run = subprocess.run([LUAJIT, '-e', 'assert(loadfile([=['+chunk.as_posix()+']=]))'],
                                     capture_output=True, text=True)
                self.assertEqual(run.returncode, 0, run.stdout+run.stderr)
                if name != 'server':
                    self.assertIn('live_selectors_checked', text)
                    self.assertIn('overlay-roles', text)
                    self.assertIn('variable_differences', text)
            self.assertIs(q.driver.capture_problems, driver.capture_problems)


if __name__ == '__main__':
    unittest.main()
