# vrprobe (VR-V1-A)

MIT, C++20, Windows x64 console tool, built by `tools/build.ps1 -Config Release` at
`out/build/win64-release/vr/native/probe/vrprobe.exe`. This development tool never ships.

| Source | Responsibility |
|---|---|
| `probe_data.h`, `probe_data.cpp` | Bounded path-file and extension parsing, enabled-runtime-log parsing, comparisons, arguments, JSON output and numerical summaries |
| `discovery.h`, `discovery.cpp` | Read-only SteamVR installation/process discovery, without OpenVR; VR-D can reuse these with `probe_data` and `nl_core` |
| `openvr_session.h`, `openvr_session.cpp` | Shared exclusive VR lock, dynamic SDK exports, client session, headset/device facts and compositor statistics |
| `vulkan_scene.h`, `vulkan_scene.cpp` | Dynamic system Vulkan loader, extension inventory, two clear-colour eye images and reference Submit |
| `main.cpp` | CLI, once-per-second samples, OpenVR event/error log, frame-timing summaries and final JSON |
| `tests.cpp` | CTest offline parser, comparison, argument and statistics regressions |
| `cli_tests.py` | CTest offline executable integration with missing, valid and malformed path files, help, arguments and JSON output |

`NL_VR_VULKAN_INCLUDE_DIR` is a CMake cache path to Vulkan's **include** directory. It defaults to
the read-only runtime clone specified in VR-V1-A. If absent, `extensions`, `submit` and
`idle --submit` report that Vulkan was compiled out, before loading OpenVR; `info`, `idle` and
offline tests remain available. No Vulkan SDK/import library is needed. Both SDKs are SYSTEM
includes; this project's code builds with `/W4 /WX`. Nothing is linked to OpenVR or Vulkan.

```powershell
python tools/ci/fetch_prebuilt.py --only openvr --out out/vr/verified
$probe = 'out/build/win64-release/vr/native/probe/vrprobe.exe'
$dll = 'out/vr/verified/vr/bin/openvr_api.dll'
& $probe info --out out/vr/info.json
& $probe extensions --dll $dll --runtime-log <remix-dxvk.log> --out out/vr/extensions.json
& $probe submit --dll $dll --seconds 30 --pose --out out/vr/submit.json
& $probe idle --dll $dll --minutes 10 --out out/vr/idle.json
& $probe idle --dll $dll --minutes 10 --submit --out out/vr/idle-submit.json
```

JSON goes to stdout or `--out`; stderr receives JSON lines for each event/error and each
measurement second. Durations accept finite positive fractional values up to one day. Unknown,
duplicate, missing or inapplicable options fail (exit 2); operational failures fail (exit 1).
Success exits 0. Compositor errors have individual log records and counters in the result;
an incomplete duration, quit event, wait error or Submit/timing error exits 1 after collecting
the measurements (`completed` and `success` are separate flags). `--help` needs no session.
Data files and output belong under `out/`. File reads are bounded (1 MiB paths, 8 MiB logs).

Every command that initializes OpenVR holds the main checkout's `out/vr/vr.lock` from before
DLL load until after client shutdown and Vulkan cleanup. CMake discovers the main checkout with
`git --git-common-dir`; source archives fall back to their own root. The lock uses exclusive
creation, records task, PID and UTC, waits three seconds on contention, and is deleted by
Windows when its owning handle closes (including process exit). It never removes another
owner's lock. `info` needs no lock and loads no DLL. A scene `VR_InitInternal2` is the dynamic
export behind `VR_Init`; it may start SteamVR. The probe never launches or quits SteamVR itself,
changes its settings, uses a null driver, or changes Steam's registry. A failed init is logged by
numeric code, symbol and description; stop subsequent headset tests after such a failure.

## Reference Vulkan Submit contract for VR-C

Based on [Valve's Vulkan documentation](https://github.com/ValveSoftware/openvr/wiki/Vulkan)
and the pinned header's `VRVulkanTextureData_t` and explicit-timing comments:

- Query the required instance list before instance creation, then the device list for **each**
  enumerated physical device. Enable the complete required list, or report an unsupported name;
  never silently filter it. Use `GetOutputDevice(TextureType_Vulkan, instance)` for the HMD's GPU.
  If requested, query and enable the `timelineSemaphore` feature along with its extension.
- Two optimal-tiled, one-mip, one-layer, single-sample `VK_FORMAT_R8G8B8A8_UNORM` images at the
  current recommended per-eye size. Usage includes `TRANSFER_SRC | SAMPLED`, plus `TRANSFER_DST`
  for the changing clear colours. The submitted bytes use `ColorSpace_Gamma` explicitly.
- Before each clear, transition from `UNDEFINED` on the first frame (otherwise `TRANSFER_SRC`)
  to `TRANSFER_DST`. After clearing, a transfer-write to transfer-read barrier puts it in
  `VK_IMAGE_LAYOUT_TRANSFER_SRC_OPTIMAL`; SteamVR leaves it there. Queue family ownership stays
  on the application's graphics queue. Ordered copies and barriers on that same queue protect
  image reuse. A fence protects the command buffer's reuse; there is no per-frame queue-idle.
- Fill **all** of `VRVulkanTextureData_t`: image, device, physical device, instance, graphics
  queue, its family, dimensions, format, and sample count. Submit each eye once per
  `WaitGetPoses`. `--pose` supplies the returned HMD matrix through `VRTextureWithPose_t` and
  `Submit_TextureWithPose`; default mode supplies an ordinary texture (the larger struct's base).
- Set `Explicit_ApplicationPerformsPostPresentHandoff`. After waiting for poses and building
  commands, call `SubmitExplicitTimingData` immediately before the first application queue
  submission, submit both eyes, and call `PostPresentHandoff` on the rendering thread.
- **Queue exclusion:** Submit, explicit timing, handoff and application queue operations must
  never overlap another thread's use of that queue. The probe has one thread. VR-C must hold
  DXVK's submission lock around these calls as well as its queue work. With the selected explicit
  mode and application handoff, `WaitGetPoses` alone can run outside that queue lock.
- Shut down the **OpenVR client before destroying Vulkan resources** retained by it, then wait
  for the device before freeing them. Shutdown of this client leaves SteamVR itself running.

`GetFrameTiming` is queried each loop and summarized only once per distinct compositor frame
index; unavailable and repeated readings are not new GPU measurements. It measures compositor
reported times, not pass timestamps. `GetCumulativeStats` before and after supplies presents,
drops, reprojections and submits; samples also retain their raw values. Wait-return intervals
and time blocked inside `WaitGetPoses` are separate summaries in milliseconds, with min/mean/max
overall and per measurement second. Connected devices include class, activity enum, validity and
tracking enum. Proximity, desktop visibility and the optional suppressed-display property are
reported separately; `null` means the API did not provide the value. These are not a measurement
of panel luminance. Quit events end only the probe's session.

`extensions --runtime-log` compares with **enabled** blocks, never the log's available-extension
inventory. It takes the last list of each kind (normal DXVK logs may repeat instance creation),
and compares device enablement only for the GPU named by that log. Missing blocks or a different
GPU give `null` enablement. Keep the exact log
beside results to identify the runtime build and GPU being compared.
