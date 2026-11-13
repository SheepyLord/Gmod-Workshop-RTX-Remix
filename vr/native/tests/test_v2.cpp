// SPDX-License-Identifier: MIT
#include "session.h"
#include "sim_device.h"
#include "lua_policy.h"
#include "fake_control.h"
#include "nl_test.h"
#include <windows.h>
#include <fstream>
#include <thread>
#include <functional>
#include <cstdio>

namespace {
namespace v=nl::vr;
using Clock=std::chrono::steady_clock;
std::filesystem::path folder() {
  wchar_t file[32768]{};GetModuleFileNameW(nullptr,file,static_cast<DWORD>(std::size(file)));
  return std::filesystem::path(file).parent_path();
}
template<class T> T fn(HMODULE module,const char* name) {
  const auto p=GetProcAddress(module,name);REQUIRE(p);return reinterpret_cast<T>(p);
}
struct Fake {
  HMODULE dll;
  FakeReset reset;FakeFault fault;FakeStats stats;
  explicit Fake(const wchar_t* name):dll(LoadLibraryW((folder()/name).c_str())) {
    REQUIRE(dll);reset=fn<FakeReset>(dll,"nlvr_fake_reset");fault=fn<FakeFault>(dll,"nlvr_fake_fault");stats=fn<FakeStats>(dll,"nlvr_fake_stats");reset();
  }
  ~Fake() { FreeLibrary(dll); }
};
struct Root {
  std::wstring prior;
  bool existed=false;
  explicit Root(const std::filesystem::path& path) {
    wchar_t value[32768]{};const auto n=GetEnvironmentVariableW(L"NLVR_TEST_ROOT",value,32768);
    existed=n>0;prior=value;SetEnvironmentVariableW(L"NLVR_TEST_ROOT",path.empty()?nullptr:path.c_str());
  }
  ~Root() { SetEnvironmentVariableW(L"NLVR_TEST_ROOT",existed?prior.c_str():nullptr); }
};
v::Options live() {
  v::Options o;o.openvr_dll=folder()/L"openvr_api.dll";o.runtime_dll=folder()/L"nlvr_test_runtime.dll";
  o.manifest=NL_VR_MANIFEST;o.no_submit=true;return o;
}
void wait(const std::function<bool()>& done) {
  const auto until=Clock::now()+std::chrono::seconds(5);
  while(!done()&&Clock::now()<until) std::this_thread::sleep_for(std::chrono::milliseconds(1));
  REQUIRE(done());
}
void start(v::Session& s,const v::Options& o) {
  std::string error;REQUIRE(s.start(o,error));wait([&] { return s.state().first!="starting"; });
  if(s.state().first!="running") std::printf("V2 start failure: %s\n",s.state().second.c_str());
  REQUIRE(s.state().first=="running");
}
void stop(v::Session& s) { s.stop();wait([&] { return s.state().first=="off"; }); }
bool near_value(float a,float b) { return std::abs(a-b)<.0001f; }
const char* script=R"({"version":1,"events":[{"time":0.04,"type":"keyboard_done","text":"script text"},{"time":0.08,"type":"keyboard_closed"}],"steps":[
 {"time":0,"hmd":{"pos":[0,0,1.6],"ang":[0,0,0]},"left":{"pos":[0.2,0.3,1],"ang":[0,0,0]},"right":{"pos":[0.2,-0.3,1],"ang":[0,0,0]},"actions":{"left_grip":true,"left_grip_force":0,"right_trigger_value":0.5,"left_stick":[0,0],"left_skeleton":{"curls":[0,0,0,0,0],"splay":[0,0,0,0]}}},
 {"time":1,"hmd":{"pos":[1,0,1.6],"ang":[0,90,0]},"left":{"pos":[1.2,0.3,1],"ang":[0,0,0]},"right":{"pos":[1.2,-0.3,1],"ang":[0,0,0]},"actions":{"left_grip":false,"left_grip_force":1,"right_trigger_value":1,"left_stick":[1,-1],"left_skeleton":{"curls":[1,1,1,1,1],"splay":[1,1,1,1]}}}]})";
