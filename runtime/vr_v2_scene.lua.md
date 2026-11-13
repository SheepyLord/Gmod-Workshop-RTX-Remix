# vr_v2_scene.lua

This is the controlled client-side scene used by VR V2 task R. It is a test fragment, not a game
add-on or an autorun file. It makes the stock geometry for the thin-feature and near-prop captures,
or binds the game window to an overlay and opens the escape menu. It is not packaged.

Append its text to the generated acceptance probe, inside that probe's lexical scope, before the
driver transfers the probe to its own PoC game. The V1 probe provides CONFIG, origin, angles, barrel,
lastFrame and emit. Task R's private lab adapter records the complete generated source and its
hash beside every run. Do not inject this fragment into a field game or an unowned game process.

Set CONFIG.v2r_case to ghost, near, window or barrel. Ghost uses fifteen 3 mm strands and a segmented
0.12 m radius ring at 1.5 m, with a wall at 8 m. Near sets a held stock cube's nominal model bounds
to 0.06 x 0.08 x 0.10 m and follows lastFrame.left. CONFIG.v2r_near records the commanded front depth;
the timeline puts the hand's centre 0.03 m farther forward. Use a fixed head and hand for the size
comparison. The mesh/bounds query logs the visible mesh's padding rather than assuming that model
bounds are visible vertices. Window requires task N's OverlayWindow function and the runtime's
SetOverlayWindow export. It uses a head-attached overlay and keeps the mirror out of its picture.
Barrel adds no geometry and keeps the acceptance probe's stock barrel.

The fragment writes console records with the v2r-fixture, v2r-mesh and v2r-window kinds. It writes
no file itself; the surrounding probe requests the runtime captures. It creates client entities
and, for near/window cases, PreRender hooks. The window overlay belongs to the native session and
is destroyed at Stop. The driver owns the whole test process; its normal quit removes the remaining
client entities and fixture hooks, then restores the PoC from its protected snapshot. Keep the
game under three minutes. Simulated sessions use the PoC lock; Index sessions also use the VR lock.

There is no command-line exit code. A missing stock model or failed overlay API raises a Lua error,
which the unattended driver records as a failed run. Source and picture evidence, the exact lab
commands, the measured near limit and the interpretation of the captures are in
[the task report](../docs/handover/VR-V2-R-report.md).
