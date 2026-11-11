#include "probe_data.h"
#include <iostream>
#include <stdexcept>

using namespace nl::vrprobe;
namespace {
int checks = 0;
void expect(bool condition) { ++checks; if (!condition) throw std::runtime_error("check " + std::to_string(checks)); }
template<class F> void rejects(F f) {
  bool rejected = false;
  try { f(); } catch (const std::exception&) { rejected = true; }
  expect(rejected);
}
}
int main() {
  try {
    const auto paths = runtime_paths(R"({"runtime":["C:\\Steam\\SteamVR", "D:/SteamVR"],"external_drivers":null})");
    expect(paths.size() == 2 && paths[0] == "C:\\Steam\\SteamVR");
    expect(runtime_paths(R"({"runtime":[]})").empty());
    for (const auto* bad : {"null", "[]", "{}", R"({"runtime":"C:/vr"})", R"({"runtime":[1]})",
         R"({"runtime":[""]})", R"({"runtime":["x\u0000y"]})", R"({"runtime":[],"runtime":[]})", "{bad"})
      rejects([&] { runtime_paths(bad); });
    expect(extension_list("\tVK_KHR_surface  VK_KHR_win32_surface\r\nVK_KHR_surface ").size() == 2);
    expect(extension_list("").empty());
    expect(extension_list(std::string_view("VK_EXT_test\0", 12)).size() == 1);
    for (const auto& bad : {std::string("no_prefix"), std::string("VK_bad-name"), std::string("VK_x\0tail", 9), std::string(65537, 'a')})
      rejects([&] { extension_list(bad); });
    const auto runtime = runtime_extensions(
      "info:  Vulkan instance extensions:\ninfo:    VK_wrong_available\n"
      "info:  Enabled instance extensions:\ninfo:    VK_KHR_surface\ninfo: Layer Names:\n"
      "info:  Enabled instance extensions:\ninfo:    VK_EXT_test\nwarn: other\n"
      "info:    Device name:     : GPU Test\n"
      "info:  Enabled device extensions:\ninfo:    VK_KHR_swapchain\ninfo: Device Features:\n");
    expect(runtime.instance_known && runtime.device_known);
    expect(runtime.instance == std::vector<std::string>{"VK_EXT_test"});
    expect(runtime.device == std::vector<std::string>{"VK_KHR_swapchain"});
    expect(runtime.device_name == "GPU Test");
    expect(!runtime_extensions("info: Vulkan device extensions:\ninfo: VK_KHR_surface\n").device_known);
    const auto comparison = compare_extensions({"VK_A", "VK_B", "VK_C"}, {"VK_A", "VK_B"}, {"VK_A"}, true).as_array();
    expect(comparison[0].find("runtime_enabled")->as_bool());
    expect(comparison[1].find("needs_enable")->as_bool() && comparison[1].find("offered")->as_bool());
    expect(!comparison[2].find("offered")->as_bool());
    expect(compare_extensions({"VK_A"}, {}, {}, false).as_array()[0].find("runtime_enabled")->is_null());
    expect(arguments({"info"}).dll.empty());
    expect(arguments({"--help"}).help);
    expect(arguments({"extensions", "--dll", "a.dll", "--runtime-log", "a.log"}).runtime_log == "a.log");
    expect(arguments({"submit", "--dll", "a.dll", "--seconds", "2.5", "--pose"}).pose);
    const auto idle = arguments({"idle", "--minutes", "10", "--dll", "a.dll", "--submit", "--out", "x.json"});
    expect(idle.submit && idle.seconds == 600 && idle.out == "x.json");
    for (const auto& bad : std::vector<std::vector<std::string>>{{}, {"bad"}, {"extensions"}, {"idle", "--dll", "x"},
         {"info", "--out"}, {"info", "--pose"}, {"info", "--out", "x", "--out", "y"},
         {"submit", "--dll", "x", "--seconds", "nan"}, {"submit", "--dll", "x", "--seconds", "2foo"},
         {"submit", "--dll", "x", "--seconds", "0"}, {"submit", "--dll", "x", "--seconds", "-2"},
         {"idle", "--dll", "x", "--minutes", "999999"}, {"submit", "--dll", "--seconds", "1"}})
      rejects([&] { arguments(bad); });
    Moments m; m.add(10); m.add(20); m.add(30);
    expect(m.json().find("mean")->as_double() == 20);
    expect(m.json().find("min")->as_double() == 10);
    expect(m.json().find("max")->as_double() == 30);
    expect(nl::json::parse(dump(object({{"escaped", Json::make_string("quotes\"\n\\")}, {"moments", m.json()},
      {"array", strings({"one", "two"})}}))).find("escaped")->as_string() == "quotes\"\n\\");
    std::cout << checks << " offline checks passed\n";
    return 0;
  } catch (const std::exception& e) { std::cerr << e.what() << '\n'; return 1; }
}
