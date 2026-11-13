# cl_input.lua: Logical input and claims

New() returns left/right physical controls, main/off aliases, mainHand/offHand names, Mapping and Buttons data, Update(actions,realTime,leftDominant), Mirror(leftDominant), Resolve(hand), Claim(hand,control,owner), Owner, Tapped and Held. A hand argument is left/right/main/off or a current hand table. Update reads native named action records once per frame, clamps axes, generates edges and held seconds, resets claims, and maps skeletal curls/splay. Inactive/missing actions release controls. A release at most 0.3 seconds after press is a tap; Held requires the button still down. First owner wins for the frame; the same owner can claim again. Consumers act only when Owner is nil or their own name. No engine hooks or mutations.

Inputs are the session/context arguments described above. Outputs are returned Lua tables and active-session state only. Errors propagate to the owning session or harness; there is no process exit code for production Lua.
