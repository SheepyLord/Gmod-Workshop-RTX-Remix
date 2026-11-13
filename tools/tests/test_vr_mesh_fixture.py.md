# test_vr_mesh_fixture.py

Offline synthetic-source, strict-file-read, authored-bone, no-product-target, beam-label
and regeneration tests. Run `python -B -m unittest discover -s tools/tests -p
test_vr_mesh_fixture.py`. Raw local evidence is optional for the byte-identical
regeneration case; all synthetic contracts run without it. Scratch stays under out/tmp.
No game/OpenVR/network; unittest exit0 means pass, nonzero failure.
