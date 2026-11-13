# test_vr_manifest_pins.py

Offline explicit-stock-manifest tests. A pinned copy must use its declared revision
instead of a separately updated field install; missing pins fail closed. Only synthetic
manifest objects are used, with no Steam/game/registry mutation. Run normal unittest
discovery or Release gate; exit0 pass, nonzero failure.

Round5 retains a mismatch-before-mutation test: wrong explicit stock manifests fail before registry access, snapshot creation or install changes.
