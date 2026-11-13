// SPDX-License-Identifier: MIT
#pragma once
#include <array>
#include <cstdint>
#include <string>

namespace nl::vr {
// The platform boundary is injectable: offline tests never post to a real window.
using GameWindow=uintptr_t;
struct WindowCalls {
  virtual ~WindowCalls()=default;
  virtual GameWindow find()=0;
  virtual bool owned(GameWindow window)=0;
  virtual bool bounds(GameWindow window,int& width,int& height)=0;
  virtual bool screen(GameWindow window,int& x,int& y)=0;
  virtual bool foreground(GameWindow window)=0;
  virtual unsigned scan(unsigned key)=0;
  virtual bool post(GameWindow window,unsigned message,uintptr_t word,intptr_t value)=0;
};
WindowCalls& system_window_calls();
struct WindowInputEvent {
  std::string kind,name;
  int x=0,y=0;
  bool down=false;
  uint32_t character=0;
};
struct WindowInputInfo {
  bool owned=false,foreground=false;
  int width=0,height=0,x=0,y=0;
  uint32_t held=0,frame_messages=0;
  uint64_t posted=0,failures=0;
};
class WindowInput {
 public:
  static constexpr unsigned frame_limit=64;
  explicit WindowInput(WindowCalls& calls=system_window_calls()):calls_(calls) {}
  ~WindowInput() { release(); }
  void dispatch(const WindowInputEvent& event,uint64_t frame);
  void release() noexcept;
  WindowInputInfo info();
 private:
  WindowCalls& calls_;
  GameWindow window_=0;
  uint64_t frame_=0,posted_=0,failures_=0;
  unsigned used_=0;
  int x_=0,y_=0;
  std::array<bool,3> buttons_{};
  std::array<bool,11> keys_{};
  unsigned flags() const;
  void post(unsigned message,uintptr_t word,intptr_t value);
};
}
