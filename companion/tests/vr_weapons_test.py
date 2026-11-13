"""Actual W client/server modules under LuaJIT; automatically imported by S's gate bridge."""
from pathlib import Path
import subprocess
import unittest
from test_mmd_alpha import LUAJIT, ROOT

CASES = ("kinds", "grip_math", "model_muzzle", "fallback", "switch", "left", "pitch", "stopped", "world_draw",
         "custom_draw", "claims", "ui_and_reload_claim", "convergence", "filters", "foregrip", "foregrip_release",
         "hands_client", "death_exit", "invalid_tracking", "server_pose", "server_wall", "server_validation",
         "bullets", "server_twohand", "projectiles", "delayed_projectile_owner", "hands_server", "hands_unarmed",
         "throw", "melee", "melee_trigger", "punch_suppression", "events_effects", "no_punch", "no_weapon_library", "barrel_calibration",
         "armed_touch_ownership", "crossbow_rail", "tool_screen_lifetime", "geometry_ack", "relocating_filter", "owned_turret_unchanged", "custom_empty", "camera_visibility", "palm_anchor", "released_weapon_curls", "left_grip_basis", "remeasure_scale", "grasp_anchor", "melee_hand_frame", "unprofiled_frame", "grip_release_latches", "holding_grasp", "generic_models", "trigger_release_latch", "tip_only_aim", "uncalibrated_thumb_up", "unknown_up_muzzle", "independent_grip")
REVIEW_CASES = ("melee_walk", "melee_sprint", "melee_snap", "melee_teleport", "melee_tip_jump",
                "melee_tracked_velocity", "melee_angular_velocity", "melee_impact_fields", "bullet_followup",
                "bullet_missing_geometry", "grenade_spin_frame", "projectile_same_tick", "foregrip_burst",
                "pitch_keeps_firing", "exit_keeps_active", "exit_hands_fallback", "exit_unarmed_fallback",
                "bullet_hooks_first", "bullet_hooks_last", "server_tracer_broadcast", "client_predicted_tracer",
                "flash_explicit_origin", "bullet_dispatch_cleanup", "bullet_dispatch_cancel", "projectile_nointerp_owned",
                "exit_hands_previous", "cached_engine_dispatch", "projectile_after_postthink",
                "grenade_native_initializer", "model_decals_scope", "grenade_initializing_exit",
                "bugbait_without_vphysics", "bullet_hook_added_during_vr", "bugbait_first_visible", "impact_reaches_surface")
SECOND_REVIEW_CASES = ("hook_library_dispatch", "gamemode_nil_applies", "swing_walking", "swing_sprinting",
                       "swing_platform", "still_hand_walking", "tracked_tip_jump", "body_teleport_same_proxy",
                       "foregrip_held", "foregrip_climbing", "foregrip_blocked", "foregrip_holding_api", "model_decals_untouched", "priority_observers", "gamemode_nil_client")
THIRD_REVIEW_CASES = ("room_lunge", "room_walk_swing", "walk_crossing_proxy_lag", "walk_thin_door", "dispatch_copied_table", "dispatch_copied_client")
CASES += REVIEW_CASES + SECOND_REVIEW_CASES + THIRD_REVIEW_CASES


@unittest.skipUnless(LUAJIT, "LuaJIT is not installed")
class VRWeaponsTests(unittest.TestCase):
    def test_death_ownership_mutants_are_rejected(self):
        import shutil,tempfile
        scratch=ROOT/'out/tmp';scratch.mkdir(parents=True,exist_ok=True)
        original=(ROOT/'vr/addon/lua/nlvr/modules/sv_weapons.lua').read_text(encoding='utf-8')
        mutations=(('q4r_ownership_death','ctx.On("OnDeath",function(ply,state) restoreOwnership(ply,state)',
                    'ctx.On("OnDeath",function(ply,state)','death retained ownership'),
                   ('q4r_ownership_dead_tick','if ply:Alive() then ownHand(ply,state) else restoreOwnership(ply,state) end',
                    'if ply:Alive() then ownHand(ply,state) end','dead tick retained ownership'))
        with tempfile.TemporaryDirectory(dir=scratch,prefix='q4r-w-death-') as tmp:
            tree=Path(tmp);shutil.copytree(ROOT/'vr/addon/lua',tree/'vr/addon/lua');(tree/'companion/tests').mkdir(parents=True)
            for name in ('vr_stubs.lua','vr_hook_fixture.lua'):shutil.copy2(ROOT/'companion/tests'/name,tree/'companion/tests'/name)
            path=tree/'vr/addon/lua/nlvr/modules/sv_weapons.lua'
            for case,before,after,message in mutations:
                with self.subTest(case=case):
                    self.assertIn(before,original);path.write_text(original.replace(before,after,1),encoding='utf-8')
                    run=subprocess.run([LUAJIT,str(ROOT/'companion/tests/vr_weapons_harness.lua'),str(tree),case],capture_output=True,text=True)
                    self.assertNotEqual(run.returncode,0);self.assertIn(message,run.stdout+run.stderr)

    def run_case(self, name, library="stock"):
        done = subprocess.run([LUAJIT, str(Path(__file__).with_name("vr_weapons_harness.lua")), str(ROOT), name, library],
                              cwd=ROOT, capture_output=True, encoding="utf-8", timeout=30)
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        self.assertIn("PASS " + name, done.stdout)


