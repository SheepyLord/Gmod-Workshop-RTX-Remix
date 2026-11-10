#include "core.hpp"
#ifdef _WIN32
#include <windows.h>
#else
#include "../posix.hpp"
#include "release.hpp"
#include <dlfcn.h>
#endif
#include <meshoptimizer.h>
#include <algorithm>
#include <cstdio>
#include <memory>
#include <string>
#include <thread>

namespace props {
// Stable C ABI from the pinned CoACD 1.0.14 wheel (see dependencies.lock.json).
struct CoMesh{double* vertices;uint64_t vertexCount;int* triangles;uint64_t triangleCount;};
struct CoArray{CoMesh* meshes;uint64_t count;};
using CoRun=CoArray(*)(const CoMesh*,double,int,int,int,int,int,int,int,bool,bool,bool,int,bool,double,int,unsigned,bool);
namespace {
void warn(Asset& a,const std::string& text){auto& w=a.manifest["warnings"];if(!w.is_array())w=Json::array();w.push_back(text);}
#ifdef _WIN32
// Detailed collision's percentage. CoACD has no progress callback, but at log level "info" it
// writes each decomposition pass to standard output (spdlog): "iter N ---- waiting pool: K"
// and "Processing [x%]" within a pass. The game starts the worker without a console, so while
// CoACD runs, standard output is a pipe that a thread here reads. Each pass splits every piece
// that is still too concave in two, so a piece finished in pass N is 2^-N of the mesh, and the
// finished pieces' shares add up to exactly 1 at the end: that sum, with the number of passes
// done, gives the passes' share. The merge down to 16 hulls logs nothing until it ends; its
// time grows with the square of the pieces it merges (each pair is costed), so it is estimated
// from that count, approaching its end without reaching it. Measured (2026-11-10, this
// machine): a 1,584-triangle flower 20 passes and 246 pieces in 21 s, then a 24-27 s merge;
// a 39,147-triangle character 10 passes and 36 pieces in 5 s, then a 2 s merge.
class CoacdProgress {
    const Progress& progress;const float from,to;
    HANDLE readEnd=nullptr,writeEnd=nullptr,previous=nullptr;
    std::thread reader;std::atomic<bool> stopping{false};
    std::string phase="prepare",pending,shownDetail;
    std::vector<double> pools;double finished=0,pieces=0,passFraction=0,shown=0;uint64_t mergeStarted=0;
    static constexpr double PassesEnd=.55,MergeEnd=.97;
    void line(const std::string& text){
        auto tag=text.find("] [CoACD] [");if(tag==std::string::npos)return;
        auto close=text.find("] ",tag+11);if(close==std::string::npos)return;
        const std::string message=text.substr(close+2);
        int pass=0;double pool=0,value=0;
        if(message.starts_with(" - Preprocess"))phase="prepare";
        else if(message.starts_with(" - Decomposition"))phase="passes";
        else if(std::sscanf(message.c_str(),"iter %d ---- waiting pool: %lf",&pass,&pool)==2){
            if(!pools.empty()){double done=std::max(0.,pools.back()-pool/2);finished=std::min(1.,finished+done*std::ldexp(1.,-int(pools.size()-1)));pieces+=done;}
            pools.push_back(pool);passFraction=0;phase="passes";
        }
        else if(message.starts_with("Processing [")&&std::sscanf(message.c_str()+12,"%lf",&value)==1)passFraction=std::max(passFraction,std::clamp(value/100,0.,1.));
        else if(message.starts_with(" - Merge Convex Hulls")){if(!pools.empty())pieces+=pools.back();finished=1;phase="merge";mergeStarted=GetTickCount64();}
        else if(message.starts_with(" - Simplify"))phase="simplify";
    }
    double fraction(uint64_t now) const {
        if(phase=="prepare")return .01;
        if(phase=="passes"){
            if(pools.empty())return .03;
            // Within a pass, assume a quarter of what is left finishes.
            double reached=finished+(1-finished)*.25*passFraction;
            double share=.5*(1-std::cbrt(std::max(0.,1-reached)))+.5*(1-std::pow(.85,double(pools.size()-1)+passFraction));
            return .03+(PassesEnd-.03)*share;
        }
        if(phase=="merge"){
            double seconds=std::max(.05,std::max(1.,pieces*pieces-128)*.0006/1.5);
            return PassesEnd+(MergeEnd-PassesEnd)*(1-std::exp(-double(now-mergeStarted)/1000/seconds));
        }
        return .98;
    }
    std::string detail() const {
        if(phase=="passes"&&!pools.empty())return "Pass "+std::to_string(pools.size())+": "+std::to_string(std::llround(pools.back()))+" pieces to split, "+std::to_string(std::llround(pieces))+" finished";
        if(phase=="merge")return "Merging "+std::to_string(std::llround(pieces))+" pieces into at most 16 hulls (time estimated)";
        if(phase=="simplify")return "Simplifying the hulls";
        return "Preparing the collision mesh";
    }
    void publish(uint64_t now){
        double value=std::min(.99,std::max(shown,fraction(now)));auto text=detail();
        if(value-shown<.0005&&text==shownDetail)return;
        shown=value;shownDetail=text;
        try{progress("Decomposing collision",from+(to-from)*float(shown),text,0,0,false);}catch(...){}
    }
    void read(){
        char buffer[4096];uint64_t reported=0;
        for(;;){
            DWORD available=0,count=0;bool got=false;
            if(PeekNamedPipe(readEnd,nullptr,0,nullptr,&available,nullptr)&&available&&ReadFile(readEnd,buffer,std::min<DWORD>(available,sizeof buffer),&count,nullptr)&&count){
                got=true;pending.append(buffer,count);size_t start=0;
                for(size_t end;(end=pending.find('\n',start))!=std::string::npos;start=end+1){auto text=pending.substr(start,end-start);if(!text.empty()&&text.back()=='\r')text.pop_back();line(text);}
                pending.erase(0,start);if(pending.size()>65536)pending.clear();
            }
            auto now=GetTickCount64();if(now-reported>=150){reported=now;publish(now);}
            if(!got){if(stopping)break;Sleep(50);}
        }
        publish(GetTickCount64());
    }
public:
    // Before CoACD loads: its logger keeps the standard output it finds when it is made.
    CoacdProgress(const Progress& report,float first,float last):progress(report),from(first),to(last){
        SECURITY_ATTRIBUTES attributes{sizeof(attributes),nullptr,FALSE};
        if(!CreatePipe(&readEnd,&writeEnd,&attributes,1<<16)){readEnd=writeEnd=nullptr;return;}
        previous=GetStdHandle(STD_OUTPUT_HANDLE);
        if(!SetStdHandle(STD_OUTPUT_HANDLE,writeEnd)){CloseHandle(readEnd);CloseHandle(writeEnd);readEnd=writeEnd=nullptr;}
    }
    CoacdProgress(const CoacdProgress&)=delete;CoacdProgress& operator=(const CoacdProgress&)=delete;
    ~CoacdProgress(){finish();}
    bool capturing() const {return readEnd!=nullptr;}
    void start(){if(readEnd&&!reader.joinable())reader=std::thread([this]{read();});}
    // After CoACD returned and its log was turned off: the rest is read, standard output is put
    // back. CoACD keeps the write end (its logger holds it), so only the read end is closed: a
    // write after this fails instead of waiting for a reader.
    void finish(){
        if(!readEnd)return;
        stopping=true;if(reader.joinable())reader.join();
        SetStdHandle(STD_OUTPUT_HANDLE,previous);CloseHandle(readEnd);readEnd=nullptr;
    }
};
#endif
void fastCollision(Asset& a,const Progress& progress){
    std::string note;a.hulls={makeFastHull(a,progress,&note)};
    a.manifest["collision_method"]=note.empty()?"direct_support_hull_26":"bounding_box";
    a.manifest["collision_triangles"]=a.indices.size()/3;
    if(!note.empty())warn(a,note);
    progress("Validating collision hulls",.86f,{},1,1);
    parseHulls(hullJson(a.hulls));
}
void detailedCollision(Asset& a,const std::string& mode,const Progress& progress);
}
// The import never fails because of collision: detailed decomposition falls
// back to the fast single hull, which falls back to a thickened bounding box.
void makeCollision(Asset& a,const std::string& mode,const Progress& progress){
    if(mode!="hull"){
        try{detailedCollision(a,mode,progress);a.manifest["collision_method"]="coacd";return;}
        catch(const std::exception& e){a.hulls.clear();warn(a,std::string("Detailed collision failed (")+e.what()+"); a single enclosing hull is used instead.");}
    }
    fastCollision(a,progress);
}
namespace {
void detailedCollision(Asset& a,const std::string& mode,const Progress& progress){
    // CoACD owns runtime threads. Keep its DLL loaded until this short-lived worker exits.
#ifdef _WIN32
    // Its percentage comes from its log (CoacdProgress), on standard output from before it loads.
    auto watch=std::make_unique<CoacdProgress>(progress,.65f,.86f);
    wchar_t path[32768];GetModuleFileNameW(nullptr,path,32768);auto dllPath=fs::path(path).parent_path()/L"lib_coacd.dll";HMODULE library=LoadLibraryExW(dllPath.c_str(),nullptr,LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR|LOAD_LIBRARY_SEARCH_DEFAULT_DIRS);if(!library)throw std::runtime_error("Cannot load CoACD: install lib_coacd.dll beside the worker and Microsoft Visual C++ 2015-2022 x64 Redistributable (VCOMP140)");
    auto run=reinterpret_cast<CoRun>(GetProcAddress(library,"CoACD_run"));auto freeMesh=reinterpret_cast<void(*)(CoArray)>(GetProcAddress(library,"CoACD_freeMeshArray"));auto log=reinterpret_cast<void(*)(const char*)>(GetProcAddress(library,"CoACD_setLogLevel"));if(!run||!freeMesh){FreeLibrary(library);throw std::runtime_error("CoACD ABI mismatch");}
    const bool counted=log&&watch->capturing();if(log)log(counted?"info":"error");
    // Without its log level nothing reads the pipe: standard output goes back before CoACD writes there.
    if(!counted)watch->finish();
#else
    // lib_coacd.so takes its OpenMP runtime from beside it (RPATH $ORIGIN).
    auto soPath=mmd::posix::executablePath().parent_path()/MMDHL_COACD_FILE;void* library=dlopen(soPath.c_str(),RTLD_NOW|RTLD_LOCAL);
    if(!library){auto why=dlerror();throw std::runtime_error(std::string("Cannot load CoACD: install ")+MMDHL_COACD_FILE+" and its libgomp beside the worker ("+(why?why:"unknown error")+")");}
    auto run=reinterpret_cast<CoRun>(dlsym(library,"CoACD_run"));auto freeMesh=reinterpret_cast<void(*)(CoArray)>(dlsym(library,"CoACD_freeMeshArray"));auto log=reinterpret_cast<void(*)(const char*)>(dlsym(library,"CoACD_setLogLevel"));if(!run||!freeMesh){dlclose(library);throw std::runtime_error("CoACD ABI mismatch");}if(log)log("error");
#endif
    // Welding by position is essential: UV/material seams are not holes in the collider.
    progress("Welding collision geometry",.55f,{},0,a.indices.size()/3);
    std::vector<unsigned> remap(a.vertices.size());meshopt_generatePositionRemap(remap.data(),reinterpret_cast<const float*>(&a.vertices[0].pos),a.vertices.size(),sizeof(Vertex));
    std::vector<Vec> vertices(a.vertices.size());for(size_t i=0;i<a.vertices.size();i++)vertices[remap[i]]=a.vertices[i].pos;
    std::vector<unsigned> indices(a.indices.size());for(size_t i=0;i<indices.size();i++)indices[i]=remap[a.indices[i]];
    progress("Simplifying collision geometry",.58f,"Visual geometry is preserved",0,indices.size()/3);
    if(indices.size()>18000){std::vector<unsigned> simplified(indices.size());auto n=meshopt_simplify(simplified.data(),indices.data(),indices.size(),reinterpret_cast<const float*>(vertices.data()),vertices.size(),sizeof(Vec),18000,.025f,0,nullptr);if(n>=12){simplified.resize(n);indices=std::move(simplified);}}
    std::vector<unsigned> dense(vertices.size(),~0u);std::vector<double> xyz;std::vector<int> tris;for(auto i:indices){if(dense[i]==~0u){dense[i]=unsigned(xyz.size()/3);auto p=vertices[i];xyz.insert(xyz.end(),{p.x,p.y,p.z});}tris.push_back(int(dense[i]));}
    CoMesh mesh{xyz.data(),xyz.size()/3,tris.data(),tris.size()/3};a.manifest["collision_triangles"]=mesh.triangleCount;
#ifdef _WIN32
    if(counted){progress("Decomposing collision",.65f,std::to_string(mesh.triangleCount)+" collision triangles",0,0,false);watch->start();}
    else
#endif
    progress(mode=="hull"?"Building outer hull":"Decomposing collision",.65f,std::to_string(mesh.triangleCount)+" collision triangles; this stage has no percentage estimate",0,0,true);
    CoArray result=run(&mesh,mode=="hull"?1.0:.05,mode=="hull"?1:16,0,30,600,8,20,2,false,true,true,64,false,.01,0,0,false);
#ifdef _WIN32
    // Nothing more goes to the pipe; then the reader stops and standard output is put back.
    if(counted)log("off");
    watch->finish();
#endif
    progress("Validating collision hulls",.86f,{},result.count,result.count);
    size_t repaired=0,dropped=0;
    try{
        if(!result.count||result.count>16)throw std::runtime_error("the decomposition returned "+std::to_string(result.count)+" pieces");
        for(size_t i=0;i<result.count;i++){
            auto& src=result.meshes[i];Hull h;
            for(size_t v=0;v<src.vertexCount;v++)h.points.push_back({float(src.vertices[v*3]),float(src.vertices[v*3+1]),float(src.vertices[v*3+2])});
            bool valid=src.vertexCount>=4&&src.vertexCount<=64&&src.triangleCount<=128;
            for(size_t t=0;valid&&t<src.triangleCount*3;t++){if(src.triangles[t]<0||uint64_t(src.triangles[t])>=src.vertexCount)valid=false;else h.indices.push_back(uint32_t(src.triangles[t]));}
            if(valid)try{parseHulls(hullJson({h}));}catch(...){valid=false;}
            // Sliver faces or too many points: rebuild the piece from its points.
            if(!valid){try{h=hullFromPoints(h.points);++repaired;}catch(...){++dropped;continue;}}
            a.hulls.push_back(std::move(h));
        }
        if(a.hulls.empty())throw std::runtime_error("no usable pieces");
        parseHulls(hullJson(a.hulls));
    }catch(...){freeMesh(result);throw;}
    freeMesh(result);
    if(repaired||dropped)warn(a,"Detailed collision: "+std::to_string(repaired)+" piece(s) rebuilt and "+std::to_string(dropped)+" degenerate piece(s) skipped.");
}
}
}
