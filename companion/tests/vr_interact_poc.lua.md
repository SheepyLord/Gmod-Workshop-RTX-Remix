# vr_interact_poc.lua

Server-only fixture for task P's PoC driver. Injected through ordinary admin console Lua,
not shipped in any add-on. Commands are restricted to the local SP/listen host. Phases spawn
a barrel/can, static blocker, plank, heavy crate, ragdoll, button/health/armour/ammo kits,
melon, supported glove prop, NPC, door and point ladder.
Known positions follow the scripted hands; a world brush ledge is searched for climbing.
The baseline is selected from a verified clear 300x200x150-unit brush volume above ground,
so a long held prop cannot start inside the spawn platform. Ragdolls retain their natural
joint pose under a rigid transform; a death-ragdoll fixture needs only its one squeezed hand.
Records positions, hands/grabs/bones/throws/spin, alignment, health, use, climb and pulses as
NLVR_P JSON. NPC death exercises a server ragdoll; player death exercises release without Exit.

Inputs: host, phase command, actual NLVR_SV state. Outputs: console JSON, owned fixtures/hooks.
nlvr_p_done removes fixtures and probe commands/hooks after Exit. The shared driver restores
the entire PoC snapshot. No file/settings write, SteamVR changes or external contact.
Lua errors fail the shared session acceptance; no process exit code.


Review correction: the deliberate NPC death-ragdoll fixture uses Entity:SetShouldServerRagdoll(true) only on its own NPC. It never changes the player-wide Keep corpses setting.


When W is loaded the bare-hand V2/V3 fixture explicitly selects nlvr_hands; W otherwise preserves the equipped weapon and claims that hand. The dedicated NPC alone requests a server ragdoll with its per-entity API.
