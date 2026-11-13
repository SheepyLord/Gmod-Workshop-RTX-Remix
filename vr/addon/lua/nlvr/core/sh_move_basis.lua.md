# sh_move_basis.lua

Shared active-VR movement basis. Intent stamps ladder buttons from the original command before gun-angle encoding. Apply preserves those buttons, reconstructs world intent, and re-expresses it for Source movement. Water uses a horizontal movement basis plus world up. Ladders preserve the head pitch/yaw basis: normal Source head-directed forward/back climbing, independent of the gun. No late head-sync projection may invent a digital side command. Client/server calls match; no hooks on include, no file/setting side effects. Used by Core CreateMove/SetupMove; tests cover yaw jitter, small inputs and armed parity.

Ladder direction buttons use8-way22.5degree sectors from original stick intent, before tool commands. Non-ladder/vehicle buttons are untouched. Noclip bypasses water/ladder SetupMove adaptation.
