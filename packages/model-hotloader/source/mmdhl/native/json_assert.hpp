#pragma once
// Included first in every C++ file of this project's own targets (CMakeLists.txt, mmdhl_json_assert):
// nlohmann::json checks the preconditions of its unchecked access (a const operator[] with a key the
// object lacks, iterators of another value) with JSON_ASSERT, which compiles to nothing in a release
// build, so a manifest a script wrote could make it read out of bounds (review finding 9). Here a
// failed check throws: inside a function that may throw, the caller sees an exception; inside one
// nlohmann marks noexcept, the process ends at once (std::terminate) instead of reading on.
#ifdef __cplusplus
#include <stdexcept>
#include <string>
namespace mmdhl_json {
[[noreturn]] inline void assertionFailed(const char* condition){throw std::logic_error(std::string("Invalid JSON access (")+condition+")");}
}
#define JSON_ASSERT(condition) ((condition) ? static_cast<void>(0) : ::mmdhl_json::assertionFailed(#condition))
#endif
