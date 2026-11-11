// SPDX-License-Identifier: MIT
// Explicit real-hardware test, never a CTest. The runtime can be the stand-in when VR-C is absent.
#include "session.h"
#include "nl/fs.h"
#include "nl/json.h"
#include <windows.h>
#include <algorithm>
#include <cstdio>
#include <fstream>
#include <thread>

namespace {
struct Lock {
  std::filesystem::path path;
  HANDLE file=INVALID_HANDLE_VALUE;
  explicit Lock(std::filesystem::path p):path(std::move(p)) {
    file=CreateFileW(path.c_str(),GENERIC_WRITE,0,nullptr,CREATE_NEW,FILE_ATTRIBUTE_NORMAL,nullptr);
    if(file==INVALID_HANDLE_VALUE) throw std::runtime_error("VR lock is occupied or unavailable");
    SYSTEMTIME t{};GetSystemTime(&t);char text[128]{};
    const int n=sprintf_s(text,"VR-V1-D %04u-%02u-%02uT%02u:%02u:%02uZ\n",t.wYear,t.wMonth,t.wDay,t.wHour,t.wMinute,t.wSecond);
    DWORD written=0;WriteFile(file,text,static_cast<DWORD>(n),&written,nullptr);FlushFileBuffers(file);
  }
  ~Lock() { if(file!=INVALID_HANDLE_VALUE) { CloseHandle(file);DeleteFileW(path.c_str()); } }
};
}
int wmain(int argc,wchar_t** argv) {
  if(argc!=8) {
    std::fprintf(stderr,"usage: nl_vr_session_host <openvr.dll> <runtime.dll> <manifest.json> <timeline.json|-> <seconds> <vr.lock> <log.jsonl>\n");return 2;
  }
  try {
    const double seconds=std::stod(argv[5]);if(seconds<1||seconds>600) throw std::runtime_error("seconds must be 1-600");
    Lock lock(argv[6]);std::ofstream out(argv[7]);if(!out) throw std::runtime_error("cannot open host log");
    out<<"{\"test_runtime\":true,\"real_eye_submission\":false}\n";out.flush();
    nl::vr::Options options;options.openvr_dll=argv[1];options.runtime_dll=argv[2];options.manifest=argv[3];options.no_submit=true;
    if(std::wstring(argv[4])!=L"-") options.timeline=argv[4];
    nl::vr::Session session(std::filesystem::path(argv[1]).parent_path());
    for(int cycle=1;cycle<=2;++cycle) {
      std::string error;if(!session.start(options,error)) throw std::runtime_error(error);
      const auto start=std::chrono::steady_clock::now();
      while(session.state().first=="starting") {
        if(std::chrono::steady_clock::now()-start>std::chrono::seconds(120)) throw std::runtime_error("start timed out");
        std::this_thread::sleep_for(std::chrono::milliseconds(20));
      }
      const auto [state,detail]=session.state();
      if(state!="running") throw std::runtime_error(detail);
      const auto facts=session.info();
      out<<"{\"cycle\":"<<cycle<<",\"model\":"<<nl::json::quote(facts.model)<<",\"refresh\":"<<facts.refresh<<",\"eye_width\":"<<facts.eye_width<<",\"eye_height\":"<<facts.eye_height<<"}\n";
      const auto handle=session.overlay_create("nativeloader.vr.d.host","VR-D session test");
      session.begin_frame();session.overlay_attach(handle,"left",{.1f,0,0},{0,0,0},.2f);session.overlay_show(handle,true);
      session.overlay_source(handle,513,257); // Stand-in renderer records the normal module request only.
      out<<"{\"cycle\":"<<cycle<<",\"overlay_visible\":"<<(session.overlay_visible(handle)?"true":"false")
        <<",\"left_haptic_error\":"<<session.haptic("left",.01f,100,.1f)<<",\"right_haptic_error\":"<<session.haptic("right",.01f,100,.1f)<<"}\n";out.flush();
      const auto begin=std::chrono::steady_clock::now();uint64_t frames=0,valid=0;double sum=0,max=0;
      std::map<int,uint64_t> input_errors;uint64_t reads=0;
      bool grip_true=false,grip_false=false;float stick_min=1,stick_max=-1;
      do {
        const auto f=session.begin_frame();if(!f) throw std::runtime_error("no frame");
        ++frames;if(f->poses[0].valid) ++valid;sum+=f->wait_ms;max=std::max(max,f->wait_ms);
        session.set_camera(f->sequence,f->poses[0].pos*options.scale,f->poses[0].ang);
        if(frames==1||frames%200==0) {
          const auto script=session.test_state();
          out<<"{\"cycle\":"<<cycle<<",\"sequence\":"<<f->sequence<<",\"head\":["<<f->poses[0].pos.x<<','<<f->poses[0].pos.y<<','<<f->poses[0].pos.z
            <<"],\"left_valid\":"<<(f->poses[1].valid?"true":"false")<<",\"right_valid\":"<<(f->poses[2].valid?"true":"false")
            <<",\"scripted\":"<<(script?"true":"false");
          if(script) out<<",\"timeline_time\":"<<script->time<<",\"timeline_ended\":"<<(script->ended?"true":"false");
          out<<"}\n";out.flush();
        }
        for(const auto& [name,a]:session.actions()) {
          ++input_errors[a.error];++reads;
          if(name=="left_grip") { grip_true=grip_true||a.state;grip_false=grip_false||!a.state; }
          if(name=="left_stick") { stick_min=std::min(stick_min,a.value.x);stick_max=std::max(stick_max,a.value.x); }
        }
        for(const auto& e:session.events()) {
          out<<"{\"event\":"<<nl::json::quote(e.type)<<",\"code\":"<<e.code<<"}\n";
          if(e.type=="quit") throw std::runtime_error("SteamVR asked the scene application to quit");
        }
      } while(std::chrono::duration<double>(std::chrono::steady_clock::now()-begin).count()<seconds);
      const auto info=session.info();
      const auto elapsed=std::chrono::duration<double>(std::chrono::steady_clock::now()-begin).count();
      out<<"{\"cycle\":"<<cycle<<",\"frames\":"<<frames<<",\"valid_head\":"<<valid<<",\"wait_mean_ms\":"<<sum/static_cast<double>(frames)
        <<",\"wait_max_ms\":"<<max<<",\"elapsed_seconds\":"<<elapsed<<",\"wait_calls_per_second\":"<<static_cast<double>(frames)/elapsed
        <<",\"grip_true\":"<<(grip_true?"true":"false")<<",\"grip_false\":"<<(grip_false?"true":"false")
        <<",\"stick_min\":"<<stick_min<<",\"stick_max\":"<<stick_max<<",\"action_reads\":"<<reads<<",\"input_errors\":{";
      bool first=true;for(const auto& [code,n]:input_errors) { if(!first) out<<',';first=false;out<<'"'<<code<<"\":"<<n; }
      out<<"},\"timing_valid\":"<<(info.timing_valid?"true":"false")<<",\"presents\":"<<info.cumulative.m_nNumFramePresents
        <<",\"dropped\":"<<info.cumulative.m_nNumDroppedFrames<<",\"reprojected\":"<<info.cumulative.m_nNumReprojectedFrames<<"}\n";
      session.stop();
      const auto stop_deadline=std::chrono::steady_clock::now()+std::chrono::seconds(10);
      while(session.state().first=="stopping"&&std::chrono::steady_clock::now()<stop_deadline)
        std::this_thread::sleep_for(std::chrono::milliseconds(1));
      if(session.state().first!="off") throw std::runtime_error("session teardown did not finish");
      out<<"{\"cycle\":"<<cycle<<",\"stopped\":true}\n";out.flush();
    }
    return 0;
  } catch(const std::exception& e) { std::fprintf(stderr,"VR-D host: %s\n",e.what());return 1; }
}
