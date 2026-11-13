# vr_frames_weapons_poc.py

Run W's actual combined weapon/physics PoC driver with C's corrected controller frames. Example:

`python companion/tests/vr_frames_weapons_poc.py --package out/dist/package.gma --evidence out/vr/v4c/combined --simulate --seconds 38 --weapons-phases pistol-5,fore-smg,wall,frag-throw,hands`

Every W palm trajectory is converted to a nonidentity raw controller trajectory by inverting the recorded Index tip and palm components. Desired hand/head poses, buttons, server fixture, native bullets, P's grab/throw checks, shared locks, production rollback and W's analysis remain the real ones. No SteamVR-install read or production code override. Normal W flags pass through. Outputs W/production receipts, pictures and checks under the selected out directory; exit codes and dependencies are W's. C's palm-aware wrist comparison preserves legacy W receipt behavior.

Independent review round: live hooks use the shared dispatcher and detached compatibility snapshots; geometry witnesses use raw posed-mesh/hand-bone data with rejecting placement/skew mutants. Full destructive acceptance stays gated pending Claude's fixes repair. See VR-V4-Q-resume.md for exact test/evidence scope.
