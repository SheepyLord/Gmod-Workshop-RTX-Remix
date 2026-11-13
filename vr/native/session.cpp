// SPDX-License-Identifier: MIT
#include "session.h"
#include "input_actions.h"
#include "lua_policy.h"
#include "probe/discovery.h"
#include "sim_device.h"
#include "nl/fs.h"
#include "nl/utf8.h"
#include <windows.h>
#include <algorithm>
#include <atomic>
#include <cstring>
#include <deque>
#include <condition_variable>
#include <mutex>
#include <thread>

namespace nl::vr {
namespace {
using Clock=std::chrono::steady_clock;
double pose_clock() { LARGE_INTEGER t{},f{};QueryPerformanceCounter(&t);QueryPerformanceFrequency(&f);return double(t.QuadPart)/double(f.QuadPart); }
void need(bool condition,const std::string& detail) { if(!condition) throw std::runtime_error(detail); }
template<class T> T symbol(HMODULE dll,const char* name) {
  const auto fn=GetProcAddress(dll,name);
  need(fn!=nullptr,std::string("missing export: ")+name);
  return reinterpret_cast<T>(fn);
}
HMODULE load(const std::filesystem::path& path) {
  need(path.is_absolute(),"DLL path must be absolute");
  const auto dll=LoadLibraryExW(path.c_str(),nullptr,LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR|LOAD_LIBRARY_SEARCH_DEFAULT_DIRS);
  need(dll!=nullptr,"cannot load "+nl::fs::utf8(path.wstring())+" (Windows error "+std::to_string(GetLastError())+")");
  return dll;
}
rtxvr_Matrix34 matrix(const ::vr::HmdMatrix34_t& m) {
  rtxvr_Matrix34 out{};static_assert(sizeof out==sizeof m);std::memcpy(&out,&m,sizeof out);return out;
}
::vr::HmdMatrix34_t matrix(const rtxvr_Matrix34& m) {
  ::vr::HmdMatrix34_t out{};std::memcpy(&out,&m,sizeof out);return out;
}
Pose pose(const ::vr::TrackedDevicePose_t& p) {
  return source_pose(matrix(p.mDeviceToAbsoluteTracking),p.bPoseIsValid&&p.bDeviceIsConnected,
    {p.vVelocity.v[0],p.vVelocity.v[1],p.vVelocity.v[2]},
    {p.vAngularVelocity.v[0],p.vAngularVelocity.v[1],p.vAngularVelocity.v[2]});
}
std::string action_path(const ActionSpec& s) { return std::string("/actions/main/")+(s.type=='h'?"out/":"in/")+s.name; }
void input_check(::vr::EVRInputError error,const char* operation) {
  need(error==::vr::VRInputError_None,std::string(operation)+": VRInputError "+std::to_string(error));
}
void runtime_check(int code,const char* operation) {
  need(code==RTXVR_OK,std::string(operation)+": RTXVR error "+std::to_string(code));
}
void keyboard_string(const std::string& text,std::size_t limit) {
  need(text.size()<=limit&&text.find('\0')==text.npos&&nl::utf8::valid(text),"invalid keyboard UTF-8 text or length");
}
}
struct Session::Impl {
  Impl(std::filesystem::path folder,WindowCalls& calls):module_folder(std::move(folder)),window_input(calls) {}
  std::filesystem::path module_folder;
  WindowInput window_input;
  mutable std::mutex status_mutex, api_mutex;
  std::mutex lifecycle,stop_mutex,event_mutex;
  std::condition_variable stop_requested;
  std::string phase="off",detail;
  std::thread worker;
  std::atomic<bool> cancelled=false;
  std::atomic<bool> worker_finished=true;
  std::atomic<bool> eyes_dirty=false;
  HMODULE openvr=nullptr,runtime=nullptr;
  using Init=uint32_t (*)(::vr::EVRInitError*,::vr::EVRApplicationType,const char*);
  using Shutdown=void (*)();
  using ErrorName=const char* (*)(::vr::EVRInitError);
  Shutdown shutdown=nullptr;
  rtxvr_GetGenericInterfaceFn generic=nullptr;
  bool initialised=false,renderer_started=false,ready=false,quit=false;
  ::vr::IVRSystem* system=nullptr;
  ::vr::IVRCompositor* compositor=nullptr;
  ::vr::IVRInput* input=nullptr;
  ::vr::IVROverlay* overlay=nullptr;
  ::vr::IVRRenderModels* render_models=nullptr;
  ControllerFrameCache controller_frames;
  std::array<ControllerFrames,2> simulated_controllers{};
  decltype(&rtxvr_Start) rt_start=nullptr;
  decltype(&rtxvr_Stop) rt_stop=nullptr;
  decltype(&rtxvr_UpdateEyes) rt_eyes=nullptr;
  decltype(&rtxvr_PushFramePose) rt_pose=nullptr;
  decltype(&rtxvr_SetOverlaySource) rt_overlay=nullptr;
  decltype(&rtxvr_Capture) rt_capture=nullptr;
  decltype(&rtxvr_GetStatus) rt_status=nullptr;
  decltype(&rtxvr_SetOverlayWindow) rt_window=nullptr;
  Options options;
  Info facts;
  rtxvr_Eye eyes[2]{};
  std::optional<Timeline> timeline;
  std::optional<ScriptSample> script;
  Clock::time_point epoch;
  Clock::time_point next_sim_frame;
  HANDLE sim_timer=nullptr;
  uint64_t next_sim_overlay=1;
  std::size_t script_event=0;
  bool keyboard_owned=false,keyboard_done=false;
  std::string keyboard_text;
  uint32_t keyboard_limit=1024;
  static constexpr uint64_t keyboard_token=0x4e4c5652;
  uint64_t sequence=0;
  struct PendingPose { uint64_t sequence; rtxvr_Matrix34 head; bool scripted; double sampled,target,base; };
  std::deque<PendingPose> poses;
  struct Overlay {
    std::string device="world";rtxvr_Matrix34 local=source_matrix({},{}),absolute{};
    float width=0.2f,alpha=1;bool wanted=false,placed=false,window=false;
    uint32_t texture_width=0,texture_height=0,sort=0;
    Vec3 color{1,1,1};
  };
  std::map<uint64_t,Overlay> overlays;
  std::deque<Event> pending_events;
  std::map<std::string,::vr::VRActionHandle_t,std::less<>> handles;
  ::vr::VRActionSetHandle_t action_set=0;
  ::vr::VRInputValueHandle_t hands[2]{};
  Actions action_values;

