# shadow_copies_server.lua

The server half of [shadow_copies_session.py](shadow_copies_session.py.md), run once in the PoC game from the
session's data folder (`lua_run RunString(file.Read("nlshadow/server.txt","DATA"),"nlshadow_server")`).

- **Entities without a model scale.** It wraps `GetModelScale` in the `Entity` metatable: every caller asks through
  it, the Model Hotloader's scene capture (`secondary_collision.lua`) included, so the first time an entity class and
  model answer nothing it records the class, model, entity index, time and the caller's traceback and prints
  `NLSH_NILSCALE <class> <model>`. Every two seconds it also scans `ents.GetAll()` for entities with a model and no
  model scale, whoever asks, keeping each class and model's first time and the most seen at once.
- **`nlshadow_character`**: the PoC library's first imported character (`data\mmd_hotloader\assets`) as an NPC
  (`mmdhl.SpawnNPC`, a citizen without a weapon) 140 units in front of the player, facing them, with
  `ai_disabled 1`. Prints `NLSH_CHARACTER <class or error>`.
- **`nlshadow_weapon <class>`**: gives the player that weapon if they lack it and selects it (a class of letters,
  digits and underscores). Prints `NLSH_WEAPON <class>`.
- **`nlshadow_player_model`**: the same character as the player's own model (`mmdhl.Spawn`, role `player`). Prints
  `NLSH_PLAYER_MODEL <model or error>`.
- **`nlshadow_server_report`**: scans once more and writes `data\nlshadow\server.json` (`asked`, `present`). Prints
  `NLSH_SERVER_REPORT`.

The commands answer only the single-player game's host (or a listen server's). **Prints:** `NLSH_SERVER_READY` once
loaded. **Writes:** `data\nlshadow\server.json` in the PoC's data folder.
