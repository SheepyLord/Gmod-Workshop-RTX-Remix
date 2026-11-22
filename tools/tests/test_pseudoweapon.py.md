# test_pseudoweapon.py

Runs [pseudoweapon_harness.lua](pseudoweapon_harness.lua.md) under LuaJIT against the shipped
`packages/fixes/garrysmod/garrysmod/addons/remixbinary/lua/entities/rtx_pseudoweapon.lua`, without starting Garry's Mod
([ADR 0251](../../docs/decisions/0251-the-weapon-copy-draws-nothing-before-the-frame.md),
[ADR 0252](../../docs/decisions/0252-the-weapon-copy-draws-only-with-its-private-textures.md)).

```powershell
python -I -m unittest discover -s tools/tests -p test_pseudoweapon.py    # from the repository root
```

| Test | Checks |
|---|---|
| `test_a_lua_weapon_in_first_person` | With a scripted weapon (the tool gun) in hand, in first person, the weapon copy's `Think` calls no `DrawWorldModel`, draws no model and sets up the player's and the weapon's bones each time |
| `test_a_lua_weapon_in_third_person` | The same in third person, the view in which the draw before the frame left the whole frame without path tracing |
| `test_an_engine_weapon` | An engine weapon (no `DrawWorldModel`) in both views: nothing drawn, the bones set up |
| `test_the_copy_draws_only_with_its_private_textures` | With the legacy `rtx_pseudoweapon_unique_hashes 0`, the copy's first draw makes its private textures and draws with them, puts the material overrides back, registers the materials as the player model's once their hashes are known; a weapon change makes new textures at the next draw, never in `Think` |

Before the fix of 2026-11-21 the two Lua-weapon tests failed (`DrawWorldModel` called on every `Think`) and the engine
weapon's failed for the bones; with only ADR 0251's change the private-texture test failed (no private texture with
the legacy setting).

LuaJIT is optional: without it (CI) the tests are skipped. Writes nothing. Exit code 0 on success.
