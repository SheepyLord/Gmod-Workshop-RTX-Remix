"""Independent fixture regeneration contracts; no game or OpenVR starts."""
from pathlib import Path
import io
import json
import sys
import tempfile
import unittest
from unittest import mock

ROOT=Path(__file__).resolve().parents[2]
sys.path.insert(0,str(ROOT/'companion/tests'))
import vr_mesh_fixture as fixture


class MeshFixtureTests(unittest.TestCase):
    def synthetic(self):
        bone={'pos':'[0 0 0]','ang':'{0 0 0}'}
        models={'w_pistol':{'lo':'[-10 -5 -5]','hi':'[10 5 5]',
            'bones':{'ValveBiped.Bip01_R_Hand':bone},'vertices':[[1,-1,-5],[4,-1,-5],[1,1,-2],[4,1,-2]],'attachments':{}}}
        records=[]
        for side in ('left','right'):
            records.append({'kind':'capture','label':'pistol-'+side+'-side','diagnostic':False,
                side:{'model':'generated-hand','bones':{'Hand':{'pos':'[10 20 30]','ang':'{0 0 0}'}}},
                'shown':{side:{'pos':'[12 20 30]','ang':'{0 0 0}'}},
                'hands':{side:{'palm_frame':{'grip':[999,999,999]}}}})
        return models,records

    def test_grip_region_comes_from_authored_bone_and_actual_rendered_hand(self):
        models,hands=self.synthetic();data=fixture.build([models],hands)
        row=data['models']['models/weapons/w_pistol.mdl']
        self.assertEqual(row['spec']['grip_bone'],'ValveBiped.Bip01_R_Hand')
        self.assertIn('handle_bounds',row['spec'])
        self.assertEqual(len(row['vertices']),4)
        for hand in data['hands'].values():
            self.assertNotIn('grip',hand['frame'])
            self.assertEqual(hand['frame']['pos'],[2,0,0])
        models['w_pistol']['bones']={}
        with self.assertRaisesRegex(ValueError,'authored holding-hand bone'):fixture.build([models],hands)

    def test_no_product_cap_constants_or_pruned_geometry(self):
        self.assertFalse(hasattr(fixture,'CAPS'),'generator copied product cross-section constants')
        models,hands=self.synthetic();row=fixture.build([models],hands)['models']['models/weapons/w_pistol.mdl']
        self.assertEqual(len(row['vertices']),len(models['w_pistol']['vertices']))

    def test_harness_uses_truthful_beam_source(self):
        text=(ROOT/'companion/tests/vr_weapons_harness.lua').read_text()
        self.assertNotIn('independent engine emitter witness',text)
        self.assertIn('add-on beam draw; independent model core',text)

    def test_generator_opens_only_declared_raw_sources(self):
        scratch=ROOT/'out/tmp';scratch.mkdir(parents=True,exist_ok=True)
        with tempfile.TemporaryDirectory(dir=scratch) as tmp:
            root=Path(tmp);models,hands=self.synthetic()
            a,b=root/'raw-models.json',root/'raw-hands.json';a.write_text(json.dumps(models));b.write_text(json.dumps(hands))
            original=io.open;opened=[]
            def only_declared(path,*args,**kwargs):
                if not isinstance(path,int):
                    self.assertIn(Path(path).resolve(),{a.resolve(),b.resolve()});opened.append(Path(path).name)
                return original(path,*args,**kwargs)
            with mock.patch('io.open',side_effect=only_declared):fixture.generate([a],b)
            self.assertEqual(sorted(opened),['raw-hands.json','raw-models.json'])

    def test_checked_fixture_has_no_product_grip_regions_or_targets(self):
        data=json.loads((ROOT/'companion/tests/fixtures/vr_mesh_witnesses.json').read_text())
        for row in data['models'].values():self.assertNotIn('grip_roi',row['spec'])
        for hand in data['hands'].values():self.assertNotIn('grip',hand['frame'])
        fit=data['models']['models/weapons/w_smg1.mdl']['spec']['barrel_fit']
        self.assertLess(fit['angular_uncertainty_degrees'],.05)
        self.assertGreater(fit['axis'][1],.03)

    def test_observer_beam_is_labelled_addon_and_core_is_the_independent_reference(self):
        source=(ROOT/'companion/tests/vr_frames_poc.lua').read_text()
        self.assertNotIn('observed_engine_convention_beam_draw',source)
        self.assertIn('observed_addon_cl_tools_beam_draw',source)
        self.assertIn('independent_source="model_attachment_named_core"',source)

    def test_fixture_regenerates_from_local_raw_exports(self):
        data=json.loads((ROOT/'companion/tests/fixtures/vr_mesh_witnesses.json').read_text())
        sources=[ROOT/s['file'] for s in data['provenance']['sources']]
        models,hands=sources[:-1],sources[-1]
        if not all(p.exists() for p in [*models,hands]):self.skipTest('optional local raw measurement exports absent; synthetic generator contracts still run')
        expected=json.dumps(fixture.generate(models,hands),indent=2,sort_keys=True)+'\n'
        self.assertEqual((ROOT/'companion/tests/fixtures/vr_mesh_witnesses.json').read_text(),expected)


if __name__=='__main__':unittest.main()
