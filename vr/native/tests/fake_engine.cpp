// SPDX-License-Identifier: MIT
// A stand-in engine.dll for the VR module's single-player gate (review finding 8), never the game's. Its
// CreateInterface("VEngineClient015") returns an object whose vtable has GMod x64's slots, written here on their own
// so that the module's slot numbers are checked against them: GetMaxClients 21, IsConnected 27, GetNetChannelInfo 72,
// IsPlayingDemo 76; the channel it returns has IsLoopback at 6. The test says what they answer, counts the calls and
// can give the objects another shape.
#include <windows.h>
#include <cstring>

namespace {
struct Facts { int connected=1,channel=1,loopback=1,demo=0,max_clients=1; } g_facts;
volatile long g_calls=0;
int g_data[4]{};  // data inside this image, never code
void* g_client_table[80];
void* g_channel_table[10];
void** g_foreign=nullptr;  // a vtable outside this image
struct Object { void* const* table; };
Object g_client{g_client_table},g_channel{g_channel_table};
bool g_known=true;

int other(void*) { InterlockedIncrement(&g_calls);return 0; }
bool is_connected(void*) { InterlockedIncrement(&g_calls);return g_facts.connected!=0; }
int max_clients(void*) { InterlockedIncrement(&g_calls);return g_facts.max_clients; }
void* channel_info(void*) { InterlockedIncrement(&g_calls);return g_facts.channel?&g_channel:nullptr; }
bool playing_demo(void*) { InterlockedIncrement(&g_calls);return g_facts.demo!=0; }
bool is_loopback(void*) { InterlockedIncrement(&g_calls);return g_facts.loopback!=0; }

// 0 the game's shape; 1 IsConnected's slot holds data; 2 the channel's vtable is not this image's; 3 no
// VEngineClient015; 4 the client's vtable is not this image's.
void shape(int kind) {
  for(auto& slot:g_client_table) slot=reinterpret_cast<void*>(&other);
  for(auto& slot:g_channel_table) slot=reinterpret_cast<void*>(&other);
  g_client_table[21]=reinterpret_cast<void*>(&max_clients);
  g_client_table[27]=reinterpret_cast<void*>(&is_connected);
  g_client_table[72]=reinterpret_cast<void*>(&channel_info);
  g_client_table[76]=reinterpret_cast<void*>(&playing_demo);
  g_channel_table[6]=reinterpret_cast<void*>(&is_loopback);
  g_client.table=g_client_table;g_channel.table=g_channel_table;g_known=true;
  if(kind==1) g_client_table[27]=g_data;
  if(kind==2||kind==4) {
    if(!g_foreign) g_foreign=static_cast<void**>(VirtualAlloc(nullptr,sizeof(g_client_table),MEM_COMMIT|MEM_RESERVE,PAGE_READWRITE));
    if(g_foreign) {
      // The same functions, in a table that is not engine.dll's: the module must not trust it.
      std::memcpy(g_foreign,kind==2?g_channel_table:g_client_table,kind==2?sizeof(g_channel_table):sizeof(g_client_table));
      (kind==2?g_channel:g_client).table=g_foreign;
    }
  }
  if(kind==3) g_known=false;
}
}

extern "C" __declspec(dllexport) void* CreateInterface(const char* name,int* code) {
  const bool found=g_known&&name&&std::strcmp(name,"VEngineClient015")==0;
  if(code) *code=found?0:1;
  return found?&g_client:nullptr;
}
extern "C" __declspec(dllexport) void nlvr_fake_engine_facts(int connected,int channel,int loopback,int demo,int max_clients) {
  g_facts={connected,channel,loopback,demo,max_clients};
}
extern "C" __declspec(dllexport) void nlvr_fake_engine_shape(int kind) { shape(kind); }
extern "C" __declspec(dllexport) long nlvr_fake_engine_calls() { return g_calls; }

BOOL APIENTRY DllMain(HMODULE,DWORD reason,LPVOID) {
  if(reason==DLL_PROCESS_ATTACH) shape(0);
  if(reason==DLL_PROCESS_DETACH&&g_foreign) VirtualFree(g_foreign,0,MEM_RELEASE);
  return TRUE;
}
