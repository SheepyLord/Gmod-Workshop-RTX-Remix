"""Offline safety and evidence tests for the VR session driver; no OpenVR or game starts."""
import importlib.util
import contextlib
import io
import base64
import json
import re
import os
import shutil
import subprocess
import struct
from pathlib import Path
import sys
import tempfile
import unittest
import argparse
from unittest import mock
import zlib

TOOLS = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(TOOLS))
import vr_session as vr


def wrist_png(blank=False, size=(8, 8), pixel=None):
    def chunk(kind, data):
        return struct.pack('>I', len(data)) + kind + data + struct.pack('>I',zlib.crc32(kind+data))
    pixel = bytes(pixel or ((12,18,26,235) if blank else (255,255,255,255)))
    raw = (b'\0'+pixel*size[0])*size[1]
    return (b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR',struct.pack('>IIBBBBB',*size,8,6,0,0,0)) +
            chunk(b'IDAT',zlib.compress(raw)) + chunk(b'IEND',b''))


class VrSessionTests(unittest.TestCase):
    def test_requested_simulation_takes_both_shared_locks(self):
        self.assertTrue(vr.needs_vr_lock(argparse.Namespace(flat=False,simulate=True,both_locks=True)))

    def test_framework_probe_inventories_new_owned_hooks_and_both_realms(self):
        source = vr.Path(vr.__file__).with_suffix('.lua').read_text(encoding='utf-8')
        self.assertIn('tostring(id):match("^nlvr%.")', source)
        self.assertIn('out.nlvr_global, out.receiver', source)
        self.assertNotIn('RunConsoleCommand("lua_run"', source)
        server = (TOOLS.parent / 'vr/addon/lua/nlvr/core/sv_core.lua').read_text(encoding='utf-8')
        self.assertIn('active=%s hooks=%d receiver=%s accepted=%d dropped=%d', server)
    def test_every_poc_mode_takes_both_shared_locks(self):
        import argparse
        for flat, simulate, expected in ((False,False,True),(True,False,True),(False,True,True)):
            self.assertEqual(vr.needs_vr_lock(argparse.Namespace(flat=flat,simulate=simulate)),expected)
        source=Path(vr.__file__).read_text(encoding='utf-8')
        self.assertIn("ExclusiveLock(main_root / 'out/r10/poc.lock'",source)

    def test_simulation_copies_the_recorded_device_under_the_launch_root(self):
        native=self.root/'native'
        content=vr.timeline(15)
        vr.prepare_native_data(native,content,True)
        self.assertEqual(json.loads((native/'timelines/timeline.json').read_text()),content)
        source=vr.REPO/'vr/native/sim/index-v1.json'
        self.assertEqual((native/'simulated-index.json').read_bytes(),source.read_bytes())
        self.assertEqual(json.loads((native/'simulated-index-source.json').read_text())['sha256'],vr.sha256(source))
        ordinary=self.root/'ordinary';vr.prepare_native_data(ordinary,content,False)
        self.assertFalse((ordinary/'simulated-index.json').exists())

    def test_generated_simulation_probe_uses_rendered_progress_and_simulates_both_starts(self):
        path=self.root/'simulate.lua'
        vr.lua_script(path,{'simulate':True})
        source=path.read_text()
        self.assertEqual(source.count('simulated_start({simulate = true,'),2)
        self.assertIn('native.Info().framesRendered',source)
        self.assertNotIn('native.Info().framesSubmitted',source)
        ordinary=self.root/'ordinary.lua';vr.lua_script(ordinary,{'simulate':False})
        original=Path(vr.__file__).with_suffix('.lua').read_text(encoding='utf-8')
        expanded=original.replace('__CAPTURE_QUEUE__',(TOOLS/'vr_capture_queue.lua').read_text(encoding='utf-8'))
        self.assertTrue(ordinary.read_text().endswith(expanded))

    def test_simulation_adapter_restores_actual_probe_on_success_refusal_and_error(self):
        lua=shutil.which('luajit') or str(Path(os.environ.get('LOCALAPPDATA',''))/'Programs/LuaJIT/bin/luajit.exe')
        if not Path(lua).exists():self.skipTest('LuaJIT is not installed')
        script=self.root/'simulator-adapter.lua'
        script.write_text('''local actual={steamvr_installed=false,steamvr_running=false,runtime_api=3}
local real=function() return actual end
nlvr={Probe=real}
require=function(name) assert(name=="nlvr") end
NativeLoaderVR={Start=function(options)
 assert(options.simulate and nlvr.Probe().steamvr_installed)
 assert(nlvr.Probe().runtime_api==3)
 return true
end}
'''+vr.simulation_adapter()+'''
assert(simulated_start({timeline="test"})==true)
assert(nlvr.Probe==real and NativeLoaderVR.probe==actual and actual.steamvr_installed==false)
NativeLoaderVR.Start=function() return false,"refused by native boundary" end
local ok,why=simulated_start({}) assert(ok==false and why=="refused by native boundary")
assert(nlvr.Probe==real and NativeLoaderVR.probe==actual)
NativeLoaderVR.Start=function() error("test failure") end
assert(pcall(simulated_start,{})==false)
assert(nlvr.Probe==real and NativeLoaderVR.probe==actual)
''',encoding='utf-8')
        result=subprocess.run([lua,str(script)],capture_output=True,text=True)
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)

    def test_window_dimensions_are_bounded_and_default_is_unchanged(self):
        import argparse
        self.assertEqual(vr.window_size('3840x2160'),(3840,2160))
        self.assertEqual(vr.window_size('1280X720'),(1280,720))
        for value in ('4k','1x1','99999x720','1280x-720','1280x720;quit'):
            with self.assertRaises(argparse.ArgumentTypeError):vr.window_size(value)
        source=Path(vr.__file__).read_text(encoding='utf-8')
        self.assertIn('default=(1280, 720)',source)
        self.assertIn("'--width', str(args.window[0]), '--height', str(args.window[1])",source)

    def test_simulation_refuses_conflicting_modes_before_touching_the_environment(self):
        for switch in ('--flat','--look','--live-poses'):
            with mock.patch.object(vr,'main_checkout') as checkout,contextlib.redirect_stderr(io.StringIO()):
                with self.assertRaises(SystemExit):vr.main(['--evidence',str(self.root/'unused'),'--simulate',switch])
            checkout.assert_not_called()

    def test_simulation_evidence_requires_rendering_and_no_sdk_or_eye_submissions(self):
        folder=self.root/'simulated';folder.mkdir();(folder/'modules.json').write_text('[]')
        run={'normal_quit':True,'settings_back':'restored','lua_errors':0}
        info={'simulated':True,'openvr_loaded':False,'state':2,'framesRendered':60,'framesSubmitted':0,'posesUnmatched':0,'submitErrors':0}
        data=[{'kind':'sample','phase':'active','seconds':1,'info':dict(info,framesRendered=5)},
              {'kind':'sample','phase':'active','seconds':6,'info':info},
              {'kind':'final-vr','info':info},{'kind':'done','success':True,'inventory':{'hooks':[],'timers':[]}}]
        def evaluate():
            (folder/'console.log').write_text('\n'.join('NLVR_Q '+json.dumps(r) for r in data))
            return vr.evaluate(folder,run,simulate=True)
        self.assertTrue(evaluate()['success'])
        saved=data[2];data.pop(2);self.assertFalse(evaluate()['success']);data.insert(2,saved)
        info['openvr_loaded']=True;self.assertFalse(evaluate()['success']);info['openvr_loaded']=False
        info['framesSubmitted']=1;self.assertFalse(evaluate()['success']);info['framesSubmitted']=0
        info['framesRendered']=5;result=evaluate();self.assertFalse(result['success']);self.assertIn('rendered frame',result['progress_failure'])

    def test_missing_pillow_refuses_before_any_side_effect(self):
        evidence=self.root/'must-not-exist'
        for switches in ([],['--flat'],['--simulate']):
            with self.subTest(switches=switches):
                errors=io.StringIO()
                with mock.patch.object(vr.importlib,'import_module',side_effect=ModuleNotFoundError('PIL')), \
                     mock.patch.object(vr,'ExclusiveLock') as lock, mock.patch.object(vr,'main_checkout') as checkout, \
                     mock.patch.object(vr,'command') as command, contextlib.redirect_stderr(errors):
                    result=vr.main(['--evidence',str(evidence),'--package','unused.gma','--seconds','30',*switches])
                self.assertEqual(result,2)
                self.assertFalse(evidence.exists())
                lock.assert_not_called();checkout.assert_not_called();command.assert_not_called()
                self.assertEqual(len(errors.getvalue().splitlines()),1)
                self.assertIn(vr.sys.executable,errors.getvalue())
                self.assertIn('-m pip install pillow',errors.getvalue())

    def test_look_skips_pillow_preflight(self):
        with mock.patch.object(vr.importlib,'import_module',side_effect=ModuleNotFoundError('PIL')) as imports, \
             mock.patch.object(vr,'main_checkout',side_effect=RuntimeError('past preflight')), \
             mock.patch.object(vr,'ExclusiveLock') as lock:
            with self.assertRaisesRegex(RuntimeError,'past preflight'):
                vr.main(['--look','--evidence',str(self.root/'look'),'--seconds','1800'])
        imports.assert_not_called();lock.assert_not_called()
        self.assertEqual(vr.completion_arguments(True,1800),['--lua-manual'])
        self.assertEqual(vr.completion_arguments(False,30),['--lua-shots','130'])

    def test_low_space_refuses_before_locks_or_evidence_creation(self):
        evidence=self.root/'out/unused'
        with mock.patch.object(vr,'main_checkout',return_value=self.root), \
             mock.patch.object(vr,'inside_out',return_value=evidence), \
             mock.patch.object(vr,'check_screenshot_dependencies'), \
             mock.patch.object(vr.shutil,'disk_usage',return_value=shutil._ntuple_diskusage(100,99,1)), \
             mock.patch.object(vr,'ExclusiveLock') as lock,contextlib.redirect_stderr(io.StringIO()):
            self.assertEqual(vr.main(['--evidence',str(evidence),'--package','unused.gma']),2)
        self.assertFalse(evidence.exists());lock.assert_not_called()

    def test_unfinished_transaction_requires_its_own_verified_recovery(self):
        evidence=self.root/'out/one';other=self.root/'out/two'
        vr.begin_transaction(self.root,evidence)
        with self.assertRaisesRegex(RuntimeError,'unfinished'):vr.require_clean_transaction(self.root)
        with self.assertRaises(ValueError):vr.validate_recovery_transaction(self.root,other)
        with self.assertRaises(ValueError):vr.complete_transaction(self.root,other)
        self.assertTrue(vr.pending_transaction(self.root).exists())
        vr.complete_transaction(self.root,evidence)
        vr.require_clean_transaction(self.root)

    def test_look_probe_never_requests_a_screenshot_and_uses_wall_time(self):
        lua=shutil.which('luajit') or str(Path(os.environ.get('LOCALAPPDATA',''))/'Programs/LuaJIT/bin/luajit.exe')
        if not Path(lua).exists():self.skipTest('LuaJIT is not installed')
        source=vr.Path(vr.__file__).with_suffix('.lua').read_text()
        block=re.search(r'    if CONFIG\.look then\n.*?\n        return\n    end',source,re.S)[0]
        begin=source.index('local flatSettledAt');settle=source[begin:source.index('\nend',begin)+4]
        script=self.root/'look-test.lua'
        script.write_text('''local CONFIG={look=true,seconds=1800}
local began,lookEnding,captures=0,false,{}
local stops,finishes,previews=0,0,0
local NativeLoaderVR={state="running",Stop=function() stops=stops+1 end}
local function shot() error("screenshot attempted without Pillow") end
local function print(text) if text:find("NLVR preview:",1,true) then previews=previews+1 end end
local function finish(ok) assert(ok) finishes=finishes+1 end
'''+settle+'''
local function tick(now)
'''+block+'''
end
tick(4) tick(150) assert(previews==1 and stops==0 and finishes==0)
NativeLoaderVR.state="failed" tick(1799) assert(stops==0 and finishes==0)
tick(1800) assert(stops==1 and finishes==0)
NativeLoaderVR.state="off" tick(1801) assert(finishes==0)
tick(1801.9) assert(finishes==0) tick(1802.01) assert(finishes==1)
''',encoding='ascii')
        result=subprocess.run([lua,str(script)],capture_output=True,text=True)
        self.assertEqual(result.returncode,0,result.stdout+result.stderr)

    def test_closed_manual_game_is_truthful_without_a_probe_done_record(self):
        folder=self.root/'closed';folder.mkdir()
        (folder/'console.log').write_text('')
        (folder/'modules.json').write_text(json.dumps(['C:/game/openvr_api.dll']))
        run={'manual_end':'game_exited','exit':0,'normal_quit':True,'lua_errors':0,
             'settings_back':'not sent: game already exited'}
        result=vr.evaluate(folder,run,look=True)
        self.assertTrue(result['success'])
        self.assertEqual(result['outcome'],'game_closed')
        self.assertTrue(result['last_observed_openvr_loaded'])
        self.assertFalse(result['openvr_loaded_after_exit'])
        self.assertTrue(result['sdk_unloaded_by_process_exit'])
        run['failed']='GPU device lost'
        self.assertFalse(vr.evaluate(folder,run,look=True)['success'])

    def test_isolated_module_failure_is_not_a_complete_acceptance_even_if_rendering_and_done_pass(self):
        folder=self.root/'module-failure';folder.mkdir()
        done={'kind':'done','success':True,'inventory':{'hooks':[],'timers':[]}}
        (folder/'console.log').write_text('NLVR_Q '+json.dumps(done)+'\n[nlvr] module ui: overlay limit\n')
        (folder/'modules.json').write_text('[]')
        run={'normal_quit':True,'lua_errors':0,'settings_back':'restored'}
        result=vr.evaluate(folder,run)
        self.assertFalse(result['success'])
        self.assertEqual(result['module_failures'],['[nlvr] module ui: overlay limit'])

    def test_blank_wrist_is_not_a_successful_capture_even_with_all_files(self):
        folder = self.root / 'neutral'
        folder.mkdir()
        for name in ('centre.png','centre_depth.png','left.png','right.png','mirror.png','timings.json'):
            (folder/name).write_bytes(b'fixture')
        image = folder / 'overlay_1.png'
        image.write_bytes(wrist_png(blank=True))
        records = [{'kind':'capture','ok':True,'label':'neutral','overlays':{'1':{'role':'wrist'}}}]
        self.assertIn('blank wrist',vr.capture_problems(self.root,records)[0])
        image.write_bytes(wrist_png())
        self.assertEqual(vr.capture_problems(self.root,records),[])

    def test_overlay_roles_are_handle_based_and_accept_black_comfort_and_large_panels(self):
        folder = self.root / 'roles'
        folder.mkdir()
        for name in ('centre.png','centre_depth.png','left.png','right.png','mirror.png','timings.json'):
            (folder/name).write_bytes(b'fixture')
        # A large black source is not a wrist. A tiny wrist must still have glyphs.
        (folder/'overlay_10.png').write_bytes(wrist_png(size=(1537,1025),pixel=(0,0,0,255)))
        (folder/'overlay_11.png').write_bytes(wrist_png())
        (folder/'overlay_12.png').write_bytes(wrist_png(pixel=(0,0,0,255)))
        manifest = {'10':{'role':'spawn','info':{'visible':True}},'11':{'role':'wrist'},
                    '12':{'role':'vignette','info':{'visible':True}}}
        records = [{'kind':'overlay-roles','label':'roles','overlays':manifest},
                   {'kind':'capture','label':'roles','ok':True}]
        self.assertEqual(vr.capture_problems(self.root, records), [])
        manifest['12']['role']='move_arc_8'
        self.assertEqual(vr.capture_problems(self.root, records), [])
        manifest['12']['role']='move_arc_9'
        self.assertTrue(any('unknown' in p for p in vr.capture_problems(self.root,records)))
        manifest['12']['role']='vignette'
        manifest['10']['expected']=[1537,1024]
        self.assertTrue(any('declared source' in p for p in vr.capture_problems(self.root,records)))
        manifest['10'].pop('expected')
        manifest['10']['role'], manifest['11']['role'] = 'wrist', 'spawn'
        self.assertTrue(any('blank wrist' in p for p in vr.capture_problems(self.root,records)))
        manifest['10']['role'] = 'window-guess'
        self.assertTrue(any('unknown' in p for p in vr.capture_problems(self.root,records)))

    def test_overlay_without_a_role_manifest_fails_instead_of_guessing_by_size(self):
        folder = self.root/'unlabelled'
        folder.mkdir()
        (folder/'overlay_1.png').write_bytes(wrist_png(size=(769,257)))
        problems = vr.capture_problems(self.root,[{'kind':'capture','label':'unlabelled','ok':True}])
        self.assertTrue(any('role missing' in p for p in problems))

    def test_explicit_empty_overlay_inventory_allows_retired_hidden_hud(self):
        folder=self.root/'retired'
        folder.mkdir()
        for name in ('centre.png','centre_depth.png','left.png','right.png','mirror.png','timings.json'):
            (folder/name).write_bytes(b'fixture')
        records=[{'kind':'capture','ok':True,'label':'retired','overlays':{},'expected_roles':[]}]
        self.assertEqual(vr.capture_problems(self.root,records),[])
        (folder/'overlay_2.png').write_bytes(wrist_png(pixel=(0,0,0,255)))
        records[0]['overlays']={'2':{'role':'vignette','info':{'visible':True}}}
        self.assertEqual(vr.capture_problems(self.root,records),[])
        records[0]['overlays']['3']={'role':'spawn','info':{'visible':True}}
        self.assertTrue(any('declared overlay' in p for p in vr.capture_problems(self.root,records)))
        records[0]['overlays']['3']['info']['visible']=False
        self.assertEqual(vr.capture_problems(self.root,records),[],"hidden source can retire after request")

    def test_expected_wrist_without_a_handle_cannot_pass_capture(self):
        folder=self.root/'unallocated'; folder.mkdir()
        for name in ('centre.png','centre_depth.png','left.png','right.png','mirror.png','timings.json'):
            (folder/name).write_bytes(b'fixture')
        records=[{'kind':'capture','ok':True,'label':'unallocated','overlays':{},'expected_roles':['wrist']}]
        self.assertTrue(vr.capture_problems(self.root,records),'expected logical role must fail even without native allocation')

    def test_probe_transport_has_bounded_idempotent_stages_and_exact_utf8(self):
        source = ('-- boundary ]====] and UTF-8: \u00e9\n' * 300).encode('utf-8')
        path = self.root / 'probe.lua'
        path.write_bytes(source)
        stages = vr.lua_stages(path)
        self.assertNotIn('NLVR_Q_SOURCE', stages[0].read_text())
        chunks = []
        import poc_session
        for number, stage in enumerate(stages[1:-1], 1):
            text = stage.read_text(encoding='ascii')
            match = re.search(r'NLVR_Q_SOURCE\[(\d+)\]="([a-f0-9]+)"', text)
            self.assertEqual(int(match[1]), number)
            chunks.append(bytes.fromhex(match[2]))
            self.assertLessEqual(len(chunks[-1]), 512)
            self.assertLess(sum(len(line) for line in poc_session.client_lua_lines('fixture', text)), 4096)
        self.assertEqual(b''.join(chunks), source)
        self.assertIn('NLVR_Q_SOURCE=nil', stages[-1].read_text())

    def test_first_camera_must_already_use_the_vr_projection(self):
        log='\n'.join('RTX VR camera: main, cut=0, FOV='+v for v in ('1.287','1.90874','1.90874'))
        self.assertFalse(vr.camera_diagnostics(log)['first_projection_consistent'])
        self.assertTrue(vr.camera_diagnostics(log.replace('1.287','1.90874'))['first_projection_consistent'])
        self.assertTrue(vr.camera_diagnostics('')['first_projection_consistent'])
        self.assertEqual(vr.camera_diagnostics('RTX VR skipped initial camera: waiting')['initial_camera_skips'],1)

    def test_manual_look_does_not_hide_an_unmatched_initial_camera(self):
        folder=self.root/'look';folder.mkdir()
        (folder/'modules.json').write_text('[]')
        data=[{'kind':'sample','info':{'framesSubmitted':2,'posesUnmatched':1,'submitErrors':0}},
              {'kind':'done','success':True,'inventory':{'hooks':[],'timers':[]}}]
        def evaluate():
            (folder/'console.log').write_text('NLVR preview: ready\n'+'\n'.join('NLVR_Q '+json.dumps(r) for r in data))
            return vr.evaluate(folder,{'normal_quit':True,'lua_errors':0,'settings_back':'restored'})
        self.assertFalse(evaluate()['success'])
        data[0]['info']['posesUnmatched']=0
        self.assertTrue(evaluate()['success'])

    def setUp(self):
        (vr.REPO / 'out/tmp').mkdir(parents=True, exist_ok=True)
        self.tmp = tempfile.TemporaryDirectory(dir=vr.REPO / 'out/tmp')
        self.root = Path(self.tmp.name)

    def tearDown(self):
        self.tmp.cleanup()

    def test_lock_never_releases_a_different_owner(self):
        path = self.root / 'vr.lock'
        with vr.ExclusiveLock(path, 'test'):
            self.assertEqual(json.loads(path.read_text())['task'], 'test')
            path.write_text('foreign owner')
        self.assertEqual(path.read_text(), 'foreign owner')

    def test_lock_is_exclusive_and_released_after_error(self):
        path = self.root / 'vr.lock'
        with self.assertRaisesRegex(RuntimeError, 'fixture'):
            with vr.ExclusiveLock(path, 'test'):
                with self.assertRaises(TimeoutError):
                    with vr.ExclusiveLock(path, 'another', timeout=0):
                        self.fail('lock not exclusive')
                raise RuntimeError('fixture')
        self.assertFalse(path.exists())

    def test_evidence_cannot_escape_out(self):
        with self.assertRaises(ValueError):
            vr.inside_out(vr.REPO / 'packages', vr.REPO)
        self.assertEqual(vr.inside_out(self.root, vr.REPO), self.root.resolve())

    def test_generated_timeline_has_three_poses_and_monotonic_times(self):
        steps = vr.timeline(190)['steps']
        self.assertEqual(sorted(set(s['time'] for s in steps)), [s['time'] for s in steps])
        for s in steps:
            self.assertEqual(set(s), {'time', 'hmd', 'left', 'right'})
        self.assertEqual(steps[3]['hmd']['ang'][1], 20)
        self.assertEqual(steps[5]['hmd']['ang'][1], -20)

    def test_console_parser_reads_only_own_json_markers(self):
        self.assertEqual(vr.records('other {}\nNLVR_Q {"kind":"sample"}\nnoise\n'), [{'kind': 'sample'}])

    def test_long_console_packets_are_reassembled_and_incomplete_data_fails(self):
        record = {'kind': 'sample', 'detail': 'native timing ' * 500}
        encoded = base64.b64encode(json.dumps(record).encode()).decode()
        chunks = [encoded[i:i+1600] for i in range(0, len(encoded), 1600)]
        lines = [f'NLVR_Q_CHUNK 1 {i}/{len(chunks)} {s}' for i, s in enumerate(chunks, 1)]
        console = 'NLVR_Q {"kind":"before"}\n' + '\n'.join(lines) + '\nNLVR_Q {"kind":"after"}\n'
        self.assertEqual(vr.records(console), [{'kind': 'before'}, record, {'kind': 'after'}])
        with self.assertRaisesRegex(ValueError, 'incomplete'):
            vr.records('\n'.join(lines[:-1]))
        with self.assertRaises(ValueError):
            vr.records('NLVR_Q {"kind":"sample"')

    def test_probe_json_cannot_close_lua_literal(self):
        path = self.root / 'probe.lua'
        vr.lua_script(path, {'timeline': ']====] print("bad")'})
        self.assertIn('util.JSONToTable([=====[', path.read_text())

    def test_user_conf_in_moved_tree_refuses_before_any_mutation(self):
        root, evidence = self.root / 'game', self.root / 'evidence'
        (root / 'native-loader').mkdir(parents=True)
        (root / 'native-loader/user.conf').write_text('owned')
        with self.assertRaisesRegex(ValueError, 'user.conf'):
            vr.preserve(root, evidence)
        self.assertEqual((root / 'native-loader/user.conf').read_text(), 'owned')
        self.assertFalse(evidence.exists())

    def test_bulk_cleanup_requires_clean_restoration(self):
        (self.root / 'restoration.json').write_text('{"clean":false}')
        with self.assertRaises(ValueError):
            vr.cleanup(self.root)

    def test_capture_deduplication_requires_matching_retained_bytes_before_removing_any_source(self):
        (self.root/'restoration.json').write_text('{"clean":true}')
        source=self.root/'native/captures/near'
        retained=self.root/'captures/near'
        source.mkdir(parents=True);retained.mkdir(parents=True)
        (source/'left.png').write_bytes(wrist_png())
        (retained/'left.png').write_bytes(wrist_png(blank=True))
        with self.assertRaises(ValueError):vr.deduplicate_captures(self.root)
        self.assertTrue((source/'left.png').exists())
        (retained/'left.png').write_bytes((source/'left.png').read_bytes())
        vr.deduplicate_captures(self.root)
        self.assertFalse((self.root/'native/captures').exists())
        self.assertTrue((retained/'left.png').exists())
        receipt=json.loads((self.root/'capture-deduplication.json').read_text())
        self.assertTrue(receipt['all_bytes_verified'])
        self.assertEqual(receipt['files'][0]['sha256'],vr.sha256(retained/'left.png'))

    def test_capture_collection_renames_owned_raw_data_and_refuses_existing_destination(self):
        native=self.root/'native';source=native/'captures/near';source.mkdir(parents=True)
        payload=wrist_png();(source/'left.png').write_bytes(payload)
        retained=self.root/'captures';retained.mkdir()
        with self.assertRaises(ValueError):vr.collect_captures(native,self.root)
        self.assertTrue((source/'left.png').exists())
        retained.rmdir();vr.collect_captures(native,self.root)
        self.assertEqual((retained/'near/left.png').read_bytes(),payload)
        self.assertFalse((native/'captures').exists())
        self.assertTrue((self.root/'capture-collection.json').exists())

    def test_capture_must_survive_until_traced_output_and_include_every_image(self):
        records=[{'kind':'capture','label':'deferred-scene','ok':True,'overlays':{'1':{'role':'wrist'}}}]
        self.assertTrue(vr.capture_problems(self.root,records))
        folder=self.root/'deferred-scene';folder.mkdir()
        for name in ('centre.png','centre_depth.png','left.png','right.png','mirror.png','timings.json','overlay_1.png'):
            (folder/name).write_bytes(b'fixture')
        (folder/'overlay_1.png').write_bytes(wrist_png())
        self.assertEqual(vr.capture_problems(self.root,records),[])
        (folder/'left.png').unlink()
        self.assertIn('left.png',vr.capture_problems(self.root,records)[0])

    def test_equal_success_counters_do_not_hide_an_active_scene_stall(self):
        folder = self.root / 'stalled'
        folder.mkdir()
        data = [
            {'kind': 'sample', 'phase': 'active', 'seconds': 1, 'info': {'state': 2, 'framesSubmitted': 5}},
            {'kind': 'sample', 'phase': 'active', 'seconds': 6, 'info': {'state': 2, 'framesSubmitted': 5}},
            {'kind': 'done', 'success': True, 'inventory': {'hooks': [], 'timers': []}},
        ]
        (folder / 'console.log').write_text('\n'.join('NLVR_Q ' + json.dumps(x) for x in data))
        (folder / 'modules.json').write_text('[]')
        result = vr.evaluate(folder, {'normal_quit': True, 'lua_errors': 0, 'settings_back': 'restored'})
        self.assertFalse(result['success'])
        self.assertIn('progress_failure', result)

    def test_steady_analysis_separates_gpu_work_and_queue_gap(self):
        data = [{'kind': 'running', 'seconds': 0}, {'kind': 'final-vr', 'seconds': 100}]
        for t, sequence, pairs, presents, reprojected in ((60, 100, 100, 200, 100), (90, 1450, 1450, 2900, 1450)):
            data.append({'kind': 'sample', 'phase': 'active', 'seconds': t, 'camera': {'sequence': sequence},
                         'info': {'state': 2, 'framesSubmitted': pairs, 'presents': presents, 'dropped': 0,
                                  'reprojected': reprojected, 'refresh': 90, 'timing': {'valid': False}}})
        profile = {'pose': 500, 'coverage_known': True, 'untracked_submissions': 0, 'gpu_total_ms': 19,
                   'gpu_queue_wait_cpu_ms': 9, 'render_thread_cpu_average_ms': 3,
                   'render_injection_wall_ms': 2, 'passes': {'trace': {'gpu_ms': 8}, 'warp': {'gpu_ms': 2}}}
        result = vr.analyse({'records': data, 'profiles': [profile]})
        self.assertEqual(result['pair_fps'], 45)
        self.assertEqual(result['reprojected_percent'], 50)
        self.assertEqual(result['gpu_command_and_sdk_ms'], 10)
        self.assertEqual(result['gpu_elapsed_ms'], 19)
        self.assertEqual(result['queue_gap_ms'], 9)


if __name__ == '__main__':
    unittest.main()
