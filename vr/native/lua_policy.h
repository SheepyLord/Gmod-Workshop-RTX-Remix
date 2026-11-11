// SPDX-License-Identifier: MIT
#pragma once
#include <filesystem>
#include <string_view>
#include <stdexcept>
#include <cctype>
#include <windows.h>
namespace nl::vr {
inline void reject_lua_path_key(std::string_view key) {
  if(key=="openvr_dll"||key=="manifest"||key=="runtime_dll")
    throw std::runtime_error("Lua cannot select a DLL or manifest path");
}
inline std::filesystem::path named_data(const std::filesystem::path& root,std::string_view name,bool capture) {
  if(name.empty()||name.size()>64||name.find_first_not_of("abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-")!=name.npos)
    throw std::runtime_error("expected a data name (1-64 letters, digits, _ or -), not a path");
  std::string upper(name);for(auto& c:upper) c=char(std::toupper(static_cast<unsigned char>(c)));
  if(upper=="CON"||upper=="PRN"||upper=="AUX"||upper=="NUL"||
     (upper.size()==4&&(upper.substr(0,3)=="COM"||upper.substr(0,3)=="LPT")&&std::isdigit(upper[3])))
    throw std::runtime_error("reserved Windows data name");
  auto p=(root/(capture?L"captures":L"timelines")/std::string(name)).lexically_normal();
  if(!capture) p+=L".json";
  for(auto at=p.parent_path();!at.empty()&&at!=at.parent_path();at=at.parent_path()) {
    const auto flags=GetFileAttributesW(at.c_str());
    if(flags!=INVALID_FILE_ATTRIBUTES&&(flags&FILE_ATTRIBUTE_REPARSE_POINT))
      throw std::runtime_error("VR data path contains a link");
  }
  const auto flags=GetFileAttributesW(p.c_str());
  if(flags!=INVALID_FILE_ATTRIBUTES&&(flags&FILE_ATTRIBUTE_REPARSE_POINT)) throw std::runtime_error("VR data name is a link");
  return p;
}
inline std::filesystem::path data_root(const std::filesystem::path& module_folder) {
  wchar_t value[32768]{};const auto n=GetEnvironmentVariableW(L"NLVR_TEST_ROOT",value,32768);
  if(n&&n<32768) {
    const std::filesystem::path root(value);
    if(!root.is_absolute()) throw std::runtime_error("NLVR_TEST_ROOT must be absolute");
    return root.lexically_normal();
  }
  return (module_folder/L"../../data/nlvr").lexically_normal();
}
}
