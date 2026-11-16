// SPDX-License-Identifier: MIT
#include "session.h"
#include "lua_policy.h"
#include "fake_control.h"
#include "fake_game.h"
#include "nl_test.h"
#include <windows.h>
#include <algorithm>
#include <fstream>
#include <thread>
#include <cstdio>
#include <cstring>
#include <functional>
#include <vector>

extern "C" int nlvr_c_api_layout(void);
static_assert(sizeof(rtxvr_StartInfo)==168&&sizeof(rtxvr_FramePose)==112&&sizeof(rtxvr_Status)==496&&sizeof(rtxvr_Quality)==24);

namespace {
namespace v=nl::vr;
std::filesystem::path folder() {
  wchar_t name[32768]{};GetModuleFileNameW(nullptr,name,static_cast<DWORD>(std::size(name)));
  return std::filesystem::path(name).parent_path();
}
template<class T> T symbol(HMODULE m,const char* name) { return reinterpret_cast<T>(GetProcAddress(m,name)); }
struct Fake {
  HMODULE dll;
  FakeReset reset;
  FakeFault fault;
  FakeStats stats;
  explicit Fake(const wchar_t* name) {
    dll=LoadLibraryW((folder()/name).c_str());REQUIRE(dll!=nullptr);
    reset=symbol<FakeReset>(dll,"nlvr_fake_reset");fault=symbol<FakeFault>(dll,"nlvr_fake_fault");stats=symbol<FakeStats>(dll,"nlvr_fake_stats");
    REQUIRE(reset&&fault&&stats);reset();
  }
  ~Fake() { FreeLibrary(dll); }
};
v::Options options() {
  v::Options o;o.openvr_dll=folder()/L"openvr_api.dll";o.runtime_dll=folder()/L"nlvr_test_runtime.dll";
  o.manifest=std::filesystem::path(NL_VR_MANIFEST);o.no_submit=true;return o;
}
std::string settle(v::Session& s) {
  const auto end=std::chrono::steady_clock::now()+std::chrono::seconds(5);
  for(;;) {
    const auto state=s.state().first;
    if(state!="starting"&&state!="stopping") return state;
    if(std::chrono::steady_clock::now()>end) return "timeout";
    std::this_thread::sleep_for(std::chrono::milliseconds(1));
  }
}
void stop(v::Session& s) {
  s.stop();REQUIRE(settle(s)=="off");
}
bool close_to(float a,float b) { return std::abs(a-b)<.0001f; }
const char* timeline=R"({"version":1,"steps":[
 {"time":0,"hmd":{"pos":[0,0,1.6],"ang":[0,170,0]},"left":{"pos":[0,0.3,1],"ang":[0,0,0]},"right":{"pos":[0,-0.3,1],"ang":[0,0,0]},"actions":{"left_grip":true,"left_stick":[0,0,0]}},
 {"time":2,"hmd":{"pos":[2,0,1.6],"ang":[0,-170,0]},"left":{"pos":[0,0.3,1],"ang":[0,0,0]},"right":{"pos":[0,-0.3,1],"ang":[0,0,0]},"actions":{"left_grip":false,"left_stick":[1,0,0]}}]})";
