"""Regression checks for distinct timing quantities and complete flat-parity evidence."""
import copy
import json
from pathlib import Path
import sys
import tempfile
import unittest
from unittest import mock

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'tools'))
import vr_measure as measurement
import vr_flat_parity as parity
from test_vr_session import wrist_png


class MeasurementTests(unittest.TestCase):
    def test_flat_selects_only_a_restored_known_single_runtime_retry(self):
        scratch=ROOT/'out/tmp';scratch.mkdir(parents=True,exist_ok=True)
        with tempfile.TemporaryDirectory(dir=scratch) as tmp:
            root=Path(tmp);parent=root/'candidate-1';parent.mkdir();child=root/'candidate-1-retry1';child.mkdir()
            data={'classification':'known_nvidia_startup','prior_crash':False,'retry_eligible':True,
                'retry':{'evidence':str(child),'exit':0}}
            def write(): (parent/'crash.json').write_text(json.dumps(data))
            write();(parent/'restoration.json').write_text(json.dumps({'clean':True}))
            (parent/'crash-retry-used.json').write_text(json.dumps({'evidence':str(child)}))
            self.assertEqual(parity.completed_run_folder(root,'candidate-1'),child)
            data['classification']='unknown_crash';write()
            with self.assertRaises(ValueError):parity.completed_run_folder(root,'candidate-1')
            data['classification']='known_nvidia_startup';data['prior_crash']=True;write()
            with self.assertRaises(ValueError):parity.completed_run_folder(root,'candidate-1')
            data['prior_crash']=False;write();(child/'crash.json').write_text('{}')
            with self.assertRaises(ValueError):parity.completed_run_folder(root,'candidate-1')
            (child/'crash.json').unlink();data['retry']['evidence']=str(root.parent/'outside');write()
            with self.assertRaises(ValueError):parity.completed_run_folder(root,'candidate-1')

    def test_flat_child_cli_exposes_evidence_to_the_shared_crash_retry(self):
        scratch=ROOT/'out/tmp';scratch.mkdir(parents=True,exist_ok=True)
        with tempfile.TemporaryDirectory(dir=scratch) as tmp:
            root=Path(tmp);record=root/'out/workshop/published.json';record.parent.mkdir(parents=True)
            package=root/'control.gma';package.write_bytes(b'generated test fixture')
            record.write_text(json.dumps({'gma':str(package),'gma_sha256':measurement.driver.sha256(package)}))
            with mock.patch.object(parity.driver,'main_checkout',return_value=root),mock.patch.object(parity.subprocess,'run',return_value=mock.Mock(returncode=0)) as run,mock.patch.object(parity,'aggregate',return_value={'success':True}):
                parity.main(['--package',str(package),'--evidence',str(root/'out/flat'),'--run','1'])
            arguments=run.call_args.args[0][2:]
            _,folder,_=measurement.driver.evidence_argument(arguments)
            self.assertEqual(Path(folder),root/'out/flat/published-1')

    def test_armed_measurement_requires_actual_model_draws_throughout_the_window(self):
        rows=[{'kind':'running','seconds':100}]
        for i in range(30):
            rows.append({'kind':'sample','phase':'active','seconds':110+i,
                'framework':{'debug':{'weapons':{'class':'weapon_smg1','model':'models/weapons/w_smg1.mdl','hand':'right','draws':100+i}}}})
        summary={'records':rows}
        self.assertTrue(measurement.weapon_witness(summary,'weapon_smg1')['success'])
        self.assertFalse(measurement.weapon_witness(summary,'weapon_pistol')['success'])
        rows[5]['framework']['debug']['weapons']['draws']=0
        rows[5]['framework']['debug']['weapons']['model']=''
        self.assertFalse(measurement.weapon_witness(summary,'weapon_smg1')['success'])
        for row in rows[1:]: row['framework']['debug']['weapons'].update(model='model',draws=0)
        self.assertFalse(measurement.weapon_witness(summary,'weapon_smg1')['success'])

    def test_rates_gpu_command_work_and_elapsed_span_remain_distinct(self):
        rows=[{'kind':'running','seconds':100}]
        for i in range(45):
            rows.append({'kind':'sample','phase':'active','seconds':100+i,'camera':{'sequence':i*45},
                         'info':{'state':2,'framesRendered':i*45,'framesSubmitted':i*45,'presents':i*90,
                                 'reprojected':i*45,'dropped':0,'eyeWidth':2468,'eyeHeight':2740,
                                 'centreWidth':3112,'centreHeight':2752,'renderWidth':1556,'renderHeight':1376,'refresh':90}})
        profile={'pose':900,'coverage_known':True,'untracked_submissions':0,'passes':{'trace':{'gpu_ms':7},'warp':{'gpu_ms':1}},
                 'gpu_total_ms':22,'render_thread_cpu_average_ms':4,'render_thread_cpu_ms':9}
        result=measurement.steady({'success':True,'records':rows,'profiles':[profile]})
        self.assertTrue(result['success'])
        self.assertEqual(result['submitted_pairs_s'],45)
        self.assertEqual(result['reprojected_percent'],50)
        self.assertEqual(result['gpu_command_and_sdk_mean_ms'],8)
        self.assertEqual(result['gpu_elapsed_span_mean_ms'],22)
        self.assertEqual(result['render_thread_cpu_mean_ms'],9)
        self.assertEqual(result['render_thread_cpu_cumulative_average_mean_ms'],4)
        self.assertEqual(result['sample_seconds'],[110,135])
        profile['untracked_submissions']=1
        self.assertFalse(measurement.steady({'success':True,'records':rows,'profiles':[profile]})['success'])

    def test_missing_steady_samples_never_form_a_pass(self):
        self.assertFalse(measurement.steady({'success':True,'records':[],'profiles':[]})['success'])

    def test_server_cpu_keeps_its_own_tick_and_time_denominators(self):
        server={'kind':'Q-server-profile','ticks':120,'elapsed':2,'modules':{'move':{'cpu_ms':15}}}
        result=measurement.accounting({'records':[server]})
        self.assertEqual(result['server_profiles'],[server])
        self.assertEqual(result['profiles'],[])

    def test_client_cpu_uses_distinct_game_frames_not_postrender_or_eye_pairs(self):
        record={'kind':'Q-profile','label':'active','frames':60,'postrender_callbacks':62,
                'frame_denominator':'Distinct FrameNumber at active PostRender','elapsed':1,
                'modules':{'core':{'cpu_ms':30,'cycles':300,'wall_ms':40}},'client_messages':{}}
        result=measurement.accounting({'records':[record]})['profiles'][0]
        self.assertEqual(result['postrender_callbacks'],62)
        self.assertEqual(result['frames'],60)
        self.assertEqual(result['modules']['core']['cpu_ms_per_frame'],.5)

    def test_cpu_network_acceptance_requires_both_realms_and_the_off_witness(self):
        self.assertFalse(all(measurement.accounting_checks({}).values()))
        modules={k:{'calls':2} for k in ('core','hud','hands','move','ui','interact')}
        result={'profiles':[{'frames':60,'elapsed_seconds':1,'modules':modules,'client_messages':{'3':{'count':66}}}],
                'server_profiles':[{'ticks':66,'elapsed':1,'modules':modules}],
                'server_network':[{'elapsed':1,'messages':{'41':{'count':33}}}],
                'off':[{'global':False,'receiver':False}]}
        self.assertTrue(all(measurement.accounting_checks(result).values()))
        result['server_profiles']=[]
        self.assertFalse(measurement.accounting_checks(result)['server_callbacks'])

    def test_engine_timer_dump_keeps_sources_and_rejects_unknown_or_vr_timers(self):
        scratch=ROOT/'out/tmp';scratch.mkdir(parents=True,exist_ok=True)
        with tempfile.TemporaryDirectory(dir=scratch) as tmp:
            root=Path(tmp);folder=root/'poc/game';folder.mkdir(parents=True)
            path=folder/'console.log'
            dump="Timer 'RTXPatcher_Retry_123' Time Left: 0.2, Reps Left: 1, Paused: 0\t@addons/patch.lua (line 9)\n"
            def write(client):
                path.write_text('NLVR_Q_TIMERS_BEGIN_CL\n'+client+'NLVR_Q_TIMERS_END_CL\n'
                                'NLVR_Q_TIMERS_BEGIN_SV\nNo timers!\nNLVR_Q_TIMERS_END_SV\n')
            write(dump)
            result=parity.timer_inventory(root)
            self.assertTrue(result['success'])
            self.assertEqual(result['CL']['named_timers'],[{'name':'RTXPatcher_Retry_123','source':'addons/patch.lua','line':9}])
            self.assertEqual(result['CL']['named_sources'],['RTXPatcher_Retry_123@addons/patch.lua'])
            write('Unknown command: lua_dumptimers_cl\n')
            self.assertFalse(parity.timer_inventory(root)['success'])
            write(dump+"Timer 'nlvr.unexpected' Time Left: 1\t@addons/nlvr.lua (line 1)\n")
            self.assertFalse(parity.timer_inventory(root)['success'])

    def test_flat_batch_requires_ten_launches_and_expected_off_stub_only(self):
        scratch=ROOT/'out/tmp';scratch.mkdir(parents=True,exist_ok=True)
        with tempfile.TemporaryDirectory(dir=scratch) as tmp:
            root=Path(tmp)
            self.assertFalse(parity.aggregate(root)['success'])
            for i in range(10):
                label=('published' if i%2==0 else 'candidate')+'-'+str(i//2+1)
                folder=root/label
                (folder/'poc/game').mkdir(parents=True)
                empty={'hooks':[],'timers':[],'receivers':[],'vr_global':False,'vr_hooks':[],'vr_timers':[],'vr_receiver':False}
                server=copy.deepcopy(empty);server['vr_receiver']=bool(i%2)
                if i%2:server['receivers']=['nlvr']
                records=[{'kind':'flat-window','intervals':{'median_ms':8}},
                         {'kind':'Q-flat-inventory',**empty},{'kind':'Q-flat-server',**server}]
                (folder/'summary.json').write_text(json.dumps({'success':True,'records':records}))
                (folder/'poc/session.json').write_text('[{"seconds_to_map":25}]')
                (folder/'poc/game/console.log').write_text('NLVR_Q_TIMERS_BEGIN_CL\n0 timers\nNLVR_Q_TIMERS_END_CL\nNLVR_Q_TIMERS_BEGIN_SV\n0 timers\nNLVR_Q_TIMERS_END_SV\n')
                (folder/'poc/game/shot-flat-after.png').write_bytes(wrist_png())
            try:
                import PIL.Image
            except ImportError:
                self.skipTest('Pillow unavailable for actual paired image comparison')
            self.assertTrue(parity.aggregate(root)['success'])
            path=root/'candidate-5/summary.json'
            summary=json.loads(path.read_text())
            summary['records'][1]['vr_timers']=['nlvr.unexpected']
            path.write_text(json.dumps(summary))
            self.assertFalse(parity.aggregate(root)['success'])
            summary['records'][1]['vr_timers']=[]
            summary['records'][1]['hooks']=['Think:unrelated_unexplained_addition']
            path.write_text(json.dumps(summary))
            self.assertFalse(parity.aggregate(root)['success'])

    def test_preparation_retry_never_overwrites_or_replaces_a_launched_game(self):
        scratch=ROOT/'out/tmp';scratch.mkdir(parents=True,exist_ok=True)
        with tempfile.TemporaryDirectory(dir=scratch) as tmp:
            root=Path(tmp);original=root/'candidate-5';(original/'poc').mkdir(parents=True)
            (original/'poc/session.json').write_text('[{"step":"install","failed":"disk full"}]')
            retry=parity.retry_preparation(root,'candidate-5')
            self.assertEqual(retry.name,'candidate-5-retry-1')
            self.assertEqual(parity.run_folder(root,'candidate-5'),retry)
            self.assertTrue((original/'poc/session.json').exists())
            retry.mkdir();(retry/'game.log').write_text('game command attempted')
            with self.assertRaises(ValueError):parity.retry_preparation(root,'candidate-5')
            (original/'game.log').write_text('cannot retrospectively replace a launched game')
            with self.assertRaises(ValueError):parity.run_folder(root,'candidate-5')


if __name__=='__main__':unittest.main()
