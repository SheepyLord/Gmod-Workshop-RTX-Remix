#include "probe_data.h"
#include <algorithm>
#include <charconv>
#include <cmath>
#include <fstream>
#include <iomanip>
#include <sstream>
#include <stdexcept>

namespace nl::vrprobe {
std::filesystem::path path_utf8(std::string_view value) {
  return std::filesystem::path(std::u8string_view(reinterpret_cast<const char8_t*>(value.data()), value.size()));
}
Json object(std::initializer_list<std::pair<std::string, Json>> members) {
  return Json::make_object(Json::Object(members));
}
Json number(double value) { return Json::make_number(value, {}); }
Json strings(const std::vector<std::string>& values) {
  Json::Array result;
  for (const auto& s : values) result.push_back(Json::make_string(s));
  return Json::make_array(std::move(result));
}
std::string dump(const Json& v) {
  if (v.is_null()) return "null";
  if (v.is_bool()) return v.as_bool() ? "true" : "false";
  if (v.is_string()) return nl::json::quote(v.as_string());
  if (v.is_number()) {
    if (!std::isfinite(v.as_double())) throw std::runtime_error("non-finite JSON number");
    std::ostringstream out;
    out << std::setprecision(17) << v.as_double();
    return out.str();
  }
  std::string out = v.is_array() ? "[" : "{";
  bool first = true;
  auto append = [&](const std::string& s) { if (!first) out += ','; first = false; out += s; };
  if (v.is_array()) for (const auto& item : v.as_array()) append(dump(item));
  else for (const auto& [key, item] : v.as_object()) append(nl::json::quote(key) + ':' + dump(item));
  return out + (v.is_array() ? "]" : "}");
}
std::string read_text(const std::filesystem::path& path, std::size_t limit) {
  std::ifstream in(path, std::ios::binary);
  if (!in) throw std::runtime_error("cannot read " + path.string());
  std::string data(limit + 1, '\0');
  in.read(data.data(), static_cast<std::streamsize>(data.size()));
  data.resize(static_cast<std::size_t>(in.gcount()));
  if (data.size() > limit) throw std::runtime_error("file exceeds size limit: " + path.string());
  return data;
}
std::vector<std::string> runtime_paths(std::string_view document) {
  const auto root = nl::json::parse(document);
  if (!root.is_object()) throw std::runtime_error("OpenVR paths must be an object");
  const auto* paths = root.find("runtime");
  if (!paths || !paths->is_array()) throw std::runtime_error("OpenVR paths need a runtime array");
  std::vector<std::string> result;
  for (const auto& item : paths->as_array()) {
    const auto& path = item.as_string("runtime path");
    if (path.empty() || path.find('\0') != std::string::npos)
      throw std::runtime_error("empty or NUL-containing runtime path");
    result.push_back(path);
  }
  return result;
}
std::vector<std::string> extension_list(std::string_view list) {
  if (list.size() > 65536) throw std::runtime_error("extension list exceeds size limit");
  if (const auto end = list.find('\0'); end != std::string_view::npos) {
    for (auto c : list.substr(end)) if (c != '\0') throw std::runtime_error("data after extension terminator");
    list = list.substr(0, end);
  }
  std::istringstream in{std::string(list)};
  std::string name;
  std::vector<std::string> result;
  while (in >> name) {
    if (!name.starts_with("VK_") || name.size() >= 256 || !std::all_of(name.begin(), name.end(),
        [](unsigned char c) { return (c >= 'A' && c <= 'Z') || (c >= 'a' && c <= 'z') ||
                                     (c >= '0' && c <= '9') || c == '_'; }))
      throw std::runtime_error("invalid Vulkan extension name");
    if (std::find(result.begin(), result.end(), name) == result.end()) result.push_back(name);
  }
  return result;
}
RuntimeExtensions runtime_extensions(std::string_view log) {
  RuntimeExtensions result;
  std::istringstream in{std::string(log)};
  std::string line;
  std::string device_name;
  std::vector<std::string>* active = nullptr;
  while (std::getline(in, line)) {
    if (const auto label = line.find("Device name:"); label != std::string::npos) {
      const auto begin = line.find_first_not_of(": \t", label + 12);
      device_name = begin == std::string::npos ? "" : line.substr(begin);
      if (!device_name.empty() && device_name.back() == '\r') device_name.pop_back();
    }
    if (line.find("Enabled instance extensions:") != std::string::npos) {
      result.instance_known = true; result.instance.clear(); active = &result.instance; continue;
    }
    if (line.find("Enabled device extensions:") != std::string::npos) {
      result.device_known = true; result.device_name = device_name;
      result.device.clear(); active = &result.device; continue;
    }
    if (!active) continue;
    const auto prefix = line.find("info:");
    if (prefix == std::string::npos) { active = nullptr; continue; }
    const auto begin = line.find_first_not_of(" \t", prefix + 5);
    if (begin == std::string::npos || line.compare(begin, 3, "VK_") != 0) { active = nullptr; continue; }
    const auto names = extension_list(std::string_view(line).substr(begin));
    active->insert(active->end(), names.begin(), names.end());
  }
  return result;
}
Json compare_extensions(const std::vector<std::string>& required, const std::vector<std::string>& offered,
                        const std::vector<std::string>& enabled, bool runtime_known) {
  Json::Array result;
  for (const auto& name : required) {
    const bool supported = std::find(offered.begin(), offered.end(), name) != offered.end();
    const bool on = std::find(enabled.begin(), enabled.end(), name) != enabled.end();
    result.push_back(object({{"name", Json::make_string(name)}, {"offered", Json::make_bool(supported)},
      {"runtime_enabled", runtime_known ? Json::make_bool(on) : Json{}},
      {"needs_enable", runtime_known ? Json::make_bool(!on) : Json{}}}));
  }
  return Json::make_array(std::move(result));
}
Options arguments(const std::vector<std::string>& args) {
  Options result;
  if (args.empty()) throw std::runtime_error("expected info, extensions, submit or idle (see --help)");
  if (args.size() == 1 && args[0] == "--help") { result.help = true; return result; }
  result.command = args[0];
  if (result.command != "info" && result.command != "extensions" && result.command != "submit" && result.command != "idle")
    throw std::runtime_error("unknown command: " + result.command);
  std::vector<std::string> seen;
  for (std::size_t i = 1; i < args.size(); ++i) {
    const auto& option = args[i];
    if (std::find(seen.begin(), seen.end(), option) != seen.end()) throw std::runtime_error("duplicate " + option);
    seen.push_back(option);
    if (option == "--pose" && result.command == "submit") { result.pose = true; continue; }
    if (option == "--submit" && result.command == "idle") { result.submit = true; continue; }
    const bool duration = (option == "--seconds" && result.command == "submit") ||
                          (option == "--minutes" && result.command == "idle");
    if (option != "--dll" && option != "--out" && !(option == "--runtime-log" && result.command == "extensions") && !duration)
      throw std::runtime_error("unexpected option: " + option);
    if (++i == args.size() || args[i].empty() || args[i].starts_with("--")) throw std::runtime_error("missing value for " + option);
    if (option == "--dll") result.dll = path_utf8(args[i]);
    else if (option == "--out") result.out = path_utf8(args[i]);
    else if (option == "--runtime-log") result.runtime_log = path_utf8(args[i]);
    else {
      double n = 0;
      const auto parsed = std::from_chars(args[i].data(), args[i].data() + args[i].size(), n);
      if (parsed.ec != std::errc{} || parsed.ptr != args[i].data() + args[i].size() || !std::isfinite(n) || n <= 0)
        throw std::runtime_error("duration must be a finite positive number");
      result.seconds = option == "--minutes" ? n * 60 : n;
      if (result.seconds > 86400) throw std::runtime_error("duration exceeds one day");
    }
  }
  if (result.command != "info" && result.dll.empty()) throw std::runtime_error("--dll must name a verified OpenVR DLL");
  if ((result.command == "idle" || result.command == "submit") && result.seconds == 0)
    throw std::runtime_error("a duration is required");
  return result;
}
void Moments::add(double value) {
  if (!count) minimum = maximum = value;
  minimum = std::min(minimum, value); maximum = std::max(maximum, value); sum += value; ++count;
}
Json Moments::json() const {
  return object({{"count", number(static_cast<double>(count))}, {"min", number(minimum)},
    {"mean", number(count ? sum / static_cast<double>(count) : 0)}, {"max", number(maximum)}});
}
}  // namespace nl::vrprobe
