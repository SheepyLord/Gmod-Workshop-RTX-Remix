# pseudoweapon_harness.lua

A LuaJIT harness for the RTX fixes' weapon copy, `lua/entities/rtx_pseudoweapon.lua` in the fixes part
([ADR 0251](../../docs/decisions/0251-the-weapon-copy-draws-nothing-before-the-frame.md)), run by
[test_pseudoweapon.py](test_pseudoweapon.py.md).

```powershell
luajit tools\tests\pseudoweapon_harness.lua <scenario> packages\fixes\garrysmod\garrysmod\addons\remixbinary\lua\entities\rtx_pseudoweapon.lua
```

It reads the file and turns GMod's C-style `!=` and `!` into Lua's `~=` and `not` (LuaJIT knows neither), stubs the
parts of the game's API the entity uses (`ENT`, `LocalPlayer`, `GetConVar` with `rtx_pseudoweapon` 1 and
`rtx_pseudoweapon_unique_hashes` 0, `ClientsideModel`, `hook`, `file.Exists`, `util.CRC`, `Color`, the enums), loads the
file, creates the entity (`Initialize`) and runs its `Think` three times. The held weapon is the tool gun; in the
`_lua` scenarios it has `DrawWorldModel` (a scripted weapon), in the `_engine` ones it has none (an engine weapon).

Scenarios: `first_lua`, `third_lua`, `first_engine`, `third_engine` (first or third person: `ShouldDrawLocalPlayer`).
Each checks that `Think` called no `DrawWorldModel` and drew no model, and that it set up the player's and the weapon's
bones on every call. Prints `PASS <scenario>`; a failed check raises `FAIL <scenario>: <why>` (exit code 1). Writes no
file.
