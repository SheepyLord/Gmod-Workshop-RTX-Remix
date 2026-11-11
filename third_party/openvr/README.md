# Valve OpenVR SDK

Unmodified files from [ValveSoftware/openvr](https://github.com/ValveSoftware/openvr), tag
**v2.15.6**, commit `0924064316de3effbcd1acf1e309182a2deb1c05`, downloaded from
`https://raw.githubusercontent.com/ValveSoftware/openvr/<commit>/<path>`.

| Upstream path | Local path | Bytes | SHA-256 |
|---|---|---:|---|
| headers/openvr.h | include/openvr.h | 296217 | 1e6ed57199896cc1f7c5484e50fa18955e97be15be690beb28d998c877ead7fd |
| LICENSE | LICENSE | 1488 | f56ff606104d4ef18e617921a75c73ad73b5a1a1d70c69590c29de16919e04ad |
| bin/win64/openvr_api.dll | packages/vr/bin/openvr_api.dll.xz (indexed Git LFS input) | 837272 | bab8ac6ef64e68a9ca53315b0014d131088584b2efdfa6db511d67ec03cfcb4a |

The probe and VR module use the header as a SYSTEM include and resolve the DLL's exports at
run time; no OpenVR import library is needed. Retain the BSD-3-Clause [licence](LICENSE) with
redistribution. Vendored bytes must stay identical to upstream (the root `.gitattributes` disables
third-party newline conversion).

The DLL is pinned in `tools/ci/pins.json` as a shipped download; VR-Q imported it once for the VR part.
Obtain a verified working copy through `python tools/ci/fetch_prebuilt.py --only openvr --out
out/vr/verified` in any task's checkout. It lands at `out/vr/verified/vr/bin/openvr_api.dll`.
The initial downloads under the main checkout's `out/vr/sdk/openvr-2.15.6/` are untrusted data
only; nothing is executed from that quarantine folder.
