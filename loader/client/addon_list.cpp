#include "addon_list.h"
#include "nl/fs.h"
#include "nl/paths.h"
#include "nl/vdf.h"
#include <algorithm>
#include <stdexcept>
#include <string>
#include <utility>
#include <vector>

namespace nl::client {
namespace {
using Entries = std::vector<std::pair<std::string, std::string>>;
constexpr std::size_t kMaxBytes = std::size_t{1} << 20;

bool digits(std::string_view text, std::size_t most) {
  return !text.empty() && text.size() <= most && std::all_of(text.begin(), text.end(), [](char c) { return c >= '0' && c <= '9'; });
}

// The list's entries: one top-level "addonnomount" block of plain key/value entries, and nothing else.
Entries entries_of(std::string_view text) {
  const vdf::Node top = vdf::parse(text);
  if (top.children.size() != 1 || paths::fold(top.children[0].first) != "addonnomount" || !top.children[0].second.block) {
    throw std::runtime_error(std::string(kAddonList) + " is not GMod's list of disabled add-ons");
  }
  Entries out;
  for (const auto& [key, value] : top.children[0].second.children) {
    if (value.block) throw std::runtime_error(std::string(kAddonList) + " holds a block inside its list");
    out.emplace_back(key, value.value);
  }
  return out;
}

// GMod's own layout of the file.
std::string layout(const Entries& entries) {
  std::string out = "\"addonnomount\"\n{\n";
  for (const auto& [key, value] : entries) out += "\t\"" + key + "\"\t\t\"" + value + "\"\n";
  return out + "}\n";
}

struct List {
  bool exists = false;
  std::string text;
  Entries entries;
};

List read_list(const std::filesystem::path& root) {
  fs::refuse_links(root, kAddonList);
  List list;
  const auto found = fs::stat(fs::join(root, kAddonList));
  if (!found.exists) return list;
  if (found.directory) throw std::runtime_error(std::string(kAddonList) + " is a folder");
  list.exists = true;
  list.text = fs::read_file(fs::join(root, kAddonList), kMaxBytes);
  list.entries = entries_of(list.text);
  return list;
}

// Writes `text` if it reads back as exactly `expected`, else GMod's layout of `expected`.
void write(const std::filesystem::path& root, std::string text, const Entries& expected) {
  bool same = false;
  try {
    same = entries_of(text) == expected;
  } catch (const std::exception&) {
    same = false;
  }
  if (!same) text = layout(expected);
  fs::write_atomic(fs::win32(), fs::join(root, kAddonList), text);
}

// A line that holds just one entry with this value: "<key>" "<id>", with any blanks around.
bool entry_line(std::string_view line, std::string_view id) {
  while (!line.empty() && (line.back() == '\r' || line.back() == ' ' || line.back() == '\t')) line.remove_suffix(1);
  while (!line.empty() && (line.front() == ' ' || line.front() == '\t')) line.remove_prefix(1);
  if (line.size() < 2 || line.front() != '"') return false;
  const auto key_end = line.find('"', 1);
  if (key_end == std::string_view::npos) return false;
  std::string_view rest = line.substr(key_end + 1);
  while (!rest.empty() && (rest.front() == ' ' || rest.front() == '\t')) rest.remove_prefix(1);
  return rest.size() == id.size() + 2 && rest.front() == '"' && rest.back() == '"' && rest.substr(1, id.size()) == id;
}
}  // namespace

ListChange add_to_addon_list(const std::filesystem::path& root, std::string_view id) {
  if (!digits(id, 20)) throw std::runtime_error("not a Workshop item id: " + std::string(id));
  const List list = read_list(root);
  if (std::any_of(list.entries.begin(), list.entries.end(), [&](const auto& entry) { return entry.second == id; })) {
    return ListChange::already_listed;
  }
  unsigned long long next = 1;
  for (const auto& entry : list.entries) {
    if (digits(entry.first, 18)) next = std::max(next, std::stoull(entry.first) + 1);
  }
  Entries expected = list.entries;
  expected.emplace_back(std::to_string(next), std::string(id));
  std::string text;
  const auto close = list.text.rfind('}');
  if (list.exists && close != std::string::npos) {
    text = list.text.substr(0, close);
    if (!text.empty() && text.back() != '\n') text += '\n';
    text += "\t\"" + expected.back().first + "\"\t\t\"" + expected.back().second + "\"\n" + list.text.substr(close);
  }
  write(root, text, expected);
  return ListChange::added;
}

ListChange remove_from_addon_list(const std::filesystem::path& root, std::string_view id) {
  if (!digits(id, 20)) throw std::runtime_error("not a Workshop item id: " + std::string(id));
  const List list = read_list(root);
  Entries expected;
  for (const auto& entry : list.entries) {
    if (entry.second != id) expected.push_back(entry);
  }
  if (expected.size() == list.entries.size()) return ListChange::not_listed;
  std::string text;
  for (std::size_t at = 0; at < list.text.size();) {
    const auto end = list.text.find('\n', at);
    const auto next = end == std::string::npos ? list.text.size() : end + 1;
    const std::string_view line(list.text.data() + at, next - at);
    if (!entry_line(line, id)) text += line;
    at = next;
  }
  write(root, text, expected);
  return ListChange::removed;
}
}  // namespace nl::client
