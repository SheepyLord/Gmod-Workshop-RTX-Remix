// SPDX-License-Identifier: MIT
#include "session.h"
#include "lua_policy.h"
#include "nl/fs.h"
#include <GarrysMod/Lua/Interface.h>
#include <windows.h>
#include <limits>

namespace {
using GarrysMod::Lua::ILuaBase;
namespace Type=GarrysMod::Lua::Type;
using namespace nl::vr;
std::unique_ptr<Session> session;
ILuaBase* owner=nullptr;
void need(bool b,const char* text) { if(!b) throw std::runtime_error(text); }
int absolute(ILuaBase* l,int i) { return i>0?i:l->Top()+i+1; }
void set(ILuaBase* l,const char* name) { l->SetField(-2,name); }
void num(ILuaBase* l,const char* name,double value) { l->PushNumber(value);set(l,name); }
void text(ILuaBase* l,const char* name,const std::string& value) { l->PushString(value.c_str());set(l,name); }
void boolean(ILuaBase* l,const char* name,bool value) { l->PushBool(value);set(l,name); }
void index(ILuaBase* l,unsigned i) { l->PushNumber(i);l->Insert(-2);l->RawSet(-3); }
double number(ILuaBase* l,int i,double low,double high) {
  need(l->IsType(i,Type::Number),"expected number");const double v=l->GetNumber(i);
  need(std::isfinite(v)&&v>=low&&v<=high,"number outside allowed range");return v;
}
uint64_t integer(ILuaBase* l,int i,double low,double high) {
  const double v=number(l,i,low,high);need(std::floor(v)==v,"expected integer");return static_cast<uint64_t>(v);
}
std::string string(ILuaBase* l,int i,bool empty=false) {
  need(l->IsType(i,Type::String),"expected string");unsigned size=0;const char* data=l->GetString(i,&size);
  need(data&&(empty||size>0)&&size<=32767&&std::char_traits<char>::length(data)==size,"invalid string");return {data,size};
}
Vec3 vector(ILuaBase* l,int i,bool angle=false) {
  need(l->IsType(i,angle?Type::Angle:Type::Vector),angle?"expected Angle":"expected Vector");
  const auto v=angle?l->GetAngle(i):l->GetVector(i);Vec3 result{v.x,v.y,v.z};need(finite(result),"nonfinite vector/angle");return result;
}
template<class F> int guard(ILuaBase* l,F&& fn,bool start=false) noexcept {
  const auto top=l->Top();
  try { need(l==owner&&session!=nullptr,"nlvr belongs to its client realm");return fn(); }
  catch(const std::exception& e) {
    if(l->Top()>top) l->Pop(l->Top()-top);
    if(start) l->PushBool(false);else l->PushNil();l->PushString(e.what());return 2;
  } catch(...) {
    if(l->Top()>top) l->Pop(l->Top()-top);
    if(start) l->PushBool(false);else l->PushNil();l->PushString("nlvr internal failure");return 2;
  }
}
int ok(ILuaBase* l) { l->PushBool(true);return 1; }
void push_vec(ILuaBase* l,Vec3 v,bool angle=false) {
  Vector out;out.x=v.x;out.y=v.y;out.z=v.z;if(angle) l->PushAngle(out);else l->PushVector(out);
}
void push_pose(ILuaBase* l,const Pose& p) {
  l->CreateTable();boolean(l,"valid",p.valid);push_vec(l,p.pos);set(l,"pos");push_vec(l,p.ang,true);set(l,"ang");
  push_vec(l,p.vel);set(l,"vel");push_vec(l,p.angvel);set(l,"angvel");
}
void push_controller(ILuaBase* l,const ControllerFrames& f) {
  l->CreateTable();boolean(l,"valid",f.valid);boolean(l,"skeleton",f.skeleton);
  text(l,"model",f.model);text(l,"source",f.source);text(l,"detail",f.detail);
  num(l,"device",f.device);num(l,"revision",f.revision);
  push_pose(l,f.aim);set(l,"aim");push_pose(l,f.hand);set(l,"hand");push_pose(l,f.wrist);set(l,"wrist");
  push_vec(l,f.skeleton_finger);set(l,"skeleton_finger");push_vec(l,f.skeleton_normal);set(l,"skeleton_normal");
}
// Lua numbers cannot represent all uint64 overlay handles. Always return decimal strings.
// Accept exact small numbers as well, for callers with a legacy/synthetic handle.
uint64_t handle(ILuaBase* l,int i=1) {
  if(l->IsType(i,Type::String)) {
    const auto s=string(l,i);need(s.size()<=20&&s.find_first_not_of("0123456789")==std::string::npos,"invalid overlay handle");
    std::size_t end=0;const auto n=std::stoull(s,&end);need(n!=0&&end==s.size(),"invalid overlay handle");return n;
  }
  return integer(l,i,1,9007199254740991.0);
}
LUA_FUNCTION_STATIC(Version) { LUA->PushNumber(1);return 1; }
LUA_FUNCTION_STATIC(LuaProbe) { return guard(LUA,[&] {
  const auto p=session->probe();LUA->CreateTable();
  if(p.runtime_api) num(LUA,"runtime_api",*p.runtime_api);
  boolean(LUA,"openvr_dll",!p.openvr_dll.empty());
  boolean(LUA,"steamvr_installed",p.steamvr_installed);boolean(LUA,"steamvr_running",p.steamvr_running);return 1;
}); }
LUA_FUNCTION_STATIC(Start) { return guard(LUA,[&] {
  Options options;
  if(LUA->Top()>0&&!LUA->IsType(1,Type::Nil)) {
    need(LUA->IsType(1,Type::Table),"expected Start options table");
    const auto scalar=[&](const char* key,float& out,double low,double high) {
      LUA->GetField(1,key);if(!LUA->IsType(-1,Type::Nil)) out=static_cast<float>(number(LUA,-1,low,high));LUA->Pop();
    };
    scalar("scale",options.scale,1,1000);scalar("render_scale",options.render_scale,.1,2);
    for(const char* key:{"openvr_dll","manifest","runtime_dll"}) {
      LUA->GetField(1,key);const bool supplied=!LUA->IsType(-1,Type::Nil);LUA->Pop();if(supplied) reject_lua_path_key(key);
    }
    LUA->GetField(1,"timeline");if(!LUA->IsType(-1,Type::Nil)) options.timeline=session->data_path(string(LUA,-1),false);LUA->Pop();
    LUA->GetField(1,"pacing");if(!LUA->IsType(-1,Type::Nil)) { const auto mode=string(LUA,-1);need(mode=="render","V1 uses render-side pacing only"); }LUA->Pop();
    LUA->GetField(1,"no_submit");
    if(!LUA->IsType(-1,Type::Nil)) { need(LUA->IsType(-1,Type::Bool),"no_submit must be boolean");options.no_submit=LUA->GetBool(-1); }
    LUA->Pop();
    LUA->GetField(1,"simulate");
    if(!LUA->IsType(-1,Type::Nil)) { need(LUA->IsType(-1,Type::Bool),"simulate must be boolean");options.simulate=LUA->GetBool(-1); }
    LUA->Pop();
  }
  std::string error;const bool result=session->start(options,error);LUA->PushBool(result);
  if(!result) { LUA->PushString(error.c_str());return 2; }return 1;
},true); }
LUA_FUNCTION_STATIC(State) { return guard(LUA,[&] {
  const auto [state,detail]=session->state();LUA->PushString(state.c_str());LUA->PushString(detail.c_str());return 2;
}); }
LUA_FUNCTION_STATIC(Stop) { return guard(LUA,[&] { session->stop();return ok(LUA); }); }
LUA_FUNCTION_STATIC(BeginFrame) { return guard(LUA,[&] {
  const auto f=session->begin_frame();if(!f) { LUA->PushNil();return 1; }
  LUA->CreateTable();num(LUA,"sequence",static_cast<double>(f->sequence));num(LUA,"ipd",f->ipd);num(LUA,"seconds_to_photons",f->seconds_to_photons);
  num(LUA,"sample_seconds",f->sample_seconds);num(LUA,"prediction_seconds",f->predicted_seconds);
  num(LUA,"wait_ms",f->wait_ms);
  num(LUA,"completion_wait_ms",f->completion_wait_ms);
  push_pose(LUA,f->poses[0]);set(LUA,"hmd");push_pose(LUA,f->poses[1]);set(LUA,"left");push_pose(LUA,f->poses[2]);set(LUA,"right");
  LUA->CreateTable();push_controller(LUA,f->controllers[0]);set(LUA,"left");push_controller(LUA,f->controllers[1]);set(LUA,"right");set(LUA,"controllers");
  LUA->CreateTable();
  for(unsigned i=0;i<f->devices.size();++i) if(f->devices[i].valid) { push_pose(LUA,f->devices[i]);index(LUA,i+1); }
  set(LUA,"devices");return 1;
}); }
LUA_FUNCTION_STATIC(SetFrameCamera) { return guard(LUA,[&] {
  const auto seq=integer(LUA,1,1,9007199254740991.0);const auto pos=vector(LUA,2),ang=vector(LUA,3,true);
  session->set_camera(seq,pos,ang);return ok(LUA);
}); }
void push_status(ILuaBase* l,const rtxvr_Status& s) {
#define N(field) num(l,#field,static_cast<double>(s.field))
  N(state);N(lastError);text(l,"lastErrorText",s.lastErrorText);
  N(centreWidth);N(centreHeight);N(renderWidth);N(renderHeight);N(eyeWidth);N(eyeHeight);
  N(framesRendered);N(framesSubmitted);N(submitErrors);N(lastSubmitError);N(posesMatched);N(posesUnmatched);
  N(timingSamples);N(renderWaitCalls);N(poseAgeMs);N(predictionErrorMs);N(pipelineIntervals);N(renderWaitMs);N(renderWaitMaxMs);N(lastPoseSequence);
  N(focusLossIntervals);N(waitFailures);
  N(gpuMsTotal);N(gpuMsPathTrace);N(gpuMsUpscale);N(gpuMsWarp);N(gpuMsOther);N(cpuMsSubmit);N(overlaysBound);N(overlayUpdates);
#undef N
}
LUA_FUNCTION_STATIC(LuaInfo) { return guard(LUA,[&] {
  const auto i=session->info();LUA->CreateTable();boolean(LUA,"sdk_ready",i.sdk_ready);text(LUA,"model",i.model);text(LUA,"tracking",i.tracking);
  boolean(LUA,"simulated",i.simulated);boolean(LUA,"simulation_high_resolution",i.simulation_high_resolution);
  boolean(LUA,"openvr_loaded",i.openvr_loaded);
  boolean(LUA,"keyboard_visible",i.keyboard_visible);text(LUA,"keyboard_text",i.keyboard_text);
  boolean(LUA,"overlay_window_supported",i.overlay_window_supported);
  LUA->CreateTable();boolean(LUA,"owned",i.window_input.owned);boolean(LUA,"foreground",i.window_input.foreground);
  num(LUA,"width",i.window_input.width);num(LUA,"height",i.window_input.height);
  num(LUA,"x",i.window_input.x);num(LUA,"y",i.window_input.y);num(LUA,"held",i.window_input.held);
  num(LUA,"frame_messages",i.window_input.frame_messages);num(LUA,"posted",static_cast<double>(i.window_input.posted));
  num(LUA,"failures",static_cast<double>(i.window_input.failures));set(LUA,"window_input");
  num(LUA,"haptic_requests",static_cast<double>(i.haptic_requests));num(LUA,"binding_ui_requests",static_cast<double>(i.binding_ui_requests));
  LUA->CreateTable();unsigned eye_index=0;
  for(const auto& eye:i.eyes) {
    LUA->CreateTable();num(LUA,"tanLeft",eye.tanLeft);num(LUA,"tanRight",eye.tanRight);num(LUA,"tanTop",eye.tanTop);num(LUA,"tanBottom",eye.tanBottom);
    LUA->CreateTable();unsigned row_index=0;
    for(const auto& row:eye.eyeToHead.m) { LUA->CreateTable();unsigned column=0;for(float value:row) { LUA->PushNumber(value);index(LUA,++column); }index(LUA,++row_index); }
    set(LUA,"eyeToHead");index(LUA,++eye_index);
  }
  set(LUA,"eyes");
  text(LUA,"input_detail",i.input_detail);text(LUA,"frame_error",i.frame_error);num(LUA,"refresh",i.refresh);num(LUA,"ipd",i.ipd);
  num(LUA,"eye_width",i.eye_width);num(LUA,"eye_height",i.eye_height);num(LUA,"activity",i.activity);push_status(LUA,i.runtime);
  num(LUA,"prediction_seconds",i.prediction_seconds);
  num(LUA,"completion_wait_ms",i.completion_wait_ms);num(LUA,"completion_wait_max_ms",i.completion_wait_max_ms);
  num(LUA,"completion_wait_timeouts",static_cast<double>(i.completion_wait_timeouts));
  num(LUA,"completion_wait_count",static_cast<double>(i.completion_wait_count));
  num(LUA,"completion_wait_polls",i.completion_wait_polls);
  boolean(LUA,"completion_wait_high_resolution",i.completion_wait_high_resolution);
  LUA->CreateTable();boolean(LUA,"left",i.left_tracked);boolean(LUA,"right",i.right_tracked);set(LUA,"devices");
  num(LUA,"presents",i.cumulative.m_nNumFramePresents);num(LUA,"dropped",i.cumulative.m_nNumDroppedFrames);
  num(LUA,"reprojected",i.cumulative.m_nNumReprojectedFrames);
  if(i.timing_valid) {
    num(LUA,"compositor_gpu_ms",i.timing.m_flCompositorRenderGpuMs);num(LUA,"compositor_cpu_ms",i.timing.m_flCompositorRenderCpuMs);
  }
  LUA->CreateTable();boolean(LUA,"valid",i.timing_valid);
#define T(field) num(LUA,#field,i.timing.field)
  T(m_nFrameIndex);T(m_nNumFramePresents);T(m_nNumMisPresented);T(m_nNumDroppedFrames);T(m_nReprojectionFlags);
  T(m_flSystemTimeInSeconds);T(m_flPreSubmitGpuMs);T(m_flPostSubmitGpuMs);T(m_flTotalRenderGpuMs);
  T(m_flCompositorRenderGpuMs);T(m_flCompositorRenderCpuMs);T(m_flCompositorIdleCpuMs);T(m_flClientFrameIntervalMs);
  T(m_flPresentCallCpuMs);T(m_flWaitForPresentCpuMs);T(m_flSubmitFrameMs);T(m_flWaitGetPosesCalledMs);T(m_flNewPosesReadyMs);
  T(m_flNewFrameReadyMs);T(m_flCompositorUpdateStartMs);T(m_flCompositorUpdateEndMs);T(m_flCompositorRenderStartMs);
  T(m_nNumVSyncsReadyForUse);T(m_nNumVSyncsToFirstView);T(m_flTransferLatencyMs);
#undef T
  set(LUA,"timing");
  LUA->CreateTable();
#define C(field) num(LUA,#field,i.cumulative.field)
  C(m_nPid);C(m_nNumFramePresents);C(m_nNumDroppedFrames);C(m_nNumReprojectedFrames);
  C(m_nNumFramePresentsOnStartup);C(m_nNumDroppedFramesOnStartup);C(m_nNumReprojectedFramesOnStartup);
  C(m_nNumLoading);C(m_nNumFramePresentsLoading);C(m_nNumDroppedFramesLoading);C(m_nNumReprojectedFramesLoading);
  C(m_nNumTimedOut);C(m_nNumFramePresentsTimedOut);C(m_nNumDroppedFramesTimedOut);C(m_nNumReprojectedFramesTimedOut);
  C(m_nNumFrameSubmits);C(m_flSumCompositorCPUTimeMS);C(m_flSumCompositorGPUTimeMS);C(m_flSumTargetFrameTimes);
  C(m_flSumApplicationCPUTimeMS);C(m_flSumApplicationGPUTimeMS);C(m_nNumFramesWithDepth);
#undef C
  set(LUA,"cumulative");return 1;
}); }
LUA_FUNCTION_STATIC(LuaActions) { return guard(LUA,[&] {
  const auto actions=session->actions();LUA->CreateTable();
  for(const auto& [name,a]:actions) {
    LUA->CreateTable();boolean(LUA,"active",a.active);boolean(LUA,"state",a.state);boolean(LUA,"changed",a.changed);
    num(LUA,"x",a.value.x);num(LUA,"y",a.value.y);num(LUA,"z",a.value.z);num(LUA,"error",a.error);
    LUA->CreateTable();for(unsigned i=0;i<a.curls.size();++i) { LUA->PushNumber(a.curls[i]);index(LUA,i+1); }
    set(LUA,"curls");
    LUA->CreateTable();for(unsigned i=0;i<a.splay.size();++i) { LUA->PushNumber(a.splay[i]);index(LUA,i+1); }
    set(LUA,"splay");set(LUA,name.c_str());
  }return 1;
}); }
LUA_FUNCTION_STATIC(Haptic) { return guard(LUA,[&] {
  const auto hand=string(LUA,1);const auto duration=static_cast<float>(number(LUA,2,0,5));
  const auto frequency=static_cast<float>(number(LUA,3,0,1000)),amplitude=static_cast<float>(number(LUA,4,0,1));
  const auto error=session->haptic(hand,duration,frequency,amplitude);LUA->PushBool(error==0);LUA->PushNumber(error);return 2;
}); }
LUA_FUNCTION_STATIC(ShowKeyboard) { return guard(LUA,[&] {
  const auto value=string(LUA,1,true),description=string(LUA,2,true);
  need(LUA->IsType(3,Type::Bool),"multiline must be boolean");const bool multiline=LUA->GetBool(3);
  const auto maximum=static_cast<uint32_t>(integer(LUA,4,1,4096));
  session->show_keyboard(value,description,multiline,maximum);return ok(LUA);
}); }
LUA_FUNCTION_STATIC(HideKeyboard) { return guard(LUA,[&] { session->hide_keyboard();return ok(LUA); }); }
LUA_FUNCTION_STATIC(LuaWindowInput) { return guard(LUA,[&] {
  try {
    WindowInputEvent e;e.kind=string(LUA,1);int arguments=1;
    if(e.kind=="cursor") { arguments=3;e.x=static_cast<int>(integer(LUA,2,0,32766));e.y=static_cast<int>(integer(LUA,3,0,32766)); }
    else if(e.kind=="button"||e.kind=="key") {
      arguments=3;e.name=string(LUA,2);need(LUA->IsType(3,Type::Bool),"WindowInput: down must be boolean");e.down=LUA->GetBool(3);
    } else if(e.kind=="wheel") {
      arguments=2;const auto steps=number(LUA,2,-8,8);need(std::floor(steps)==steps,"WindowInput: expected integer wheel steps");e.y=static_cast<int>(steps);
    } else if(e.kind=="char") { arguments=2;e.character=static_cast<uint32_t>(integer(LUA,2,0,0x10ffff)); }
    need(LUA->Top()==arguments,"WindowInput: unexpected arguments");session->window_input(e);return ok(LUA);
  } catch(...) { session->cancel_window_input();throw; }
}); }
LUA_FUNCTION_STATIC(OpenBindingUI) { return guard(LUA,[&] {
  const auto code=session->open_binding_ui();LUA->PushBool(code==0);
  if(code) { LUA->PushString(("OpenBindingUI: VRInputError "+std::to_string(code)).c_str());return 2; }return 1;
}); }
LUA_FUNCTION_STATIC(OverlaySortOrder) { return guard(LUA,[&] {
  const auto h=handle(LUA);session->overlay_sort_order(h,static_cast<uint32_t>(integer(LUA,2,0,4294967295.0)));return ok(LUA);
}); }
LUA_FUNCTION_STATIC(OverlayColor) { return guard(LUA,[&] {
  const auto h=handle(LUA);Vec3 c{static_cast<float>(number(LUA,2,0,1)),static_cast<float>(number(LUA,3,0,1)),static_cast<float>(number(LUA,4,0,1))};
  session->overlay_color(h,c);return ok(LUA);
}); }
LUA_FUNCTION_STATIC(OverlayWindow) { return guard(LUA,[&] {
  const auto h=handle(LUA);need(LUA->IsType(2,Type::Bool),"enable must be boolean");std::string error;
  const bool result=session->overlay_window(h,LUA->GetBool(2),error);LUA->PushBool(result);
  if(!result) { LUA->PushString(error.c_str());return 2; }return 1;
}); }
LUA_FUNCTION_STATIC(OverlayCreate) { return guard(LUA,[&] {
  const auto key=string(LUA,1),name=string(LUA,2);const auto h=session->overlay_create(key,name);
  LUA->PushString(std::to_string(h).c_str());return 1;
}); }
LUA_FUNCTION_STATIC(OverlaySource) { return guard(LUA,[&] {
  const auto h=handle(LUA);const auto w=static_cast<uint32_t>(integer(LUA,2,0,16384)),v=static_cast<uint32_t>(integer(LUA,3,0,16384));
  session->overlay_source(h,w,v);return ok(LUA);
}); }
LUA_FUNCTION_STATIC(OverlayAttach) { return guard(LUA,[&] {
  const auto h=handle(LUA);const auto device=string(LUA,2);const auto p=vector(LUA,3),a=vector(LUA,4,true);
  session->overlay_attach(h,device,p,a,static_cast<float>(number(LUA,5,.001,100)));return ok(LUA);
}); }
LUA_FUNCTION_STATIC(OverlayShow) { return guard(LUA,[&] {
  const auto h=handle(LUA);need(LUA->IsType(2,Type::Bool),"shown must be boolean");session->overlay_show(h,LUA->GetBool(2));return ok(LUA);
}); }
LUA_FUNCTION_STATIC(OverlayAlpha) { return guard(LUA,[&] { const auto h=handle(LUA);session->overlay_alpha(h,static_cast<float>(number(LUA,2,0,1)));return ok(LUA); }); }
LUA_FUNCTION_STATIC(OverlayDestroy) { return guard(LUA,[&] { session->overlay_destroy(handle(LUA));return ok(LUA); }); }
LUA_FUNCTION_STATIC(OverlayVisible) { return guard(LUA,[&] { LUA->PushBool(session->overlay_visible(handle(LUA)));return 1; }); }
LUA_FUNCTION_STATIC(LuaOverlayInfo) { return guard(LUA,[&] {
  const auto info=session->overlay_info(handle(LUA));LUA->CreateTable();boolean(LUA,"visible",info.visible);
  num(LUA,"width_m",info.width);num(LUA,"texture_width",info.texture_width);num(LUA,"texture_height",info.texture_height);
  num(LUA,"alpha",info.alpha);num(LUA,"sort_order",info.sort_order);boolean(LUA,"window",info.window);boolean(LUA,"simulated",info.simulated);
  LUA->CreateTable();LUA->PushNumber(info.color.x);index(LUA,1);LUA->PushNumber(info.color.y);index(LUA,2);LUA->PushNumber(info.color.z);index(LUA,3);set(LUA,"color");
  num(LUA,"texture_error",info.texture_error);num(LUA,"transform_error",info.transform_error);num(LUA,"tracking_origin",info.origin);
  LUA->CreateTable();unsigned i=0;
  for(const auto& row:info.transform.m) for(float value:row) { LUA->PushNumber(value);index(LUA,++i); }
  set(LUA,"openvr_matrix34");return 1;
}); }
LUA_FUNCTION_STATIC(Events) { return guard(LUA,[&] {
  const auto events=session->events();LUA->CreateTable();unsigned i=0;
  for(const auto& e:events) { LUA->CreateTable();text(LUA,"type",e.type);num(LUA,"code",e.code);num(LUA,"device",e.device);
    if(e.type=="keyboard_done") text(LUA,"text",e.text);index(LUA,++i); }
  return 1;
}); }
LUA_FUNCTION_STATIC(Capture) { return guard(LUA,[&] {
  const auto folder=session->data_path(string(LUA,1),true);session->capture(folder,static_cast<uint32_t>(integer(LUA,2,1,15)));return ok(LUA);
}); }
LUA_FUNCTION_STATIC(TestState) { return guard(LUA,[&] {
  const auto s=session->test_state();if(!s) { LUA->PushNil();return 1; }
  LUA->CreateTable();num(LUA,"time",s->time);num(LUA,"step",static_cast<double>(s->step));boolean(LUA,"ended",s->ended);return 1;
}); }
LUA_FUNCTION_STATIC(Skeleton) { return guard(LUA,[&] {
  const auto s=session->skeleton(string(LUA,1),string(LUA,2));
  if(LUA->Top()>=3) {
    need(LUA->IsType(3,Type::Table),"expected reusable skeleton table");LUA->Push(3);
    const int root=LUA->Top();boolean(LUA,"valid",s.valid);num(LUA,"error",s.error);text(LUA,"source",s.source);
    boolean(LUA,"compact",true);
    if(s.valid) {
      LUA->GetField(root,"bones");
      if(!LUA->IsType(-1,Type::Table)) { LUA->Pop();LUA->CreateTable();LUA->Push(-1);LUA->SetField(root,"bones"); }
      const int bones=LUA->Top();
      for(unsigned i=0;i<s.bones.size();++i) {
        LUA->PushNumber(i+1);LUA->RawGet(bones);
        if(!LUA->IsType(-1,Type::Table)) {
          LUA->Pop();LUA->CreateTable();LUA->PushNumber(i+1);LUA->Push(-2);LUA->RawSet(bones);
        }
        const int bone=LUA->Top();const auto& p=s.bones[i];
        const double values[]{p.pos.x,p.pos.y,p.pos.z,p.ang.x,p.ang.y,p.ang.z};
        for(unsigned j=0;j<6;++j) { LUA->PushNumber(j+1);LUA->PushNumber(values[j]);LUA->RawSet(bone); }
        LUA->Pop();
      }
      LUA->Pop();
    }
    return 1;
  }
  LUA->CreateTable();boolean(LUA,"valid",s.valid);num(LUA,"error",s.error);text(LUA,"source",s.source);
  LUA->CreateTable();if(s.valid) for(unsigned i=0;i<s.bones.size();++i) { push_pose(LUA,s.bones[i]);index(LUA,i+1); }
  set(LUA,"bones");return 1;
}); }
}
GMOD_MODULE_OPEN() {
  if(owner&&owner!=LUA) { LUA->PushBool(false);return 1; }
  if(!session) {
    HMODULE self=nullptr;wchar_t filename[32768]{};
    if(!GetModuleHandleExW(GET_MODULE_HANDLE_EX_FLAG_FROM_ADDRESS|GET_MODULE_HANDLE_EX_FLAG_UNCHANGED_REFCOUNT,
      reinterpret_cast<const wchar_t*>(&gmod13_open),&self)) return 0;
    const auto n=GetModuleFileNameW(self,filename,static_cast<DWORD>(std::size(filename)));if(!n||n>=std::size(filename)) return 0;
    session=std::make_unique<Session>(std::filesystem::path(filename).parent_path());owner=LUA;
  }
  LUA->CreateTable();
  const struct { const char* name; GarrysMod::Lua::CFunc fn; } functions[]={
    {"ShowKeyboard",ShowKeyboard},{"HideKeyboard",HideKeyboard},{"WindowInput",LuaWindowInput},{"OpenBindingUI",OpenBindingUI},
    {"OverlayWindow",OverlayWindow},{"OverlaySortOrder",OverlaySortOrder},{"OverlayColor",OverlayColor},
    {"Version",Version},{"Probe",LuaProbe},{"Start",Start},{"State",State},{"Stop",Stop},{"BeginFrame",BeginFrame},{"Skeleton",Skeleton},
    {"SetFrameCamera",SetFrameCamera},{"Info",LuaInfo},{"Actions",LuaActions},{"Haptic",Haptic},{"OverlayCreate",OverlayCreate},
    {"OverlaySource",OverlaySource},{"OverlayAttach",OverlayAttach},{"OverlayShow",OverlayShow},{"OverlayAlpha",OverlayAlpha},
    {"OverlayDestroy",OverlayDestroy},{"OverlayVisible",OverlayVisible},{"OverlayInfo",LuaOverlayInfo},{"Events",Events},{"Capture",Capture},{"TestState",TestState}};
  for(const auto& f:functions) { LUA->PushCFunction(f.fn);set(LUA,f.name); }
  LUA->Push(-1);LUA->SetField(GarrysMod::Lua::INDEX_GLOBAL,"nlvr");return 1;
}
GMOD_MODULE_CLOSE() { if(owner==LUA) { session.reset();owner=nullptr; }return 0; }
