// SPDX-License-Identifier: MIT
#include "pose_math.h"
#include <algorithm>
#include <stdexcept>

namespace nl::vr {
namespace {
constexpr double pi=3.14159265358979323846;
constexpr float basis[3][3]={{0,0,-1},{-1,0,0},{0,1,0}};
rtxvr_Matrix34 change_basis(const rtxvr_Matrix34& a, bool inverse) {
  rtxvr_Matrix34 out{};
  const auto b=[&](int i,int j) { return inverse?basis[j][i]:basis[i][j]; };
  for(int i=0;i<3;++i) {
    for(int k=0;k<3;++k) out.m[i][3]+=b(i,k)*a.m[k][3];
    for(int j=0;j<3;++j) for(int k=0;k<3;++k) for(int l=0;l<3;++l)
      out.m[i][j]+=b(i,k)*a.m[k][l]*b(j,l);
  }
  return out;
}
Vec3 matrix_angles(const rtxvr_Matrix34& m) {
  const double c=std::hypot(m.m[0][0],m.m[1][0]);
  return {static_cast<float>(std::atan2(-m.m[2][0],c)*180/pi),
    static_cast<float>(std::atan2(c>1e-6?m.m[1][0]:-m.m[0][1],c>1e-6?m.m[0][0]:m.m[1][1])*180/pi),
    static_cast<float>(c>1e-6?std::atan2(m.m[2][1],m.m[2][2])*180/pi:0)};
}
}
Vec3 operator+(Vec3 a,Vec3 b) { return {a.x+b.x,a.y+b.y,a.z+b.z}; }
Vec3 operator-(Vec3 a,Vec3 b) { return {a.x-b.x,a.y-b.y,a.z-b.z}; }
Vec3 operator*(Vec3 a,double b) { return {static_cast<float>(a.x*b),static_cast<float>(a.y*b),static_cast<float>(a.z*b)}; }
bool finite(Vec3 v) { return std::isfinite(v.x)&&std::isfinite(v.y)&&std::isfinite(v.z); }
Quat normalise(Quat q) {
  const double length=std::sqrt(q.x*q.x+q.y*q.y+q.z*q.z+q.w*q.w);
  if(!std::isfinite(length)||length<1e-9) throw std::runtime_error("invalid quaternion");
  return {q.x/length,q.y/length,q.z/length,q.w/length};
}
Quat slerp(Quat a,Quat b,double t) {
  a=normalise(a);b=normalise(b);
  double dot=a.x*b.x+a.y*b.y+a.z*b.z+a.w*b.w;
  if(dot<0) { b={-b.x,-b.y,-b.z,-b.w};dot=-dot; }
  double x=1-t,y=t;
  if(dot<0.9995) {
    const double theta=std::acos(std::clamp(dot,-1.0,1.0));
    x=std::sin((1-t)*theta)/std::sin(theta);y=std::sin(t*theta)/std::sin(theta);
  }
  return normalise({a.x*x+b.x*y,a.y*x+b.y*y,a.z*x+b.z*y,a.w*x+b.w*y});
}
Quat rotation(Vec3 a) {
  const double p=a.x*pi/360,y=a.y*pi/360,r=a.z*pi/360;
  const double cp=std::cos(p),sp=std::sin(p),cy=std::cos(y),sy=std::sin(y),cr=std::cos(r),sr=std::sin(r);
  return {cy*cp*sr-sy*sp*cr,cy*sp*cr+sy*cp*sr,sy*cp*cr-cy*sp*sr,cy*cp*cr+sy*sp*sr};
}
rtxvr_Matrix34 source_matrix(Vec3 pos,Quat q) {
  q=normalise(q);
  const auto f=[](double x) { return static_cast<float>(x); };
  return {{{f(1-2*(q.y*q.y+q.z*q.z)),f(2*(q.x*q.y-q.z*q.w)),f(2*(q.x*q.z+q.y*q.w)),pos.x},
    {f(2*(q.x*q.y+q.z*q.w)),f(1-2*(q.x*q.x+q.z*q.z)),f(2*(q.y*q.z-q.x*q.w)),pos.y},
    {f(2*(q.x*q.z-q.y*q.w)),f(2*(q.y*q.z+q.x*q.w)),f(1-2*(q.x*q.x+q.y*q.y)),pos.z}}};
}
Vec3 angles(Quat q) { return matrix_angles(source_matrix({},q)); }
rtxvr_Matrix34 to_openvr(const rtxvr_Matrix34& m) { return change_basis(m,true); }
rtxvr_Matrix34 to_source(const rtxvr_Matrix34& m) { return change_basis(m,false); }
rtxvr_Matrix34 compose(const rtxvr_Matrix34& a,const rtxvr_Matrix34& b) {
  rtxvr_Matrix34 out{};
  for(int i=0;i<3;++i) {
    out.m[i][3]=a.m[i][3];
    for(int k=0;k<3;++k) out.m[i][3]+=a.m[i][k]*b.m[k][3];
    for(int j=0;j<3;++j) for(int k=0;k<3;++k) out.m[i][j]+=a.m[i][k]*b.m[k][j];
  }
  return out;
}
Pose source_pose(const rtxvr_Matrix34& raw,bool valid,Vec3 v,Vec3 spin) {
  if(!valid) return {};
  const auto m=to_source(raw);
  return {true,{m.m[0][3],m.m[1][3],m.m[2][3]},matrix_angles(m),{-v.z,-v.x,v.y},{-spin.z,-spin.x,spin.y}};
}
}
