// SPDX-License-Identifier: MIT
#pragma once
#include "timeline.h"
#include <openvr.h>
#include <chrono>
#include <memory>
#include <optional>

namespace nl::vr {
struct Options {
  float scale=39.37007874f, render_scale=1;
  bool no_submit=false;
  std::filesystem::path timeline, openvr_dll, manifest;
  // Native test hosts only. Lua cannot choose a different renderer DLL.
  std::filesystem::path runtime_dll;
};
struct Probe {
  std::optional<uint32_t> runtime_api;
  std::filesystem::path openvr_dll;
  bool steamvr_installed=false, steamvr_running=false;
};
struct Event { std::string type; uint32_t code=0, device=0; };
struct OverlayInfo {
  bool visible=false;
  float width=0;
  uint32_t texture_width=0,texture_height=0;
  int transform_error=0,texture_error=0,origin=0;
  rtxvr_Matrix34 transform{}; // OpenVR tracking basis, exactly as the compositor reports it.
};
struct Frame {
  uint64_t sequence=0;
  std::array<Pose,3> poses{};
  std::array<Pose,::vr::k_unMaxTrackedDeviceCount> devices{};
  float ipd=0, seconds_to_photons=0;
  double sample_seconds=0, predicted_seconds=0, base_seconds=0;
  double wait_ms=0;
  double completion_wait_ms=0;
};
struct Info {
  bool sdk_ready=false;
  std::string model, tracking, input_detail, frame_error;
  float refresh=0, ipd=0;
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
  explicit Session(std::filesystem::path module_folder);
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
  int haptic(const std::string& hand,float seconds,float frequency,float amplitude);
  uint64_t overlay_create(const std::string& key,const std::string& name);
  void overlay_source(uint64_t handle,uint32_t width,uint32_t height);
  void overlay_attach(uint64_t handle,const std::string& device,Vec3 pos,Vec3 angles,float width);
  void overlay_show(uint64_t handle,bool shown);
  void overlay_alpha(uint64_t handle,float alpha);
  void overlay_destroy(uint64_t handle);
  bool overlay_visible(uint64_t handle) const;
  OverlayInfo overlay_info(uint64_t handle) const;
  std::vector<Event> events();
  void capture(const std::filesystem::path& folder,uint32_t what);
  std::optional<ScriptSample> test_state() const;
 private:
  struct Impl;
  std::unique_ptr<Impl> impl_;
};
}
