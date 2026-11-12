"""Port a finished map's Remix mod (or the set of mod folders it was played with) into one mod folder
for a content pack, keeping exactly what each texture, mesh and light hash showed.

    python -I port_classic_mods.py --dest <new mod folder> --source <mod folder> [--source ...]
        [--blank-missing] [--drop-unreferenced] [--doc TEXT] [--dry-run] [--force] [--json FILE]

Classic installs (RTXLauncher's GarrysMod_RTX_c) hold a map's look as loose folders in rtx-remix\\mods,
often a main mod plus fix mods (Poolday, Poolday_mirror_fix, gmodrtx_poolday_fix). The runtime ranks
mod folders by their name (byte order: ! < digits < upper case < _ < lower case < ~) and, for each
hash, uses the first folder that replaces it, whole (AssetReplacer::getReplacement*). One mod folder
instead composes its sub-layers with USD: a stronger layer wins attribute by attribute, and a weaker
layer's attributes fill what the stronger one leaves unset. So a merge keeps the look only if no hash
the first folder owns gets attributes from a later one. This script:

1. orders the sources as the runtime did (by folder name) and walks each from its mod.usda through
   every sub-layer, reference and payload, text (.usda) and binary crate (.usd) alike (usd_refs.py);
2. compares every hash prim (mat_, mesh_, light_) that more than one source authors: the first
   source with a non-empty prim owned it; a later source that sets anything the owner does not is a
   difference, and the script refuses (exit 1) - remove that override from the later source first;
   an empty prim (over "mesh_X" {}) never registered, so the next source's override was the live one
   and stays live;
3. copies each source into <dest>/<source folder name>/ unchanged and writes <dest>/mod.usda with
   their mod.usda files as sub-layers, strongest first. With one source the folder is copied as it
   is: a rename;
4. with --blank-missing, a texture reference to a file the source never had becomes @@ (no texture,
   what Remix drew for it anyway); without it, missing files are an error. With --drop-unreferenced,
   files no layer reaches are left out. Every copied file is SHA-256-checked.

Exit codes: 0 done (or a clean --dry-run); 1 refused (missing files, a difference, unreadable layer,
dest exists); 2 bad command line.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import shutil
import sys

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import usd_refs  # noqa: E402

HASH_PRIM = re.compile(r'(?:over|def)\s+(?:\w+\s+)?"((?:mat|mesh|light|sky)_[0-9A-Fa-f]{16})"')
CHILD_PRIM = re.compile(r'(?:over|def|class)\s+(?:\w+\s+)?"([^"]+)"')
PROPERTY = re.compile(r'(?m)^[ \t]*(?:(?:custom|uniform|prepend|append|delete|add|reorder)[ \t]+)*'
                      r'[\w\[\]]+[ \t]+([A-Za-z_][\w:]*(?:\.connect)?)[ \t]*(?:=|\(|$)')
ARC = re.compile(r"\b(references|payload|inherits|specializes|variants|variantSets)\s*=")


def runtime_key(name: str) -> bytes:
    """How the runtime orders mod folders: by path, case-sensitive (byte order of the UTF-8 name)."""
    return name.encode("utf-8")


def skip_string(text: str, i: int) -> int:
    if text.startswith('"""', i):
        j = text.find('"""', i + 3)
        return len(text) if j < 0 else j + 3
    j = i + 1
    while j < len(text) and text[j] not in '"\n':
        j += 2 if text[j] == "\\" else 1
    return j + 1


def prim_blocks(text: str):
    """[(path tuple, header text, body text)] of every prim in a .usda text, nested ones included."""
    out, stack = [], []
    i, n, paren, stmt = 0, len(text), 0, 0
    while i < n:
        c = text[i]
        if c == "#":
            j = text.find("\n", i)
            i = n if j < 0 else j
            continue
        if c == '"':
            i = skip_string(text, i)
            continue
        if c == "@":
            j = text.find("@", i + 1) if not text.startswith("@@", i) else i + 1
            i = (j + 1) if j >= 0 else n
            continue
        if c in "([":
            paren += 1
        elif c in ")]":
            paren -= 1
        elif c == "{" and paren == 0:
            header = text[stmt:i]
            m = CHILD_PRIM.search(header)
            stack.append((m.group(1) if m else None, header, i + 1))
            stmt = i + 1
        elif c == "}" and paren == 0:
            if stack:
                name, header, start = stack.pop()
                if name is not None:
                    path = tuple(s[0] for s in stack if s[0] is not None) + (name,)
                    out.append((path, header, text[start:i]))
            stmt = i + 1
        elif c == "\n" and paren == 0:
            stmt = i + 1 if not text[stmt:i].strip() else stmt
        i += 1
    return out