for _case in CASES:
    setattr(VRWeaponsTests, "test_" + _case, lambda self, name=_case: self.run_case(name))


HOOK_LIBRARY_CASES = ("hook_library_dispatch", "gamemode_nil_applies", "bullets", "bullet_followup", "bullet_missing_geometry",
                      "bullet_hooks_first", "bullet_hooks_last", "bullet_dispatch_cancel", "server_tracer_broadcast",
                      "client_predicted_tracer", "projectiles", "projectile_after_postthink", "grenade_native_initializer",
                      "cached_engine_dispatch", "bullet_hook_added_during_vr", "priority_observers", "gamemode_nil_client")
for _case in HOOK_LIBRARY_CASES:
    setattr(VRWeaponsTests, "test_ulib_" + _case, lambda self, name=_case: self.run_case(name, "ulib"))
for _case in ("hook_library_dispatch", "gamemode_nil_applies", "projectile_after_postthink", "client_predicted_tracer"):
    setattr(VRWeaponsTests, "test_unknown_" + _case, lambda self, name=_case: self.run_case(name, "unknown"))

class VRWeaponEvidenceTests(unittest.TestCase):
    def test_smg_marker_orientation_does_not_replace_mesh_barrel(self):
        from vr_weapons_analyse import rendered_barrel, degrees, vector
        row={'debug':{'model':'models/weapons/w_smg1.mdl','model_ang':[0,0,0]},
             'attachment':{'Ang':[1.86,2.26,92]},'ray':{'dir':[1,0,0]}}
        actual=rendered_barrel(row)
        self.assertGreater(degrees(actual,vector(row['ray']['dir'])),1)
        row['ray']['dir']=actual
        row['debug']['model_ang']=[0,2.9,0]
        self.assertGreater(degrees(rendered_barrel(row),actual),2.8)
        row['debug']['model_ang']=[0,0,0]
        self.assertGreater(degrees(rendered_barrel(row),[.99,.1,0]),2)
        row['debug']['model']='models/unknown.mdl'
        self.assertIsNone(rendered_barrel(row))

    @unittest.skipUnless(LUAJIT, "LuaJIT is not installed")
    def independent_geometry_case(self,case,root=None,reject=None):
        import json,tempfile
        fixture=json.loads((ROOT/'companion/tests/fixtures/vr_mesh_witnesses.json').read_text())
        def lua(value):
            if isinstance(value,dict):return '{'+','.join('['+json.dumps(k)+']='+lua(v) for k,v in value.items())+'}'
            if isinstance(value,list):return '{'+','.join(map(lua,value))+'}'
            return json.dumps(value)
        scratch=ROOT/'out/tmp';scratch.mkdir(parents=True,exist_ok=True)
        with tempfile.TemporaryDirectory(dir=scratch,prefix='q4-grips-') as tmp:
            path=Path(tmp)/'profiles.lua';path.write_text('return '+lua(fixture))
            run=subprocess.run([LUAJIT,str(ROOT/'companion/tests/vr_weapons_harness.lua'),str(root or ROOT),case,'stock',str(path)],capture_output=True,text=True)
        if reject:
            self.assertNotEqual(run.returncode,0,run.stdout+run.stderr);self.assertIn(reject,run.stdout+run.stderr)
        else:self.assertEqual(run.returncode,0,run.stdout+run.stderr)
        return run.stdout

    @unittest.skipUnless(LUAJIT, "LuaJIT is not installed")
    def test_independent_mesh_witness_kills_placement_and_barrel_mutants(self):
        import tempfile,shutil
        scratch=ROOT/'out/tmp';scratch.mkdir(parents=True,exist_ok=True)
        mutations=(
            ('cl_weapons_model.lua','gripPos=actualGrip','gripPos=actualGrip+Vector(1.2,0,0)','q4_stock_grips','independently fitted mesh grip'),
            ('cl_weapons_model.lua','model:SetPos(origin) model:SetAngles(rotation)','model:SetPos(origin+Vector(1.2,0,0)) model:SetAngles(rotation)','q4_stock_grips','independently fitted mesh grip'),
            ('sh_weapons.lua','modelData["models/weapons/w_physics.mdl"].attachment=1','modelData["models/weapons/w_physics.mdl"].attachment=2','q4_stock_grips','add-on beam draw; independent model core'),
            ('cl_weapons_model.lua','gripPos=actualGrip','gripPos=actualGrip\n        if model:GetModel()=="models/weapons/w_smg1.mdl" then gripPos=attachment.Pos end','q4_stock_grips','independently fitted mesh grip'),
            ('cl_weapons_model.lua','local meshAxis=Mesh.Axis(model,points)','local meshAxis=Mesh.Axis(model,points) if model:GetModel()=="models/weapons/w_smg1.mdl" then meshAxis=nil end','q4_stock_grips','actual barrel/up orientation'),
            ('cl_weapons_mesh.lua','return axis*(spec.strike or 1),a,axis','if spec.barrel then axis=LocalToWorld(axis,Angle(),Vector(),Angle(0,2.9,0)) end\n    return axis*(spec.strike or 1),a,axis','q4_stock_grips','actual barrel/up orientation'),
            ('sv_weapons.lua','local tip=gun.meleeTip','local tip=gun.pose.pos+gun.muzzle.ang:Forward()*(gun.class=="weapon_crowbar" and .56 or .48)*state.scale','q4_real_melee','server sweep endpoint misses real hook'))
        mutations=list(mutations)
        for model,point in (("w_smg1","Vector(-3,1,-2)"),("w_irifle","Vector(-3,0,-2)"),
                            ("w_smg1","Vector(-11,1,3)"),("w_irifle","Vector(24,0,3)"),
                            ("w_pistol","Vector(-3,0,1)")):
            mutations.append(('cl_weapons_model.lua','gripPos=actualGrip',
                'gripPos=actualGrip\n        if model:GetModel()=="models/weapons/'+model+'.mdl" then gripPos='+point+' end',
                'q4_stock_grips','independently fitted mesh grip'))
        for model,axis,turn in (("w_pistol","y",180),("w_pistol","r",90),("w_irifle","y",180)):
            mutations.append(('cl_weapons_model.lua','    M.measureMs=',
                '    if model:GetModel()=="models/weapons/'+model+'.mdl" then wrist.'+axis+'=wrist.'+axis+'+'+str(turn)+' end\n    M.measureMs=',
                'q4_stock_grips','actual barrel/up orientation'))
        with tempfile.TemporaryDirectory(dir=scratch,prefix='q4r-geometry-mutants-') as tmp:
            tree=Path(tmp);shutil.copytree(ROOT/'vr/addon/lua',tree/'vr/addon/lua');(tree/'companion/tests').mkdir(parents=True)
            for name in ('vr_stubs.lua','vr_hook_fixture.lua','vr_mesh_witness.lua'):shutil.copy2(ROOT/'companion/tests'/name,tree/'companion/tests'/name)
            for file,before,after,case,message in mutations:
                with self.subTest(file=file,case=case):
                    path=tree/'vr/addon/lua/nlvr/modules'/file;original=(ROOT/'vr/addon/lua/nlvr/modules'/file).read_text(encoding='utf-8')
                    self.assertIn(before,original);path.write_text(original.replace(before,after,1),encoding='utf-8')
                    self.independent_geometry_case(case,tree,message)
                    path.write_text(original,encoding='utf-8')

    @unittest.skipUnless(LUAJIT, "LuaJIT is not installed")
    def test_remaining_stock_grips_against_independent_posed_mesh_points(self):
        self.independent_geometry_case('q4_stock_grips')

    @unittest.skipUnless(LUAJIT, "LuaJIT is not installed")
    def test_real_hand_frames_server_tip_and_hook_only_hit(self):
        self.independent_geometry_case('q4_real_melee')

    def test_palm_receipt_wrist_and_legacy_receipt(self):
        from vr_weapons_analyse import grip_wrist
        client={"shown":{"pos":[20,30,40],"ang":[0,0,0]},"active":{"hand":"right"},
                "hands":{"right":{"palm_frame":{"pos":[2,0,0],"ang":[0,0,90]}}}}
        self.assertEqual(grip_wrist(client),(18,30,40))
        client["hands"]={}
        self.assertEqual(grip_wrist(client),[20,30,40])

    def test_melee_requires_engine_witness(self):
        from vr_weapons_analyse import held_contact
        server = {"target_valid": True, "target_index": 152, "phase_id": 3,
                  "phase_start": 10, "time": 12.65,
                  "melee": {"source": "held", "damage": 27, "ent": 152}}
        effect = {"kind": "server-effect", "name": "Impact", "entity": 152,
                  "phase_id": 3, "tick": 100, "time": 11.1, "start": [0,0,0], "origin": [1,0,0]}
        engine = {"kind": "melee-engine-damage", "entity": 152, "damage": 27,
                  "damage_type": 128, "phase_id": 3, "tick": 100, "time": 11.1}
        self.assertTrue(held_contact(server, [effect, engine]))
        self.assertFalse(held_contact(server, [effect]))
        self.assertFalse(held_contact(dict(server, target_index=999), [effect, engine]))
        self.assertFalse(held_contact(server, [dict(effect, origin=[0,0,0]), engine]))
        self.assertFalse(held_contact(server, [dict(effect, tick=101), engine]))
        self.assertFalse(held_contact(server, [effect, dict(engine, phase_id=2)]))
        self.assertFalse(held_contact(server, [effect, dict(engine, time=9)]))

    def test_lunge_tail_keeps_hands_in_front(self):
        from vr_weapons_poc import timeline
        t=timeline(30,["pistol-5","melee-fast","melee-walk","melee-lunge"])
        tail=t["steps"][-1]
        for hand in ["left","right"]:
            self.assertGreaterEqual(tail[hand]["pos"][0]-tail["hmd"]["pos"][0],.3)

    def test_native_timeline_monotonic(self):
        from vr_weapons_poc import timeline, PHASES
        for phases in (PHASES, ["fore-smg", "fore-shotgun"]):
            times = [s["time"] for s in timeline(len(phases)*4+10, phases)["steps"]]
            self.assertEqual(times[0], 0)
            self.assertTrue(all(a < b for a, b in zip(times, times[1:])), "native timeline requires strictly increasing times")

    def test_unbreakable_native_contact(self):
        from vr_weapons_analyse import held_contact
        server = {"target_valid": True, "target_index": 152, "target_health": 100, "phase_id": 3,
                  "phase_start": 10, "time": 12.65,
                  "melee": {"source": "held", "speed": 133.3333, "damage": 27, "ent": 152}}
        effect = {"kind": "server-effect", "name": "Impact", "entity": 152, "phase_id": 3,
                  "tick": 100, "time": 11.1, "start": [0,0,0], "origin": [1,0,0]}
        engine = {"kind": "melee-engine-damage", "entity": 152, "damage": 27,
                  "damage_type": 128, "phase_id": 3, "tick": 100, "time": 11.1}
        self.assertTrue(held_contact(server, [effect, engine]))
        self.assertFalse(held_contact(server, [effect]))
        self.assertFalse(held_contact(server, [dict(effect, entity=999), engine]))
        self.assertFalse(held_contact(dict(server, melee={"source":"held", "ent":152, "damage":0}), [effect]))

    def test_engine_vector_formats(self):
        from vr_weapons_analyse import vector
        self.assertEqual(vector("[1 -0 1.25e2]"), (1, 0, 125))
        self.assertEqual(vector({"p": 12, "y": 45, "r": -9}), (12, 45, -9))
        with self.assertRaises(ValueError):
            vector([float("nan"), 0, 0])

    def test_source_forward_and_wrap(self):
        from vr_weapons_analyse import degrees, forward
        self.assertAlmostEqual(degrees(forward([0, 179, 30]), forward([0, -179, -30])), 2)
        self.assertAlmostEqual(degrees(forward([0, 45, 0]), forward([0, 0, 0])), 45)
        self.assertAlmostEqual(forward([90, 0, 0])[2], -1)

for _case in ("camera_module_failure", "camera_two_writers", "camera_screen_cleanup", "q4_rendered_muzzle", "q4_physgun_attachment", "q4r_muzzle_world_model", "q4r_ownership_death", "q4r_ownership_dead_tick", "q4r_grenade_feedback"):
    setattr(VRWeaponsTests,"test_"+_case,lambda self,case=_case:self.run_case(case))

if __name__ == "__main__":
    unittest.main()
