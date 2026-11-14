// GPL-2.0. The player's own Remix categories win over automatic categorisation (the loader's ADR 0213).
//
// Automatic categories go to the runtime's user layer (remixapi_AddTextureHash), which is stronger than rtx.conf.
// A texture the player took out of a category in rtx.conf (a "-0x..." entry, which the Remix developer menu writes
// when a category is cleared and the settings are saved) was put back there by the next automatic pass, every
// session. Automatic categorisation now never adds a hash to a list the player's rtx.conf takes it out of. user.conf
// is not read: Remix writes its texture lists only from automatic categories that a Save Settings kept, never from
// the player's own choices. Removals are unchanged (they correct automatic leftovers such as water saved as a decal).
#pragma once
#include <algorithm>
#include <cctype>
#include <chrono>
#include <cstdint>
#include <cstdlib>
#include <filesystem>
#include <fstream>
#include <mutex>
#include <string>
#include <system_error>
#include <unordered_map>
#include <unordered_set>
#include <utility>

namespace MaterialPipeline { namespace AutoCategorisation { namespace PlayerCategories {

// Bounds: a larger rtx.conf is read up to MaxBytes, and at most MaxHashes exclusions are kept.
constexpr std::uintmax_t MaxBytes = 16u * 1024 * 1024;
constexpr size_t MaxHashes = 1000000;

// For each rtx.*Textures list (lower-case name), the hashes the file takes out of it.
struct Exclusions {
    std::unordered_map<std::string, std::unordered_set<uint64_t>> lists;
    size_t count = 0;
    bool truncated = false;
};

inline std::string Lower(std::string text) {
    for (auto& c : text) c = char(std::tolower(static_cast<unsigned char>(c)));
    return text;
}

inline std::string Trim(const std::string& text) {
    const auto begin = text.find_first_not_of(" \t\r\n\"");
    if (begin == std::string::npos) return {};
    const auto end = text.find_last_not_of(" \t\r\n\"");
    return text.substr(begin, end - begin + 1);
}

// Remix config text: "key = value" lines; '#' starts a comment line. A texture list's value is comma-separated
// hashes, "-0x..." taking one out. Only the exclusions are kept.
inline Exclusions Parse(const std::string& text, size_t maxHashes = MaxHashes) {
    Exclusions result;
    size_t start = 0;
    while (start < text.size()) {
        size_t stop = text.find('\n', start);
        if (stop == std::string::npos) stop = text.size();
        const std::string line = Trim(text.substr(start, stop - start));
        start = stop + 1;
        if (line.empty() || line[0] == '#') continue;
        const size_t equals = line.find('=');
        if (equals == std::string::npos) continue;
        const std::string key = Lower(Trim(line.substr(0, equals)));
        if (key.size() <= 12 || key.compare(0, 4, "rtx.") != 0 || key.compare(key.size() - 8, 8, "textures") != 0) continue;
        const std::string value = line.substr(equals + 1);
        size_t at = 0;
        while (at <= value.size()) {
            size_t comma = value.find(',', at);
            if (comma == std::string::npos) comma = value.size();
            const std::string item = Trim(value.substr(at, comma - at));
            at = comma + 1;
            if (item.size() < 2 || item[0] != '-') continue;
            const std::string digits = item.substr(1);
            char* end = nullptr;
            const unsigned long long hash = std::strtoull(digits.c_str(), &end, 16);
            if (!end || *end != '\0' || hash == 0) continue;
            if (result.count >= maxHashes) { result.truncated = true; return result; }
            if (result.lists[key].insert(hash).second) ++result.count;
        }
    }
    return result;
}

inline bool Excluded(const Exclusions& exclusions, const char* option, uint64_t hash) {
    if (!option || !hash) return false;
    const auto list = exclusions.lists.find(Lower(option));
    return list != exclusions.lists.end() && list->second.count(hash) != 0;
}

// The category bits automatic categorisation writes, and their lists (the values of the module's CategoryFlags and
// of the Lua RemixCategoryManager.CATEGORY bits for these six are the same).
struct BitList { uint32_t bit; const char* option; };
constexpr BitList Lists[] = {
    {0x4, "rtx.skyBoxTextures"}, {0x8, "rtx.ignoreTextures"}, {0x400, "rtx.particleTextures"},
    {0x1000, "rtx.decalTextures"}, {0x40000, "rtx.animatedWaterTextures"}, {0x1000000, "rtx.legacyEmissiveTextures"},
};

// The bits of flags that may be added for hash: those whose list the exclusions do not take the hash out of.
inline uint32_t Allowed(const Exclusions& exclusions, uint64_t hash, uint32_t flags) {
    for (const auto& list : Lists)
        if ((flags & list.bit) && Excluded(exclusions, list.option, hash)) flags &= ~list.bit;
    return flags;
}

// The player's rtx.conf in the game folder (two folders above bin\win64), read again when its size or write time
// changes; Refresh looks at most every two seconds. Thread-safe: the render hooks and the pipeline worker ask.
class File {
public:
    static File& Instance() { static File file; return file; }

    void SetPath(std::filesystem::path path) {
        std::lock_guard<std::mutex> lock(m_mutex);
        m_path = std::move(path);
        m_size = std::uintmax_t(-1);
        m_checked = {};
    }

    // Returns true when the exclusions changed.
    bool Refresh(bool force = false) {
        std::filesystem::path path;
        {
            std::lock_guard<std::mutex> lock(m_mutex);
            const auto now = std::chrono::steady_clock::now();
            if (!force && m_checked != std::chrono::steady_clock::time_point{} && now - m_checked < std::chrono::seconds(2))
                return false;
            m_checked = now;
            path = m_path;
        }
        if (path.empty()) return false;
        std::error_code ec;
        const auto size = std::filesystem::file_size(path, ec);
        const auto time = ec ? std::filesystem::file_time_type{} : std::filesystem::last_write_time(path, ec);
        const bool present = !ec;
        {
            std::lock_guard<std::mutex> lock(m_mutex);
            if (present == m_present && (!present || (size == m_size && time == m_time))) return false;
        }
        Exclusions exclusions;
        if (present) {
            std::ifstream file(path, std::ios::binary);
            std::string text(size_t((std::min)(size, MaxBytes)), '\0');
            if (!file.read(text.data(), std::streamsize(text.size()))) text.resize(size_t(file.gcount()));
            exclusions = Parse(text);
            exclusions.truncated = exclusions.truncated || size > MaxBytes;
        }
        std::lock_guard<std::mutex> lock(m_mutex);
        m_present = present; m_size = present ? size : std::uintmax_t(-1); m_time = time;
        m_exclusions = std::move(exclusions);
        return true;
    }

    uint32_t Allowed(uint64_t hash, uint32_t flags) const {
        std::lock_guard<std::mutex> lock(m_mutex);
        return PlayerCategories::Allowed(m_exclusions, hash, flags);
    }

    bool MayAdd(const char* option, uint64_t hash) const {
        std::lock_guard<std::mutex> lock(m_mutex);
        return !Excluded(m_exclusions, option, hash);
    }

    size_t Count() const { std::lock_guard<std::mutex> lock(m_mutex); return m_exclusions.count; }

private:
    mutable std::mutex m_mutex;
    std::filesystem::path m_path;
    bool m_present = false;
    std::uintmax_t m_size = std::uintmax_t(-1);
    std::filesystem::file_time_type m_time{};
    std::chrono::steady_clock::time_point m_checked{};
    Exclusions m_exclusions;
};

}}}
