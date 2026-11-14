"""Re-key a Remix mod made with Remix's default texture hash (XXH3) to the RTX package's (XXH64).

    python -I rekey_mod_hashes.py --mod <mod folder> --source <map item | VPK | folder> [--source ...]
        [--cache FILE] [--json FILE] [--dry-run]

The RTX package's classic defaults set `rtx.useObsoleteHashOnTextureUpload = True`, so the runtime keys
every replacement material by XXH64 of the texture's top mip. A mod authored in a Remix setup with
the default (False) keys them by XXH3 of the same bytes, and under the package none of them applies.
This script hashes every VTF of the sources both ways (vtf_hash.py), then renames each `mat_<XXH3>` in
the mod's text layers to `mat_<XXH64>`: prim names and every path that names them. A hash that is
already some texture's XXH64 is left alone; one no source explains is left alone and reported (a
texture of a source not given, a format the game converts in a way vtf_hash does not try, or a
material from another map).

Sources: the map's Workshop item (.gma, or legacy .bin: its loose VTFs and every BSP's pakfile), the
game's and mounted games' `*_dir.vpk`, folders. `--cache` keeps each source's table (keyed by path,
size and time) so the next mod reuses it.

Exit codes: 0 done (or a dry run); 1 refused (no mod.usda, a name clash, an unreadable source);
2 bad command line.
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

MAT = re.compile(r"mat_([0-9A-Fa-f]{16})(?![0-9A-Za-z_])")


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--mod", required=True)
    ap.add_argument("--source", action="append", required=True)
    ap.add_argument("--cache")
    ap.add_argument("--json")
    ap.add_argument("--dry-run", action="store_true")
    args = ap.parse_args(argv)

    if not os.path.isfile(os.path.join(args.mod, "mod.usda")):
        print("ERROR %s has no mod.usda" % args.mod)
        return 1
    cache = vtf_hash.load_cache(args.cache)
    to64, known64 = {}, set()
    for src in args.source:
        if not os.path.exists(src):
            print("ERROR source %s is missing" % src)
            return 1
        for x64, x3, _, _ in vtf_hash.source_table(src, cache):
            to64.setdefault(x3, x64)
            known64.add(x64)
    vtf_hash.save_cache(args.cache, cache)

    walk = usd_refs.walk(args.mod)
    text_layers = [l for l in walk.layers if l not in walk.crate]
    names = set()
    texts = {}
    for layer in text_layers:
        with open(os.path.join(args.mod, layer), encoding="utf-8", newline="") as fh:
            texts[layer] = fh.read()
        names |= {h.upper() for h in re.findall(r'(?:over|def)\s+(?:\w+\s+)?"mat_([0-9A-Fa-f]{16})"', texts[layer])}
    crate_mats = []
    for layer in walk.crate:
        toks = usd_refs.crate_tokens(os.path.join(args.mod, layer))
        crate_mats += [t for t in toks if MAT.fullmatch(t) and t[4:].upper() in to64]
    rename = {}
    status = {"converted": [], "already_xxh64": [], "unknown": []}
    for h in sorted(names):
        if h in to64 and to64[h] != h:
            rename[h] = to64[h]
            status["converted"].append(h)
        elif h in known64:
            status["already_xxh64"].append(h)
        else:
            status["unknown"].append(h)
    clash = sorted(v for v in rename.values() if v in names and v not in rename)
    targets = list(rename.values())
    clash += sorted({v for v in targets if targets.count(v) > 1})
    print("materials %d: %d re-keyed XXH3 -> XXH64, %d already XXH64, %d not explained by the sources"
          % (len(names), len(status["converted"]), len(status["already_xxh64"]), len(status["unknown"])))
    if crate_mats:
        print("ERROR binary layers name %d materials to re-key (%s...): rewrite them first" % (len(crate_mats), crate_mats[:3]))
    if clash:
        print("ERROR re-keyed names would clash with materials already there: %s" % clash[:5])
    report = dict(status, rename=rename, clash=clash, crate_names=crate_mats)
    if args.json:
        with open(args.json, "w", encoding="utf-8") as fh:
            json.dump(report, fh, indent=1)
    if clash or crate_mats:
        return 1
    if args.dry_run or not rename:
        return 0
    changed = 0
    for layer, text in texts.items():
        new = MAT.sub(lambda m: "mat_" + rename.get(m.group(1).upper(), m.group(1)), text)
        if new != text:
            tmp = os.path.join(args.mod, layer) + ".rekey-tmp"
            with open(tmp, "w", encoding="utf-8", newline="") as fh:
                fh.write(new)
            os.replace(tmp, os.path.join(args.mod, layer))
            changed += 1
    print("rewrote %d layers" % changed)
    return 0


if __name__ == "__main__":
    sys.exit(main())
