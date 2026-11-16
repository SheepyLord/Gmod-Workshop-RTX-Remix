#include "mesh_prop.hpp"
#include "material_processing.hpp"
#include <algorithm>
#include <array>
#include <cmath>
#include <map>
#include <unordered_map>

namespace props {
namespace {
void warn(Asset& a,const std::string& text){auto& w=a.manifest["warnings"];if(!w.is_array())w=Json::array();w.push_back(text);}
float number(const Json& value,const char* what){
    if(!value.is_number())throw std::runtime_error(std::string("The piece's ")+what+" is not a number");
    float f=value.get<float>();if(!std::isfinite(f)||std::abs(f)>1e7f)throw std::runtime_error(std::string("The piece's ")+what+" is out of range");
    return f;
}
uint64_t whole(const Json& value,uint64_t limit,const char* what){
    // util.TableToJSON writes Lua's whole numbers as 1.0.
    double d=value.is_number()?value.get<double>():-1;
    if(!(d>=0)||d!=std::floor(d)||d>=double(limit))throw std::runtime_error(std::string("Invalid ")+what+" in the piece");
    return uint64_t(d);
}
float unit(const Json& j,const char* key,float fallback){
    if(!j.contains(key))return fallback;float f=number(j.at(key),key);return std::clamp(f,0.f,1.f);
}
std::array<float,3> rgb(const Json& j,const char* key,std::array<float,3> fallback){
    if(!j.contains(key))return fallback;auto& v=j.at(key);if(!v.is_array()||v.size()!=3)throw std::runtime_error(std::string("Invalid ")+key+" in the piece");
    return {std::clamp(number(v[0],key),0.f,1.f),std::clamp(number(v[1],key),0.f,1.f),std::clamp(number(v[2],key),0.f,1.f)};
}
// A Source material path: printable, no parent folders, at most 260 bytes.
std::string sourceMaterial(const Json& j){
    auto path=j.value("source_material",std::string());if(path.size()>260)throw std::runtime_error("A source material path is too long");
    for(unsigned char c:path)if(c<32||c==127||c=='"')throw std::runtime_error("Invalid source material path");
    if(path.find("..")!=std::string::npos||(!path.empty()&&(path[0]=='/'||path[0]=='\\')))throw std::runtime_error("Invalid source material path");
    return path;
}
// Only the fields the static prop format knows, each checked; the request comes from Lua.
Json material(const Json& src,size_t order){
    if(!src.is_object())throw std::runtime_error("Invalid material in the piece");
    auto name=src.value("name",std::string("Material"));if(name.size()>256)name.resize(256);
    std::array<float,4> color{1,1,1,1};
    if(src.contains("color")){auto& c=src.at("color");if(!c.is_array()||c.size()!=4)throw std::runtime_error("Invalid material colour in the piece");for(int k=0;k<4;k++)color[k]=std::clamp(number(c[k],"colour"),0.f,1.f);}
    auto mode=src.value("alpha_mode",std::string("opaque"));if(mode!="opaque"&&mode!="mask"&&mode!="blend")mode="opaque";
    Json m={{"source_order",order},{"name",name},{"color",color},{"two_sided",src.value("two_sided",false)==true},{"alpha_mode",mode},
        {"alpha_explicit",src.value("alpha_explicit",false)==true},{"alpha_cutoff",unit(src,"alpha_cutoff",.5f)},{"base_texture",""},{"normal_texture",""},
        {"specular",rgb(src,"specular",{0,0,0})},{"ambient",rgb(src,"ambient",{1,1,1})}};
    if(src.contains("shininess"))m["shininess"]=std::clamp(number(src.at("shininess"),"shininess"),0.f,1000.f);
    auto shading=src.value("source_shading",std::string());if(shading=="pmx"||shading=="phong"||shading=="pbr")m["source_shading"]=shading;
    if(src.contains("sphere_mode"))m["sphere_mode"]=whole(src.at("sphere_mode"),4,"sphere mode");
    if(src.contains("has_toon"))m["has_toon"]=src.at("has_toon")==true;
    auto path=sourceMaterial(src);if(!path.empty())m["source_material"]=path;
    return m;
}
}
Asset meshAsset(const Json& request,const fs::path& characterTextures,const Limits& limits,const Progress& progress){
    progress("Reading the piece",.05f);
    const auto& vertices=request.at("vertices");const auto& indices=request.at("indices");
    const auto& triangleMaterials=request.at("triangle_materials");const auto& materials=request.at("materials");
    if(!vertices.is_array()||!indices.is_array()||!triangleMaterials.is_array()||!materials.is_array())throw std::runtime_error("Invalid piece");
    if(vertices.empty()||vertices.size()%8)throw std::runtime_error("Invalid piece vertices");
    if(indices.empty()||indices.size()%3)throw std::runtime_error("Invalid piece triangles");
    const size_t vertexCount=vertices.size()/8,triangleCount=indices.size()/3;
    if(triangleMaterials.size()!=triangleCount)throw std::runtime_error("Every triangle of the piece needs a material");
    if(materials.empty()||materials.size()>limits.materials)throw std::runtime_error("Invalid number of materials in the piece");
    checkGeometryStorage(vertexCount,indices.size(),limits);
    // Triangles grouped by material, in material order; only the vertices they use are kept.
    std::vector<std::vector<uint32_t>> byMaterial(materials.size());
    for(size_t t=0;t<triangleCount;t++){
        auto m=whole(triangleMaterials[t],materials.size(),"triangle material");
        std::array<uint32_t,3> tri{};for(int k=0;k<3;k++)tri[k]=uint32_t(whole(indices[t*3+k],vertexCount,"vertex index"));
        if(tri[0]==tri[1]||tri[1]==tri[2]||tri[0]==tri[2])continue;
        byMaterial[m].insert(byMaterial[m].end(),tri.begin(),tri.end());
    }
    Asset a;std::vector<uint32_t> remap(vertexCount,UINT32_MAX);
    auto vertexAt=[&](uint32_t i){
        if(remap[i]!=UINT32_MAX)return remap[i];
        Vertex v;const size_t o=size_t(i)*8;
        v.pos={number(vertices[o],"position"),number(vertices[o+1],"position"),number(vertices[o+2],"position")};
        v.normal={number(vertices[o+3],"normal"),number(vertices[o+4],"normal"),number(vertices[o+5],"normal")};
        v.u=number(vertices[o+6],"texture coordinate");v.v=number(vertices[o+7],"texture coordinate");
        remap[i]=uint32_t(a.vertices.size());a.vertices.push_back(v);return remap[i];
    };
    Json outMaterials=Json::array(),parts=Json::array();std::map<std::string,std::string> stored;
    for(size_t m=0;m<materials.size();m++){
        if(byMaterial[m].empty())continue;
        progress("Collecting materials",.1f+.2f*float(m)/float(materials.size()),{},m,materials.size());
        const size_t slot=outMaterials.size();Json out=material(materials[m],slot);
        auto hash=materials[m].value("base_texture",std::string());
        if(!hash.empty()){
            if(!validHash(hash))throw std::runtime_error("Invalid texture reference in the piece");
            auto found=stored.find(hash);
            if(found==stored.end()){
                std::string kept;
                // The character cache keeps each texture as <SHA-256 of the PNG>.png: embedding it unchanged keeps its key.
                try{auto t=makeTexture(readFile(characterTextures/(wide(hash)+L".png"),MaxTextureFileBytes),limits.textureDimension);kept=t.hash;addTexture(a,std::move(t),out.value("name",std::string()));}
                catch(const std::exception& e){warn(a,"Texture of "+out.value("name",std::string("a material"))+": "+e.what());}
                found=stored.emplace(hash,kept).first;
            }
            out["base_texture"]=found->second;
        }
        outMaterials.push_back(out);
        uint32_t first=uint32_t(a.indices.size());for(auto i:byMaterial[m])a.indices.push_back(vertexAt(i));
        uint32_t count=uint32_t(a.indices.size())-first;
        while(count){uint32_t n=std::min(count,60000u);parts.push_back({{"material",slot},{"first",first},{"count",n}});first+=n;count-=n;}
    }
    if(a.indices.empty())throw std::runtime_error("The piece has no triangles");
    Json warnings=a.manifest.contains("warnings")?a.manifest["warnings"]:Json::array();
    auto name=request.value("name",std::string("Piece"));
    a.manifest={{"version",1},{"name",name},{"format","separator"},{"materials",outMaterials},{"parts",parts},{"warnings",warnings}};
    if(request.contains("separated_from")&&request["separated_from"].is_object()){
        const auto& s=request["separated_from"];Json from=Json::object();
        for(auto key:{"kind","asset","model","pose"})if(s.contains(key)&&s[key].is_string()&&s[key].get<std::string>().size()<=260)from[key]=s[key];
        for(auto key:{"skin","bodygroups"})if(s.contains(key)&&(s[key].is_number_integer()||s[key].is_string()))from[key]=s[key];
        a.manifest["separated_from"]=from;
    }
    // Normals: a zero one takes its triangles'; tangents from the UVs, as the PMX importer derives them.
    progress("Generating tangents",.32f);
    std::vector<Vec> faces(a.vertices.size()),ts(a.vertices.size()),bs(a.vertices.size());
    for(size_t i=0;i<a.indices.size();i+=3){
        auto i0=a.indices[i],i1=a.indices[i+1],i2=a.indices[i+2];auto& p=a.vertices[i0];auto& q=a.vertices[i1];auto& s=a.vertices[i2];
        Vec e=q.pos-p.pos,f=s.pos-p.pos,n=e.cross(f);for(auto k:{i0,i1,i2})faces[k]=faces[k]+n;
        float u=q.u-p.u,v=q.v-p.v,u2=s.u-p.u,v2=s.v-p.v,d=u*v2-u2*v;if(std::abs(d)<1e-10f)continue;
        Vec t=(e*v2-f*v)*(1/d),b=(f*u-e*u2)*(1/d);for(auto k:{i0,i1,i2}){ts[k]=ts[k]+t;bs[k]=bs[k]+b;}
    }
    for(size_t i=0;i<a.vertices.size();i++){
        auto& v=a.vertices[i];if(v.normal.length()<1e-6f)v.normal=faces[i];v.normal=v.normal.normalized();
        auto t=(ts[i]-v.normal*ts[i].dot(v.normal)).normalized();v.tangent={t.x,t.y,t.z,v.normal.cross(t).dot(bs[i])<0?-1.f:1.f};
    }
    progress("Analyzing materials",.4f);
    analyzeMaterials(a,progress);
    a.manifest["triangles"]=a.indices.size()/3;a.manifest["vertices"]=a.vertices.size();
    warnLargeGeometry(a.manifest,a.vertices.size(),a.indices.size(),limits);
    updateBounds(a);
    return a;
}
PieceShape measurePiece(const Asset& a){
    PieceShape shape;
    // Welded by position (to a thousandth of a unit): UV and material seams are not openings.
    struct Key{int64_t x,y,z;bool operator==(const Key& o)const{return x==o.x&&y==o.y&&z==o.z;}};
    struct Hash{size_t operator()(const Key& k)const{return size_t(k.x*73856093^k.y*19349663^k.z*83492791);}};
    std::unordered_map<Key,uint32_t,Hash> ids;std::vector<uint32_t> welded(a.vertices.size());
    for(size_t i=0;i<a.vertices.size();i++){auto& p=a.vertices[i].pos;Key k{int64_t(std::llround(p.x*1000.)),int64_t(std::llround(p.y*1000.)),int64_t(std::llround(p.z*1000.))};
        welded[i]=ids.emplace(k,uint32_t(ids.size())).first->second;}
    std::unordered_map<uint64_t,uint32_t> edges;double volume=0;
    for(size_t i=0;i<a.indices.size();i+=3){
        std::array<uint32_t,3> w{welded[a.indices[i]],welded[a.indices[i+1]],welded[a.indices[i+2]]};
        for(int k=0;k<3;k++){uint32_t x=w[k],y=w[(k+1)%3];if(x==y)continue;uint64_t key=uint64_t(std::min(x,y))<<32|std::max(x,y);edges[key]++;}
        auto& p0=a.vertices[a.indices[i]].pos;auto& p1=a.vertices[a.indices[i+1]].pos;auto& p2=a.vertices[a.indices[i+2]].pos;
        volume+=double(p0.dot(p1.cross(p2)))/6.0;
    }
    shape.edges=edges.size();for(auto& [key,uses]:edges)if(uses==1)shape.boundaryEdges++;
    shape.volume=std::abs(volume);
    try{
        auto hull=makeFastHull(a);Vec c{0,0,0};for(auto& p:hull.points)c=c+p;c=c*(1.f/float(std::max<size_t>(1,hull.points.size())));
        double h=0;for(size_t i=0;i+2<hull.indices.size();i+=3){auto& p0=hull.points[hull.indices[i]];auto& p1=hull.points[hull.indices[i+1]];auto& p2=hull.points[hull.indices[i+2]];h+=std::abs(double((p0-c).dot((p1-c).cross(p2-c))))/6.0;}
        shape.hullVolume=h;
    }catch(...){shape.hullVolume=0;}
    return shape;
}
std::string automaticCollision(const Asset& a){
    if(a.indices.size()<36)return "hull";
    // A small piece (a hairpin, an earring) gains nothing from a decomposition: CoACD cuts it into slivers far below a
    // unit, which the game's physics may refuse. Under 12 units across it keeps the fast hull.
    Vec lo{INFINITY,INFINITY,INFINITY},hi{-INFINITY,-INFINITY,-INFINITY};
    for(auto& v:a.vertices){lo={std::min(lo.x,v.pos.x),std::min(lo.y,v.pos.y),std::min(lo.z,v.pos.z)};hi={std::max(hi.x,v.pos.x),std::max(hi.y,v.pos.y),std::max(hi.z,v.pos.z)};}
    if(std::max({hi.x-lo.x,hi.y-lo.y,hi.z-lo.z})<12.f)return "hull";
    auto shape=measurePiece(a);
    // An open shell (cloth, a hair card, most accessories): CoACD needs a closed surface to find its inside.
    if(shape.edges==0||shape.boundaryEdges*50>shape.edges)return "hull";
    if(shape.hullVolume<=0)return "hull";
    // A closed piece that fills little of its hull is concave: a ring, a bow, a cup. One with almost no volume is a
    // flat double layer (a sheet and its back-face copy): there is no inside for CoACD to find.
    const double fill=shape.volume/shape.hullVolume;
    return fill>=.02&&fill<.55?"balanced":"hull";
}
}
