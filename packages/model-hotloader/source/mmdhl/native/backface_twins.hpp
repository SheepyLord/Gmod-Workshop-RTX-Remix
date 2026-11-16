#pragma once
// Back-face copies: a part whose triangles lie exactly on another part's with the opposite winding
// (MMD's "X+" or lining layers), so that single-sided rendering shows the outer layer from outside and
// the copy from inside. Raster culling hides whichever layer faces away, so a copy whose vertices are
// skinned or morphed differently from its twins never shows there. A path tracer's shadow and bounce
// rays still meet it: where a pose or a morph lifts the copy above its outer layer, it shades that
// layer black (RTX Remix). At load each copy vertex takes the skinning of its twin on the layer facing
// outside (weldBackfaceTwins), and its vertex morphs are corrected to its twin's offsets
// (buildTwinMorphFixes, applied with the morphs in Instance::publish). The outside layer of a pair is
// voted over its triangles: a ray along each layer's normals through a coarse occupancy grid of the
// rest mesh; the layer whose rays cross fewer surfaces faces outside. A pair the vote leaves open is
// decided by its names (a "+" suffix, 裏, 内側, lining), else left alone.
#include "runtime.hpp"
#include <algorithm>
#include <array>
#include <cmath>
#include <cstdint>
#include <cstring>
#include <map>
#include <string>
#include <unordered_map>
#include <utility>
#include <vector>

