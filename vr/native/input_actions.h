// SPDX-License-Identifier: MIT
#pragma once
namespace nl::vr {
struct ActionSpec { const char* name; char type; unsigned components=0; };
// b digital, v analog, s skeletal, h haptic. Shared by input reads and timeline validation.
inline constexpr ActionSpec specs[]={
  {"left_grip",'b'},{"right_grip",'b'},{"left_trigger",'b'},{"right_trigger",'b'},
  {"left_stick_click",'b'},{"right_stick_click",'b'},{"left_a",'b'},{"right_a",'b'},
  {"left_b",'b'},{"right_b",'b'},{"left_stick",'v',2},{"right_stick",'v',2},
  {"left_grip_force",'v',1},{"right_grip_force",'v',1},{"left_trigger_value",'v',1},{"right_trigger_value",'v',1},
  {"left_skeleton",'s'},{"right_skeleton",'s'},{"left_haptic",'h'},{"right_haptic",'h'}};
}
