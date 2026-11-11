// MIT. Deliberately separate from nlvr: a disposable, build-specific S4 experiment.
#include <GarrysMod/Lua/Interface.h>
#include <windows.h>
#include <array>
#include <atomic>
#include <cstdint>
#include <cstring>

namespace {
using GarrysMod::Lua::ILuaBase;
using Fn = void(*)();
void* material{};
std::uintptr_t image{};
using GetContext = void*(*)(void*);
GetContext get_context{};
struct Record {
  unsigned id{}, stage{}, main_thread{};
  std::atomic<unsigned> called{}, render_thread{}, width{}, height{}, released{}, execution{};
};
struct Functor {
  Fn* vtable{};
  Record* record{};
  int refs{1};
};
std::array<Record, 1024> records;
std::array<Functor, 1024> functors;
unsigned used{};
std::atomic<unsigned> execution_counter{};
bool ready{};
template<class T> T slot(void* object, unsigned index) {
  return reinterpret_cast<T>((*static_cast<void***>(object))[index]);
}
std::uintptr_t rva(void* address) { return reinterpret_cast<std::uintptr_t>(address)-image; }
bool has_queue_vtable(void* queue) {
  const auto first=*static_cast<void**>(queue);
  const auto offset=rva(first);
  if(offset<0xb0000 || offset>=0xe4000)return false;
  const auto function=rva(*static_cast<void**>(first));
  return function>=0x1000 && function<0xaf000;
}
int add_ref(Functor* f) { return ++f->refs; }
int release(Functor* f) { f->record->released.fetch_add(1); return --f->refs; }
void invoke(Functor* f) {
  auto& r = *f->record;
  r.execution=execution_counter.fetch_add(1)+1;
  r.render_thread = GetCurrentThreadId();
  int w{}, h{};
  void* context = get_context(material);
  if (context) slot<void(*)(void*, int&, int&)>(context, 8)(context,w,h);
  r.width = static_cast<unsigned>(w); r.height = static_cast<unsigned>(h);
  r.called.fetch_add(1, std::memory_order_release);
}
Fn callbacks[]{reinterpret_cast<Fn>(add_ref),reinterpret_cast<Fn>(release),
  reinterpret_cast<Fn>(invoke),reinterpret_cast<Fn>(invoke)};
void num(ILuaBase* lua, const char* key, double value) {
  lua->PushNumber(value); lua->SetField(-2,key);
}
LUA_FUNCTION_STATIC(Layout) {
  LUA->CreateTable();
  num(LUA,"main_thread",GetCurrentThreadId());
  num(LUA,"materialsystem_base",static_cast<double>(image));
  num(LUA,"get_context_slot",102);
  num(LUA,"get_queue_slot",145);
  num(LUA,"get_context_rva",static_cast<double>(material?rva(reinterpret_cast<void*>(get_context)):0));
  LUA->PushBool(ready); LUA->SetField(-2,"ready");
  if (ready) {
    auto* ctx=get_context(material);
    num(LUA,"context_vtable_rva",static_cast<double>(rva(*static_cast<void**>(ctx))));
    const auto get_queue=slot<void*(*)(void*)>(ctx,145);
    num(LUA,"get_queue_rva",static_cast<double>(rva(reinterpret_cast<void*>(get_queue))));
    auto* queue=get_queue(ctx);
    num(LUA,"queue",static_cast<double>(reinterpret_cast<std::uintptr_t>(queue)));
    if(queue) {
      const auto first=*static_cast<void**>(queue);
      num(LUA,"queue_offset",static_cast<double>(reinterpret_cast<std::uintptr_t>(queue)-reinterpret_cast<std::uintptr_t>(ctx)));
      num(LUA,"queue_first_word",static_cast<double>(reinterpret_cast<std::uintptr_t>(first)));
      if(has_queue_vtable(queue))num(LUA,"queue_function_rva",static_cast<double>(rva((*static_cast<void***>(queue))[0])));
      LUA->PushBool(has_queue_vtable(queue));LUA->SetField(-2,"queue_has_module_vtable");
    }
  }
  return 1;
}
LUA_FUNCTION_STATIC(Queue) {
  LUA->PushBool(false);
  if(!ready || used>=records.size())return 1;
  const auto id=static_cast<unsigned>(LUA->GetNumber(1));
  const auto stage=static_cast<unsigned>(LUA->GetNumber(2));
  auto* ctx=get_context(material);
  // Only the analysed queued implementation is allowed to accept our functor ABI.
  const auto get_queue=slot<void*(*)(void*)>(ctx,145);
  if(rva(reinterpret_cast<void*>(get_queue))!=0x1d6b0)return 1;
  auto* queue=get_queue(ctx);
  if(!queue)return 1;
  if(!has_queue_vtable(queue))return 1;
  auto& rec=records[used];auto& functor=functors[used++];
  rec.id=id;rec.stage=stage;rec.main_thread=GetCurrentThreadId();
  functor.vtable=callbacks;functor.record=&rec;
  slot<void(*)(void*,Functor*)>(queue,0)(queue,&functor);
  LUA->Pop(); LUA->PushBool(true);return 1;
}
LUA_FUNCTION_STATIC(Records) {
  LUA->CreateTable();
  for(unsigned i=0;i<used;++i) {
    const auto& r=records[i];LUA->PushNumber(i+1);LUA->CreateTable();
    num(LUA,"id",r.id);num(LUA,"stage",r.stage);num(LUA,"main_thread",r.main_thread);
    num(LUA,"called",r.called.load(std::memory_order_acquire));
    num(LUA,"render_thread",r.render_thread.load());num(LUA,"width",r.width.load());
    num(LUA,"height",r.height.load());num(LUA,"released",r.released.load());
    num(LUA,"execution",r.execution.load());
    LUA->RawSet(-3);
  }
  return 1;
}
}
GMOD_MODULE_OPEN() {
  const auto mod=GetModuleHandleW(L"materialsystem.dll");
  image=reinterpret_cast<std::uintptr_t>(mod);
  if(mod) {
    const auto factory=reinterpret_cast<void*(*)(const char*,int*)>(GetProcAddress(mod,"CreateInterface"));
    material=factory?factory("VMaterialSystem080",nullptr):nullptr;
    if(material) {
      get_context=slot<GetContext>(material,102);
      const unsigned char expected[]{0x40,0x53,0x48,0x83,0xec,0x20,0x48,0x8b,0xd9};
      ready=rva(reinterpret_cast<void*>(get_context))==0x1dd40 &&
        std::memcmp(reinterpret_cast<void*>(get_context),expected,sizeof(expected))==0;
    }
  }
  LUA->CreateTable();
  LUA->PushCFunction(Layout);LUA->SetField(-2,"Layout");
  LUA->PushCFunction(Queue);LUA->SetField(-2,"Queue");
  LUA->PushCFunction(Records);LUA->SetField(-2,"Records");
  LUA->SetField(GarrysMod::Lua::INDEX_GLOBAL,"nlvrs4");
  return 0;
}
GMOD_MODULE_CLOSE() { return 0; }
