set(NL_VR_VULKAN_INCLUDE_DIR
  "H:/BACKUP_20260815/Modding/!NVIDIA-RTX-Remix/out/worktrees/r17/out/runtime-src/include/vulkan/include"
  CACHE PATH "Vulkan headers (read only); empty/missing disables Vulkan probe commands")
execute_process(COMMAND git rev-parse --path-format=absolute --git-common-dir
  WORKING_DIRECTORY "${PROJECT_SOURCE_DIR}" OUTPUT_VARIABLE vr_git_dir
  OUTPUT_STRIP_TRAILING_WHITESPACE ERROR_QUIET)
if(vr_git_dir)
  get_filename_component(vr_main "${vr_git_dir}" DIRECTORY)
else()
  set(vr_main "${PROJECT_SOURCE_DIR}")
endif()
file(TO_CMAKE_PATH "${vr_main}/out/vr/vr.lock" vr_lock_file)

add_library(nl_vr_probe_data STATIC probe_data.cpp discovery.cpp)
target_link_libraries(nl_vr_probe_data PUBLIC nl_core PRIVATE nl_build_options)
target_include_directories(nl_vr_probe_data PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}")

add_executable(vrprobe main.cpp openvr_session.cpp vulkan_scene.cpp)
target_link_libraries(vrprobe PRIVATE nl_vr_probe_data nl_build_options)
target_include_directories(vrprobe SYSTEM PRIVATE "${PROJECT_SOURCE_DIR}/third_party/openvr/include")
target_compile_definitions(vrprobe PRIVATE NL_VR_LOCK_FILE="${vr_lock_file}")
if(EXISTS "${NL_VR_VULKAN_INCLUDE_DIR}/vulkan/vulkan.h")
  target_include_directories(vrprobe SYSTEM PRIVATE "${NL_VR_VULKAN_INCLUDE_DIR}")
  target_compile_definitions(vrprobe PRIVATE NL_VR_HAS_VULKAN=1 VK_NO_PROTOTYPES)
else()
  message(STATUS "vrprobe: Vulkan headers unavailable; extensions and submit compiled out")
  target_compile_definitions(vrprobe PRIVATE NL_VR_HAS_VULKAN=0)
endif()

add_executable(nl_vr_probe_tests tests.cpp)
target_link_libraries(nl_vr_probe_tests PRIVATE nl_vr_probe_data nl_build_options)
add_test(NAME nl_vr_probe_tests COMMAND nl_vr_probe_tests)
find_package(Python3 REQUIRED COMPONENTS Interpreter)
add_test(NAME nl_vr_probe_cli
  COMMAND "${Python3_EXECUTABLE}" -I -B "${CMAKE_CURRENT_SOURCE_DIR}/cli_tests.py"
          --probe "$<TARGET_FILE:vrprobe>" --scratch "${CMAKE_CURRENT_BINARY_DIR}/scratch")
