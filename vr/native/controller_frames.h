// SPDX-License-Identifier: MIT
#pragma once
#include "pose_math.h"
#include <openvr.h>
#include <string>
#include <chrono>

namespace nl::vr {
struct SkeletonSample {
  bool valid=false;
  int error=0;
  std::string source;
  std::array<Pose,31> bones{};
};
SkeletonSample read_skeleton(::vr::IVRInput* input,::vr::VRActionHandle_t action,const std::string& reference);
// Local transforms in Source tracking axes/metres. The frame's device pose stays raw.
struct ControllerFrames {
  uint32_t device=::vr::k_unTrackedDeviceIndexInvalid, revision=0;
  std::string model, source="raw", detail;
  bool valid=false, skeleton=false;
  Pose aim, hand, wrist;
  Pose component_wrist;
  Vec3 skeleton_finger{}, skeleton_normal{};
};
class ControllerFrameCache {
 public:
  void reset();
  void invalidate(uint32_t device);
  void refresh(uint32_t device);
  const ControllerFrames& read(unsigned side,uint32_t device,::vr::IVRSystem* system,
    ::vr::IVRRenderModels* models,::vr::IVRInput* input,::vr::VRInputValueHandle_t path,
    ::vr::VRActionHandle_t skeleton);
 private:
  std::array<ControllerFrames,2> values_{};
  uint32_t revision_=0;
  std::array<std::chrono::steady_clock::time_point,2> retry_at_{};
  std::array<unsigned,2> failures_{};
};
bool rigid(const rtxvr_Matrix34& matrix);
ControllerFrames component_frames(const rtxvr_Matrix34& tip,const rtxvr_Matrix34& wrist);
bool skeleton_frames(ControllerFrames& frames,const ::vr::VRBoneTransform_t* bones,uint32_t count,unsigned side);
Pose apply_frame(const Pose& raw,const Pose& local);
}
