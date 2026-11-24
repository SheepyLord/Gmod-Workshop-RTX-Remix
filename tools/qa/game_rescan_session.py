"""game_rescan_session.py: the RTX fixes' imported game PBR when a model is imported again in the same session (ADR
0263, the user's report of 2026-11-24). In a locked PoC RTX session with the given package, a game-rip character is
imported without its PBR maps beside it, spawned, and ToPBR's view of each of its materials read until it settles; then
the maps are copied into its folder, the same PMX is imported again (the same asset id) and the views are read again.
See game_rescan_session.py.md."""
from __future__ import annotations

import argparse
import contextlib
import fnmatch
import json
import os
import shutil
import subprocess
import sys
import time
from pathlib import Path

TOOLS = Path(__file__).resolve().parents[1]
REPO = TOOLS.parent
sys.path.insert(0, str(TOOLS))
sys.path.insert(0, str(TOOLS / 'qa'))

import poc_session as poc  # noqa: E402
import vr_session as vs  # noqa: E402
import mmd_reimport_session as r12a  # noqa: E402
from mmd_player_session import Lock  # noqa: E402

TASK = 'imported game PBR after a re-import (ADR 0263)'
PROBE = Path(__file__).resolve().with_name('game_rescan_probe.lua')
# The images ToPBR reads as a game's maps (game_matching.inl): a stem ending in one of these.
MAP_SUFFIXES = ('_n', '_hn', '_mra', '_p', '_e', '_id', '_hm')
IMAGES = ('.png', '.bmp', '.tga', '.jpg')
RESCAN_LINE = '[MaterialPipeline::ToPBR] Game maps looked at again'
IMPORTED_LINE = '[MaterialPipeline::ToPBR] Imported game maps:'


def first_json(value: str):
    """The JSON value at the start of a marker line's text. A line the module's worker thread prints can land on the
    same console line, right after the probe's text (seen: "NLRS_IMPORTED {...}[MaterialPipeline::ToPBR] Game maps
    looked at again: ..."), so anything after the value is left out."""
    return json.JSONDecoder().raw_decode(value.lstrip())[0]


def held_back(model: Path, patterns: list[str]) -> list[Path]:
    """The model folder's files the first import must not see: those matching a --hold pattern (relative to the
    folder, fnmatch, any case), or by default every image whose stem ends in a game-map suffix."""
    held = []
    for path in sorted(model.rglob('*')):
        if not path.is_file():
            continue
        rel = path.relative_to(model).as_posix().lower()
        if patterns:
            if any(fnmatch.fnmatch(rel, p.lower()) for p in patterns):
                held.append(path)
        elif path.suffix.lower() in IMAGES and path.stem.lower().endswith(MAP_SUFFIXES):
            held.append(path)
    return held


def prepare_model(source: Path, folder: Path, patterns: list[str]) -> tuple[Path, list[tuple[Path, Path]]]:
    """Copies the model folder into the evidence without its maps; returns the folder and (held copy, its place)."""
    model, held_root = folder / 'model' / source.name, folder / 'held'
    held = held_back(source, patterns)
    skip = {p.resolve() for p in held}
    pairs = []
    for path in sorted(source.rglob('*')):
        if not path.is_file():
            continue
        rel = path.relative_to(source)
        if path.resolve() in skip:
            target = held_root / rel
            pairs.append((target, model / rel))
        else:
            target = model / rel
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copy2(path, target)
    return model, pairs


