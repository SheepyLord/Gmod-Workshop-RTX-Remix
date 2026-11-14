// GPL-2.0. Conservative filesystem exclusion; runtime lookup remains authoritative.
#pragma once
#include <algorithm>
#include <cstdint>
#include <cstring>
#include <cwctype>
#include <filesystem>
#include <fstream>
#include <string>
#include <unordered_map>
#include <unordered_set>
#include <vector>
#include <Windows.h>

namespace MaterialPipeline { namespace ToPBR { namespace FallbackGuard {
// What a scan of the other mods found: the material hashes their readable USD text names, and whether it read
// every USD file (with the first reason it did not, for the log).
struct Result {
    bool complete = true;
    std::unordered_set<uint64_t> hashes;
    std::string reason;
    size_t files = 0, unread = 0;
};

// The bounds of one scan. It reads at most ReadLimit bytes of new text; a file left unread is read by a later scan
// (the cache keeps what earlier scans read), so a large mods folder is covered over a few scans.
constexpr size_t MaxEntries = 65536;
constexpr int MaxDepth = 16;
constexpr uint64_t MaxFileBytes = 16ull * 1024 * 1024, ReadLimit = 64ull * 1024 * 1024;
struct Limits {
    size_t entries = MaxEntries;
    uint64_t fileBytes = MaxFileBytes, readBytes = ReadLimit;
};

// Issue 6 (the loader's ADR 0212): a generated material is published unless another mod's readable text names its
// hash. A scan that could not read every mod (binary USD such as the Remix Toolkit's meshes, a file over the bounds,
// a link) used to publish nothing at all, so conversion kept writing textures that never showed. The runtime ranks
// ~gmod_topbr after every authored mod (runtime patch 0020, rtx.gmod.fallbackMods): an authored material the scan
// cannot read still wins in game. The scan only spares duplicate work and memory.
template<class Materials>
Materials Select(const Materials& materials, bool worldEnabled, bool gameEnabled, const Result& guard) {
    Materials visible;
    for (const auto& pair : materials)
        if ((pair.second.importedGame ? gameEnabled : worldEnabled) && !guard.hashes.count(pair.first)) visible.insert(pair);
    return visible;
}

// Every "mat_<hex>" in USD text. A hex run longer than a hash is not one (complete becomes false, for the log).
inline void ExtractHashes(const std::string& text, std::vector<uint64_t>& hashes, bool& complete) {
    size_t at = 0;
    while ((at = text.find("mat_", at)) != std::string::npos) {
        at += 4;
        size_t end = at; uint64_t value = 0;
        for (; end < text.size(); ++end) {
            unsigned char c = text[end];
            unsigned digit = c >= '0' && c <= '9' ? c - '0' :
                c >= 'A' && c <= 'F' ? c - 'A' + 10 :
                c >= 'a' && c <= 'f' ? c - 'a' + 10 : 16;
            if (digit == 16) break;
            if (end - at >= 16) { complete = false; break; }
            value = (value << 4) | digit;
        }
        if (value && end > at) hashes.push_back(value);
        at = end + 1;
    }
}

inline void ExtractHashes(const std::string& text, Result& result) {
    std::vector<uint64_t> hashes;
    ExtractHashes(text, hashes, result.complete);
    result.hashes.insert(hashes.begin(), hashes.end());
}

// One USD file's result, kept while its size and write time stay the same: a later scan does not read it again.
struct FileEntry {
    uint64_t size = 0;
    int64_t written = 0;
    bool readable = false, complete = true;
    std::string reason;
    std::vector<uint64_t> hashes;
};
struct Cache { std::unordered_map<std::wstring, FileEntry> files; };

inline std::string Relative(const std::filesystem::path& path, const std::filesystem::path& root) {
    const auto relative = path.lexically_relative(root);
    return (relative.empty() ? path : relative).u8string();
}

inline Result Scan(const std::filesystem::path& mods, const std::filesystem::path& generated, Cache* cache = nullptr,
                   const Limits& limits = {}) {
    Result result; std::error_code ec;
    size_t entries = 0; uint64_t read = 0; bool walked = true;
    std::unordered_map<std::wstring, FileEntry> seen;
    auto incomplete = [&](const std::string& why) { if (result.complete) result.reason = why; result.complete = false; };
    std::filesystem::recursive_directory_iterator it(mods, ec), end;
    if (ec) { incomplete("cannot list " + mods.u8string()); return result; }
    for (; it != end; it.increment(ec)) {
        if (ec) { incomplete("listing failed in " + mods.u8string()); walked = false; break; }
        if (++entries > limits.entries) { incomplete("more than " + std::to_string(limits.entries) + " entries"); walked = false; break; }
        const auto& path = it->path();
        if (path == generated) { it.disable_recursion_pending(); continue; }
        const DWORD attrs = GetFileAttributesW(path.c_str());
        if (attrs == INVALID_FILE_ATTRIBUTES || (attrs & FILE_ATTRIBUTE_REPARSE_POINT)) {
            incomplete("link or unreadable entry " + Relative(path, mods)); it.disable_recursion_pending(); continue;
        }
        if (it.depth() > MaxDepth) {
            incomplete("deeper than " + std::to_string(MaxDepth) + " folders: " + Relative(path, mods));
            it.disable_recursion_pending(); continue;
        }
        if (!it->is_regular_file(ec)) continue;
        auto ext = path.extension().wstring();
        for (auto& c : ext) c = wchar_t(std::towlower(c));
        if (ext != L".usda" && ext != L".usd" && ext != L".usdc") continue;
        ++result.files;
        const uint64_t size = it->file_size(ec);
        const int64_t written = ec ? 0 : int64_t(it->last_write_time(ec).time_since_epoch().count());
        if (ec) { incomplete("cannot read " + Relative(path, mods)); ++result.unread; continue; }
        if (size > limits.fileBytes) {
            incomplete("over " + std::to_string(limits.fileBytes) + " bytes: " + Relative(path, mods)); ++result.unread; continue;
        }
        const std::wstring key = path.wstring();
        const FileEntry* cached = nullptr;
        if (cache) {
            const auto found = cache->files.find(key);
            if (found != cache->files.end() && found->second.size == size && found->second.written == written) cached = &found->second;
        }
        FileEntry entry;
        if (cached) {
            entry = *cached;
        } else {
            entry.size = size; entry.written = written;
            std::ifstream f(path, std::ios::binary);
            char magic[8] = {};
            const size_t head = size_t((std::min<uint64_t>)(size, sizeof(magic)));
            if (!f.read(magic, std::streamsize(head))) {
                entry.reason = "cannot read " + Relative(path, mods);
            } else if (head == sizeof(magic) && std::memcmp(magic, "PXR-USDC", sizeof(magic)) == 0) {
                // Binary USD (the Remix Toolkit's crate files) cannot be read here; only its magic is read, and
                // the runtime still ranks its mod first.
                entry.reason = "binary USD " + Relative(path, mods);
            } else if (read + size > limits.readBytes) {
                incomplete("read limit reached before " + Relative(path, mods)); ++result.unread; continue;
            } else {
                read += size;
                std::string text(magic, head);
                text.resize(size_t(size));
                if (size > head && !f.read(text.data() + head, std::streamsize(size - head))) {
                    entry.reason = "cannot read " + Relative(path, mods);
                } else if (text.find(char(0)) != std::string::npos) {
                    entry.reason = "binary USD " + Relative(path, mods);
                } else {
                    entry.readable = true;
                    ExtractHashes(text, entry.hashes, entry.complete);
                    if (!entry.complete) entry.reason = "a name longer than a hash in " + Relative(path, mods);
                }
            }
        }
        if (!entry.readable || !entry.complete) incomplete(entry.reason);
        if (!entry.readable) ++result.unread;
        result.hashes.insert(entry.hashes.begin(), entry.hashes.end());
        seen[key] = std::move(entry);
    }
    // A whole walk replaces the cache (files that went away leave it); a walk cut short only adds to it.
    if (cache) {
        if (walked) cache->files = std::move(seen);
        else for (auto& pair : seen) cache->files[pair.first] = std::move(pair.second);
    }
    return result;
}
}}}
