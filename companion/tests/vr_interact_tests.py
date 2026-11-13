"""Task P's independent LuaJIT physics/gesture/lifecycle suite (no game or OpenVR)."""
from pathlib import Path
import subprocess
import unittest
import shutil
import tempfile
from test_mmd_alpha import LUAJIT, ROOT


@unittest.skipUnless(LUAJIT, "LuaJIT is not installed")
class InteractTests(unittest.TestCase):
    def test_review_claim_and_collision_mutants_are_rejected(self):
        scratch=ROOT/'out/tmp';scratch.mkdir(parents=True,exist_ok=True)
        mutations=(
            ('sv_interact_physics.lua','q4r_release_rules','rules(ply) rules(ent)\n        return true','return true','registration did not invalidate'),
            ('sv_interact_physics.lua','q4r_release_rules','P.released[ent]=nil rules(record.ply) rules(ent) end\n        end\n    end\n    function P.Drive','P.released[ent]=nil end\n        end\n    end\n    function P.Drive','expiry did not invalidate'),
            ('sv_interact_actions.lua','q4r_each_use_mask','local canUse=not owned and control.grip~=false and control.trigger~=false','local canUse=not owned and control.trigger~=false','passive Use ignored only grip'),
            ('sv_interact_actions.lua','q4r_each_use_mask','local canUse=not owned and control.grip~=false and control.trigger~=false','local canUse=not owned and control.grip~=false','passive Use ignored only trigger'),
            ('sv_interact.lua','q4r_owned_grab_and_drop','state.interact.owners[hand] or ','','owned hand acquired'),
            ('sv_interact.lua','q4r_owned_grab_and_drop','release(ply,hand,false) action.EndPull(h)','action.EndPull(h)','claim did not drop'),
            ('sv_interact_actions.lua','q4r_main_mask_off_damage','(state.interact.controls[h.name] or {}).grip==false','false','claimed main grip punched'),
            ('sv_interact_actions.lua','q4r_held_press_across_claim','touch.pos,bit.band(pose.buttons,1)~=0,bit.band(pose.buttons,2)~=0','touch.pos,gripping,trigger','held trigger became a fresh press'))
        with tempfile.TemporaryDirectory(dir=scratch,prefix='q4r-claims-') as tmp:
            tree=Path(tmp);shutil.copytree(ROOT/'vr/addon/lua',tree/'vr/addon/lua');(tree/'companion/tests').mkdir(parents=True)
            for name in ('vr_stubs.lua','vr_hook_fixture.lua'):shutil.copy2(ROOT/'companion/tests'/name,tree/'companion/tests'/name)
            for file,case,before,after,message in mutations:
                with self.subTest(file=file,case=case,guard=message):
                    path=tree/'vr/addon/lua/nlvr/modules'/file;original=(ROOT/'vr/addon/lua/nlvr/modules'/file).read_text(encoding='utf-8')
                    self.assertIn(before,original);path.write_text(original.replace(before,after,1),encoding='utf-8')
                    run=subprocess.run([LUAJIT,str(ROOT/'companion/tests/vr_interact_harness.lua'),str(tree),case],capture_output=True,text=True)
                    self.assertNotEqual(run.returncode,0);self.assertIn(message,run.stdout+run.stderr)
                    path.write_text(original,encoding='utf-8')

    def test_motion_regressions_reject_reverted_paths(self):
        scratch=ROOT/'out/tmp'
        scratch.mkdir(parents=True,exist_ok=True)
        with tempfile.TemporaryDirectory(dir=scratch,prefix='q-motion-mutants-') as tmp:
            tree=Path(tmp)
            shutil.copytree(ROOT/'vr/addon/lua',tree/'vr/addon/lua')
            (tree/'companion/tests').mkdir(parents=True)
            for name in ('vr_stubs.lua','vr_hook_fixture.lua'):
                shutil.copy2(ROOT/'companion/tests'/name,tree/'companion/tests'/name)
            file=tree/'vr/addon/lua/nlvr/modules/sv_interact_physics.lua'
            original=file.read_text(encoding='utf-8')
            mutations=(
                ('verify_bare_contact_world_velocity',
                 '(data.OurOldVelocity or Vector())-ply:GetVelocity()', '(data.OurOldVelocity or Vector())'),
                ('review_proxy_walk','local feed=pose.wvel or pose.vel or Vector()', 'local feed=pose.vel or Vector()'),
                ('verify_held_contact_world_velocity',
                 'record.contact = {ent = data.HitEntity, pos = data.HitPos,\n                velocity = relative, speed = relative:Length()}',
                 'record.contact = {ent = data.HitEntity, pos = data.HitPos,\n                velocity = data.OurOldVelocity or Vector(), speed = data.Speed or 0}'))
            for case,before,after in mutations:
                with self.subTest(case=case):
                    self.assertIn(before,original)
                    file.write_text(original.replace(before,after,1),encoding='utf-8')
                    run=subprocess.run([LUAJIT,str(Path(__file__).with_name('vr_interact_harness.lua')),str(tree),case],capture_output=True,text=True)
                    self.assertNotEqual(run.returncode,0,'regression accepted reverted '+case)
            file.write_text(original,encoding='utf-8')

    def run_case(self, case):
        result = subprocess.run([LUAJIT, str(Path(__file__).with_name("vr_interact_harness.lua")), str(ROOT), case],
                                capture_output=True, text=True, timeout=30, cwd=ROOT)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("PASS " + case, result.stdout)


