// SPDX-License-Identifier: MIT
#include "session.h"
#include "lua_policy.h"
#include "fake_control.h"
#include "nl_test.h"
#include <windows.h>
#include <algorithm>
#include <fstream>
#include <thread>
#include <cstdio>
#include <functional>

extern "C" int nlvr_c_api_layout(void);
static_assert(sizeof(rtxvr_StartInfo)==168&&sizeof(rtxvr_FramePose)==112&&sizeof(rtxvr_Status)==456);

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
  v::Session s(folder());std::string error;
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
    s.overlay_create("auto.cleanup","test");
    stop(s);stop(s);CHECK(s.state().first=="off");CHECK(!s.begin_frame());CHECK(s.actions().empty());CHECK(!s.test_state());
  }
  CHECK(api.stats().init==2&&api.stats().shutdown==2&&api.stats().waits==0);
  CHECK(api.stats().created==4&&api.stats().destroyed==4&&api.stats().after_stop==0);
  CHECK(runtime.stats().runtime_starts==2&&runtime.stats().runtime_stops==2&&runtime.stats().eyes==2);
  CHECK(runtime.stats().after_stop==0); // Stop barrier ran before OpenVR shutdown.
}
TEST_CASE("VR failures: missing renderer API version missing SteamVR headset interface manifest renderer failure") {
  Fake api(L"openvr_api.dll"),runtime(L"nlvr_test_runtime.dll");v::Session s(folder());std::string error;
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
  Fake api(L"openvr_api.dll"),runtime(L"nlvr_test_runtime.dll");v::Session s(folder());std::string error;
  api.fault(5);REQUIRE(s.start(options(),error));std::this_thread::sleep_for(std::chrono::milliseconds(10));
  CHECK(s.state().first=="starting");stop(s);CHECK(s.state().first=="off");CHECK(api.stats().init==api.stats().shutdown);
  api.fault(0);REQUIRE(s.start(options(),error));CHECK(settle(s)=="running");stop(s);
}
TEST_CASE("VR scripted frames: camera flag pose ownership hand overlay no live controller dependency") {
  Fake api(L"openvr_api.dll"),runtime(L"nlvr_test_runtime.dll");
  const auto scratch=nl::test::scratch_dir("vr-timeline");const auto file=scratch/L"timeline.json";
  { std::ofstream out(file);out<<timeline; }
  auto o=options();o.timeline=file;v::Session s(folder());std::string error;REQUIRE(s.start(o,error));REQUIRE(settle(s)=="running");
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
  v::Session s(folder());std::string error;REQUIRE(s.start(options(),error));REQUIRE(settle(s)=="running");
  CHECK(GetModuleHandleW(L"openvr_api.dll")!=nullptr);CHECK(GetModuleHandleW(L"nlvr_test_runtime.dll")!=nullptr);
  stop(s);CHECK(GetModuleHandleW(L"openvr_api.dll")==nullptr);CHECK(GetModuleHandleW(L"nlvr_test_runtime.dll")==nullptr);
  CHECK(!s.begin_frame());CHECK(s.events().empty());CHECK(s.actions().empty());
}
TEST_CASE("VR renderer transition: SDK ready exposes the producer before its first traced frame") {
  Fake api(L"openvr_api.dll"),runtime(L"nlvr_test_runtime.dll");v::Session s(folder());std::string error;
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
  Fake api(L"openvr_api.dll"),runtime(L"nlvr_test_runtime.dll");v::Session s(folder());std::string error;
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
  };
  calls();timed("Stop",[&] { s.stop(); });
  CHECK(s.state().first=="stopping");calls();timed("StopAgain",[&] { s.stop(); });
  release.join();CHECK(settle(s)=="off");CHECK(api.stats().shutdown==1);CHECK(runtime.stats().runtime_starts==0);
  REQUIRE(s.start(options(),error));CHECK(settle(s)=="running");stop(s);
  std::printf("review-latency maximum %.6f ms with init held 1000 ms\n",worst);
}

TEST_CASE("VR render pacing: a stalled renderer cannot block pose acquisition") {
  Fake api(L"openvr_api.dll"),runtime(L"nlvr_test_runtime.dll");v::Session s(folder());std::string error;
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
  set_delay(-1);v::Session s(folder());std::string error;REQUIRE(s.start(options(),error));REQUIRE(settle(s)=="running");
  REQUIRE(s.begin_frame());REQUIRE(s.begin_frame());REQUIRE(s.begin_frame());
  CHECK(api.stats().waits==0);CHECK(s.info().completion_wait_count==0);CHECK(s.info().completion_wait_timeouts==0);stop(s);
  runtime.fault(4);v::Session starting(folder());
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
  auto o=options();o.manifest.clear();v::Session s(bin);std::string error;
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
  Fake api(L"openvr_api.dll"),runtime(L"nlvr_test_runtime.dll");v::Session s(folder());std::string error;
  REQUIRE(s.start(options(),error));REQUIRE(settle(s)=="running");
  symbol<FakeEvent>(api.dll,"nlvr_fake_event")(vr::VREvent_Quit);
  const auto until=std::chrono::steady_clock::now()+std::chrono::seconds(2);
  while(s.state().first!="off"&&std::chrono::steady_clock::now()<until) Sleep(1);
  CHECK(s.state().first=="off");CHECK(api.stats().acknowledged==1);CHECK(api.stats().shutdown==1);
  CHECK(s.state().second.find("SteamVR")!=std::string::npos);CHECK(api.stats().waits==0);
}
TEST_CASE("VR review 8 9 and render pacing: prediction never waits and invisible hands hide overlays") {
  Fake api(L"openvr_api.dll"),runtime(L"nlvr_test_runtime.dll");v::Session s(folder());std::string error;
  auto o=options();REQUIRE(s.start(o,error));REQUIRE(settle(s)=="running");
  auto frame=s.begin_frame();REQUIRE(frame);s.set_camera(frame->sequence,{},{});
  CHECK(api.stats().waits==0);CHECK(api.stats().predicted==1);CHECK(frame->predicted_seconds>0);
  api.fault(8);frame=s.begin_frame();REQUIRE(frame);CHECK(!frame->poses[0].valid);s.set_camera(frame->sequence,{},{});
  CHECK(symbol<FakePose>(runtime.dll,"nlvr_fake_pose")().flags&RTXVR_POSE_SCRIPTED);
  api.fault(9);const auto h=s.overlay_create("sleep","sleep");s.overlay_attach(h,"left",{},{},.2f);s.overlay_show(h,true);CHECK(!s.overlay_visible(h));
  api.fault(0);REQUIRE(s.begin_frame());CHECK(s.overlay_visible(h));api.fault(9);REQUIRE(s.begin_frame());CHECK(!s.overlay_visible(h));
  CHECK(api.stats().waits==0);stop(s);
}