def strip_children(body: str) -> str:
    """A prim body without its nested prims' bodies and without metadata in (...), so the property
    statements left are the prim's own."""
    out, depth, i, paren = [], 0, 0, 0
    while i < len(body):
        c = body[i]
        if c == '"':
            j = skip_string(body, i)
            if depth == 0 and paren == 0:
                out.append(body[i:j])
            i = j
            continue
        if c == "#":
            j = body.find("\n", i)
            i = len(body) if j < 0 else j
            continue
        if c in "([":
            paren += 1
        elif c in ")]":
            paren -= 1
        elif paren == 0 and c == "{":
            depth += 1
        elif paren == 0 and c == "}":
            depth -= 1
        elif depth == 0 and paren == 0:
            out.append(c)
        i += 1
    return "".join(out)


HASH_NAME = re.compile(r"^(?:mat|mesh|light|sky)_[0-9A-Fa-f]{16}$")


def authored(text: str):
    """{hash prim name: set of 'child/path.property' it authors} for one text layer."""
    blocks = prim_blocks(text)
    result = {}
    for path, header, body in blocks:
        hashed = [k for k, p in enumerate(path) if HASH_NAME.match(p)]
        if not hashed:
            continue
        k = hashed[-1]
        owner = path[k]
        rel = "/".join(path[k + 1:])
        props = result.setdefault(owner, set())
        own = strip_children(body)
        for name in PROPERTY.findall(own):
            if name in ("over", "def", "class"):
                continue
            props.add("%s.%s" % (rel, name) if rel else name)
        for arc in ARC.findall(header):
            props.add("%s[%s]" % (rel, arc) if rel else "[%s]" % arc)
        if rel:
            props.add(rel + "/")  # the child prim itself: a light or a mesh is something
    return result


def source_prims(mod: str, walk: usd_refs.Walk):
    """{hash prim: set of authored properties} over every text layer of one source."""
    merged = {}
    for rel in walk.layers:
        if rel in walk.crate:
            continue
        with open(os.path.join(mod, rel), encoding="utf-8", errors="replace") as fh:
            text = fh.read()
        for prim, props in authored(text).items():
            merged.setdefault(prim, set()).update(props)
    return merged


def stage_meta(text: str):
    """(metersPerUnit, upAxis) of a root layer; USD's fallbacks when unset."""
    head = text.split("\n)", 1)[0]
    mpu = re.search(r"metersPerUnit\s*=\s*([0-9.eE+-]+)", head)
    up = re.search(r'upAxis\s*=\s*"(\w)"', head)
    return (float(mpu.group(1)) if mpu else 0.01, up.group(1) if up else "Y")


def sha256(path: str) -> str:
    h = hashlib.sha256()
    with open(path, "rb") as fh:
        for chunk in iter(lambda: fh.read(1 << 20), b""):
            h.update(chunk)
    return h.hexdigest()


