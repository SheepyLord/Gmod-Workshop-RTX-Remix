# v2_probe.lua

Test-only native feature probe, appended after the ordinary session probe by N's disposable
launcher under out. Do not install as an add-on. It observes the same named timeline and calls
ShowKeyboard at 7 s, HideKeyboard at 9.5 s and OpenBindingUI at 10 s. The supplied timeline emits
the text `V2 native keyboard` at 8.5 s and keyboard_closed at 9 s; the native worker closes the
owned real keyboard too. The probe observes Events without consuming them away from the page.

Creates an owned textureless overlay to test tint, sort and optional window binding; records
Info's actual eye matrices and all return values as NLVR_N_FEATURES JSON bounded below 3000 bytes
(the large status/timing tables are deliberately excluded), destroys the overlay,
then restores Events/removes its own hook at native off. No setting or binding is edited; SteamVR
is left running. No file or DLL path reaches Lua. The launcher validates both the normal VR
acceptance and this record. No standalone exit code; exceptions appear in the session's Lua log.
