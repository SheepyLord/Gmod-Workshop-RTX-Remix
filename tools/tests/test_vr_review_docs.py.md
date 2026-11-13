# test_vr_review_docs.py

Checks one short VR status outside AGENTS' repo map and verifies that the shared decision
index preserves every main line, adding only matching table rows. Main comparison skips
only when the ref is unavailable in a shallow checkout. Run with unittest discovery or
the Release gate. Reads repository docs/Git only; no writes/native/game/network. Exit is
unittest's pass/failure status.

The baseline is merge-base(main,HEAD), not live main. A simulated unmerged main decision must not affect preservation checks.
