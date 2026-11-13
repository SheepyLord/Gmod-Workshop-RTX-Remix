# vr_measure_build.ps1

Builds the read-only thread-clock development helper in vr/native/tests/qinspect.cpp with
MSVC x64 /O2 /MT. Run `tools\vr_measure_build.ps1`. Inputs: configured VS Build Tools, Windows
SDK and vendored GMod headers. Output: out/vr/v2q/inspect/gmcl_nlvrqinspect_win64.dll and linker
scratch beside it. TEMP/TMP stay under out/tmp; all environment variables are restored. No
package index, game/Steam file, OpenVR call, download or publication. Exit 0 on success;
compiler/toolchain errors are fatal. Used only by the VR driver --inspect-dll option.

Links user32 solely for a read-only current-process foreground observation; it activates no
window and injects no input. Info records that fact to distinguish focus/context from CPU/GPU work.
