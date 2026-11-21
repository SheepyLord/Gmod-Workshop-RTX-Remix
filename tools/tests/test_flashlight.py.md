# test_flashlight.py

Runs [flashlight_harness.lua](flashlight_harness.lua.md) with local LuaJIT against the packaged RTX
fixes flashlight Lua in `packages/fixes` (`sv_remix_flashlight.lua`, `cl_remix_flashlight.lua`):
the R19 toggle cooldown, coalesced colours and gamemode rule on the server, and one Remix light per
player on the client ([ADR 0112](../../docs/decisions/0112-fixes-lua-apis-stay-in-the-game-and-follow-the-player.md));
and the client's automatic brightness, on by default: fast dimming, gentle brightening up to Max Boost, the haze
kept at its level, the player's car left out, the fixed brightness when off, other players' lights measured ten
times a second, the menu and Reset ([ADR 0208](../../docs/decisions/0208-the-rtx-flashlights-automatic-brightness.md));
and a light another add-on keeps dark through `RTXFlashlightHidden` (`test_client_light_kept_dark_by_another_addon`:
the motion importer's camera motion leaving you out of the shot): dark and not measured while hidden, still on,
others' lights lit, back as it was ([ADR 0250](../../docs/decisions/0250-hide-yourself-during-camera-motion.md)).

`python -I -m pytest tools\tests\test_flashlight.py -q`. Reads only repository files; no game or
network. A missing LuaJIT is a reported skip; a failed harness assertion fails the test.
