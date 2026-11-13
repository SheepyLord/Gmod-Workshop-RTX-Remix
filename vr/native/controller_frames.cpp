// SPDX-License-Identifier: MIT
#include "controller_frames.h"
#include <algorithm>
#include <cstring>
#include <stdexcept>

namespace nl::vr {
namespace {
rtxvr_Matrix34 matrix(const ::vr::HmdMatrix34_t& m) {
  rtxvr_Matrix34 result{};std::memcpy(&result,&m,sizeof result);return result;
}
Vec3 point(const ::vr::VRBoneTransform_t& b) { return {b.position.v[0],b.position.v[1],b.position.v[2]}; }
Vec3 cross(Vec3 a,Vec3 b) { return {a.y*b.z-a.z*b.y,a.z*b.x-a.x*b.z,a.x*b.y-a.y*b.x}; }
double length(Vec3 a) { return std::sqrt(a.x*a.x+a.y*a.y+a.z*a.z); }
Vec3 unit(Vec3 a) { const auto n=length(a);return n>1e-6?a*(1/n):Vec3{}; }
Vec3 source_vector(Vec3 v) { return {-v.z,-v.x,v.y}; }
}
SkeletonSample read_skeleton(::vr::IVRInput* input,::vr::VRActionHandle_t action,const std::string& reference) {
  SkeletonSample out;out.source=reference;
  if(reference!="with_controller"&&reference!="fist"&&reference!="grip_limit"&&reference!="open")
    throw std::runtime_error("unknown skeletal reference");
  if(!input) { out.error=::vr::VRInputError_NoData;return out; }
  uint32_t count=0;out.error=input->GetBoneCount(action,&count);
  if(out.error) return out;
  if(count!=31) { out.error=::vr::VRInputError_InvalidSkeleton;return out; }
  ::vr::VRBoneTransform_t raw[31]{};
  if(reference=="with_controller") out.error=input->GetSkeletalBoneData(action,::vr::VRSkeletalTransformSpace_Model,::vr::VRSkeletalMotionRange_WithController,raw,31);
  else out.error=input->GetSkeletalReferenceTransforms(action,::vr::VRSkeletalTransformSpace_Model,
    reference=="fist"?::vr::VRSkeletalReferencePose_Fist:reference=="grip_limit"?::vr::VRSkeletalReferencePose_GripLimit: ::vr::VRSkeletalReferencePose_OpenHand,raw,31);
  if(out.error) return out;
  for(unsigned i=0;i<31;++i) {
    const auto& b=raw[i];Vec3 pos{b.position.v[0],b.position.v[1],b.position.v[2]};
    if(!finite(pos)||length(pos)>1) { out.error=::vr::VRInputError_InvalidSkeleton;return out; }
    try { out.bones[i]=source_pose(source_matrix(pos,{b.orientation.x,b.orientation.y,b.orientation.z,b.orientation.w}),true); }
    catch(const std::exception&) { out.error=::vr::VRInputError_InvalidSkeleton;return out; }
  }
  out.valid=true;return out;
}
bool rigid(const rtxvr_Matrix34& m) {
  for(int i=0;i<3;++i) {
    if(!std::isfinite(m.m[i][3])||std::abs(m.m[i][3])>1) return false;
    for(int j=0;j<3;++j) {
      double dot=0;for(int k=0;k<3;++k) dot+=m.m[i][k]*m.m[j][k];
      if(!std::isfinite(dot)||std::abs(dot-(i==j?1:0))>.001) return false;
    }
  }
  const Vec3 a{m.m[0][0],m.m[1][0],m.m[2][0]},b{m.m[0][1],m.m[1][1],m.m[2][1]},c{m.m[0][2],m.m[1][2],m.m[2][2]};
  const auto x=cross(a,b);return x.x*c.x+x.y*c.y+x.z*c.z>.999;
}
Pose apply_frame(const Pose& raw,const Pose& local) {
  if(!raw.valid||!local.valid) return {};
  const auto m=compose(source_matrix(raw.pos,rotation(raw.ang)),source_matrix(local.pos,rotation(local.ang)));
  auto result=source_pose(to_openvr(m),true);
  // The offset rotates with the device: omega cross r belongs in throw/melee velocity.
  result.vel=raw.vel+cross(raw.angvel,result.pos-raw.pos);result.angvel=raw.angvel;return result;
}
ControllerFrames component_frames(const rtxvr_Matrix34& tip,const rtxvr_Matrix34& wrist) {
  ControllerFrames f;
  if(!rigid(tip)||!rigid(wrist)) return f;
  f.valid=true;f.source="components";f.aim=source_pose(tip,true);f.wrist=source_pose(wrist,true);
  // openxr_handmodel is the wrist. The fallback palm is 6 cm toward the knuckles,
  // retaining the tip's pointing/thumbnail-up basis (ADR 0186).
  f.hand=apply_frame({true,f.wrist.pos,f.aim.ang},{true,{.06f,0,0}});
  return f;
}
bool skeleton_frames(ControllerFrames& f,const ::vr::VRBoneTransform_t* bones,uint32_t count,unsigned side) {
  if(!f.aim.valid||count!=31) return false;
  // OpenVR's standard 31-bone hand: wrist 1; index/middle/ring/little proximal 7/12/17/22.
  const auto wrist=point(bones[1]);Vec3 knuckles{};
  for(unsigned i:{7u,12u,17u,22u}) { const auto p=point(bones[i]);if(!finite(p)) return false;knuckles=knuckles+p*.25; }
  const auto finger=unit(knuckles-wrist),across=unit(point(bones[7])-point(bones[22]));
  if(!finite(wrist)||length(wrist)>.5||length(knuckles-wrist)<.025||length(knuckles-wrist)>.18||length(cross(finger,across))<.2) return false;
  // Model-space bones already contain the root transform; do not multiply it a second time.
  f.wrist.pos=source_vector(wrist);f.hand.pos=source_vector((wrist+knuckles)*.5);
  f.skeleton_finger=source_vector(finger);
  f.skeleton_normal=source_vector(unit(cross(finger,across))*(side==0?1:-1));
  f.hand.ang=f.aim.ang;if(!f.wrist.valid) f.wrist.ang=f.aim.ang;
  f.hand.valid=f.wrist.valid=f.valid=true;
  f.skeleton=true;f.source="skeleton_with_controller";return true;
}
void ControllerFrameCache::reset() { values_={};revision_=0;retry_at_={};failures_={}; }
void ControllerFrameCache::invalidate(uint32_t device) {
  for(unsigned i=0;i<values_.size();++i) if(values_[i].device==device) {
    values_[i]={};values_[i].revision=++revision_;retry_at_[i]={};failures_[i]=0;
  }
}
void ControllerFrameCache::refresh(uint32_t device) {
  for(unsigned i=0;i<values_.size();++i) if(values_[i].device==device) retry_at_[i]={};
}
const ControllerFrames& ControllerFrameCache::read(unsigned side,uint32_t device,::vr::IVRSystem* system,
  ::vr::IVRRenderModels* models,::vr::IVRInput* input,::vr::VRInputValueHandle_t path,::vr::VRActionHandle_t skeleton) {
  auto& f=values_.at(side);
  if(device==::vr::k_unTrackedDeviceIndexInvalid||!system->IsTrackedDeviceConnected(device)) {
    if(f.device!=::vr::k_unTrackedDeviceIndexInvalid) { f={};f.revision=++revision_; }
    return f;
  }
  const auto now=std::chrono::steady_clock::now();
  if(f.device==device&&now<retry_at_[side]) return f;
  const auto before=f;
  const auto same=[](const Pose& a,const Pose& b) {
    return a.valid==b.valid&&length(a.pos-b.pos)<1e-6&&length(a.ang-b.ang)<1e-6;
  };
  const auto retry=[&] {
    const auto delay=100u<<std::min(failures_[side]++,4u);
    retry_at_[side]=now+std::chrono::milliseconds(delay);
  };
  char name[1024]{};::vr::ETrackedPropertyError error{};
  system->GetStringTrackedDeviceProperty(device,::vr::Prop_RenderModelName_String,name,sizeof name,&error);name[sizeof name-1]=0;
  const std::string model=error==::vr::TrackedProp_Success?name:before.device==device?before.model:std::string{};
  ::vr::RenderModel_ComponentState_t aim{},wrist{};::vr::RenderModel_ControllerMode_State_t mode{};
  const bool tip_ok=models&&!model.empty()&&models->GetComponentStateForDevicePath(model.c_str(),"tip",path,&mode,&aim)&&rigid(matrix(aim.mTrackingToComponentLocal));
  const bool wrist_ok=models&&!model.empty()&&models->GetComponentStateForDevicePath(model.c_str(),"openxr_handmodel",path,&mode,&wrist)&&rigid(matrix(wrist.mTrackingToComponentLocal));
  const auto tip=tip_ok?source_pose(matrix(aim.mTrackingToComponentLocal),true):Pose{};
  const auto component=wrist_ok?source_pose(matrix(wrist.mTrackingToComponentLocal),true):Pose{};
  if(before.device==device&&before.model==model&&before.skeleton&&same(tip,before.aim)&&same(component,before.component_wrist)) {
    // A battery/property notification is not a new grasp calibration.
    retry_at_[side]=std::chrono::steady_clock::time_point::max();failures_[side]=0;return f;
  }
  if(before.device==device&&before.model==model&&before.valid&&(!tip_ok||(before.component_wrist.valid&&!wrist_ok))) {
    retry();return f; // transient component read: keep the last usable geometry
  }
  f={};f.device=device;f.model=model;f.aim=tip;f.wrist=component;f.component_wrist=component;
  if(tip_ok&&wrist_ok) {
    const auto full=component_frames(matrix(aim.mTrackingToComponentLocal),matrix(wrist.mTrackingToComponentLocal));
    f.valid=full.valid;f.hand=full.hand;f.source=full.source;
  }
  ::vr::VRBoneTransform_t bones[31]{};uint32_t count=0;
  if(tip_ok&&input&&input->GetBoneCount(skeleton,&count)==::vr::VRInputError_None&&count==31&&
      input->GetSkeletalReferenceTransforms(skeleton,::vr::VRSkeletalTransformSpace_Model,::vr::VRSkeletalReferencePose_GripLimit,bones,31)==::vr::VRInputError_None) {
    if(skeleton_frames(f,bones,31,side)) f.source="skeleton_grip_reference";
  }
  if(!f.aim.valid) { f.valid=false;f.hand={};f.source="raw";f.detail="controller aim unavailable; using raw pose"; }
  else if(!f.valid) { f.source="tip_only";f.detail="hand unavailable; retaining tip aim and raw hand"; }
  if(f.skeleton) { retry_at_[side]=std::chrono::steady_clock::time_point::max();failures_[side]=0; }
  else retry();
  f.revision=before.revision;
  if(before.device!=device||f.model!=before.model||f.valid!=before.valid||f.source!=before.source||
      !same(f.aim,before.aim)||!same(f.hand,before.hand)||!same(f.wrist,before.wrist)) f.revision=++revision_;
  return f;
}
}