// A game window that counts what reaches it (test_window_input.cpp checks the messages themselves).
struct Window final:v::WindowCalls {
  unsigned finds=0,posts=0;
  v::GameWindow find() override { ++finds;return 42; }
  bool owned(v::GameWindow window) override { return window==42; }
  bool bounds(v::GameWindow,int& width,int& height) override { width=1280;height=720;return true; }
  bool screen(v::GameWindow,int&,int&) override { return true; }
  bool foreground(v::GameWindow) override { return true; }
  unsigned scan(unsigned) override { return 0; }
  bool post(v::GameWindow,unsigned,uintptr_t,intptr_t) override { ++posts;return true; }
};
v::WindowInputEvent cursor(int x,int y) { return {"cursor","",x,y}; }
std::string thrown(const std::function<void()>& fn) {
  try { fn(); } catch(const std::exception& e) { return e.what(); }
  return {};
}
// The stand-in engine.dll (tests/fake_engine.cpp), loaded by path for one test and released after it.
struct Engine {
  HMODULE dll=nullptr;
  void (*facts)(int,int,int,int,int)=nullptr;
  void (*shape)(int)=nullptr;
  long (*calls)()=nullptr;
  Engine() {
    REQUIRE(GetModuleHandleW(L"engine.dll")==nullptr);dll=LoadLibraryW(NL_VR_FAKE_ENGINE);REQUIRE(dll!=nullptr);
    facts=symbol<decltype(facts)>(dll,"nlvr_fake_engine_facts");shape=symbol<decltype(shape)>(dll,"nlvr_fake_engine_shape");
    calls=symbol<decltype(calls)>(dll,"nlvr_fake_engine_calls");REQUIRE(facts&&shape&&calls);
  }
  ~Engine() { FreeLibrary(dll); }
  Engine(const Engine&)=delete;
  Engine& operator=(const Engine&)=delete;
};
}
TEST_CASE("VR off: constructing, polling status and loading the Lua module loads no OpenVR or worker") {
  CHECK(nlvr_c_api_layout()==RTXVR_API_VERSION);
  REQUIRE(GetModuleHandleW(L"openvr_api.dll")==nullptr);
  v::Session s(folder());CHECK(s.state().first=="off");CHECK(!s.begin_frame());CHECK(s.events().empty());
  const auto m=LoadLibraryW((folder()/L"gmcl_nlvr_win64.dll").c_str());REQUIRE(m!=nullptr);
  CHECK(GetModuleHandleW(L"openvr_api.dll")==nullptr);FreeLibrary(m);
  stop(s);CHECK(s.state().first=="off");CHECK(GetModuleHandleW(L"openvr_api.dll")==nullptr);
}
TEST_CASE("VR axes: position velocity rotations and inverse conversion") {
  rtxvr_Matrix34 raw{{{1,0,0,1},{0,1,0,2},{0,0,1,-3}}};
  const auto p=v::source_pose(raw,true,{4,5,6},{7,8,9});
  CHECK(close_to(p.pos.x,3)&&close_to(p.pos.y,-1)&&close_to(p.pos.z,2));
  CHECK(close_to(p.ang.x,0)&&close_to(p.ang.y,0)&&close_to(p.ang.z,0));
  CHECK(close_to(p.vel.x,-6)&&close_to(p.vel.y,-4)&&close_to(p.vel.z,5));
  CHECK(close_to(p.angvel.x,-9)&&close_to(p.angvel.y,-7)&&close_to(p.angvel.z,8));
  for(auto a:{v::Vec3{0,90,0},v::Vec3{30,-70,25},v::Vec3{-89,179,90},v::Vec3{90,45,0}}) {
    const auto original=v::source_matrix({1,2,3},v::rotation(a));
    const auto vr=v::to_openvr(original),again=v::to_source(vr);
    for(int i=0;i<3;++i) for(int j=0;j<4;++j) CHECK(close_to(original.m[i][j],again.m[i][j]));
    const auto p2=v::source_pose(vr,true);const auto round=v::source_matrix(p2.pos,v::rotation(p2.ang));
    for(int i=0;i<3;++i) for(int j=0;j<4;++j) CHECK(close_to(original.m[i][j],round.m[i][j]));
  }
  CHECK(!v::source_pose(raw,false).valid);
}
TEST_CASE("VR timeline: interpolation shortest slerp derivatives steps end and invalid documents") {
  const auto t=v::Timeline::parse(timeline);const auto mid=t.sample(1);
  CHECK(close_to(mid.poses[0].pos.x,1));CHECK(close_to(std::abs(mid.poses[0].ang.y),180));
  CHECK(close_to(mid.poses[0].vel.x,1));CHECK(close_to(mid.poses[0].angvel.z,static_cast<float>(3.141592653589793/18)));
  CHECK(mid.actions.at("left_grip").state);CHECK(close_to(mid.actions.at("left_stick").value.x,.5f));
  CHECK(!mid.ended&&mid.step==1);
  const auto end=t.sample(200);CHECK(end.ended&&end.step==2);CHECK(close_to(end.poses[0].pos.x,2));
  CHECK(close_to(end.poses[0].vel.x,0));CHECK(!end.actions.at("left_grip").state);
  CHECK_THROWS_AS(v::Timeline::parse("{}"),std::exception);
  CHECK_THROWS_AS(v::Timeline::parse(R"({"version":2,"steps":[]})"),std::exception);
  CHECK_THROWS_AS(v::Timeline::parse(R"({"version":1,"steps":[]})"),std::exception);
  CHECK_THROWS_AS(v::Timeline::parse("not json"),std::exception);
  std::string bad=timeline;bad.replace(bad.find("\"time\":2"),8,"\"time\":0");
  CHECK_THROWS_AS(v::Timeline::parse(bad),std::exception);
  bad=timeline;bad.replace(bad.find("left_grip"),9,"unknown_x");
  CHECK_THROWS_AS(v::Timeline::parse(bad),std::exception);
  bad=timeline;bad.replace(bad.find("true"),4,"0.5");
  CHECK_THROWS_AS(v::Timeline::parse(bad),std::exception);
  CHECK_THROWS_AS(t.sample(-1),std::exception);
  CHECK_THROWS_AS(v::Timeline::load("relative.json"),std::exception);
}
TEST_CASE("VR lifecycle: two starts stops duplicate start poses inputs overlays events cleanup") {
  Fake api(L"openvr_api.dll"),runtime(L"nlvr_test_runtime.dll");
  v::Session s(folder(),single_player());std::string error;
  CHECK(api.stats().init==0&&runtime.stats().runtime_starts==0);
  for(int cycle=0;cycle<2;++cycle) {
    REQUIRE(s.start(options(),error));REQUIRE(settle(s)=="running");CHECK(!s.start(options(),error));
    const auto f=s.begin_frame();REQUIRE(f);CHECK(f->poses[0].valid);CHECK(close_to(f->poses[0].pos.x,3));
    s.set_camera(f->sequence,{10,20,30},{40,50,60});
    const auto p=symbol<FakePose>(runtime.dll,"nlvr_fake_pose")();CHECK(p.sequence==f->sequence);CHECK(p.flags==0);CHECK(p.cameraOrigin[1]==20);
    CHECK(s.actions().at("left_grip").state);CHECK(s.actions().at("left_skeleton").curls[4]==.5f);
    CHECK(s.haptic("left",.01f,100,.5f)==0);api.fault(6);CHECK(s.haptic("right",.01f,100,.5f)==vr::VRInputError_InvalidDevice);api.fault(0);
    const auto h=s.overlay_create("test.nlvr","test");CHECK(h>9007199254740991ull);
    s.overlay_source(h,513,257);s.overlay_attach(h,"left",{.1f,0,0},{0,0,0},.2f);
    s.overlay_show(h,true);CHECK(s.overlay_visible(h));s.overlay_show(h,false);CHECK(!s.overlay_visible(h));s.overlay_alpha(h,.5f);
    CHECK_THROWS_AS(s.overlay_source(h,0,1),std::exception);CHECK_THROWS_AS(s.overlay_alpha(h,2),std::exception);
    s.overlay_destroy(h);CHECK_THROWS_AS(s.overlay_show(h,true),std::exception);
    const auto emit=symbol<FakeEvent>(api.dll,"nlvr_fake_event");
    emit(vr::VREvent_IpdChanged);emit(vr::VREvent_DashboardActivated);
    // The worker polls every 20 ms, but a loaded test host need not schedule it within 30 ms.
    // Wait for delivery without weakening the exact count, order or drain assertions.
    std::vector<v::Event> events;
    const auto deadline=std::chrono::steady_clock::now()+std::chrono::seconds(5);
    while(events.size()<2&&std::chrono::steady_clock::now()<deadline) {
      const auto batch=s.events();events.insert(events.end(),batch.begin(),batch.end());
      if(events.size()<2) std::this_thread::sleep_for(std::chrono::milliseconds(1));
    }
    REQUIRE(events.size()==2);CHECK(events[0].type=="ipd"&&events[1].type=="dashboard_on");CHECK(s.events().empty());
    CHECK(api.stats().eye_reads==uint32_t(2+cycle*4));
    s.set_camera(f->sequence,{10,20,30},{40,50,60});
    REQUIRE(s.begin_frame());CHECK(api.stats().eye_reads==uint32_t(4+cycle*4));
    CHECK(s.info().eye_width==2016);CHECK(s.info().timing_valid);
    CHECK(s.info().motion_smoothing_supported);CHECK(s.info().motion_smoothing_enabled);
    api.fault(27);CHECK(!s.info().motion_smoothing_enabled);CHECK(s.info().motion_smoothing_supported);api.fault(0);
    s.overlay_create("auto.cleanup","test");
    stop(s);stop(s);CHECK(s.state().first=="off");CHECK(!s.begin_frame());CHECK(s.actions().empty());CHECK(!s.test_state());
  }
  CHECK(api.stats().init==2&&api.stats().shutdown==2&&api.stats().waits==0);
  CHECK(api.stats().created==4&&api.stats().destroyed==4&&api.stats().after_stop==0);
  CHECK(runtime.stats().runtime_starts==2&&runtime.stats().runtime_stops==2&&runtime.stats().eyes==2);
  CHECK(runtime.stats().after_stop==0); // Stop barrier ran before OpenVR shutdown.
}
TEST_CASE("VR failures: missing renderer API version missing SteamVR headset interface manifest renderer failure") {
  Fake api(L"openvr_api.dll"),runtime(L"nlvr_test_runtime.dll");v::Session s(folder(),single_player());std::string error;
  auto o=options();o.runtime_dll=folder()/L"nl_vr_missing_runtime.dll";
  REQUIRE(s.start(o,error));CHECK(settle(s)=="failed");CHECK(s.state().second.find("rtxvr_GetApiVersion")!=std::string::npos);CHECK(api.stats().init==0);stop(s);
  runtime.fault(1);REQUIRE(s.start(options(),error));CHECK(settle(s)=="failed");CHECK(api.stats().init==0);
  CHECK(s.state().second.find("expected "+std::to_string(RTXVR_API_VERSION))!=std::string::npos);stop(s);runtime.fault(0);
  for(int fault:{1,2,3,4}) {
    api.fault(fault);REQUIRE(s.start(options(),error));CHECK(settle(s)=="failed");CHECK(!s.state().second.empty());
    stop(s);CHECK(s.state().first=="off");CHECK(api.stats().init==api.stats().shutdown);
  }
  api.fault(0);runtime.fault(2);REQUIRE(s.start(options(),error));CHECK(settle(s)=="failed");stop(s);
  runtime.fault(3);REQUIRE(s.start(options(),error));CHECK(settle(s)=="failed");CHECK(s.state().second=="missing VK_TEST_required");stop(s);
  runtime.fault(0);o=options();o.openvr_dll=folder()/L"does_not_exist.dll";REQUIRE(s.start(o,error));CHECK(settle(s)=="failed");stop(s);
  o=options();o.manifest=folder()/L"missing.json";REQUIRE(s.start(o,error));CHECK(settle(s)=="failed");stop(s);
  REQUIRE(s.start(options(),error));CHECK(settle(s)=="running");stop(s);
  CHECK(api.stats().init==api.stats().shutdown);
  api.fault(2);REQUIRE(s.start(options(),error));CHECK(settle(s)=="failed");
  api.fault(0);REQUIRE(s.start(options(),error));CHECK(settle(s)=="running");stop(s);
}
TEST_CASE("VR cancellation: Stop requests cancellation and cleanup completes before another Start") {
  Fake api(L"openvr_api.dll"),runtime(L"nlvr_test_runtime.dll");v::Session s(folder(),single_player());std::string error;
  api.fault(5);REQUIRE(s.start(options(),error));std::this_thread::sleep_for(std::chrono::milliseconds(10));
  CHECK(s.state().first=="starting");stop(s);CHECK(s.state().first=="off");CHECK(api.stats().init==api.stats().shutdown);
  api.fault(0);REQUIRE(s.start(options(),error));CHECK(settle(s)=="running");stop(s);
}
TEST_CASE("VR scripted frames: camera flag pose ownership hand overlay no live controller dependency") {
  Fake api(L"openvr_api.dll"),runtime(L"nlvr_test_runtime.dll");
  const auto scratch=nl::test::scratch_dir("vr-timeline");const auto file=scratch/L"timeline.json";
  { std::ofstream out(file);out<<timeline; }
  auto o=options();o.timeline=file;v::Session s(folder(),single_player());std::string error;REQUIRE(s.start(o,error));REQUIRE(settle(s)=="running");
  const auto h=s.overlay_create("script","script");const auto frame=s.begin_frame();REQUIRE(frame);
  const auto before=api.stats().absolute;
  s.overlay_attach(h,"left",{.1f,0,0},{0,0,0},.2f);CHECK(api.stats().absolute==before+1);CHECK(api.stats().relative==0);
  s.overlay_show(h,true);const auto overlay=s.overlay_info(h);
  CHECK(overlay.visible);CHECK(close_to(overlay.width,.2f));CHECK(overlay.texture_width==513&&overlay.texture_height==257);
  CHECK(overlay.transform_error==0&&overlay.texture_error==0);
  const auto absolute=v::source_pose(overlay.transform,true);
  CHECK(close_to(absolute.pos.x,frame->poses[1].pos.x+.1f));CHECK(close_to(absolute.pos.y,frame->poses[1].pos.y));
  CHECK_THROWS_AS(s.overlay_source(h,8193,257),std::exception);
  s.set_camera(frame->sequence,{1,2,3},{4,5,6});const auto p=symbol<FakePose>(runtime.dll,"nlvr_fake_pose")();CHECK(p.flags==RTXVR_POSE_SCRIPTED);
  CHECK(s.actions().at("left_grip").state);CHECK(s.test_state().has_value());
  for(int i=0;i<17;++i) s.begin_frame();
  CHECK_THROWS_AS(s.set_camera(frame->sequence,{},{ }),std::exception);
  stop(s);o.timeline=scratch/L"missing.json";REQUIRE(s.start(o,error));CHECK(settle(s)=="failed");stop(s);
}
TEST_CASE("VR unload: Stop releases OpenVR and runtime DLL references without a test-held handle") {
  REQUIRE(GetModuleHandleW(L"openvr_api.dll")==nullptr);
  REQUIRE(GetModuleHandleW(L"nlvr_test_runtime.dll")==nullptr);
  v::Session s(folder(),single_player());std::string error;REQUIRE(s.start(options(),error));REQUIRE(settle(s)=="running");
  CHECK(GetModuleHandleW(L"openvr_api.dll")!=nullptr);CHECK(GetModuleHandleW(L"nlvr_test_runtime.dll")!=nullptr);
  stop(s);CHECK(GetModuleHandleW(L"openvr_api.dll")==nullptr);CHECK(GetModuleHandleW(L"nlvr_test_runtime.dll")==nullptr);
  CHECK(!s.begin_frame());CHECK(s.events().empty());CHECK(s.actions().empty());
}
TEST_CASE("VR renderer transition: SDK ready exposes the producer before its first traced frame") {
  Fake api(L"openvr_api.dll"),runtime(L"nlvr_test_runtime.dll");v::Session s(folder(),single_player());std::string error;
  runtime.fault(4);REQUIRE(s.start(options(),error));
  const auto deadline=std::chrono::steady_clock::now()+std::chrono::seconds(5);
  while(s.info().eye_width==0&&std::chrono::steady_clock::now()<deadline)
    std::this_thread::sleep_for(std::chrono::milliseconds(1));
  REQUIRE(s.info().eye_width==2016);CHECK(s.state().first=="running");
  CHECK(s.info().sdk_ready);auto first=s.begin_frame();REQUIRE(first);CHECK(api.stats().waits==0);
  s.set_camera(first->sequence,{},{}); // The real runtime cannot draw a VR frame before this push.
  runtime.fault(0);CHECK(s.state().first=="running");CHECK(s.begin_frame().has_value());CHECK(api.stats().waits==0);
  stop(s);CHECK(!s.begin_frame());CHECK(api.stats().waits==0);
}

