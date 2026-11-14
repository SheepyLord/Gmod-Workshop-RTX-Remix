"""Fit any Remix mod folder under one Workshop item's budget by leaving out top mips, no re-encoding.

    python -I fit_mod.py --mod <mod folder> --out <new mod folder> [--budget BYTES] [--min-side N]
        [--report FILE] [--dry-run] [--force]

For mods that did not come from this project's remaster pipeline (third-party map mods ported with
port_classic_mods.py), which fit_map_mod.py cannot read: no materials.usda convention, no per-map
inventory. It walks the mod with usd_refs.py (text and binary layers), copies every file to --out at
the same relative path, and shrinks block-compressed DDS files (BC1-BC7 with a full mip chain) by
dropping top mips: the header is rewritten and the remaining mips copied byte for byte
(fit_map_mod.Dds), so every layer stays as it is. A texture's role comes from the material inputs that
name it (diffuse/albedo, normal, emissive, roughness/metallic/height = aux; a texture only a binary
layer names is a model texture with no known role).

Lossless first: a BC4/BC5 map whose top mip holds one value keeps a 16 px tail. Then tiers, each
applied to the largest files first and only until the mod fits:

  aux      roughness, metallic and height maps at half the size of their material's albedo
  4096     every texture above 4096 at 4096
  2048     every texture above 2048 at 2048
  normal   normal maps at half the size of their material's albedo
  halve    every texture halved again, round by round, down to --min-side

A file several materials use takes the largest size any of them still wants. Nothing is cut below
--min-side (default 128) or below its own mip chain.

Exit codes: 0 written (or planned with --dry-run); 1 refused (a reference that does not resolve,
--out exists without --force, the budget out of reach); 2 bad command line.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import fit_map_mod as F  # noqa: E402
import usd_refs  # noqa: E402

TIERS = ("aux", "4096", "2048", "normal", "halve")
MATERIAL = re.compile(r'(?:over|def)\s+(?:\w+\s+)?"((?:mat_[0-9A-Fa-f]{16})|[^"]+)"')
INPUT = re.compile(r"inputs:(\w+)\s*=\s*@([^@\r\n]+)@")


class Unit:
    def __init__(self, rel, dds):
        self.rel, self.dds = rel, dds
        self.roles = set()
        self.materials = set()
        self.drop = 0
        self.constant = False

    @property
    def size(self):
        return self.dds.bytes_after(self.drop)

    def side(self, drop=None):
        return self.dds.side >> (self.drop if drop is None else drop)


def roles_by_file(mod, walk):
    """{file rel (lower): [(role, material)]} from the text layers' material inputs."""
    out = {}
    for layer in walk.layers:
        if layer in walk.crate:
            continue
        with open(os.path.join(mod, layer), encoding="utf-8", errors="replace") as fh:
            text = fh.read()
        heads = [(m.start(), m.group(1)) for m in MATERIAL.finditer(text)]
        k = 0
        current = None
        for m in INPUT.finditer(text):
            while k < len(heads) and heads[k][0] < m.start():
                if heads[k][1].startswith("mat_") or current is None:
                    current = heads[k][1]
                k += 1
            ref = m.group(2)
            if not ref.startswith(("./", "../")):
                continue
            rel = os.path.normpath(os.path.join(os.path.dirname(layer), ref)).replace("\\", "/").lower()
            out.setdefault(rel, []).append((F.KIND.get(m.group(1), m.group(1)), current or layer))
    return out


def game_sides(sources, cache_path):
    """{texture hash (XXH64 or XXH3): the game texture's longer side} from the sources."""
    if not sources:
        return {}
    import vtf_hash
    cache = vtf_hash.load_cache(cache_path)
    sides = {}
    for src in sources:
        for x64, x3, w, h in vtf_hash.source_table(src, cache):
            sides.setdefault(x64, max(w, h))
            sides.setdefault(x3, max(w, h))
    vtf_hash.save_cache(cache_path, cache)
    return sides