namespace mmd {

// One vertex morph's offsets as (vertex, offset); a vertex may repeat (its offsets add up).
using MorphOffsets=std::vector<std::pair<unsigned,btVector3>>;

namespace twins_detail {
// A lining layer puts two triangles (a few where layers stack) on the same three points. A point set
// shared by more is a stack of duplicates, not a copy, and is left out; a mesh whose point sets still
// pair more twin triangles than MaxPairsPerTriangle per triangle, or more part pairs than MaxPartPairs,
// is left as it is. So the work stays linear in the model's size: before (review finding 11) every
// pair of a crafted stack was kept, and 16,384 copies of one triangle took 1.2 GB and 1.4 s.
constexpr size_t MaxCoincidentTriangles=16,MaxPairsPerTriangle=2,MaxPartPairs=4096;
template<class T,size_t N> struct ArrayHash {
 size_t operator()(const std::array<T,N>& a)const{size_t h=0;for(auto v:a)h^=std::hash<T>{}(v)+0x9e3779b9+(h<<6)+(h>>2);return h;}
};
// Coincident rest positions share one representative: the light overlaps' rule (within 1e-4 PMX units). Cells are
// four times that wide, so a neighbouring cell is searched only where the point lies that close to its border.
inline std::vector<unsigned> points(const Model& m){
 constexpr float epsilon=1e-4f;constexpr double width=4.0*epsilon;using Cell=std::array<int64_t,3>;
 std::unordered_map<Cell,std::vector<unsigned>,ArrayHash<int64_t,3>> cells;cells.reserve(m.vertices.size());
 std::vector<unsigned> out(m.vertices.size());
 for(unsigned i=0;i<m.vertices.size();i++){
  auto p=m.vertices[i].position;Cell cell{};std::array<int,3> low{},high{};bool bounded=true;out[i]=i;
  for(int k=0;k<3;k++){
   double v=double(p[k])/width,base=std::floor(v);
   if(!std::isfinite(base)||std::abs(base)>1e12){bounded=false;break;}
   cell[k]=int64_t(base);double inside=(v-base)*width;low[k]=inside<epsilon?-1:0;high[k]=inside>width-epsilon?1:0;
  }
  if(!bounded)continue;bool found=false;
  for(int x=low[0];x<=high[0]&&!found;x++)for(int y=low[1];y<=high[1]&&!found;y++)for(int z=low[2];z<=high[2]&&!found;z++){
   auto it=cells.find({cell[0]+x,cell[1]+y,cell[2]+z});if(it==cells.end())continue;
   for(unsigned j:it->second)if((m.vertices[j].position-p).length2()<=epsilon*epsilon){out[i]=j;found=true;break;}
  }
  if(!found)cells[cell].push_back(i);
 }
 return out;
}
// The rest mesh in cells of 1/64 of its largest extent, with one empty cell around it.
struct Grid {
 btVector3 low{0,0,0};float cell=0;int nx=0,ny=0,nz=0;std::vector<uint8_t> occupied;
 int index(const btVector3& p)const{
  int x=int(std::floor((p.x()-low.x())/cell)),y=int(std::floor((p.y()-low.y())/cell)),z=int(std::floor((p.z()-low.z())/cell));
  return x<0||y<0||z<0||x>=nx||y>=ny||z>=nz?-1:(z*ny+y)*nx+x;
 }
};
inline Grid occupancy(const Model& m){
 Grid g;btVector3 low(BT_LARGE_FLOAT,BT_LARGE_FLOAT,BT_LARGE_FLOAT),high=-low;
 for(auto i:m.indices){const auto& p=m.vertices[i].position;low.setMin(p);high.setMax(p);}
 auto size=high-low;float extent=std::max({size.x(),size.y(),size.z()});
 if(m.indices.empty()||!std::isfinite(extent)||!(extent>0))return g;
 g.cell=extent/64;g.low=low-btVector3(g.cell,g.cell,g.cell);
 g.nx=int(size.x()/g.cell)+3;g.ny=int(size.y()/g.cell)+3;g.nz=int(size.z()/g.cell)+3;
 g.occupied.assign(size_t(g.nx)*size_t(g.ny)*size_t(g.nz),0);
 for(size_t t=0;t+2<m.indices.size();t+=3){
  const auto& a=m.vertices[m.indices[t]].position;const auto& b=m.vertices[m.indices[t+1]].position;const auto& c=m.vertices[m.indices[t+2]].position;
  float edge=std::max({(b-a).length(),(c-a).length(),(c-b).length()});
  int n=std::clamp(int(std::ceil(edge/(.5f*g.cell))),1,32);
  for(int i=0;i<=n;i++)for(int j=0;i+j<=n;j++){int k=g.index(a+(b-a)*(float(i)/n)+(c-a)*(float(j)/n));if(k>=0)g.occupied[size_t(k)]=1;}
 }
 return g;
}
// Surfaces a ray from p along the unit direction d crosses, from two cells away to the grid's edge.
inline int crossings(const Grid& g,const btVector3& p,const btVector3& d){
 int count=0;bool inside=false;const float step=.5f*g.cell,limit=g.cell*float(g.nx+g.ny+g.nz);
 for(float t=2*g.cell;t<limit;t+=step){int k=g.index(p+d*t);if(k<0)break;bool occupied=g.occupied[size_t(k)]!=0;if(occupied&&!inside)count++;inside=occupied;}
 return count;
}
// Which layer of a pair faces outside: +1 the first part's, -1 the second's, 0 undecided. Up to 64
// twin triangles, spread over the pair, vote; one side needs three votes and three times the other's.
inline int outsideLayer(const Model& m,const Grid& g,const std::vector<std::pair<unsigned,unsigned>>& twins){
 int first=0,second=0;const size_t stride=std::max<size_t>(1,twins.size()/64);
 for(size_t s=0;s<twins.size();s+=stride){
  auto [ta,tb]=twins[s];btVector3 na(0,0,0),nb(0,0,0),centre(0,0,0);
  for(int k=0;k<3;k++){const auto& a=m.vertices[m.indices[ta*3+k]];na+=a.normal;nb+=m.vertices[m.indices[tb*3+k]].normal;centre+=a.position;}
  if(na.length2()<1e-12f||nb.length2()<1e-12f)continue;
  na.normalize();nb.normalize();centre/=3;
  // A copy's normals face the other way; a pair whose normals do not tells nothing.
  if(na.dot(nb)>-.5f)continue;
  int a=crossings(g,centre,na),b=crossings(g,centre,nb);
  if(a<b)first++;else if(b<a)second++;
 }
 if(first>=3&&first>=3*second)return 1;
 if(second>=3&&second>=3*first)return -1;
 return 0;
}
// Whether two vertices deform alike: the same bones with the same weights (in any slot order, within 1e-4), and the
// same kind of blend (PMX SDEF 3 and QDEF 4 differ from linear blending; SDEF also by its parameters).
inline bool sameSkinning(const Vertex& a,const Vertex& b){
 auto special=[](int type){return type==3||type==4;};
 if(special(a.type)!=special(b.type)||(special(a.type)&&a.type!=b.type))return false;
 if(a.type==3&&(a.c!=b.c||a.r0!=b.r0||a.r1!=b.r1))return false;
 auto influences=[](const Vertex& v){std::array<std::pair<int,float>,4> out{};int count=0;
  for(int k=0;k<4;k++){if(v.bones[k]<0||!(v.weights[k]>1e-6f))continue;int at=0;while(at<count&&out[at].first!=v.bones[k])at++;if(at==count)out[count++]={v.bones[k],0.f};out[at].second+=v.weights[k];}
  std::sort(out.begin(),out.begin()+count);for(int k=count;k<4;k++)out[k]={-1,0.f};return out;};
 auto x=influences(a),y=influences(b);
 for(int k=0;k<4;k++)if(x[k].first!=y[k].first||std::abs(x[k].second-y[k].second)>1e-4f)return false;
 return true;
}
// A part named as the inside of another: a "+" suffix, 裏, 内侧/內側/内側, a trailing 内/內, inner, lining.
inline bool namedCopy(const std::string& name){
 std::string n=name;while(!n.empty()&&(n.back()==' '||n.back()=='\t'))n.pop_back();
 if(!n.empty()&&n.back()=='+')return true;
 std::string lower;for(char c:n)lower+=char(c>='A'&&c<='Z'?c-'A'+'a':c);
 for(const char* mark:{"inner","lining","\xE8\xA3\x8F","\xE5\x86\x85\xE4\xBE\xA7","\xE5\x85\xA7\xE5\x81\xB4","\xE5\x86\x85\xE5\x81\xB4"})
  if(lower.find(mark)!=std::string::npos)return true;
 auto ends=[&](const char* s){size_t l=std::strlen(s);return n.size()>=l&&n.compare(n.size()-l,l,s)==0;};
 return ends("\xE5\x86\x85")||ends("\xE5\x85\xA7");
}
}

// Finds the back-face copies, decides each pair's outside layer and gives every copy vertex the
// skinning (type, bones, weights, SDEF parameters) of its twin on that layer. Sets Model::twinLeads
// (follower, lead), ascending, and returns what it found (TwinReport::skins: the followers whose own
// skinning deformed differently; stacked and limited: twins_detail::MaxCoincidentTriangles and the
// limits beside it); the rest geometry is not changed.
inline Model::TwinReport weldBackfaceTwins(Model& m){
 Model::TwinReport report;m.twinLeads.clear();
 const size_t triangles=m.indices.size()/3;
 if(m.materials.size()<2||!triangles)return report;
 auto point=twins_detail::points(m);
 // Triangles by their three points; twins have the same points in the opposite cyclic order.
 std::vector<uint8_t> clockwise(triangles,0);std::vector<unsigned> partOf(triangles,~0u);
 std::vector<std::pair<std::array<unsigned,3>,unsigned>> keys;keys.reserve(triangles);
 for(unsigned part=0;part<m.materials.size();part++){
  const auto& material=m.materials[part];
  for(size_t i=material.first;i+2<size_t(material.first)+material.count&&i+2<m.indices.size();i+=3){
   unsigned t=unsigned(i/3);std::array<unsigned,3> p{point[m.indices[i]],point[m.indices[i+1]],point[m.indices[i+2]]};
   if(p[0]==p[1]||p[1]==p[2]||p[0]==p[2])continue;
   unsigned k=unsigned(std::min_element(p.begin(),p.end())-p.begin());
   clockwise[t]=p[(k+1)%3]<p[(k+2)%3];partOf[t]=part;
   auto key=p;std::sort(key.begin(),key.end());keys.push_back({key,t});
  }
 }
 std::sort(keys.begin(),keys.end());
 // Twin triangles per pair of parts (first part < second), in triangle order, so every load votes alike.
 // Point sets of more than MaxCoincidentTriangles are left out; past the other limits nothing is welded.
 std::map<std::pair<unsigned,unsigned>,std::vector<std::pair<unsigned,unsigned>>> pairs;
 const size_t maxListed=triangles*twins_detail::MaxPairsPerTriangle;size_t listed=0;
 auto limited=[&]{report=Model::TwinReport{};report.limited=true;m.twinLeads.clear();return report;};
 for(size_t begin=0,end=0;begin<keys.size();begin=end){
  end=begin+1;while(end<keys.size()&&keys[end].first==keys[begin].first)end++;
  if(end-begin>twins_detail::MaxCoincidentTriangles){report.stacked++;continue;}
  for(size_t i=begin;i<end;i++)for(size_t j=i+1;j<end;j++){
   unsigned s=keys[i].second,t=keys[j].second;
   if(clockwise[s]==clockwise[t]||partOf[s]==partOf[t])continue;
   if(partOf[s]>partOf[t])std::swap(s,t);
   if(++listed>maxListed)return limited();
   auto& list=pairs[{partOf[s],partOf[t]}];if(list.empty()&&pairs.size()>twins_detail::MaxPartPairs)return limited();
   list.push_back({s,t});
  }
 }
 report.pairs=unsigned(pairs.size());
 if(pairs.empty())return report;
 auto grid=twins_detail::occupancy(m);
 std::vector<unsigned> follow(m.vertices.size(),~0u);
 for(auto& [parts,list]:pairs){
  std::sort(list.begin(),list.end());
  int side=grid.cell>0?twins_detail::outsideLayer(m,grid,list):0;
  if(side)report.voted++;
  else{
   bool first=twins_detail::namedCopy(m.materials[parts.first].name),second=twins_detail::namedCopy(m.materials[parts.second].name);
   if(first!=second){side=first?-1:1;report.named++;}
  }
  if(!side){report.undecided++;continue;}
  for(auto [s,t]:list){
   unsigned outer=side>0?s:t,copy=side>0?t:s;
   for(int k=0;k<3;k++){
    unsigned c=m.indices[copy*3+k];if(follow[c]!=~0u)continue;
    for(int j=0;j<3;j++){unsigned o=m.indices[outer*3+j];if(point[o]==point[c]){if(o!=c)follow[c]=o;break;}}
   }
  }
 }
 // A copy of a copy follows the end of its chain; a cycle leaves its vertices as they are.
 for(unsigned v=0;v<follow.size();v++)if(follow[v]!=~0u){
  unsigned lead=v;bool cycle=false;
  for(int step=0;step<16&&follow[lead]!=~0u;step++){lead=follow[lead];if(lead==v){cycle=true;break;}}
  if(!cycle&&lead!=v&&follow[lead]==~0u)m.twinLeads.push_back({v,lead});
 }
 // Every follower takes its lead's record as it is (the two then deform bit for bit alike); `skins` counts those
 // whose own skinning deformed differently.
 for(auto [v,lead]:m.twinLeads){
  auto& c=m.vertices[v];const auto& a=m.vertices[lead];report.followers++;
  if(!twins_detail::sameSkinning(c,a))report.skins++;
  c.type=a.type;c.bones=a.bones;c.weights=a.weights;c.c=a.c;c.r0=a.r0;c.r1=a.r1;
 }
 return report;
}

// Per vertex morph, the offsets that bring each copy vertex to its lead's offset (Model::twinMorphFixes):
// a morph that moves the outside layer moves its copy alike, and one that moves only the copy no longer
// does. `morphs` holds every morph's vertex offsets by morph index (others empty); only the entries of
// twin vertices are read. Returns the number of corrections.
inline unsigned buildTwinMorphFixes(Model& m,const std::vector<MorphOffsets>& morphs){
 m.twinMorphFixes.assign(morphs.size(),{});
 if(m.twinLeads.empty())return 0;
 std::vector<unsigned> lead(m.vertices.size(),~0u);std::unordered_map<unsigned,std::vector<unsigned>> led;
 for(auto [v,l]:m.twinLeads){lead[v]=l;led[l].push_back(v);}
 std::vector<uint32_t> stamp(m.vertices.size(),0);unsigned fixes=0;
 for(size_t i=0;i<morphs.size();i++){
  std::unordered_map<unsigned,btVector3> offset;
  for(const auto& [v,p]:morphs[i])if(v<lead.size()&&(lead[v]!=~0u||led.count(v))){auto [it,added]=offset.try_emplace(v,btVector3(0,0,0));it->second+=p;}
  if(offset.empty())continue;
  std::vector<unsigned> touched;const uint32_t mark=uint32_t(i+1);
  for(const auto& [v,p]:offset){
   if(lead[v]!=~0u&&stamp[v]!=mark){stamp[v]=mark;touched.push_back(v);}
   if(auto it=led.find(v);it!=led.end())for(auto f:it->second)if(stamp[f]!=mark){stamp[f]=mark;touched.push_back(f);}
  }
  std::sort(touched.begin(),touched.end());
  auto at=[&](unsigned v){auto it=offset.find(v);return it==offset.end()?btVector3(0,0,0):it->second;};
  for(auto f:touched){auto d=at(lead[f])-at(f);if(d.length2()>1e-14f){m.twinMorphFixes[i].push_back({f,d});fixes++;}}
 }
 m.twins.morphFixes=fixes;
 return fixes;
}
}
