#include "discovery.h"
#include "openvr_session.h"
#include "vulkan_scene.h"
#include <array>
#include <chrono>
#include <fstream>
#include <iostream>
#include <memory>

namespace nl::vrprobe {
namespace {
using Clock = std::chrono::steady_clock;
double seconds(Clock::time_point a, Clock::time_point b) { return std::chrono::duration<double>(b - a).count(); }
std::string utf8(const wchar_t* text) {
  const int size = WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, text, -1, nullptr, 0, nullptr, nullptr);
  if (!size) throw std::runtime_error("invalid Unicode argument");
  std::string value(static_cast<std::size_t>(size), '\0');
  WideCharToMultiByte(CP_UTF8, WC_ERR_INVALID_CHARS, text, -1, value.data(), size, nullptr, nullptr);
  value.pop_back(); return value;
}
Json run_loop(Session& session, const Options& options) {
  std::unique_ptr<VulkanScene> scene;
  if (options.submit || options.command == "submit") {
    scene = std::make_unique<VulkanScene>(session); scene->prepare();
  }
  const auto headset = session.info();
  const auto before = cumulative_stats(session.compositor);
  std::array<vr::TrackedDevicePose_t, vr::k_unMaxTrackedDeviceCount> poses{};
  std::uint64_t waits = 0, valid = 0, accepted = 0, errors = 0, wait_errors = 0, timing_unavailable = 0;
  Moments intervals, blocking, bin_intervals, bin_blocking, gpu, compositor_gpu, cpu, submits;
  Json::Array samples, events, error_log;
  auto begin = Clock::now(), previous = begin, bin_begin = begin;
  std::uint64_t bin_waits = 0;
  bool quit = false, have_timing_index = false;
  uint32_t timing_index = 0;
  std::string failure;
  log_event(object({{"event", Json::make_string("measurement_begin")}, {"seconds", number(options.seconds)},
    {"submitting", Json::make_bool(scene != nullptr)}, {"pose_flag", Json::make_bool(options.pose)}, {"headset", headset}}));
  try {
    while (seconds(begin, Clock::now()) < options.seconds && !quit) {
      const auto wait_begin = Clock::now();
      const auto error = session.compositor->WaitGetPoses(poses.data(), static_cast<uint32_t>(poses.size()), nullptr, 0);
      const auto now = Clock::now();
      const double blocked_ms = seconds(wait_begin, now) * 1000;
      blocking.add(blocked_ms); bin_blocking.add(blocked_ms);
      if (waits) {
        const double interval_ms = seconds(previous, now) * 1000;
        intervals.add(interval_ms); bin_intervals.add(interval_ms);
      }
      previous = now; ++waits; ++bin_waits;
      if (poses[0].bPoseIsValid) ++valid;
      if (error != vr::VRCompositorError_None) {
        ++wait_errors;
        auto item = object({{"event", Json::make_string("wait_error")}, {"code", number(error)},
          {"seconds", number(seconds(begin, now))}});
        log_event(item); error_log.push_back(std::move(item));
      }
      if (scene) {
        const auto submit_begin = Clock::now();
        scene->frame(waits, poses[0], options.pose, accepted, errors, error_log);
        submits.add(seconds(submit_begin, Clock::now()) * 1000);
      }
      vr::Compositor_FrameTiming timing{}; timing.m_nSize = sizeof(timing);
      const bool has_timing = session.compositor->GetFrameTiming(&timing);
      if (!has_timing) ++timing_unavailable;
      if (has_timing && (!have_timing_index || timing_index != timing.m_nFrameIndex)) {
        have_timing_index = true; timing_index = timing.m_nFrameIndex;
        gpu.add(timing.m_flPreSubmitGpuMs); compositor_gpu.add(timing.m_flCompositorRenderGpuMs);
        cpu.add(timing.m_flClientFrameIntervalMs);
      }
      vr::VREvent_t event{};
      while (session.system->PollNextEvent(&event, sizeof(event))) {
        const bool process_event = event.eventType == vr::VREvent_ProcessConnected ||
          event.eventType == vr::VREvent_ProcessDisconnected || event.eventType == vr::VREvent_Quit ||
          event.eventType == vr::VREvent_ProcessQuit || event.eventType == vr::VREvent_QuitAcknowledged ||
          event.eventType == vr::VREvent_InputFocusChanged;
        auto item = object({{"event", Json::make_string(session.system->GetEventTypeNameFromEnum(static_cast<vr::EVREventType>(event.eventType)))},
          {"type", number(event.eventType)}, {"device", number(event.trackedDeviceIndex)},
          {"process_pid", process_event ? number(event.data.process.pid) : Json{}},
          {"process_old_pid", process_event ? number(event.data.process.oldPid) : Json{}},
          {"process_forced", process_event ? Json::make_bool(event.data.process.bForced) : Json{}},
          {"age_seconds", number(event.eventAgeSeconds)}, {"seconds", number(seconds(begin, Clock::now()))}});
        log_event(item); events.push_back(std::move(item));
        if (event.eventType == vr::VREvent_Quit) {
          // Acknowledge the application's exit, never ask SteamVR to quit.
          session.system->AcknowledgeQuit_Exiting(); quit = true;
        }
      }
      const auto sample_now = Clock::now();
      if (seconds(bin_begin, sample_now) >= 1 || seconds(begin, sample_now) >= options.seconds || quit) {
        auto sample = object({{"event", Json::make_string("sample")}, {"seconds", number(seconds(begin, sample_now))},
          {"window_seconds", number(seconds(bin_begin, sample_now))}, {"waits", number(static_cast<double>(bin_waits))},
          {"wait_hz", number(static_cast<double>(bin_waits) / seconds(bin_begin, sample_now))},
          {"interval_ms", bin_intervals.json()}, {"blocking_ms", bin_blocking.json()},
          {"devices", device_state(session, poses.data())}, {"cumulative", cumulative_stats(session.compositor)},
          {"timing_available", Json::make_bool(has_timing)}, {"timing_index", number(timing.m_nFrameIndex)},
          {"timing_gpu_ms", number(timing.m_flPreSubmitGpuMs)}, {"timing_reprojection_flags", number(timing.m_nReprojectionFlags)}});
        log_event(sample); samples.push_back(std::move(sample));
        bin_begin = sample_now; bin_waits = 0; bin_intervals = {}; bin_blocking = {};
      }
    }
  } catch (const std::exception& e) { failure = e.what(); log_event(object({{"event", Json::make_string("measurement_error")}, {"error", Json::make_string(failure)}})); }
  const double elapsed = seconds(begin, Clock::now());
  const auto after = cumulative_stats(session.compositor);
  auto result = object({{"command", Json::make_string(options.command)}, {"headset", headset},
    {"completed", Json::make_bool(elapsed >= options.seconds && !quit && failure.empty())},
    {"success", Json::make_bool(elapsed >= options.seconds && !quit && failure.empty() && !errors && !wait_errors)},
    {"requested_seconds", number(options.seconds)}, {"elapsed_seconds", number(elapsed)},
    {"waits", number(static_cast<double>(waits))}, {"wait_hz", number(static_cast<double>(waits) / elapsed)},
    {"interval_ms", intervals.json()}, {"blocking_ms", blocking.json()},
    {"valid_pose_frames", number(static_cast<double>(valid))}, {"invalid_pose_frames", number(static_cast<double>(waits - valid))},
    {"wait_errors", number(static_cast<double>(wait_errors))}, {"eye_submits_accepted", number(static_cast<double>(accepted))},
    {"compositor_errors", number(static_cast<double>(errors))}, {"submit_cpu_ms", submits.json()},
    {"timing_gpu_ms", gpu.json()}, {"timing_compositor_gpu_ms", compositor_gpu.json()},
    {"timing_client_interval_ms", cpu.json()}, {"timing_unavailable", number(static_cast<double>(timing_unavailable))},
    {"cumulative_before", before}, {"cumulative_after", after}, {"quit_event", Json::make_bool(quit)},
    {"error", Json::make_string(failure)}, {"samples", Json::make_array(std::move(samples))},
    {"events", Json::make_array(std::move(events))}, {"errors", Json::make_array(std::move(error_log))}});
  // Keep Vulkan alive across VR_Shutdown (also on exceptional paths in VulkanScene's Impl).
  session.shutdown(); scene.reset();
  return result;
}
void write_result(const Json& result, const std::filesystem::path& path) {
  const auto data = dump(result) + '\n';
  if (path.empty()) std::cout << data;
  else {
    if (!path.parent_path().empty()) std::filesystem::create_directories(path.parent_path());
    std::ofstream file(path, std::ios::binary | std::ios::trunc);
    file << data;
    if (!file) throw std::runtime_error("cannot write result: " + path.string());
  }
}
}  // namespace
}  // namespace nl::vrprobe

