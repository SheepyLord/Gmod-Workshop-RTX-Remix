# collect_runtime.py

Lays out the Remix runtime a workflow built as the runtime part's files (R16,
[ADR 0106](../../docs/decisions/0106-the-rtx-package-built-on-github.md)): from the build's install folder
(`runtime\build_runtime.ps1 -Install` writes `<tree>\_output`) it copies every file the runtime part
indexes under `files/` ([`packages/runtime/files.json`](../../packages/runtime/files.json)), except this
repository's own `files/atmosphere/`, to `<out>\runtime\files\`.

The collector requires every indexed `files/numos/` path from the tagged install and reports an
unindexed file there as an error. This keeps the DLL with its own compiled passes, four night-sky
data files, credits and licences.

```powershell
python tools\ci\collect_runtime.py <tree>\_output [--out out\ci\built] [--run-url URL]
```

Writes `<out>\provenance-runtime.json`: `copied`, the indexed files the build did not make (`missing`),
the files it made that the part does not ship (`built_not_shipped`, without `.pdb`, `.lib`, `.exp`), and
for every `.dll`/`.exe` (by its SHA-256) its part, path, the fork's repository and commit from
[`runtime/base.json`](../../runtime/base.json), `runtime/patches`, and `how`: `compiled:` for `d3d9.dll`,
`usdg.dll` (upstream's USDG plugin, installed beside it since runtime patch 0093) and the Remix USD plugins,
`fetched by the same build` for the vendor binaries packman, the submodules and the clones bring. The build's
`usdg-converter.exe`, a packaging tool, is reported as built and not shipped.

Exit 0 means collection succeeded. Exit 1 means the install lacks a shipped binary or the NUMOS paths
differ from the index. [Collector tests](../tests/test_ci_tools.py.md)
