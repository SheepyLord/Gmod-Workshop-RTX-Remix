// SPDX-License-Identifier: MIT
#pragma once
#include "include/rtxvr_api.h"
#include "controller_frames.h"
#include <filesystem>
#include <string>
namespace nl::vr {
struct SimDevice {
  std::string model,tracking;
  uint32_t width=0,height=0;
  float refresh=0,ipd=0;
  rtxvr_Eye eyes[2]{};
  std::array<ControllerFrames,2> controllers{};
  static SimDevice load(const std::filesystem::path& path);
};
}
