# ame_tabs_harness.lua

LuaJIT harness (R23, the user's item 4) for the Advanced Material Editor's RTX editor panel
(`cl_76_rtx_editor.lua`, loaded as packaged, with stub globals so only its `vgui.Register` runs).
Invoked by [test_ame_tabs.py](test_ame_tabs.py.md): `luajit ame_tabs_harness.lua REPO`.

It switches the panel's sheets through a property sheet that orders the calls as Derma's
`DPropertySheet:SetActiveTab` does (`dpropertysheet.lua` 212-234: `OnActiveTabChanged` runs before
the sheet records the new tab), with the selection functions recorded, and checks:

- Material to Source / VMT: the Source sheet gets the PBR sheet's material while it counts as
  active, and that row is selected;
- Source / VMT to Material: the Material sheet gets the Source sheet's material (forced to the PBR
  selection), and the action bar is the Material sheet's;
- a row that shares a captured texture identity goes to its canonical owner;
- an error during a switch is reported and never leaves the switch state behind.

Prints `PASS ame tabs` and exits 0, or raises an assertion error. No side effects.
