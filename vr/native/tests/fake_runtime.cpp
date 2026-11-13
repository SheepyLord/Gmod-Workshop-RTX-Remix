// SPDX-License-Identifier: MIT
#include "fake_control.h"
#include <openvr.h>
#include <windows.h>
#include <chrono>
#include <cstring>
#include <mutex>
#include <string>
#include <thread>
namespace {
std::mutex mutex;
FakeCounters count;
int fault=0,delay=0;
bool pending=false;
std::thread renderer;
std::string trace;
int64_t submitted_at=0;
rtxvr_FramePose last{};
rtxvr_StartInfo started{};
rtxvr_Status status{};
rtxvr_GetGenericInterfaceFn generic=nullptr;
void complete() {
  if(!pending) return;
  trace+='S'; // Publish the completion count only after the stand-in Submit/handoff.
  submitted_at=std::chrono::duration_cast<std::chrono::nanoseconds>(std::chrono::steady_clock::now().time_since_epoch()).count();
  ++status.framesRendered;if(started.getGenericInterface) ++status.framesSubmitted;pending=false;
}
void join() { if(renderer.joinable()) renderer.join(); }
}
extern "C" __declspec(dllexport) void nlvr_fake_reset() {
  join();std::lock_guard lock(mutex);count={};fault=0;delay=0;pending=false;trace.clear();submitted_at=0;status={};last={};started={};generic=nullptr;
}
extern "C" __declspec(dllexport) void nlvr_fake_fault(int value) {
  std::lock_guard lock(mutex);fault=value;if(value==0&&status.state==RTXVR_STATE_STARTING) status.state=RTXVR_STATE_RUNNING;
}
extern "C" __declspec(dllexport) void nlvr_fake_render_delay(int value) { std::lock_guard lock(mutex);delay=value; }
extern "C" __declspec(dllexport) void nlvr_fake_complete() { std::lock_guard lock(mutex);complete(); }
extern "C" __declspec(dllexport) void nlvr_fake_wait() {
  std::lock_guard lock(mutex);trace+='W';if(pending) ++count.after_stop;
}
extern "C" __declspec(dllexport) const char* nlvr_fake_trace() {
  thread_local std::string copy;std::lock_guard lock(mutex);copy=trace;return copy.c_str();
}
extern "C" __declspec(dllexport) int64_t nlvr_fake_submit_time() { std::lock_guard lock(mutex);return submitted_at; }
extern "C" __declspec(dllexport) FakeCounters nlvr_fake_stats() { std::lock_guard lock(mutex);return count; }
extern "C" __declspec(dllexport) rtxvr_FramePose nlvr_fake_pose() { std::lock_guard lock(mutex);return last; }
extern "C" __declspec(dllexport) rtxvr_StartInfo nlvr_fake_start_info() { std::lock_guard lock(mutex);return started; }
extern "C" uint32_t rtxvr_GetApiVersion() { std::lock_guard lock(mutex);return fault==1?99u:RTXVR_API_VERSION; }
extern "C" int rtxvr_Start(const rtxvr_StartInfo* info) {
  std::lock_guard lock(mutex);++count.runtime_starts;
  generic=info->getGenericInterface;
  started=*info;
  if(!generic&&!(info->flags&RTXVR_START_NO_SUBMIT)) return RTXVR_E_ARGUMENT;
  if(info->structSize!=sizeof(*info)||info->apiVersion!=RTXVR_API_VERSION) return RTXVR_E_VERSION;
  status={};status.structSize=sizeof status;status.state=RTXVR_STATE_RUNNING;status.eyeWidth=info->eyeWidth;status.eyeHeight=info->eyeHeight;
  if(fault==2) return RTXVR_E_EXTENSION;
  if(fault==3) { status.state=RTXVR_STATE_FAILED;status.lastError=RTXVR_E_EXTENSION;strcpy_s(status.lastErrorText,"missing VK_TEST_required"); }
  if(fault==4) status.state=RTXVR_STATE_STARTING;
  return RTXVR_OK;
}
extern "C" void rtxvr_Stop() {
  join();std::lock_guard lock(mutex);++count.runtime_stops;
  if(generic) { int error=0;if(!generic(vr::IVRSystem_Version,&error)) ++count.after_stop; }
  status.state=RTXVR_STATE_OFF;pending=false;
}
extern "C" int rtxvr_UpdateEyes(const rtxvr_Eye*) { std::lock_guard lock(mutex);++count.eyes;return RTXVR_OK; }
extern "C" int rtxvr_PushFramePose(const rtxvr_FramePose* pose) {
  join();std::lock_guard lock(mutex);++count.pushed;last=*pose;pending=true;
  if(delay==0) complete();
  else if(delay>0) renderer=std::thread([ms=delay] {
    const auto timer=CreateWaitableTimerExW(nullptr,nullptr,CREATE_WAITABLE_TIMER_HIGH_RESOLUTION,TIMER_MODIFY_STATE|SYNCHRONIZE);
    LARGE_INTEGER due{};due.QuadPart=-static_cast<LONGLONG>(ms)*10000;
    if(timer&&SetWaitableTimer(timer,&due,0,nullptr,nullptr,FALSE)) WaitForSingleObject(timer,1000);
    else Sleep(static_cast<DWORD>(ms));
    if(timer) CloseHandle(timer);
    std::lock_guard guard(mutex);complete();
  });
  return RTXVR_OK;
}
extern "C" int rtxvr_SetOverlaySource(uint64_t,uint32_t,uint32_t) { std::lock_guard lock(mutex);++count.sources;return RTXVR_OK; }
extern "C" int rtxvr_Capture(const wchar_t*,uint32_t) { return RTXVR_OK; }
extern "C" int rtxvr_GetStatus(rtxvr_Status* out) { std::lock_guard lock(mutex);*out=status;return RTXVR_OK; }
#ifdef NLVR_FAKE_WINDOW
#pragma comment(linker, "/EXPORT:rtxvr_SetOverlayWindow")
extern "C" int rtxvr_SetOverlayWindow(uint64_t,uint32_t flags) {
  std::lock_guard lock(mutex);++count.windows;count.window_flags=flags;return fault==5?RTXVR_E_ARGUMENT:RTXVR_OK;
}
#endif
