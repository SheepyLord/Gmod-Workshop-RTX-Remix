"""Export Model Hotloader characters as a Workshop package add-on folder, through the running game.

It does what the library's Export dialog (lua/mmdhl/workshop_export.lua) does, with the same item
settings (spawn preset, body groups, arms, fits, terms-of-use records) and the same native call
(StartPackageExport), then unpacks the archive Model Hotloader writes into an add-on folder
(addon.json + data_static/mmdhl/...) that package_content.py takes as --addon.

    python hotloader_export.py --game-root <GarrysMod> --asset cf3eec2f --asset e2c25f9e ^
        --title "Evernight and March 7th (Model Hotloader + RTX PBR)" --description-file desc.txt ^
        --file-name evernight-march7th --tag cartoon --out out\\packages\\x\\mmdhl_x

--asset takes the full 64-digit id or any unique prefix. The game must be in a map (client Lua
runs there) with Model Hotloader loaded; the models must be in its library (not shared ones).

Names (model_names.py, the user's rule of 2026-11-08): the title, the export file name, the --out
folder and every model's library name must carry no game, version, author, rating or pack tag. The
library names travel as they are, so a tagged one ("鸣潮-千咲", "阿芙2.0") is refused before the game
is contacted: rename the model in Model Hotloader (ask the user first) or pack offline with
workshop-content-pack's mmdhl_pack.py, which takes the names on its command line.

The export dialog asks the player to acknowledge the models' terms of use first
(mmdhl_terms_warning_export). This script does not show that dialog and does not change the
setting: use it for private items, and make an item public only after exporting through the dialog.
"""
from __future__ import annotations

import argparse
import json
import subprocess
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
TOOL = HERE.parent / "tool"
sys.path.insert(0, str(TOOL))
sys.path.insert(0, str(HERE))  # model_names.py, also under python -I
import model_names  # noqa: E402

# gmapack.py of the native loader repository: the one this skill sits in, else the main checkout.
GMAPACK = next((p for p in (HERE.parents[2] / "tools" / "gmapack" / "gmapack.py",
                            Path(r"H:\BACKUP_20260815\Modding\!NVIDIA-RTX-Remix\tools\gmapack\gmapack.py"))
                if p.is_file()), HERE.parents[2] / "tools" / "gmapack" / "gmapack.py")

START = r'''
local meta = util.JSONToTable(__META__)
local native = mmdhl.native
if not native.StartPackageExport then return { error = "this Model Hotloader has no package export" } end
local items = {}
for _, id in ipairs(meta.assets) do
  local entry = mmdhl.library.entries[id]
  if not entry then return { error = "not in the library: " .. id } end
  if entry.shared then return { error = "a shared (Workshop) model cannot be exported: " .. id } end
  if not mmdhl.workshop.InCache("character", id) then return { error = "not in the cache: " .. id } end
  local s = entry.settings or {}
  local item = { kind = "character", asset = id, name = entry.name,
    settings = { spawn = s.spawn, bodygroups = s.bodygroups },
    terms = mmdhl.terms and mmdhl.terms.ForPackage("character", id) or nil }
  local arms = mmdhl.GetArmsParts and mmdhl.GetArmsParts(id) or {}
  if next(arms) then item.arms = {} for k, v in pairs(arms) do item.arms[tostring(k)] = v end end
  local fit = util.JSONToTable(file.Read("mmd_hotloader/fit_overrides/" .. id .. ".json", "DATA") or "")
  -- Who saved a physics default stays on this computer (as the dialog does).
  if istable(fit) then
    if istable(fit.editor) then fit.editor.savedBy = nil fit.editor.savedByName = nil end
    item.fit = fit
  end
  items[#items + 1] = item
end
local spec = { title = meta.title, author = meta.author, description = meta.description, tags = meta.tags,
  install = "workshop", fileName = meta.file_name, items = items }
local handle, err = native.StartPackageExport(util.TableToJSON(spec))
if not handle then return { error = tostring(err) } end
RPAI_EXPORT = handle
local names = {}
for _, item in ipairs(items) do names[#names + 1] = item.name end
return { started = true, names = names }
'''

POLL = r'''
local state = util.JSONToTable(mmdhl.native.PollPackageExport(RPAI_EXPORT) or "") or { state = "failed" }
return state
'''


def resolve_assets(game_root: Path, prefixes: list[str]) -> list[str]:
    folder = game_root / "garrysmod" / "data" / "mmd_hotloader" / "assets"
    out = []
    for prefix in prefixes:
        hits = [p.name for p in folder.iterdir() if p.name.startswith(prefix.lower())]
        if len(hits) != 1:
            raise SystemExit(f"--asset {prefix}: {len(hits)} matches in {folder}")
        out.append(hits[0])
    return out


