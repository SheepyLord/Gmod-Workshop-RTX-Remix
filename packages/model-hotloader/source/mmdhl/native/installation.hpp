#pragma once
#include "runtime.hpp"
#include "release.hpp"
namespace mmd {
Json runtimeIdentity();
Json componentIdentity(const char* component, const void* address);
Json workerSelfTest(bool coacd);
Json probeWorker(const fs::path& bin, bool coacd);
// ---- paths for the scripts of a server this game does not host (review finding 18) ----
// Connected to another server, every client script comes from that server, so the client module gives
// it no absolute path (the Windows account name, the folder layout). A path inside the game folder
// `gameRoot` becomes relative to it: "<game>\garrysmod\lua\bin\..." with `marked` (the installation
// check compares such paths with each other), "garrysmod\data\..." without; anything else becomes its
// file name. Windows compares the folders without regard to case.
std::string gameRelativePath(const fs::path& gameRoot,const std::string& path,bool marked);
// An identity (componentIdentity) with its "path" and "expectedPath" made game-relative, marked.
Json gameRelativeIdentity(const fs::path& gameRoot,Json identity);
// Every text of `value` without the given folders (their files keep their names): what a job's
// result names of the player's folders (its private folder, a source from the player's own list).
Json withoutFolders(Json value,const std::vector<fs::path>& folders);
// Whether a message names an absolute path.
bool namesAbsolutePath(std::string_view text);
}
