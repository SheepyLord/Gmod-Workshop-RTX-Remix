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
    def test_physical_fields_do_not_swap_eye_or_camera_axes(self):
        text='frame.right.pos actions.right_trigger state.hands.left camera.right image.left NLVR.Pose.right'
        changed=fixture.physical_fields(text)
        self.assertEqual(changed,'frame.left.pos actions.left_trigger state.hands.right camera.right image.left NLVR.Pose.left')


if __name__=='__main__':unittest.main()
