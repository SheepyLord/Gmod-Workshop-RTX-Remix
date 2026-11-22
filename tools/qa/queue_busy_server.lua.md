# queue_busy_server.lua

A busy single-player map for the engine guard's PoC series
([`queue_check_session.py`](queue_check_session.py.md),
[ADR 0247](../../docs/decisions/0247-queued-render-calls-checked-before-the-game-leaves-threaded-rendering.md),
[ADR 0254](../../docs/decisions/0254-queued-render-calls-checked-again-while-the-game-runs-them.md)). The field's
crashes at `disconnect` came after long sessions "with lots of things spawned"; a busy run tries to end such a
session in the PoC.

Server realm, single-player. The driver copies it to the PoC's `garrysmod/data/nlqueue/busy.txt` and runs it after
the map loads with `lua_run RunString(file.Read("nlqueue/busy.txt","DATA"),"nlqueue_busy")`.

## What it does

- Makes the player invulnerable (`GodEnable`) and spawns around them 250 physics props (stock HL2 models), 40 ragdolls
  and 12 armed citizens facing 12 armed Combine soldiers, which fight.
- Every second (timer `nlqueue_busy`): three explosions (magnitude 60), a spread of 12 bullets from the player's eyes
  (impact decals on the world, the props and the bodies), a blood decal traced at each ragdoll, five more props and
  now and then another ragdoll.
- Every 30 seconds (timer `nlqueue_busy_report`) prints `[nlqueue] busy: <props>, <ragdolls>, <NPCs>,
  <explosions>, <entities>` to the console; `[nlqueue] busy: started` once.

## Inputs, outputs, side effects

No inputs. Prints to the game's console. Changes only the running map (the level change or the disconnect that follows
ends it). Nothing is written to disk.
