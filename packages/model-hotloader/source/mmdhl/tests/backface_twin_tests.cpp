// Back-face copies (native/backface_twins.hpp): a copy layer takes the skinning and the morph offsets of
// its twin on the layer facing outside, decided by the outside vote, else by the names, else left alone.
// argv[1]: any PMX (the synthetic scene replaces its mesh). Optional argv[2]: a real PMX, then
// "follower:lead" vertex pairs that must be welded; every weld of it is checked under a random pose.
#include "backface_twins.hpp"
#include "light_overlaps.hpp"
#include <chrono>
#include <cstdlib>
#include <iostream>
#include <map>
#include <random>
#include <sstream>
using namespace mmd;
static void check(bool ok,const std::string& why){if(!ok)throw std::runtime_error(why);}

// A layer of (n+1)^2 vertices on a plane: origin + u*s + v*t for s,t in [-.8,.8], normal `normal`,
// triangles wound so that `flip` reverses them. Appends to the model as part `name`.
static void layer(Model& m,const char* name,btVector3 origin,btVector3 u,btVector3 v,btVector3 normal,bool flip,int bone,int n=4){
 unsigned first=unsigned(m.vertices.size());Material part;part.name=name;part.first=unsigned(m.indices.size());
 for(int j=0;j<=n;j++)for(int i=0;i<=n;i++){Vertex x;x.position=origin+u*(-.8f+1.6f*i/n)+v*(-.8f+1.6f*j/n);x.normal=normal;x.bones={bone,-1,-1,-1};x.weights={1,0,0,0};x.type=0;m.vertices.push_back(x);}
 auto at=[&](int i,int j){return first+unsigned(j*(n+1)+i);};
 for(int j=0;j<n;j++)for(int i=0;i<n;i++){
  std::array<unsigned,6> t{at(i,j),at(i+1,j),at(i+1,j+1),at(i,j),at(i+1,j+1),at(i,j+1)};
  if(flip){std::swap(t[1],t[2]);std::swap(t[4],t[5]);}
  m.indices.insert(m.indices.end(),t.begin(),t.end());
 }
 part.count=unsigned(m.indices.size())-part.first;m.materials.push_back(part);
}
// The k-th vertex of a layer (its vertices are consecutive, from the lowest its triangles use).
static unsigned partVertex(const Model& m,unsigned part,unsigned k){
 unsigned lowest=~0u;const auto& p=m.materials[part];
 for(unsigned i=p.first;i<p.first+p.count;i++)lowest=std::min(lowest,m.indices[i]);
 return lowest+k;
}
static unsigned leadOf(const Model& m,unsigned v){for(auto [f,l]:m.twinLeads)if(f==v)return l;return ~0u;}

static void scene(Model& m){
 m.vertices.clear();m.indices.clear();m.materials.clear();m.morphs.clear();
 // Part 0: a closed box, the body every layer below lies around.
 Material box;box.name="body";box.first=0;
 for(int i=0;i<8;i++){Vertex x;x.position=btVector3(i&1?1.f:-1.f,i&2?1.f:-1.f,i&4?1.f:-1.f);x.normal=x.position.normalized();x.bones={0,-1,-1,-1};x.weights={1,0,0,0};m.vertices.push_back(x);}
 const unsigned faces[12][3]={{0,2,1},{1,2,3},{4,5,6},{5,7,6},{0,1,4},{1,5,4},{2,6,3},{3,6,7},{0,4,2},{2,4,6},{1,3,5},{3,7,5}};
 for(auto& f:faces)for(int k=0;k<3;k++)m.indices.push_back(f[k]);
 box.count=36;m.materials.push_back(box);
 const btVector3 X(1,0,0),Y(0,1,0),Z(0,0,1);
 // Parts 1-2: a skirt at x=1.6 facing out (+x) and its copy facing the box; the copy's names mark it.
 layer(m,"skirt",X*1.6f,Y,Z,X,false,0);layer(m,"skirt+",X*1.6f,Y,Z,-X,true,0);
 // Parts 3-4: a cape at x=-1.6; the layer named as a copy ("cape+") is the one facing outside (-x).
 layer(m,"cape",-X*1.6f,Y,Z,X,false,0);layer(m,"cape+",-X*1.6f,Y,Z,-X,true,0);
 // Parts 5-6: a ribbon far from the box (and from the rays above), open on both sides: only its names decide.
 layer(m,"ribbon",X*8+Y*4,X,Y,Z,false,0);layer(m,"ribbon+",X*8+Y*4,X,Y,-Z,true,0);
 // Parts 7-8: another open pair whose names say nothing: left as it is.
 layer(m,"a",X*8+Y*7,X,Y,Z,false,0);layer(m,"b",X*8+Y*7,X,Y,-Z,true,0);
}
static void stray(Model& m,unsigned v,int bone){m.vertices[v].bones={bone,-1,-1,-1};m.vertices[v].weights={1,0,0,0};}