def plan(mod, budget, min_side, sides=None):
    sides = sides or {}
    walk = usd_refs.walk(mod)
    problems = ["%s: %s" % e for e in walk.errors] + ["%s names %s, missing" % m for m in walk.missing] + \
        ["%s names %s outside the mod" % o for o in walk.outside]
    files = usd_refs.mod_files(mod)
    used = walk.used()
    roles = roles_by_file(mod, walk)
    units, fixed = {}, 0
    for rel in files:
        path = os.path.join(mod, rel)
        if rel.lower().endswith(".dds") and rel.lower() in used:
            try:
                d = F.Dds(path)
            except F.Refused:
                fixed += os.path.getsize(path)
                continue
            u = Unit(rel, d)
            for role, mat in roles.get(rel.lower(), []):
                u.roles.add(role)
                u.materials.add(mat)
            if not u.roles:
                u.roles.add("model")
            F.check_constant(d)
            if d.constant is not None and d.side > F.CONST_SIDE:
                u.drop = d.drop_for_side(F.CONST_SIDE)
                u.constant = True
            units[rel.lower()] = u
        else:
            fixed += os.path.getsize(path)
    albedo_side = {}
    for u in units.values():
        if "albedo" in u.roles:
            for m in u.materials:
                albedo_side[m] = max(albedo_side.get(m, 0), u.dds.side)
        # How much larger than the game's own texture this file is (its materials' largest game side);
        # 1 when no source names it. Cuts go to the biggest upscales of small game textures first.
        game = [sides[m[4:].upper()] for m in u.materials if m.startswith("mat_") and m[4:].upper() in sides]
        u.game_side = max(game) if game else 0
    known = sum(1 for u in units.values() if u.game_side)
    report = {"source_bytes": sum(os.path.getsize(os.path.join(mod, r)) for r in files), "fixed_bytes": fixed,
              "lossless_bytes": None, "tiers": {}, "problems": problems,
              "game_sizes_known": "%d of %d textures" % (known, len(units))}

    def factor(u):
        return (u.side() / u.game_side) if u.game_side else 1.0

    def total():
        return fixed + sum(u.size for u in units.values())
    report["lossless_bytes"] = total()

    def floor_drop(u):
        return u.dds.drop_for_side(min_side) if u.dds.side > min_side else 0

    def want(u, tier, rnd=0):
        """The drop this tier asks of a unit (never less than it has)."""
        if u.constant:
            return u.drop
        d = u.drop
        if tier == "aux" and u.roles <= {"aux"}:
            ref = max([albedo_side.get(m, 0) for m in u.materials] + [0]) or u.dds.side
            d = max(d, u.dds.drop_for_side(max(1, ref // 2)))
        elif tier in ("4096", "2048"):
            d = max(d, u.dds.drop_for_side(int(tier)))
        elif tier == "normal" and u.roles <= {"normal"}:
            ref = max([albedo_side.get(m, 0) for m in u.materials] + [0]) or u.dds.side
            d = max(d, u.dds.drop_for_side(max(1, ref // 2)))
        elif tier == "halve":
            d = u.drop + 1
        return min(d, floor_drop(u), u.dds.max_drop()) if d > u.drop else u.drop

    for tier in TIERS:
        if total() <= budget:
            break
        rounds = 0
        while total() > budget:
            cands = sorted((u for u in units.values() if want(u, tier) > u.drop),
                           key=lambda u: (-factor(u), -u.size, u.rel) if tier in ("2048", "normal", "halve")
                           else (-u.size, u.rel))
            if not cands:
                break
            for u in cands:
                if total() <= budget:
                    break
                before = u.size
                u.drop = want(u, tier)
                t = report["tiers"].setdefault(tier, {"textures": 0, "saved": 0})
                t["textures"] += 1
                t["saved"] += before - u.size
            rounds += 1
            if tier != "halve":
                break
    report["fitted_bytes"] = total()
    report["fits"] = total() <= budget
    report["files"] = {u.rel: {"side": u.dds.side, "to": u.side(), "dropped": u.drop, "roles": sorted(u.roles),
                               "game_side": u.game_side, "constant": u.constant} for u in units.values() if u.drop}
    return walk, files, units, report


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--mod", required=True)
    ap.add_argument("--out", required=True)
    ap.add_argument("--budget", type=int, default=F.DEFAULT_BUDGET)
    ap.add_argument("--min-side", type=int, default=128)
    ap.add_argument("--source", action="append", default=[],
                    help="the map's item, a *_dir.vpk or a folder (repeatable): the game textures' sizes")
    ap.add_argument("--cache", help="vtf_hash's cache file (shared with rekey_mod_hashes.py)")
    ap.add_argument("--report")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--force", action="store_true")
    args = ap.parse_args(argv)
    mod, out = os.path.abspath(args.mod), os.path.abspath(args.out)
    if not os.path.isfile(os.path.join(mod, "mod.usda")):
        print("ERROR %s has no mod.usda" % mod)
        return 1
    walk, files, units, report = plan(mod, args.budget, args.min_side, game_sides(args.source, args.cache))
    for p in report["problems"]:
        print("ERROR " + p)
    print("source %.3f GB, lossless %.3f GB, fitted %.3f GB (budget %.3f GB); game sizes known for %s" % (
        report["source_bytes"] / 1e9, report["lossless_bytes"] / 1e9, report["fitted_bytes"] / 1e9,
        args.budget / 1e9, report["game_sizes_known"]))
    for tier, t in report["tiers"].items():
        print("  tier %-6s %4d textures, %.3f GB saved" % (tier, t["textures"], t["saved"] / 1e9))
    if args.report:
        os.makedirs(os.path.dirname(os.path.abspath(args.report)), exist_ok=True)
        with open(args.report, "w", encoding="utf-8") as fh:
            json.dump(report, fh, indent=1)
    if report["problems"]:
        return 1
    if not report["fits"]:
        print("ERROR the budget is out of reach at --min-side %d" % args.min_side)
        return 1
    if args.dry_run:
        return 0
    if os.path.exists(out) and not args.force:
        print("ERROR %s exists (--force replaces it)" % out)
        return 1
    work = out + ".partial-%d" % os.getpid()
    if os.path.exists(work):
        shutil.rmtree(work)
    for rel in files:
        src, dst = os.path.join(mod, rel), os.path.join(work, rel)
        os.makedirs(os.path.dirname(dst), exist_ok=True)
        u = units.get(rel.lower())
        if u is not None and u.drop:
            with open(dst, "wb") as fh:
                fh.write(u.dds.reduced(u.drop))
        else:
            shutil.copyfile(src, dst)
    written = sum(os.path.getsize(os.path.join(work, r)) for r in files)
    if written != report["fitted_bytes"]:
        print("ERROR wrote %d bytes, planned %d" % (written, report["fitted_bytes"]))
        return 1
    check = usd_refs.walk(work)
    if check.missing or check.errors:
        print("ERROR the result does not resolve: %s" % (check.missing[:3] + check.errors[:3]))
        return 1
    if os.path.exists(out):
        shutil.rmtree(out)
    os.replace(work, out)
    print("wrote %s: %d files, %d bytes" % (out, len(files), written))
    return 0


if __name__ == "__main__":
    sys.exit(main())
