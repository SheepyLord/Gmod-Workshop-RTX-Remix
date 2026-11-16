# editors_harness.lua

LuaJIT harness invoked by [test_editors.py](test_editors.py.md), one scenario per run:

```powershell
luajit tools\tests\editors_harness.lua <scenario> <!advanced_material_editor> <!advanced_bodygroup_tool> <bullet_break_simulator folder>
```

The last three arguments are the add-on folders (for Procedural Bodygroup Destruction, its
`lua/bullet_break_simulator` folder). Scenarios: `adv_snapshot`, `adv_hello`, `adv_entity_owner`, `abt_dupe`,
`abt_actions`, `abt_cache`, `bbs_denied`, `getbool`. Each loads the shipped files it tests (`sh_20_net.lua` and
`sv_30_store.lua`, with `sh_00_config.lua` for `adv_entity_owner`; `sv_31_rtx_store.lua`; the bodygroup tool's
autorun file and stool; `cl_uv_hide.lua`; `sv_20_hits.lua`; for `getbool`, the helpers cut out of their files) with
stand-ins for the game's libraries: hooks, timers fired on demand, a clock the scenario advances, convars, net
messages recorded and delivered, entities, players and counting `util.TableToJSON`/`util.Compress`.

`adv_entity_owner` (review finding 23, 2026-11-16) sets `advmat_adminonly 0` and a prop-protection stand-in on
`CanTool` (a player may use a tool on what they own, an admin on anything), then sends saves and clears through the
real `AdvMat.RuleSet`/`AdvMat.RuleClear` receivers: a player restyles their own prop (and `CanTool` is asked about it,
for the `advmateditor` mode) and their own model; another player's prop and another player are refused with the
translated "not allowed" notice and nothing stored; an admin restyles both; a model rule is saved as before; a target
that is gone keeps its own reason. The tool's paste (`Store.Set` with the player) follows the same rule, the server's
own `Store.Clear` still clears any entity, and with `advmat_adminonly 1` a player is refused first while an admin
saves.

It writes no files and touches no network. Prints `PASS <scenario>` and exits 0, or fails an assertion
with a message and exits 1.