def plan(sources, blank_missing: bool, drop_unreferenced: bool):
    """Everything the port will do, and the reasons to refuse it."""
    report = {"order": [], "sources": {}, "overlaps": [], "refusals": []}
    prims = {}
    for src in sources:
        name = os.path.basename(os.path.normpath(src))
        report["order"].append(name)
        if not os.path.isfile(os.path.join(src, "mod.usda")):
            report["refusals"].append("%s has no mod.usda" % src)
            continue
        w = usd_refs.walk(src)
        files = usd_refs.mod_files(src)
        used = w.used()
        info = {
            "path": src,
            "layers": w.layers,
            "crate_layers": w.crate,
            "files": len(files),
            "referenced_files": len(w.files),
            "missing": ["%s: %s" % m for m in w.missing],
            "unreferenced": [f for f in files if f.lower() not in used],
            "shaders": sorted(w.shaders),
        }
        report["sources"][name] = info
        for layer, error in w.errors:
            report["refusals"].append("%s/%s cannot be read: %s" % (name, layer, error))
        for layer, ref in w.outside:
            report["refusals"].append("%s/%s references %s outside the mod" % (name, layer, ref))
        for layer, ref in w.bare:
            report["refusals"].append("%s/%s references %r: not a relative path or a shader name" % (name, layer, ref))
        layer_missing = [(l, r) for l, r in w.missing if r.lower().endswith(usd_refs.LAYER_EXTENSIONS)]
        for layer, ref in layer_missing:
            report["refusals"].append("%s/%s names the layer %s, which is missing" % (name, layer, ref))
        crate_missing = [(l, r) for l, r in w.missing if l in w.crate]
        for layer, ref in crate_missing:
            report["refusals"].append("%s/%s (binary) names %s, which is missing: cannot blank it" % (name, layer, ref))
        if w.missing and not blank_missing:
            report["refusals"].append("%s names %d files it does not have (--blank-missing sets them to @@)"
                                      % (name, len(w.missing)))
        prims[name] = source_prims(src, w)
    # Overlaps, in runtime order: the first source with a non-empty prim owned the hash.
    names = [n for n in report["order"] if n in prims]
    every = sorted({p for n in names for p in prims[n]})
    for prim in every:
        holders = [n for n in names if prim in prims[n]]
        if len(holders) < 2:
            continue
        owner = next((n for n in holders if prims[n][prim]), None)
        entry = {"prim": prim, "sources": holders, "owner": owner, "added": {}}
        if owner is not None:
            for later in holders[holders.index(owner) + 1:]:
                extra = sorted(prims[later][prim] - prims[owner][prim])
                if extra:
                    entry["added"][later] = extra
                    report["refusals"].append(
                        "%s: %s owned it, but %s also sets %s; merged, those would apply"
                        % (prim, owner, later, ", ".join(extra[:6])))
        report["overlaps"].append(entry)
    metas = {}
    for name in names:
        with open(os.path.join(report["sources"][name]["path"], "mod.usda"), encoding="utf-8", errors="replace") as fh:
            metas[name] = stage_meta(fh.read())
    if len(set(metas.values())) > 1:
        report["refusals"].append("the sources' mod.usda differ in metersPerUnit/upAxis: %s" % metas)
    report["stage"] = next(iter(metas.values()), (0.01, "Z"))
    report["drop_unreferenced"] = drop_unreferenced
    return report


ROOT = """#usda 1.0
(
    customLayerData = {{
        string lightspeed_game_name = "Garry's Mod"
        string lightspeed_layer_type = "replacement"
    }}
    doc = "{doc}"
    metersPerUnit = {mpu}
    subLayers = [
{layers}
    ]
    timeCodesPerSecond = 24
    upAxis = "{up}"
)
"""


