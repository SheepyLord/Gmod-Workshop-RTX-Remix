# Enhanced sky package (Task P)

Compare **Standard** in the review GMA with the published package at the same
camera and time on `gm_construct`. Then switch to Enhanced and back at that camera. Look at the sky
in reflections and check that the lit haze clears on returning to Standard.
[Scene checks](sky-enhanced-R-report.md#first-check-in-the-poc)

The combined GMA carries the Enhanced sky under `native/payload/runtime/numos/`. The loader puts this
folder beside the active `d3d9.dll`, in `native-loader/packages/gmod-rtx-remix/<version>_<generation>/runtime/`.
[Runtime part](../../packages/runtime/README.md), [package format](../PACKAGE_FORMAT.md)

## Files and provenance

The runtime part gained 55 files (23,744,503 bytes). `numos/spirv/` holds all 41 compute passes named
in the pinned library's pass table. `numos/nightsky/` holds `milkyway.bin`, `moon.bin`,
`starlight_low.bin`, `stars.bin` and their original `CREDITS.md`. The three top-level notices are
`LICENSE`, `NOTICE` and `THIRD_PARTY_NOTICES.md`. The six licence texts are in `numos/licenses/`.

Each of the 55 inputs came from the runtime's tagged `_output/numos/` install through a separate,
serial `python tools/inputs.py import runtime --file "<source>=files/numos/<relative-path>"` call.
The index stores 45 binaries as XZ objects and ten texts verbatim, occupying 10,880,115 bytes in total
before the DLL. Each stored file was read back and compared with its compiled pass or pinned source,
and its SHA-256 was checked against the tagged install. The runtime index uses portable source paths.
[File index](../../packages/runtime/files.json)

The wrapper ran in `sky2p` with the Python installation providing Meson 1.12.1 first on `PATH` and
temporary files under `out/tmp/`. It reused the configured Release build on `claude/sky-enhanced`.

```powershell
$runtime = (Resolve-Path '..\r17\out\runtime-src').Path
$fork = Split-Path -Parent (git -C $runtime rev-parse --path-format=absolute --git-common-dir)
.\runtime\build_runtime.ps1 -Fork $fork -Worktree $runtime -Install -Jobs 6
```

Both compile passes and the tagged install produced the same DLL tested in Task R, 532,803,072 bytes
with SHA-256 `d8b30bd8e544a038b8472d7790df76132f307fe3facb123d7a9389e704e3e795`.
The wrapper verified the fork tree at `1370af0d2` and imported the DLL once. Its 78,830,324-byte
XZ object has LFS SHA-256 `98b94946f488177b6deee0a6352cd8908adf02d698ece4ce814fd8e99e25a797`.
The packaged record now includes all 104 runtime patches through 0108, the RTXDI submodule patch,
the two submodule settings and the three clone pins. The wrapper cleared the pending patch record.
[Build record](../../runtime/base.json), [Task R verification](sky-enhanced-R-report.md#verification)

## Release workflow

The runtime cache key checks the NUMOS repository and commit in `tools/ci/pins.json` against
`runtime/base.json` before the cache lookup. On a miss the existing runtime wrapper clones NUMOS
at `41842c69e9281f197acff95263260a0149876007`. The collector requires the complete indexed
`numos/` set from the tagged install. A missing pass, data file or notice fails collection, as does
an installed NUMOS file missing from the index. The package job gets these files and the DLL from
the runtime job's cache and excludes local NUMOS copies from its LFS download.
[Package workflow](../../.github/workflows/package.yml), [collector](../../tools/ci/collect_runtime.py.md)

## Local verification

The initial PoC check found an active capture. Each build started after both the process check and the
capture-lock check were clear, then held the shared lock for its duration.

| Command in `sky2p` | Result |
|---|---|
| `tools\test.ps1 -Config Release` | Exit 0. `repo conventions OK` and `100% tests passed, 0 tests failed out of 35` in CTest. Python reported 29 gmapack tests (1 skipped), 26 Steam tests (1 skipped) and 2,249 tools tests (8 skipped). The gate ended with `All checks passed.` |
| `python tools/ci/collect_runtime.py <runtime>/_output --out out/task-p/ci` | Exit 0. Collected 246 indexed files and 42 native binaries. All 55 NUMOS paths and hashes and the DLL matched the local package inputs. The only extra tagged file was the build tool `usdg-converter.exe`. |

The runtime LFS pointers match the stored XZ hashes and sizes. Both workflow LFS filters retained
the same 627 paths and excluded all 45 NUMOS objects that the runtime job supplies. The local logs are
under `out/task-p/` in this worktree.

## Archive and deployment

`python tools/build_package.py` built all 15 parts from packaging commit `3ffccf66` after the
Release gate. The combined manifest lists 1,993 files. The Release `nlctl` accepted both the
combined manifest and the packed archive.

| GMA | Version | Size in bytes |
|---|---|---:|
| Published Workshop item 3829070317 | `0.0.0-dev.20261125084526+82cd43a9` | 2,356,069,196 |
| Local review package | `0.0.0-dev.20261126092958+13e4bb21` | 2,402,365,274 |
| Increase | | **46,296,078** (44.15 MiB) |

The published size matches the archive named by `<repo>/out/workshop/published.json`. The review
archive is `out/dist/gmod-rtx-remix-0.0.0-dev.20261126092958_13e4bb21.gma` in this worktree.
Its SHA-256 is `29622427ae15ad390ff8ec4cfb48a9380dcb058f9230632bf3ac6fa463d25a6e`.

An independent read of the GMA matched the DLL and every NUMOS entry to its manifest size and SHA-256
and to the package index. With just this GMA allowlisted in an empty scratch game folder,
`nlctl apply <scratch game> --json` returned `deployed`. The extracted DLL and all 55 NUMOS files
matched by path and hash in the active generation's `runtime/` folder.

Task P is complete on the local branch. Claude owns in-game comparison and frame-time measurements.
The GitHub workflow, merge and publication await the round's release decision.
