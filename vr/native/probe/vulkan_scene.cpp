#include "vulkan_scene.h"
#if NL_VR_HAS_VULKAN
#include <vulkan/vulkan.h>
#include <algorithm>
#include <array>
#include <cmath>
#include <cstring>
#include <limits>

namespace nl::vrprobe {
namespace {
void check(VkResult result, const char* operation) {
  if (result != VK_SUCCESS) throw std::runtime_error(std::string(operation) + ": VkResult " + std::to_string(result));
}
template<class T, class F> std::vector<T> enumerate(F f) {
  for (int attempt = 0; attempt != 8; ++attempt) {
    uint32_t count = 0; check(f(&count, static_cast<T*>(nullptr)), "Vulkan enumerate count");
    std::vector<T> items(count);
    const auto result = f(&count, items.data());
    if (result == VK_INCOMPLETE) continue;
    check(result, "Vulkan enumerate"); items.resize(count); return items;
  }
  throw std::runtime_error("Vulkan enumeration kept changing");
}
std::vector<std::string> names(const std::vector<VkExtensionProperties>& properties) {
  std::vector<std::string> result;
  for (const auto& property : properties) result.emplace_back(property.extensionName);
  return result;
}
std::vector<const char*> pointers(const std::vector<std::string>& values) {
  std::vector<const char*> result;
  for (const auto& value : values) result.push_back(value.c_str());
  return result;
}
void require_all(const std::vector<std::string>& required, const std::vector<std::string>& offered) {
  for (const auto& name : required) if (std::find(offered.begin(), offered.end(), name) == offered.end())
    throw std::runtime_error("SteamVR requires unsupported extension: " + name);
}
}  // namespace
struct VulkanScene::Impl {
  Session& session;
  HMODULE library = nullptr;
  VkInstance instance = VK_NULL_HANDLE;
  VkPhysicalDevice physical = VK_NULL_HANDLE;
  VkDevice device = VK_NULL_HANDLE;
  VkQueue queue = VK_NULL_HANDLE;
  uint32_t family = 0, width = 0, height = 0;
  VkCommandPool pool = VK_NULL_HANDLE;
  VkCommandBuffer command = VK_NULL_HANDLE;
  VkFence fence = VK_NULL_HANDLE;
  std::array<VkImage, 2> images{};
  std::array<VkDeviceMemory, 2> memory{};
  bool first = true;
  std::vector<std::string> instance_required, instance_offered;
  std::vector<VkPhysicalDevice> devices;
  PFN_vkGetInstanceProcAddr get_instance = nullptr;
  PFN_vkGetDeviceProcAddr get_device = nullptr;
#define VR_INSTANCE_FUNCTIONS(X) \
  X(DestroyInstance) X(EnumeratePhysicalDevices) X(GetPhysicalDeviceProperties) \
  X(EnumerateDeviceExtensionProperties) X(GetPhysicalDeviceQueueFamilyProperties) \
  X(GetPhysicalDeviceMemoryProperties) X(GetPhysicalDeviceFeatures2) X(CreateDevice)
#define VR_DEVICE_FUNCTIONS(X) \
  X(DestroyDevice) X(GetDeviceQueue) X(CreateImage) X(GetImageMemoryRequirements) \
  X(AllocateMemory) X(BindImageMemory) X(CreateCommandPool) X(AllocateCommandBuffers) \
  X(CreateFence) X(WaitForFences) X(ResetFences) X(ResetCommandBuffer) \
  X(BeginCommandBuffer) X(CmdPipelineBarrier) X(CmdClearColorImage) X(EndCommandBuffer) \
  X(QueueSubmit) X(DeviceWaitIdle) X(DestroyFence) X(DestroyCommandPool) X(DestroyImage) X(FreeMemory)
#define VR_DECLARE(name) PFN_vk##name name = nullptr;
  VR_INSTANCE_FUNCTIONS(VR_DECLARE)
  VR_DEVICE_FUNCTIONS(VR_DECLARE)
#undef VR_DECLARE
  explicit Impl(Session& s) : session(s) {}
  ~Impl() {
    // OpenVR retains the application's handles until its client shuts down.
    session.shutdown();
    if (device && DeviceWaitIdle) DeviceWaitIdle(device);
    if (fence && DestroyFence) DestroyFence(device, fence, nullptr);
    if (pool && DestroyCommandPool) DestroyCommandPool(device, pool, nullptr);
    for (std::size_t i = 0; i != 2; ++i) {
      if (images[i] && DestroyImage) DestroyImage(device, images[i], nullptr);
      if (memory[i] && FreeMemory) FreeMemory(device, memory[i], nullptr);
    }
    if (device && DestroyDevice) DestroyDevice(device, nullptr);
    if (instance && DestroyInstance) DestroyInstance(instance, nullptr);
    if (library) FreeLibrary(library);
  }
  template<class T> T function(const char* name) {
    const auto fn = device && get_device ? get_device(device, name) : get_instance(instance, name);
    if (!fn) throw std::runtime_error(std::string("Vulkan function missing: ") + name);
    return reinterpret_cast<T>(fn);
  }
  void init() {
    library = LoadLibraryExW(L"vulkan-1.dll", nullptr, LOAD_LIBRARY_SEARCH_SYSTEM32);
    if (!library) throw std::runtime_error("system Vulkan loader unavailable");
    get_instance = reinterpret_cast<PFN_vkGetInstanceProcAddr>(GetProcAddress(library, "vkGetInstanceProcAddr"));
    if (!get_instance) throw std::runtime_error("vkGetInstanceProcAddr missing");
    const auto enum_instance = function<PFN_vkEnumerateInstanceExtensionProperties>("vkEnumerateInstanceExtensionProperties");
    instance_offered = names(enumerate<VkExtensionProperties>([&](auto* n, auto* p) { return enum_instance(nullptr, n, p); }));
    instance_required = required_instance(session.compositor);
    require_all(instance_required, instance_offered);
    const auto enabled = pointers(instance_required);
    VkApplicationInfo app{}; app.sType = VK_STRUCTURE_TYPE_APPLICATION_INFO;
    app.pApplicationName = "Native Loader VR probe"; app.apiVersion = VK_API_VERSION_1_1;
    VkInstanceCreateInfo create{}; create.sType = VK_STRUCTURE_TYPE_INSTANCE_CREATE_INFO;
    create.pApplicationInfo = &app;
    create.enabledExtensionCount = static_cast<uint32_t>(enabled.size()); create.ppEnabledExtensionNames = enabled.data();
    check(function<PFN_vkCreateInstance>("vkCreateInstance")(&create, nullptr, &instance), "vkCreateInstance");
#define VR_LOAD_INSTANCE(name) name = function<PFN_vk##name>("vk" #name);
    VR_INSTANCE_FUNCTIONS(VR_LOAD_INSTANCE)
#undef VR_LOAD_INSTANCE
    get_device = function<PFN_vkGetDeviceProcAddr>("vkGetDeviceProcAddr");
    devices = enumerate<VkPhysicalDevice>([&](auto* n, auto* p) { return EnumeratePhysicalDevices(instance, n, p); });
    uint64_t output = 0;
    session.system->GetOutputDevice(&output, vr::TextureType_Vulkan, instance);
    physical = reinterpret_cast<VkPhysicalDevice>(static_cast<uintptr_t>(output));
  }
  std::vector<std::string> offered(VkPhysicalDevice gpu) {
    return names(enumerate<VkExtensionProperties>([&](auto* n, auto* p) { return EnumerateDeviceExtensionProperties(gpu, nullptr, n, p); }));
  }
  void prepare() {
    if (std::find(devices.begin(), devices.end(), physical) == devices.end())
      throw std::runtime_error("SteamVR did not identify an enumerated Vulkan output device");
    const auto required = required_device(session.compositor, physical);
    require_all(required, offered(physical)); // Validate; never silently filter SteamVR's list.
    const auto extensions = pointers(required);
    uint32_t family_count = 0;
    GetPhysicalDeviceQueueFamilyProperties(physical, &family_count, nullptr);
    std::vector<VkQueueFamilyProperties> families(family_count);
    GetPhysicalDeviceQueueFamilyProperties(physical, &family_count, families.data());
    family = family_count;
    for (uint32_t i = 0; i != family_count; ++i)
      if (families[i].queueCount && (families[i].queueFlags & VK_QUEUE_GRAPHICS_BIT)) { family = i; break; }
    if (family == family_count) throw std::runtime_error("Vulkan output device has no graphics queue");
    const float priority = 1;
    VkDeviceQueueCreateInfo qc{}; qc.sType = VK_STRUCTURE_TYPE_DEVICE_QUEUE_CREATE_INFO;
    qc.queueFamilyIndex = family; qc.queueCount = 1; qc.pQueuePriorities = &priority;
    VkDeviceCreateInfo dc{}; dc.sType = VK_STRUCTURE_TYPE_DEVICE_CREATE_INFO;
    dc.queueCreateInfoCount = 1; dc.pQueueCreateInfos = &qc;
    dc.enabledExtensionCount = static_cast<uint32_t>(extensions.size()); dc.ppEnabledExtensionNames = extensions.data();
    VkPhysicalDeviceTimelineSemaphoreFeatures timeline{};
    timeline.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_TIMELINE_SEMAPHORE_FEATURES;
    if (std::find(required.begin(), required.end(), VK_KHR_TIMELINE_SEMAPHORE_EXTENSION_NAME) != required.end()) {
      VkPhysicalDeviceFeatures2 features{}; features.sType = VK_STRUCTURE_TYPE_PHYSICAL_DEVICE_FEATURES_2;
      features.pNext = &timeline; GetPhysicalDeviceFeatures2(physical, &features);
      if (!timeline.timelineSemaphore) throw std::runtime_error("SteamVR's timelineSemaphore feature is unavailable");
      dc.pNext = &timeline;
    }
    check(CreateDevice(physical, &dc, nullptr, &device), "vkCreateDevice");
#define VR_LOAD_DEVICE(name) name = function<PFN_vk##name>("vk" #name);
    VR_DEVICE_FUNCTIONS(VR_LOAD_DEVICE)
#undef VR_LOAD_DEVICE
    GetDeviceQueue(device, family, 0, &queue);
    session.system->GetRecommendedRenderTargetSize(&width, &height);
    if (!width || !height || width > 16384 || height > 16384) throw std::runtime_error("unreasonable eye dimensions");
    VkPhysicalDeviceMemoryProperties mp{}; GetPhysicalDeviceMemoryProperties(physical, &mp);
    for (std::size_t eye = 0; eye != 2; ++eye) {
      VkImageCreateInfo ic{}; ic.sType = VK_STRUCTURE_TYPE_IMAGE_CREATE_INFO;
      ic.imageType = VK_IMAGE_TYPE_2D; ic.format = VK_FORMAT_R8G8B8A8_UNORM;
      ic.extent = {width, height, 1}; ic.mipLevels = 1; ic.arrayLayers = 1;
      ic.samples = VK_SAMPLE_COUNT_1_BIT; ic.tiling = VK_IMAGE_TILING_OPTIMAL;
      ic.usage = VK_IMAGE_USAGE_TRANSFER_SRC_BIT | VK_IMAGE_USAGE_TRANSFER_DST_BIT | VK_IMAGE_USAGE_SAMPLED_BIT;
      ic.sharingMode = VK_SHARING_MODE_EXCLUSIVE; ic.initialLayout = VK_IMAGE_LAYOUT_UNDEFINED;
      check(CreateImage(device, &ic, nullptr, &images[eye]), "vkCreateImage");
      VkMemoryRequirements mr{}; GetImageMemoryRequirements(device, images[eye], &mr);
      uint32_t type = mp.memoryTypeCount;
      for (uint32_t i = 0; i != mp.memoryTypeCount; ++i)
        if ((mr.memoryTypeBits & (1u << i)) && (mp.memoryTypes[i].propertyFlags & VK_MEMORY_PROPERTY_DEVICE_LOCAL_BIT)) { type = i; break; }
      if (type == mp.memoryTypeCount) throw std::runtime_error("no device-local eye memory type");
      VkMemoryAllocateInfo ma{}; ma.sType = VK_STRUCTURE_TYPE_MEMORY_ALLOCATE_INFO;
      ma.allocationSize = mr.size; ma.memoryTypeIndex = type;
      check(AllocateMemory(device, &ma, nullptr, &memory[eye]), "vkAllocateMemory");
      check(BindImageMemory(device, images[eye], memory[eye], 0), "vkBindImageMemory");
    }
    VkCommandPoolCreateInfo pc{}; pc.sType = VK_STRUCTURE_TYPE_COMMAND_POOL_CREATE_INFO;
    pc.flags = VK_COMMAND_POOL_CREATE_RESET_COMMAND_BUFFER_BIT; pc.queueFamilyIndex = family;
    check(CreateCommandPool(device, &pc, nullptr, &pool), "vkCreateCommandPool");
    VkCommandBufferAllocateInfo ca{}; ca.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_ALLOCATE_INFO;
    ca.commandPool = pool; ca.level = VK_COMMAND_BUFFER_LEVEL_PRIMARY; ca.commandBufferCount = 1;
    check(AllocateCommandBuffers(device, &ca, &command), "vkAllocateCommandBuffers");
    VkFenceCreateInfo fc{}; fc.sType = VK_STRUCTURE_TYPE_FENCE_CREATE_INFO; fc.flags = VK_FENCE_CREATE_SIGNALED_BIT;
    check(CreateFence(device, &fc, nullptr, &fence), "vkCreateFence");
    session.compositor->SetExplicitTimingMode(vr::VRCompositorTimingMode_Explicit_ApplicationPerformsPostPresentHandoff);
    log_event(object({{"event", Json::make_string("vulkan_scene_ready")}, {"queue_family", number(family)},
      {"width", number(width)}, {"height", number(height)}, {"device_extensions", strings(required)}}));
  }
  void frame(std::uint64_t index, const vr::TrackedDevicePose_t& pose, bool with_pose,
             std::uint64_t& accepted, std::uint64_t& errors, Json::Array& error_log) {
    check(WaitForFences(device, 1, &fence, VK_TRUE, 5000000000ull), "vkWaitForFences (5s)");
    check(ResetFences(device, 1, &fence), "vkResetFences");
    check(ResetCommandBuffer(command, 0), "vkResetCommandBuffer");
    VkCommandBufferBeginInfo begin{}; begin.sType = VK_STRUCTURE_TYPE_COMMAND_BUFFER_BEGIN_INFO;
    begin.flags = VK_COMMAND_BUFFER_USAGE_ONE_TIME_SUBMIT_BIT;
    check(BeginCommandBuffer(command, &begin), "vkBeginCommandBuffer");
    const VkImageSubresourceRange range{VK_IMAGE_ASPECT_COLOR_BIT, 0, 1, 0, 1};
    const float phase = static_cast<float>(index % 240) / 239.0f;
    for (std::size_t eye = 0; eye != 2; ++eye) {
      VkImageMemoryBarrier barrier{}; barrier.sType = VK_STRUCTURE_TYPE_IMAGE_MEMORY_BARRIER;
      barrier.srcAccessMask = first ? 0 : VK_ACCESS_TRANSFER_READ_BIT;
      barrier.dstAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT;
      barrier.oldLayout = first ? VK_IMAGE_LAYOUT_UNDEFINED : VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL;
      barrier.newLayout = VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL;
      barrier.srcQueueFamilyIndex = barrier.dstQueueFamilyIndex = VK_QUEUE_FAMILY_IGNORED;
      barrier.image = images[eye]; barrier.subresourceRange = range;
      CmdPipelineBarrier(command, first ? VK_PIPELINE_STAGE_TOP_OF_PIPE_BIT : VK_PIPELINE_STAGE_TRANSFER_BIT,
        VK_PIPELINE_STAGE_TRANSFER_BIT, 0, 0, nullptr, 0, nullptr, 1, &barrier);
      VkClearColorValue color{};
      color.float32[0] = eye == 0 ? phase : 1 - phase; color.float32[1] = 0.15f;
      color.float32[2] = 1 - phase; color.float32[3] = 1;
      CmdClearColorImage(command, images[eye], VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL, &color, 1, &range);
      barrier.srcAccessMask = VK_ACCESS_TRANSFER_WRITE_BIT; barrier.dstAccessMask = VK_ACCESS_TRANSFER_READ_BIT;
      barrier.oldLayout = VK_IMAGE_LAYOUT_TRANSFER_DST_OPTIMAL; barrier.newLayout = VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL;
      CmdPipelineBarrier(command, VK_PIPELINE_STAGE_TRANSFER_BIT, VK_PIPELINE_STAGE_TRANSFER_BIT,
        0, 0, nullptr, 0, nullptr, 1, &barrier);
    }
    check(EndCommandBuffer(command), "vkEndCommandBuffer");
    auto report = [&](vr::EVRCompositorError error, const char* operation, int eye) {
      if (error == vr::VRCompositorError_None) return;
      ++errors;
      auto item = object({{"event", Json::make_string("compositor_error")}, {"operation", Json::make_string(operation)},
        {"frame", number(static_cast<double>(index))}, {"eye", number(eye)}, {"code", number(error)}});
      log_event(item); error_log.push_back(std::move(item));
    };
    // All queue operations, timing, both Submits and handoff are on this one thread.
    report(session.compositor->SubmitExplicitTimingData(), "SubmitExplicitTimingData", -1);
    VkSubmitInfo submit{}; submit.sType = VK_STRUCTURE_TYPE_SUBMIT_INFO;
    submit.commandBufferCount = 1; submit.pCommandBuffers = &command;
    check(QueueSubmit(queue, 1, &submit, fence), "vkQueueSubmit");
    first = false;
    for (int eye = 0; eye != 2; ++eye) {
      vr::VRVulkanTextureData_t data{};
      data.m_nImage = reinterpret_cast<uint64_t>(images[eye]); data.m_pDevice = device;
      data.m_pPhysicalDevice = physical; data.m_pInstance = instance; data.m_pQueue = queue;
      data.m_nQueueFamilyIndex = family; data.m_nWidth = width; data.m_nHeight = height;
      data.m_nFormat = VK_FORMAT_R8G8B8A8_UNORM; data.m_nSampleCount = 1;
      vr::VRTextureWithPose_t texture{};
      texture.handle = &data; texture.eType = vr::TextureType_Vulkan; texture.eColorSpace = vr::ColorSpace_Gamma;
      texture.mDeviceToAbsoluteTracking = pose.mDeviceToAbsoluteTracking;
      const auto error = session.compositor->Submit(static_cast<vr::EVREye>(eye), &texture, nullptr,
        with_pose ? vr::Submit_TextureWithPose : vr::Submit_Default);
      if (error == vr::VRCompositorError_None) ++accepted;
      report(error, "Submit", eye);
    }
    session.compositor->PostPresentHandoff();
  }
};
VulkanScene::VulkanScene(Session& session) : impl_(std::make_unique<Impl>(session)) { impl_->init(); }
VulkanScene::~VulkanScene() = default;
void VulkanScene::prepare() { impl_->prepare(); }
void VulkanScene::frame(std::uint64_t i, const vr::TrackedDevicePose_t& p, bool wp,
                       std::uint64_t& accepted, std::uint64_t& errors, Json::Array& log) {
  impl_->frame(i, p, wp, accepted, errors, log);
}
Json VulkanScene::extensions(const RuntimeExtensions& runtime) {
  Json::Array devices;
  for (auto device : impl_->devices) {
    VkPhysicalDeviceProperties properties{}; impl_->GetPhysicalDeviceProperties(device, &properties);
    const auto offered = impl_->offered(device);
    const auto required = required_device(impl_->session.compositor, device);
    const bool runtime_matches = runtime.device_known && runtime.device_name == properties.deviceName;
    devices.push_back(object({{"name", Json::make_string(properties.deviceName)}, {"vendor_id", number(properties.vendorID)},
      {"device_id", number(properties.deviceID)}, {"api_version", number(properties.apiVersion)},
      {"steamvr_output", Json::make_bool(device == impl_->physical)}, {"offered", strings(offered)},
      {"required", strings(required)}, {"runtime_device_matches", Json::make_bool(runtime_matches)},
      {"comparison", compare_extensions(required, offered, runtime.device, runtime_matches)}}));
  }
  return object({{"vulkan_available", Json::make_bool(true)}, {"required_instance", strings(impl_->instance_required)},
    {"offered_instance", strings(impl_->instance_offered)}, {"runtime_instance", strings(runtime.instance)},
    {"runtime_device_name", Json::make_string(runtime.device_name)},
    {"runtime_device", strings(runtime.device)},
    {"instance_comparison", compare_extensions(impl_->instance_required, impl_->instance_offered, runtime.instance, runtime.instance_known)},
    {"devices", Json::make_array(std::move(devices))}});
}
}  // namespace nl::vrprobe
#else
namespace nl::vrprobe {
struct VulkanScene::Impl {};
VulkanScene::VulkanScene(Session&) { throw std::runtime_error("Vulkan commands compiled out: set NL_VR_VULKAN_INCLUDE_DIR to Vulkan headers"); }
VulkanScene::~VulkanScene() = default;
void VulkanScene::prepare() {}
void VulkanScene::frame(std::uint64_t, const vr::TrackedDevicePose_t&, bool, std::uint64_t&, std::uint64_t&, Json::Array&) {}
Json VulkanScene::extensions(const RuntimeExtensions&) { return {}; }
}  // namespace nl::vrprobe
#endif
