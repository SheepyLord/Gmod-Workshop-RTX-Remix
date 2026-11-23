# queue_stale_client.lua

The client Lua of the engine guard's `stale` and `stale-net` PoC runs
([`queue_check_session.py`](queue_check_session.py.md), ADR 0261). It does at `ShutDown` what the companion's hooks do
to imported characters' materials (`SetTexture("$basetexture")`, `SetInt("$flags")`, `SetInt("$allowalphatocoverage")`,
`Recompute()`), on materials it makes with `CreateMaterial` and on five file-based materials only it refers to. In
queued rendering each setter waits in the list the main thread records, holding its material variable; the RTX fixes'
map-exit cleanup (`RTXTextureCleanup_MapExit`, `UncacheAllMaterials`) then destroys every file-based material's
variables. Before ADR 0261 the game crashed after this 4 of 4 times (exit 0xC0000409). A `stale` run must not crash
because the fixes' hook runs the queued calls first; a `stale-net` run (the flush switched off with
`-nl_queue_check_no_flush`) must not crash because the run check skips the calls whose variable is gone.

Client realm. The driver passes it to [`poc_session.py`](../poc_session.py.md) `run --lua`, which runs it through the
console once the run's second map (after the level change) is up. So it exercises the final `disconnect` that ends
the run, not the level change.

## What it does

- Makes 24 materials with `CreateMaterial("nlqueue_stale_<n>", "VertexLitGeneric", ...)` and looks up five stock
  file-based materials (`models/props_c17/metalladder001`, `models/props_junk/ravenholmsign_sheet`,
  `models/props_wasteland/wood_fence01a`, `models/props_lab/cornerunit_cloud`, `models/gibs/metalgibs/metal_gibs`),
  keeping those that exist.
- The order of `ShutDown` hooks is not guaranteed, so it makes the hazardous order certain: it wraps the RTX fixes' own
  hook function (`hook.GetTable().ShutDown["RTXTextureCleanup_MapExit"]`, re-added under the same name), so its setters
  are queued right before that hook's body runs. Each setter round sets a texture, two integers and recomputes each
  material, then prints `[nlqueue] stale: queued restores for <n> materials at ShutDown`.
- Prints `[nlqueue] stale: armed with 24 made and <n> disk materials, right before the RTX fixes' cleanup hook`. When
  the fixes' hook is not there it adds a `ShutDown` hook of its own (`nlqueue_stale`) and prints
  `[nlqueue] stale: armed with ... disk materials; the RTX fixes' cleanup hook is not there, so in a ShutDown hook of its own`.

## Inputs, outputs, side effects

No inputs. Prints to the game's console. Changes only the running game's materials and `ShutDown` hooks in memory (the
disconnect ends the client state that holds them). Nothing is written to disk.