  void status(std::string state,std::string message={}) {
    std::lock_guard lock(status_mutex);phase=std::move(state);detail=std::move(message);
  }
  void request_cancel() {
    // The predicate and wait use the same mutex: a notify cannot slip between the predicate
    // check and entering the wait. This mutex is never held across OpenVR or renderer calls.
    { std::lock_guard lock(stop_mutex);cancelled=true; }
    stop_requested.notify_one();
  }
  template<class T> T* interface(const char* version) {
    int error=0;auto* ptr=generic(version,&error);
    need(ptr&&error==0,std::string("OpenVR interface unavailable: ")+version+" ("+std::to_string(error)+")");
    return static_cast<T*>(ptr);
  }
  std::string property(::vr::ETrackedDeviceProperty p) const {
    char text[1024]{};::vr::ETrackedPropertyError error{};
    system->GetStringTrackedDeviceProperty(::vr::k_unTrackedDeviceIndex_Hmd,p,text,sizeof text,&error);
    return error==::vr::TrackedProp_Success?text:"";
  }
  void read_eyes() {
    system->GetRecommendedRenderTargetSize(&facts.eye_width,&facts.eye_height);
    facts.refresh=system->GetFloatTrackedDeviceProperty(::vr::k_unTrackedDeviceIndex_Hmd,::vr::Prop_DisplayFrequency_Float);
    facts.ipd=system->GetFloatTrackedDeviceProperty(::vr::k_unTrackedDeviceIndex_Hmd,::vr::Prop_UserIpdMeters_Float);
    for(int i=0;i<2;++i) {
      const auto eye=static_cast<::vr::EVREye>(i);
      system->GetProjectionRaw(eye,&eyes[i].tanLeft,&eyes[i].tanRight,&eyes[i].tanTop,&eyes[i].tanBottom);
      eyes[i].eyeToHead=matrix(system->GetEyeToHeadTransform(eye));
    }
  }
  void require_ready() const { need(ready&&!cancelled,"nlvr is not running"); }
  std::unique_lock<std::mutex> access() const {
    std::unique_lock lock(api_mutex,std::try_to_lock);
    need(lock.owns_lock(),"nlvr is busy starting or stopping");require_ready();return lock;
  }
  void fail(const std::string& message) {
    window_input.release();
    { std::lock_guard lock(status_mutex);
      if(phase=="stopping") return;
      phase="failed";detail=message;request_cancel();
    }
  }
  bool renderer_ready(rtxvr_Status& result,bool allow_start=true) {
    result={};result.structSize=sizeof result;
    const auto code=rt_status(&result);result.lastErrorText[sizeof(result.lastErrorText)-1]=0;
    if(code!=RTXVR_OK) { fail("rtxvr_GetStatus: RTXVR error "+std::to_string(code));return false; }
    if(result.state==RTXVR_STATE_STARTING) {
      return allow_start&&!cancelled;
    }
    if(result.state!=RTXVR_STATE_RUNNING) {
      fail(result.lastErrorText[0]?result.lastErrorText:"RTX VR output stopped");return false;
    }
    return true;
  }
  Overlay& owned(uint64_t handle) {
    require_ready();const auto it=overlays.find(handle);need(it!=overlays.end(),"overlay is not owned by nlvr");return it->second;
  }
  void overlay_check(::vr::EVROverlayError error) const {
    need(error==::vr::VROverlayError_None,std::string("OpenVR overlay: ")+overlay->GetOverlayErrorNameFromEnum(error));
  }
  void place(uint64_t handle,Overlay& item) {
    bool placed=true;
    if(options.simulate) {
      item.absolute=to_openvr(item.local);
      if(item.device!="world") {
        placed=script.has_value();
        if(script) {
          const auto index=item.device=="head"?0u:item.device=="left"?1u:2u;
          const auto& p=script->poses[index];placed=p.valid;
          item.absolute=to_openvr(compose(source_matrix(p.pos,rotation(p.ang)),item.local));
        }
      }
      item.placed=placed;return;
    }
    const auto local=matrix(to_openvr(item.local));
    if(item.device=="world") overlay_check(overlay->SetOverlayTransformAbsolute(handle,::vr::TrackingUniverseStanding,&local));
    else if(script) {
      const auto index=item.device=="head"?0u:item.device=="left"?1u:2u;
      const auto& p=script->poses[index];
      const auto world=matrix(to_openvr(compose(source_matrix(p.pos,rotation(p.ang)),item.local)));
      overlay_check(overlay->SetOverlayTransformAbsolute(handle,::vr::TrackingUniverseStanding,&world));
    } else {
      const auto index=item.device=="head"?::vr::k_unTrackedDeviceIndex_Hmd:
        system->GetTrackedDeviceIndexForControllerRole(item.device=="left"?::vr::TrackedControllerRole_LeftHand: ::vr::TrackedControllerRole_RightHand);
      // Sleeping controllers can be absent. Keep the relative attachment for when they wake.
      placed=index!=::vr::k_unTrackedDeviceIndexInvalid && system->IsTrackedDeviceConnected(index);
      if(placed) overlay_check(overlay->SetOverlayTransformTrackedDeviceRelative(handle,index,&local));
    }
    item.placed=placed;
    overlay_check(item.wanted&&placed?overlay->ShowOverlay(handle):overlay->HideOverlay(handle));
  }
  void cleanup() noexcept {
    window_input.release();
    ready=false;
    // Stop is a barrier: the renderer will never use OpenVR again after it returns.
    if(renderer_started&&rt_stop) rt_stop();
    renderer_started=false;
    if(overlay&&keyboard_owned) overlay->HideKeyboard();
    if(overlay) for(const auto& [handle,item]:overlays) { (void)item;overlay->DestroyOverlay(handle); }
    overlays.clear();
    if(initialised&&shutdown) shutdown();
    initialised=false;system=nullptr;compositor=nullptr;input=nullptr;overlay=nullptr;render_models=nullptr;
    controller_frames.reset();simulated_controllers={};
    if(openvr) FreeLibrary(openvr);
    if(runtime) FreeLibrary(runtime);
    if(sim_timer) CloseHandle(sim_timer);
    sim_timer=nullptr;script_event=0;keyboard_owned=false;keyboard_done=false;keyboard_text.clear();
    openvr=nullptr;runtime=nullptr;shutdown=nullptr;generic=nullptr;
    rt_start=nullptr;rt_stop=nullptr;rt_eyes=nullptr;rt_pose=nullptr;rt_overlay=nullptr;rt_capture=nullptr;rt_status=nullptr;rt_window=nullptr;
    poses.clear();timeline.reset();script.reset();handles.clear();action_values.clear();pending_events.clear();facts={};
  }
  void initialise() {
      if(options.runtime_dll.empty()) {
        need(GetModuleHandleExW(0,L"d3d9.dll",&runtime)!=0,"RTX runtime has no VR output (d3d9.dll is not loaded)");
      } else runtime=load(options.runtime_dll);
      const auto version=symbol<decltype(&rtxvr_GetApiVersion)>(runtime,"rtxvr_GetApiVersion")();
      need(version==RTXVR_API_VERSION,"RTXVR API version mismatch: expected "+std::to_string(RTXVR_API_VERSION)+", got "+std::to_string(version));
      rt_start=symbol<decltype(rt_start)>(runtime,"rtxvr_Start");rt_stop=symbol<decltype(rt_stop)>(runtime,"rtxvr_Stop");
      rt_eyes=symbol<decltype(rt_eyes)>(runtime,"rtxvr_UpdateEyes");rt_pose=symbol<decltype(rt_pose)>(runtime,"rtxvr_PushFramePose");
      rt_overlay=symbol<decltype(rt_overlay)>(runtime,"rtxvr_SetOverlaySource");
      rt_capture=symbol<decltype(rt_capture)>(runtime,"rtxvr_Capture");rt_status=symbol<decltype(rt_status)>(runtime,"rtxvr_GetStatus");
      rt_window=reinterpret_cast<decltype(rt_window)>(GetProcAddress(runtime,"rtxvr_SetOverlayWindow"));
      if(cancelled) return;
      if(options.simulate) {
        const auto root=simulation_root(module_folder);
        const auto device=SimDevice::load(checked_data_path(root/L"simulated-index.json"));
        timeline=Timeline::load(checked_data_path(options.timeline));
        facts.simulated=true;facts.model=device.model;facts.tracking=device.tracking;
        facts.eye_width=device.width;facts.eye_height=device.height;facts.refresh=device.refresh;facts.ipd=device.ipd;
        simulated_controllers=device.controllers;
        std::copy(std::begin(device.eyes),std::end(device.eyes),std::begin(eyes));
      } else {
      openvr=load(options.openvr_dll.empty()?module_folder/L"openvr_api.dll":options.openvr_dll);
      const auto init=symbol<Init>(openvr,"VR_InitInternal2");shutdown=symbol<Shutdown>(openvr,"VR_ShutdownInternal");
      generic=symbol<rtxvr_GetGenericInterfaceFn>(openvr,"VR_GetGenericInterface");
      const auto name=symbol<ErrorName>(openvr,"VR_GetVRInitErrorAsSymbol");
      if(cancelled) return;
      ::vr::EVRInitError error=::vr::VRInitError_None;
      init(&error,::vr::VRApplication_Scene,nullptr);initialised=true;
      need(error==::vr::VRInitError_None,std::string("OpenVR init: ")+name(error)+" ("+std::to_string(error)+")");
      if(cancelled) return;
      system=interface<::vr::IVRSystem>(::vr::IVRSystem_Version);
      const auto sdk=system->SetSDKVersion(::vr::k_nSteamVRVersionMajor,::vr::k_nSteamVRVersionMinor,::vr::k_nSteamVRVersionBuild);
      need(sdk==::vr::VRInitError_None,std::string("OpenVR SDK: ")+name(sdk));
      compositor=interface<::vr::IVRCompositor>(::vr::IVRCompositor_Version);
      input=interface<::vr::IVRInput>(::vr::IVRInput_Version);overlay=interface<::vr::IVROverlay>(::vr::IVROverlay_Version);
      int render_error=0;
      render_models=static_cast<::vr::IVRRenderModels*>(generic(::vr::IVRRenderModels_Version,&render_error));
      if(render_error) render_models=nullptr; // Optional: unknown controllers retain the raw fallback.
      compositor->SetTrackingSpace(::vr::TrackingUniverseStanding);
      const auto manifest=options.manifest.empty()?
        (module_folder/L"../../addons/nlvr/input/nlvr_actions.json").lexically_normal():options.manifest;
      need(manifest.is_absolute()&&std::filesystem::is_regular_file(manifest),"SteamVR action manifest not found: "+nl::fs::utf8(manifest.wstring()));
      input_check(input->SetActionManifestPath(nl::fs::utf8(manifest.wstring()).c_str()),"SetActionManifestPath");
      input_check(input->GetActionSetHandle("/actions/main",&action_set),"GetActionSetHandle");
      input_check(input->GetInputSourceHandle("/user/hand/left",&hands[0]),"GetInputSourceHandle(left)");
      input_check(input->GetInputSourceHandle("/user/hand/right",&hands[1]),"GetInputSourceHandle(right)");
      for(const auto& spec:specs) {
        ::vr::VRActionHandle_t handle=0;
        input_check(input->GetActionHandle(action_path(spec).c_str(),&handle),"GetActionHandle");handles[spec.name]=handle;
      }
      facts.model=property(::vr::Prop_ModelNumber_String);facts.tracking=property(::vr::Prop_TrackingSystemName_String);read_eyes();
      if(!options.timeline.empty()) timeline=Timeline::load(options.timeline);
      }
      rtxvr_StartInfo start{};start.structSize=sizeof start;start.apiVersion=RTXVR_API_VERSION;
      start.getGenericInterface=generic;start.eyeWidth=facts.eye_width;start.eyeHeight=facts.eye_height;
      start.refreshHz=facts.refresh;start.worldUnitsPerMetre=options.scale;start.renderScale=options.render_scale;
      std::copy(std::begin(eyes),std::end(eyes),std::begin(start.eyes));
      start.flags=options.simulate?RTXVR_START_NO_SUBMIT:(options.no_submit?RTXVR_START_NO_SUBMIT:0)|RTXVR_START_RENDER_PACING;
      if(cancelled) return;
      const auto start_error=rt_start(&start);
      if(start_error!=RTXVR_OK) {
        rtxvr_Status report{};report.structSize=sizeof report;
        const auto status_error=rt_status(&report);report.lastErrorText[sizeof(report.lastErrorText)-1]=0;
        need(false,status_error==RTXVR_OK&&report.lastErrorText[0]?report.lastErrorText:
          "rtxvr_Start: RTXVR error "+std::to_string(start_error));
      }
      renderer_started=true;
      if(cancelled) return;
      if(options.simulate) {
        sim_timer=CreateWaitableTimerExW(nullptr,nullptr,CREATE_WAITABLE_TIMER_HIGH_RESOLUTION,TIMER_MODIFY_STATE|SYNCHRONIZE);
        facts.simulation_high_resolution=sim_timer!=nullptr;
        if(!sim_timer) sim_timer=CreateWaitableTimerW(nullptr,FALSE,nullptr);
        need(sim_timer!=nullptr,"could not create simulated frame timer");
        script=timeline->sample(0);
      }
      facts.overlay_window_supported=rt_window!=nullptr;
      eyes_dirty=false;epoch=Clock::now();ready=true;
      next_sim_frame=epoch;
      { std::lock_guard lock(status_mutex);if(!cancelled) { phase="running";detail.clear(); } }
  }
  void run() noexcept {
    std::string error;
    try {
      { std::lock_guard lock(api_mutex);initialise(); }
      while(!cancelled) {
        { std::unique_lock lock(stop_mutex);stop_requested.wait_for(lock,std::chrono::milliseconds(20),[&] { return cancelled.load(); }); }
        if(cancelled) break;
        if(ready) {
          if(!options.simulate) poll_events();
          poll_script_events();
          if(timeline&&timeline->quit_at>=0 && std::chrono::duration<double>(Clock::now()-epoch).count()>=timeline->quit_at) handle_quit();
        }
      }
    } catch(const std::exception& e) { error=e.what(); }
    catch(...) { error="nlvr worker failed"; }
    { std::lock_guard lock(api_mutex);cleanup(); }
    { std::lock_guard lock(status_mutex);
      if(phase=="stopping"||quit) { phase="off";if(!quit) detail.clear(); }
      else if(phase!="failed") { phase="failed";detail=error.empty()?"nlvr session ended":error; }
      worker_finished.store(true,std::memory_order_release);
    }
  }
  void handle_quit() {
    if(quit) return;
    if(system) system->AcknowledgeQuit_Exiting();quit=true;
    status("stopping",options.simulate?"Simulated VR timeline requested the session to end":"SteamVR requested the VR session to end");request_cancel();
  }
  void queue_event(Event event) {
    std::lock_guard events_lock(event_mutex);
    if(pending_events.size()==256) pending_events.pop_front();
    pending_events.push_back(std::move(event));
  }
  void poll_script_events() {
    if(!timeline) return;
    const auto seconds=std::chrono::duration<double>(Clock::now()-epoch).count();
    while(script_event<timeline->events.size()&&timeline->events[script_event].time<=seconds) {
      const auto& e=timeline->events[script_event++];
      { std::lock_guard lock(event_mutex);
        if(e.type=="keyboard_done") { keyboard_text=e.text;keyboard_done=true; }
        else {
          if(overlay&&keyboard_owned) overlay->HideKeyboard();
          keyboard_owned=false;
        }
      }
      queue_event({e.type,static_cast<uint32_t>(e.type=="keyboard_done"?::vr::VREvent_KeyboardDone: ::vr::VREvent_KeyboardClosed),0,e.text});
    }
  }
  void poll_events() {
    ::vr::VREvent_t e{};
    for(unsigned count=0;count<1024&&system->PollNextEvent(&e,sizeof e);++count) {
      const char* type="other";
      switch(e.eventType) {
        case ::vr::VREvent_Quit: case ::vr::VREvent_DriverRequestedQuit: type="quit";handle_quit();break;
        case ::vr::VREvent_DashboardActivated:type="dashboard_on";break;
        case ::vr::VREvent_DashboardDeactivated:type="dashboard_off";break;
        case ::vr::VREvent_EnterStandbyMode:type="standby";break;
        case ::vr::VREvent_LeaveStandbyMode:type="wake";break;
        case ::vr::VREvent_IpdChanged:type="ipd";eyes_dirty.store(true,std::memory_order_release);break;
        case ::vr::VREvent_TrackedDeviceActivated: case ::vr::VREvent_TrackedDeviceDeactivated:
        case ::vr::VREvent_TrackedDeviceRoleChanged:
          { std::lock_guard lock(api_mutex);controller_frames.invalidate(e.trackedDeviceIndex); }break;
        case ::vr::VREvent_TrackedDeviceUpdated: case ::vr::VREvent_PropertyChanged:
          { std::lock_guard lock(api_mutex);controller_frames.refresh(e.trackedDeviceIndex); }break;
        case ::vr::VREvent_KeyboardDone: {
          std::lock_guard lock(event_mutex);
          if(!keyboard_owned||keyboard_done||e.data.keyboard.overlayHandle!=::vr::k_ulOverlayHandleInvalid||
            (e.data.keyboard.uUserValue&&e.data.keyboard.uUserValue!=keyboard_token)) continue;
          std::array<char,16385> text{};overlay->GetKeyboardText(text.data(),static_cast<uint32_t>(text.size()));
          text.back()=0;keyboard_text=text.data();keyboard_done=true;
          if(pending_events.size()==256) pending_events.pop_front();
          pending_events.push_back({"keyboard_done",e.eventType,e.trackedDeviceIndex,keyboard_text});continue;
        }
        case ::vr::VREvent_KeyboardClosed: case ::vr::VREvent_KeyboardClosed_Global: {
          std::lock_guard lock(event_mutex);
          if(!keyboard_owned||e.data.keyboard.overlayHandle!=::vr::k_ulOverlayHandleInvalid||
            (e.data.keyboard.uUserValue&&e.data.keyboard.uUserValue!=keyboard_token)) continue;
          keyboard_owned=false;type="keyboard_closed";break;
        }
        default:break;
      }
      queue_event({type,e.eventType,e.trackedDeviceIndex,{}});
    }
  }
  void read_actions() {
    ::vr::VRActiveActionSet_t set{};set.ulActionSet=action_set;
    const auto result=options.simulate?::vr::VRInputError_None:input->UpdateActionState(&set,sizeof set,1);
    facts.input_detail=result==::vr::VRInputError_None?"":"UpdateActionState: VRInputError "+std::to_string(result);
    Actions fresh;
    for(const auto& spec:specs) {
      if(spec.type=='h') continue;
      Action a;const auto handle=options.simulate?0:handles.at(spec.name);
      if(options.simulate) a.active=true;
      else if(result!=::vr::VRInputError_None) a.error=result;
      else if(spec.type=='b') {
        ::vr::InputDigitalActionData_t data{};
        a.error=input->GetDigitalActionData(handle,&data,sizeof data,::vr::k_ulInvalidInputValueHandle);
        a.active=data.bActive;a.state=data.bState;a.changed=data.bChanged;
      } else if(spec.type=='v') {
        ::vr::InputAnalogActionData_t data{};
        a.error=input->GetAnalogActionData(handle,&data,sizeof data,::vr::k_ulInvalidInputValueHandle);
        a.active=data.bActive;a.value={data.x,data.y,data.z};
      } else {
        ::vr::InputSkeletalActionData_t data{};::vr::VRSkeletalSummaryData_t summary{};
        a.error=input->GetSkeletalActionData(handle,&data,sizeof data);a.active=data.bActive;
        if(a.error==0&&a.active) {
          a.error=input->GetSkeletalSummaryData(handle,::vr::VRSummaryType_FromDevice,&summary);
          std::copy(std::begin(summary.flFingerCurl),std::end(summary.flFingerCurl),a.curls.begin());
          std::copy(std::begin(summary.flFingerSplay),std::end(summary.flFingerSplay),a.splay.begin());
        }
      }
      if(a.error!=0) a.active=false;
      fresh.emplace(spec.name,a);
    }
    if(script) {
      for(auto& [name,a]:fresh) { (void)name;a={};a.active=true; }
      for(const auto& [name,a]:script->actions) if(auto found=fresh.find(name);found!=fresh.end()) found->second=a;
      for(auto& [name,a]:fresh) {
        const auto old=action_values.find(name);
        a.changed=a.state!=(old!=action_values.end()&&old->second.state);
      }
    }
    action_values=std::move(fresh);
  }
};
Session::Session(std::filesystem::path folder,WindowCalls& calls):impl_(std::make_unique<Impl>(std::move(folder),calls)) {}
std::filesystem::path Session::data_path(const std::string& name,bool capture) const { return named_data(data_root(impl_->module_folder),name,capture); }
Session::~Session() {
  // Unlike Exit VR, unloading cannot leave code executing in this DLL. OpenVR exposes no Init cancellation.
  auto& s=*impl_;std::lock_guard life(s.lifecycle);
  s.request_cancel();
  if(s.worker.joinable()) s.worker.join();
}
Probe Session::probe() const {
  Probe result;
  if(const auto dll=GetModuleHandleW(L"d3d9.dll")) if(const auto fn=GetProcAddress(dll,"rtxvr_GetApiVersion"))
    result.runtime_api=reinterpret_cast<decltype(&rtxvr_GetApiVersion)>(fn)();
  const auto dll=impl_->module_folder/L"openvr_api.dll";
  if(std::filesystem::is_regular_file(dll)) result.openvr_dll=dll;
  const auto discovery=nl::vrprobe::discover_steamvr();
  result.steamvr_installed=discovery.find("installed")->as_bool();
  result.steamvr_running=discovery.find("vrserver")->as_bool();
  return result;
}
bool Session::start(const Options& options,std::string& error) {
  auto& s=*impl_;std::unique_lock life(s.lifecycle,std::try_to_lock);
  if(!life) { error="nlvr lifecycle is busy; try Start again";return false; }
  { std::lock_guard lock(s.status_mutex);
    if((s.phase!="off"&&s.phase!="failed")||!s.worker_finished.load(std::memory_order_acquire)) {
      error="nlvr is already "+s.phase+"; wait for cleanup before starting again";return false;
    }
  }
  if(!std::isfinite(options.scale)||options.scale<1||options.scale>1000||!std::isfinite(options.render_scale)||options.render_scale<0.1f||options.render_scale>2) {
    error="invalid scale (1-1000) or render_scale (0.1-2)";return false;
  }
  if(options.simulate) try {
    (void)simulation_root(s.module_folder);
    need(!options.timeline.empty(),"simulated VR requires a timeline");
  } catch(const std::exception& e) { error=e.what();return false; }
  if(s.worker.joinable()) s.worker.join(); // Finished only: never joins a pending VR_Init or teardown.
  s.options=options;s.quit=false;s.cancelled=false;s.worker_finished=false;
  s.status("starting",options.simulate?"initialising simulated VR and RTX output; Exit VR can cancel this request":
    "initialising OpenVR and RTX VR output; Exit VR can cancel this request");
  try { s.worker=std::thread([&s] { s.run(); }); }
  catch(const std::exception& e) { s.worker_finished=true;s.status("failed",e.what());error=e.what();return false; }
  return true;
}
void Session::stop() {
  auto& s=*impl_;std::unique_lock life(s.lifecycle,std::try_to_lock);
  need(life.owns_lock(),"nlvr lifecycle is busy; try Stop again");
  { std::lock_guard lock(s.status_mutex);
    if(s.worker_finished.load(std::memory_order_acquire)) { s.phase="off";s.detail.clear();return; }
    s.request_cancel();s.phase="stopping";
    s.detail="Waiting for OpenVR initialisation or RTX teardown to finish; the game can continue";
  }
  // The worker alone owns teardown and releases the DLLs.
}
std::pair<std::string,std::string> Session::state() const {
  auto& s=*impl_;std::pair<std::string,std::string> out;
  { std::lock_guard lock(s.status_mutex);out={s.phase,s.detail}; }
  if(out.first=="running") {
    std::unique_lock lock(s.api_mutex,std::try_to_lock);
    if(lock&&s.ready&&!s.cancelled) {
      rtxvr_Status status{};
      if(!s.renderer_ready(status)) {
        std::lock_guard state_lock(s.status_mutex);
        if(s.phase=="failed"||s.phase=="stopping") return {s.phase,s.detail};
        return {"starting","Waiting for SDK readiness"};
      }
      if(status.state==RTXVR_STATE_STARTING) out.second="OpenVR is ready; waiting for the first traced scene";
    } else {
      std::lock_guard state_lock(s.status_mutex);
      if(s.phase!="running") return {s.phase,s.detail};
      return {"starting","VR session is busy; waiting for status"};
    }
  }
  return out;
}
std::optional<Frame> Session::begin_frame() {
  auto& s=*impl_;std::unique_lock lock(s.api_mutex,std::try_to_lock);if(!lock||!s.ready||s.cancelled) return {};
  rtxvr_Status renderer{};
  if(!s.renderer_ready(renderer,true)) return {};
  Frame frame;frame.completion_wait_ms=s.facts.completion_wait_ms;std::array<::vr::TrackedDevicePose_t,::vr::k_unMaxTrackedDeviceCount> raw{};
  const auto before=Clock::now();
  if(s.options.simulate) {
    const auto now=Clock::now();
    if(now<s.next_sim_frame) {
      LARGE_INTEGER due{};
      due.QuadPart=-std::max<LONGLONG>(1,std::chrono::duration_cast<std::chrono::nanoseconds>(s.next_sim_frame-now).count()/100);
      need(SetWaitableTimer(s.sim_timer,&due,0,nullptr,nullptr,FALSE)!=0,"simulated frame timer could not be armed");
      need(WaitForSingleObject(s.sim_timer,1000)==WAIT_OBJECT_0,"simulated frame timer timed out");
    }
    if(s.cancelled) return {};
    const auto period=std::chrono::duration_cast<Clock::duration>(std::chrono::duration<double>(1/s.facts.refresh));
    s.next_sim_frame+=period;
    if(s.next_sim_frame<Clock::now()) s.next_sim_frame=Clock::now()+period;
    frame.base_seconds=1/s.facts.refresh;frame.sample_seconds=pose_clock();frame.predicted_seconds=0;
  } else {
    if(s.eyes_dirty.exchange(false,std::memory_order_acq_rel)) {
      s.read_eyes();runtime_check(s.rt_eyes(s.eyes),"rtxvr_UpdateEyes");
    }
    float since=0;uint64_t vsync=0;
    const float photons=s.system->GetFloatTrackedDeviceProperty(0,::vr::Prop_SecondsFromVsyncToPhotons_Float);
    s.system->GetTimeSinceLastVsync(&since,&vsync);
    frame.base_seconds=std::max(0.f,1/s.facts.refresh-since)+photons;
    frame.sample_seconds=pose_clock();
    frame.predicted_seconds=frame.base_seconds+(renderer.timingSamples?
      std::clamp(std::round(renderer.pipelineIntervals),0.0,8.0)/s.facts.refresh:0);
    s.system->GetDeviceToAbsoluteTrackingPose(::vr::TrackingUniverseStanding,float(frame.predicted_seconds),raw.data(),uint32_t(raw.size()));
  }
  s.facts.prediction_seconds=frame.predicted_seconds;
  frame.wait_ms=std::chrono::duration<double,std::milli>(Clock::now()-before).count();
  rtxvr_Status after{};after.structSize=sizeof after;
  runtime_check(s.rt_status(&after),"rtxvr_GetStatus(after WaitGetPoses)");
  frame.sequence=++s.sequence;frame.ipd=s.facts.ipd;
  for(std::size_t i=0;i<raw.size();++i) frame.devices[i]=pose(raw[i]);
  const auto left=s.options.simulate?1:s.system->GetTrackedDeviceIndexForControllerRole(::vr::TrackedControllerRole_LeftHand);
  const auto right=s.options.simulate?2:s.system->GetTrackedDeviceIndexForControllerRole(::vr::TrackedControllerRole_RightHand);
  frame.poses={frame.devices[::vr::k_unTrackedDeviceIndex_Hmd],left<raw.size()?frame.devices[left]:Pose{},right<raw.size()?frame.devices[right]:Pose{}};
  if(s.timeline) {
    s.script=s.timeline->sample(std::chrono::duration<double>(Clock::now()-s.epoch).count()+frame.predicted_seconds);frame.poses=s.script->poses;
    frame.devices[0]=frame.poses[0];if(left<raw.size()) frame.devices[left]=frame.poses[1];if(right<raw.size()) frame.devices[right]=frame.poses[2];
  }
  s.facts.left_tracked=frame.poses[1].valid;s.facts.right_tracked=frame.poses[2].valid;
  frame.seconds_to_photons=float(frame.predicted_seconds);
  const auto head=s.script?to_openvr(source_matrix(frame.poses[0].pos,rotation(frame.poses[0].ang))):matrix(raw[0].mDeviceToAbsoluteTracking);
  s.poses.push_back({frame.sequence,head,s.script.has_value()||!frame.poses[0].valid,frame.sample_seconds,frame.sample_seconds+frame.predicted_seconds,frame.base_seconds});if(s.poses.size()>16) s.poses.pop_front();
  // Side-channel errors must not discard a pose already acquired for this frame.
  s.facts.frame_error.clear();
  try { s.read_actions(); } catch(const std::exception& e) { s.facts.input_detail=e.what(); }
  for(unsigned i=0;i<2;++i) frame.controllers[i]=s.options.simulate?s.simulated_controllers[i]:
    s.controller_frames.read(i,i==0?left:right,s.system,s.render_models,s.input,s.hands[i],s.handles.at(i==0?"left_skeleton":"right_skeleton"));
  // A sleeping hand can appear later, and scripted transforms change every frame.
  for(auto& [handle,item]:s.overlays) try { s.place(handle,item); } catch(const std::exception& e) { s.facts.frame_error=e.what(); }
  return frame;
}
void Session::set_camera(uint64_t seq,Vec3 origin,Vec3 ang) {
  need(finite(origin)&&finite(ang),"nonfinite camera");auto& s=*impl_;auto lock=s.access();
  const auto it=std::find_if(s.poses.begin(),s.poses.end(),[&](const auto& p) { return p.sequence==seq; });
  need(it!=s.poses.end(),"camera sequence is outside the last 16 BeginFrame poses");
  rtxvr_FramePose p{};p.structSize=sizeof p;p.flags=it->scripted?RTXVR_POSE_SCRIPTED:0;p.sequence=seq;p.hmdToTracking=it->head;
  p.cameraOrigin[0]=origin.x;p.cameraOrigin[1]=origin.y;p.cameraOrigin[2]=origin.z;
  p.cameraAngles[0]=ang.x;p.cameraAngles[1]=ang.y;p.cameraAngles[2]=ang.z;
  p.sampleTimeSeconds=it->sampled;p.predictedDisplayTimeSeconds=it->target;p.baseSecondsToPhotons=it->base;
  runtime_check(s.rt_pose(&p),"rtxvr_PushFramePose");

}
Info Session::info() const {
  auto& s=*impl_;std::unique_lock lock(s.api_mutex,std::try_to_lock);if(!lock||!s.ready||s.cancelled) return {};
  rtxvr_Status renderer{};s.renderer_ready(renderer);if(s.cancelled) return {};
  auto out=s.facts;out.sdk_ready=!s.options.simulate;out.runtime=renderer;
  out.window_input=s.window_input.info();
  std::copy(std::begin(s.eyes),std::end(s.eyes),out.eyes.begin());
  out.openvr_loaded=GetModuleHandleW(L"openvr_api.dll")!=nullptr;
  { std::lock_guard keyboard_lock(s.event_mutex);out.keyboard_visible=s.keyboard_owned;out.keyboard_text=s.keyboard_text; }
  if(s.options.simulate) return out;
  out.runtime.lastErrorText[sizeof(out.runtime.lastErrorText)-1]=0;
  out.timing.m_nSize=sizeof out.timing;out.timing_valid=s.compositor->GetFrameTiming(&out.timing,0);
  s.compositor->GetCumulativeStats(&out.cumulative,sizeof out.cumulative);
  out.activity=s.system->GetTrackedDeviceActivityLevel(0);return out;
}
Actions Session::actions() const {
  auto& s=*impl_;std::unique_lock lock(s.api_mutex,std::try_to_lock);
  return lock&&s.ready&&!s.cancelled?s.action_values:Actions{};
}
SkeletonSample Session::skeleton(const std::string& hand,const std::string& reference) {
  need(hand=="left"||hand=="right","invalid skeletal hand");
  auto& s=*impl_;auto lock=s.access();
  return read_skeleton(s.options.simulate?nullptr:s.input,s.options.simulate?0:s.handles.at(hand+"_skeleton"),reference);
}
int Session::haptic(const std::string& hand,float seconds,float frequency,float amplitude) {
  need((hand=="left"||hand=="right")&&std::isfinite(seconds)&&seconds>=0&&seconds<=5&&std::isfinite(frequency)&&frequency>=0&&frequency<=1000&&std::isfinite(amplitude)&&amplitude>=0&&amplitude<=1,"invalid haptic arguments");
  auto& s=*impl_;auto lock=s.access();
  ++s.facts.haptic_requests;if(s.options.simulate) return 0;
  return s.input->TriggerHapticVibrationAction(s.handles.at(hand+"_haptic"),0,seconds,frequency,amplitude,s.hands[hand=="left"?0:1]);
}
void Session::window_input(const WindowInputEvent& event) {
  auto& s=*impl_;
  try { auto lock=s.access();s.window_input.dispatch(event,s.sequence); }
  catch(...) { cancel_window_input();throw; }
}
void Session::cancel_window_input() noexcept {
  auto& s=*impl_;std::unique_lock lock(s.api_mutex,std::try_to_lock);
  if(lock) s.window_input.release(); // Otherwise the starting/stopping worker owns cleanup.
}
void Session::show_keyboard(const std::string& text,const std::string& description,bool multiline,uint32_t maxchars) {
  keyboard_string(text,16384);keyboard_string(description,512);need(maxchars>=1&&maxchars<=4096,"keyboard maxchars must be 1..4096");
  auto& s=*impl_;auto lock=s.access();std::lock_guard keyboard_lock(s.event_mutex);
  if(!s.options.simulate) s.overlay_check(s.overlay->ShowKeyboard(::vr::k_EGamepadTextInputModeNormal,
    multiline?::vr::k_EGamepadTextInputLineModeMultipleLines: ::vr::k_EGamepadTextInputLineModeSingleLine,
    ::vr::KeyboardFlag_Modal,description.c_str(),maxchars,text.c_str(),Impl::keyboard_token));
  s.keyboard_owned=true;s.keyboard_done=false;s.keyboard_text=text;s.keyboard_limit=maxchars;
}
void Session::hide_keyboard() {
  auto& s=*impl_;auto lock=s.access();bool emit=false;
  { std::lock_guard keyboard_lock(s.event_mutex);
    if(s.keyboard_owned) {
      if(s.options.simulate) { s.keyboard_owned=false;emit=true; }
      else s.overlay->HideKeyboard();
    }
  }
  if(emit) s.queue_event({"keyboard_closed",::vr::VREvent_KeyboardClosed,0,{}});
}
int Session::open_binding_ui() {
  auto& s=*impl_;auto lock=s.access();++s.facts.binding_ui_requests;
  if(s.options.simulate) return 0;
  // OpenBindingUI requires a device source, not k_ulInvalidInputValueHandle. Prefer a controller;
  // a sleeping pair has no connected device, but the HMD opens the application's desktop editor.
  for(const auto hand:s.hands) {
    const auto result=s.input->OpenBindingUI(nullptr,s.action_set,hand,true);
    if(result!=::vr::VRInputError_InvalidDevice) return result;
  }
  ::vr::VRInputValueHandle_t head=0;
  const auto result=s.input->GetInputSourceHandle("/user/head",&head);
  if(result!=::vr::VRInputError_None) return result;
  return s.input->OpenBindingUI(nullptr,s.action_set,head,true);
}
uint64_t Session::overlay_create(const std::string& key,const std::string& name) {
  need(!key.empty()&&key.size()<=128&&!name.empty()&&name.size()<=128,"invalid overlay key/name");
  auto& s=*impl_;auto lock=s.access();need(s.overlays.size()<32,"nlvr overlay limit (32)");
  ::vr::VROverlayHandle_t handle=0;
  if(s.options.simulate) { need(s.next_sim_overlay!=0,"simulated overlay handle limit");handle=s.next_sim_overlay++; }
  else s.overlay_check(s.overlay->CreateOverlay(key.c_str(),name.c_str(),&handle));
  s.overlays.emplace(handle,Impl::Overlay{});return handle;
}
void Session::overlay_source(uint64_t handle,uint32_t w,uint32_t h) {
  need((w==0&&h==0)||(w>=1&&w<=8192&&h>=1&&h<=8192),"invalid overlay size (maximum 8192)");
  auto& s=*impl_;auto lock=s.access();auto& item=s.owned(handle);runtime_check(s.rt_overlay(handle,w,h),"rtxvr_SetOverlaySource");
  item.texture_width=w;item.texture_height=h;
}
void Session::overlay_attach(uint64_t handle,const std::string& device,Vec3 pos,Vec3 ang,float width) {
  need((device=="world"||device=="head"||device=="left"||device=="right")&&finite(pos)&&finite(ang)&&std::isfinite(width)&&width>0&&width<=100,"invalid overlay transform");
  auto& s=*impl_;auto lock=s.access();auto& item=s.owned(handle);
  item.device=device;item.local=source_matrix(pos,rotation(ang));item.width=width;item.placed=false;
  if(!s.options.simulate) s.overlay_check(s.overlay->SetOverlayWidthInMeters(handle,width));s.place(handle,item);
}
void Session::overlay_show(uint64_t handle,bool shown) {
  auto& s=*impl_;auto lock=s.access();auto& item=s.owned(handle);item.wanted=shown;s.place(handle,item);
}
void Session::overlay_alpha(uint64_t handle,float alpha) {
  need(std::isfinite(alpha)&&alpha>=0&&alpha<=1,"invalid overlay alpha");
  auto& s=*impl_;auto lock=s.access();auto& item=s.owned(handle);
  if(!s.options.simulate) s.overlay_check(s.overlay->SetOverlayAlpha(handle,alpha));item.alpha=alpha;
}
void Session::overlay_sort_order(uint64_t handle,uint32_t order) {
  auto& s=*impl_;auto lock=s.access();auto& item=s.owned(handle);
  if(!s.options.simulate) s.overlay_check(s.overlay->SetOverlaySortOrder(handle,order));item.sort=order;
}
void Session::overlay_color(uint64_t handle,Vec3 color) {
  need(finite(color)&&color.x>=0&&color.x<=1&&color.y>=0&&color.y<=1&&color.z>=0&&color.z<=1,"overlay color must be in 0..1");
  auto& s=*impl_;auto lock=s.access();auto& item=s.owned(handle);
  if(!s.options.simulate) s.overlay_check(s.overlay->SetOverlayColor(handle,color.x,color.y,color.z));item.color=color;
}
bool Session::overlay_window(uint64_t handle,bool enable,std::string& error) {
  auto& s=*impl_;auto lock=s.access();auto& item=s.owned(handle);
  if(!s.rt_window) { error="RTX runtime lacks rtxvr_SetOverlayWindow; update the VR runtime for window overlays";return false; }
  const auto result=s.rt_window(handle,enable?RTXVR_WINDOW_SHOW|RTXVR_WINDOW_NO_MIRROR:0u);
  if(result!=RTXVR_OK) { error="rtxvr_SetOverlayWindow: RTXVR error "+std::to_string(result);return false; }
  item.window=enable;return true;
}
void Session::overlay_destroy(uint64_t handle) {
  auto& s=*impl_;auto lock=s.access();s.owned(handle);
  if(s.overlays.at(handle).window&&s.rt_window) runtime_check(s.rt_window(handle,0),"rtxvr_SetOverlayWindow(remove)");
  runtime_check(s.rt_overlay(handle,0,0),"rtxvr_SetOverlaySource(remove)");
  if(!s.options.simulate) s.overlay_check(s.overlay->DestroyOverlay(handle));s.overlays.erase(handle);
}
bool Session::overlay_visible(uint64_t handle) const {
  auto& s=*impl_;auto lock=s.access();const auto& item=s.owned(handle);
  return s.options.simulate?item.wanted&&item.placed:s.overlay->IsOverlayVisible(handle);
}
OverlayInfo Session::overlay_info(uint64_t handle) const {
  auto& s=*impl_;auto lock=s.access();const auto& item=s.owned(handle);OverlayInfo result;
  result.alpha=item.alpha;result.color=item.color;result.sort_order=item.sort;result.window=item.window;result.simulated=s.options.simulate;
  if(s.options.simulate) {
    result.visible=item.wanted&&item.placed;result.width=item.width;result.texture_width=item.texture_width;result.texture_height=item.texture_height;
    result.origin=::vr::TrackingUniverseStanding;result.transform=item.absolute;return result;
  }
  result.visible=s.overlay->IsOverlayVisible(handle);
  s.overlay_check(s.overlay->GetOverlayWidthInMeters(handle,&result.width));
  ::vr::ETrackingUniverseOrigin origin{};::vr::HmdMatrix34_t transform{};
  result.transform_error=s.overlay->GetOverlayTransformAbsolute(handle,&origin,&transform);
  result.origin=origin;result.transform=matrix(transform);
  result.texture_error=s.overlay->GetOverlayTextureSize(handle,&result.texture_width,&result.texture_height);
  return result;
}
std::vector<Event> Session::events() {
  auto& s=*impl_;std::unique_lock lock(s.api_mutex,std::try_to_lock);
  if(!lock||!s.ready||s.cancelled) return {};
  std::lock_guard events_lock(s.event_mutex);
  std::vector<Event> result(s.pending_events.begin(),s.pending_events.end());s.pending_events.clear();return result;
}
void Session::capture(const std::filesystem::path& folder,uint32_t what) {
  need(folder.is_absolute()&&what>0&&(what&~15u)==0,"invalid capture folder/flags");
  auto& s=*impl_;auto lock=s.access();runtime_check(s.rt_capture(folder.c_str(),what),"rtxvr_Capture");
}
std::optional<ScriptSample> Session::test_state() const {
  auto& s=*impl_;std::unique_lock lock(s.api_mutex,std::try_to_lock);
  return lock&&s.ready&&!s.cancelled?s.script:std::nullopt;
}
}
