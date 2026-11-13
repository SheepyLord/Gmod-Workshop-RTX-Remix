# sh_tools_math.lua

Use-modifier information is excluded from ordinary Trigger/A/B mappings because T supplies
no Use chord for the toolgun. Snap quantises the desired world angle to the player's
gm_snapangles step, clamped to the native UI's 5..90-degree range with 45 fallback.

Pure rules shared with offline tests, no registration or side effects on include. Returns
rigid hand-relative rotation/error, sorted/deduplicated inventory, 12-entry pages/picking
(3 cm dead zone), rearmed vertical paging, time-weighted native distance-key duty and
translated tool information signatures. Gesture distances metres, angles degrees; command
time is game seconds. Invalid stick/pick numbers are refused. No files/network/hooks,
native initialization or process exit code. Used by cl_tools, sv_tools and vr_tools_test.py.
Inventory sorting uses a strict comparison even when the sort compares an entry to itself;
large inventories keep exactly one Hands entry at the front.
