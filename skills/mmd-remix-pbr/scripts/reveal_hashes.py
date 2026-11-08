"""Show a spawned model's hidden parts, run `rpai hashes`, then put the visibility back exactly.

Remix reports a texture's hash only once the game has drawn it, so parts hidden by their bodygroup
(outfit layers, toggled accessories) keep predicted hashes, which are often wrong. This shows every
hidden part of every spawned copy through Model Hotloader's own API, waits for the draws, runs
`rpai hashes` (the predicted hashes of those parts become live), then hides exactly those parts again
and checks the visibility matches what it was.

    python reveal_hashes.py [--game-root <GarrysMod>] [--settle 8] <asset id8> <material count> <pmx> [rpai options]

    python reveal_hashes.py --game-root H:\\SteamLibrary\\steamapps\\common\\GarrysMod 32c908bc 76 "E:\\...\\x.pmx"
    python reveal_hashes.py 19c0edc5 83 "<pmx>" --asset 19c0edc5      # extra options go to rpai hashes

<material count> is the PMX's material count (`classes.json` lists them; rpai prints it). Parts that a
material morph hides, and painted shadows the companion leaves out of the draw in RTX sessions
(nativeloader_hide_painted_shadows), stay undrawn: they keep their predicted hashes.

Restores only the parts it showed, also when rpai fails. Exit codes: 0 done and restored exactly,
1 the visibility differs afterwards or a step failed, 2 bad command line.
"""
from __future__ import annotations

import argparse
import os
import subprocess
import sys
import time
from pathlib import Path

HERE = Path(__file__).resolve().parent
TOOL = HERE.parent / "tool"
sys.path.insert(0, str(HERE))
import abtest  # noqa: E402


def main(argv: list[str] | None = None) -> int:
    if hasattr(sys.stdout, "reconfigure"):
        sys.stdout.reconfigure(encoding="utf-8")
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--game-root", type=Path, help="Garry's Mod folder of the game to use (default: the first running)")
    p.add_argument("--settle", type=float, default=8.0, help="seconds to let the shown parts draw (default 8)")
    p.add_argument("asset", help="Model Hotloader asset id or prefix of the spawned model")
    p.add_argument("count", type=int, help="the PMX's material count")
    p.add_argument("pmx", help="the PMX path, as for rpai")
    p.add_argument("extra", nargs=argparse.REMAINDER, help="further options for rpai hashes (such as --asset)")
    a = p.parse_args(argv)
    abtest.GAME_ROOT = a.game_root
    b = abtest.bridge()
    before = abtest.visibility(b, a.asset, list(range(a.count)))
    hidden = [[i for i, v in row.items() if not v] for row in before]
    print("hidden parts per copy:", hidden, flush=True)
    rpai_python = Path(os.environ.get("RPAI_HOME", Path.home() / ".rpai")) / "venv" / "Scripts" / "python.exe"
    command = [str(rpai_python if rpai_python.is_file() else Path(sys.executable)), "-m", "rpai", "hashes", a.pmx]
    if a.game_root:
        command += ["--game-root", str(a.game_root)]
    try:
        abtest.set_visible(b, a.asset, hidden, True)
        time.sleep(a.settle)
        env = {**os.environ, "PYTHONPATH": str(TOOL), "PYTHONIOENCODING": "utf-8"}
        r = subprocess.run(command + list(a.extra), capture_output=True, text=True, encoding="utf-8", env=env,
                           cwd=str(TOOL))
        print("\n".join(line for line in r.stdout.splitlines()
                        if any(word in line for word in ("predicted", "agreed", "not drawn", "live"))))
        if r.returncode:
            print(r.stderr.strip(), file=sys.stderr)
    finally:
        abtest.set_visible(b, a.asset, hidden, False)
        after = abtest.visibility(b, a.asset, list(range(a.count)))
        print("restored exactly:", after == before, flush=True)
    return 0 if after == before and not r.returncode else 1


if __name__ == "__main__":
    sys.exit(main())
