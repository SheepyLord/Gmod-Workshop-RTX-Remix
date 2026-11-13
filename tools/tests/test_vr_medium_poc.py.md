# test_vr_medium_poc.py

Offline observer mutations reject fake media, side buttons/drift, wrong gun pose,
gun-steered water, changed armed speed or missing cases. Generated client/server Lua
compiles under LuaJIT; source contracts forbid forcing ladder type or creating/removing
targets. Run unittest discovery/the Release gate. Uses only generated out/tmp scratch;
no game/OpenVR/network. Exit0 pass, nonzero failure.

Also tests --help from a fresh subprocess without unittest sys.path and nested preference-directory creation.


A retained315/-45 equivalence regression rejects incorrect linear angle comparison. Synthetic ladder movement follows head pitch.


Also rejects a wrong rendered barrel when the eye command agrees; equivalent wrapped barrel angles pass.


Synthetic observer tests cover frozen-sample rejection and rendered-barrel versus eye-command distinction.

Round5:33 cases retain the original15 and add6 five-degree ladder trials,6 underwater noclip idle/throttle trials and6 land noclip controls. Head and off-hand directions plus actual stick components are recorded. The same5mm hold,1degree barrel,3degree water-velocity, .2degree wish and .1unit lateral bounds are retained. No old261104 depot pins are passed; current PoC261112 verifies against field manifests. Both locks and normal driver-owned field quit remain mandatory.
