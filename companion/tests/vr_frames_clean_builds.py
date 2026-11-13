"""Remove only hash-verified older C package builds after a newer passing, restored PoC run."""
from pathlib import Path
import argparse
import hashlib
import json
import re
import subprocess

ROOT = Path(__file__).resolve().parents[2]
PREFIX = "gmod-rtx-remix-0.0.0-v4c."


def read(path):
    return json.loads(path.read_text(encoding="utf-8"))


def checksum(path):
    hasher = hashlib.sha256()
    with path.open("rb") as stream:
        for block in iter(lambda: stream.read(1024*1024), b""):
            hasher.update(block)
    return hasher.hexdigest()


def verified(version):
    dist = ROOT / "out/dist"
    if not dist.resolve().is_relative_to(ROOT.resolve() / "out"):
        raise ValueError("build directory escapes this worktree")
    path = dist / (PREFIX+str(version)+".gma")
    if path.is_symlink() or path.resolve().parent != dist.resolve() or getattr(path.lstat(), "st_file_attributes", 0) & 0x400:
        raise ValueError("package is not an owned plain file")
    summary = read(path.with_suffix(".json"))
    digest = checksum(path)
    if summary["version"] != "0.0.0-v4c."+str(version) or summary["gma_sha256"] != digest or summary["gma_bytes"] != path.stat().st_size:
        raise ValueError("package differs from C's build receipt; retaining it")
    return path, digest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--evidence", type=Path, required=True)
    parser.add_argument("--versions", type=int, nargs="+", default=[])
    parser.add_argument("--fixture-bulk", nargs="+", choices=("sim-02", "sim-03"), default=[])
    parser.add_argument("--execute", action="store_true")
    args = parser.parse_args()
    branch = subprocess.check_output(["git", "branch", "--show-current"], cwd=ROOT, text=True).strip()
    if branch != "v4c":
        raise ValueError("C build cleanup is restricted to branch v4c")
    evidence = args.evidence.resolve()
    evidence.relative_to(ROOT / "out/vr/v4c")
    if not read(evidence / "summary.json")["success"] or not read(evidence / "restoration.json")["clean"]:
        raise ValueError("requires a successful PoC run with verified restoration")
    witness = Path(read(evidence / "sources.json")["package"])
    match = re.fullmatch(re.escape(PREFIX)+r"(\d+)\.gma", witness.name)
    if not match or witness.resolve().parent != (ROOT / "out/dist").resolve():
        raise ValueError("the witness is not C's production package")
    newer = int(match[1])
    verified(newer)
    plans = []
    for version in sorted(set(args.versions)):
        if not 0 < version < newer:
            raise ValueError("only strictly older C versions may be removed")
        path, digest = verified(version)
        plans.append({"path": str(path), "sha256": digest, "bytes": path.stat().st_size, "version": version})
    for name in args.fixture_bulk:
        old = ROOT / "out/vr/v4c" / name
        package = old.with_name(name+"-fixture") / "package"
        if not read(old / "summary.json")["success"] or not read(old / "restoration.json")["clean"]:
            raise ValueError("old fixture has no completed, restored production session")
        if Path(read(old / "sources.json")["package"]).resolve() != package.resolve():
            raise ValueError("fixture is not the package recorded by C's old session")
        manifest = read(package / "native/manifest.json")
        for relative, info in manifest["files"].items():
            if info["size"] < 1024*1024:
                continue
            path = package / relative
            if path.is_symlink() or not path.resolve().is_relative_to(package.resolve()) or getattr(path.lstat(), "st_file_attributes", 0) & 0x400:
                raise ValueError("fixture payload is not an owned plain file")
            if path.stat().st_size != info["size"] or checksum(path) != info["sha256"]:
                raise ValueError("fixture payload was edited; retaining it")
            plans.append({"path": str(path), "sha256": info["sha256"], "bytes": info["size"], "fixture": name})
    receipt = {"newer_witness": str(witness), "evidence": str(evidence), "execute": args.execute, "files": plans}
    stem = "clean-fixture-bulk" if args.fixture_bulk else "clean-builds"
    stem += "-"+("-".join(args.fixture_bulk) if args.fixture_bulk else "v"+"-".join(map(str,sorted(set(args.versions)))))
    target = ROOT / "out/vr/v4c" / (stem+("-executed.json" if args.execute else "-plan.json"))
    target.write_text(json.dumps(receipt, indent=2)+"\n", encoding="utf-8")
    for plan in plans:
        if args.execute:
            if "version" in plan:
                path, digest = verified(plan["version"])
            else:
                path=Path(plan["path"])
                digest=checksum(path)
            if digest != plan["sha256"]:
                raise ValueError("package changed after planning")
            path.unlink()
    print(("Removed" if args.execute else "Verified")+f" {len(plans)} owned C files, {sum(p['bytes'] for p in plans)} bytes; receipts retained")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
