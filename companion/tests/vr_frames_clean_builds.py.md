# vr_frames_clean_builds.py

C-only cleanup of superseded development GMAs, as the user requested for limited H: space.

`python companion/tests/vr_frames_clean_builds.py --evidence out/vr/v4c/combined-02 --versions 1 2 3 4`

Plans only. Add `--execute` to remove exactly the verified files. Requires branch v4c, a newer C production GMA named by a successful PoC source receipt, clean restoration, and matching version, size and SHA-256 in every build receipt (the witness too). Restricts paths to this worktree's out/dist, rejects links/reparse files, accepts only strictly older numbered C builds, rechecks hashes immediately before each unlink, and never recurses. Edited or foreign outputs stop cleanup. Retains every JSON summary and all game evidence; writes clean-builds-plan/executed.json under out/vr/v4c. No game, SteamVR, other worktree, user data or publication side effects. Exit 0 succeeds; a failed guard raises and exits nonzero.

--fixture-bulk sim-02 sim-03 retires only indexed payload files over 1 MiB in those two superseded C diagnostic copies. Both original sessions must have successful production receipts and clean restoration, recorded package paths must match, and every selected plain-file size/SHA-256 must match its manifest. It never recurses; metadata, source-model receipts, text and all pictures remain. The retired diagnostic copies are deliberately no longer installable. Separate plan/execution receipts list the files.

Plan/execution receipt filenames include their selected versions or fixture names, retaining separate cleanup histories.
