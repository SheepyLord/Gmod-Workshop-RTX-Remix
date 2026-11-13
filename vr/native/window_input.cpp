// SPDX-License-Identifier: MIT
#include "window_input.h"
#include <windows.h>
#include <algorithm>
#include <cwchar>
#include <stdexcept>
#include <string_view>

namespace nl::vr {
namespace {
void need(bool value,const char* error) { if(!value) throw std::runtime_error(error); }
bool game_window(HWND window) {
  DWORD process=0;GetWindowThreadProcessId(window,&process);
  if(process!=GetCurrentProcessId()||!IsWindow(window)||GetWindow(window,GW_OWNER)||
      (GetWindowLongPtrW(window,GWL_STYLE)&WS_CHILD)) return false;
  wchar_t name[128]{};
  return GetClassNameW(window,name,static_cast<int>(std::size(name)))&&std::wcscmp(name,L"Valve001")==0;
}
struct SystemCalls final:WindowCalls {
  GameWindow find() override {
    struct Search { HWND window=nullptr;bool ambiguous=false; } search;
    EnumWindows([](HWND window,LPARAM parameter)->BOOL {
      auto& result=*reinterpret_cast<Search*>(parameter);
      if(game_window(window)) {
        if(result.window) result.ambiguous=true;
        else result.window=window;
      }
      return TRUE;
    },reinterpret_cast<LPARAM>(&search));
    return search.ambiguous?0:reinterpret_cast<GameWindow>(search.window);
  }
  bool owned(GameWindow window) override { return window&&game_window(reinterpret_cast<HWND>(window)); }
  bool bounds(GameWindow window,int& width,int& height) override {
    RECT r{};if(!GetClientRect(reinterpret_cast<HWND>(window),&r)) return false;
    width=r.right-r.left;height=r.bottom-r.top;return width>0&&height>0&&width<=32767&&height<=32767;
  }
  bool screen(GameWindow window,int& x,int& y) override {
    POINT p{x,y};if(!ClientToScreen(reinterpret_cast<HWND>(window),&p)||p.x<-32768||p.x>32767||p.y<-32768||p.y>32767) return false;
    x=p.x;y=p.y;return true;
  }
  bool foreground(GameWindow window) override { return GetForegroundWindow()==reinterpret_cast<HWND>(window); }
  unsigned scan(unsigned key) override { return MapVirtualKeyW(key,MAPVK_VK_TO_VSC); }
  bool post(GameWindow window,unsigned message,uintptr_t word,intptr_t value) override {
    // Recheck even during failure/Exit cleanup. A recycled HWND must never receive input.
    return owned(window)&&PostMessageW(reinterpret_cast<HWND>(window),message,word,value)!=0;
  }
};
constexpr unsigned button_down[]={WM_LBUTTONDOWN,WM_RBUTTONDOWN,WM_MBUTTONDOWN};
constexpr unsigned button_up[]={WM_LBUTTONUP,WM_RBUTTONUP,WM_MBUTTONUP};
constexpr unsigned button_flags[]={MK_LBUTTON,MK_RBUTTON,MK_MBUTTON};
constexpr std::string_view button_names[]={"left","right","middle"};
constexpr unsigned key_codes[]={VK_RETURN,VK_BACK,VK_DELETE,VK_ESCAPE,VK_TAB,VK_LEFT,VK_RIGHT,VK_UP,VK_DOWN,VK_HOME,VK_END};
constexpr std::string_view key_names[]={"enter","backspace","delete","escape","tab","left","right","up","down","home","end"};
template<std::size_t N> unsigned lookup(const std::string& value,const std::string_view (&names)[N]) {
  for(unsigned i=0;i<N;++i) if(value==names[i]) return i;
  throw std::runtime_error("WindowInput: unsupported button or key");
}
intptr_t position(int x,int y) { return static_cast<intptr_t>(MAKELONG(static_cast<WORD>(x),static_cast<WORD>(y))); }
intptr_t key_data(WindowCalls& calls,unsigned key,bool up) {
  const bool extended=key==VK_DELETE||(key>=VK_END&&key<=VK_DOWN);
  const auto value=1u|((calls.scan(key)&0xffu)<<16)|(extended?1u<<24:0u)|(up?0xc0000000u:0u);
  return static_cast<intptr_t>(value);
}
}
WindowCalls& system_window_calls() { static SystemCalls calls;return calls; }
unsigned WindowInput::flags() const {
  unsigned value=0;for(unsigned i=0;i<buttons_.size();++i) if(buttons_[i]) value|=button_flags[i];return value;
}
void WindowInput::post(unsigned message,uintptr_t word,intptr_t value) {
  need(used_<frame_limit,"WindowInput: 64 posted messages per VR frame exceeded");
  ++used_;
  need(calls_.post(window_,message,word,value),"WindowInput: posting to the owned game window failed");++posted_;
}
void WindowInput::dispatch(const WindowInputEvent& event,uint64_t frame) {
  try {
    need(frame!=0,"WindowInput: acquire a VR frame first");
    if(frame!=frame_) { frame_=frame;used_=0; }
    if(!window_) window_=calls_.find();
    need(window_&&calls_.owned(window_),"WindowInput: this process's unique Valve001 game window is unavailable");
    int width=0,height=0;
    need(calls_.bounds(window_,width,height),"WindowInput: game client dimensions unavailable or outside 1..32767");
    if(event.kind=="cursor") {
      need(event.x>=0&&event.y>=0&&event.x<width&&event.y<height,"WindowInput: cursor outside the game client");
      x_=event.x;y_=event.y;post(WM_MOUSEMOVE,flags(),position(x_,y_));
    } else if(event.kind=="button") {
      const auto i=lookup(event.name,button_names);
      if(buttons_[i]==event.down) return;
      // A failed post must still attempt its matching release.
      if(event.down) buttons_[i]=true;
      post(event.down?button_down[i]:button_up[i],event.down?flags():flags()&~button_flags[i],position(x_,y_));
      buttons_[i]=event.down;
    } else if(event.kind=="wheel") {
      need(event.y>=-8&&event.y<=8&&event.y!=0,"WindowInput: wheel steps must be -8..8 and nonzero");
      int x=x_,y=y_;need(calls_.screen(window_,x,y),"WindowInput: wheel screen coordinates unavailable");
      post(WM_MOUSEWHEEL,MAKELONG(static_cast<WORD>(flags()),static_cast<WORD>(event.y*WHEEL_DELTA)),position(x,y));
    } else if(event.kind=="char") {
      const auto cp=event.character;
      need(cp>=32&&cp<=0x10ffff&&!(cp>=0xd800&&cp<=0xdfff)&&cp!=127,"WindowInput: expected a printable Unicode scalar");
      need(used_+(cp>0xffff?2u:1u)<=frame_limit,"WindowInput: 64 posted messages per VR frame exceeded");
      if(cp>0xffff) { post(WM_CHAR,0xd800+((cp-0x10000)>>10),1);post(WM_CHAR,0xdc00+((cp-0x10000)&0x3ff),1); }
      else post(WM_CHAR,cp,1);
    } else if(event.kind=="key") {
      const auto i=lookup(event.name,key_names);if(keys_[i]==event.down) return;
      if(event.down) keys_[i]=true;
      post(event.down?WM_KEYDOWN:WM_KEYUP,key_codes[i],key_data(calls_,key_codes[i],!event.down));keys_[i]=event.down;
    } else if(event.kind=="release") release();
    else throw std::runtime_error("WindowInput: unsupported kind (cursor, button, wheel, char, key, release)");
  } catch(...) { ++failures_;release();throw; }
}
void WindowInput::release() noexcept {
  // Safety releases bypass the frame budget, bounded by three buttons and eleven keys.
  // Retain a held bit on a failed post, so cleanup/retry attempts it again.
  try {
    if(!window_||!calls_.owned(window_)) { buttons_={};keys_={};window_=0;return; }
    for(unsigned i=0;i<buttons_.size();++i) if(buttons_[i]) {
      if(calls_.post(window_,button_up[i],flags()&~button_flags[i],position(x_,y_))) { buttons_[i]=false;++posted_; }
    }
    for(unsigned i=0;i<keys_.size();++i) if(keys_[i]) {
      if(calls_.post(window_,WM_KEYUP,key_codes[i],key_data(calls_,key_codes[i],true))) { keys_[i]=false;++posted_; }
    }
  } catch(...) {} // No exceptions may escape the module's unload/worker cleanup.
}
WindowInputInfo WindowInput::info() {
  WindowInputInfo result;result.owned=window_&&calls_.owned(window_);
  if(result.owned) { result.foreground=calls_.foreground(window_);calls_.bounds(window_,result.width,result.height); }
  result.x=x_;result.y=y_;result.frame_messages=used_;result.posted=posted_;result.failures=failures_;
  result.held=static_cast<unsigned>(std::count(buttons_.begin(),buttons_.end(),true)+std::count(keys_.begin(),keys_.end(),true));
  return result;
}
}
