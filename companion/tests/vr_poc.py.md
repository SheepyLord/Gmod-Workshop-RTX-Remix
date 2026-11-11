# vr_poc.py

Explicit real-game review driver; never part of automatic unittest discovery or shipping inputs.

```powershell
python companion/tests/vr_poc.py --tag r1
python companion/tests/vr_poc.py --tag r2 --players 1
python companion/tests/vr_poc.py --build-only
python companion/tests/vr_poc.py --tag review-r3 --evaluate-only
```

Builds a console-injectable client script from the current shipping page/add-on, [vr_standin.lua](vr_standin.lua.md)
and [vr_poc.lua](vr_poc.lua.md), recording source hashes. Scratch is in this worktree's out/vr/e/review; evidence
defaults to the main checkout's out/vr/e/review (`--evidence` overrides it). --players selects SP, listen host or both.
Use a fresh --tag for each attempt so snapshots/records are not overwritten.

Takes the main PoC lock by exclusive creation, waits without stealing another task's lock, checks for remaining
PoC processes, snapshots with field_snapshot.py, runs poc_session.py --lua for the chosen modes, then rolls back
and releases only its own lock. No OpenVR is initialized, so no VR lock is needed. SteamVR/Steam settings and the
field install are not modified. Uses the existing PoC package; changes no packaging or loader configuration.
No large-copy deletion is attempted by this driver.

The game's temporary fixture sets health 87/armour 31 and requests a pistol with clip 12/reserve 36, ensures its existing
body/weapon proxies are enabled, and sets fps_max 60 on the **launch command line**, not from addon Lua. Client
API probes restore allowed changes before Start; the production addon leaves all engine convars unchanged.
The normal driver restores shared settings before quit and snapshot rollback restores the PoC/Source registry.
The probe selects the pistol through CreateMove and captures the real values after selection (the observed
18/256 is not replaced by the requested fixture numbers).

Decodes console-only base64 PNG/JSON exports into out/, validates all seven screenshots/acknowledgements,
camera/cleanup results and a nonblank 769x257 wrist PNG, and writes per-session summaries. The real shutdown is
the game's normal quit after the final active session. No game evidence files or native module are written.
The intentionally blocked fps_max probe emits one client error in SP and two copies of that same error on a
listen host (client plus server forwarding); other Lua errors fail validation. Saved runs can be validated with
--evaluate-only (or validate(folder, session_record)) without launching another game, acquiring a lock or
overwriting the recorded source hashes.
Exit 0 means the requested modes and rollback passed; subprocess/validation failures are nonzero and still
attempt rollback/release. Requirements: Windows, installed PoC/package, Python/Pillow, local Release nlctl for
the existing snapshot rollback. Use the report for measured results and expected blocked-command diagnostics.
