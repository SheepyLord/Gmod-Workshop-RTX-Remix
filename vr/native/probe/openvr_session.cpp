#include "openvr_session.h"
#include <chrono>
#include <iostream>
#include <sstream>
#include <thread>

namespace nl::vrprobe {
void log_event(const Json& event) { std::cerr << dump(event) << '\n'; }
VrLock::VrLock() {
  const auto path = path_utf8(NL_VR_LOCK_FILE);
  std::filesystem::create_directories(path.parent_path());
  for (;;) {
    handle_ = CreateFileW(path.c_str(), GENERIC_WRITE | DELETE, 0, nullptr, CREATE_NEW,
                         FILE_ATTRIBUTE_NORMAL | FILE_FLAG_DELETE_ON_CLOSE, nullptr);
    if (handle_ != INVALID_HANDLE_VALUE) break;
    const auto error = GetLastError();
    if (error != ERROR_FILE_EXISTS && error != ERROR_ALREADY_EXISTS && error != ERROR_SHARING_VIOLATION && error != ERROR_ACCESS_DENIED)
      throw std::runtime_error("cannot create VR lock; Win32 " + std::to_string(error));
    log_event(object({{"event", Json::make_string("waiting_for_vr_lock")}, {"path", Json::make_string(path.string())}}));
    std::this_thread::sleep_for(std::chrono::seconds(3));
  }
  SYSTEMTIME utc{}; GetSystemTime(&utc);
  std::ostringstream stamp;
  stamp << "VR-V1-A vrprobe pid=" << GetCurrentProcessId() << " UTC=" << utc.wYear << '-' << utc.wMonth
        << '-' << utc.wDay << 'T' << utc.wHour << ':' << utc.wMinute << ':' << utc.wSecond << '\n';
  const auto contents = stamp.str();
  DWORD written = 0;
  if (!WriteFile(handle_, contents.data(), static_cast<DWORD>(contents.size()), &written, nullptr) || written != contents.size()) {
    CloseHandle(handle_); handle_ = INVALID_HANDLE_VALUE;
    throw std::runtime_error("cannot write VR lock owner");
  }
}
VrLock::~VrLock() { if (handle_ != INVALID_HANDLE_VALUE) CloseHandle(handle_); }
Session::Session(const std::filesystem::path& dll) {
  const auto path = std::filesystem::absolute(dll);
  library_ = LoadLibraryExW(path.c_str(), nullptr, LOAD_LIBRARY_SEARCH_DLL_LOAD_DIR | LOAD_LIBRARY_SEARCH_SYSTEM32);
  if (!library_) throw std::runtime_error("cannot load OpenVR DLL; Win32 " + std::to_string(GetLastError()));
  init_ = reinterpret_cast<Init>(GetProcAddress(library_, "VR_InitInternal2"));
  shutdown_ = reinterpret_cast<Shutdown>(GetProcAddress(library_, "VR_ShutdownInternal"));
  interface_ = reinterpret_cast<Interface>(GetProcAddress(library_, "VR_GetGenericInterface"));
  error_name_ = reinterpret_cast<ErrorName>(GetProcAddress(library_, "VR_GetVRInitErrorAsSymbol"));
  error_description_ = reinterpret_cast<ErrorName>(GetProcAddress(library_, "VR_GetVRInitErrorAsEnglishDescription"));
  if (!init_ || !shutdown_ || !interface_ || !error_name_ || !error_description_) {
    FreeLibrary(library_); library_ = nullptr;
    throw std::runtime_error("OpenVR DLL is missing required exports");
  }
}
Session::~Session() { shutdown(); if (library_) FreeLibrary(library_); }
void Session::start() {
  vr::EVRInitError error = vr::VRInitError_None;
  init_(&error, vr::VRApplication_Scene, nullptr);
  log_event(object({{"event", Json::make_string("VR_Init")}, {"code", number(error)},
    {"symbol", Json::make_string(error_name_(error))}, {"description", Json::make_string(error_description_(error))}}));
  if (error != vr::VRInitError_None)
    throw std::runtime_error("VR_Init failed: " + std::to_string(error) + " " + error_name_(error) + ": " + error_description_(error));
  initialized_ = true;
  system = static_cast<vr::IVRSystem*>(interface_(vr::IVRSystem_Version, &error));
  if (!system || error != vr::VRInitError_None) throw std::runtime_error("IVRSystem: " + std::string(error_name_(error)));
  compositor = static_cast<vr::IVRCompositor*>(interface_(vr::IVRCompositor_Version, &error));
  if (!compositor || error != vr::VRInitError_None) throw std::runtime_error("IVRCompositor: " + std::string(error_name_(error)));
}
void Session::shutdown() {
  if (initialized_) {
    shutdown_(); initialized_ = false; system = nullptr; compositor = nullptr;
    log_event(object({{"event", Json::make_string("VR_Shutdown_client_only")}}));
  }
}
std::string Session::property(vr::TrackedDeviceIndex_t device, vr::ETrackedDeviceProperty name) const {
  vr::ETrackedPropertyError error{};
  const auto size = system->GetStringTrackedDeviceProperty(device, name, nullptr, 0, &error);
  if (!size || size > 65536) return {};
  std::vector<char> buffer(size);
  system->GetStringTrackedDeviceProperty(device, name, buffer.data(), size, &error);
  if (error != vr::TrackedProp_Success) return {};
  return std::string(buffer.data());
}
Json Session::info() const {
  uint32_t width = 0, height = 0;
  system->GetRecommendedRenderTargetSize(&width, &height);
  return object({{"model", Json::make_string(property(0, vr::Prop_ModelNumber_String))},
    {"tracking_system", Json::make_string(property(0, vr::Prop_TrackingSystemName_String))},
    {"refresh_hz", number(system->GetFloatTrackedDeviceProperty(0, vr::Prop_DisplayFrequency_Float))},
    {"ipd_m", number(system->GetFloatTrackedDeviceProperty(0, vr::Prop_UserIpdMeters_Float))},
    {"eye_width", number(width)}, {"eye_height", number(height)},
    {"system_interface", Json::make_string(vr::IVRSystem_Version)},
    {"compositor_interface", Json::make_string(vr::IVRCompositor_Version)}});
}
template<class Query> std::vector<std::string> required(Query query) {
  for (int attempt = 0; attempt != 3; ++attempt) {
    const auto size = query(nullptr, 0);
    if (!size) return {};
    if (size > 65536) throw std::runtime_error("SteamVR extension list exceeds size limit");
    std::vector<char> buffer(size);
    const auto actual = query(buffer.data(), size);
    if (actual > size) continue;
    if (!actual || buffer[actual - 1] != '\0') throw std::runtime_error("unterminated SteamVR extension list");
    return extension_list(std::string_view(buffer.data(), actual));
  }
  throw std::runtime_error("SteamVR extension list kept changing");
}
std::vector<std::string> required_instance(vr::IVRCompositor* compositor) {
  return required([&](char* b, uint32_t n) { return compositor->GetVulkanInstanceExtensionsRequired(b, n); });
}
std::vector<std::string> required_device(vr::IVRCompositor* compositor, VkPhysicalDevice_T* device) {
  return required([&](char* b, uint32_t n) { return compositor->GetVulkanDeviceExtensionsRequired(device, b, n); });
}
Json cumulative_stats(vr::IVRCompositor* compositor) {
  vr::Compositor_CumulativeStats s{};
  compositor->GetCumulativeStats(&s, sizeof(s));
  return object({{"pid", number(s.m_nPid)}, {"presents", number(s.m_nNumFramePresents)},
    {"dropped", number(s.m_nNumDroppedFrames)}, {"reprojected", number(s.m_nNumReprojectedFrames)},
    {"startup_presents", number(s.m_nNumFramePresentsOnStartup)}, {"loading", number(s.m_nNumLoading)},
    {"timed_out", number(s.m_nNumTimedOut)}, {"submits", number(s.m_nNumFrameSubmits)},
    {"sum_app_gpu_ms", number(s.m_flSumApplicationGPUTimeMS)}, {"sum_app_cpu_ms", number(s.m_flSumApplicationCPUTimeMS)},
    {"sum_compositor_gpu_ms", number(s.m_flSumCompositorGPUTimeMS)}});
}
Json device_state(Session& session, const vr::TrackedDevicePose_t* poses) {
  Json::Array devices;
  for (uint32_t i = 0; i != vr::k_unMaxTrackedDeviceCount; ++i) {
    if (!session.system->IsTrackedDeviceConnected(i)) continue;
    devices.push_back(object({{"index", number(i)}, {"class", number(session.system->GetTrackedDeviceClass(i))},
      {"model", Json::make_string(session.property(i, vr::Prop_ModelNumber_String))},
      {"activity", number(session.system->GetTrackedDeviceActivityLevel(i))},
      {"pose_valid", Json::make_bool(poses[i].bPoseIsValid)}, {"tracking_result", number(poses[i].eTrackingResult)}}));
  }
  vr::VRControllerState_t controller{};
  const bool state_known = session.system->GetControllerState(0, &controller, sizeof(controller));
  vr::ETrackedPropertyError proximity_error{}, suppressed_error{};
  const bool sensor = session.system->GetBoolTrackedDeviceProperty(0, vr::Prop_ContainsProximitySensor_Bool, &proximity_error);
  const bool suppressed = session.system->GetBoolTrackedDeviceProperty(0, vr::Prop_DisplaySuppressed_Bool, &suppressed_error);
  const bool worn = (controller.ulButtonPressed & vr::ButtonMaskFromId(vr::k_EButton_ProximitySensor)) != 0;
  return object({{"connected", Json::make_array(std::move(devices))},
    {"hmd_pose_valid", Json::make_bool(poses[0].bPoseIsValid)}, {"hmd_connected", Json::make_bool(poses[0].bDeviceIsConnected)},
    {"hmd_tracking_result", number(poses[0].eTrackingResult)},
    {"hmd_activity", number(session.system->GetTrackedDeviceActivityLevel(0))},
    {"has_proximity_sensor", proximity_error == vr::TrackedProp_Success ? Json::make_bool(sensor) : Json{}},
    {"proximity_pressed", state_known ? Json::make_bool(worn) : Json{}},
    {"display_suppressed", suppressed_error == vr::TrackedProp_Success ? Json::make_bool(suppressed) : Json{}},
    {"display_suppressed_property_error", number(suppressed_error)},
    {"display_on_desktop", Json::make_bool(session.system->IsDisplayOnDesktop())},
    {"can_render_scene", Json::make_bool(session.compositor->CanRenderScene())},
    {"scene_focus_pid", number(session.compositor->GetCurrentSceneFocusProcess())}});
}
}  // namespace nl::vrprobe