TEST_CASE("VR review: every Lua-facing entry returns promptly while VR_Init is held and after cancellation") {
  Fake api(L"openvr_api.dll"),runtime(L"nlvr_test_runtime.dll");v::Session s(folder(),single_player());std::string error;
  const auto hold=symbol<FakeHoldInit>(api.dll,"nlvr_fake_hold_init");
  const auto entered=symbol<FakeInitEntered>(api.dll,"nlvr_fake_init_entered");
  REQUIRE(hold&&entered);hold(true);REQUIRE(s.start(options(),error));
  // An old blocking implementation is still released after one second, so the test fails without hanging.
  std::thread release([&] { std::this_thread::sleep_for(std::chrono::seconds(1));hold(false); });
  const auto deadline=std::chrono::steady_clock::now()+std::chrono::milliseconds(500);
  while(!entered()&&std::chrono::steady_clock::now()<deadline) std::this_thread::sleep_for(std::chrono::milliseconds(1));
  CHECK(entered());
  double worst=0;
  const auto timed=[&](const char* name,const std::function<void()>& fn) {
    const auto began=std::chrono::steady_clock::now();
    try { fn(); } catch(const std::exception&) { /* Mutators must fail immediately while busy. */ }
    const auto ms=std::chrono::duration<double,std::milli>(std::chrono::steady_clock::now()-began).count();
    worst=std::max(worst,ms);std::printf("review-latency %s %.6f ms\n",name,ms);CHECK(ms<100);
  };
  const auto calls=[&] {
    timed("State",[&] { s.state(); });timed("Info",[&] { s.info(); });timed("Events",[&] { s.events(); });
    timed("Actions",[&] { s.actions(); });timed("TestState",[&] { s.test_state(); });
    timed("BeginFrame",[&] { CHECK(!s.begin_frame()); });timed("Probe",[&] { s.probe(); });
    timed("Start",[&] { CHECK(!s.start(options(),error)); });
    timed("SetFrameCamera",[&] { s.set_camera(1,{},{}); });
    timed("Haptic",[&] { s.haptic("left",.01f,100,.5f); });
    timed("OverlayCreate",[&] { s.overlay_create("review","review"); });
    timed("OverlaySource",[&] { s.overlay_source(123,513,257); });
    timed("OverlayAttach",[&] { s.overlay_attach(123,"left",{},{},.2f); });
    timed("OverlayShow",[&] { s.overlay_show(123,true); });timed("OverlayAlpha",[&] { s.overlay_alpha(123,.5f); });
    timed("OverlayDestroy",[&] { s.overlay_destroy(123); });timed("OverlayVisible",[&] { s.overlay_visible(123); });
    timed("Capture",[&] { s.capture(folder(),1); });
    timed("ShowKeyboard",[&] { s.show_keyboard("","",false,128); });
    timed("HideKeyboard",[&] { s.hide_keyboard(); });timed("OpenBindingUI",[&] { s.open_binding_ui(); });
    timed("OverlayColor",[&] { s.overlay_color(123,{1,1,1}); });
    timed("OverlaySortOrder",[&] { s.overlay_sort_order(123,1); });
    timed("OverlayWindow",[&] { std::string detail;s.overlay_window(123,true,detail); });
  };
  calls();timed("Stop",[&] { s.stop(); });
  CHECK(s.state().first=="stopping");calls();timed("StopAgain",[&] { s.stop(); });
  release.join();CHECK(settle(s)=="off");CHECK(api.stats().shutdown==1);CHECK(runtime.stats().runtime_starts==0);
  REQUIRE(s.start(options(),error));CHECK(settle(s)=="running");stop(s);
  std::printf("review-latency maximum %.6f ms with init held 1000 ms\n",worst);
}

