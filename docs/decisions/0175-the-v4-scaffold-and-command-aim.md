# 0175: The V4 scaffold and command aim

Accepted for implementation on the V4 task branches, 2026-11-11; milestone approval/merge remains with the user.

The [V4 plan](../handover/VR-V4-plan.md) assigns weapons, reloading and tools to separate tasks. They need fixed composition slots, disjoint message ranges, render-target dimensions and shared settings before their implementations can run in parallel.

## Decision

The client composes weapons (44), reload (46) and tools (48) after UI (40) and before interaction (50). Their server descriptors have the same names/orders. Initially each Start/Stop is empty. Files reach the package-owning SP/listen host through the same locally deployed nlvr add-on as F's files; no remote distribution or dormant server autorun is added.

The one-byte protocol accepts integral module types 16..127: hands 16..23, movement 24..31, UI 32..39, interaction 40..63, weapons 64..79, reload 80..95, tools 96..111; 112..127 are unassigned. Both realms use ModuleType for handlers/senders; the server also validates incoming dispatch. The 1467-bit pose sync, rate/reach limits and local-host gate remain unchanged.

All overlay sizes live in NLVR.Overlay.Sizes. In addition to F's sizes: wheel 1035x1037, tool 643x133, M's settings 1283x963 and flat_close 131x133, and keyboard 1039x391 reserved for M's fallback. Each pair stays unique and both dimensions odd; the reserved key and live duplicate checks apply.

The page declares archived nl_vr_physical_reload, nl_vr_foregrip and nl_vr_ammo_counter (default 1, range 0..1) and nl_vr_gun_angle (default 0, -45..45 degrees). Its Weapons group has three check boxes and a slider, each with help. Core reads/normalizes settings at Start and on change, removes callbacks at Exit and never writes them. Catalog generation uses explicit UTF-8 and ASCII-escaped source for all six translations.

Control ownership follows the binding V4 table:

| Control | Owner and action |
|---|---|
| Main trigger / grip | W while armed: attack / prevent grabbing. UI may claim the trigger first. |
| Main A | W: attack2 held. K claims ejectable physical magazines: tap ejects, hold >=0.3 seconds attack2. |
| Main B | K tap: one-tick reload unless physical reload applies. T hold >=0.3 seconds: weapon wheel. |
| Main stick | T while physgun holds: push/pull; otherwise L. |
| Off grip | W at foregrip; K over shoulder/holding ammo; otherwise P. |
| Off trigger | W at foregrip: attack2; otherwise UI/P. |

Claims run in frame events before command movers, first owner wins; command buttons implement attacks, with no +attack console commands.

The head-derived command copies pitch/yaw and clears roll while the tracked camera retains roll. If NLVR.Aim replaces the command's final yaw after movers, forward and side are rebased from that yaw to the aim yaw, preserving world direction and length. Source positive side is right (-Y at yaw zero): with delta = newYaw-oldYaw, f' = f*cos(delta)-s*sin(delta), s' = s*cos(delta)+f*sin(delta). Up movement is unchanged. This uses the yaw actually left by movers, including L's adjustments, and leaves feet prediction untouched.

## Consequences

W/K/T replace only their own slots. Independent harness fixtures expose engine weapon/inventory/command/model contracts without simulating firing or prediction. The tools-only Release gate loads H/L/M and S, and prepares explicit named bridges for P/W/K/T; absent future suites are named skips, present empty/broken suites fail. Integration must replace those pending skips with feature counts.
