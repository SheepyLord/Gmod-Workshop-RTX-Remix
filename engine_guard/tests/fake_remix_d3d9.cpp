// A stand-in d3d9.dll for the colour cap's end-to-end test (ADR 0190): it exports what marks the Remix runtime,
// which is all the colour cap asks of the game's d3d9.dll. Built into a folder of its own, never beside a program
// that uses Direct3D.
extern "C" __declspec(dllexport) int remixapi_InitializeLibrary(const void*, void*) { return 1; }
