---
name: workshop-content-pack
description: Build, check, upload and update a native-loader content pack on the Steam Workshop - one hidden item holding a Model Hotloader character package (mmdhl_<name>) with its rpai PBR mod (pbr_<name>), package id <name>-rtx, or a remastered map's Lua add-on and Remix mod - that the GMod native loader deploys for players who subscribe. Covers the naming rule (the character's own name only), live hashes, hotloader_export.py or the offline mmdhl_pack.py, staging referenced DDS, package_content.py, nlctl, check_pack.py, a PoC check, the icon, the description with Required items, gmpublish create (hidden) and update -id, and post-upload checks. Use it whenever a character, model or map with its PBR is to be packed, uploaded or updated on the Workshop, or for gmpublish, hidden items, Required items, a Model Hotloader package, a pack's deployment, or items 3829348717, 3829892354, 3830769477. Not for the RTX package itself (item 3829070317, published by tools/publish_workshop.py).
---

# Workshop content packs for Garry's Mod RTX

A **pack** is one Workshop item holding a native-loader package with content only
(`docs/PACKAGE_FORMAT.md` in the repository `H:\BACKUP_20260815\Modding\!NVIDIA-RTX-Remix`): a Model
Hotloader package add-on and a Remix mod for a character, or a Lua add-on and a Remix mod for a
remastered map. GMod cannot mount such an item. The native loader deploys it at start-up, **only for a
player who subscribed to it** (loader 0.14.0 or later, ADR 0111; 0.4.0-0.13.x took any installed
item), and it relies on the RTX package (3829070317) for the Remix runtime and Model Hotloader.

Items made this way (all hidden; dates UTC):

| Item | Package id | Holds | Last upload | Open |
|---|---|---|---|---|
| 3829348717 | `guinaifen-rtx` | Guinaifen: Model Hotloader package + 18 PBR materials, 44 DDS (about 696 MB) | `0.0.0-dev.202611010517+7ccac1bb`, 2026-11-02 (C-16 adaptive eye emission) | display name `Guinaifen (桂乃芬)` kept by the user (2026-11-01): updates pass `check_pack.py --keep-name 1c2ed2fc` |
| 3829347093 | `guinaifen-rtx` | the first build of the same pack | 2026-10-29 | a hidden duplicate: never delete it, never subscribe to it |
| 3829892354 | `robin-rtx` | Robin: preset `Default`, name `Robin`, 17 materials, 30 DDS (about 453 MB) | `0.0.0-dev.202611010515+3a6d9e61`, 2026-11-01 (C-16) | the Workshop page title is still the creation's `Robin R18 RTX (native loader package)`: only the owner can rename it on the page (to `Robin (Model Hotloader + RTX PBR)` by the naming rule) |
| 3830769477 | `evernight-march7th-rtx` | Evernight and March 7th: two models, two layers (about 1.22 GB) | `0.0.0-dev.202611010518+103fde9b`, 2026-11-01 (C-16) | display names `Evernight` and `March 7th` with both terms records since the R5 rebuild (uploaded 2026-10-31 22:13 UTC); Evernight's terms forbid redistribution: stays hidden |

Related: 3829275998 Modern House RTX (a map remaster, ADR 0023), 3829070317 the RTX package. The
last builds are in the main checkout's `out\packages\guinaifen`, `out\packages\robin` and
`out\packages\evernight-march7th` (each with a `pre-c16` copy of the earlier archive and layers).

## Rules (the user's)

