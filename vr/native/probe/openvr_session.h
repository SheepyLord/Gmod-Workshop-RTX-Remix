#pragma once
#include "probe_data.h"
#include <Windows.h>
#include <openvr.h>

namespace nl::vrprobe {
class VrLock {
 public:
  VrLock();
  ~VrLock();
  VrLock(const VrLock&) = delete;
  VrLock& operator=(const VrLock&) = delete;
 private:
  HANDLE handle_ = INVALID_HANDLE_VALUE;
};
class Session {
 public:
  explicit Session(const std::filesystem::path& dll);
  ~Session();
  Session(const Session&) = delete;
  Session& operator=(const Session&) = delete;
  void start();
  void shutdown();
  vr::IVRSystem* system = nullptr;
  vr::IVRCompositor* compositor = nullptr;
  std::string property(vr::TrackedDeviceIndex_t device, vr::ETrackedDeviceProperty name) const;
  Json info() const;
 private:
  HMODULE library_ = nullptr;
  bool initialized_ = false;
  using Init = uint32_t (__cdecl*)(vr::EVRInitError*, vr::EVRApplicationType, const char*);
  using Shutdown = void (__cdecl*)();
  using Interface = void* (__cdecl*)(const char*, vr::EVRInitError*);
  using ErrorName = const char* (__cdecl*)(vr::EVRInitError);
  Init init_ = nullptr;
  Shutdown shutdown_ = nullptr;
  Interface interface_ = nullptr;
  ErrorName error_name_ = nullptr, error_description_ = nullptr;
};
std::vector<std::string> required_instance(vr::IVRCompositor* compositor);
std::vector<std::string> required_device(vr::IVRCompositor* compositor, VkPhysicalDevice_T* device);
Json cumulative_stats(vr::IVRCompositor* compositor);
Json device_state(Session& session, const vr::TrackedDevicePose_t* poses);
void log_event(const Json& event);
}  // namespace nl::vrprobe
