# queue_midgame_client.lua

The client Lua of the `midgame` and `midgame-console` PoC runs
([`queue_check_session.py`](queue_check_session.py.md), ADR 0262). It sets variables of file-based materials and has
the RTX fixes' texture cleanup run in the same frame, in the middle of a game. In queued rendering each setter waits in
the list the main thread records, holding its material variable, and the render thread runs that list at the end of
the frame. The cleanup (`PerformTextureCleanup` in the fixes' native module) uncaches every material, which destroys
every file-based material's variables. Before ADR 0262 the render thread then ran the setters on freed memory and the
game closed with exit 0xC0000005; since ADR 0262 the cleanup has the engine guard run the queued calls first, so a run
must not crash and its console must show the cleanup's `Ran <n> queued render calls before the purge` and `Source
material cache fully uncached` lines after the setters.

Client realm. The driver writes a copy of it per run with `NLQ_MODE = "lua"` or `NLQ_MODE = "console"` as its first
line and passes that copy to [`poc_session.py`](../poc_session.py.md) `run --lua`, which runs it through the console
once the run's second map is up.

## What it does

- Looks up five stock file-based materials (`models/props_c17/metalladder001`, `models/props_junk/ravenholmsign_sheet`,
  `models/props_wasteland/wood_fence01a`, `models/props_lab/cornerunit_cloud`, `models/gibs/metalgibs/metal_gibs`),
  keeping those that exist, and the base texture of `models/shiny`.
- Defines the Lua console command `nlqueue_touch` in both modes: it sets each material's `$basetexture` to that texture
  and adds 256 to its `$flags`, then prints
  `[nlqueue] midgame: queued setters for <n> file-based materials (<c> calls)`, `<c>` the setter calls it made (two
  for each material). The driver wants the cleanup's `Ran <n>` line to count at least `<c>` calls (each texture setter
  queues two, the setter and its texture's release). A Lua
  console command runs when the command buffer reaches it, so `nlqueue_touch;rtx_flush_textures` queues the setters
  and runs the console command's cleanup in one pass (`lua_run_cl` would run its code later, after the cleanup).
- Prints `[nlqueue] midgame: armed (<mode>) with <n> disk materials`.
- Mode `lua` (the default when `NLQ_MODE` is not set): three seconds later a timer sets the variables and, in the same
  chunk, calls `RTX_CleanupMapTextures()` under `pcall`, then prints
  `[nlqueue] midgame: RTX_CleanupMapTextures returned <ok> <result>`. Mode `console`: nothing runs by itself; the driver
  sends the console line.

## Inputs, outputs, side effects

Input: the global `NLQ_MODE` (`"lua"` or `"console"`). Prints to the game's console. Changes only the running game's
materials in memory and adds one console command and, in mode `lua`, one timer; the cleanup it starts releases
cached materials and textures, which the game loads again when it next draws them. Nothing is written to disk.
