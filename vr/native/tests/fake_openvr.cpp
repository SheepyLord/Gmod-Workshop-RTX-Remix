// SPDX-License-Identifier: MIT
#define VR_API_EXPORT
#pragma warning(push)
#pragma warning(disable:4100)
#include "openvr_stubs.h"
#pragma warning(pop)
#include "fake_control.h"
#include <windows.h>
#include <atomic>
#include <cstring>
#include <cmath>
#include <deque>
#include <map>
#include <mutex>
#include <string>

#pragma warning(disable:4100) // Deliberately unused default stub arguments.
namespace {
FakeCounters count;
std::atomic<int> fault=0;
std::atomic<bool> hold_init=false,init_entered=false;
bool active=false;
bool reference_query=false;
std::deque<uint32_t> events;
std::mutex events_mutex;
std::map<uint64_t,bool> visible;
std::map<uint64_t,vr::HmdMatrix34_t> transforms;
std::map<uint64_t,float> widths;
uint64_t next_overlay=9007199254740997ull,next_action=1;
std::map<std::string,uint64_t> actions;
std::string manifest_path;
std::string keyboard_text;
vr::HmdMatrix34_t identity() { return {{{1,0,0,1},{0,1,0,2},{0,0,1,-3}}}; }
struct System final:vr::StubIVRSystem {
  bool IsTrackedDeviceConnected(vr::TrackedDeviceIndex_t i) override { return i<3 && !(fault==9&&i>0)&&!(fault==19&&i==1); }
  void AcknowledgeQuit_Exiting() override { ++count.acknowledged; }
  void GetDeviceToAbsoluteTrackingPose(vr::ETrackingUniverseOrigin,float,vr::TrackedDevicePose_t* p,uint32_t n) override {
    ++count.predicted;
    for(uint32_t i=0;i<n;++i) { p[i]={};p[i].mDeviceToAbsoluteTracking=identity();p[i].bPoseIsValid=i<3&&fault!=8;p[i].bDeviceIsConnected=i<3; }
  }
  vr::EVRInitError SetSDKVersion(uint32_t,uint32_t,uint32_t) override { return vr::VRInitError_None; }
  void GetRecommendedRenderTargetSize(uint32_t* w,uint32_t* h) override { *w=2016;*h=2240; }
  float GetFloatTrackedDeviceProperty(vr::TrackedDeviceIndex_t,vr::ETrackedDeviceProperty p,vr::ETrackedPropertyError* e=nullptr) override {
    if(e) *e=vr::TrackedProp_Success;
    return p==vr::Prop_DisplayFrequency_Float?90.f:p==vr::Prop_UserIpdMeters_Float?.064f:.003f;
  }
  uint32_t GetStringTrackedDeviceProperty(vr::TrackedDeviceIndex_t i,vr::ETrackedDeviceProperty p,char* out,uint32_t size,vr::ETrackedPropertyError* e=nullptr) override {
    if(e) *e=vr::TrackedProp_Success;const char* model="Fake Index";
    if(p==vr::Prop_RenderModelName_String) { ++count.controller_properties;model=i==1?"fake_index_left":"fake_index_right"; }
    if(size) strncpy_s(out,size,model,_TRUNCATE);return static_cast<uint32_t>(std::strlen(model)+1);
  }
  void GetProjectionRaw(vr::EVREye,float* l,float* r,float* t,float* b) override { ++count.eye_reads;*l=-1;*r=1;*t=-1;*b=1; }
  vr::HmdMatrix34_t GetEyeToHeadTransform(vr::EVREye eye) override {
    auto m=identity();m.m[0][3]=eye==vr::Eye_Left?-.032f:.032f;m.m[1][3]=m.m[2][3]=0;return m;
  }
  vr::TrackedDeviceIndex_t GetTrackedDeviceIndexForControllerRole(vr::ETrackedControllerRole role) override {
    return role==vr::TrackedControllerRole_LeftHand?1:2;
  }
  bool GetTimeSinceLastVsync(float* since,uint64_t* frame) override { *since=.001f;*frame=count.waits;return true; }
  bool PollNextEvent(vr::VREvent_t* out,uint32_t) override {
    std::lock_guard lock(events_mutex);
    if(events.empty()) return false;*out={};out->eventType=events.front();if(out->eventType==vr::VREvent_PropertyChanged) out->trackedDeviceIndex=1;events.pop_front();return true;
  }
  vr::EDeviceActivityLevel GetTrackedDeviceActivityLevel(vr::TrackedDeviceIndex_t) override { return vr::k_EDeviceActivityLevel_Standby; }
} fake_system;
struct Models final:vr::StubIVRRenderModels {
  bool GetComponentStateForDevicePath(const char*,const char* name,vr::VRInputValueHandle_t path,
      const vr::RenderModel_ControllerMode_State_t*,vr::RenderModel_ComponentState_t* out) override {
    ++count.component_reads;if(fault==17||(fault==25&&std::strcmp(name,"tip")==0)||((fault==20||fault==21)&&std::strcmp(name,"openxr_handmodel")==0)) return false;
    *out={};const float x=-40*3.14159265358979323846f/180,y=(path==11?-5:5)*3.14159265358979323846f/180;
    auto& m=out->mTrackingToComponentLocal;
    m.m[0][0]=cos(y);m.m[0][1]=sin(y)*sin(x);m.m[0][2]=sin(y)*cos(x);
    m.m[1][1]=cos(x);m.m[1][2]=-sin(x);m.m[2][0]=-sin(y);m.m[2][1]=cos(y)*sin(x);m.m[2][2]=cos(y)*cos(x);
    const bool tip=std::strcmp(name,"tip")==0;
    m.m[0][3]=(tip?-.006f:.015f)*(path==11?-1:1);m.m[1][3]=-.015f;m.m[2][3]=tip?.02f:.13f;
    if(fault==18) m.m[0][0]=NAN;
    return true;
  }
} models;
struct Compositor final:vr::StubIVRCompositor {
  vr::EVRCompositorError WaitGetPoses(vr::TrackedDevicePose_t* p,uint32_t n,vr::TrackedDevicePose_t*,uint32_t) override {
    if(const auto runtime=GetModuleHandleW(L"nlvr_test_runtime.dll"))
      if(const auto fn=GetProcAddress(runtime,"nlvr_fake_wait")) reinterpret_cast<void(*)()>(fn)();
    ++count.waits;if(!active) ++count.after_stop;
    for(uint32_t i=0;i<n;++i) { p[i]={};p[i].mDeviceToAbsoluteTracking=identity();p[i].bPoseIsValid=i<3&&fault!=8;p[i].bDeviceIsConnected=i<3; }
    return fault==7?vr::VRCompositorError_RequestFailed:vr::VRCompositorError_None;
  }
  bool GetFrameTiming(vr::Compositor_FrameTiming* t,uint32_t) override { t->m_nFrameIndex=count.waits;t->m_nNumFramePresents=count.waits;return true; }
  void GetCumulativeStats(vr::Compositor_CumulativeStats* s,uint32_t) override { *s={};s->m_nNumFramePresents=count.waits; }
  bool IsMotionSmoothingSupported() override { return true; }
  bool IsMotionSmoothingEnabled() override { return fault!=27; } // 27: Motion Smoothing off in SteamVR
} compositor;
struct Input final:vr::StubIVRInput {
  vr::EVRInputError SetActionManifestPath(const char* path) override { manifest_path=path;++count.manifests;return fault==4?vr::VRInputError_MismatchedActionManifest:vr::VRInputError_None; }
  vr::EVRInputError GetActionSetHandle(const char*,vr::VRActionSetHandle_t* out) override { *out=1;return vr::VRInputError_None; }
  vr::EVRInputError GetInputSourceHandle(const char* path,vr::VRInputValueHandle_t* out) override {
    *out=std::strstr(path,"left")?11:std::strstr(path,"right")?12:13;return vr::VRInputError_None;
  }
  vr::EVRInputError GetActionHandle(const char* path,vr::VRActionHandle_t* out) override {
    const auto [it,inserted]=actions.emplace(path,next_action);if(inserted) ++next_action;*out=it->second;return vr::VRInputError_None;
  }
  vr::EVRInputError UpdateActionState(vr::VRActiveActionSet_t*,uint32_t,uint32_t) override { ++count.actions;return vr::VRInputError_None; }
  vr::EVRInputError GetDigitalActionData(vr::VRActionHandle_t,vr::InputDigitalActionData_t* out,uint32_t,vr::VRInputValueHandle_t) override {
    *out={};out->bActive=true;out->bState=true;return vr::VRInputError_None;
  }
  vr::EVRInputError GetAnalogActionData(vr::VRActionHandle_t,vr::InputAnalogActionData_t* out,uint32_t,vr::VRInputValueHandle_t) override {
    *out={};out->bActive=true;out->x=.75f;return vr::VRInputError_None;
  }
  vr::EVRInputError GetSkeletalActionData(vr::VRActionHandle_t,vr::InputSkeletalActionData_t* out,uint32_t) override {
    *out={};out->bActive=true;return vr::VRInputError_None;
  }
  vr::EVRInputError GetSkeletalSummaryData(vr::VRActionHandle_t,vr::EVRSummaryType,vr::VRSkeletalSummaryData_t* out) override {
    *out={};for(float& f:out->flFingerCurl) f=.5f;
    for(unsigned i=0;i<vr::VRFingerSplay_Count;++i) out->flFingerSplay[i]=.1f*static_cast<float>(i+1);
    return vr::VRInputError_None;
  }
  vr::EVRInputError GetBoneCount(vr::VRActionHandle_t,uint32_t* out) override { *out=31;return fault==21?vr::VRInputError_InvalidSkeleton:vr::VRInputError_None; }
  vr::EVRInputError GetSkeletalBoneData(vr::VRActionHandle_t,vr::EVRSkeletalTransformSpace space,vr::EVRSkeletalMotionRange range,vr::VRBoneTransform_t* out,uint32_t n) override {
    ++count.skeleton_reads;
    if(n!=31||space!=vr::VRSkeletalTransformSpace_Model||range!=vr::VRSkeletalMotionRange_WithController) return vr::VRInputError_InvalidParam;
    for(unsigned i=0;i<n;++i) { out[i]={};out[i].orientation.w=1; }
    out[1].position.v[2]=.13f;
    for(unsigned i=0;i<4;++i) { out[7+i*5].position.v[0]=float(i)*.01f;out[7+i*5].position.v[2]=.05f; }
    if(fault==26&&!reference_query) for(unsigned i=0;i<n;++i) out[i].position.v[0]+=.009f;
    return vr::VRInputError_None;
  }
  vr::EVRInputError GetSkeletalReferenceTransforms(vr::VRActionHandle_t h,vr::EVRSkeletalTransformSpace space,vr::EVRSkeletalReferencePose,vr::VRBoneTransform_t* out,uint32_t n) override {
    reference_query=true;const auto result=GetSkeletalBoneData(h,space,vr::VRSkeletalMotionRange_WithController,out,n);reference_query=false;return result;
  }
  vr::EVRInputError TriggerHapticVibrationAction(vr::VRActionHandle_t,float,float,float,float,vr::VRInputValueHandle_t) override {
    ++count.haptics;return fault==6?vr::VRInputError_InvalidDevice:vr::VRInputError_None;
  }
  vr::EVRInputError OpenBindingUI(const char* key,vr::VRActionSetHandle_t set,vr::VRInputValueHandle_t device,bool desktop) override {
    ++count.binding_ui;count.binding_own_context=key==nullptr&&set==1&&(device==11||device==12||device==13)&&desktop;
    if(fault==13&&device!=13) return vr::VRInputError_InvalidDevice;
    return fault==12?vr::VRInputError_IPCError:vr::VRInputError_None;
  }
} input;
struct Overlay final:vr::StubIVROverlay {
  vr::EVROverlayError ShowKeyboard(vr::EGamepadTextInputMode,vr::EGamepadTextInputLineMode line,uint32_t flags,const char*,uint32_t maxchars,const char* text,uint64_t) override {
    ++count.keyboard_shows;count.keyboard_maxchars=maxchars;count.keyboard_multiline=line==vr::k_EGamepadTextInputLineModeMultipleLines;
    count.keyboard_flags=flags;keyboard_text=text;return fault==11?vr::VROverlayError_InvalidParameter:vr::VROverlayError_None;
  }
  uint32_t GetKeyboardText(char* text,uint32_t size) override {
    ++count.keyboard_reads;if(size) strncpy_s(text,size,keyboard_text.c_str(),_TRUNCATE);return static_cast<uint32_t>(keyboard_text.size()+1);
  }
  void HideKeyboard() override { ++count.keyboard_hides; }
  vr::EVROverlayError SetOverlayColor(vr::VROverlayHandle_t,float r,float g,float b) override {
    ++count.colors;count.red=r;count.green=g;count.blue=b;return vr::VROverlayError_None;
  }
  vr::EVROverlayError SetOverlaySortOrder(vr::VROverlayHandle_t,uint32_t order) override { ++count.sorts;count.sort_value=order;return vr::VROverlayError_None; }
  vr::EVROverlayError CreateOverlay(const char*,const char*,vr::VROverlayHandle_t* handle) override {
    ++count.created;*handle=next_overlay++;visible[*handle]=false;return vr::VROverlayError_None;
  }
  vr::EVROverlayError DestroyOverlay(vr::VROverlayHandle_t h) override { ++count.destroyed;if(!active) ++count.after_stop;visible.erase(h);return vr::VROverlayError_None; }
  vr::EVROverlayError ShowOverlay(vr::VROverlayHandle_t h) override { visible[h]=true;return vr::VROverlayError_None; }
  vr::EVROverlayError HideOverlay(vr::VROverlayHandle_t h) override { visible[h]=false;return vr::VROverlayError_None; }
  bool IsOverlayVisible(vr::VROverlayHandle_t h) override { return visible.contains(h)&&visible[h]; }
  vr::EVROverlayError SetOverlayTransformAbsolute(vr::VROverlayHandle_t h,vr::ETrackingUniverseOrigin,const vr::HmdMatrix34_t* m) override {
    transforms[h]=*m;++count.absolute;return vr::VROverlayError_None;
  }
  vr::EVROverlayError GetOverlayTransformAbsolute(vr::VROverlayHandle_t h,vr::ETrackingUniverseOrigin* origin,vr::HmdMatrix34_t* m) override {
    *origin=vr::TrackingUniverseStanding;*m=transforms[h];return vr::VROverlayError_None;
  }
  vr::EVROverlayError SetOverlayWidthInMeters(vr::VROverlayHandle_t h,float width) override { widths[h]=width;return vr::VROverlayError_None; }
  vr::EVROverlayError GetOverlayWidthInMeters(vr::VROverlayHandle_t h,float* width) override { *width=widths[h];return vr::VROverlayError_None; }
  vr::EVROverlayError GetOverlayTextureSize(vr::VROverlayHandle_t,uint32_t* w,uint32_t* h) override { *w=513;*h=257;return vr::VROverlayError_None; }
  vr::EVROverlayError SetOverlayTransformTrackedDeviceRelative(vr::VROverlayHandle_t,vr::TrackedDeviceIndex_t,const vr::HmdMatrix34_t*) override {
    ++count.relative;return vr::VROverlayError_None;
  }
  const char* GetOverlayErrorNameFromEnum(vr::EVROverlayError) override { return "fake overlay error"; }
} overlay;
}
extern "C" __declspec(dllexport) void nlvr_fake_reset() { count={};fault=0;hold_init=false;init_entered=false;active=false;{ std::lock_guard lock(events_mutex);events.clear(); }visible.clear();actions.clear();next_action=1; }
extern "C" __declspec(dllexport) void nlvr_fake_hold_init(bool held) { hold_init=held; }
extern "C" __declspec(dllexport) bool nlvr_fake_init_entered() { return init_entered.load(); }
extern "C" __declspec(dllexport) const char* nlvr_fake_manifest_path() { return manifest_path.c_str(); }
extern "C" __declspec(dllexport) void nlvr_fake_fault(int value) { fault=value; }
extern "C" __declspec(dllexport) FakeCounters nlvr_fake_stats() { return count; }
extern "C" __declspec(dllexport) void nlvr_fake_event(uint32_t code) { std::lock_guard lock(events_mutex);events.push_back(code); }
extern "C" __declspec(dllexport) void nlvr_fake_keyboard_text(const char* text) { keyboard_text=text; }
namespace vr {
uint32_t VR_CALLTYPE VR_GetInitToken() { return 1; }
uint32_t VR_CALLTYPE VR_InitInternal2(EVRInitError* error,EVRApplicationType,const char*) {
  ++count.init;init_entered=true;
  while(hold_init) Sleep(1);
  if(fault==5) Sleep(100);
  *error=fault==1?VRInitError_Init_InstallationNotFound:fault==2?VRInitError_Init_HmdNotFound:VRInitError_None;
  active=*error==VRInitError_None;return 1;
}
void VR_CALLTYPE VR_ShutdownInternal() { ++count.shutdown;active=false; }
void* VR_CALLTYPE VR_GetGenericInterface(const char* version,EVRInitError* error) {
  *error=VRInitError_None;
  if(!active||fault==3) { *error=VRInitError_Init_InterfaceNotFound;return nullptr; }
  if(std::strcmp(version,IVRSystem_Version)==0) return &fake_system;
  if(std::strcmp(version,IVRCompositor_Version)==0) return &compositor;
  if(std::strcmp(version,IVRInput_Version)==0) return &input;
  if(std::strcmp(version,IVROverlay_Version)==0) return &overlay;
  if(std::strcmp(version,IVRRenderModels_Version)==0&&fault!=16) return &models;
  *error=VRInitError_Init_InterfaceNotFound;return nullptr;
}
const char* VR_CALLTYPE VR_GetVRInitErrorAsSymbol(EVRInitError error) {
  return error==VRInitError_Init_HmdNotFound?"VRInitError_Init_HmdNotFound":"VRInitError_Init_InstallationNotFound";
}
}
