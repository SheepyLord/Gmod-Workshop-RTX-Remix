"""Stage the Remix mod folder of a Workshop character package from the live ai_pbr mod.

Copies only the DDS files the named layers reference, checks every copy by SHA-256, copies the
layers and writes a mod.usda that lists them. The folder is the --mod input of package_content.py.

    python stage_pbr_mod.py --src <GarrysMod>\\rtx-remix\\mods\\ai_pbr --dest out\\packages\\x\\pbr_x ^
        --layer evernight_cf3eec2f --layer model_e2c25f9e --doc "Evernight and March 7th RTX PBR, packaged for the Workshop."

Layer names are the rpai model keys (`rpai status` lists them). The destination must not exist.
Nothing is written outside it.

Names (model_names.py, the user's rule of 2026-11-08): the --dest folder's name (pbr_<name>) and the
--doc text must carry no game, version, author or rating tag; a tagged one is refused before anything
is written. Keep rpai keys out of --doc: they come from the PMX's English name and may carry tags.
"""
from __future__ import annotations

import argparse
import hashlib
import re
import shutil
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).resolve().parent))  # model_names.py, also under python -I
import model_names  # noqa: E402

MOD_USDA = '''#usda 1.0
(
    customLayerData = {
        string lightspeed_game_name = "Garry's Mod (x64)"
        string lightspeed_layer_type = "replacement"
    }
    doc = "%s"
    metersPerUnit = 0.01
    subLayers = [
%s
    ]
    timeCodesPerSecond = 24
    upAxis = "Z"
)
'''


def sha(path: Path) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as f:
        for chunk in iter(lambda: f.read(1 << 22), b""):
            h.update(chunk)
    return h.hexdigest()


def main(argv: list[str] | None = None) -> None:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--src", type=Path, required=True, help="the live mod folder (rtx-remix/mods/ai_pbr)")
    p.add_argument("--dest", type=Path, required=True)
    p.add_argument("--layer", action="append", required=True, help="an rpai model key (repeatable)")
    p.add_argument("--doc", required=True, help="the doc string of the staged mod.usda: '<Name> RTX PBR, packaged for the Workshop.'")
    a = p.parse_args(argv)
    problems = [x for x in (model_names.refusal("--dest folder", a.dest.resolve().name, "slug"),
                            model_names.refusal("--doc", a.doc, "title")) if x]
    if problems:
        sys.exit("\n".join("error: " + x for x in problems))
    if a.dest.exists():
        sys.exit(f"{a.dest} exists; remove it first")
    (a.dest / "models").mkdir(parents=True)
    total = 0
    for key in a.layer:
        layer = a.src / "models" / f"{key}.usda"
        if not layer.exists():
            sys.exit(f"no layer {layer}")
        refs = sorted(set(re.findall(r"@(\.\./textures/[^@]+)@", layer.read_text(encoding="utf-8"))))
        for ref in refs:
            s, d = (a.src / "models" / ref).resolve(), (a.dest / "models" / ref).resolve()
            if not s.exists():
                sys.exit(f"missing {s}")
            d.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(s, d)
            if sha(s) != sha(d):
                sys.exit(f"copy differs: {d}")
            total += d.stat().st_size
        shutil.copyfile(layer, a.dest / "models" / f"{key}.usda")
        print(f"{key}: {len(refs)} textures")
    sub = ",\n".join(f"        @./models/{key}.usda@" for key in a.layer)
    (a.dest / "mod.usda").write_text(MOD_USDA % (a.doc.replace('"', "'"), sub), encoding="utf-8", newline="\n")
    print(f"staged {total / 1e6:.0f} MB of textures in {a.dest}")


if __name__ == "__main__":
    main()
