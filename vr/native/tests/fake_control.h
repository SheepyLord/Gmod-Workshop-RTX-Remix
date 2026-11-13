// SPDX-License-Identifier: MIT
#pragma once
#include "include/rtxvr_api.h"
#include <cstdint>
struct FakeCounters {
  uint32_t keyboard_shows=0,keyboard_hides=0,keyboard_reads=0,binding_ui=0,colors=0,sorts=0,windows=0,window_flags=0;
  uint32_t keyboard_maxchars=0,keyboard_multiline=0,keyboard_flags=0,sort_value=0,binding_own_context=0;
  float red=0,green=0,blue=0;
  uint32_t eye_reads=0;
  uint32_t component_reads=0,skeleton_reads=0,controller_properties=0;
  uint32_t acknowledged=0,predicted=0;
  uint32_t init=0,shutdown=0,waits=0,manifests=0,actions=0,haptics=0,created=0,destroyed=0,eyes=0;
  uint32_t runtime_starts=0,runtime_stops=0,pushed=0,sources=0,absolute=0,relative=0,after_stop=0;
  uint32_t quality=0;
};
// Faults: 1 no SteamVR, 2 no HMD, 3 missing interface, 4 manifest error,
// 5 delayed init, 6 sleeping haptic, 7 WaitGetPoses error; the runtime stand-in refuses a quality step at 40.
using FakeReset=void (*)();
using FakeFault=void (*)(int);
using FakeStats=FakeCounters (*)();
using FakeEvent=void (*)(uint32_t);
using FakePose=rtxvr_FramePose (*)();
using FakeHoldInit=void (*)(bool);
using FakeInitEntered=bool (*)();
using FakeRenderDelay=void (*)(int);
using FakeComplete=void (*)();
using FakeTrace=const char* (*)();
using FakeSubmitTime=int64_t (*)();
using FakeStartInfo=rtxvr_StartInfo (*)();
using FakeQuality=rtxvr_Quality (*)();
using FakeKeyboardText=void (*)(const char*);
