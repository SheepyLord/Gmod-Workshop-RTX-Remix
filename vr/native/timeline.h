// SPDX-License-Identifier: MIT
#pragma once
#include "pose_math.h"
#include <filesystem>
#include <map>
#include <string>
#include <vector>

namespace nl::vr {
struct Action {
  bool active=false, state=false, changed=false;
  Vec3 value{};
  std::array<float,5> curls{};
  int error=0;
};
using Actions=std::map<std::string,Action,std::less<>>;
struct ScriptPose { Vec3 pos{}; Quat rot{}; };
struct ScriptStep { double time=0; std::array<ScriptPose,3> poses{}; Actions actions; };
struct ScriptSample {
  double time=0;
  std::size_t step=0;
  bool ended=false;
  std::array<Pose,3> poses{};
  Actions actions;
};
class Timeline {
 public:
  double quit_at=-1;
  static Timeline parse(std::string_view text);
  static Timeline load(const std::filesystem::path& path);
  ScriptSample sample(double seconds) const;
 private:
  std::vector<ScriptStep> steps_;
};
}
