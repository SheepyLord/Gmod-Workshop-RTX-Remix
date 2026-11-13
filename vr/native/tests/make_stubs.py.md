# make_stubs.py

Build-only generator for the offline tests' inert implementations of the four pinned OpenVR
interfaces. Reads the vendored `openvr.h` passed as argument 1 and writes an include to argument 2
under the CMake build tree. It preserves virtual signatures and supplies empty default returns;
the fake overrides the methods the session actually uses. No SDK DLL, game or SteamVR is loaded.

Usage: `python make_stubs.py <openvr.h> <out/openvr_stubs.h>`. CMake runs it when either input
changes. Exit 0 on success; nonzero for an unreadable/changed header or unwritable output.


## V4 controller frames

C also generates the IVRRenderModels test base; this remains an offline stand-in and never calls SteamVR.
