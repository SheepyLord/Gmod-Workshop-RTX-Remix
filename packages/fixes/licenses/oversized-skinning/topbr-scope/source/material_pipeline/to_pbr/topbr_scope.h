#pragma once

// Which materials world conversion (ToPBR) may take: the player's range, rtx_topbr_scope (the native loader's
// ADR 0229). 0 is the map's own surfaces (the default), 1 adds the map's props, 2 is every scene material as before.
// Restricted (0 or 1), a material is taken only when the game's Lua has named it: the map's BSP materials, and with 1
// the props' model materials. Until Lua names any, nothing is taken.
//
// Names are compared as the texture tracker records them (lower case, forward slashes), whichever way they arrive:
// without a materials/ prefix or .vmt, a second base texture's tracker name (..._stage1) as its material, and a map's
// own patched material (maps/<map>/..., a cubemap patch, or a blended displacement's ..._wvt_patch) without that
// prefix and suffix, so the BSP's name and the drawn name meet.
//
// Standard C++ only (no Source SDK, no Windows SDK), so tests/topbr_scope_test.cpp builds it alone.

#include <cstddef>
#include <mutex>
#include <string>
#include <unordered_set>
#include <vector>

namespace MaterialPipeline {
namespace ToPBR {
namespace Scope {

constexpr int MapSurfaces = 0;
constexpr int MapAndProps = 1;
constexpr int Everything = 2;
// Bounds on what Lua may hand over: any server's client Lua reaches the bindings.
constexpr std::size_t MaxNames = 65536;
constexpr std::size_t MaxNameLength = 512;

inline bool StartsWith(const std::string& text, const char* prefix) {
    return text.compare(0, std::char_traits<char>::length(prefix), prefix) == 0;
}

inline bool EndsWith(const std::string& text, const char* suffix) {
    const std::size_t length = std::char_traits<char>::length(suffix);
    return text.size() >= length && text.compare(text.size() - length, length, suffix) == 0;
}

// The key a material name is compared by.
inline std::string Key(const std::string& name) {
    std::string key;
    key.reserve(name.size());
    for (char c : name) key.push_back(c == '\\' ? '/' : (c >= 'A' && c <= 'Z') ? static_cast<char>(c - 'A' + 'a') : c);
    if (StartsWith(key, "materials/")) key.erase(0, 10);
    if (EndsWith(key, ".vmt")) key.resize(key.size() - 4);
    if (EndsWith(key, "_stage1")) key.resize(key.size() - 7);
    if (StartsWith(key, "maps/")) {
        const std::size_t slash = key.find('/', 5);
        if (slash != std::string::npos && slash + 1 < key.size()) key.erase(0, slash + 1);
    }
    if (EndsWith(key, "_wvt_patch")) key.resize(key.size() - 10);
    return key;
}

// The range the player's setting gives: anything but 2 restricts (an unknown value too).
inline bool Restricts(int setting) { return setting != Everything; }

class Filter {
public:
    void Restrict(bool restricted) {
        std::lock_guard<std::mutex> lock(m_mutex);
        m_restricted = restricted;
    }

    bool Restricted() const {
        std::lock_guard<std::mutex> lock(m_mutex);
        return m_restricted;
    }

    // Adds names (empty and overlong ones are skipped); returns how many keys were new. Holds at most MaxNames.
    std::size_t Allow(const std::vector<std::string>& names) {
        std::lock_guard<std::mutex> lock(m_mutex);
        std::size_t added = 0;
        for (const std::string& name : names) {
            if (name.empty() || name.size() > MaxNameLength || m_keys.size() >= MaxNames) continue;
            std::string key = Key(name);
            if (!key.empty() && m_keys.insert(std::move(key)).second) ++added;
        }
        return added;
    }

    void Clear() {
        std::lock_guard<std::mutex> lock(m_mutex);
        m_keys.clear();
    }

    // Whether conversion may take this material now.
    bool Allows(const std::string& name) const {
        std::lock_guard<std::mutex> lock(m_mutex);
        return !m_restricted || m_keys.count(Key(name)) != 0;
    }

    std::size_t Size() const {
        std::lock_guard<std::mutex> lock(m_mutex);
        return m_keys.size();
    }

private:
    mutable std::mutex m_mutex;
    bool m_restricted = true;
    std::unordered_set<std::string> m_keys;
};

} // namespace Scope
} // namespace ToPBR
} // namespace MaterialPipeline