def copy_source(src: str, dest: str, info: dict, blank: bool, drop: bool, done: list):
    keep = None
    if drop:
        unref = {f.lower() for f in info["unreferenced"]}
        keep = lambda rel: rel.lower() not in unref  # noqa: E731
    missing_by_layer = {}
    for entry in info["missing"]:
        layer, _ = entry.split(": ", 1)
        missing_by_layer.setdefault(layer, 0)
        missing_by_layer[layer] += 1
    for rel in usd_refs.mod_files(src):
        if keep is not None and not keep(rel):
            continue
        source = os.path.join(src, rel)
        target = os.path.join(dest, rel)
        os.makedirs(os.path.dirname(target), exist_ok=True)
        if blank and rel in missing_by_layer:
            with open(source, encoding="utf-8", newline="") as fh:
                text = fh.read()
            new, missing = usd_refs.blank_missing(text, os.path.dirname(source))
            with open(target, "w", encoding="utf-8", newline="") as fh:
                fh.write(new)
            done.append({"file": target, "from": source, "blanked": missing})
            continue
        shutil.copyfile(source, target)
        if sha256(source) != sha256(target):
            raise OSError("copy of %s does not match its source" % source)
        done.append({"file": target, "from": source})


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split("\n\n")[0])
    ap.add_argument("--dest", required=True, help="the new mod folder (rtx-remix\\mods\\<name>)")
    ap.add_argument("--source", action="append", required=True, help="a mod folder (repeatable)")
    ap.add_argument("--blank-missing", action="store_true", help="set references to missing files to @@")
    ap.add_argument("--drop-unreferenced", action="store_true", help="leave out files no layer reaches")
    ap.add_argument("--doc", default="", help="the root layer's doc string (several sources only)")
    ap.add_argument("--dry-run", action="store_true")
    ap.add_argument("--force", action="store_true", help="replace an existing --dest")
    ap.add_argument("--json", help="write the report here")
    args = ap.parse_args(argv)

    sources = sorted((os.path.abspath(s) for s in args.source), key=lambda p: runtime_key(os.path.basename(p)))
    if len({os.path.basename(s) for s in sources}) != len(sources):
        print("ERROR two sources share a folder name", file=sys.stderr)
        return 2
    report = plan(sources, args.blank_missing, args.drop_unreferenced)
    dest = os.path.abspath(args.dest)
    if os.path.exists(dest) and not args.force and not args.dry_run:
        report["refusals"].append("%s exists (--force replaces it)" % dest)
    for src in sources:
        a, b = os.path.normcase(src), os.path.normcase(dest)
        if a == b or a.startswith(b + os.sep) or b.startswith(a + os.sep):
            report["refusals"].append("%s and %s contain one another" % (src, dest))

    print("runtime order (strongest first): %s" % ", ".join(report["order"]))
    for name in report["order"]:
        info = report["sources"].get(name)
        if not info:
            continue
        print("%s: %d layers (%d binary), %d files, %d referenced, %d missing, %d unreferenced, shaders %s"
              % (name, len(info["layers"]), len(info["crate_layers"]), info["files"], info["referenced_files"],
                 len(info["missing"]), len(info["unreferenced"]), ", ".join(info["shaders"]) or "-"))
    for entry in report["overlaps"]:
        if entry["added"]:
            continue
        print("overlap %s in %s: %s"
              % (entry["prim"], ", ".join(entry["sources"]),
                 "owned by %s, the others add nothing" % entry["owner"] if entry["owner"]
                 else "empty everywhere"))
    for text in report["refusals"]:
        print("ERROR " + text)
    if args.json:
        os.makedirs(os.path.dirname(os.path.abspath(args.json)), exist_ok=True)
        with open(args.json, "w", encoding="utf-8") as fh:
            json.dump(report, fh, indent=1, ensure_ascii=True)
    if report["refusals"]:
        return 1
    if args.dry_run:
        print("dry run: nothing written")
        return 0

    work = dest + ".partial-%d" % os.getpid()
    if os.path.exists(work):
        shutil.rmtree(work)
    done = []
    if len(sources) == 1:
        name = report["order"][0]
        copy_source(sources[0], work, report["sources"][name], args.blank_missing, args.drop_unreferenced, done)
    else:
        for name, src in zip(report["order"], sources):
            copy_source(src, os.path.join(work, name), report["sources"][name], args.blank_missing,
                        args.drop_unreferenced, done)
        mpu, up = report["stage"]
        layers = ",\n".join("        @./%s/mod.usda@" % name for name in report["order"])
        doc = args.doc or "Ported from the mod folders %s (strongest first)." % ", ".join(report["order"])
        with open(os.path.join(work, "mod.usda"), "w", encoding="utf-8", newline="\n") as fh:
            fh.write(ROOT.format(doc=doc.replace('"', "'"), mpu=("%g" % mpu), layers=layers, up=up))
    if os.path.exists(dest):
        shutil.rmtree(dest)
    os.replace(work, dest)
    blanked = sum(len(d.get("blanked", [])) for d in done)
    size = sum(os.path.getsize(os.path.join(dp, f)) for dp, _, fs in os.walk(dest) for f in fs)
    print("wrote %s: %d files, %.1f MB, %d references blanked" % (dest, len(done) + (len(sources) > 1), size / 1e6, blanked))
    check = usd_refs.walk(dest)
    if check.missing or check.errors or check.outside:
        print("ERROR the result does not resolve: %s %s %s" % (check.missing[:5], check.errors[:5], check.outside[:5]))
        return 1
    print("ok every reference of the result resolves (%d layers, %d files)" % (len(check.layers), len(check.files)))
    if args.json:
        report["written"] = [{k: (v.replace(dest, "<dest>") if k == "file" else v) for k, v in d.items()} for d in done]
        with open(args.json, "w", encoding="utf-8") as fh:
            json.dump(report, fh, indent=1, ensure_ascii=True)
    return 0


if __name__ == "__main__":
    sys.exit(main())
