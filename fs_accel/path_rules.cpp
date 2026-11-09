// Which paths the loose-folder cache may answer for, and GMod's add-on wildcards (R26, ADR 0140).
#include "fs_accel.h"

namespace nl::fs_accel {
namespace {

char lower(char c) noexcept { return (c >= 'A' && c <= 'Z') ? static_cast<char>(c - 'A' + 'a') : c; }

// CON, PRN, AUX, NUL, COM0-9, LPT0-9, with or without an extension: Windows opens the device, not a file.
bool reserved_device(std::string_view component) noexcept {
  const std::string_view stem = component.substr(0, component.find('.'));
  if (stem == "con" || stem == "prn" || stem == "aux" || stem == "nul") return true;
  return stem.size() == 4 && (stem.substr(0, 3) == "com" || stem.substr(0, 3) == "lpt") && stem[3] >= '0' &&
      stem[3] <= '9';
}

// A component Windows could resolve as another name: "." and "..", trailing dots and spaces (stripped), an 8.3 short
// name ("PROGRA~1"), a device. Empty components are doubled or trailing separators.
bool component_ok(std::string_view component) noexcept {
  if (component.empty() || component == "." || component == "..") return false;
  const char last = component.back();
  if (last == '.' || last == ' ') return false;
  for (std::size_t i = 0; i + 1 < component.size(); ++i) {
    if (component[i] == '~' && component[i + 1] >= '0' && component[i + 1] <= '9') return false;
  }
  return !reserved_device(component);
}

template <class Char>
bool normalize_impl(std::basic_string_view<Char> in, PathBuffer& out) noexcept {
  constexpr std::size_t kMax = sizeof(out.text);
  if (in.size() < 4 || in.size() >= kMax) return false;
  const auto drive = static_cast<unsigned>(in[0]);
  const bool letter = (drive >= 'A' && drive <= 'Z') || (drive >= 'a' && drive <= 'z');
  if (!letter || in[1] != Char(':') || (in[2] != Char('\\') && in[2] != Char('/'))) return false;
  out.text[0] = lower(static_cast<char>(drive));
  out.text[1] = ':';
  out.text[2] = '\\';
  std::size_t n = 3;
  std::size_t start = 3;
  for (std::size_t i = 3; i < in.size(); ++i) {
    const auto code = static_cast<unsigned>(in[i]);
    if (code < 0x20 || code >= 0x7f) return false;  // printable ASCII only: no code-page or Unicode folding here
    char c = static_cast<char>(code);
    if (c == '/') c = '\\';
    if (c == ':' || c == '*' || c == '?' || c == '"' || c == '<' || c == '>' || c == '|') return false;
    if (c == '\\') {
      if (!component_ok(std::string_view(out.text + start, n - start))) return false;
      start = n + 1;
    }
    out.text[n++] = lower(c);
  }
  if (!component_ok(std::string_view(out.text + start, n - start))) return false;
  out.size = n;
  return true;
}

}  // namespace

bool normalize(std::string_view in, PathBuffer& out) noexcept { return normalize_impl(in, out); }
bool normalize(std::wstring_view in, PathBuffer& out) noexcept { return normalize_impl(in, out); }

bool wildcard_match(std::string_view pattern, std::string_view name) noexcept {
  std::size_t p = 0, s = 0, star = std::string_view::npos, mark = 0;
  while (s < name.size()) {
    if (p < pattern.size() && (pattern[p] == '?' || pattern[p] == name[s])) {
      ++p;
      ++s;
    } else if (p < pattern.size() && pattern[p] == '*') {
      star = p++;
      mark = s;
    } else if (star != std::string_view::npos) {
      p = star + 1;
      s = ++mark;
    } else {
      return false;
    }
  }
  while (p < pattern.size() && pattern[p] == '*') ++p;
  return p == pattern.size();
}

}  // namespace nl::fs_accel
