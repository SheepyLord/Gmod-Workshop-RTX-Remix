# vr_tools_review_check.py

Read-only additional assertions for the review case. Requires a real off-centre gravity
prop, held-stick ownership with no teleport/crouch/turn handoff, an eligible Use entity
untouched until a new trigger press, native ForcePlayerDrop and sustained non-reacquisition
for tracking/hand/controller/creation/Stop, actual death drop, native parameter equality
to server convars (including physgun_DampingFactor; missing factor evidence fails),
speed-key snap/release, one refused switch plus visible notice, and both
peer beam hooks. Returns checks/measurements; no IO/process/game calls or standalone exit.
