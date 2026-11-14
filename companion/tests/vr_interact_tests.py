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
            ('sv_interact_physics.lua','q4r_release_rules','P.released[ent]=nil rules(record.ply) rules(ent) end\n        end\n    end\n    -- What a hold follows','P.released[ent]=nil end\n        end\n    end\n    -- What a hold follows','expiry did not invalidate'),
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

# V8 (ADR 0203/0204): precise holds, one-hand turning, two hands, freezing and the client's drawn hold.
V8_CASES = ("v8_math", "v8_correction_cap", "v8_light_follow", "v8_wrist_turn", "v8_two_hand", "v8_two_hand_ragdoll",
            "v8_snap", "v8_api_localang", "v8_freeze", "v8_unfreeze", "v8_freeze_two_hands", "v8_freeze_ragdoll_bone",
            "v8_message", "v8_predict")
for _case in V8_CASES:
    setattr(InteractTests, "test_" + _case, lambda self, case=_case: self.run_case(case))


@unittest.skipUnless(LUAJIT, "LuaJIT is not installed")
class GrabMutantTests(unittest.TestCase):
    """Each V8 safeguard, reverted, must fail the case that names it."""
    MUTANTS = (
        ('sv_interact_actions.lua', 'v8_freeze', 'not h.freezeLatch and\n            A.Unfreeze', '\n            A.Unfreeze',
         'freezing kept the body in the hand'),
        ('sv_interact_physics.lua', 'v8_two_hand', 'if not grip.two or grip.twoWith ~= other then', 'if true then',
         ''),  # re-captured every tick, the pair never moves the body
        ('sv_interact.lua', 'v8_two_hand', 'other.rel = Grab.Relation(other.phys:GetPos(), other.phys:GetAngles(), anchor.pos, anchor.ang)',
         'local _ = anchor', 'letting go of one hand moved the body'),
        ('sv_interact_physics.lua', 'impulse_units', 'if phys:IsGravityEnabled() then dv = dv - physenv.GetGravity() * dt end', '',
         ''),
        ('sh_grab_math.lua', 'v8_light_follow', 'local dv = G.Limit(G.Limit(goal.vel + toward,', 'local dv = G.Limit(G.Limit(toward,',
         'a light hold lagged the moving hand'),
        ('sh_grab_math.lua', 'v8_light_follow', 'G.Limit(goal.spin + spinToward,', 'G.Limit(spinToward,', 'a light hold lagged the turning wrist'),
        ('sv_interact_physics.lua', 'v8_freeze_ragdoll_bone', 'function P.Freeze(ply, ent, phys)\n        if not P.CanFreeze(ply, ent, phys) then return false end\n        phys:EnableMotion(false)',
         'function P.Freeze(ply, ent, phys)\n        if not P.CanFreeze(ply, ent, phys) then return false end\n        for i = 0, ent:GetPhysicsObjectCount() - 1 do ent:GetPhysicsObjectNum(i):EnableMotion(false) end',
         'freezing a held bone stopped the whole ragdoll'),
        ('cl_interact_predict.lua', 'v8_predict', 'record.offset = {pos = record.last.pos - pos, turn = G.RotationError(ang, record.last.ang), at = now}',
         'record.offset = nil', ''),
    )

    def test_reverted_safeguards_fail(self):
        scratch = ROOT / 'out/tmp'
        scratch.mkdir(parents=True, exist_ok=True)
        with tempfile.TemporaryDirectory(dir=scratch, prefix='v8-grab-mutants-') as tmp:
            tree = Path(tmp)
            shutil.copytree(ROOT / 'vr/addon/lua', tree / 'vr/addon/lua')
            (tree / 'companion/tests').mkdir(parents=True)
            for name in ('vr_stubs.lua', 'vr_hook_fixture.lua'):
                shutil.copy2(ROOT / 'companion/tests' / name, tree / 'companion/tests' / name)
            for file, case, before, after, message in self.MUTANTS:
                with self.subTest(file=file, case=case, guard=message or before[:40]):
                    path = tree / 'vr/addon/lua/nlvr/modules' / file
                    original = (ROOT / 'vr/addon/lua/nlvr/modules' / file).read_text(encoding='utf-8').replace('\r\n', '\n')
                    self.assertIn(before, original)
                    path.write_text(original.replace(before, after, 1), encoding='utf-8')
                    run = subprocess.run([LUAJIT, str(ROOT / 'companion/tests/vr_interact_harness.lua'), str(tree), case],
                                         capture_output=True, text=True, timeout=60)
                    self.assertNotEqual(run.returncode, 0, 'mutant accepted: ' + before[:60])
                    self.assertIn(message, run.stdout + run.stderr)
                    path.write_text(original, encoding='utf-8')

