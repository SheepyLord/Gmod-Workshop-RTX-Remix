# The engine guard (R23, ADR 0130): a client and a server binary module from one source.
add_library(nl_engine_guard STATIC guard.cpp watchdog.cpp load_overlay.cpp crash_report.cpp)
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
  tests/test_crash_report.cpp)
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
