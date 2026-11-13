# vr_interact_poc_client.lua

Client probe appended to the stock VR session probe by vr_interact_poc.py. Reads the native
test timeline clock to select server fixture phases; requests an extra gloves capture and
both eyes/centre/mirror/overlay captures for each interaction phase, and
the server cleanup receipt after Exit. Uses a temporary PreRender hook removed after one cycle.
Inputs: test session only; output: ordinary server console commands and capture request.
No production file changes, archive writes or physics authority. Shared driver collects Lua
errors and restores the PoC. No process exit code.
Phase commands retry until the owned server acknowledges them, including a late first frame.
The acknowledgement global is removed after Exit. This changes no production network message.
