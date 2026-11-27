# enhanced_editor_panel.lua

Builds the third page in the RTX Remix tab's Sky and weather category from the [editor schema](enhanced_editor.lua.md).
The page follows the current sky and VR state and offers the desktop Enhanced switch. The native **Light and mist**
group holds nine style controls. Eight collapsible groups hold 46 look controls, each with a label and wrapped help.
Groups build on first expansion. The inline colour mixers are four native font lines tall, and the companion's panel
helper moves long translated labels above controls. The page hides the padded rows around the Standard notice and
switch, then lays out the form and its parent. The spawn menu supplies the width and scrolling.

The visibility slider shows metres throughout. Its first tenth covers 0–50 m and the remainder is logarithmic
to 50,000 m. Haze density runs from 0 to 100 with just over half the track devoted to 0–10. Both number boxes
accept exact values in the displayed units. **Haze darkness** follows density and uses one linear slider from
0 to 3 in steps of 0.01. It scales all three absorption channels equally. **Haze colour** supplies the tint.
A colour can be picked visually or entered as three
normalised channels. Opening the page, expanding groups and reflecting changed convar values only update widgets.

**Start from** offers the twelve weather looks, four library looks, five reviewer looks and the player's named looks. Reset copies the
current weather. Save as and Delete confirm replacement or removal of an existing named file. Copy writes one
line to the clipboard. Paste accepts text in a dialog and uses the file validator.

The client Lua include returns the page builder. The autorun supplies the panel, editor, weather choices and
live sky state. There is no process exit code.
