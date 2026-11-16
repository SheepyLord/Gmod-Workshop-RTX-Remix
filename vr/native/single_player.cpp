// SPDX-License-Identifier: MIT
#include "single_player.h"
#include <windows.h>
#include <cstddef>
#include <cstdint>

namespace nl::vr {
bool local_single_player(const GameFacts& facts) {
  return facts.connected&&facts.channel&&facts.loopback&&!facts.demo&&facts.max_clients==1;
}
std::string not_single_player(const GameFacts& facts) {
  if(!facts.connected) return "the game is not in a map";
  if(facts.demo) return "a demo is playing";
  if(!facts.channel) return "the game has no connection to its server";
  if(!facts.loopback) return "the game is connected to a server outside this game";
  if(facts.max_clients!=1) return "the game has "+std::to_string(facts.max_clients)+" player slots";
  return {};
}
namespace {
// GMod x64's engine.dll, read through RTTI and each function's code (docs/RESEARCH.md for the build the RTX debug
// module's mutation gate was checked on; the same slots in the build of 2026-11-12): CreateInterface("VEngineClient015")
// returns its CEngineClient, whose vtable has GetMaxClients at 21 (a client-state field), IsConnected at 27 (the signon
// state compared with 2), GetNetChannelInfo at 72 (the client state's channel) and IsPlayingDemo at 76 (the demo
// player's). The channel is a CNetChan, IsLoopback at 6: its remote address has type NA_LOOPBACK, which only the
// connection to the server this process runs has (127.0.0.1 or a LAN server is not loopback).
constexpr char kInterface[]="VEngineClient015";
constexpr unsigned kGetMaxClients=21,kIsConnected=27,kGetNetChannelInfo=72,kIsPlayingDemo=76,kIsLoopback=6;
using Factory=void* (*)(const char*,int*);

// engine.dll's extent and executable sections, from its headers in memory.
struct Image {
  std::uintptr_t begin=0,end=0;
  std::uintptr_t code[16][2]{};
  unsigned codes=0;
  bool holds(std::uintptr_t at,std::size_t size) const { return at>=begin&&at<end&&size<=end-at; }
  bool runs(std::uintptr_t at) const {
    for(unsigned i=0;i<codes;++i) if(at>=code[i][0]&&at<code[i][1]) return true;
    return false;
  }
};
bool read_image(HMODULE module,Image& out) noexcept {
  __try {
    const auto base=reinterpret_cast<std::uintptr_t>(module);
    const auto* dos=reinterpret_cast<const IMAGE_DOS_HEADER*>(base);
    if(dos->e_magic!=IMAGE_DOS_SIGNATURE||dos->e_lfanew<=0) return false;
    const auto* nt=reinterpret_cast<const IMAGE_NT_HEADERS64*>(base+static_cast<std::uintptr_t>(dos->e_lfanew));
    if(nt->Signature!=IMAGE_NT_SIGNATURE||nt->FileHeader.Machine!=IMAGE_FILE_MACHINE_AMD64) return false;
    out.begin=base;out.end=base+nt->OptionalHeader.SizeOfImage;
    const auto* section=IMAGE_FIRST_SECTION(nt);
    for(WORD i=0;i<nt->FileHeader.NumberOfSections&&out.codes<16;++i,++section) {
      if(!(section->Characteristics&IMAGE_SCN_MEM_EXECUTE)) continue;
      out.code[out.codes][0]=base+section->VirtualAddress;
      out.code[out.codes][1]=base+section->VirtualAddress+section->Misc.VirtualSize;
      ++out.codes;
    }
  } __except(EXCEPTION_EXECUTE_HANDLER) { return false; }
  return out.codes>0;
}
// The function in slot `index` of `object`'s vtable; 0 unless the vtable lies in engine.dll and the function in its
// code. An object that is not the engine's, or a slot the build does not have, is never called.
std::uintptr_t method(const Image& image,const void* object,unsigned index) noexcept {
  __try {
    const auto table=*static_cast<const std::uintptr_t*>(object);
    if(!image.holds(table,(index+1)*sizeof(std::uintptr_t))) return 0;
    const auto function=reinterpret_cast<const std::uintptr_t*>(table)[index];
    return image.runs(function)?function:0;
  } __except(EXCEPTION_EXECUTE_HANDLER) { return 0; }
}
// The calls, each under SEH: a fault means the engine could not say.
bool create(Factory factory,void*& out) noexcept {
  __try { out=factory(kInterface,nullptr); } __except(EXCEPTION_EXECUTE_HANDLER) { return false; }
  return true;
}
template<class T> bool call(std::uintptr_t function,void* self,T& out) noexcept {
  __try { out=reinterpret_cast<T (*)(void*)>(function)(self); } __except(EXCEPTION_EXECUTE_HANDLER) { return false; }
  return true;
}
struct EngineGameCalls final:GameCalls {
  bool facts(GameFacts& out,std::string& why) override {
    out={};
    // Never loaded here: in the game engine.dll is loaded before any Lua runs.
    const HMODULE engine=GetModuleHandleW(L"engine.dll");
    if(!engine) { why="engine.dll is not loaded";return false; }
    const auto factory=reinterpret_cast<Factory>(GetProcAddress(engine,"CreateInterface"));
    Image image;
    if(!factory||!read_image(engine,image)) { why="engine.dll's CreateInterface or headers could not be read";return false; }
    void* client=nullptr;
    if(!create(factory,client)||!client) { why="engine.dll has no VEngineClient015";return false; }
    const auto connected=method(image,client,kIsConnected),slots=method(image,client,kGetMaxClients);
    const auto channel=method(image,client,kGetNetChannelInfo),demo=method(image,client,kIsPlayingDemo);
    if(!connected||!slots||!channel||!demo) { why="engine.dll's VEngineClient015 is not the one this module knows";return false; }
    bool joined=false;
    if(!call(connected,client,joined)) { why="the engine faulted in IsConnected";return false; }
    out.connected=joined;
    if(!joined) return true;
    void* net=nullptr;
    if(!call(slots,client,out.max_clients)||!call(demo,client,out.demo)||!call(channel,client,net)) {
      why="the engine faulted reading its connection";return false;
    }
    out.channel=net!=nullptr;
    if(net) {
      const auto loopback=method(image,net,kIsLoopback);
      if(!loopback||!call(loopback,net,out.loopback)) { why="the engine's net channel is not the one this module knows";return false; }
    }
    return true;
  }
};
}
GameCalls& engine_game_calls() { static EngineGameCalls calls;return calls; }
}
