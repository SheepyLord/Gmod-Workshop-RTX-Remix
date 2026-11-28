"""Build the two local GF2 character packs for the WU game check. See the adjacent .md."""
import argparse
import hashlib
import json
from pathlib import Path
import subprocess
import sys

REPO = Path(__file__).resolve().parents[2]
SKILL = REPO / "skills/workshop-content-pack/scripts"
sys.path.insert(0, str(SKILL))
import mmdhl_pack


def change_control_manifest(addon, whitespace):
    """Put one trailing JSON whitespace byte in each build, a space in v1 and a tab in v2."""
    base = addon / "data_static/mmdhl"
    package_path, = (base / "packages").glob("*.json")
    package = json.loads(package_path.read_bytes())
    control, = (item for item in package["items"] if item.get("key") == "helena-dorm")
    path = f"assets/{control['asset']}/manifest.json"
    entry = package["files"][path]
    old = base / "files" / (entry["sha256"] + ".dat")
    codec = mmdhl_pack.Codec()
    raw = mmdhl_pack.unpack(codec, old.read_bytes(), entry["size"], entry["sha256"])
    changed = raw + whitespace
    if json.loads(changed) != json.loads(raw):
        raise ValueError("the control manifest changed meaning")
    digest = hashlib.sha256(changed).hexdigest()
    packet = mmdhl_pack.pack(codec, changed, digest)
    if len(changed) > max(mmdhl_pack.EXPANSION_FLOOR, len(packet) * mmdhl_pack.EXPANSION_LIMIT):
        packet = mmdhl_pack.pack(codec, changed, digest, compress=False)
    if mmdhl_pack.unpack(codec, packet, len(changed), digest) != changed:
        raise ValueError("control packet did not round-trip")
    (base / "files" / (digest + ".dat")).write_bytes(packet)
    entry.update(sha256=digest, size=len(changed), packed=len(packet))
    if not any(value["sha256"] + ".dat" == old.name for value in package["files"].values()):
        old.unlink()
    package_path.write_text(json.dumps(package, ensure_ascii=False, separators=(",", ":")), encoding="utf-8")
    print(f"Control manifest: {len(changed)} bytes, {digest}", flush=True)


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("cache", type=Path, help="read-only mmd_hotloader cache containing the two Gym builds and Helena (Dorm)")
    parser.add_argument("--out", type=Path, default=REPO / "out/wsup/fixtures", help="fresh fixture directory under out")
    args = parser.parse_args()
    dest = args.out.resolve()
    if not dest.is_relative_to((REPO / "out").resolve()) or dest.is_relative_to(args.cache.resolve()):
        parser.error("choose a fresh output under the worktree's out directory, outside the input cache")
    dest.mkdir(parents=True, exist_ok=False)
    description = dest / "description.txt"
    description.write_text("Local Workshop character update test.", encoding="ascii")
    for label, asset, version in [("v1", "7c6d7e466389", "1.0.0"), ("v2", "a95c9a34a5ee", "1.1.0")]:
        stage = dest / label
        stage.mkdir()
        addon = stage / "mmdhl_wu_fixture"
        subprocess.run([sys.executable, "-I", str(SKILL / "mmdhl_pack.py"), str(args.cache), asset, str(addon),
                        "Faelynn", "Faelynn (Gym Uniform)", "Local QA", str(description),
                        "--item", "81b3caae0303=Helena (Dorm)", "--model-key", "81b3caae0303=helena-dorm"], check=True)
        change_control_manifest(addon, b" " if label == "v1" else b"\t")
        subprocess.run([sys.executable, "-I", str(REPO / "tools/package_content.py"),
                        "--id", "wu-fixture", "--name", "Faelynn", "--version", version,
                        "--addon", str(addon), "--gma", str(stage / "wu-fixture.gma")], check=True)


if __name__ == "__main__":
    main()
