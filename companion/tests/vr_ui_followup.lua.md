# vr_ui_followup.lua

Task M follow-up's 50-second adaptive laser fixture, selected with `vr_ui_poc.py --followup`.
It clicks the stock model-search field, laser-types barrel on the fallback, presses Enter and
records CurrentSearch/result counts. It opens Escape on the actual window picture and measures
Resume only when visible immediately before the posted trigger. Then showconsole prepares the
console via the launcher's acknowledged fixed UI-preparation marker; the flat Aa button requests
text, and the laser keyboard types/runs `echo nlvrmconsoleok`.
The fixture never invokes a field/key DoClick or runs the echo command directly. It snapshots
keyboard, search, Resume before/after and console overlays. In simulation only, ShowKeyboard's
native result is recorded, then an explicit boundary failure selects the fallback; Index uses
its actual native result. Restores wrapped native entry points on Exit. No persistent settings,
network messages, outside-process input or standalone exit code. Outputs `NLVR_Q` records and captures.
Requires S's actual merged central size reservations. Captures also record native OverlayInfo, proving
visibility, bound texture dimensions and simulated versus SteamVR ownership alongside the raw images.
Client Lua cannot run showconsole/hideconsole (blocked commands); the Python wrapper uses only the
existing PoC launcher's own-window console path for those two preparation operations. It verifies
the current lock/PID/path/window and a per-run token. It never runs the acceptance echo command.
