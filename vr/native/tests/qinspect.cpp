// SPDX-License-Identifier: MIT
// Development-only process/thread clocks. Never packaged; no OpenVR calls or initialization.
#include <GarrysMod/Lua/Interface.h>
#include <windows.h>
#include <cstdint>
namespace {
double cpu_ms() {
  FILETIME created{}, exited{}, kernel{}, user{};
  if (!GetThreadTimes(GetCurrentThread(), &created, &exited, &kernel, &user)) return -1;
  const auto k = (uint64_t(kernel.dwHighDateTime) << 32) | kernel.dwLowDateTime;
  const auto u = (uint64_t(user.dwHighDateTime) << 32) | user.dwLowDateTime;
  return double(k + u) * .0001;
}
}
LUA_FUNCTION_STATIC(Clock) {
  ULONG64 cycles = 0;
  const bool valid = QueryThreadCycleTime(GetCurrentThread(), &cycles) != FALSE;
  LUA->PushNumber(cpu_ms());
  LUA->PushNumber(valid ? double(cycles) : -1);
  return 2;
}
LUA_FUNCTION_STATIC(Info) {
  LUA->CreateTable();
  LUA->PushNumber(GetCurrentThreadId()); LUA->SetField(-2, "thread_id");
  LUA->PushNumber(cpu_ms()); LUA->SetField(-2, "thread_cpu_ms");
  LUA->PushBool(GetModuleHandleW(L"openvr_api.dll") != nullptr); LUA->SetField(-2, "openvr_loaded");
  DWORD foreground_pid = 0;
  GetWindowThreadProcessId(GetForegroundWindow(), &foreground_pid);
  LUA->PushBool(foreground_pid == GetCurrentProcessId()); LUA->SetField(-2, "foreground");
  return 1;
}
GMOD_MODULE_OPEN() {
  LUA->CreateTable();
  LUA->PushCFunction(Clock); LUA->SetField(-2, "Clock");
  LUA->PushCFunction(Info); LUA->SetField(-2, "Info");
  LUA->Push(-1); LUA->SetField(GarrysMod::Lua::INDEX_GLOBAL, "nlvrqinspect");
  return 1;
}
GMOD_MODULE_CLOSE() { return 0; }