- **Workshop work means no repository edits.** Build under the main checkout's git-ignored
  `out\packages\<n>\`; `git -C <repo> status --short` stays as it was. Never import a pack into
  `packages\` (that is the RTX package's input, published to 3829070317 by the repository's hooks),
  never commit a `.gma`, never start GitHub's package workflow (`package.yml`: the RTX package's
  release build, started only by a person, ADR 0108). Record an item in the repository (handover,
  CHANGELOG) only when the user asks.
- **Upload only the pack the user asked for, hidden.** `gmpublish create` makes the item hidden; keep
  it so. The page's title after creation, its description, Required items and visibility are the
  user's to set on the item page. Making an item public needs the user's go-ahead after a licence and
  content review.
- **Never remove or delete a Workshop item**, duplicates included (AGENTS.md rule 5). So never
  `create` twice for one pack: look for its item first; every later build goes to `update -id`.
- **Names: the character's own name only** (the user, 2026-11-08). See "Names".
- **Public limits.** R18 models (nude base bodies, explicit morphs) stay hidden. The icon is free of
  adult content even for a hidden item. Models with restrictive terms (Evernight's record: 禁止二配，
  禁止非法使用, "Secondary matching and unauthorized use are prohibited"), game rips and another
  author's map are the user's call; never re-upload someone else's map: make it a Required item.
- **Games.** The loader deploys only at start-up. Do not close or restart the user's game unless the
  user gave a standing permission for that; otherwise tell them a restart is needed. Test on the PoC
  install (`GarrysMod_PoC`). The field install (`H:\SteamLibrary\steamapps\common\GarrysMod`) is the
  user's game: read it freely (`nlctl plan`, library entries), change nothing there unless the user
  asks in this conversation, after backing up what you touch. Never write `GarrysMod_RTX_c`.
- **Subscriptions are the user's.** Subscribing changes their Steam account: only when they asked
  for a test.
- Never edit `rtx-remix\mods\!advanced_material_editor`, `rtx.conf` or `user.conf`. `ai_pbr` is rpai's
  (it overwrites edits at the next publish): stage copies.
- Read only your own session's part of the user's GMod console log. The loader's own logs are fine.

## Names

The recorded name of a model is the character's own name as the user uses it, never a PMX or source
folder name with its tags: source folder `鸣潮-千咲` → `Chisa`; `星穹铁道-桂乃芬` → `Guinaifen`;
`阿芙2.0` → `Alf`. Ask when unsure which name the user uses. It sets everything a player sees or the
loader deploys:

| What | Form | Example |
|---|---|---|
| `<n>` | the character(s) in lowercase ASCII with underscores | `robin`, `evernight_march7th` |
| folders | `mmdhl_<n>`, `pbr_<n>` | `mmdhl_robin`, `pbr_robin` |
| package id, archive | `<n with hyphens>-rtx`, `<id>.gma` | `evernight-march7th-rtx` |
| package name | `<Name> RTX` | `Robin RTX` |
| titles (Hotloader package and archive; the archive's becomes the Workshop title at `create` and `update` never changes it) | `<Name> (Model Hotloader + RTX PBR)` | `Evernight and March 7th (Model Hotloader + RTX PBR)` |
| display name in Model Hotloader | the character's plain ASCII name | `Robin`, `March 7th` |
| default bodygroup preset | a real name | `Default` |
| description, reports | the name; no game named | `Chisa, imported with Model Hotloader ...` |

Refused anywhere in them: a game or franchise tag (鸣潮, 星穹铁道, 原神, 崩坏, 明日方舟, 终末地, 白银之城,
HSR, WuWa, Genshin, ZZZ, `[Arknights]`), a version, build or edition tag (`2.0`, `v1.2`, `Ver.3`,
`合体7`, a number after the name), an author or uploader tag (`by_mobius`, `Tda式`), a rating or format
tag (`R18`, `NSFW`, `MMD`, `PMX`), a bracketed tag, and pack words in a display name. The rule is code:
`scripts/model_names.py`. `mmdhl_pack.py` and `pbr_mod.py` (and mmd-remix-pbr's `hotloader_export.py`,
`stage_pbr_mod.py`, `package_characters.py`) refuse a tagged name with exit 1 before writing anything;
`check_pack.py` reports one as an error. An rpai layer key inside the mod (`robin_r18_f9c3e4b4.usda`)
is rpai's identifier, may keep its form and is never shown as a name.

## What a pack holds

| In the archive | Deployed to | Made by |
|---|---|---|
| `native/manifest.json` (kinds `lua-addon`, `root-files`) | read by the loader | `package_content.py` |
| `native/root/garrysmod/addons/mmdhl_<n>/` with `addon.json`, `data_static/mmdhl/packages/<32 hex>.json`, `data_static/mmdhl/files/<sha256>.dat` | `garrysmod\addons\mmdhl_<n>\` | `hotloader_export.py` or `mmdhl_pack.py` |
| `native/root/rtx-remix/mods/pbr_<n>/` with `mod.usda`, `models/<rpai key>.usda`, `textures/<rpai key>/*.dds` | `rtx-remix\mods\pbr_<n>\` | `stage_pbr_mod.py` or `pbr_mod.py` |

**The path into the game.** Steam puts the subscribed item in
`H:\SteamLibrary\steamapps\workshop\content\4000\<item id>\<n>-rtx.gma` (the uploaded file's name). At
the next start the loader finds `native/manifest.json` in it, checks Steam's
`steamapps\workshop\appworkshop_4000.acf` names a subscriber (`subscribedby`), checks it is content
only, and deploys both folders. GMod mounts the add-on folder; Model Hotloader (the RTX package's
copy) finds `data_static/mmdhl/packages/*.json` in the first map and installs the model into its cache
and library; Remix loads `pbr_<n>`. GMod refuses the archive itself (`Couldn't mount addon file`, red
in the add-on list): expected. Format and install rules: `references/model-hotloader-package.md`.

## Dependencies and deployment rules

- **Subscribed content, no allowlist** (ADR 0027, ADR 0111): kinds `lua-addon` and `root-files` only;
  root files under `rtx-remix/mods/<mod>/` that are Remix data (`.usd .usda .usdc .usdz .dds .png .jpg
  .jpeg .tga .bmp .exr .hdr .mdl .json .txt`) and under `garrysmod/addons/<add-on>/` that gmad's
  whitelist takes (plus `addon.json`). Only an item an account on that computer subscribed to deploys;
  one the game or a server only downloaded (`steamworks.DownloadUGC`) is not a candidate, and a package
  it deployed under an older loader is removed. A player turns content packages off with
  `"allow": {"subscribed_content": false}` in `native-loader\config.json`.
- **Needs the allowlist**, which players cannot edit (only 3829070317 has native code): payload files,
  binary modules, patch sets, module overrides, session variables, module dependencies, root files
  anywhere else. Such a pack is skipped, so packs use only `--addon` and `--mod`.
- **Precedence.** An allowlisted source of the same package id wins; of two subscriptions with one id
  the first found (item order) deploys and the other is "shadowed"; a pack whose folders overlap an
  active package's is skipped. Hence unique `mmdhl_<n>`, `pbr_<n>`, `<n>-rtx`.
- **In Remix,** `pbr_<n>` is an authored mod: it beats the RTX fixes' automatic materials
  (`~gmod_topbr`, ranked last by runtime patch 0020) and loses to mods that sort before it (`ai_pbr`,
  `!advanced_material_editor`) where they replace the same hash.
- **What a player needs:** the loader (`bin\win64\winmm.dll` from its release bundle on
  https://github.com/SheepyLord/Gmod-Workshop-RTX-Remix/releases, not a Workshop item; 0.16.0 is the
  newest, 2026-11-07), the RTX package 3829070317 (runtime, fixes, Model Hotloader with its natives), the
  pack, subscribed; for a map remaster also the map's own item. In starts without RTX the RTX
  package's Model Hotloader is hidden; a subscription to the standalone Model Hotloader (3810025467)
  runs then.
- **Required items** are set by the owner on the item page ("Add/Remove Required Items"); `gmpublish`
  cannot set them, and the loader ignores them. Put them in the description too.
- **`--requires-remix`:** for a map whose Lua only makes sense with Remix, yes (Modern House). For a
  character pack, no (the current recipe, Evernight): with it the model add-on is hidden without RTX,
  and by `workshop.lua` (inferred) a standalone Model Hotloader would then delete and later reinstall
  the model (`references/pitfalls.md` 22).
- **A player's own import of the same model** is taken over by a `workshop` package (R5): installed
  from the pack (differing files only), labelled as the pack's, the pack's settings written over the
  player's, whose files are kept under `workshop/own/<asset>/` and put back if the pack goes.

## Procedure for a character pack

Set the paths once (PowerShell):

```powershell
$repo  = 'H:\BACKUP_20260815\Modding\!NVIDIA-RTX-Remix'
$nlctl = "$repo\out\build\win64-release\loader\cli\nlctl.exe"
$game  = 'H:\SteamLibrary\steamapps\common\GarrysMod'          # the install with the import and the live mod
$K     = '<this skill>\scripts'
$P     = '<mmd-remix-pbr skill>\scripts'                         # $repo\skills\mmd-remix-pbr\scripts, or the installed copy
$py    = "$env:USERPROFILE\.rpai\venv\Scripts\python.exe"       # rpai's Python, for the mmd-remix-pbr scripts
$B     = "$repo\out\packages\<n>"                              # the build folder
```

1. **Scope.** Get the character(s) (PMX path or Model Hotloader asset id), the name(s) the user uses,
   the rpai model keys (`rpai status`; `<slug>_<asset8>`), the default preset, the audience (8 GB
   cards: the 2048 variant, mmd-remix-pbr "Publishing for 8 GB GPUs"). Look for an existing item for
   this pack (the table above, `$B\gmpublish-create.log`, the user); if there is one, follow "Updating
   an item". Check `git -C $repo status --short` and that `$B` is new. Load the mmd-remix-pbr skill.
   Find the layers: `rpai status` names rpai's live mod; on 2026-11-08 the field's `ai_pbr` holds none
   of the four packed imports' keys (`new_mmd_model_1c2ed2fc`, `robin_r18_f9c3e4b4`,
   `evernight_cf3eec2f`, `model_e2c25f9e`): their current layers are in the builds
   (`$B\pbr_<n>`) and deployed as the field's `rtx-remix\mods\pbr_<n>`. `GarrysMod_RTX_c` holds none.
2. **Refresh the live hashes.** In the running game, in a map, the model spawned with every part shown
   that should get PBR: `rpai hashes "<pmx>"` (mmd-remix-pbr's `reveal_hashes.py` shows hidden parts and
   puts them back), then `rpai publish "<pmx>"` if a hash changed. Spawn with `mmdhl.RequestSpawn(id,
   {}, cb)` and remove with `lua_run Entity(idx):Remove()` only what you spawned. Then list what the
   pack will lack:
   `python -I $K\add_hashes.py $game\rtx-remix\mods --check-json $env:USERPROFILE\.rpai\work\<key>\hashes.json`
   reads every mod of the install: `only in <mod>:<layer>` marks a sheet another character covers on
   this machine only; predicted-only parts are listed too (painted shadows the companion leaves out of
   the draw stay predicted and need no PBR). No game running: pack the recorded hashes and say so.
3. **Name and preset.** Read `$game\garrysmod\data\mmd_hotloader\library\<asset>.json` (`name`,
   `bodygroups.default`, `presets`). Ship the user's default preset under a real name (`Default`) and
   the character's plain ASCII name. Model Hotloader never changes either for a player who installed an
   earlier build (`writeIfMissing`), so get them right in the first upload.
4. **The Model Hotloader package**, into `$B\mmdhl_<n>`. Write `$B\description.txt` first (below).
   - Preferred, game running, the models in its library with clean names, private items only (it skips
     the terms dialog):
     `& $py "$P\hotloader_export.py" --game-root $game --asset <id8> [--asset <id8>] --title "<Name> (Model Hotloader + RTX PBR)" --description-file "$B\description.txt" --file-name <n> --tag cartoon --out "$B\mmdhl_<n>"`.
     It takes the library's names and presets as they are and refuses a tagged library name: then
     ask the user to rename the model in Model Hotloader, or use the fallback. The archive stays in
     `$game\garrysmod\data\mmd_hotloader\exports\`.
   - Fallback, offline (any install's cache), names on the command line:
     `python -I $K\mmdhl_pack.py $game\garrysmod\data\mmd_hotloader <id8> "$B\mmdhl_<n>" "<Name> (Model Hotloader + RTX PBR)" "<Name>" "SheepyLord" "$B\description.txt" [--item <id8>=<Name2>] [--default-preset-name Default]`.
     It reproduces Model Hotloader's exporter byte for byte (`scripts/mmdhl_pack.py.md`). Windows only.
5. **The PBR mod**, into `$B\pbr_<n>`, only the DDS the layers reference, every copy SHA-checked:
   - preferred: `& $py "$P\stage_pbr_mod.py" --src $game\rtx-remix\mods\ai_pbr --dest "$B\pbr_<n>" --layer <key> [--layer <key2>] --doc "<Name> RTX PBR, packaged for the Workshop."`
     (`--src ...\ai_pbr_2048` for the 8 GB variant; keep rpai keys out of `--doc`);
   - fallback: `python -I $K\pbr_mod.py $game\rtx-remix\mods\ai_pbr <key> "$B\pbr_<n>" "<Name>" [--layer <key2>]`;
   - for a pack whose layer is no longer in `ai_pbr`: start from the last build's `pbr_<n>` (copy it to
     the new `$B`, then `add_hashes.py` / `set_adaptive_emission.py` on the copy).
   - A hash that changed after staging, with no rpai at hand: `python -I $K\add_hashes.py "$B\pbr_<n>\models\<key>.usda" OLD=NEW`.
6. **Icon** `$B\icon.jpg`: a 512x512 baseline JPEG of the face(s) from a tuned in-game shot (rpai's
   `work\<key>\aabb_*\...\results.json` lists the shots), no adult content. Cropping is fine here; the
   never-crop rule is for test evidence.
   `& $py -I -c "from PIL import Image; im = Image.open(r'<shot>').convert('RGB'); im.crop((<l>, <t>, <r>, <b>)).resize((512, 512), Image.LANCZOS).save(r'$B\icon.jpg', 'JPEG', quality=92, progressive=False)"`
7. **Build** (call the main checkout's script by its absolute path so it checks with the main
   checkout's `nlctl`; it runs with `python -I`):
   ```powershell
   $d = (Get-Content -Raw -Encoding utf8 "$B\description.txt").Trim()
   python -I "$repo\tools\package_content.py" --id <n>-rtx --name "<Name> RTX" --addon "$B\mmdhl_<n>" --mod "$B\pbr_<n>" `
     --title "<Name> (Model Hotloader + RTX PBR)" --type model --tag cartoon --description $d --gma "$B\<n>-rtx.gma" --link
   git -C $repo status --short    # unchanged
   ```
   Add `--force` to rebuild an existing archive. It writes `<n>-rtx.gma` and `<n>-rtx.gma.inventory.txt`.
8. **Validate.** `& $nlctl manifest "$B\<n>-rtx.gma"` (`OK: valid native package`), `& $nlctl verify
   "$B\<n>-rtx.gma"` (`OK: gmad, <files> files`), then
   `python -I $K\check_pack.py $B --hashes-json $env:USERPROFILE\.rpai\work\<key>\hashes.json --deep`:
   no errors; carry its warnings into the report. A tagged, non-ASCII or placeholder display name, a
   tagged title, folder or package id, a description naming a game and a model without a terms-of-use
   record are errors: rename (in Model Hotloader, or `--item <id8>=<Name>`), record the terms, build
   again. An update of an item whose published name the user keeps (Guinaifen) passes `--keep-name
   <id8>`, which reports the name as a warning.
   - **Check it in the game before the upload,** on the PoC, never the user's install:
     `python -I $repo\tools\poc_session.py --evidence $B\poc install --allow-workshop 3829070317 --allow-local "$B\<n>-rtx.gma" --replace-config`,
     then `python -I $repo\tools\poc_session.py --evidence $B\poc run --name 01-pack --addons --map gm_construct --settle 40 --screenshots 1`:
     the console shows Model Hotloader installing the models, the library lists them under the pack's
     title, and one spawned shows its PBR. Put the PoC's `config.json` back from the copy the install
     step kept (its record's `config_backup`). A local archive is allowlisted, so no subscription is
     needed here.
9. **Upload** (Steam running, signed in to the user's account; from a game root holding
   `steam_appid.txt`: the PoC, as the repository's `tools\workshop.json` names its `gmpublish.exe`):
   ```powershell
   $root = 'H:\SteamLibrary\steamapps\common\GarrysMod_PoC'
   Push-Location $root
   & "$root\bin\win64\gmpublish.exe" create -addon "$B\<n>-rtx.gma" -icon "$B\icon.jpg" *> "$B\gmpublish-create.log"
   "exit $LASTEXITCODE"
   Pop-Location
   Get-Content "$B\gmpublish-create.log" | Select-String 'Success|item ID|hidden|rror|fail'
   ```
   Expect `Success! Your new item ID is <id>!` and `currently marked as hidden`. The log is the record of
   the id: keep it in `$B`. Its first lines carry the account's Steam ID; do not quote them. Robin's
   452 MB took 23 s and Guinaifen's 696 MB 28 s; give the call a 10-minute timeout.
10. **After the upload.**
    - Steam's public lookup cannot see a hidden item (`result 9`):
      `(Invoke-RestMethod -Method Post -Uri 'https://api.steampowered.com/ISteamRemoteStorage/GetPublishedFileDetails/v1/' -Body @{itemcount=1; 'publishedfileids[0]'='<id>'}).response.publishedfiledetails | Select-Object result, title`.
    - Once the user subscribed: the download's SHA-256 equals the build's (`Get-FileHash`), Steam's
      `appworkshop_4000.acf` lists the item with a `subscribedby`, and `& $nlctl plan $game` prints
      `ACTIVE  workshop <id> (subscribed, content only) -> <n>-rtx <version>`. An item Steam has but no
      account subscribed to is not listed at all.
    - After the next start of the game: `$game\native-loader\logs\loader.log` deployed it, both folders
      exist, the model is in Model Hotloader's library, and with it spawned `rpai hashes` plus
      `add_hashes.py $game\rtx-remix\mods\pbr_<n> --check-json ...` shows the hashes covered. On the
      author's machine `ai_pbr` wins hashes it shares with the pack (`references/pitfalls.md` 6).
11. **Tell the user** (plain words, numbers): the item link
    (`https://steamcommunity.com/sharedfiles/filedetails/?id=<id>`) and that it is hidden; package id,
    version, size; models with their display names and default preset; layers, materials, DDS count and
    size; the checks run and their results; what is not verified (the in-game install and PBR until a
    restart; predicted-only parts; sheets only another character's layer covers); what only they can do
    on the item page (paste the description, add 3829070317 as a Required item, rename the title, decide
    on public); that players must subscribe and restart; why it must stay hidden (R18, terms); that the
    repository is unchanged and where the build is.

## The description

Plain text, no straight double quotes (PowerShell 5.1 drops them on the way to `package_content.py`),
at most 8000 bytes, no game named. `package_content.py --description` puts it in the archive; the
Workshop page's description is pasted by the user. Template:

```
<Name>, imported with Model Hotloader, with RTX Remix PBR materials made for <her/him/them> (rpai:
upscaled albedo, normal, roughness and metallic maps; <style notes>). Spawns with the 'Default'
bodygroup preset.

Required items:
- RTX Remix for GMod, Workshop item 3829070317: the Remix runtime, the RTX fixes and Model Hotloader.
- The GMod native loader: bin\win64\winmm.dll from its release bundle on
  https://github.com/SheepyLord/Gmod-Workshop-RTX-Remix/releases (not a Workshop item).

Subscribe to this item: the loader deploys content packages only from subscribed items. At the next
start it deploys the Model Hotloader package add-on garrysmod\addons\mmdhl_<n> and the Remix mod
rtx-remix\mods\pbr_<n>; Model Hotloader then installs the model into its library. GMod cannot mount the
item itself: its console line Couldn't mount addon file and the red entry in the add-on list are
expected. Private test item.
```

## Updating an item

1. Find the id (the table above, `$B\gmpublish-create.log`, the user) and the last build in
   `out\packages\<n>`.
2. Rebuild what changed (steps 2-7 into a fresh folder, or a copy of the last build's parts:
   `mmdhl_pack.py --replace`, a fresh stage folder, `package_content.py --force`), then step 8
   (Guinaifen: `--keep-name 1c2ed2fc`). Keep the item's package id, folder names and display names
   unless the user asks for new ones, except a name the naming rule refuses: ask the user before
   renaming (Robin's rename to `robin-rtx` was the user's request; the user kept `Guinaifen (桂乃芬)`).
3. `& "$root\bin\win64\gmpublish.exe" update -id <id> -addon "$B\<n>-rtx.gma" [-icon "$B\icon.jpg"] -changes "<version>: <what changed>" *> "$B\gmpublish-update.log"`
   from `$root` as in step 9; expect `Success!`.
4. Tell the user: `update` does not change the title (rename it on the page), the description or the
   visibility; subscribers get the new build at the start after Steam fetched it; a model already
   installed keeps its library name, presets, fit and terms (they rename in Model Hotloader, or you
   edit the library entry at their request with GMod closed and a backup).

## A remastered map

The same route with a Lua add-on (`--addon <folder>`, its own folder name), the Remix mod
(`--mod <folder>`), `--requires-remix` when the Lua only makes sense with Remix, and the map's own
type and tags; the pack is named after the map only (`modern-house-rtx`, `Modern House RTX`), with no
author or version tag. Modern House RTX (ADR 0023, item 3829275998, 3.3 GB):

```powershell
python -I "$repo\tools\package_content.py" --id modern-house-rtx --name "Modern House RTX" --requires-remix `
  --addon <modern_house_rtx add-on> --mod <modern_house_rtx mod> --title "Modern House RTX (native loader package)" `
  --type effects --tag scenic --tag realism --gma "$repo\out\packages\modern-house-rtx.gma" --link
```

Never ship the map or its files (the Workshop bans re-uploads): it is a Required item (Modern House:
3495468649). Textures derived from another author's map keep the item hidden until the user decides.
Keep packs under about 4 GB (the Workshop's guideline). `check_pack.py --addon <folder> --mod <folder>
--gma <file>` checks a plain Lua add-on without the Hotloader rules.

## Scripts

| Script | Route | Does |
|---|---|---|
| `scripts/mmdhl_pack.py` | fallback for `hotloader_export.py` | the Model Hotloader package add-on folder, offline, from a cache; names on its command line |
| `scripts/pbr_mod.py` | fallback for `stage_pbr_mod.py` | the Remix mod folder with only the referenced files |
| `scripts/add_hashes.py` | both | add hashes to a staged layer; `--check-json` coverage of rpai's live hashes |
| `scripts/gma_diff.py` | diagnosis | compare two archives member by member (two imports' textures, a build and a download) |
| `scripts/check_pack.py` | both | read-only preflight of a build folder: names, Hotloader package, mod, archive, nlctl, icon, description |
| `scripts/model_names.py` | both | the naming rule, imported by the scripts above |
| `scripts/test_names.py` | tests | `python -I -m unittest -v` in `scripts\`: the naming rule and every refusal |
| mmd-remix-pbr `scripts/hotloader_export.py` | preferred | Model Hotloader's own export through the running game |
| mmd-remix-pbr `scripts/stage_pbr_mod.py` | preferred | the Remix mod folder from `ai_pbr` |

Each script has a `.md` beside it. This skill's scripts need only the standard library and run with
`python -I`; `mmdhl_pack.py` and `check_pack.py --deep` need Windows. The mmd-remix-pbr scripts run
with rpai's Python. `tools\package_content.py` and `tools\poc_session.py` run with `python -I` too.

## References

- [references/model-hotloader-package.md](references/model-hotloader-package.md): the package's files,
  fields, limits and packet format; what Model Hotloader does on install and takeover; display names.
- [references/pitfalls.md](references/pitfalls.md): every failure so far with its cause and fix, and
  where to look when a pack does not show up.
- The repository's `docs/PACKAGE_FORMAT.md`, ADRs 0015, 0016, 0023, 0024, 0027, 0111, and
  `tools/package_content.py.md`, `tools/poc_session.py.md`, `tools/gmapack/gmapack.py.md`.
