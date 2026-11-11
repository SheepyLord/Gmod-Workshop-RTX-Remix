// SPDX-License-Identifier: MIT
#pragma once
#include "include/rtxvr_api.h"
#include <array>
#include <cmath>

namespace nl::vr {
struct Vec3 { float x=0, y=0, z=0; };
struct Quat { double x=0, y=0, z=0, w=1; };
struct Pose {
  bool valid=false;
  Vec3 pos{}, ang{}, vel{}, angvel{}; // metres, Source axes; ang degrees, angvel radians/s
};
Vec3 operator+(Vec3 a, Vec3 b);
Vec3 operator-(Vec3 a, Vec3 b);
Vec3 operator*(Vec3 a, double b);
bool finite(Vec3 v);
Quat normalise(Quat q);
Quat slerp(Quat a, Quat b, double t);
Quat rotation(Vec3 angles);
Vec3 angles(Quat q);
rtxvr_Matrix34 source_matrix(Vec3 pos, Quat q);
rtxvr_Matrix34 to_openvr(const rtxvr_Matrix34& source);
rtxvr_Matrix34 to_source(const rtxvr_Matrix34& openvr);
rtxvr_Matrix34 compose(const rtxvr_Matrix34& a, const rtxvr_Matrix34& b);
Pose source_pose(const rtxvr_Matrix34& openvr, bool valid, Vec3 velocity={}, Vec3 spin={});
}
