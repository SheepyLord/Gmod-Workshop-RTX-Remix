// SPDX-License-Identifier: MIT
#pragma once
#include "timeline.h"
#include "window_input.h"
#include "controller_frames.h"
#include <openvr.h>
#include <chrono>
#include <memory>
#include <optional>

namespace nl::vr {
struct Options {
  float scale=39.37007874f, render_scale=1;
  bool no_submit=false;
  bool simulate=false;
  std::filesystem::path timeline, openvr_dll, manifest;
  // Native test hosts only. Lua cannot choose a different renderer DLL.
  std::filesystem::path runtime_dll;
};
struct Probe {
  std::optional<uint32_t> runtime_api;
  std::filesystem::path openvr_dll;
  bool steamvr_installed=false, steamvr_running=false;
};
struct Event { std::string type; uint32_t code=0, device=0; std::string text; };
struct OverlayInfo {
  bool visible=false;
  float width=0;
  uint32_t texture_width=0,texture_height=0;
  int transform_error=0,texture_error=0,origin=0;
  rtxvr_Matrix34 transform{}; // OpenVR tracking basis, exactly as the compositor reports it.
  float alpha=1;
  Vec3 color{1,1,1};
  uint32_t sort_order=0;
  bool window=false,simulated=false;
};
struct Frame {
  uint64_t sequence=0;
  std::array<Pose,3> poses{};
  std::array<ControllerFrames,2> controllers{};
  std::array<Pose,::vr::k_unMaxTrackedDeviceCount> devices{};
  float ipd=0, seconds_to_photons=0;
  double sample_seconds=0, predicted_seconds=0, base_seconds=0;
  double wait_ms=0;
  double completion_wait_ms=0;
};
struct Info {
  WindowInputInfo window_input;
  bool sdk_ready=false;
  bool simulated=false,keyboard_visible=false,overlay_window_supported=false;
  bool openvr_loaded=false;
  bool simulation_high_resolution=false;
  uint64_t haptic_requests=0,binding_ui_requests=0;
  std::string keyboard_text;
  std::string model, tracking, input_detail, frame_error;
  float refresh=0, ipd=0;
  std::array<rtxvr_Eye,2> eyes{};
  uint32_t eye_width=0,eye_height=0;
  rtxvr_Status runtime{};
  bool timing_valid=false;
  bool left_tracked=false,right_tracked=false;
  ::vr::Compositor_FrameTiming timing{};
  ::vr::Compositor_CumulativeStats cumulative{};
  int activity=0;
  double prediction_seconds=0;
  double completion_wait_ms=0,completion_wait_max_ms=0;
  uint64_t completion_wait_timeouts=0,completion_wait_count=0;
  uint32_t completion_wait_polls=0;
  bool completion_wait_high_resolution=false;
};
class Session {
 public:
  explicit Session(std::filesystem::path module_folder,WindowCalls& window_calls=system_window_calls());
  ~Session();
  Session(const Session&)=delete;
  Session& operator=(const Session&)=delete;
  Probe probe() const;
  std::filesystem::path data_path(const std::string& name,bool capture) const;
  bool start(const Options& options,std::string& error);
  void stop();
  std::pair<std::string,std::string> state() const;
  std::optional<Frame> begin_frame();
  void set_camera(uint64_t sequence,Vec3 origin,Vec3 angles);
  Info info() const;
  Actions actions() const;
  SkeletonSample skeleton(const std::string& hand,const std::string& reference);
  int haptic(const std::string& hand,float seconds,float frequency,float amplitude);
  void show_keyboard(const std::string& text,const std::string& description,bool multiline,uint32_t maxchars);
  void hide_keyboard();
  void window_input(const WindowInputEvent& event);
  void cancel_window_input() noexcept;
  int open_binding_ui();
  uint64_t overlay_create(const std::string& key,const std::string& name);
  void overlay_source(uint64_t handle,uint32_t width,uint32_t height);
  void overlay_attach(uint64_t handle,const std::string& device,Vec3 pos,Vec3 angles,float width);
  void overlay_show(uint64_t handle,bool shown);
  void overlay_alpha(uint64_t handle,float alpha);
  void overlay_sort_order(uint64_t handle,uint32_t order);
  void overlay_color(uint64_t handle,Vec3 color);
  bool overlay_window(uint64_t handle,bool enable,std::string& error);
  void overlay_destroy(uint64_t handle);
  bool overlay_visible(uint64_t handle) const;
  OverlayInfo overlay_info(uint64_t handle) const;
  std::vector<Event> events();
  // V6's ladder step. The runtime validates it and applies it on its render thread.
  struct Quality {
    float render_scale=1;
    int dlss=1,min_bounces=1,max_bounces=4;
    bool volumetrics=true,fine_clouds=true,stereo=false;
  };
  bool set_quality(const Quality& quality,std::string& error);
  void capture(const std::filesystem::path& folder,uint32_t what);
  std::optional<ScriptSample> test_state() const;
 private:
  struct Impl;
  std::unique_ptr<Impl> impl_;
};
}
