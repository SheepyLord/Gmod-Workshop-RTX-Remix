"""Controller frame composition through the actual core and anatomical model calibration."""
from pathlib import Path
import subprocess
import unittest
import hashlib
import json
import tempfile
from contextlib import contextmanager
from unittest.mock import patch
from test_mmd_alpha import LUAJIT, ROOT

def recorded_lua():
    d=json.loads((ROOT/"companion/tests/fixtures/vr_index_skeletons.json").read_text())["samples"]
    def lua(v):
        if isinstance(v,dict): return "{"+",".join("["+json.dumps(k)+"]="+lua(x) for k,x in v.items())+"}"
        if isinstance(v,list): return "{"+",".join(map(lua,v))+"}"
        if isinstance(v,bool): return "true" if v else "false"
        return json.dumps(v)
    return "return "+lua(d)

@contextmanager
def recorded_fixture():
    folder=ROOT/"out/tmp";folder.mkdir(parents=True,exist_ok=True)
    with tempfile.TemporaryDirectory(dir=folder,prefix="vr-c-skeleton-") as temporary:
        path=Path(temporary)/"skeletons.lua";path.write_text(recorded_lua())
        yield path


CASES = ("index_left", "index_right", "quest2", "rifts", "cv1", "vive", "raw_fallback", "invalid_pose", "offset_velocity", "hands_geometry", "curl_axes", "grasp_circle", "handle_axis_fit", "skeletal_reference_frame", "skeletal_matrices", "constraint_sweep", "bounded_reference", "roll_sweep", "partial_components", "wrist_sweep", "sample_storage", "recorded_reader", "draw_target_pool")


@unittest.skipUnless(LUAJIT, "LuaJIT is not installed")
class VRFramesTests(unittest.TestCase):
    def run_case(self, case):
        with recorded_fixture() as fixture:
            done = subprocess.run([LUAJIT, str(Path(__file__).with_name("vr_frames_harness.lua")), str(ROOT), case, str(fixture)],
                                  cwd=ROOT, capture_output=True, encoding="utf-8", timeout=30)
        self.assertEqual(done.returncode, 0, done.stdout + done.stderr)
        self.assertIn("PASS " + case, done.stdout)


for _case in CASES:
    setattr(VRFramesTests, "test_" + _case, lambda self, case=_case: self.run_case(case))


class VRCleanupGuards(unittest.TestCase):
    def test_verified_build_retains_edited_output(self):
        import vr_frames_clean_builds as cleanup
        with tempfile.TemporaryDirectory(dir=ROOT / "out/tmp",prefix="c-build-guard-") as directory, patch.object(cleanup,"ROOT",Path(directory)):
            dist=Path(directory)/"out/dist"
            dist.mkdir(parents=True)
            path=dist/(cleanup.PREFIX+"1.gma")
            data=b"generated C fixture"
            path.write_bytes(data)
            path.with_suffix(".json").write_text(json.dumps({"version":"0.0.0-v4c.1","gma_bytes":len(data),"gma_sha256":hashlib.sha256(data).hexdigest()}),encoding="utf-8")
            self.assertEqual(cleanup.verified(1)[0],path)
            path.write_bytes(b"user-edited output")
            with self.assertRaisesRegex(ValueError,"differs"):
                cleanup.verified(1)
            self.assertEqual(path.read_bytes(),b"user-edited output")

    def test_cleanup_refuses_other_branch_before_file_access(self):
        import vr_frames_clean_builds as cleanup
        with patch("sys.argv",["cleanup","--evidence","unused","--versions","1"]), patch.object(cleanup.subprocess,"check_output",return_value="main\n"):
            with self.assertRaisesRegex(ValueError,"restricted"):
                cleanup.main()


class VRFrameMetrology(unittest.TestCase):
    def test_authored_mount_is_separate_from_physical_grip(self):
        from vr_frames_analyse import grip_checks
        self.assertTrue(all(grip_checks(.000004,.000004,.1862).values()))
        self.assertFalse(all(grip_checks(.03,.000004,.01).values()))
        self.assertFalse(all(grip_checks(.006,None,.01).values()))
        self.assertFalse(all(grip_checks(None,.000004,.01).values()))
        self.assertFalse(all(grip_checks(.000004,.006,.01).values()))
        self.assertFalse(all(grip_checks(.000004,None,.1862,shaft=True).values()))
        self.assertTrue(all(grip_checks(.000004,None,.09,shaft=True).values()))

    def test_rendered_palm_distance_is_independent_of_grasp_target(self):
        from vr_frames_analyse import palm_axis_distance
        scale=40
        def hand(offset):
            return {"bones":{"Hand":{"pos":[0,offset*scale,0]},**{"Finger"+str(i):{"pos":[4,offset*scale,(i-2.5)*.2]} for i in range(1,5)}}}
        raw={"pos":[0,0,0],"ang":[0,0,0]}
        handle={"pos":(0,0,0),"axis":(1,0,0)}
        self.assertAlmostEqual(palm_axis_distance(hand(.04),raw,scale,handle),.04)
        self.assertGreater(palm_axis_distance(hand(.14),raw,scale,handle),.05)

    def test_proximal_middle_cylinder_recovers_tube_centre(self):
        import math
        from vr_frames_geometry import cylinder,axis_error
        points=[]
        for i,z in enumerate((-.03,-.01,.01,.03)):
            for angle in (.15+i*.04,1.8+i*.02):
                points.append((.007+.018*math.cos(angle),-.011+.018*math.sin(angle),z))
        fitted=cylinder(points,(0,0,1))
        self.assertAlmostEqual(fitted["pos"][0],.007)
        self.assertAlmostEqual(fitted["pos"][1],-.011)
        self.assertAlmostEqual(fitted["radius"],.018)
        target={"pos":(0,0,0),"axis":(0,0,1)}
        self.assertAlmostEqual(axis_error(fitted,target)["max_m"],math.hypot(.007,.011))
        moved=cylinder([(x+.03,y,z) for x,y,z in points],(0,0,1))
        self.assertGreater(axis_error(moved,target)["max_m"],.015)

    def test_finite_span_axis_rejects_lateral_and_angular_miss(self):
        from vr_frames_geometry import line,axis_error
        target={"pos":(0,0,0),"axis":(0,0,1)}
        fitted=line([(.05,0,z) for z in (-.03,-.01,.01,.03)])
        self.assertAlmostEqual(axis_error(fitted,target)["max_m"],.05)
        angled={"pos":(0,0,0),"axis":(1,0,0)}
        self.assertAlmostEqual(axis_error(angled,target)["centre_m"],0)
        self.assertGreater(axis_error(angled,target)["max_m"],.015)

    def test_handle_sections_exclude_ring(self):
        from vr_frames_geometry import handle_model
        with tempfile.TemporaryDirectory(dir=ROOT/"out/tmp",prefix="c-handle-model-") as directory:
            path=Path(directory)/"body.obj"
            points=[]
            for z in (.085,.095,.105,.115,.125,.135,.145):
                points += [(x,y,z) for x in (-.01,.01) for y in (-.02,0)]
                points += [(.08,y,z) for y in (-.08,.08)]
            path.write_text("\n".join("v "+" ".join(map(str,p)) for p in points),encoding="utf-8")
            fit=handle_model(path,"right")
            self.assertAlmostEqual(fit["pos"][0],0)
            self.assertAlmostEqual(fit["pos"][1],-.01)
            self.assertAlmostEqual(abs(fit["axis"][2]),1)

if __name__ == "__main__":
    unittest.main()
