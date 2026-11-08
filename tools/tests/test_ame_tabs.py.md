# test_ame_tabs.py

Unit test (R23, the user's item 4) for the Advanced Material Editor's RTX editor: the material being
edited carries over between its Material and Source / VMT sheets. Runs
[ame_tabs_harness.lua](ame_tabs_harness.lua.md) under LuaJIT on the packaged
`packages/advanced-material-editor/!advanced_material_editor/lua/advmat/cl_76_rtx_editor.lua`.

```powershell
cd tools; python -m unittest tests.test_ame_tabs
```

Skipped without LuaJIT. Exit code 0 when it passes. No side effects. Against the file as shipped
before R23 the harness fails at "Source / VMT shows the material being edited".