for _case in ("two_hand_use", "climb_delayed_body", "body_trace", "math", "throw", "two_hand", "nearest", "lifecycle", "api_throw", "climb", "actions", "heavy", "client", "gloves", "climbing_hands", "ladder", "pull_pairs", "inventory", "native_prop_use", "held_contact", "scale", "moved_player", "scripted_prop", "scripted_item", "impulse_units", "held_grip_contact", "finger_world_stop", "usable_claim", "contact_offset", "release_grace", "sweep_contact"):
    setattr(InteractTests, "test_" + _case, lambda self, case=_case: self.run_case(case))

for _case in ("review_ragdoll_setting", "review_climb_delays", "review_proxy_walk", "review_spring_masses", "review_melee_impulse", "review_safe_proxy", "review_teleport_carry", "review_glove_mesh"):
    setattr(InteractTests, "test_" + _case, lambda self, case=_case: self.run_case(case))

setattr(InteractTests, "test_review_teleport_wall", lambda self: self.run_case("review_teleport_wall"))
setattr(InteractTests, "test_review_critical_spring", lambda self: self.run_case("review_critical_spring"))
setattr(InteractTests, "test_review_melee_damage_force", lambda self: self.run_case("review_melee_damage_force"))
setattr(InteractTests, "test_review_glove_two_hands", lambda self: self.run_case("review_glove_two_hands"))

for _case in ("verify_walk_not_punch","verify_walk_not_glove_flick","verify_carry_constraints","verify_carry_wall","verify_glove_moving_cost","verify_heavy_perceptible_lag","verify_heavy_moving_lag","verify_bare_contact_world_velocity","verify_held_contact_world_velocity"):
    setattr(InteractTests,"test_"+_case,lambda self,case=_case:self.run_case(case))

setattr(InteractTests,"test_verify_pending_marker",lambda self:self.run_case("verify_pending_marker"))

for _case in ("q4_passive_claims", "q4_hand_ownership", "q4_released_projectile", "q4r_release_rules", "q4r_each_use_mask", "q4r_owned_grab_and_drop", "q4r_main_mask_off_damage", "q4r_held_press_across_claim"):
    setattr(InteractTests,"test_"+_case,lambda self,case=_case:self.run_case(case))

setattr(InteractTests,"test_q4r_projectile_feedback",lambda self:self.run_case("q4r_projectile_feedback"))
setattr(InteractTests,"test_q4r_dispatch_peer",lambda self:self.run_case("q4r_dispatch_peer"))
setattr(InteractTests,"test_q4s_trigger_claim_item",lambda self:self.run_case("q4s_trigger_claim_item"))

if __name__ == "__main__":
    unittest.main()
