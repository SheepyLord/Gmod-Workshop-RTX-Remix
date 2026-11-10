# test_light_updater.py

Runs [light_updater_harness.lua](light_updater_harness.lua.md) with local LuaJIT against the packaged RTX
fixes light updater in `packages/fixes` (`cl_rtx_light_updater.lua`): which helpers a frame draws since R28
([ADR 0144](../../docs/decisions/0144-the-light-updater-draws-what-the-runtime-needs.md)). One test per rule:
steady point lights in view, near the eye and on their turn; a texture light or the sun among what a helper
may set; the map's visibility data; a spot light and a switched light that their own helpers set, and one its
helper does not; a light that only its neighbours' helpers set; the runtime's options in `rtx.conf`; a map whose
world lights cannot be used; a lamp spawned later.

`python -I -m pytest tools\tests\test_light_updater.py -q`, or with `tools\test.ps1`. Reads only repository
files; no game or network. A missing LuaJIT is a reported skip; a failed harness assertion fails the test.
