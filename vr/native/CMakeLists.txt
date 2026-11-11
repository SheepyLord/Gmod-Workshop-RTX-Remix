# MIT client module, dynamically resolves OpenVR and the runtime's C API.
set(CMAKE_CXX_STANDARD 20)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
set(CMAKE_MSVC_RUNTIME_LIBRARY "MultiThreaded$<$<CONFIG:Debug>:Debug>")
set(CMAKE_MSVC_DEBUG_INFORMATION_FORMAT Embedded)
enable_testing()
add_library(nl_vr STATIC pose_math.cpp timeline.cpp session.cpp)
target_include_directories(nl_vr PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}")
target_include_directories(nl_vr SYSTEM PUBLIC "${CMAKE_SOURCE_DIR}/third_party/openvr/include")
target_link_libraries(nl_vr PRIVATE nl_core nl_build_options nl_vr_probe_data)

add_library(nl_vr_client SHARED module.cpp)
target_include_directories(nl_vr_client SYSTEM PRIVATE "${CMAKE_SOURCE_DIR}/third_party/gmod/include")
target_link_libraries(nl_vr_client PRIVATE nl_vr nl_core nl_build_options)
set_target_properties(nl_vr_client PROPERTIES OUTPUT_NAME gmcl_nlvr_win64 PREFIX "")

find_package(Python3 REQUIRED COMPONENTS Interpreter)
set(stubs "${CMAKE_CURRENT_BINARY_DIR}/openvr_stubs.h")
add_custom_command(OUTPUT "${stubs}"
  COMMAND "${Python3_EXECUTABLE}" "${CMAKE_CURRENT_SOURCE_DIR}/tests/make_stubs.py"
    "${CMAKE_SOURCE_DIR}/third_party/openvr/include/openvr.h" "${stubs}"
  DEPENDS tests/make_stubs.py "${CMAKE_SOURCE_DIR}/third_party/openvr/include/openvr.h" VERBATIM)
add_library(nl_vr_fake_openvr SHARED tests/fake_openvr.cpp "${stubs}")
target_include_directories(nl_vr_fake_openvr PRIVATE "${CMAKE_CURRENT_BINARY_DIR}" "${CMAKE_CURRENT_SOURCE_DIR}")
target_include_directories(nl_vr_fake_openvr SYSTEM PRIVATE "${CMAKE_SOURCE_DIR}/third_party/openvr/include")
target_link_libraries(nl_vr_fake_openvr PRIVATE nl_build_options)
set_target_properties(nl_vr_fake_openvr PROPERTIES OUTPUT_NAME openvr_api PREFIX "")
add_library(nl_vr_fake_runtime SHARED tests/fake_runtime.cpp tests/fake_runtime.def)
target_include_directories(nl_vr_fake_runtime PRIVATE "${CMAKE_CURRENT_SOURCE_DIR}")
target_include_directories(nl_vr_fake_runtime SYSTEM PRIVATE "${CMAKE_SOURCE_DIR}/third_party/openvr/include")
target_link_libraries(nl_vr_fake_runtime PRIVATE nl_build_options)
set_target_properties(nl_vr_fake_runtime PROPERTIES OUTPUT_NAME nlvr_test_runtime PREFIX "")
add_library(nl_vr_missing_runtime SHARED tests/missing_runtime.cpp)
target_link_libraries(nl_vr_missing_runtime PRIVATE nl_build_options)

add_executable(nl_vr_tests "${CMAKE_SOURCE_DIR}/loader/tests/test_main.cpp" tests/test_vr.cpp tests/api_layout.c)
set_target_properties(nl_vr_tests PROPERTIES C_STANDARD 11 C_STANDARD_REQUIRED ON)
target_include_directories(nl_vr_tests PRIVATE "${CMAKE_SOURCE_DIR}/loader/tests")
target_link_libraries(nl_vr_tests PRIVATE nl_vr nl_core nl_build_options)
target_compile_definitions(nl_vr_tests PRIVATE NL_VR_MANIFEST="${CMAKE_SOURCE_DIR}/vr/input/nlvr_actions.json")
add_dependencies(nl_vr_tests nl_vr_fake_openvr nl_vr_fake_runtime nl_vr_missing_runtime nl_vr_client)
add_test(NAME nl_vr_tests COMMAND nl_vr_tests)
set_tests_properties(nl_vr_tests PROPERTIES TIMEOUT 90)
add_test(NAME nl_vr_input COMMAND "${Python3_EXECUTABLE}" "${CMAKE_CURRENT_SOURCE_DIR}/tests/check_input.py")
set_tests_properties(nl_vr_input PROPERTIES TIMEOUT 30)

# Opt-in only: never initialises the user's real SteamVR in CTest.
add_executable(nl_vr_session_host tests/session_host.cpp)
target_link_libraries(nl_vr_session_host PRIVATE nl_vr nl_core nl_build_options)

# The standalone probe (VR-V1-A): a development tool, never in the package.
add_subdirectory(probe)