v::Options simulated(const std::filesystem::path& root) {
  std::filesystem::create_directories(root/L"timelines");
  std::filesystem::copy_file(NL_VR_SIM_DEVICE,root/L"simulated-index.json",std::filesystem::copy_options::overwrite_existing);
  { std::ofstream out(root/L"timelines/test.json");out<<script; }
  v::Options o;o.simulate=true;o.runtime_dll=folder()/L"nlvr_test_runtime.dll";o.timeline=root/L"timelines/test.json";return o;
}
}
TEST_CASE("V2 timeline: interpolate axes force curls splay and preserve typed keyboard events") {
  const auto t=v::Timeline::parse(script);const auto sample=t.sample(.5);
  CHECK(near_value(sample.actions.at("left_grip_force").value.x,.5f));
  CHECK(near_value(sample.actions.at("right_trigger_value").value.x,.75f));
  CHECK(near_value(sample.actions.at("left_stick").value.y,-.5f));
  for(float f:sample.actions.at("left_skeleton").curls) CHECK(near_value(f,.5f));
  for(float f:sample.actions.at("left_skeleton").splay) CHECK(near_value(f,.5f));
  CHECK(sample.actions.at("left_grip").state);CHECK(!t.sample(1).actions.at("left_grip").state);
  REQUIRE(t.events.size()==2);CHECK(t.events[0].text=="script text");CHECK(t.events[1].type=="keyboard_closed");
  std::string bad=script;bad.replace(bad.find("\"splay\":[0,0,0,0]"),19,"\"splay\":[0,0,0]");
  CHECK_THROWS_AS(v::Timeline::parse(bad),std::exception);
  bad=script;bad.replace(bad.find("keyboard_done"),13,"unsupported_x");CHECK_THROWS_AS(v::Timeline::parse(bad),std::exception);
  bad=script;bad.replace(bad.find("\"time\":0.08"),11,"\"time\":-0.1");CHECK_THROWS_AS(v::Timeline::parse(bad),std::exception);
}
TEST_CASE("V4 C: controller components and skeleton are cached until reconnect and reset on Stop") {
  Fake sdk(L"openvr_api.dll"),runtime(L"nlvr_test_runtime.dll");v::Session s(folder());start(s,live());
  auto frame=s.begin_frame();REQUIRE(frame);CHECK(frame->controllers[0].valid);CHECK(frame->controllers[1].skeleton);
  CHECK(frame->controllers[0].model=="fake_index_left");CHECK(sdk.stats().component_reads==4);CHECK(sdk.stats().skeleton_reads==2);
  for(int n=0;n<10;++n) REQUIRE(s.begin_frame());CHECK(sdk.stats().component_reads==4);CHECK(sdk.stats().controller_properties==2);
  sdk.fault(19);REQUIRE(s.begin_frame());sdk.fault(0);frame=s.begin_frame();REQUIRE(frame);
  CHECK(frame->controllers[0].valid);CHECK(sdk.stats().component_reads==6);CHECK(sdk.stats().skeleton_reads==3);
  stop(s);start(s,live());REQUIRE(s.begin_frame());CHECK(sdk.stats().component_reads==10);stop(s);
}
TEST_CASE("V4 C: missing render models components and invalid matrices fall back without failing VR") {
  for(const int fault:{16,17,18}) {
    Fake sdk(L"openvr_api.dll"),runtime(L"nlvr_test_runtime.dll");sdk.fault(fault);v::Session s(folder());start(s,live());
    const auto frame=s.begin_frame();REQUIRE(frame);CHECK(frame->poses[1].valid);CHECK(!frame->controllers[0].valid);
    CHECK(frame->controllers[0].source=="raw");CHECK(!frame->controllers[0].detail.empty());stop(s);
  }
}
TEST_CASE("V4 C review: tip-only controllers preserve aim and retry unavailable hand data") {
  Fake sdk(L"openvr_api.dll"),runtime(L"nlvr_test_runtime.dll");sdk.fault(21);v::Session s(folder());start(s,live());
  auto f=s.begin_frame();REQUIRE(f);CHECK(!f->controllers[0].valid);CHECK(f->controllers[0].aim.valid);
  CHECK(f->controllers[0].source=="tip_only");const auto reads=sdk.stats().component_reads;
  REQUIRE(s.begin_frame());CHECK(sdk.stats().component_reads==reads);
  sdk.fault(0);std::this_thread::sleep_for(std::chrono::milliseconds(160));
  f=s.begin_frame();REQUIRE(f);CHECK(f->controllers[0].valid);CHECK(sdk.stats().component_reads>reads);stop(s);
}
TEST_CASE("V4 C review3: battery events cannot resample live curled hand anchors") {
  Fake sdk(L"openvr_api.dll"),runtime(L"nlvr_test_runtime.dll");v::Session s(folder());start(s,live());
  const auto before=s.begin_frame();REQUIRE(before);const auto old=before->controllers[0];const auto reads=sdk.stats().skeleton_reads;
  sdk.fault(26);fn<FakeEvent>(sdk.dll,"nlvr_fake_event")(::vr::VREvent_PropertyChanged);
  std::this_thread::sleep_for(std::chrono::milliseconds(50));const auto after=s.begin_frame();REQUIRE(after);
  CHECK(near_value(after->controllers[0].hand.pos.x,old.hand.pos.x)&&near_value(after->controllers[0].hand.pos.y,old.hand.pos.y)&&near_value(after->controllers[0].hand.pos.z,old.hand.pos.z));
  CHECK(near_value(after->controllers[0].wrist.pos.x,old.wrist.pos.x)&&near_value(after->controllers[0].wrist.pos.y,old.wrist.pos.y)&&near_value(after->controllers[0].wrist.pos.z,old.wrist.pos.z));
  CHECK(after->controllers[0].revision==old.revision);CHECK(sdk.stats().skeleton_reads==reads);stop(s);
}
TEST_CASE("V4 C review: property changes invalidate component profiles") {
  Fake sdk(L"openvr_api.dll"),runtime(L"nlvr_test_runtime.dll");v::Session s(folder());start(s,live());
  REQUIRE(s.begin_frame());const auto reads=sdk.stats().component_reads;
  fn<FakeEvent>(sdk.dll,"nlvr_fake_event")(::vr::VREvent_PropertyChanged);
  std::this_thread::sleep_for(std::chrono::milliseconds(50));REQUIRE(s.begin_frame());
  CHECK(sdk.stats().component_reads>reads);stop(s);
}
TEST_CASE("V4 C review: a missing tip does not discard a valid wrist component") {
  Fake sdk(L"openvr_api.dll"),runtime(L"nlvr_test_runtime.dll");sdk.fault(25);v::Session s(folder());start(s,live());
  const auto f=s.begin_frame();REQUIRE(f);CHECK(!f->controllers[0].valid);CHECK(!f->controllers[0].aim.valid);
  CHECK(f->controllers[0].wrist.valid);CHECK(f->controllers[0].source=="raw");stop(s);
}
TEST_CASE("V4 C: a constrained skeleton supplies the hand when only the tip component exists") {
  Fake sdk(L"openvr_api.dll"),runtime(L"nlvr_test_runtime.dll");sdk.fault(20);v::Session s(folder());start(s,live());
  const auto frame=s.begin_frame();REQUIRE(frame);CHECK(frame->controllers[0].valid);CHECK(frame->controllers[0].skeleton);
  CHECK(std::abs(frame->controllers[0].wrist.pos.x+.13f)<.00001f);stop(s);
}
TEST_CASE("V4 C: model-space live and named skeletal references preserve all joints") {
  Fake sdk(L"openvr_api.dll"),runtime(L"nlvr_test_runtime.dll");v::Session s(folder());start(s,live());REQUIRE(s.begin_frame());
  for(const std::string kind:{"with_controller","fist","grip_limit","open"}) {
    const auto sample=s.skeleton("left",kind);REQUIRE(sample.valid);CHECK(sample.source==kind);CHECK(sample.error==0);
    CHECK(std::abs(sample.bones[1].pos.x+.13f)<.00001f);CHECK(sample.bones[30].valid);
  }
  CHECK_THROWS_AS(s.skeleton("foot","fist"),std::exception);CHECK_THROWS_AS(s.skeleton("left","other"),std::exception);
  stop(s);
}
TEST_CASE("V2 simulation: launcher boundary refuses before renderer initialization") {
  Fake runtime(L"nlvr_test_runtime.dll");Root root({});v::Session s(folder());auto o=live();o.simulate=true;std::string error;
  CHECK(!s.start(o,error));CHECK(error.find("NLVR_TEST_ROOT")!=std::string::npos);CHECK(runtime.stats().runtime_starts==0);
  CHECK(GetModuleHandleW(L"openvr_api.dll")==nullptr);CHECK(s.state().first=="off");
}
TEST_CASE("V2 simulation: timer poses actions overlays keyboard and clean restart without OpenVR") {
  REQUIRE(GetModuleHandleW(L"openvr_api.dll")==nullptr);Fake runtime(L"nlvr_test_runtime.dll");
  const auto scratch=nl::test::scratch_dir("v2-simulated");Root root(scratch);auto o=simulated(scratch);v::Session s(folder());
  for(int cycle=0;cycle<2;++cycle) {
    start(s,o);REQUIRE(GetModuleHandleW(L"openvr_api.dll")==nullptr);
    const auto info=s.info();CHECK(info.simulated&&!info.sdk_ready&&!info.openvr_loaded);CHECK(info.eye_width==2468&&info.eye_height==2740);CHECK(info.refresh==90);
    const auto received=fn<FakeStartInfo>(runtime.dll,"nlvr_fake_start_info")();
    CHECK(received.getGenericInterface==nullptr);CHECK(received.flags==RTXVR_START_NO_SUBMIT);CHECK(received.eyeWidth==2468);
    s.show_keyboard("","test",false,100);CHECK(s.info().keyboard_visible);CHECK(s.open_binding_ui()==0);CHECK(s.haptic("left",.01f,100,.5f)==0);
    const auto h=s.overlay_create("test","test");s.overlay_source(h,769,257);s.overlay_attach(h,"left",{.1f,0,0},{0,0,0},.3f);
    s.overlay_color(h,{.2f,.4f,.6f});s.overlay_alpha(h,.7f);s.overlay_sort_order(h,123);s.overlay_show(h,true);
    auto overlay=s.overlay_info(h);CHECK(overlay.simulated&&overlay.visible);CHECK(overlay.texture_width==769&&overlay.texture_height==257);
    CHECK(near_value(overlay.transform.m[0][3],-.3f)&&near_value(overlay.transform.m[1][3],1)&&near_value(overlay.transform.m[2][3],-.3f));
    CHECK(overlay.alpha==.7f&&overlay.sort_order==123&&overlay.color.y==.4f);
    std::vector<v::Event> events;const auto began=Clock::now();uint64_t frames=0;
    for(int i=0;i<36;++i) {
      const auto frame=s.begin_frame();REQUIRE(frame);CHECK(frame->poses[0].valid&&frame->poses[1].valid);++frames;
      s.set_camera(frame->sequence,frame->poses[0].pos*o.scale,frame->poses[0].ang);
      const auto next=s.events();events.insert(events.end(),next.begin(),next.end());
    }
    const auto elapsed=std::chrono::duration<double>(Clock::now()-began).count();
    CHECK(elapsed>.25&&elapsed<1.5);std::printf("V2 simulated cycle=%d frames=%llu elapsed=%.6f rate=%.3f highres=%d\n",cycle,
      static_cast<unsigned long long>(frames),elapsed,(frames-1)/elapsed,s.info().simulation_high_resolution?1:0);
    CHECK(s.actions().at("left_skeleton").curls[0]>.2f);CHECK(s.actions().at("left_skeleton").splay[0]>.2f);
    REQUIRE(events.size()==2);CHECK(events[0].type=="keyboard_done"&&events[0].text=="script text");CHECK(events[1].type=="keyboard_closed");
    CHECK(!s.info().keyboard_visible);CHECK(s.info().keyboard_text=="script text");
    CHECK(s.info().runtime.framesSubmitted==0);CHECK(s.info().runtime.framesRendered==36);
    const auto pushed=fn<FakePose>(runtime.dll,"nlvr_fake_pose")();CHECK(pushed.flags==RTXVR_POSE_SCRIPTED);
    CHECK(s.info().haptic_requests==1&&s.info().binding_ui_requests==1);
    CHECK_THROWS_AS(s.overlay_color(h,{2,0,0}),std::exception);CHECK_THROWS_AS(s.overlay_sort_order(h+1,1),std::exception);
    std::string error;CHECK(!s.overlay_window(h,true,error));CHECK(error.find("rtxvr_SetOverlayWindow")!=std::string::npos);
    s.overlay_show(h,false);CHECK(!s.overlay_visible(h));s.overlay_destroy(h);CHECK_THROWS_AS(s.overlay_info(h),std::exception);
    stop(s);CHECK(GetModuleHandleW(L"openvr_api.dll")==nullptr);
  }
  CHECK(runtime.stats().runtime_starts==2&&runtime.stats().runtime_stops==2);
}
TEST_CASE("V2 simulation: bad device and timeline fail cleanly and a scripted quit needs no Lua polling") {
  Fake runtime(L"nlvr_test_runtime.dll");const auto scratch=nl::test::scratch_dir("v2-sim-bad");Root root(scratch);
  auto o=simulated(scratch);{ std::ofstream out(scratch/L"simulated-index.json");out<<"{}"; }
  v::Session s(folder());std::string error;REQUIRE(s.start(o,error));wait([&] { return s.state().first=="failed"; });stop(s);
  o=simulated(scratch);{ std::ofstream out(o.timeline);out<<"{}"; }
  REQUIRE(s.start(o,error));wait([&] { return s.state().first=="failed"; });stop(s);
  o=simulated(scratch);std::string quit=script;quit.insert(quit.find("\"version\":"),"\"quit_at\":0.05,");
  { std::ofstream out(o.timeline);out<<quit; }start(s,o);wait([&] { return s.state().first=="off"; });
  CHECK(s.state().second.find("Simulated VR timeline")!=std::string::npos);CHECK(GetModuleHandleW(L"openvr_api.dll")==nullptr);
}
TEST_CASE("V2 combined overlays: movement ghosts gloves panels and keyboard share a bounded session budget") {
  Fake runtime(L"nlvr_test_runtime.dll");const auto scratch=nl::test::scratch_dir("v2-overlay-budget");Root root(scratch);
  auto o=simulated(scratch);v::Session s(folder());
  for(int cycle=0;cycle<2;++cycle) {
    start(s,o);std::vector<uint64_t> handles;
    for(int i=0;i<32;++i) {
      const auto h=s.overlay_create("combined."+std::to_string(i),"combined");
      handles.push_back(h);s.overlay_source(h,101+uint32_t(i)*2,103+uint32_t(i)*2);s.overlay_show(h,true);
      CHECK(s.overlay_info(h).visible);
    }
    CHECK_THROWS_AS(s.overlay_create("overflow","overflow"),std::exception);
    s.overlay_destroy(handles.back());
    const auto replacement=s.overlay_create("reused","reused");CHECK(replacement!=0);
    stop(s);CHECK(s.state().first=="off");
  }
}
TEST_CASE("V2 OpenVR: keyboard events splay binding UI tint sort and validation") {
  Fake api(L"openvr_api.dll"),runtime(L"nlvr_test_runtime.dll");v::Session s(folder());start(s,live());
  s.show_keyboard("initial","description",true,128);CHECK(api.stats().keyboard_shows==1);CHECK(s.info().keyboard_visible);
  CHECK(api.stats().keyboard_maxchars==128&&api.stats().keyboard_multiline==1&&api.stats().keyboard_flags==::vr::KeyboardFlag_Modal);
  fn<FakeKeyboardText>(api.dll,"nlvr_fake_keyboard_text")("native text");
  const auto event=fn<FakeEvent>(api.dll,"nlvr_fake_event");event(::vr::VREvent_KeyboardDone);event(::vr::VREvent_KeyboardClosed);
  std::vector<v::Event> events;wait([&] { const auto next=s.events();events.insert(events.end(),next.begin(),next.end());return events.size()==2; });
  CHECK(events[0].type=="keyboard_done"&&events[0].text=="native text");CHECK(events[1].type=="keyboard_closed");
  CHECK(!s.info().keyboard_visible);CHECK(s.open_binding_ui()==0);api.fault(12);CHECK(s.open_binding_ui()==::vr::VRInputError_IPCError);api.fault(0);
  CHECK(api.stats().binding_own_context==1);
  api.fault(13);const auto attempts=api.stats().binding_ui;CHECK(s.open_binding_ui()==0);CHECK(api.stats().binding_ui==attempts+3);api.fault(0);
  s.begin_frame();CHECK(near_value(s.actions().at("left_skeleton").splay[2],.3f));CHECK(near_value(s.actions().at("left_skeleton").splay[3],.4f));
  const auto h=s.overlay_create("v2","v2");s.overlay_sort_order(h,42);s.overlay_color(h,{.2f,.3f,.4f});
  CHECK(api.stats().sorts==1&&api.stats().colors==1);CHECK(s.overlay_info(h).sort_order==42);
  CHECK(api.stats().sort_value==42&&api.stats().red==.2f&&api.stats().green==.3f&&api.stats().blue==.4f);
  CHECK_THROWS_AS(s.show_keyboard("bad","",false,0),std::exception);CHECK_THROWS_AS(s.show_keyboard(std::string(17000,'a'),"",false,100),std::exception);
  api.fault(11);CHECK_THROWS_AS(s.show_keyboard("","",false,20),std::exception);api.fault(0);
  s.show_keyboard("","",false,20);s.hide_keyboard();CHECK(api.stats().keyboard_hides==1);stop(s);
}
TEST_CASE("V2 optional window source: flags ownership removal and older-runtime refusal") {
  Fake api(L"openvr_api.dll"),runtime(L"nlvr_test_runtime_window.dll");v::Session s(folder());auto o=live();o.runtime_dll=folder()/L"nlvr_test_runtime_window.dll";
  start(s,o);CHECK(s.info().overlay_window_supported);const auto h=s.overlay_create("window","window");std::string error;
  REQUIRE(s.overlay_window(h,true,error));CHECK(runtime.stats().window_flags==3);CHECK(s.overlay_info(h).window);
  CHECK_THROWS_AS(s.overlay_window(h+1,true,error),std::exception);CHECK(runtime.stats().windows==1);
  REQUIRE(s.overlay_window(h,false,error));CHECK(runtime.stats().window_flags==0);CHECK(!s.overlay_info(h).window);
  runtime.fault(5);CHECK(!s.overlay_window(h,true,error));CHECK(error.find("RTXVR error")!=std::string::npos);runtime.fault(0);
  REQUIRE(s.overlay_window(h,true,error));s.overlay_destroy(h);CHECK(runtime.stats().window_flags==0);stop(s);
}
