"""Fail-closed limited medium observer and generated-Lua contracts; no native run."""
from pathlib import Path
import copy
import math
import subprocess
import sys
import tempfile
import unittest

ROOT=Path(__file__).resolve().parents[2]
sys.path[:0]=[str(ROOT/'companion/tests'),str(ROOT/'tools')]
import vr_medium_poc as medium
from test_mmd_alpha import LUAJIT


class MediumPocTests(unittest.TestCase):
    def test_round5_matrix_includes_five_degree_ladder_and_underwater_flight(self):
        cases=medium.cases()
        self.assertEqual(len(cases),33)
        self.assertEqual(len([c for c in cases if c['medium']=='ladder' and c.get('stick_angle')==5]),6)
        for throttle in (0,.5):
            self.assertEqual(len([c for c in cases if c['medium']=='noclip_water' and c.get('throttle')==throttle]),3)

    def test_gun_pitch_is_rendered_barrel_not_converged_eye_command(self):
        data=self.sample()
        for row in data['records']:
            if row['case'].get('gun_pitch') is not None:
                for p in row['probes']:
                    p['meta']['gun_model_pitch']=row['case']['gun_pitch']
                    p['meta']['cmd_pitch']=12
        self.assertTrue(medium.analyse(data)['checks']['actual_gun_pitch'])

    def test_preferences_create_the_nested_client_directory(self):
        scratch=ROOT/'out/tmp';scratch.mkdir(parents=True,exist_ok=True)
        with tempfile.TemporaryDirectory(dir=scratch) as tmp:
            path=medium.write_preferences(Path(tmp)/'new-addon')
            self.assertTrue(path.is_file());self.assertIn('move_dir',path.read_text())

    def test_direct_cli_bootstraps_imports_without_test_sys_path(self):
        run=subprocess.run([sys.executable,'-B',str(ROOT/'companion/tests/vr_medium_poc.py'),'--help'],
            cwd=ROOT,capture_output=True,text=True)
        self.assertEqual(run.returncode,0,run.stdout+run.stderr)

    def sample(self):
        records=[]
        for c in medium.cases():
            rows=[];z=0
            for i in range(10):
                yaw=-90+i*.02;p=c['head_pitch']
                p,y=math.radians(p),math.radians(yaw)
                direction=[math.cos(p)*math.cos(y),math.cos(p)*math.sin(y),-math.sin(p)]
                turn=math.radians(c.get('stick_angle',0));right=[math.sin(y),-math.cos(y),0]
                if c['medium']=='ladder':direction=[v*math.cos(turn)+r*math.sin(turn) for v,r in zip(direction,right)]
                if c['medium'].startswith('noclip_'):direction=[-1,0,0]
                sign=-1 if c['medium']=='ladder' and c['direction']=='down' else 1
                wish=[v*100*sign for v in direction] if c['direction']!='idle' else [0,0,0]
                vel=[0,0,0 if c['direction']=='idle' else sign*200] if c['medium']=='ladder' else wish
                z+=vel[2]/66
                rows.append({'wish':wish,'vel':vel,'pos':[0,0,z],'side_buttons':0,'sync_yaw':yaw-.1,
                    'frozen':False,
                    'move_type':9 if c['medium']=='ladder' else 8 if c['medium'].startswith('noclip_') else 2,'water_level':3 if c['medium'] in ('water','noclip_water') else 0,
                    'meta':{'head_pitch':c['head_pitch'],'head_yaw':yaw,'cmd_pitch':c.get('gun_pitch') or c['head_pitch'],
                            'gun_model_pitch':c.get('gun_pitch') or c['head_pitch'],'off_pitch':0,'off_yaw':180,
                            'stick_x':math.sin(math.radians(c.get('stick_angle',0))),'stick_y':math.cos(math.radians(c.get('stick_angle',0))),
                            'weapon':c['weapon'],'draws':100+i}})
            records.append({'kind':'medium-trial','id':c['id'],'case':c,'probes':rows})
        return {'success':True,'records':records}

    def test_observer_requires_real_medium_direction_side_flags_and_gun_pose(self):
        good=self.sample();self.assertTrue(medium.analyse(good)['success'])
        for change,check in (
            (lambda p:p.update(move_type=8),'real_ladder'),
            (lambda p:p.update(side_buttons=1024),'no_ladder_side_button'),
            (lambda p:p.update(frozen=True),'unfrozen_physics'),
            (lambda p:p.update(pos=[5,0,p['pos'][2]]),'no_ladder_side_drift')):
            data=copy.deepcopy(good);change(data['records'][0]['probes'][-1])
            self.assertFalse(medium.analyse(data)['checks'][check])
        data=copy.deepcopy(good);data['records'][3]['probes'][-1]['meta']['gun_model_pitch']=30
        self.assertFalse(medium.analyse(data)['checks']['actual_gun_pitch'])
        self.assertFalse(medium.analyse({'success':True,'records':[]})['success'])

    def test_observer_rejects_gun_steered_water_and_armed_speed_changes(self):
        data=self.sample();water=next(r for r in data['records'] if r['case']['medium']=='water' and r['case'].get('gun_pitch')==45)
        for p in water['probes']:p['wish']=[p['wish'][1],0,p['wish'][2]]
        self.assertFalse(medium.analyse(data)['checks']['head_steers_water'])
        data=self.sample();water=next(r for r in data['records'] if r['case']['medium']=='water' and r['case'].get('gun_pitch')==45)
        for p in water['probes']:p['wish']=[2*v for v in p['wish']]
        self.assertFalse(medium.analyse(data)['checks']['armed_unarmed_world_parity'])

    def test_observer_compares_equivalent_pitch_modulo_360(self):
        data=self.sample()
        for row in data['records']:
            if row['case'].get('gun_pitch')==-45:
                for p in row['probes']:p['meta']['gun_model_pitch']=315
        self.assertTrue(medium.analyse(data)['checks']['actual_gun_pitch'])

    def test_new_cases_reject_straight_only_ladder_and_stick_only_underwater_motion(self):
        data=self.sample();row=next(r for r in data['records'] if r['case'].get('stick_angle')==5)
        for p in row['probes']:p['meta']['stick_x']=0
        self.assertFalse(medium.analyse(data)['checks']['five_degree_ladder_input'])
        data=self.sample();row=next(r for r in data['records'] if r['case']['medium']=='noclip_water' and r['case']['throttle']==0)
        row['probes'][0]['wish']=[10,0,0]
        self.assertFalse(medium.analyse(data)['checks']['noclip_stick_alone_zero'])
        data=self.sample();row=next(r for r in data['records'] if r['case']['medium']=='noclip_water' and r['case']['throttle']>0)
        for p in row['probes']:p['wish']=[0,100,0]
        self.assertFalse(medium.analyse(data)['checks']['noclip_hand_flight'])

    @unittest.skipUnless(LUAJIT,'LuaJIT not installed')
    def test_generated_fixture_compiles_and_never_forces_ladder_or_creates_targets(self):
        scratch=ROOT/'out/tmp';scratch.mkdir(parents=True,exist_ok=True)
        with tempfile.TemporaryDirectory(dir=scratch) as tmp:
            path=Path(tmp)/'probe.lua'
            medium.write_probe(path,{'simulate':True,'seconds':100,'render_scale':.65,'camera':[-2920,-1038,-48,0,-90,0]})
            for source in (path,ROOT/'companion/tests/vr_medium_server.lua'):
                run=subprocess.run([LUAJIT,'-e','assert(loadfile([=['+source.as_posix()+']=]))'],capture_output=True,text=True)
                self.assertEqual(run.returncode,0,run.stdout+run.stderr)
        server=(ROOT/'companion/tests/vr_medium_server.lua').read_text()
        self.assertNotIn('SetMoveType(MOVETYPE_LADDER)',server)
        self.assertNotIn('ents.Create',server)
        self.assertNotIn(':Remove()',server)


if __name__=='__main__':unittest.main()