TEST_CASE("VR render pacing: a stalled renderer cannot block pose acquisition") {
  Fake api(L"openvr_api.dll"),runtime(L"nlvr_test_runtime.dll");v::Session s(folder(),single_player());std::string error;
  symbol<FakeRenderDelay>(runtime.dll,"nlvr_fake_render_delay")(-1);
  REQUIRE(s.start(options(),error));REQUIRE(settle(s)=="running");
  auto first=s.begin_frame();REQUIRE(first);s.set_camera(first->sequence,{},{});
  for(int i=0;i<5000;++i) REQUIRE(s.begin_frame());
  CHECK(api.stats().waits==0);CHECK(api.stats().predicted==5001);CHECK(s.info().completion_wait_count==0);
  stop(s);
}
TEST_CASE("VR review 6: SDK ready starts the producer and absent scenes have no deadline") {
  Fake api(L"openvr_api.dll"),runtime(L"nlvr_test_runtime.dll");
  const auto set_delay=symbol<FakeRenderDelay>(runtime.dll,"nlvr_fake_render_delay");
  set_delay(-1);v::Session s(folder(),single_player());std::string error;REQUIRE(s.start(options(),error));REQUIRE(settle(s)=="running");
  REQUIRE(s.begin_frame());REQUIRE(s.begin_frame());REQUIRE(s.begin_frame());
  CHECK(api.stats().waits==0);CHECK(s.info().completion_wait_count==0);CHECK(s.info().completion_wait_timeouts==0);stop(s);
  runtime.fault(4);v::Session starting(folder(),single_player());
  REQUIRE(starting.start(options(),error));CHECK(settle(starting)=="running");
  std::this_thread::sleep_for(std::chrono::milliseconds(70));
  CHECK(starting.state().first=="running");CHECK(starting.begin_frame());stop(starting);CHECK(api.stats().waits==0);
}

