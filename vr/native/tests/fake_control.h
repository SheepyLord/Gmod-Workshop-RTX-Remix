// SPDX-License-Identifier: MIT
#pragma once
#include "include/rtxvr_api.h"
#include <cstdint>
struct FakeCounters {
  uint32_t eye_reads=0;
  uint32_t acknowledged=0,predicted=0;
  uint32_t init=0,shutdown=0,waits=0,manifests=0,actions=0,haptics=0,created=0,destroyed=0,eyes=0;
  uint32_t runtime_starts=0,runtime_stops=0,pushed=0,sources=0,absolute=0,relative=0,after_stop=0;
};
// Faults: 1 no SteamVR, 2 no HMD, 3 missing interface, 4 manifest error,
// 5 delayed init, 6 sleeping haptic, 7 WaitGetPoses error.
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
