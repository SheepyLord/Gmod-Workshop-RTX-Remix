// PMX rigid bodies without a bone (skirt lattices, chest helpers) under Source control. Their rest
// transform is in the model's rest space, which is the instance frame: the world origin of a client
// carrier. Every reset (the first pose, Reset physics, a teleport) placed them there, far from the
// character, and their joints dragged the chains they link across the map. Each start must move
// rigidly with the character (lying, turned and 3000 units away, against the same start standing at
// the world origin), every joint must hold from the first frame, and a follow-bone body without a
// bone must ride along.
// Usage: mmdhl_boneless_body_tests <native-boneless.pmx>
#include "runtime.hpp"
#include "rig.hpp"
#include "secondary.hpp"
#include "jobs.hpp"
#include <iostream>
#include "wide_main.hpp"
using namespace mmd;
namespace {
btVector3 vec3(const Json& p){return {p[0].get<float>(),p[1].get<float>(),p[2].get<float>()};}
std::vector<btTransform> palette(const Instance& p,const btTransform& placed){std::vector<btTransform> out;for(auto& b:p.sourceRig->bones)out.push_back(placed*b.rest);return out;}
void submit(Instance& p,const std::vector<btTransform>& pose,double t,uint64_t frame){p.submitPresentationPose(pose,t,frame);p.secondary->waitAsyncIdle();p.stepSource();}
// Every body's place in the world, in Source units; the report is kept while its list is read.
std::vector<btVector3> positions(const Instance& p){auto report=p.secondary->diagnostics();std::vector<btVector3> out;for(auto& b:report["bodyList"])out.push_back(vec3(b["worldPosition"]));
 if(out.size()!=p.model->bodies.size())throw std::runtime_error("the diagnostics list "+std::to_string(out.size())+" of "+std::to_string(p.model->bodies.size())+" bodies");return out;}
}
int wmain(int argc,wchar_t** argv){try{
 if(argc<2)throw std::runtime_error("Usage: mmdhl_boneless_body_tests <native-boneless.pmx>");
 int checks=0;auto check=[&](bool ok,const std::string& name){if(!ok)throw std::runtime_error(name);++checks;std::cout<<"PASS "<<name<<"\n";};
 auto model=parse(readFile(argv[1]));
 std::vector<size_t> boneless;size_t mount=0;
 for(size_t i=0;i<model->bodies.size();i++)if(!nanoemModelRigidBodyGetBoneObject(model->bodies[i])){boneless.push_back(i);if(nanoemModelRigidBodyGetTransformType(model->bodies[i])==NANOEM_MODEL_RIGID_BODY_TRANSFORM_TYPE_FROM_BONE_TO_SIMULATION)mount=i;}
 check(boneless.size()>=3&&mount>0,"the fixture has dynamic and follow-bone bodies without a bone");
 // Lying on its back, turned and 3000 units from the world origin; then 2000 units further (a teleport).
 const btTransform away(btQuaternion(btVector3(0,0,1),.9f)*btQuaternion(btVector3(1,0,0),-1.5f),btVector3(2400,-1800,40));
 const btTransform further(away.getBasis(),away.getOrigin()+btVector3(-2000,0,0));
 for(auto backend:{"reference","cpu_mt_v2"}){
  const std::string label=std::string(backend)+": ";
  // The start at the world origin, standing: the reference every other start must be a rigid motion of.
  World origin;auto& o=origin.get(origin.create(model,{{"backend","source"},{"presentationDriven",true},{"secondaryCollision",0},{"secondaryBackend",backend}}));
  submit(o,palette(o,btTransform::getIdentity()),0,1);auto rest=positions(o);
  World host;auto& p=host.get(host.create(model,{{"backend","source"},{"presentationDriven",true},{"secondaryCollision",0},{"secondaryBackend",backend}}));
  // Joint errors are PMX units, positions Source units; the error allowed is one physics step's sag.
  auto starts=[&](const btTransform& placed,const std::string& when){
   auto now=positions(p);double worst=0,worstBoned=0;
   for(size_t i=0;i<now.size();i++){double e=(now[i]-placed*rest[i]).length();bool none=std::find(boneless.begin(),boneless.end(),i)!=boneless.end();(none?worst:worstBoned)=std::max(none?worst:worstBoned,e);}
   double joint=p.secondary->diagnostics()["maxLinearLimitError"].get<double>();
   std::cout<<"  "<<label<<when<<": bodies without a bone "<<worst<<" Source units from their start, with a bone "<<worstBoned<<", largest joint error "<<joint<<" PMX units\n";
   check(worst<1,label+when+": bodies without a bone start with the character, not at the world origin");
   check(worstBoned<1,label+when+": bodies with a bone start with the character");
   check(joint<.05,label+when+": every joint holds at the start");};
  submit(p,palette(p,away),0,1);starts(away,"the first pose");
  double t=0;uint64_t frame=2;for(int f=1;f<=60;f++){t=f/60.;submit(p,palette(p,away),t,frame++);}
  {double off=(positions(p)[mount]-away*rest[mount]).length();
   std::cout<<"  "<<label<<"a second later: the follow-bone body without a bone is "<<off<<" Source units from its place on the head\n";
   check(off<.01,label+"the follow-bone body without a bone rides with the character");}
  p.reset();t+=1/60.;submit(p,palette(p,away),t,frame++);starts(away,"Reset physics");
  t+=1/60.;submit(p,palette(p,further),t,frame++);starts(further,"a teleport");
 }
 shutdownJobs();std::cout<<checks<<" checks of bodies without a bone passed\n";return 0;
}catch(const std::exception& e){std::cerr<<"FAIL "<<e.what()<<"\n";shutdownJobs();return 1;}}
