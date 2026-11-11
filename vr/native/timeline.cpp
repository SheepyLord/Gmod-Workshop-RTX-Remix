// SPDX-License-Identifier: MIT
#include "timeline.h"
#include "input_actions.h"
#include "nl/json.h"
#include <algorithm>
#include <fstream>
#include <stdexcept>

namespace nl::vr {
namespace {
using nl::json::Value;
const Value& field(const Value& v,const char* name) {
  const auto* f=v.find(name);if(!f) throw std::runtime_error(std::string("timeline missing ")+name);return *f;
}
double number(const Value& v,double bound) {
  const double n=v.as_double();
  if(!std::isfinite(n)||std::abs(n)>bound) throw std::runtime_error("timeline number outside allowed range");
  return n;
}
Vec3 vector(const Value& v,double bound) {
  const auto& a=v.as_array();if(a.size()!=3) throw std::runtime_error("timeline vector needs three numbers");
  return {static_cast<float>(number(a[0],bound)),static_cast<float>(number(a[1],bound)),static_cast<float>(number(a[2],bound))};
}
}
Timeline Timeline::parse(std::string_view text) {
  const auto root=nl::json::parse(text);
  if(field(root,"version").as_int()!=1) throw std::runtime_error("timeline version must be 1");
  const auto& steps=field(root,"steps").as_array();
  if(steps.empty()||steps.size()>10000) throw std::runtime_error("timeline needs 1-10000 steps");
  Timeline result;
  if(const auto* quit=root.find("quit_at")) result.quit_at=number(*quit,86400);
  for(const auto& v:steps) {
    ScriptStep s;s.time=number(field(v,"time"),86400);
    if(s.time<0||(result.steps_.empty()?s.time!=0:s.time<=result.steps_.back().time))
      throw std::runtime_error("timeline starts at zero and times must increase");
    constexpr const char* names[]={"hmd","left","right"};
    for(std::size_t i=0;i<3;++i) {
      const auto& p=field(v,names[i]);s.poses[i].pos=vector(field(p,"pos"),10000);
      if(const auto* q=p.find("quat")) {
        const auto& a=q->as_array();if(a.size()!=4) throw std::runtime_error("timeline quaternion needs xyzw");
        s.poses[i].rot=normalise({number(a[0],1),number(a[1],1),number(a[2],1),number(a[3],1)});
      } else s.poses[i].rot=rotation(vector(field(p,"ang"),36000));
    }
    if(const auto* actions=v.find("actions")) for(const auto& [name,a]:actions->as_object()) {
      if(name.empty()||name.size()>64||s.actions.size()>=64) throw std::runtime_error("timeline action name/count limit");
      const auto spec=std::find_if(std::begin(specs),std::end(specs),[&](const auto& item) { return name==item.name; });
      if(spec==std::end(specs)||(spec->type!='b'&&spec->type!='v'))
        throw std::runtime_error("timeline action must name a declared button or axis: "+name);
      Action action;action.active=true;
      if(spec->type=='b') action.state=a.as_bool();
      else if(spec->components==1) action.value.x=static_cast<float>(number(a,1));
      else {
        const auto& values=a.as_array();
        if(values.size()!=2&&values.size()!=3) throw std::runtime_error("timeline stick needs [x,y] or [x,y,0]");
        action.value={static_cast<float>(number(values[0],1)),static_cast<float>(number(values[1],1)),0};
        if(values.size()==3&&number(values[2],1)!=0) throw std::runtime_error("timeline stick z must be zero");
      }
      s.actions.emplace(name,action);
    }
    result.steps_.push_back(std::move(s));
  }
  return result;
}
Timeline Timeline::load(const std::filesystem::path& path) {
  if(!path.is_absolute()) throw std::runtime_error("timeline needs an absolute path under out");
  const auto resolved=std::filesystem::canonical(path);
  const auto size=std::filesystem::file_size(resolved);
  if(size>(1u<<20)) throw std::runtime_error("timeline exceeds 1 MiB");
  std::ifstream in(resolved,std::ios::binary);
  std::string text(static_cast<std::size_t>(size),'\0');
  if(!in.read(text.data(),static_cast<std::streamsize>(size))) throw std::runtime_error("cannot read timeline");
  return parse(text);
}
ScriptSample Timeline::sample(double seconds) const {
  if(!std::isfinite(seconds)||seconds<0||steps_.empty()) throw std::runtime_error("invalid timeline time");
  const auto it=std::upper_bound(steps_.begin(),steps_.end(),seconds,[](double t,const ScriptStep& s) { return t<s.time; });
  const auto i=static_cast<std::size_t>(it-steps_.begin()-1);
  const auto& a=steps_[i];const auto& b=steps_[std::min(i+1,steps_.size()-1)];
  const double dt=b.time-a.time,t=dt>0?std::clamp((seconds-a.time)/dt,0.0,1.0):0;
  ScriptSample out;out.time=std::min(seconds,steps_.back().time);out.step=i+1;out.ended=seconds>=steps_.back().time;
  for(std::size_t j=0;j<3;++j) {
    const auto& p=a.poses[j];const auto& q=b.poses[j];
    out.poses[j]={true,p.pos+(q.pos-p.pos)*t,angles(slerp(p.rot,q.rot,t)),dt>0?(q.pos-p.pos)*(1/dt):Vec3{}, {}};
    if(dt>0) {
      const Quat inv{-p.rot.x,-p.rot.y,-p.rot.z,p.rot.w};
      Quat d{q.rot.w*inv.x+q.rot.x*inv.w+q.rot.y*inv.z-q.rot.z*inv.y,
        q.rot.w*inv.y-q.rot.x*inv.z+q.rot.y*inv.w+q.rot.z*inv.x,
        q.rot.w*inv.z+q.rot.x*inv.y-q.rot.y*inv.x+q.rot.z*inv.w,
        q.rot.w*inv.w-q.rot.x*inv.x-q.rot.y*inv.y-q.rot.z*inv.z};
      if(d.w<0) d={-d.x,-d.y,-d.z,-d.w};
      const double len=std::sqrt(d.x*d.x+d.y*d.y+d.z*d.z),f=len>1e-9?2*std::atan2(len,d.w)/(len*dt):0;
      out.poses[j].angvel={static_cast<float>(d.x*f),static_cast<float>(d.y*f),static_cast<float>(d.z*f)};
    }
  }
  out.actions=a.actions;
  for(auto& [name,value]:out.actions) if(const auto found=b.actions.find(name);found!=b.actions.end())
    value.value=value.value+(found->second.value-value.value)*t;
  return out;
}
}
