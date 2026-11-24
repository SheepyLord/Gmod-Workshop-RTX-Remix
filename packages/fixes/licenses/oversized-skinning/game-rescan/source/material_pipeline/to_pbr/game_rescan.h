// GPL-2.0, like the rest of the RTX fixes. The native loader's ADR 0263: a Model Hotloader character imported again in
// the same game. A character's asset id is a hash of its manifest, which names the PMX's own textures and not the maps
// beside it, so the import of an unchanged PMX keeps its id and its material names (mmd/<the id's first 16 hex digits>/
// ...). ToPBR's game maps submitted each material name once a game session, and the worker kept each model folder's
// scan and each texture's resolution, a "no maps" result too, for its life: maps put beside the model after its first
// import were found only after a restart. ToPBR.RescanGameSource(source, prefix) forgets the prefix's submissions and
// has the worker drop its folder scans and the resolutions of that character's textures; the driver then submits the
// character's materials again. What it takes from Lua, what it forgets and which live materials the worker's rescan
// concerns are decided here. Standard C++ only: tests/game_rescan_test.cpp compiles this file alone.
#pragma once

#include <chrono>
#include <cstddef>
#include <cwctype>
#include <filesystem>
#include <set>
#include <string>
#include <string_view>

namespace MaterialPipeline { namespace ToPBR { namespace GameRescan {

// "mmd/", the first 16 hex digits of the asset id, "/": how every material name of one character starts
// (QueueGameMaterial takes a name whose characters 4 to 19 are hex digits and whose 20th is '/').
constexpr std::size_t PrefixSize = 21;

inline bool HexDigit(char c) {
    return (c >= '0' && c <= '9') || (c >= 'a' && c <= 'f') || (c >= 'A' && c <= 'F');
}

inline bool Prefix(std::string_view prefix) {
    if (prefix.size() != PrefixSize || prefix.substr(0, 4) != "mmd/" || prefix[20] != '/') return false;
    for (std::size_t i = 4; i < 20; ++i)
        if (!HexDigit(prefix[i])) return false;
    return true;
}

// Whether a material name is one of the prefix's (compared byte for byte, as the submitted names are).
inline bool Named(std::string_view name, std::string_view prefix) {
    return name.size() > prefix.size() && name.substr(0, prefix.size()) == prefix;
}

// The character's model as Lua names it: at most QueueGameMaterial's bound for a source, no control character (a NUL
// included), a file name before ".pmx" in any case. LuaPathPolicy::LocalDrivePath decides the rest. Nothing is opened.
constexpr std::size_t MaxSource = 2048;

inline bool Source(std::string_view source) {
    if (source.size() < 5 || source.size() > MaxSource) return false;
    for (char c : source) {
        const auto byte = static_cast<unsigned char>(c);
        if (byte < 0x20 || byte == 0x7F) return false;
    }
    std::string extension;
    for (char c : source.substr(source.size() - 4))
        extension += (c >= 'A' && c <= 'Z') ? static_cast<char>(c - 'A' + 'a') : c;
    const char before = source[source.size() - 5];
    return extension == ".pmx" && before != '/' && before != '\\';
}

// One file's name as Windows compares names: '/' and '\' alike, "." and ".." segments and repeated separators
// resolved, letters without case. Lexical only (nothing is opened); empty for a name that is not UTF-8.
inline std::wstring Normal(std::string_view path) {
    if (path.empty()) return {};
    try {
        std::wstring text = std::filesystem::u8path(std::string(path)).lexically_normal().wstring();
        for (auto& c : text) c = static_cast<wchar_t>(std::towlower(c));
        return text;
    } catch (...) {
        return {};
    }
}

inline bool SameFile(std::string_view a, std::string_view b) {
    const std::wstring left = Normal(a);
    return !left.empty() && left == Normal(b);
}

// Whether a live game-map job is the rescanned character's: its material name has the prefix, or its model is the
// same file (the same PMX imported before under another asset id, whose textures the character may share).
inline bool Affected(std::string_view name, std::string_view source, std::string_view prefix, std::string_view model) {
    return Named(name, prefix) || SameFile(source, model);
}

// The texture identities a rescan lets go: those of the live jobs Affected names. `jobs` maps a material name to a job
// with an `identity` and a `source` (the worker's live jobs); a job without an identity is none.
template <class Jobs>
std::set<std::string> Identities(const Jobs& jobs, std::string_view prefix, std::string_view model) {
    std::set<std::string> found;
    for (const auto& item : jobs)
        if (!item.second.identity.empty() && Affected(item.first, item.second.source, prefix, model))
            found.insert(item.second.identity);
    return found;
}

// The model's file name, for the console line.
inline std::string FileName(std::string_view source) {
    const std::size_t slash = source.find_last_of("/\\");
    return std::string(slash == std::string_view::npos ? source : source.substr(slash + 1));
}

// Forgets the prefix's names among the submitted ones, so the driver may submit them again; returns how many.
template <class Names>
std::size_t Forget(Names& names, std::string_view prefix) {
    std::size_t forgotten = 0;
    for (auto it = names.begin(); it != names.end();) {
        if (Named(*it, prefix)) {
            it = names.erase(it);
            ++forgotten;
        } else {
            ++it;
        }
    }
    return forgotten;
}

// The prefix's views say "waiting", without an error, until the worker resolves their textures again; their family
// stays. `views` is ordered by name (a std::map). Returns how many.
template <class Views>
std::size_t Wait(Views& views, std::string_view prefix) {
    std::size_t count = 0;
    for (auto it = views.lower_bound(std::string(prefix)); it != views.end() && Named(it->first, prefix); ++it) {
        it->second.state = "waiting";
        it->second.error.clear();
        ++count;
    }
    return count;
}

// At most one rescan a second (a refused call does not move the second): any server's client Lua reaches
// RescanGameSource, and a loop must not keep the worker reading model folders. One owner thread.
class Limit {
public:
    using Clock = std::chrono::steady_clock;
    static constexpr Clock::duration Interval = std::chrono::seconds(1);

    bool Take(Clock::time_point now) {
        if (taken_ && now - last_ < Interval) return false;
        taken_ = true;
        last_ = now;
        return true;
    }

private:
    Clock::time_point last_{};
    bool taken_ = false;
};

}}}