setattr(InteractTests,"test_verify_pending_marker",lambda self:self.run_case("verify_pending_marker"))

for _case in ("q4_passive_claims", "q4_hand_ownership", "q4_released_projectile", "q4r_release_rules", "q4r_each_use_mask", "q4r_owned_grab_and_drop", "q4r_main_mask_off_damage", "q4r_held_press_across_claim"):
    setattr(InteractTests,"test_"+_case,lambda self,case=_case:self.run_case(case))

setattr(InteractTests,"test_q4r_projectile_feedback",lambda self:self.run_case("q4r_projectile_feedback"))
setattr(InteractTests,"test_q4r_dispatch_peer",lambda self:self.run_case("q4r_dispatch_peer"))
setattr(InteractTests,"test_q4s_trigger_claim_item",lambda self:self.run_case("q4s_trigger_claim_item"))

class V8AnalysisTests(unittest.TestCase):
    """V8's in-game checks on synthetic records, so a broken analysis cannot pass a real run."""
    PHASES = [14, 15, 16, 17]

    @staticmethod
    def records(turn=90, rise=8, roll=25, frozen=True, bones=(True, False, True), drawn_gap=0.4):
        rows = []

        def sample(phase, t, held, position=(0, 0, 0), left_held=0, **v8):
            rows.append({"kind": "sample", "phase": phase, "time": t, "right": {"held": held}, "left": {"held": left_held},
                         "position": list(position), "v8": dict(v8, left_held=left_held), "haptic_counts": {"2": 3, "3": 3, "6": 2, "7": 1}})

        times = [2.2 + i * 0.25 for i in range(19)]
        for t in times:  # 14: the wrist turns the cube a quarter turn between 3 and 3.5 s
            yaw = 0 if t < 3 else turn if t >= 3.5 else turn * (t - 3) / 0.5
            sample(14, t, 7 if t < 6.6 else 0, ang=[0, yaw, 0], worst={"hold_error": 0.4, "hold_angle": 2.5})
        for t in times:  # 15: the pair raises the plank and rolls it
            z = 0 if t < 3 else rise if t >= 4 else rise * (t - 3)
            r = 0 if t < 5.2 else roll if t >= 5.8 else roll * (t - 5.2) / 0.6
            sample(15, t, 8 if t < 6.6 else 0, position=(0, 0, z), left_held=8 if t < 6.6 else 0, ang=[0, 0, r],
                   pair=True, worst={"hold_error": 0.9, "hold_angle": 3})
        for t in times:  # 16: freeze at 3.05, free at 5.05, carry
            x = 0 if t < 5.3 else 10 * (t - 5.3) / 1.2
            if t < 3.05:
                sample(16, t, 9, motion=[True])
            elif t < 5.05:
                sample(16, t, 0, motion=[not frozen])
            else:
                sample(16, t, 9, position=(x, 0, 0), motion=[True])
        for t in times:
            sample(17, t, 0, motion=list(bones) if t > 3.2 else [True] * len(bones))
        for i in range(8):
            rows.append({"kind": "v8-client", "phase": 14, "time": 112 + i * 0.25, "mode": "held", "tracking": True,
                         "drawn": [drawn_gap, 0, 0], "physics": [0, 0, 0]})
        rows.append({"kind": "cleanup", "active": False, "custom": False, "ragdolls": "0", "saved_ragdolls": "0"})
        return rows

    def analyse(self, **kwargs):
        import vr_interact_analyse as analysis
        return analysis.analyse(self.records(**kwargs), self.PHASES)

    def test_a_good_run_passes(self):
        result = self.analyse()
        self.assertTrue(result["success"], {k: v for k, v in result["checks"].items() if not v})

    def test_each_failure_is_caught(self):
        for fault, check in ((dict(turn=45), "v8_turn_body_degrees"), (dict(rise=0), "v8_pair_rise_units"),
                             (dict(roll=0), "v8_pair_roll_degrees"), (dict(frozen=False), "v8_freeze_frozen_samples"),
                             (dict(bones=(False, False, False)), "v8_freeze_one_bone"),
                             (dict(drawn_gap=6), "v8_drawn_vs_physics_units")):
            with self.subTest(fault=fault):
                result = self.analyse(**fault)
                self.assertFalse(result["checks"][check], check)
                self.assertFalse(result["success"])

    def test_pair_windows_sit_in_the_timelines_steady_poses(self):
        # V8 run 2: the level reference sat inside the wrists' turn and read 3.9 of its 24.9 degrees. Both windows
        # must lie where the driver's own timeline holds the hands' pitch still (poses interpolate between steps).
        import vr_interact_poc as driver
        steps = sorted(driver.timeline(20, [15])["steps"], key=lambda s: s["time"])

        def pitch(side, t):
            before = [s for s in steps if s["time"] <= t][-1]
            after = next(s for s in steps if s["time"] >= t)
            a, b = before[side]["ang"][0], after[side]["ang"][0]
            span = after["time"] - before["time"]
            return a if span == 0 else a + (b - a) * (t - before["time"]) / span

        for low, high, value in ((4.75, 5.15, 0), (6.0, 6.45, 25)):
            for t in (low, (low + high) / 2, high):
                for side in ("right", "left"):
                    with self.subTest(window=(low, high), t=t, side=side):
                        self.assertAlmostEqual(pitch(side, t), value)

    def test_frame_generation_check(self):
        import vr_interact_analyse as analysis
        status = "Running\n\nQuality: Full, chosen for this GPU\n\nFrame generation: SteamVR Motion Smoothing; making frames now: Yes"
        good = [{"kind": "v8-frame-generation", "state": "on", "target": 45, "setting": "1", "status": status},
                {"kind": "v8-frame-generation", "state": "off", "target": 90, "setting": "0", "status": status},
                {"kind": "v8-frame-generation", "state": "restored", "target": 45, "setting": "1", "status": status}]
        checks = analysis.analyse(self.records() + good, self.PHASES)["checks"]
        self.assertTrue(all(checks[k] for k in analysis.FG_CHECKS), checks)
        stuck = [dict(r, target=45) if r["state"] == "off" else r for r in good]
        self.assertFalse(analysis.analyse(self.records() + stuck, self.PHASES)["checks"]["v8_fg_target_switch"])
        unrestored = [dict(r, setting="0") if r["state"] == "restored" else r for r in good]
        self.assertFalse(analysis.analyse(self.records() + unrestored, self.PHASES)["checks"]["v8_fg_restored"])
        silent = [dict(r, status="Running") for r in good]
        self.assertFalse(analysis.analyse(self.records() + silent, self.PHASES)["checks"]["v8_fg_page_line"])

    def test_v3_phases_keep_their_checks_only(self):
        import vr_interact_analyse as analysis
        result = analysis.analyse(self.records(), [1])
        self.assertFalse(any(key.startswith("v8_") for key in result["checks"]))


if __name__ == "__main__":
    unittest.main()