TEST_CASE("VR review: manifest follows the game add-on directory and DLL discovery stays beside the module") {
  Fake api(L"openvr_api.dll"),runtime(L"nlvr_test_runtime.dll");
  const auto scratch=nl::test::scratch_dir("vr-addon-layout");
  const auto bin=scratch/L"game root/garrysmod/lua/bin",input=scratch/L"game root/garrysmod/addons/nlvr/input";
  std::filesystem::create_directories(bin);std::filesystem::create_directories(input);
  std::filesystem::copy_file(std::filesystem::path(NL_VR_MANIFEST),input/L"nlvr_actions.json");
  auto o=options();o.manifest.clear();v::Session s(bin,single_player());std::string error;
  REQUIRE(s.start(o,error));REQUIRE(settle(s)=="running");
  const auto manifest=symbol<FakeTrace>(api.dll,"nlvr_fake_manifest_path");REQUIRE(manifest);
  CHECK(std::filesystem::path(std::u8string(reinterpret_cast<const char8_t*>(manifest())))==input/L"nlvr_actions.json");
  stop(s);
}

TEST_CASE("VR review 1: Lua names cannot choose paths or native libraries") {
  using namespace nl::vr;
  for(const char* key:{"openvr_dll","manifest","runtime_dll"}) CHECK_THROWS_AS(reject_lua_path_key(key),std::exception);
  const auto root=folder()/L"safe-data";
  for(const char* name:{"../escape","C:/outside","\\\\server\\x","a/b","a.b","CON:"}) CHECK_THROWS_AS(named_data(root,name,true),std::exception);
  CHECK(named_data(root,"scene_1",true)==root/L"captures/scene_1");
  CHECK(named_data(root,"walk",false)==root/L"timelines/walk.json");
}
TEST_CASE("VR review 3: native quit is acknowledged without Lua frame or event polling") {
  Fake api(L"openvr_api.dll"),runtime(L"nlvr_test_runtime.dll");v::Session s(folder(),single_player());std::string error;
  REQUIRE(s.start(options(),error));REQUIRE(settle(s)=="running");
  symbol<FakeEvent>(api.dll,"nlvr_fake_event")(vr::VREvent_Quit);
  const auto until=std::chrono::steady_clock::now()+std::chrono::seconds(2);
  while(s.state().first!="off"&&std::chrono::steady_clock::now()<until) Sleep(1);
  CHECK(s.state().first=="off");CHECK(api.stats().acknowledged==1);CHECK(api.stats().shutdown==1);
  CHECK(s.state().second.find("SteamVR")!=std::string::npos);CHECK(api.stats().waits==0);
}
TEST_CASE("VR review 8 9 and render pacing: prediction never waits and invisible hands hide overlays") {
  Fake api(L"openvr_api.dll"),runtime(L"nlvr_test_runtime.dll");v::Session s(folder(),single_player());std::string error;
  auto o=options();REQUIRE(s.start(o,error));REQUIRE(settle(s)=="running");
  auto frame=s.begin_frame();REQUIRE(frame);s.set_camera(frame->sequence,{},{});
  CHECK(api.stats().waits==0);CHECK(api.stats().predicted==1);CHECK(frame->predicted_seconds>0);
  api.fault(8);frame=s.begin_frame();REQUIRE(frame);CHECK(!frame->poses[0].valid);s.set_camera(frame->sequence,{},{});
  CHECK(symbol<FakePose>(runtime.dll,"nlvr_fake_pose")().flags&RTXVR_POSE_SCRIPTED);
  api.fault(9);const auto h=s.overlay_create("sleep","sleep");s.overlay_attach(h,"left",{},{},.2f);s.overlay_show(h,true);CHECK(!s.overlay_visible(h));
  api.fault(0);REQUIRE(s.begin_frame());CHECK(s.overlay_visible(h));api.fault(9);REQUIRE(s.begin_frame());CHECK(!s.overlay_visible(h));
  CHECK(api.stats().waits==0);stop(s);
}

