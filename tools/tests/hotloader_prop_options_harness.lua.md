# hotloader_prop_options_harness.lua

Loads the Model Hotloader's shipped `props/library.lua` (`arg[1]`) under LuaJIT with remembered
convar values standing in for the game's `client.vdf`, then the static import starters
`library.StartStaticImport` and `library.ReimportProp` sliced from `library.lua` (`arg[2]`). Checks that
a remembered `mmdhl_prop_import_collision balanced` goes back to `hull` once
(`mmdhl_prop_import_collision_version` 1), that a choice made after that is kept until an import starts
with it and then returns to `hull`, that listing a `.blend`'s objects does not use the choice up but the
import of the chosen objects does, and that a reimport keeps detailed collision for a prop that has more
than one hull while a single-hull prop stays on the single hull (an explicit choice still applies).
Prints `PASS: detailed collision serves one import`; exit 1 with `FAIL: <reason>` otherwise. No game or
user files are accessed. Run through [test_hotloader_prop_options.py](test_hotloader_prop_options.py.md).