def library_name(game_root: Path, asset: str) -> str:
    """The name the export will carry, as Model Hotloader's library computes it (library.lua):
    the library entry's name, else the import's manifest name, else the id's first 12 digits."""
    data = game_root / "garrysmod" / "data" / "mmd_hotloader"
    for path in (data / "library" / f"{asset}.json", data / "assets" / asset / "manifest.json"):
        try:
            name = json.loads(path.read_text(encoding="utf-8-sig")).get("name")
        except (OSError, ValueError, AttributeError):
            continue
        if isinstance(name, str) and name:
            return name
    return asset[:12]


def refuse_tagged(checks) -> None:
    """Exit 1 with one line per (label, value, kind) that carries a tag (model_names.py)."""
    problems = [p for p in (model_names.refusal(label, value, kind) for label, value, kind in checks) if p]
    if problems:
        raise SystemExit("\n".join("error: " + p for p in problems))


def main(argv: list[str] | None = None) -> None:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--game-root", type=Path, required=True)
    p.add_argument("--asset", action="append", required=True)
    p.add_argument("--title", required=True)
    p.add_argument("--author", default="SheepyLord")
    p.add_argument("--description-file", type=Path, required=True)
    p.add_argument("--file-name", required=True, help="the archive's name (no extension)")
    p.add_argument("--tag", action="append", default=[], help="a Workshop tag, at most two")
    p.add_argument("--out", type=Path, required=True, help="the add-on folder to write (must not exist)")
    p.add_argument("--timeout", type=float, default=600.0)
    p.add_argument("--gmapack", type=Path, default=GMAPACK,
                   help="the native-loader repository's tools/gmapack/gmapack.py (unpacks the archive); "
                        "default: the repository this skill sits in, else the main checkout")
    a = p.parse_args(argv)
    # Names first: nothing is read from the game or written before they pass.
    refuse_tagged([("--title", a.title, "title"), ("--file-name", a.file_name, "slug"),
                   ("--out folder", a.out.resolve().name, "slug")])
    if a.out.exists():
        raise SystemExit(f"{a.out} exists")
    if not a.gmapack.is_file():
        raise SystemExit(f"{a.gmapack} not found: pass --gmapack <native loader repository>\\tools\\gmapack\\gmapack.py")
    assets = resolve_assets(a.game_root, a.asset)
    refuse_tagged([(f"library name of {asset[:8]}", library_name(a.game_root, asset), "name") for asset in assets])
    from rpai.gamebridge import GameBridge, lua_long_string
    bridge = GameBridge(a.game_root)
    meta = {"assets": assets, "title": a.title, "author": a.author, "tags": a.tag, "file_name": a.file_name,
            "description": a.description_file.read_text(encoding="utf-8").strip()}
    r = bridge.run_client_lua(START.replace("__META__", lua_long_string(json.dumps(meta, ensure_ascii=False))))
    if not r.get("ok") or r.get("error"):
        raise SystemExit(f"export not started: {r.get('error')}")
    names = r.get("names", {})
    names = list(names.values()) if isinstance(names, dict) else list(names)
    print("exporting:", ", ".join(map(str, names)))
    deadline = time.monotonic() + a.timeout
    while True:
        s = bridge.run_client_lua(POLL)
        if s.get("state") == "running":
            print(f"  {s.get('stage')} {float(s.get('progress') or 0):.0%}", flush=True)
        else:
            break
        if time.monotonic() > deadline:
            raise SystemExit("timed out; the export may still be running in the game")
        time.sleep(3)
    if s.get("state") != "complete":
        raise SystemExit(f"export {s.get('state')}: {s.get('error')}")
    print(f"archive {s['path']} ({int(s['bytes']) / 1e6:.0f} MB, {s['items']} model(s), package {s['packageId']})")
    # The live library could have been renamed since the check above: check what was exported.
    refuse_tagged([("exported name", str(name), "name") for name in names])
    subprocess.run([sys.executable, "-I", str(a.gmapack), "extract", "--file", s["path"], "--out", str(a.out)],
                   check=True)
    files = sorted(p for p in a.out.rglob("*") if p.is_file())
    print(f"add-on folder {a.out}: {len(files)} files, {sum(f.stat().st_size for f in files) / 1e6:.0f} MB")


if __name__ == "__main__":
    main()
