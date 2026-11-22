# test_hotloader_workshop_install.py

[ADR 0255](../../docs/decisions/0255-workshop-models-install-several-at-once.md): the Model Hotloader installs a Workshop
package's models several at once, lists installed models in the library without rebuilding it for each, and runs its
install work below normal CPU priority. In the user's game a freshly subscribed pack of twelve characters installed
one file and one model at a time (76 s in the PoC, 64 s of it the models' asset checks), and each model rebuilt a
library of 220 characters and its open window: a hitch of 100-140 ms per model.

`WorkshopInstallTests` runs [hotloader_workshop_install_harness.lua](hotloader_workshop_install_harness.lua.md) with
LuaJIT once per scenario: `parallel` (eight models with shared textures: each file moved once, four checks side by side,
records before writes, a few state writes, library updates without rebuilds), `failures` (a failed commit, a waiting
model, a check that passes alone, an invalid model), `replace` (a changed file replaced alone) and `library_add`
(`library.Add` lists what a rebuild lists, reading only the new models' files).

`WorkshopInstallSourceTests` reads the shipped sources: the native module's file commits and asset checks start their
work with `BackgroundWork` (`THREAD_PRIORITY_BELOW_NORMAL`, the thread's own priority given back after; not Windows'
background mode, whose very low I/O priority slowed large checks tenfold), a spawn's load
(`RequestAsset`) does not; `installed()` lists the model with `listInstalled` and saves its record with
`saveStateSoon`; `listInstalled` decodes a character's manifest at once (`library.Prime`); `library.lua` has
`library.Add` and `library.Prime`.

```powershell
python -I -m unittest discover -s tools/tests -p test_hotloader_workshop_install.py    # from the repository root
```

No game or installed data is touched; nothing is written. Requires LuaJIT for the harness (otherwise one explicit
skip). Exit 0 on pass, nonzero on an assertion, a Lua error or a timeout.
