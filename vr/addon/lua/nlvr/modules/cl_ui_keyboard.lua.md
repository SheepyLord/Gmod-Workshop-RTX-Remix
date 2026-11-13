# cl_ui_keyboard.lua

Owned UI-module fallback keyboard, included only after Start VR. `New(ctx,text)` supplies Open,
Close, Hit, Hover, Press/Release, Inventory and Stop. Layout is a US keyboard with latched shift,
space, backspace, enter/close and navigation/edit keys. It uses the central `Overlay.Sizes.keyboard`
1039 x 391 canvas, placed under the target's tracking-space plane. No VGUI root steals text focus.
Translated action labels use task M's companion catalog. A release activates only the same key
pressed; a miss/cancel does not type. Stop destroys its owned overlay. No permanent hooks/settings,
filesystem/network effects or standalone exit code. Tested by `companion/tests/vr_ui_test.py`.

Inventory caches its plain row for the lifetime of the keyboard entry; closing/reopening has a new entry, not per-frame debug allocation.


Review correction: sort order is stored by the lazy overlay manager; inventory refreshes recreated native handles.
