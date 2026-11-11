#pragma once
#include <nl/json.h>
#include <filesystem>
#include <initializer_list>
#include <string>
#include <string_view>
#include <vector>

namespace nl::vrprobe {
using Json = nl::json::Value;
Json object(std::initializer_list<std::pair<std::string, Json>> members);
Json number(double value);
Json strings(const std::vector<std::string>& values);
std::string dump(const Json& value);
std::filesystem::path path_utf8(std::string_view value);
std::string read_text(const std::filesystem::path& path, std::size_t limit = 8 * 1024 * 1024);
std::vector<std::string> runtime_paths(std::string_view document);
std::vector<std::string> extension_list(std::string_view list);
struct RuntimeExtensions {
  bool instance_known = false, device_known = false;
  std::string device_name;
  std::vector<std::string> instance, device;
};
RuntimeExtensions runtime_extensions(std::string_view log);
Json compare_extensions(const std::vector<std::string>& required,
                        const std::vector<std::string>& offered,
                        const std::vector<std::string>& enabled, bool runtime_known);
struct Options {
  std::string command;
  std::filesystem::path dll, out, runtime_log;
  double seconds = 0;
  bool pose = false, submit = false, help = false;
};
Options arguments(const std::vector<std::string>& args);
struct Moments {
  std::uint64_t count = 0;
  double sum = 0, minimum = 0, maximum = 0;
  void add(double value);
  Json json() const;
};
}  // namespace nl::vrprobe
