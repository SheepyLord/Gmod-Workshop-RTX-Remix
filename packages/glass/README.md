# packages/glass

The glass system's part of the RTX package (G1, [ADR 0070](../../docs/decisions/0070-glass-overhaul.md)).
Only the native module is stored here: `bin/gmcl_nlglass_win64.dll`, built by `tools\build.ps1 -Config Release`
from [`glass/native`](../../glass/native/README.md) (this repository's code, MIT, with Jolt Physics from
[`third_party/jolt`](../../third_party/jolt/README.md), MIT, linked in) and imported, with the record of
what it was built from ([ADR 0126](../../docs/decisions/0126-a-record-of-what-this-repositorys-modules-were-built-from.md)), by:

```powershell
python tools\ci\repo_builds.py refresh glass/bin/gmcl_nlglass_win64.dll
```

`tools\check_repo.py` fails while its sources in `tools/ci/pins.json` `repository_builds` (`glass/native`,
Jolt, LZMA, the GMod headers, the root CMake files) differ from that record. The GL module was built
from `43daa914`. Its SHA-256 is `63ce9163d57f3bd99e6deb4208e11a8d0d342992792670c70d6e330df9f9ef24`.
It accepts collision ranges from large maps and retains the byte-string API for older add-ons.
[GL handover](../../docs/handover/glass-big-maps-report.md)

The add-on itself is read from [`glass/addon`](../../glass/README.md) in this repository, as the companion
is, and deployed as `garrysmod/addons/nlglass` with the module in `garrysmod/lua/bin`
(`tools/workshop.json`, part `glass`). The add-on carries its MIT licence and Jolt's licence
(`nlglass/LICENSE`, `nlglass/licenses/jolt/LICENSE`). Refresh the module whenever one of its sources
changes; the check says when.
