# The engine guard (R23, ADR 0130): a client and a server binary module from one source.
add_library(nl_engine_guard STATIC guard.cpp watchdog.cpp load_overlay.cpp load_activity.cpp load_eta.cpp crash_report.cpp
  colour_cap.cpp)
target_include_directories(nl_engine_guard PUBLIC "${CMAKE_CURRENT_SOURCE_DIR}")
target_link_libraries(nl_engine_guard PRIVATE nl_build_options user32 gdi32)

foreach(realm IN ITEMS client server)
  if(realm STREQUAL "client")
    set(prefix gmcl)
  else()
    set(prefix gmsv)
  endif()
  add_library(nl_engine_guard_${realm} SHARED module.cpp)
  target_include_directories(nl_engine_guard_${realm} SYSTEM PRIVATE "${CMAKE_SOURCE_DIR}/third_party/gmod/include")
  target_link_libraries(nl_engine_guard_${realm} PRIVATE nl_engine_guard nl_build_options)
  target_compile_definitions(nl_engine_guard_${realm} PRIVATE NL_ENGINE_GUARD_REALM="${realm}")
  if(realm STREQUAL "server")
    # The menu loads the gmsv_ copy: only it has the load overlay's functions (R24, ADR 0134).
    target_compile_definitions(nl_engine_guard_${realm} PRIVATE NL_ENGINE_GUARD_MENU=1)
  endif()
  set_target_properties(nl_engine_guard_${realm} PROPERTIES OUTPUT_NAME ${prefix}_nlengineguard_win64 PREFIX "")
endforeach()

add_executable(nl_engine_guard_tests ../loader/tests/test_main.cpp tests/test_guard.cpp tests/test_overlay.cpp
  tests/test_load_activity.cpp tests/test_load_eta.cpp tests/test_crash_report.cpp tests/test_colour_cap.cpp)
target_include_directories(nl_engine_guard_tests PRIVATE ../loader/tests)
target_link_libraries(nl_engine_guard_tests PRIVATE nl_engine_guard nl_build_options)
target_compile_definitions(nl_engine_guard_tests PRIVATE
  NL_ENGINE_GUARD_MODULE_SOURCE="${CMAKE_CURRENT_SOURCE_DIR}/module.cpp")
add_test(NAME nl_engine_guard_tests COMMAND nl_engine_guard_tests)
set_tests_properties(nl_engine_guard_tests PROPERTIES TIMEOUT 60)

# End to end (ADR 0130): a stand-in materialsystem.dll whose code holds the call site, and a test of its own
# (a separate process: the tests above must see no materialsystem.dll).
enable_language(ASM_MASM)
add_library(nl_engine_guard_fake_materialsystem SHARED tests/fake_materialsystem.cpp tests/fake_materialsystem.asm)
target_link_libraries(nl_engine_guard_fake_materialsystem PRIVATE nl_build_options)
set_target_properties(nl_engine_guard_fake_materialsystem PROPERTIES OUTPUT_NAME materialsystem PREFIX "")
add_executable(nl_engine_guard_detour_tests ../loader/tests/test_main.cpp tests/test_detour.cpp)
target_include_directories(nl_engine_guard_detour_tests PRIVATE ../loader/tests)
target_link_libraries(nl_engine_guard_detour_tests PRIVATE nl_engine_guard nl_build_options)
add_dependencies(nl_engine_guard_detour_tests nl_engine_guard_fake_materialsystem)
add_test(NAME nl_engine_guard_detour_tests COMMAND nl_engine_guard_detour_tests)
set_tests_properties(nl_engine_guard_detour_tests PROPERTIES TIMEOUT 60)

# The colour cap end to end (ADR 0190): a stand-in shaderapidx9.dll whose four colour functions wrap above 1 as the
# game's do, and a stand-in Remix d3d9.dll, both in a folder of their own (a d3d9.dll beside other programs would be
# loaded by them), and a test process of its own that loads them by path.
set(nl_colour_fakes "${CMAKE_CURRENT_BINARY_DIR}/colour_fakes")
add_library(nl_engine_guard_fake_shaderapi SHARED tests/fake_shaderapi.cpp tests/fake_shaderapi.asm)
target_link_libraries(nl_engine_guard_fake_shaderapi PRIVATE nl_build_options)
# The vtable must hold the functions themselves, not incremental linking's jump thunks.
target_link_options(nl_engine_guard_fake_shaderapi PRIVATE /INCREMENTAL:NO)
set_target_properties(nl_engine_guard_fake_shaderapi PROPERTIES OUTPUT_NAME shaderapidx9 PREFIX ""
  RUNTIME_OUTPUT_DIRECTORY "${nl_colour_fakes}" LIBRARY_OUTPUT_DIRECTORY "${nl_colour_fakes}"
  ARCHIVE_OUTPUT_DIRECTORY "${nl_colour_fakes}")
add_library(nl_engine_guard_fake_d3d9 SHARED tests/fake_remix_d3d9.cpp)
target_link_libraries(nl_engine_guard_fake_d3d9 PRIVATE nl_build_options)
set_target_properties(nl_engine_guard_fake_d3d9 PROPERTIES OUTPUT_NAME d3d9 PREFIX ""
  RUNTIME_OUTPUT_DIRECTORY "${nl_colour_fakes}" LIBRARY_OUTPUT_DIRECTORY "${nl_colour_fakes}"
  ARCHIVE_OUTPUT_DIRECTORY "${nl_colour_fakes}")
add_executable(nl_engine_guard_colour_tests ../loader/tests/test_main.cpp tests/test_colour_cap_e2e.cpp)
target_include_directories(nl_engine_guard_colour_tests PRIVATE ../loader/tests)
target_link_libraries(nl_engine_guard_colour_tests PRIVATE nl_engine_guard nl_build_options)
target_compile_definitions(nl_engine_guard_colour_tests PRIVATE NL_COLOUR_FAKES_DIR=L"${nl_colour_fakes}")
add_dependencies(nl_engine_guard_colour_tests nl_engine_guard_fake_shaderapi nl_engine_guard_fake_d3d9)
add_test(NAME nl_engine_guard_colour_tests COMMAND nl_engine_guard_colour_tests)
set_tests_properties(nl_engine_guard_colour_tests PROPERTIES TIMEOUT 60)
