# test_companion_vr.py

Discovery adapter only: tools/test.ps1 searches tests below tools, so this imports VRTests and VRCatalogTests
from [test_vr.py](../../companion/tests/test_vr.py.md). Run the normal gate or `python -m unittest discover -s
tools/tests -p test_companion_vr.py -v`. No game/network/native VR use; LuaJIT absence skips the Lua cases while
the catalog byte case still runs. Exit status is unittest's. This adapter is required to put VR-E's new tests in
the gate; it changes no build/packaging.


Q4 also imports VRULibTests, the complete core suite including movement/settings/lifecycle cases, not just view ownership. The repository gate runs both libraries.
