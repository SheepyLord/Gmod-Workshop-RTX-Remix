# vr_guard_harness.lua

Run `luajit companion/tests/vr_guard_harness.lua <repo-root>` (normally via test_vr.py). Reuses the existing
render_guard_harness.lua engine fixture, inserting one extra test branch in memory; changes no files or guard
policy. Loads the **complete production guard**, creates the chosen exact wrist target from a `lua/nlvr/client.lua`
caller, and paints an ordinary 2D raster canvas into it. Asserts 769x257, one native allocation, 790532 RGBA8
bytes, zero refusals and balanced camera/target stacks. Fixture drift fails rather than silently skipping.
Prints measurements and PASS; nonzero on assertion/runtime failure. No GPU, game, OpenVR, network or writes.
