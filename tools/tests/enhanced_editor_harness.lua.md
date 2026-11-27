# enhanced_editor_harness.lua

Runs in [test_companion_sky.py](test_companion_sky.py.md) inside its existing LuaJIT sky session. It builds
the production editor with Derma widget doubles, exercises callbacks, expands every group, uses the visibility
slider and exact colour input, and checks all four library looks. It also checks all five E2 looks in menu order,
their loaded values, lamp glow independent of the look, the four-line height of all four mixers, and high haze
values from dragging, typing and sharing. Its form models the padded docking rows so the tests detect a blank band
when the Standard notice and switch hide, on initial open and across desktop, fog-preset and VR changes.

The haze-darkness case exercises one slider at 0, 0.1, 1 and 3, verifies the three native absorption
coefficients and checks that density and tint keep their values. A version-1 file and a pasted version-1
line both acquire the library default. Copying either back as version 2 preserves every original field.
Invalid absorption vectors and incomplete version-2 looks are rejected as a whole.

In-memory DATA files and a clipboard stand in for the game's I/O. The JSON double emits compact canonical fixtures
and returns their decoded values, including native decoder cases that collapse duplicates or nulls. The harness
checks atomic validation, strict names, failed replacement, selection, saving, sharing, loading and deletion.
It writes no player files. An assertion failure exits LuaJIT nonzero. Use the Python sky suite to run it.
