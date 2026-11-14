"""Dominant-hand layout preserves physical controls and declared rotation witnesses."""
import sys
import unittest
from pathlib import Path
ROOT=Path(__file__).resolve().parents[2]
sys.path[:0]=[str(ROOT/'companion/tests'),str(ROOT/'tools')]
import vr_v4_fixture as fixture


class V4FixtureTests(unittest.TestCase):
    def test_mirror_swaps_controls_and_locations_but_not_declared_hand_rotations(self):
        original={'steps':[{'time':0,'hmd':{'pos':[0,.1,1.6],'ang':[10,45,0]},
            'left':{'pos':[.2,.3,1.2],'ang':[90,0,0]},'right':{'pos':[.4,-.25,1.2],'ang':[0,90,90]},
            'actions':{'left_grip':True,'right_trigger':True,'right_stick':[0,1]}}]}
        data=fixture.mirror_layout(original);row=data['steps'][0]
        self.assertEqual(row['left']['pos'],[.4,.25,1.2]);self.assertEqual(row['left']['ang'],[0,90,90])
        self.assertEqual(row['right']['ang'],[90,0,0]);self.assertEqual(row['hmd']['ang'],[10,-45,0])
        self.assertTrue(row['actions']['right_grip']);self.assertTrue(row['actions']['left_trigger'])
        self.assertEqual(fixture.mirror_layout(data),original)
    def test_calibration_port_world_rotation_is_retained(self):
        rows=[{'kind':'calibration','port_tracking':[.5,.2,1.2],'port_angle':[25,30,90]}]
        data=fixture.canonical_calibration(rows,True)
        self.assertEqual(data[0]['port_tracking'],[.5,-.2,1.2]);self.assertEqual(data[0]['port_angle'],[25,30,90])
        self.assertEqual(rows[0]['port_tracking'],[.5,.2,1.2])
    def test_prepared_probe_keeps_the_room_yaw_and_clears_physical_input(self):
        # V4's adapter turned the room to yaw 0, so weapons and reload (fixture yaw 180) faced 0 or 45.
        from test_mmd_alpha import LUAJIT
        import subprocess, tempfile
        import vr_session as driver
        if not LUAJIT:
            self.skipTest('LuaJIT is not installed')
        scratch = ROOT / 'out/tmp'
        scratch.mkdir(parents=True, exist_ok=True)
        for role in ('weapons', 'reload', 'tools'):
            with self.subTest(role=role), tempfile.TemporaryDirectory(dir=scratch, prefix='v8-adapter-') as tmp:
                path = Path(tmp) / 'probe.lua'
                config = {'seconds': 60, 'simulate': True}
                fixture.configure(config, role, False, {'steps': []})
                driver.lua_script(path, config)
                text = path.read_text(encoding='utf-8') + '\ndo\n' + \
                    (ROOT / 'companion/tests' / fixture.CLIENTS[role]).read_text(encoding='utf-8') + '\nend\n'
                text = fixture.prepare(text, role, False)
                self.assertNotIn('Space.Turn', text[text.index('hook.Add("Think","q_v4_fixture_prepare"'):])
                block = text[text.rindex('\ndo\nlocal prepared=false'):]
                lua = '''local think
hook = {Add = function(_, _, fn) think = fn end}
NativeLoaderVR = {state = "running"}
local movers = {}
NLVR = {Space = {yaw = 135, Turn = function() error("the adapter turned the room") end},
    Registry = {entries = {{module = {name = "move"}, ctx = {mover = function(p, fn) movers[#movers + 1] = {p, fn} end}}}}}
''' + block + '''
think() think()
assert(NLVR.Space.yaw == 135 and #movers == 1 and movers[1][1] == -30)
local cmd = {x = 9, y = 9, cleared = 0}
function cmd:ClearMovement() self.cleared = self.cleared + 1 end function cmd:ClearButtons() self.cleared = self.cleared + 1 end
function cmd:SetMouseX(n) self.x = n end function cmd:SetMouseY(n) self.y = n end
movers[1][2](cmd) assert(cmd.x == 0 and cmd.y == 0 and cmd.cleared == 2)
print("ok")
'''
                run = subprocess.run([LUAJIT, '-e', lua], capture_output=True, text=True)
                self.assertEqual(run.returncode, 0, run.stdout + run.stderr)

    def test_physical_fields_do_not_swap_eye_or_camera_axes(self):
        text='frame.right.pos actions.right_trigger state.hands.left camera.right image.left NLVR.Pose.right'
        changed=fixture.physical_fields(text)
        self.assertEqual(changed,'frame.left.pos actions.left_trigger state.hands.right camera.right image.left NLVR.Pose.left')


if __name__=='__main__':unittest.main()
