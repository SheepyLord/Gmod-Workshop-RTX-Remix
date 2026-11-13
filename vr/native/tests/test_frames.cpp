// SPDX-License-Identifier: MIT
#include "controller_frames.h"
#include "nl_test.h"
#include <algorithm>

namespace {
namespace v=nl::vr;
// Source: SteamVR's render-model component_local tables, copied 2026-11-11.
// drivers/indexcontroller/resources/rendermodels/valve_controller_knu_1_0_{left,right};
// resources/rendermodels/{oculus_{quest2,rifts,cv1}_controller_right,vr_controller_vive_1_5}.
// Tests never read the SteamVR installation. JSON rotate_xyz is Rz * Ry * Rx.
struct Component { v::Vec3 pos, xyz; };
struct Fixture { const char* name; Component tip,wrist; };
const Fixture fixtures[]={
  {"Index left",{{.006f,-.015f,.02f},{-40,-5,0}},{{-.015f,-.015f,.13f},{-40,-5,0}}},
  {"Index right",{{-.006f,-.015f,.02f},{-40,5,0}},{{.015f,-.015f,.13f},{-40,5,0}}},
  {"Quest 2",{{-.0167f,-.0252f,.0247f},{-37.4f,0,0}},{{.0113f,-.0018f,.1019f},{-39.4f,0,0}}},
  {"Rift S",{{-.0063f,-.0252f,.0347f},{-39.4f,0,0}},{{.0113f,-.0018f,.1019f},{-39.4f,0,0}}},
  {"CV1",{{-.0063f,-.0252f,.0347f},{-39.4f,0,0}},{{.0113f,-.0018f,.1019f},{-39.4f,0,0}}},
  {"Vive wand",{{0,-.01f,-.007f},{1.282f,0,0}},{{-.02f,-.0285f,.097f},{1.282f,0,0}}}
};
rtxvr_Matrix34 component(Component c) {
  constexpr double rad=3.14159265358979323846/180;
  const double x=c.xyz.x*rad,y=c.xyz.y*rad,z=c.xyz.z*rad;
  const double cx=cos(x),sx=sin(x),cy=cos(y),sy=sin(y),cz=cos(z),sz=sin(z);
  return {{{float(cz*cy),float(cz*sy*sx-sz*cx),float(cz*sy*cx+sz*sx),c.pos.x},
    {float(sz*cy),float(sz*sy*sx+cz*cx),float(sz*sy*cx-cz*sx),c.pos.y},
    {float(-sy),float(cy*sx),float(cy*cx),c.pos.z}}};
}
rtxvr_Matrix34 inverse_rotation(rtxvr_Matrix34 m) {
  for(unsigned i=0;i<3;++i) { m.m[i][3]=0;for(unsigned j=i+1;j<3;++j) std::swap(m.m[i][j],m.m[j][i]); }return m;
}
bool near(float a,float b,float e=.00001f) { return std::abs(a-b)<e; }
}
TEST_CASE("V4 C: recorded Index Touch and Vive components compose a level natural hold") {
  for(const auto& f:fixtures) {
    const auto tip=component(f.tip),wrist=component(f.wrist);
    const auto frames=v::component_frames(tip,wrist);REQUIRE(frames.valid);
    auto raw=v::source_pose(inverse_rotation(tip),true);raw.pos={.45f,-.2f,1.3f};
    const auto aim=v::apply_frame(raw,frames.aim),hand=v::apply_frame(raw,frames.hand);
    CHECK(std::abs(aim.ang.x)<.5);CHECK(std::abs(aim.ang.y)<.5);CHECK(std::abs(aim.ang.z)<.5);
    CHECK(std::abs(hand.ang.x)<.5);CHECK(std::abs(hand.ang.z)<.5);
    // Assert positions independently using OpenVR's matrix-vector multiplication.
    auto natural=inverse_rotation(tip);v::Vec3 expected{};
    for(unsigned r=0;r<3;++r) for(unsigned c=0;c<3;++c) (&expected.x)[r]+=natural.m[r][c]*(&f.tip.pos.x)[c];
    CHECK(near(aim.pos.x,raw.pos.x-expected.z));CHECK(near(aim.pos.y,raw.pos.y-expected.x));CHECK(near(aim.pos.z,raw.pos.z+expected.y));
    const auto m=v::source_matrix(hand.pos,v::rotation(hand.ang));
    CHECK(near(m.m[0][0],1));CHECK(near(m.m[2][2],1)); // fingers forward, thumb up; palm is +/- local Y.
  }
}
TEST_CASE("V4 C: malformed or reflected component matrices retain the raw fallback") {
  auto m=component(fixtures[0].tip);auto bad=m;bad.m[0][0]=NAN;
  CHECK(!v::component_frames(bad,m).valid);bad=m;for(int r=0;r<3;++r) bad.m[r][0]*=-1;
  CHECK(!v::component_frames(m,bad).valid);CHECK(!v::apply_frame({},{}).valid);
}
TEST_CASE("V4 C: wrist and palm from the controller constrained standard skeleton") {
  for(unsigned side=0;side<2;++side) {
    auto f=v::component_frames(component(fixtures[side].tip),component(fixtures[side].wrist));
    ::vr::VRBoneTransform_t bones[31]{};
    bones[1].position={{0,0,.13f,1}};
    for(unsigned i=0;i<4;++i) bones[7+i*5].position={{float(i)*.01f,0,.05f,1}};
    REQUIRE(v::skeleton_frames(f,bones,31,side));CHECK(f.skeleton);CHECK(f.source=="skeleton_with_controller");
    CHECK(near(f.wrist.pos.x,-.13f));CHECK(near(f.hand.pos.x,-.09f));
    bones[1].position.v[0]=NAN;CHECK(!v::skeleton_frames(f,bones,31,side));
  }
}
TEST_CASE("V4 C: offset angular velocity is included in hand velocity") {
  const auto p=v::apply_frame({true,{1,2,3},{},{1,0,0},{0,0,2}},{true,{.1f,0,0}});
  CHECK(near(p.pos.x,1.1f));CHECK(near(p.vel.x,1));CHECK(near(p.vel.y,.2f));CHECK(near(p.angvel.z,2));
}