int wmain(int argc, wchar_t* argv[]) {
  using namespace nl::vrprobe;
  Options options;
  try {
    std::vector<std::string> args;
    for (int i = 1; i < argc; ++i) args.push_back(utf8(argv[i]));
    options = arguments(args);
  } catch (const std::exception& e) {
    std::cout << dump(object({{"error", Json::make_string(e.what())}, {"phase", Json::make_string("arguments")}})) << '\n';
    return 2;
  }
  try {
    if (options.help) {
      std::cout << "vrprobe info [--out FILE]\n"
        "vrprobe extensions --dll FILE [--runtime-log FILE] [--out FILE]\n"
        "vrprobe submit --dll FILE --seconds N [--pose] [--out FILE]\n"
        "vrprobe idle --dll FILE --minutes N [--submit] [--out FILE]\n"
        "All OpenVR sessions take the shared out/vr/vr.lock. No SteamVR settings are changed.\n";
      return 0;
    }
    if (options.command == "info") { write_result(discover_steamvr(), options.out); return 0; }
#if !NL_VR_HAS_VULKAN
    if (options.command == "extensions" || options.command == "submit" || options.submit)
      throw std::runtime_error("Vulkan commands compiled out: set NL_VR_VULKAN_INCLUDE_DIR to Vulkan headers");
#endif
    // Parse a supplied log before touching the headset, to keep input errors offline.
    RuntimeExtensions runtime;
    if (!options.runtime_log.empty()) runtime = runtime_extensions(read_text(options.runtime_log));
    VrLock lock;
    Session session(options.dll); session.start();
    Json result;
    if (options.command == "extensions") {
      const auto headset = session.info();
      VulkanScene vulkan(session);
      result = object({{"headset", headset}, {"extensions", vulkan.extensions(runtime)}});
    } else result = run_loop(session, options);
    write_result(result, options.out);
    if (const auto* success = result.find("success")) return success->as_bool() ? 0 : 1;
    const auto* failure = result.find("error");
    return failure && !failure->as_string().empty() ? 1 : 0;
  } catch (const std::exception& e) {
    const auto result = object({{"error", Json::make_string(e.what())}, {"command", Json::make_string(options.command)}});
    log_event(result);
    try { write_result(result, options.out); } catch (...) { std::cout << dump(result) << '\n'; }
    return 1;
  }
}
