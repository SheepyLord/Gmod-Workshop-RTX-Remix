# cl_76_rtx_editor.lua

The RTX editor shows original material names with raw paths in tooltips. Entering Source follows the current RTX row; leaving Source maps its selected row to the canonical RTX owner. Other RTX workspace switches retain selection and neither dirty store is replaced.

R23: Derma calls the sheet's `OnActiveTabChanged` before it records the new tab (`DPropertySheet:SetActiveTab`), so the old sheet answered `IsSourceTabActive()` during a switch and neither direction carried the material over. `OnWorkspaceChanged` now sets `SwitchingTo` to the new sheet while it hands the selection over (`ApplyWorkspaceChange`, under `pcall`), and the action bar follows the new sheet at once. Tested by the loader repository's `tools/tests/ame_tabs_harness.lua`.
