#pragma once
#include "openvr_session.h"
#include <memory>
namespace nl::vrprobe {
// Shutdown the OpenVR client before releasing this object's Vulkan resources.
class VulkanScene {
 public:
  explicit VulkanScene(Session& session);
  ~VulkanScene();
  VulkanScene(const VulkanScene&) = delete;
  VulkanScene& operator=(const VulkanScene&) = delete;
  Json extensions(const RuntimeExtensions& runtime);
  void prepare();
  void frame(std::uint64_t index, const vr::TrackedDevicePose_t& pose, bool with_pose,
             std::uint64_t& accepted, std::uint64_t& errors, Json::Array& error_log);
 private:
  struct Impl;
  std::unique_ptr<Impl> impl_;
};
}  // namespace nl::vrprobe
