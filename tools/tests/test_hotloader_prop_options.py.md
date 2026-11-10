# test_hotloader_prop_options.py

The Model Hotloader's detailed static prop collision (CoACD) is chosen for one import, never a
remembered default. Runs [the harness](hotloader_prop_options_harness.lua.md) on the shipped
`props/library.lua` and `library.lua` with LuaJIT (skipped without LuaJIT), and checks that the
importer's option combo boxes (`convarChoices` in `ui.lua`) follow their setting, so the collision choice
shows the single hull again once an import used the detailed one. Against the files before the change
the harness fails at once ("a remembered detailed choice goes back to the single hull"). Run
`python -m unittest discover -s tools/tests -p test_hotloader_prop_options.py`. No game, network,
Workshop upload or profile change. Exit follows unittest.
