#pragma once
// A character converted from another format (FBX, glTF, DAE) by the worker
// (character_import.cpp), imported like a VRM avatar: an in-memory PMX with
// embedded textures and a manifest block, "conversion", inside its identity.
#include "runtime.hpp"
#include <map>
namespace mmd {
struct CharacterConversion {
 Bytes pmx;                             // PMX 2.0, UTF-8 text, 4-byte indices
 std::map<std::string,Bytes> textures;  // PMX texture path -> encoded image
 Json conversion;                       // manifest.conversion: bone map, units, springs, renamed morphs
 std::vector<std::string> warnings;
};
// importAsset for a converted character: the same identity, cache, registry and fit.
Json importConverted(const fs::path& source,const fs::path& cache,const Json& options,const fs::path& progress,CharacterConversion&& converted);
// A source registry (Reload's source paths: the characters' or the static props', see
// sourceRegistryPath) for adding an entry. One that does not read as a JSON object must not
// block every import, nor be overwritten: it is renamed to <name>.damaged-<UTC time> beside it,
// its file name goes to `setAside` (the import result reports it as registryBackup, in the form
// sourceRegistryDisplay gives), and a new registry starts. A file that cannot be read or renamed
// fails the import instead.
Json openSourceRegistry(const fs::path& path,std::string& setAside);
// Reload's source registries: the absolute path of the file each character (Characters) or
// static prop (Props) was imported from, with its import options, by asset id. They are kept
// outside the game folder, whose files any server's scripts read (review finding 18: they were
// garrysmod/data/mmd_hotloader/sources.local.json and static/sources.local.json), in the
// folder of their cache under %LOCALAPPDATA%\ModelHotloader\sources (sourceRegistryFolder),
// beside the picked-models list and the file-access store. A registry still in the cache from
// before, and the copies set aside beside it, move there on the first call for that cache: its
// entries join those already there (which win), and the old files go.
enum class SourceRegistry {Characters,Props};
fs::path sourceRegistryPath(const fs::path& cache,SourceRegistry which);
// <root>\<16 hex digits of SHA-256 of the cache's full path (lowercase on Windows)>: one per game
// install. <root> is %LOCALAPPDATA%\ModelHotloader\sources ($XDG_DATA_HOME/ModelHotloader/sources),
// or the folder MMDHL_SOURCES_DIR names (the tests).
fs::path sourceRegistryFolder(const fs::path& cache);
// A file there as messages name it, without the account name: %LOCALAPPDATA%\ModelHotloader\sources\...
std::string sourceRegistryDisplay(const fs::path& file);
// Moves both registries of a cache from before (see above); what cannot move now stays for the next call.
void moveSourceRegistries(const fs::path& cache);
// Adds or replaces one entry ({"source","options"}) of a registry; returns where a damaged registry
// was set aside (sourceRegistryDisplay), or nothing. A failure is an ImportError naming no path.
std::string recordSource(const fs::path& cache,SourceRegistry which,const std::string& id,const Json& entry);
}