int main(int argc,char** argv){try{
 auto m=parse(readFile(argv[1]));check(m->bones.size()>=2,"The fixture needs two bones");
 scene(*m);
 // Strays: the skirt's copy (part 2) vertex 7, the cape's inner layer (part 3) vertex 7, the cape's outer
 // layer (part 4) vertex 12, the ribbon's copy (part 6) vertex 3, the open pair's second layer vertex 3.
 unsigned skirtCopy=partVertex(*m,2,7),skirtOuter=partVertex(*m,1,7);
 unsigned capeInner=partVertex(*m,3,7),capeOuter=partVertex(*m,4,7),capeOuterStray=partVertex(*m,4,12),capeInnerTwin=partVertex(*m,3,12);
 unsigned ribbonCopy=partVertex(*m,6,3),ribbonOuter=partVertex(*m,5,3),openB=partVertex(*m,8,3);
 stray(*m,skirtCopy,1);stray(*m,capeInner,1);stray(*m,capeOuterStray,1);stray(*m,ribbonCopy,1);stray(*m,openB,1);
 auto report=weldBackfaceTwins(*m);
 check(report.pairs==4,"Four layer pairs expected, found "+std::to_string(report.pairs));
 check(report.voted==2&&report.named==1&&report.undecided==1,"Votes "+std::to_string(report.voted)+", names "+std::to_string(report.named)+", undecided "+std::to_string(report.undecided));
 // The skirt: the copy follows the outer layer, whose skinning is unchanged.
 check(leadOf(*m,skirtCopy)==skirtOuter,"The skirt's copy does not follow its outer layer");
 check(m->vertices[skirtCopy].bones[0]==0&&m->vertices[skirtOuter].bones[0]==0,"The skirt's stray copy vertex kept its bone");
 for(auto [f,l]:m->twinLeads)check(f!=l,"A vertex leads itself");
 // The cape: the vote beats the names; the inner layer follows the outer one, stray included.
 check(leadOf(*m,capeInner)==capeOuter&&m->vertices[capeInner].bones[0]==0,"The cape's inner layer does not follow the outside");
 check(leadOf(*m,capeInnerTwin)==capeOuterStray&&m->vertices[capeInnerTwin].bones[0]==1&&m->vertices[capeOuterStray].bones[0]==1,
       "The cape's outer layer must keep its own skinning and lead its copy with it");
 check(leadOf(*m,capeOuter)==~0u,"The outside layer follows its copy");
 // The ribbon: decided by its names.
 check(leadOf(*m,ribbonCopy)==ribbonOuter&&m->vertices[ribbonCopy].bones[0]==0,"The ribbon's named copy does not follow");
 // The open pair: nothing to go on, nothing changed.
 check(leadOf(*m,openB)==~0u&&m->vertices[openB].bones[0]==1,"An undecided pair was changed");
 // Four copy vertices change their skinning: three strays and the cape's inner twin of its outer stray.
 check(report.skins==4,"Four copy vertices change their skinning, found "+std::to_string(report.skins));
 for(size_t i=1;i<m->twinLeads.size();i++)check(m->twinLeads[i-1].first<m->twinLeads[i].first,"Leads not ascending");
 // Morphs: one moving the skirt's outer vertex, one moving only its copy, one moving both alike.
 std::vector<MorphOffsets> morphs(4);
 morphs[0]={{skirtOuter,btVector3(0,0,.1f)}};
 morphs[1]={{skirtCopy,btVector3(.2f,0,0)},{skirtCopy,btVector3(.1f,0,0)}};
 morphs[2]={{skirtOuter,btVector3(0,.3f,0)},{skirtCopy,btVector3(0,.3f,0)}};
 auto fixes=buildTwinMorphFixes(*m,morphs);
 check(fixes==2&&m->twins.morphFixes==2,"Two morph corrections expected, in the model's report too");
 check(m->twinMorphFixes.size()==4&&m->twinMorphFixes[0].size()==1&&m->twinMorphFixes[0][0].first==skirtCopy&&
       (m->twinMorphFixes[0][0].second-btVector3(0,0,.1f)).length()<1e-6f,"The outer layer's morph does not move its copy");
 check(m->twinMorphFixes[1].size()==1&&(m->twinMorphFixes[1][0].second+btVector3(.3f,0,0)).length()<1e-6f,"A morph of the copy alone still moves it");
 check(m->twinMorphFixes[2].empty()&&m->twinMorphFixes[3].empty(),"Matching or absent morphs corrected");
 // The same mesh welds alike every time.
 auto first=m->twinLeads;scene(*m);stray(*m,skirtCopy,1);stray(*m,capeInner,1);stray(*m,capeOuterStray,1);stray(*m,ribbonCopy,1);stray(*m,openB,1);
 weldBackfaceTwins(*m);check(first==m->twinLeads,"Welds differ between loads");
 // A layer with its own winding (a coplanar overlay, no copy) is not a twin.
 scene(*m);for(unsigned i=m->materials[2].first;i<m->materials[2].first+m->materials[2].count;i+=3)std::swap(m->indices[i+1],m->indices[i+2]);
 check(weldBackfaceTwins(*m).pairs==3,"A same-wound overlay was taken for a back-face copy");
 std::cout<<"Back-face copies: outside vote, names, undecided pairs, skinning and morph corrections passed\n";
 if(argc>2){
  auto bytes=readFile(argv[2]);auto real=parse(bytes);auto& r=real->twins;
  // The weld's own time: a second weld of the same model finds the same twins and changes nothing.
  auto started=std::chrono::steady_clock::now();auto again=weldBackfaceTwins(*real);
  double ms=std::chrono::duration<double,std::milli>(std::chrono::steady_clock::now()-started).count();
  check(again.pairs==r.pairs&&again.followers==r.followers&&again.skins==0,"A second weld changed the model");
  auto clock=[](auto&& work){auto t=std::chrono::steady_clock::now();work();return std::chrono::duration<double,std::milli>(std::chrono::steady_clock::now()-t).count();};
  double pointsMs=clock([&]{twins_detail::points(*real);}),gridMs=clock([&]{twins_detail::occupancy(*real);}),overlapMs=clock([&]{buildLightOverlaps(*real);});
  std::cout<<"  of the weld: coincident points "<<pointsMs<<" ms, occupancy grid "<<gridMs<<" ms; the light overlaps' own pass "<<overlapMs<<" ms\n";
  std::cout<<"Real model: "<<real->vertices.size()<<" vertices, "<<real->indices.size()/3<<" triangles; pairs "<<r.pairs<<", voted "<<r.voted<<", named "<<r.named
           <<", undecided "<<r.undecided<<"; followers "<<r.followers<<", skinning changed "<<r.skins<<", morph corrections "<<r.morphFixes<<"; weld "<<ms<<" ms\n";
  // Which part follows which (by the leads' parts), with the vertices that changed their skinning.
  std::vector<unsigned> partOf(real->vertices.size(),~0u);
  for(unsigned p=0;p<real->materials.size();p++)for(unsigned i=real->materials[p].first;i<real->materials[p].first+real->materials[p].count;i++)if(partOf[real->indices[i]]==~0u)partOf[real->indices[i]]=p;
  std::map<std::pair<unsigned,unsigned>,unsigned> follows;for(auto [f,l]:real->twinLeads)follows[{partOf[f],partOf[l]}]++;
  for(auto& [parts,count]:follows)std::cout<<"  part "<<parts.first+1<<" "<<real->materials[parts.first].name<<" follows part "<<parts.second+1<<" "<<real->materials[parts.second].name<<": "<<count<<" vertices\n";
  for(int a=3;a<argc;a++){
   std::string pair=argv[a];auto colon=pair.find(':');check(colon!=std::string::npos,"Pairs are follower:lead");
   unsigned f=unsigned(std::stoul(pair.substr(0,colon))),l=unsigned(std::stoul(pair.substr(colon+1)));
   check(leadOf(*real,f)==l,"Vertex "+std::to_string(f)+" does not follow "+std::to_string(l));
   const auto& x=real->vertices[f];const auto& y=real->vertices[l];
   check(x.type==y.type&&x.bones==y.bones&&x.weights==y.weights,"Vertex "+std::to_string(f)+" kept its own skinning");
   std::ostringstream text;for(int k=0;k<4;k++)if(y.weights[k]>0)text<<" bone "<<y.bones[k]<<" "<<y.weights[k];
   std::cout<<"  "<<f<<" follows "<<l<<":"<<text.str()<<"\n";
  }
  // Every weld holds under a random pose: twins land together.
  std::mt19937 random(7);std::uniform_real_distribution<float> unit(-1,1);
  std::vector<btTransform> pose(real->bones.size());
  for(auto& t:pose){btVector3 axis(unit(random),unit(random),unit(random));if(axis.length2()<1e-6f)axis=btVector3(0,1,0);t.setRotation(btQuaternion(axis.normalized(),unit(random)*1.2f));t.setOrigin(btVector3(unit(random),unit(random),unit(random))*2);}
  float worst=0;for(auto [f,l]:real->twinLeads)worst=std::max(worst,(skinPosition(real->vertices[f],pose)-skinPosition(real->vertices[l],pose)).length());
  check(worst<1e-2f,"Welded twins part under a pose by "+std::to_string(worst));
  std::cout<<"  "<<real->twinLeads.size()<<" welds under a random pose: largest gap "<<worst<<"\n";
 }
 return 0;
}catch(const std::exception& e){std::cerr<<e.what()<<'\n';return 1;}}
