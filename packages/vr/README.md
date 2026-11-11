# packages/vr

The opt-in V1 VR part, on the VR milestone branch pending independent review and user approval.
Only `bin/gmcl_nlvr_win64.dll` and Valve's `bin/openvr_api.dll` are stored here, xz-compressed in
Git LFS and indexed in files.json. No loader change or eager DLL dependency is needed.

`tools/workshop.json` packages `vr/addon` as `garrysmod/addons/nlvr` (no autorun), the four JSON
files in `vr/input` as real `nlvr/input/` files, this repository's MIT LICENSE, and OpenVR's
BSD-3-Clause LICENSE. Both DLLs deploy to `garrysmod/lua/bin`; the module loads OpenVR by full
path only at Start VR and unloads it after Exit's acknowledged cleanup.

The module is built from [vr/native](../../vr/native/README.md). Refresh it only through the
provenance/import helper (ADR 0126):

```powershell
python tools/ci/repo_builds.py refresh vr/bin/gmcl_nlvr_win64.dll
python tools/ci/fetch_prebuilt.py --only openvr --out out/vr/verified
python tools/inputs.py import vr --file out/vr/verified/vr/bin/openvr_api.dll=bin/openvr_api.dll
python tools/build_package.py
```

The SDK pin is OpenVR v2.15.6, commit `0924064316de3effbcd1acf1e309182a2deb1c05`.
DLL: 837272 bytes, SHA-256 `bab8ac6ef64e68a9ca53315b0014d131088584b2efdfa6db511d67ec03cfcb4a`.
Headers/license are vendored unchanged in [third_party/openvr](../../third_party/openvr/README.md).
The CI repository collector and fetched-download collector read the same pins; no GitHub workflow
is started by this task. The package and tests stay local. See the [integration report](../../docs/handover/VR-V1-Q-report.md).
