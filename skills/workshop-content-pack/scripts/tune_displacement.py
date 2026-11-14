"""Tone down a mod's parallax displacement: none on model and decal textures, a cap on world textures.

    python -I tune_displacement.py --mod <mod folder> --source <map item> [--source <*_dir.vpk> ...]
        [--world-max 0.008] [--cache FILE] [--json FILE] [--dry-run]

Remix draws a material with a height map and `displace_in` > 0 with parallax occlusion mapping: the
surface looks `displace_in` x one texture repeat deep. Third-party mods often set one depth for every
material (HamzaPOPO's Map Pack RTX: 0.05, up to 0.115), which turns floor tiles into stacked blocks and
smears props, whose UV islands tear at their seams. This project's remasters keep 0.0006-0.008 on world
floors and walls and none on models (remix-map-pbr). The script finds each material's game texture by
its hash in the sources (vtf_hash.py; a texture under materials/models/ is a model texture, one under
materials/decals/ a decal) and rewrites only the `displace_in` values in the mod's text layers: 0 for
model and decal textures, at most --world-max for the rest (a material no source names counts as world).
Everything else is left as it is.

Exit codes: 0 done (or a dry run); 1 refused (no mod.usda, a missing source); 2 bad command line.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import usd_refs  # noqa: E402
import vtf_hash  # noqa: E402

DISPLACE = re.compile(r"(float\s+inputs:displace_in\s*=\s*)([0-9.eE+-]+)")


def texture_names(sources):
    names = {}
    for src in sources:
        for name, blob in vtf_hash.iter_vtfs(src):
            try:
                for x64, x3 in vtf_hash.texture_hashes(blob):
                    names.setdefault(x64, name)
                    names.setdefault(x3, name)
            except (ValueError, KeyError, IndexError):
                continue
    return names


def kind_of(name):
    n = (name or "").lower().replace("\\", "/")
    if n.startswith("pak:"):
        n = n[4:]
    if n.startswith("materials/models/") or "/models/" in n:
        return "model"
    if n.startswith("materials/decals/") or "/decals/" in n:
        return "decal"
    return "world"


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--mod", required=True)
    ap.add_argument("--source", action="append", required=True)
    ap.add_argument("--world-max", type=float, default=0.008)
    ap.add_argument("--json")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args(argv)
    if not os.path.isfile(os.path.join(args.mod, "mod.usda")):
        print("ERROR %s has no mod.usda" % args.mod)
        return 1
    for s in args.source:
        if not os.path.exists(s):
            print("ERROR source %s is missing" % s)
            return 1
    names = texture_names(args.source)
    walk = usd_refs.walk(args.mod)
    report = {"changed": {}, "kept": 0}
    counts = {"model": 0, "decal": 0, "world": 0}
    for layer in walk.layers:
        if layer in walk.crate:
            continue
        path = os.path.join(args.mod, layer)
        with open(path, encoding="utf-8", newline="") as fh:
            text = fh.read()
        out, last = [], 0
        heads = [(m.start(), m.group(1).upper()) for m in re.finditer(r'"mat_([0-9A-Fa-f]{16})"', text)]
        for m in DISPLACE.finditer(text):
            owner = None
            for start, h in heads:
                if start < m.start():
                    owner = h
                else:
                    break
            if owner is None:
                continue
            kind = kind_of(names.get(owner))
            value = float(m.group(2))
            new = 0.0 if kind in ("model", "decal") else min(value, args.world_max)
            if new == value:
                report["kept"] += 1
                continue
            counts[kind] += 1
            report["changed"][owner] = {"kind": kind, "texture": names.get(owner), "from": value, "to": new}
            out.append(text[last:m.start(2)])
            out.append("%g" % new)
            last = m.end(2)
        if out and not args.dry_run:
            out.append(text[last:])
            tmp = path + ".tune-tmp"
            with open(tmp, "w", encoding="utf-8", newline="") as fh:
                fh.write("".join(out))
            os.replace(tmp, path)
    print("displacement: %d model and %d decal materials set to 0, %d world materials capped at %g, %d left as they were"
          % (counts["model"], counts["decal"], counts["world"], args.world_max, report["kept"]))
    if args.json:
        with open(args.json, "w", encoding="utf-8") as fh:
            json.dump(report, fh, indent=1)
    return 0


if __name__ == "__main__":
    sys.exit(main())