class Rescan(r12a.Probe):
    """R12-A's console driver (send, Lua through the console, markers read from the session's own console.log)."""

    def wait(self, marker, offset=None, timeout=240):
        start = self.offset if offset is None else offset
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            for line in poc.read_shared(self.log, start).splitlines():
                # Anywhere in the line: the module's worker thread can print into the middle of a console line.
                at = line.find(marker)
                if at >= 0:
                    value = line[at + len(marker):].strip()
                    self.events.append(dict(marker=marker, value=value))
                    print(marker, value[:300], flush=True)
                    return value
                if 'NLRS_ERROR' in line:
                    raise RuntimeError(line)
            if self.session and self.session.poll() is not None:
                raise RuntimeError('owning PoC session ended before ' + marker)
            time.sleep(.25)
        raise RuntimeError('timeout: ' + marker)

    def states(self, asset):
        value = first_json(self.call('NLRS.States(' + json.dumps(asset) + ')', 'NLRS_STATES ', False))
        detail = vs.POC / 'garrysmod/data/nlrescan' / ('states_%03d.json' % value['report'])
        with contextlib.suppress(OSError, ValueError):
            value['detail'] = json.loads(detail.read_text(encoding='utf-8'))
        return value

    def settle(self, asset, limit, steady_for=20):
        """Reads the views every three seconds until their counts and the converting count have not changed for
        `steady_for` seconds with nothing converting, or `limit` seconds have passed."""
        deadline, last, steady, value = time.monotonic() + limit, None, time.monotonic(), None
        while time.monotonic() < deadline:
            value = self.states(asset)
            key = (json.dumps(value.get('counts'), sort_keys=True), value.get('pending'))
            if key != last:
                last, steady = key, time.monotonic()
            elif time.monotonic() - steady >= steady_for and not value.get('pending'):
                value['settled'] = True
                return value
            time.sleep(3)
        if value is not None:
            value['settled'] = False
        return value

    def import_model(self):
        return first_json(self.call('NLRS.Import(' + json.dumps(str(self.source)) + ')', 'NLRS_IMPORTED ', False))['asset']

    def sequence(self, held, settle):
        installed = first_json(self.call(PROBE.read_text(encoding='utf-8'), 'NLRS_INSTALLED ', False))
        # Daylight held still for comparable screenshots (the RTX sky's clock); the probe puts it back at the end.
        for command in ('sv_cheats 1', 'ai_disabled 1', 'engine_no_focus_sleep 0',
                        'nativeloader_sky_time_passes 0', 'nativeloader_sky_time 14'):
            self.send(command)
        asset = self.import_model()
        self.send('setang 35 180 0')
        time.sleep(.4)
        ready = first_json(self.call('NLRS.Spawn(' + json.dumps(asset) + ')', 'NLRS_READY ', False))
        self.lua('NLRS.View(' + str(ready['index']) + ')', False)
        before = self.settle(asset, settle)
        self.shot('01-no-maps')
        # The player copies the maps into the model's folder, then imports the same PMX again.
        for held_copy, place in held:
            place.parent.mkdir(parents=True, exist_ok=True)
            shutil.copy2(held_copy, place)
        at = self.log.stat().st_size
        again = self.import_model()
        after = self.settle(asset, settle)
        self.shot('02-after-reimport')
        text = poc.read_shared(self.log, at)
        return dict(installed=installed, asset=asset, again=again, same_asset=again == asset, maps_copied=len(held),
                    before=before, after=after, rescan_lines=text.count(RESCAN_LINE),
                    imported_lines=text.count(IMPORTED_LINE))


def judge(summary: dict, expect_none: bool) -> list[str]:
    """Why the run does not show what it must (empty: it passes). By default the fix: no maps at first, the same asset
    again, the rescan line, then imported maps. With expect_none, the old behaviour: no maps after the import either."""
    reasons = []
    before = (summary.get('before') or {}).get('counts') or {}
    after = (summary.get('after') or {}).get('counts') or {}
    if not summary.get('same_asset'):
        reasons.append('the second import gave another asset id')
    if before.get('automatic'):
        reasons.append(f'{before["automatic"]} material(s) had game maps before they were copied')
    if not (summary.get('before') or {}).get('settled'):
        reasons.append('the views did not settle before the maps were copied')
    if expect_none:
        if after.get('automatic'):
            reasons.append(f'{after["automatic"]} material(s) got game maps (expected none, the old behaviour)')
    else:
        if not after.get('automatic'):
            reasons.append('no material got game maps after the import')
        if not summary.get('rescan_lines'):
            reasons.append('no "Game maps looked at again" line after the import')
        if not summary.get('imported_lines'):
            reasons.append('no "Imported game maps" line after the import')
    return reasons


def launch(probe: Rescan) -> None:
    env = dict(os.environ, TEMP=str(REPO / 'out/tmp'), TMP=str(REPO / 'out/tmp'))
    command = [sys.executable, str(TOOLS / 'poc_session.py'), '--evidence', str(probe.out / 'poc'), 'run', '--name',
               'game', '--addons', '--map', 'gm_construct', '--width', '1600', '--height', '900', '--settle', '0',
               '--screenshots', '0', '--lua-shots', '2400', '--console', 'sv_cheats 1', '--timeout', '900',
               '--hang-grace', '600']
    with (probe.out / 'owner.log').open('w', encoding='utf8') as output:
        probe.session = subprocess.Popen(command, cwd=REPO, env=env, stdout=output, stderr=subprocess.STDOUT)
    probe.wait('Clientside Lua startup!', 0, timeout=900)
    probe.quiet()
    probe.offset = 0