// Review finding 8: any client Lua, a server's included, can require this module, so ADR 0197's single-player rule is
// the module's own, read from the engine and never from Lua.
TEST_CASE("VR review finding 8: a game of two player slots starts no VR and reaches no window, keyboard, binding editor or capture") {
  Fake api(L"openvr_api.dll"),runtime(L"nlvr_test_runtime.dll");
  FakeGame game;game.game.max_clients=2;Window window;v::Session s(folder(),game,window);std::string error;
  CHECK(!s.start(options(),error));CHECK(error=="VR works in single-player games only: the game has 2 player slots");
  CHECK(game.asked==1);CHECK(settle(s)=="off");  // no worker: nothing to wait for
  CHECK(api.stats().init==0);CHECK(runtime.stats().runtime_starts==0);  // no VR_InitInternal2: SteamVR never starts
  CHECK(thrown([&] { s.window_input(cursor(1,1)); })=="nlvr is not running");CHECK(window.finds==0&&window.posts==0);
  CHECK(thrown([&] { s.show_keyboard("","Enter your password",false,64); })=="nlvr is not running");
  CHECK(thrown([&] { s.open_binding_ui(); })=="nlvr is not running");
  CHECK(thrown([&] { s.capture(folder(),1); })=="nlvr is not running");
  CHECK(api.stats().keyboard_shows==0&&api.stats().binding_ui==0&&runtime.stats().captures==0);
  // Every other game that is not a local single-player one is refused the same way, before anything loads.
  struct Case { v::GameFacts facts;bool readable;const char* says; };
  const Case refused[]={
    {{true,true,false,false,1},true,"the game is connected to a server outside this game"},  // a remote server: one slot
    {{true,false,false,false,1},true,"the game has no connection to its server"},
    {{true,true,true,true,1},true,"a demo is playing"},
    {{false,false,false,false,0},true,"the game is not in a map"},                         // the main menu
    {{true,true,true,false,1},false,"the engine could not say whether this is one"},
  };
  for(const auto& c:refused) {
    game.game=c.facts;game.readable=c.readable;
    CHECK(!s.start(options(),error));CHECK(error.find(c.says)!=std::string::npos);CHECK(s.state().first=="off");
  }
  CHECK(api.stats().init==0&&runtime.stats().runtime_starts==0);
  // The module's own default asks this process's engine.dll, and a process without one is no game.
  v::Session plain(folder());CHECK(!plain.start(options(),error));CHECK(error.find("engine.dll is not loaded")!=std::string::npos);
  CHECK(settle(plain)=="off");CHECK(api.stats().init==0);
  // A local single-player game starts VR as before; the window, keyboard, binding editor and captures work.
  game.game={true,true,true,false,1};game.readable=true;
  REQUIRE(s.start(options(),error));REQUIRE(settle(s)=="running");REQUIRE(s.begin_frame());
  s.window_input(cursor(1,1));CHECK(window.posts==1);
  s.show_keyboard("","label",false,64);CHECK(api.stats().keyboard_shows==1);
  CHECK(s.open_binding_ui()==0);const auto bindings=api.stats().binding_ui;CHECK(bindings>0);
  s.capture(folder(),1);CHECK(runtime.stats().captures==1);
  // A game that stops being one while VR runs (a new client Lua state closes the module first): the four refuse each
  // time, poses go on, and they work again in a local single-player game.
  game.game.loopback=false;
  const std::string remote="VR works in single-player games only: the game is connected to a server outside this game";
  CHECK(thrown([&] { s.window_input(cursor(2,2)); })==remote);CHECK(window.posts==1);
  CHECK(thrown([&] { s.show_keyboard("","label",false,64); })==remote);CHECK(api.stats().keyboard_shows==1);
  CHECK(thrown([&] { s.open_binding_ui(); })==remote);CHECK(api.stats().binding_ui==bindings);
  CHECK(thrown([&] { s.capture(folder(),1); })==remote);CHECK(runtime.stats().captures==1);
  CHECK(s.begin_frame().has_value());CHECK(s.state().first=="running");
  game.game.loopback=true;s.window_input(cursor(3,3));CHECK(window.posts==2);
  stop(s);CHECK(api.stats().init==1&&api.stats().shutdown==1);
}
TEST_CASE("VR review finding 8: the game is read from engine.dll's VEngineClient015, and only where it has the game's shape") {
  auto& engine=v::engine_game_calls();v::GameFacts facts;std::string why;
  CHECK(!engine.facts(facts,why));CHECK(why=="engine.dll is not loaded");  // this process is no game
  Engine stand_in;
  // Joined through the loopback channel to this process's own server with one slot: IsConnected, GetMaxClients,
  // IsPlayingDemo, GetNetChannelInfo and the channel's IsLoopback, each from its own slot.
  CHECK(engine.facts(facts,why));CHECK(v::local_single_player(facts));CHECK(stand_in.calls()==5);
  CHECK(facts.connected&&facts.channel&&facts.loopback&&!facts.demo&&facts.max_clients==1);
  stand_in.facts(1,1,1,0,2);CHECK(engine.facts(facts,why));CHECK(facts.max_clients==2);CHECK(!v::local_single_player(facts));
  stand_in.facts(1,1,0,0,1);CHECK(engine.facts(facts,why));CHECK(!facts.loopback);CHECK(!v::local_single_player(facts));
  stand_in.facts(1,1,1,1,1);CHECK(engine.facts(facts,why));CHECK(facts.demo);CHECK(!v::local_single_player(facts));
  stand_in.facts(1,0,1,0,1);CHECK(engine.facts(facts,why));CHECK(!facts.channel&&!facts.loopback);
  auto calls=stand_in.calls();stand_in.facts(0,1,1,0,1);
  CHECK(engine.facts(facts,why));CHECK(!facts.connected);CHECK(stand_in.calls()==calls+1);  // only IsConnected was asked
  CHECK(v::not_single_player(facts)=="the game is not in a map");
  // Another shape is never called: the engine cannot say, and nothing starts.
  stand_in.facts(1,1,1,0,1);
  struct Shape { int kind;const char* says;long asked; };
  const Shape shapes[]={
    {1,"engine.dll's VEngineClient015 is not the one this module knows",0},  // IsConnected's slot holds data
    {4,"engine.dll's VEngineClient015 is not the one this module knows",0},  // the object's vtable is not engine.dll's
    {3,"engine.dll has no VEngineClient015",0},
    {2,"the engine's net channel is not the one this module knows",4},        // the channel's vtable is not engine.dll's
  };
  for(const auto& shape:shapes) {
    stand_in.shape(shape.kind);calls=stand_in.calls();
    CHECK(!engine.facts(facts,why));CHECK(why==shape.says);CHECK(stand_in.calls()==calls+shape.asked);
  }
  stand_in.shape(0);CHECK(engine.facts(facts,why));CHECK(v::local_single_player(facts));
}
TEST_CASE("VR review finding 8: a session asks engine.dll itself before OpenVR and again before the game window") {
  Engine stand_in;Fake api(L"openvr_api.dll"),runtime(L"nlvr_test_runtime.dll");Window window;
  v::Session s(folder(),v::engine_game_calls(),window);std::string error;
  stand_in.facts(1,1,1,0,2);CHECK(!s.start(options(),error));
  CHECK(error=="VR works in single-player games only: the game has 2 player slots");
  CHECK(settle(s)=="off");CHECK(api.stats().init==0);
  stand_in.facts(1,1,1,0,1);REQUIRE(s.start(options(),error));REQUIRE(settle(s)=="running");REQUIRE(s.begin_frame());
  s.window_input(cursor(1,1));CHECK(window.posts==1);
  stand_in.facts(1,1,0,0,1);CHECK(thrown([&] { s.window_input(cursor(2,2)); }).find("outside this game")!=std::string::npos);
  CHECK(window.posts==1);
  stop(s);CHECK(api.stats().init==1);
}
// The installed game's engine.dll (NL_ENGINE_DLL, else the PoC's), mapped as an image and never run: CEngineClient's
// and CNetChan's vtables found through RTTI, and in each slot the gate calls the code of the function it means. A GMod
// update that moves them fails here, before a package ships a gate that would read other functions.
TEST_CASE("VR review finding 8: the installed game's engine.dll has the functions the gate calls in its slots") {
  wchar_t path[MAX_PATH]{};
  if(!GetEnvironmentVariableW(L"NL_ENGINE_DLL",path,MAX_PATH))
    wcscpy_s(path,L"H:\\SteamLibrary\\steamapps\\common\\GarrysMod_PoC\\bin\\win64\\engine.dll");
  if(GetFileAttributesW(path)==INVALID_FILE_ATTRIBUTES) return;  // no game on this machine (CI)
  const HMODULE mapped=LoadLibraryExW(path,nullptr,LOAD_LIBRARY_AS_IMAGE_RESOURCE|LOAD_LIBRARY_AS_DATAFILE);
  REQUIRE(mapped!=nullptr);
  struct Unmap { HMODULE module;~Unmap() { FreeLibrary(module); } } unmap{mapped};
  const auto* base=reinterpret_cast<const uint8_t*>(reinterpret_cast<uintptr_t>(mapped)&~uintptr_t{3});
  const auto* nt=reinterpret_cast<const IMAGE_NT_HEADERS64*>(base+reinterpret_cast<const IMAGE_DOS_HEADER*>(base)->e_lfanew);
  const uint64_t preferred=nt->OptionalHeader.ImageBase;  // not relocated: pointers hold preferred-base addresses
  std::vector<std::pair<uint32_t,uint32_t>> readable;
  const auto* section=IMAGE_FIRST_SECTION(nt);
  for(WORD i=0;i<nt->FileHeader.NumberOfSections;++i,++section)
    if(section->Characteristics&IMAGE_SCN_MEM_READ) readable.push_back({section->VirtualAddress,section->VirtualAddress+section->Misc.VirtualSize});
  const auto u32=[&](uint32_t rva) { uint32_t value=0;std::memcpy(&value,base+rva,4);return value; };
  const auto u64=[&](uint32_t rva) { uint64_t value=0;std::memcpy(&value,base+rva,8);return value; };
  const auto rel=[&](uint32_t rva) { int32_t value=0;std::memcpy(&value,base+rva,4);return value; };
  // RTTI: the type descriptor (its name at +16), the complete object locator naming it (signature 1, offset 0, itself)
  // and, after the pointer to that locator, the vtable.
  const auto vtable=[&](const char* name)->uint32_t {
    const uint32_t length=static_cast<uint32_t>(std::strlen(name)+1);uint32_t descriptor=0;
    for(const auto& [begin,end]:readable)
      for(uint32_t at=begin;!descriptor&&at+length<=end;++at)
        if(base[at]=='.'&&std::memcmp(base+at,name,length)==0) descriptor=at-16;
    if(!descriptor) return 0;
    for(const auto& [begin,end]:readable)
      for(uint32_t at=(begin+3)&~3u;at+24<=end;at+=4)
        if(u32(at)==1&&u32(at+4)==0&&u32(at+12)==descriptor&&u32(at+20)==at)
          for(const auto& [first,last]:readable)
            for(uint32_t p=(first+7)&~7u;p+16<=last;p+=8) if(u64(p)==preferred+at) return p+8;
    return 0;
  };
  const uint32_t client=vtable(".?AVCEngineClient@@"),channel=vtable(".?AVCNetChan@@");
  REQUIRE(client!=0);REQUIRE(channel!=0);
  const auto slot=[&](uint32_t table,unsigned index) { return static_cast<uint32_t>(u64(table+8*index)-preferred); };
  const auto shaped=[&](uint32_t rva,std::initializer_list<int> bytes) {  // -1: any byte (a displacement)
    uint32_t i=0;
    for(const int b:bytes) { if(b>=0&&base[rva+i]!=b) return false;++i; }
    return true;
  };
  const uint32_t max_clients=slot(client,21),connected=slot(client,27),in_game=slot(client,26);
  const uint32_t net_channel=slot(client,72),demo=slot(client,76),loopback=slot(channel,6);
  CHECK(shaped(max_clients,{0x8B,0x05,-1,-1,-1,-1,0xC3}));                      // mov eax,[rip+maxclients]; ret
  CHECK(shaped(connected,{0x83,0x3D,-1,-1,-1,-1,0x02,0x0F,0x9D,0xC0,0xC3}));     // cmp [rip+signon],2; setge al; ret
  CHECK(shaped(in_game,{0x83,0x3D,-1,-1,-1,-1,0x06,0x0F,0x94,0xC0,0xC3}));       // IsInGame: cmp [rip+signon],6; sete al
  CHECK(connected+7+rel(connected+2)==in_game+7+rel(in_game+2));                 // both read the client's signon state
  CHECK(shaped(net_channel,{0x48,0x8B,0x05,-1,-1,-1,-1,0xC3}));                  // mov rax,[rip+netchannel]; ret
  CHECK(shaped(demo,{0x48,0x8B,0x0D,-1,-1,-1,-1,0x48,0x8B,0x01,0x48,0xFF,0x60,0x30}));  // the demo player's slot 6
  CHECK(shaped(loopback,{0x48,0x81,0xC1,0xC4,0x00,0x00,0x00,0xE9,-1,-1,-1,-1}));  // the remote address, then:
  CHECK(shaped(loopback+12+rel(loopback+8),{0x83,0x39,0x01,0x0F,0x94,0xC0,0xC3}));  // netadr_t: type == NA_LOOPBACK
}

