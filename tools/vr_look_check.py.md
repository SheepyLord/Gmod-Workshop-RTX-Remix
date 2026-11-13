# vr_look_check.py

Runs the actual vr_session --look path in a newly created standard-library-only venv, with
neither Pillow nor pip. `python tools/vr_look_check.py --package out/dist/candidate.gma --evidence
out/vr/v2q/new-look --venv out/vr/v2q/new-empty-venv`. Refuses an existing venv and installs no
package. Both paths stay below out. The child checks actual import availability, then uses the
normal real SteamVR/PoC locks, snapshot, launch, menu page, live poses, settings and rollback.

A private fixture invokes the ordinary nl_vr_start command (as a user would), observes five
seconds of real compositor progress, requests native eye/centre/depth/overlay/mirror captures,
then invokes nl_vr_demo_done after seven seconds. No desktop screenshot/PIL import occurs.
Counter errors, refused Start, missing proof/captures, teardown or restoration failure fail the
test. This checks the running public path, not only an import/preflight mock. Internal --child
starts the package-free interpreter phase. Output includes no-pillow-look.json, exact interpreter
and import facts, native proof/captures and all normal driver receipts. Exit 0 only for a complete
pass, otherwise nonzero. Uses the authorised field-game normal quit only if needed and records
it; never changes SteamVR settings/processes or writes a depot/user.conf/loader source.
