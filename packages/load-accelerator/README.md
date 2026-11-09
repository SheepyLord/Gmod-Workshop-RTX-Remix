# packages/load-accelerator

The load accelerator's part of the RTX package (R26, [ADR 0140](../../docs/decisions/0140-the-load-accelerator.md)).
Only the native modules are stored here: `bin/gmcl_nlfsaccel_win64.dll` and `bin/gmsv_nlfsaccel_win64.dll`, built by
`tools\build.ps1 -Config Release` from [`fs_accel`](../../fs_accel/README.md) (this repository's code, MIT) and
imported, with the record of what they were built from
([ADR 0126](../../docs/decisions/0126-a-record-of-what-this-repositorys-modules-were-built-from.md)), by:

```powershell
python tools\ci\repo_builds.py refresh load-accelerator/bin/gmsv_nlfsaccel_win64.dll
python tools\ci\repo_builds.py refresh load-accelerator/bin/gmcl_nlfsaccel_win64.dll
```

`tools\check_repo.py` fails while their sources in `tools/ci/pins.json` `repository_builds` (`fs_accel`, the GMod
headers, the root CMake files) differ from that record.

The add-on is read from [`fs_accel/addon`](../../fs_accel/README.md) in this repository and deployed as
`garrysmod/addons/nlloadaccel`, with the modules in `garrysmod/lua/bin` (`tools/workshop.json`, part
`load-accelerator`), and it carries this repository's MIT licence (`nlloadaccel/LICENSE`). Unlike most parts it is
not marked `requires_remix`, as nothing in it needs Remix; but the combined package is, and the loader leaves every
add-on folder of such a package out of starts without RTX
([ADR 0013](../../docs/decisions/0013-rtx-only-addons-hidden-without-rtx.md)), so the accelerator runs in RTX starts
only until the loader can tell a part's add-ons apart.
