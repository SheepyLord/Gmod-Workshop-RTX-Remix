// SPDX-License-Identifier: MIT
#include "nl_test.h"
#include "session.h"
#include "fake_control.h"
#include <windows.h>
#include <chrono>
#include <thread>
#include <vector>

namespace {
namespace v=nl::vr;
struct Message { v::GameWindow window;unsigned kind;uintptr_t word;intptr_t value; };
struct Calls final:v::WindowCalls {
  std::vector<Message> messages;
  v::GameWindow found=42;
  bool valid=true,front=false,dimension=true,coordinates=true;
  unsigned fail_at=0,attempts=0,finds=0;
  v::GameWindow find() override { ++finds;return found; }
  bool owned(v::GameWindow window) override { return valid&&window==42; }
  bool bounds(v::GameWindow,int& w,int& h) override { w=3840;h=2160;return dimension; }
  bool screen(v::GameWindow,int& x,int& y) override { x+=100;y+=200;return coordinates; }
  bool foreground(v::GameWindow) override { return front; }
  unsigned scan(unsigned) override { return 0x35; }
  bool post(v::GameWindow window,unsigned kind,uintptr_t word,intptr_t value) override {
    ++attempts;if(attempts==fail_at) return false;
    messages.push_back({window,kind,word,value});return true;
  }
};
v::WindowInputEvent cursor(int x,int y) { return {"cursor","",x,y}; }
v::WindowInputEvent button(const char* name,bool down) { return {"button",name,0,0,down}; }
v::WindowInputEvent key(const char* name,bool down) { return {"key",name,0,0,down}; }
v::WindowInputEvent character(uint32_t cp) { v::WindowInputEvent e;e.kind="char";e.character=cp;return e; }
}
TEST_CASE("Window input: posted client cursor buttons signed wheel and background diagnostics") {
  Calls calls;v::WindowInput input(calls);input.dispatch(cursor(140,249),1);
  REQUIRE(calls.messages.size()==1);CHECK(calls.messages[0].window==42&&calls.messages[0].kind==WM_MOUSEMOVE);
  CHECK(LOWORD(calls.messages[0].value)==140&&HIWORD(calls.messages[0].value)==249);
  input.dispatch(button("left",true),1);input.dispatch(button("right",true),1);input.dispatch(button("middle",true),1);
  CHECK(calls.messages.back().word==(MK_LBUTTON|MK_RBUTTON|MK_MBUTTON));
  input.dispatch({"wheel","",0,-2},1);const auto wheel=calls.messages.back();
  CHECK(wheel.kind==WM_MOUSEWHEEL);CHECK(static_cast<short>(HIWORD(wheel.word))==-240);
  CHECK(LOWORD(wheel.value)==240&&HIWORD(wheel.value)==449);
  const auto info=input.info();CHECK(info.owned&&!info.foreground&&info.width==3840&&info.height==2160&&info.held==3);
  const auto count=calls.messages.size();input.dispatch(button("left",true),1);CHECK(calls.messages.size()==count);
  input.dispatch(button("left",false),1);CHECK(calls.messages.back().kind==WM_LBUTTONUP);
  CHECK(calls.messages.back().word==(MK_RBUTTON|MK_MBUTTON));
  input.release();CHECK(input.info().held==0&&calls.messages.back().kind==WM_MBUTTONUP);
}
TEST_CASE("Window input: Unicode UTF16 pairs printable scalar validation and paired key bits") {
  Calls calls;v::WindowInput input(calls);input.dispatch(character(0x4e2d),1);input.dispatch(character(0x1f642),1);
  REQUIRE(calls.messages.size()==3);CHECK(calls.messages[0].word==0x4e2d);
  CHECK(calls.messages[1].kind==WM_CHAR&&calls.messages[1].word==0xd83d&&calls.messages[2].word==0xde42);
  input.dispatch(key("left",true),1);CHECK(calls.messages.back().kind==WM_KEYDOWN&&calls.messages.back().word==VK_LEFT);
  CHECK(calls.messages.back().value==(1u|(0x35u<<16)|(1u<<24)));
  input.dispatch(key("enter",true),1);input.release();CHECK(input.info().held==0);
  CHECK(calls.messages.back().kind==WM_KEYUP&&calls.messages.back().word==VK_LEFT);
  CHECK((static_cast<uint32_t>(calls.messages.back().value)&0xc1000000u)==0xc1000000u);
  for(auto cp:{0u,13u,127u,0xd800u,0xdfffu,0x110000u}) CHECK_THROWS_AS(input.dispatch(character(cp),1),std::exception);
  CHECK_THROWS_AS(input.dispatch(key("alt",true),1),std::exception);
  CHECK_THROWS_AS(input.dispatch(key("insert",true),1),std::exception);
}
TEST_CASE("Window input: frame cap releases held input and reserves both halves of a surrogate pair") {
  Calls calls;v::WindowInput input(calls);input.dispatch(button("left",true),1);input.dispatch(key("tab",true),1);
  for(unsigned i=2;i<v::WindowInput::frame_limit;++i) input.dispatch(cursor(2,3),1);
  CHECK_THROWS_AS(input.dispatch(cursor(3,4),1),std::exception);
  CHECK(input.info().held==0&&input.info().frame_messages==64);
  REQUIRE(calls.messages.size()==66);CHECK(calls.messages[64].kind==WM_LBUTTONUP&&calls.messages[65].kind==WM_KEYUP);
  input.dispatch(cursor(4,5),2);CHECK(input.info().frame_messages==1);
  for(unsigned i=1;i<63;++i) input.dispatch(cursor(2,3),2);
  const auto count=calls.messages.size();CHECK_THROWS_AS(input.dispatch(character(0x1f642),2),std::exception);
  CHECK(calls.messages.size()==count);CHECK_THROWS_AS(input.dispatch(cursor(0,0),0),std::exception);
}
TEST_CASE("Window input: missing foreign recycled targets failures and destructor balance") {
  Calls calls;
  { v::WindowInput input(calls);calls.found=0;CHECK_THROWS_AS(input.dispatch(cursor(1,2),1),std::exception);CHECK(calls.messages.empty());
    calls.found=43;CHECK_THROWS_AS(input.dispatch(cursor(1,2),1),std::exception);CHECK(calls.messages.empty()); }
  calls.found=42;
  { v::WindowInput input(calls);input.dispatch(button("left",true),1);input.dispatch(key("escape",true),1); }
  REQUIRE(calls.messages.size()==4);CHECK(calls.messages[2].kind==WM_LBUTTONUP&&calls.messages[3].kind==WM_KEYUP);
  calls.messages.clear();calls.attempts=0;
  { v::WindowInput input(calls);input.dispatch(button("right",true),1);calls.valid=false;
    CHECK_THROWS_AS(input.dispatch(cursor(1,2),1),std::exception);CHECK(calls.messages.size()==1); }
  calls.valid=true;calls.messages.clear();calls.attempts=0;calls.fail_at=2;
  { v::WindowInput input(calls);input.dispatch(button("middle",true),1);
    CHECK_THROWS_AS(input.dispatch(key("home",true),1),std::exception);CHECK(input.info().held==0);
    REQUIRE(calls.messages.size()==3);CHECK(calls.messages[1].kind==WM_MBUTTONUP&&calls.messages[2].kind==WM_KEYUP); }
  calls.fail_at=0;
}
TEST_CASE("Window input: invalid coordinates dimensions wheel and names release previous holds") {
  Calls calls;v::WindowInput input(calls);input.dispatch(button("left",true),1);
  CHECK_THROWS_AS(input.dispatch(cursor(-1,0),1),std::exception);CHECK(input.info().held==0);
  CHECK_THROWS_AS(input.dispatch(cursor(3840,0),1),std::exception);
  CHECK_THROWS_AS(input.dispatch({"wheel","",0,9},1),std::exception);
  CHECK_THROWS_AS(input.dispatch({"wheel","",0,0},1),std::exception);
  CHECK_THROWS_AS(input.dispatch(button("extra",true),1),std::exception);
  CHECK_THROWS_AS(input.dispatch({"focus"},1),std::exception);
  calls.dimension=false;CHECK_THROWS_AS(input.dispatch(cursor(0,0),1),std::exception);
  calls.dimension=true;calls.coordinates=false;CHECK_THROWS_AS(input.dispatch({"wheel","",0,1},1),std::exception);
}
TEST_CASE("Window input: an idle Session refuses before discovering or posting to a window") {
  Calls calls;v::Session session(std::filesystem::current_path(),calls);
  CHECK_THROWS_AS(session.window_input(cursor(0,0)),std::exception);CHECK(calls.messages.empty()&&calls.finds==0);
  session.cancel_window_input();CHECK(calls.messages.empty());
}
TEST_CASE("Window input: Session Exit and renderer failure release every owned press") {
  wchar_t path[32768]{};GetModuleFileNameW(nullptr,path,static_cast<DWORD>(std::size(path)));
  const auto folder=std::filesystem::path(path).parent_path();
  const auto runtime=LoadLibraryW((folder/L"nlvr_test_runtime.dll").c_str());REQUIRE(runtime);
  const auto api=LoadLibraryW((folder/L"openvr_api.dll").c_str());REQUIRE(api);
  const auto reset_api=reinterpret_cast<FakeReset>(GetProcAddress(api,"nlvr_fake_reset"));REQUIRE(reset_api);
  const auto reset=reinterpret_cast<FakeReset>(GetProcAddress(runtime,"nlvr_fake_reset"));REQUIRE(reset);
  const auto wait=[](const auto& done) {
    const auto end=std::chrono::steady_clock::now()+std::chrono::seconds(3);
    while(!done()&&std::chrono::steady_clock::now()<end) std::this_thread::sleep_for(std::chrono::milliseconds(1));
    REQUIRE(done());
  };
  for(bool failure:{false,true}) {
    reset();reset_api();Calls calls;v::Session session(folder,calls);v::Options o;
    o.openvr_dll=folder/L"openvr_api.dll";o.runtime_dll=folder/L"nlvr_test_runtime.dll";o.manifest=NL_VR_MANIFEST;o.no_submit=true;
    std::string error;REQUIRE(session.start(o,error));wait([&] { return session.state().first=="running"; });
    REQUIRE(session.begin_frame());session.window_input(button("left",true));session.window_input(key("enter",true));
    if(failure) {
      // The fake runtime's own stop export changes its reported state without touching OpenVR.
      reinterpret_cast<decltype(&rtxvr_Stop)>(GetProcAddress(runtime,"rtxvr_Stop"))();
      CHECK(session.state().first=="failed");
    }
    else session.stop();
    wait([&] { return session.state().first=="off"||session.state().first=="failed"; });
    // The failure phase may be observable before the worker cleanup; fail() posts releases itself.
    REQUIRE(calls.messages.size()>=4);CHECK(calls.messages[2].kind==WM_LBUTTONUP&&calls.messages[3].kind==WM_KEYUP);
    CHECK_THROWS_AS(session.window_input(character('x')),std::exception);
  }
  FreeLibrary(api);FreeLibrary(runtime);
}
