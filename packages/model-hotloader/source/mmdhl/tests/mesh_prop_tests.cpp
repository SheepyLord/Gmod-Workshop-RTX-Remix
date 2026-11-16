// The mesh separator's prop job (native/props/mesh_prop.hpp): a request's triangles become a valid static prop with
// its materials (an embedded character texture, a Source material), the automatic collision choice (a compact box, a
// concave closed ring, an open sheet), and invalid requests are refused. argv[1]: a scratch folder.
#include "mesh_prop.hpp"
#include <array>
#include <iostream>
#include <utility>
using namespace props;
static void check(bool ok,const std::string& why){if(!ok)throw std::runtime_error(why);}
struct Builder {
    Json vertices=Json::array(),indices=Json::array(),triangles=Json::array();
    // An axis-aligned box, outward counter-clockwise (Source's +Z up), material m.
    void box(Vec lo,Vec hi,unsigned m){
        const unsigned base=unsigned(vertices.size()/8);
        for(int i=0;i<8;i++){Vec p{i&1?hi.x:lo.x,i&2?hi.y:lo.y,i&4?hi.z:lo.z};for(float v:{p.x,p.y,p.z,0.f,0.f,0.f,float(i&1),float((i>>1)&1)})vertices.push_back(v);}
        const unsigned faces[12][3]={{0,2,1},{1,2,3},{4,5,6},{5,7,6},{0,1,4},{1,5,4},{2,6,3},{3,6,7},{0,4,2},{2,4,6},{1,3,5},{3,7,5}};
        for(auto& f:faces){for(int k=0;k<3;k++)indices.push_back(base+f[k]);triangles.push_back(m);}
    }
    // A flat n x n grid of quads at z, facing +Z, or -Z (a back-face copy) when flipped.
    void sheet(int n,float z,bool flipped,unsigned m){
        const unsigned base=unsigned(vertices.size()/8);
        for(int j=0;j<=n;j++)for(int i=0;i<=n;i++)for(float v:{float(i),float(j),z,0.f,0.f,flipped?-1.f:1.f,float(i)/n,float(j)/n})vertices.push_back(v);
        auto at=[&](int i,int j){return base+unsigned(j*(n+1)+i);};
        for(int j=0;j<n;j++)for(int i=0;i<n;i++){
            std::array<unsigned,6> t{at(i,j),at(i+1,j),at(i+1,j+1),at(i,j),at(i+1,j+1),at(i,j+1)};
            if(flipped){std::swap(t[1],t[2]);std::swap(t[4],t[5]);}
            for(auto k:t)indices.push_back(k);triangles.push_back(m);triangles.push_back(m);
        }
    }
    Json request(Json materials)const{return {{"name","Piece"},{"vertices",vertices},{"indices",indices},{"triangle_materials",triangles},{"materials",materials}};}
};
static bool throws(const Json& request,const fs::path& textures){try{meshAsset(request,textures,fullTextureLimits(),{});}catch(const std::exception&){return true;}return false;}
int main(int argc,char** argv){try{
    check(argc>1,"Pass a scratch folder");
    fs::path scratch=argv[1];fs::remove_all(scratch);fs::create_directories(scratch/"textures");
    // A 2x2 RGBA PNG in the character cache's way: <SHA-256 of its bytes>.png.
    static const uint8_t png[]={137,80,78,71,13,10,26,10,0,0,0,13,73,72,68,82,0,0,0,2,0,0,0,2,8,6,0,0,0,114,182,13,36,0,0,0,20,73,68,65,84,120,218,99,56,161,161,241,95,227,132,198,127,6,24,3,0,72,196,8,93,121,124,77,129,0,0,0,0,73,69,78,68,174,66,96,130};
    const std::string hash=sha256(std::span<const uint8_t>(png,sizeof png));writeAtomic(scratch/"textures"/(hash+".png"),std::span<const uint8_t>(png,sizeof png));
    Json materials=Json::array({{{"name","cloth"},{"base_texture",hash},{"source_material","mmd/0123456789abcdef/cloth"},{"color",{1,1,1,1}},{"two_sided",true}},
        {{"name","metal"},{"source_material","models/props_c17/metalladder001"},{"specular",{.5,.5,.5}},{"shininess",40}},{{"name","unused"}}});
    // A box (cloth) beside a box (metal); the third material has no triangle.
    Builder b;b.box({-2,-1,-1},{0,1,1},0);b.box({0,-1,-1},{2,1,1},1);
    auto a=meshAsset(b.request(materials),scratch/"textures",fullTextureLimits(),{});
    check(a.indices.size()==72&&a.vertices.size()==16,"Geometry not kept");
    check(a.manifest["materials"].size()==2,"An unused material was kept");
    check(a.manifest["materials"][0]["source_material"]=="mmd/0123456789abcdef/cloth"&&a.manifest["materials"][1]["source_material"]=="models/props_c17/metalladder001","Source materials lost");
    check(a.textures.size()==1&&a.manifest["materials"][0]["base_texture"]==a.textures[0].hash&&a.manifest["materials"][1]["base_texture"]=="","The character texture was not embedded");
    check(a.manifest["parts"].size()==2&&a.manifest["parts"][1]["first"]==36,"Parts not grouped by material");
    for(auto& v:a.vertices)check(std::abs(v.normal.length()-1)<1e-3f,"A zero normal was not replaced");
    check(automaticCollision(a)=="hull","Two boxes side by side are compact");
    // Through the static prop pipeline: collision, save, load.
    makeCollision(a,"hull",{});auto id=saveAsset(scratch/"static",a,{},fullTextureLimits());
    auto loaded=loadAsset(scratch/"static",id,fullTextureLimits());
    check(loaded.indices.size()==72&&loaded.manifest["materials"][1]["source_material"]=="models/props_c17/metalladder001","The saved piece differs");
    // A missing texture: a warning and no texture, not a failure.
    Json missing=materials;missing[0]["base_texture"]=std::string(64,'a');
    auto m=meshAsset(b.request(missing),scratch/"textures",fullTextureLimits(),{});
    check(m.textures.empty()&&m.manifest["materials"][0]["base_texture"]==""&&!m.manifest["warnings"].empty(),"A missing texture was not reported");
    // A closed ring that fills little of its hull is concave: CoACD.
    Builder ring;ring.box({-10,-10,0},{10,-8,1},1);ring.box({-10,8,0},{10,10,1},1);ring.box({-10,-8,0},{-8,8,1},1);ring.box({8,-8,0},{10,8,1},1);
    auto r=meshAsset(ring.request(materials),scratch/"textures",fullTextureLimits(),{});auto shape=measurePiece(r);
    check(shape.boundaryEdges==0&&shape.volume>0&&shape.hullVolume>shape.volume,"The ring was measured wrongly");
    check(automaticCollision(r)=="balanced","A concave ring did not get a decomposition ("+std::to_string(shape.volume/shape.hullVolume)+")");
    // The same ring a tenth of the size (2 units across, a hairpin's size) keeps the fast hull.
    Builder small;small.box({-1,-1,0},{1,-.8f,.1f},1);small.box({-1,.8f,0},{1,1,.1f},1);small.box({-1,-.8f,0},{-.8f,.8f,.1f},1);small.box({.8f,-.8f,0},{1,.8f,.1f},1);
    check(automaticCollision(meshAsset(small.request(materials),scratch/"textures",fullTextureLimits(),{}))=="hull","A small concave piece got a decomposition");
    // An open sheet keeps the fast hull; so does a sheet with its back-face copy (closed, but without volume).
    Builder open;open.sheet(4,0,false,0);
    check(automaticCollision(meshAsset(open.request(materials),scratch/"textures",fullTextureLimits(),{}))=="hull","An open sheet got a decomposition");
    Builder layered;layered.sheet(4,0,false,0);layered.sheet(4,0,true,1);
    auto l=meshAsset(layered.request(materials),scratch/"textures",fullTextureLimits(),{});
    check(measurePiece(l).boundaryEdges==0&&automaticCollision(l)=="hull","A sheet with its back-face copy got a decomposition");
    // Refused requests.
    auto bad=b.request(materials);bad["indices"][0]=999;check(throws(bad,scratch/"textures"),"A vertex index out of range was accepted");
    bad=b.request(materials);bad["triangle_materials"][0]=7;check(throws(bad,scratch/"textures"),"A material out of range was accepted");
    bad=b.request(materials);bad["materials"][0]["source_material"]="../../cfg/autoexec";check(throws(bad,scratch/"textures"),"A parent folder in a source material was accepted");
    bad=b.request(materials);bad["vertices"][0]=1e30;check(throws(bad,scratch/"textures"),"A position out of range was accepted");
    bad=b.request(materials);bad["triangle_materials"].erase(0);check(throws(bad,scratch/"textures"),"A triangle without material was accepted");
    bad=b.request(materials);bad["materials"][0]["base_texture"]="../x";check(throws(bad,scratch/"textures"),"An invalid texture reference was accepted");
    std::cout<<"Mesh separator props: materials, embedded texture, save and load, automatic collision ("<<shape.volume/shape.hullVolume<<" for the ring), refusals passed\n";
    return 0;
}catch(const std::exception& e){std::cerr<<e.what()<<'\n';return 1;}}
