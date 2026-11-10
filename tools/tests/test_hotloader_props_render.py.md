# test_hotloader_props_render.py

Static props of the Model Hotloader draw their own meshes. Checks that the shipped
`props/render.lua` has no `GetRenderMesh`, `DrawModel`, `ents.CreateClientside` or
`scripted_ents.Register` outside comments, and runs [the harness](hotloader_props_render_harness.lua.md)
on it with LuaJIT (skipped without LuaJIT). Against the file before the fix the harness fails at once
("no proxy entity class may be registered"). Run
`python -m unittest discover -s tools/tests -p test_hotloader_props_render.py`. No game, network,
Workshop upload or profile change. Exit follows unittest.
