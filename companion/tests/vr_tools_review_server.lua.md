# vr_tools_review_server.lua

Actual shadow parameter observations include dampfactor and physgun_DampingFactor, as
well as angular limits and arrival time. The observer reads these values and writes no convar.

Appended by vr_tools_poc in the base private server fixture's lexical scope for review
or API diagnostics. Admin commands select/spawn owned test props, create an eligible
near-hand Use entity, temporarily refuse crowbar selection, and inject invalid tracking,
controller/creation failure, real death or T Registry Stop. Fault wrappers target only
the owned prop/controller and restore after one call/cleanup. Observes native held state
before/after/0.3 s later, gravity/COM/velocities, switch attempts and Use calls. The API
diagnostic separately calls Player:DropObject/Entity:ForcePlayerDrop. Only the refusal
hook intentionally returns true while armed; production hooks are unchanged. Done restores
wrappers and removes owned entity/hooks/commands. No independent process exit or external IO.
