// SPDX-License-Identifier: MIT
#include "sim_device.h"
#include "lua_policy.h"
#include "nl/fs.h"
#include "nl/json.h"
#include <cmath>
#include <stdexcept>
namespace nl::vr {
namespace {
const nl::json::Value& field(const nl::json::Value& v,const char* key) {
  const auto* f=v.find(key);if(!f) throw std::runtime_error(std::string("simulated device missing ")+key);return *f;
}
float number(const nl::json::Value& v,double low,double high) {
  const auto n=v.as_double();if(!std::isfinite(n)||n<low||n>high) throw std::runtime_error("simulated device number out of range");
  return static_cast<float>(n);
}
uint32_t dimension(const nl::json::Value& v) {
  const auto n=v.as_int();if(n<16||n>16384) throw std::runtime_error("simulated device dimension out of range");return static_cast<uint32_t>(n);
}
}
SimDevice SimDevice::load(const std::filesystem::path& path) {
  const auto root=nl::json::parse(nl::fs::read_file(checked_data_path(path),65536));
  if(field(root,"version").as_int()!=1) throw std::runtime_error("simulated device version must be 1");
  SimDevice d;d.model=field(root,"model").as_string();d.tracking=field(root,"tracking").as_string();
  if(d.model.empty()||d.model.size()>128||d.tracking.empty()||d.tracking.size()>128||
    d.model.find('\0')!=d.model.npos||d.tracking.find('\0')!=d.tracking.npos) throw std::runtime_error("invalid simulated device strings");
  d.width=dimension(field(root,"eye_width"));d.height=dimension(field(root,"eye_height"));
  d.refresh=number(field(root,"refresh"),20,240);d.ipd=number(field(root,"ipd"),.04,.1);
  const auto& eyes=field(root,"eyes").as_array();if(eyes.size()!=2) throw std::runtime_error("simulated device needs two eyes");
  for(std::size_t i=0;i<2;++i) {
    auto& e=d.eyes[i];const auto& v=eyes[i];
    e.tanLeft=number(field(v,"tanLeft"),-10,-.01);e.tanRight=number(field(v,"tanRight"),.01,10);
    e.tanTop=number(field(v,"tanTop"),-10,-.01);e.tanBottom=number(field(v,"tanBottom"),.01,10);
    const auto& rows=field(v,"eyeToHead").as_array();if(rows.size()!=3) throw std::runtime_error("simulated eye matrix needs three rows");
    for(std::size_t r=0;r<3;++r) {
      const auto& row=rows[r].as_array();if(row.size()!=4) throw std::runtime_error("simulated eye matrix needs four columns");
      for(std::size_t c=0;c<4;++c) e.eyeToHead.m[r][c]=number(row[c],-1,1);
    }
    for(int r=0;r<3;++r) for(int c=0;c<3;++c) {
      double dot=0;for(int k=0;k<3;++k) dot+=e.eyeToHead.m[r][k]*e.eyeToHead.m[c][k];
      if(std::abs(dot-(r==c?1:0))>.001) throw std::runtime_error("simulated eye rotation must be orthonormal");
    }
    const auto& m=e.eyeToHead.m;
    const double determinant=m[0][0]*(m[1][1]*m[2][2]-m[1][2]*m[2][1])-
      m[0][1]*(m[1][0]*m[2][2]-m[1][2]*m[2][0])+m[0][2]*(m[1][0]*m[2][1]-m[1][1]*m[2][0]);
    if(determinant<.999) throw std::runtime_error("simulated eye rotation cannot be a reflection");
  }
  const auto& a=d.eyes[0].eyeToHead;const auto& b=d.eyes[1].eyeToHead;
  const double distance=std::sqrt(std::pow(a.m[0][3]-b.m[0][3],2)+std::pow(a.m[1][3]-b.m[1][3],2)+std::pow(a.m[2][3]-b.m[2][3],2));
  if(std::abs(distance-d.ipd)>.001) throw std::runtime_error("simulated eye offsets disagree with IPD");
  if(const auto* controllers=root.find("controllers")) {
    for(unsigned i=0;i<2;++i) {
      const auto& c=field(*controllers,i==0?"left":"right");
      const auto transform=[&](const char* name) {
        rtxvr_Matrix34 m{};const auto& rows=field(c,name).as_array();
        if(rows.size()!=3) throw std::runtime_error("controller transform needs three rows");
        for(unsigned r=0;r<3;++r) {
          const auto& row=rows[r].as_array();if(row.size()!=4) throw std::runtime_error("controller transform needs four columns");
          for(unsigned col=0;col<4;++col) m.m[r][col]=number(row[col],-1,1);
        }
        if(!rigid(m)) throw std::runtime_error("controller transform is not rigid");return m;
      };
      auto& f=d.controllers[i];f=component_frames(transform("tip"),transform("wrist"));
      f.device=i+1;f.revision=1;f.model=field(c,"model").as_string();
      if(f.model.size()>1023||f.model.find('\0')!=f.model.npos) throw std::runtime_error("invalid controller model");
      f.source="recorded_components";
    }
  }
  return d;
}
}