def finish(probe: Rescan) -> None:
    if probe.session and probe.session.poll() is None:
        with contextlib.suppress(RuntimeError):
            probe.call('if NLRS and NLRS.Restore then NLRS.Restore() end', 'NLRS_RESTORED', False)
        try:
            probe.lua('print("NL_SHOT_DONE")', False)
        except RuntimeError:
            with contextlib.suppress(RuntimeError):
                probe.send('quit')
        probe.session.wait(timeout=240)


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--evidence', type=Path, required=True, help='a new folder under this repository\'s out')
    parser.add_argument('--package', type=Path, help='the RTX package (.gma) to deploy')
    parser.add_argument('--model', type=Path, help='a game-rip character\'s folder (copied; never changed)')
    parser.add_argument('--pmx', default='', help='the PMX inside --model (default: the only one, or the largest)')
    parser.add_argument('--hold', action='append', default=[],
                        help='files the first import must not see, relative to --model, fnmatch (repeatable; default: '
                             'every image whose stem ends in _n, _hn, _mra, _p, _e, _id or _hm)')
    parser.add_argument('--settle', type=int, default=240, help='seconds each reading may take to settle')
    parser.add_argument('--expect-none', action='store_true', help='judge the old behaviour (a package before the fix)')
    parser.add_argument('--lock-timeout', type=int, default=6 * 3600)
    parser.add_argument('--keep-copies', action='store_true')
    parser.add_argument('--rollback', action='store_true', help='restore the PoC after an interrupted run')
    args = parser.parse_args(argv)
    main_root = vs.main_checkout()
    evidence = vs.inside_out(args.evidence, main_root)
    if not args.rollback:
        if not args.package or not args.package.is_file():
            parser.error('--package must name a built .gma')
        if not args.model or not args.model.is_dir():
            parser.error('--model must name a model folder')
    with contextlib.ExitStack() as stack:
        stack.enter_context(Lock(main_root / 'out/r10/poc.lock', TASK, timeout=args.lock_timeout))
        if args.rollback:
            if poc.game_processes(vs.POC):
                raise RuntimeError('the PoC still runs')
            vs.restore(vs.POC, evidence)
            if not args.keep_copies:
                vs.cleanup(evidence)
            return 0
        if evidence.exists() and any(evidence.iterdir()):
            raise ValueError('use a new evidence folder; --rollback recovers an interrupted run')
        evidence.mkdir(parents=True, exist_ok=True)
        model, held = prepare_model(args.model.resolve(), evidence, args.hold)
        pmxs = sorted(model.glob('*.pmx'), key=lambda p: p.stat().st_size, reverse=True)
        pmx = model / args.pmx if args.pmx else (pmxs[0] if pmxs else None)
        if not pmx or not pmx.is_file():
            raise ValueError('no PMX in the model folder')
        if not held:
            raise ValueError('nothing to hold back: the first import would see the maps')
        if poc.game_processes(vs.POC):
            raise RuntimeError('a game is already running in the PoC')
        protected = {str(p): vs.sha256(p) for p in vs.POC.rglob('user.conf')}
        registry = r12a.video_settings()
        vs.write_json(evidence / 'plan.json', {'args': {k: str(v) for k, v in vars(args).items()},
                                               'package_sha256': vs.sha256(args.package), 'pmx': pmx.name,
                                               'held': [str(place.relative_to(model)) for _, place in held]})
        vs.command(['tools/field_snapshot.py', '--snapshot', evidence / 'snapshot', 'snapshot', '--root', vs.POC,
                    '--manifests-from', vs.FIELD], evidence, 'snapshot')
        summary, reasons = None, ['the run did not finish']
        probe = Rescan(evidence, pmx, True)
        try:
            vs.preserve(vs.POC, evidence)
            vs.command(['tools/poc_session.py', '--evidence', evidence / 'poc', 'install', '--allow-local',
                        args.package.resolve(), '--remix', 'on', '--replace-config'], evidence, 'install')
            vs.write_json(evidence / 'field-games.json', r12a.end_field_games())
            log = vs.POC / 'garrysmod/console.log'
            if log.exists():
                log.rename(evidence / 'console-before.log')  # not read: only this run's lines count
            launch(probe)
            summary = probe.sequence(held, args.settle)
            reasons = judge(summary, args.expect_none)
        finally:
            finish(probe)
            log = vs.POC / 'garrysmod/console.log'
            if log.exists():
                shutil.copy2(log, evidence / 'console.log')
            results = vs.POC / 'garrysmod/data/nlrescan'
            if results.is_dir():
                shutil.copytree(results, evidence / 'results', dirs_exist_ok=True)
            vs.write_json(evidence / 'events.json', probe.events)
            if not poc.game_processes(vs.POC) and (evidence / 'originals.json').exists():
                vs.restore(vs.POC, evidence)
            r12a.restore_video_settings(registry)
            if any(vs.sha256(Path(p)) != digest for p, digest in protected.items()):
                raise RuntimeError('protected user.conf hash changed')
        verdict = 'FAIL' if reasons else 'PASS'
        vs.write_json(evidence / 'summary.json', {'verdict': verdict, 'reasons': reasons, 'summary': summary})
        if not args.keep_copies:
            vs.cleanup(evidence)
    before = (summary or {}).get('before') or {}
    after = (summary or {}).get('after') or {}
    print(f'{verdict}' + (f' ({"; ".join(reasons)})' if reasons else '') +
          f'; before: {before.get("counts")} settled {before.get("settled")}; after: {after.get("counts")} settled'
          f' {after.get("settled")}; same asset {(summary or {}).get("same_asset")}; rescan lines'
          f' {(summary or {}).get("rescan_lines")}, imported lines {(summary or {}).get("imported_lines")}')
    return 1 if reasons else 0


if __name__ == '__main__':
    raise SystemExit(main())
