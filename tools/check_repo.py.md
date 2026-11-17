# check_repo.py

Enforces the repo's documentation conventions so they cannot drift. Prints one line per problem and
exits 1 if there is any; [`test.ps1`](test.ps1.md) runs it first.

| Rule | Why |
|---|---|
| Every script (`.ps1 .psm1 .py .bat .cmd .lua .sh`) has `<script file name>.md` beside it | Agents and humans learn what a script does without reading it |
| Every folder with a `CMakeLists.txt` (except the root) has a `README.md` naming each C/C++ source file below it | Same, for native code; sub-folders with their own `CMakeLists.txt` are separate modules |
| Relative Markdown links resolve | Docs are navigated by links; stale links mislead |
| `CHANGELOG.md` has `## [Unreleased]` | Every notable change lands there first |
| [`docs/COMPONENTS.md`](../docs/COMPONENTS.md) mentions every folder under `loader/` and `tools/` | The component map stays complete |
| `CLAUDE.md` imports `@AGENTS.md` | One source of agent instructions |
| `runtime/base.json` `packaged` matches `runtime/` (the commit, `submodules`, `clones` and every `patches/*.patch` and `submodules/*.patch` SHA-256; the `why` texts aside) and `packages/runtime`'s `files/d3d9.dll` SHA-256 | The stored runtime is what [`runtime/build_runtime.ps1`](../runtime/build_runtime.ps1.md) builds from this repository; a patch changed without a new build fails here (R3-014, [ADR 0034](../docs/decisions/0034-the-runtimes-build-inputs-recorded.md)). Skipped when there is no `runtime/base.json` |
| Each `tools/ci/pins.json` `repository_builds` module has a `packaged` record, the SHA-256 of each of its `sources` (Markdown and `not_sources` left out, line endings as git stores them) matches the record, and `packages/<part>/files.json` lists the recorded copy | The client and glass modules stored in `packages/` are what this repository builds now; a source changed without a new build fails here, naming the source and the [`ci/repo_builds.py`](ci/repo_builds.py.md) command (R20-Q's stale client module, [ADR 0126](../docs/decisions/0126-a-record-of-what-this-repositorys-modules-were-built-from.md)). Skipped when there is no `tools/ci/pins.json` |
| No text file under `packages/` names a Windows account's folder: a drive, `Users` and an account name, with one or two backslashes (as JSON writes them) or slashes, in any case. An account name that starts with a character other than a letter or digit (`<account>`, `%USERNAME%`) is not one, and neither are the placeholders `NAME~1`, `me`, `name`, `user`, `username`, `yourname`, `you`, `example`, `public`, `default`, `someone` (the Model Hotloader's installation tests) and `private-person` (the render guard's harness), punctuation after the name left out, nor a one-character name (`C:\Users\J\xFCrgen` in a C string). Files with a NUL byte and `.xz` files are not text. Each hit is reported with its file and line | `packages/` is published twice, with the repository and in the package every player installs: `rtx_agent`'s README carried a maintainer's `C:\Users\<account>\` harness path in every package (review finding 19, 2026-11-16). This rule reads `packages/` (the other rules skip it) |
| No other text file names a Windows account's folder either (the same pattern and placeholders), and no text file anywhere, `packages/` included, names the Windows account the check runs under: its `USERNAME`, its profile folder's name and that folder's 8.3 short name, in any case, as a whole word. Names under five characters and common ones (`admin`, `runneradmin`, `guest`, ...) are not looked for. The problem gives the file and line, not the name. [`tests/test_check_repo.py`](tests/test_check_repo.py.md), which writes the fixtures for these rules, is left out | The repository is public ([AGENTS.md](../AGENTS.md) rule 10): an account name in a doc, a path under `C:\Users\<account>` or the 8.3 form of one says whose machine this is |

Skipped folders: `.git`, `out`, `build`, `__pycache__`, `third_party`, `.vs`, virtual environments, the
top-level `packages` (the RTX package's vendored inputs, whose add-ons bring their own scripts and
READMEs, [ADR 0033](../docs/decisions/0033-one-repository-package-inputs-in-git-lfs.md); only the account
rules read it, skipping the same folders inside it), and any folder
with its own `.git`: another checkout, such as a worktree the Claude app keeps in `.claude/worktrees`.
Links inside code blocks and inline code are not checked.

## Usage

```powershell
python tools\check_repo.py                # this repo
python tools\check_repo.py --root D:\x    # another checkout
```

Tests: [`tests/test_check_repo.py`](tests/test_check_repo.py.md).

R20-E's `runtime/base.json` may declare `pending_patches: {why, files}` while parallel runtime work
awaits one integration import. `files` must be a nonempty map of exact SHA-256 values for **new**
`patches/NNNN-*.patch` files sorted after every packaged patch. These alone are excluded from the
packaged comparison. A changed/missing pending patch, an existing packaged patch, an undeclared
addition, a changed submodule/clone/base or a changed packaged DLL still fails. A successful runtime
import clears the pending record; `-NoImport` retains it. This is an explicit source-versus-shipped
record, not a claim that the stored DLL contains a pending patch (ADR 0123).
