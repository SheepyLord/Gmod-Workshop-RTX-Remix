"""authored_mod_session.py: an authored Remix mod in the RTX Remix Toolkit's packaged format applies under the
package, with ToPBR off and on (GitHub issue 14, "Custom RTX weapon files no longer applying to material hash after
ToPBR update"). In a locked PoC RTX session with the given package: launch 1 reads the Remix texture hashes of the
crowbar's view model and two frozen props and takes a screenshot; two test mods are written into the PoC's
rtx-remix/mods; launch 2 loads them from the start, takes a screenshot, turns ToPBR on at scope 2 (everything it can
convert) and takes another. See authored_mod_session.py.md."""
from __future__ import annotations

import argparse
import contextlib
import json
import os
import re
import shutil
import struct
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

TASK = 'authored Remix mods under the package (GitHub issue 14)'
PROBE = Path(__file__).resolve().with_name('authored_mod_probe.lua')
BARREL = 'models/props_c17/oildrum001.mdl'
CRATE = 'models/props_junk/wood_crate001a.mdl'
TOOLKIT, CONTROL = 'nlam_toolkit', 'nlam_control'

# Server Lua: the crowbar in hand, a barrel and a crate frozen on the ground ahead, the view held still.
SPAWN = r'''
local p = Entity(1)
p:Give("weapon_crowbar") p:SelectWeapon("weapon_crowbar")
local ang = Angle(0, p:EyeAngles().y, 0)
local base = p:GetPos() + ang:Forward() * 120
local function spawn(model, side)
    local pos = base + ang:Right() * side
    local tr = util.TraceLine({ start = pos + Vector(0, 0, 60), endpos = pos - Vector(0, 0, 300), filter = p })
    local e = ents.Create("prop_physics")
    e:SetModel(model) e:SetPos(tr.HitPos) e:SetAngles(Angle(0, ang.y + 180, 0)) e:Spawn()
    e:SetPos(tr.HitPos - Vector(0, 0, e:OBBMins().z))
    local ph = e:GetPhysicsObject() if IsValid(ph) then ph:EnableMotion(false) end
    return e:EntIndex()
end
local a, b = spawn("%s", -30), spawn("%s", 30)
p:SetEyeAngles(Angle(24, ang.y, 0))
p:Lock()
print("NLAM_SPAWNED " .. util.TableToJSON({ a = a, b = b }))
''' % (BARREL, CRATE)

TOOLKIT_INPUT = '''                asset inputs:{name} = @./assets/ingested/{file}@ (
                    colorSpace = "auto"
                    customData = {{
                        asset default = @@
                    }}
                    displayGroup = "Base Material"
                    displayName = "{label}"
                    hidden = false
                    renderType = "texture_2d"
                )
'''
MOD_LOAD = re.compile(r'\[RTX Mod Load\] mod=(\S+) .*?\bmaterials=(\d+) .*?\btextures=(\d+)')


def first_json(value: str):
    """The JSON value at the start of a marker line's text (a native thread's line can follow it on the same line)."""
    return json.JSONDecoder().raw_decode(value.lstrip())[0]


def norm(value) -> str | None:
    """A Remix texture hash as the 16 upper-case hex digits of a mat_ prim name."""
    if not isinstance(value, str) or not value.strip():
        return None
    text = value.strip().upper()
    text = text[2:] if text.startswith('0X') else text
    return text.zfill(16) if len(text) <= 16 and all(c in '0123456789ABCDEF' for c in text) else None


def dds_rgba(path: Path, rgba: tuple[int, int, int, int], size: int = 4) -> None:
    """An uncompressed DX10 DDS (R8G8B8A8_UNORM, one mip) of one colour."""
    header = struct.pack('<4s7I44x', b'DDS ', 124, 0x1 | 0x2 | 0x4 | 0x8 | 0x1000, size, size, size * 4, 0, 1)
    pixelformat = struct.pack('<2I4s5I', 32, 0x4, b'DX10', 0, 0, 0, 0, 0)
    caps = struct.pack('<5I', 0x1000, 0, 0, 0, 0)
    dx10 = struct.pack('<5I', 28, 3, 0, 1, 0)
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_bytes(header + pixelformat + caps + dx10 + bytes(rgba) * (size * size))


def toolkit_mod(folder: Path, hashes: list[str]) -> str:
    """The issue's format: over-only prims, no sourceAsset and no albedo, metallic/normal/roughness *.a.rtex.dds maps.
    Metallic 1 and roughness near 0 turn a surface into dark mirror metal, which a screenshot shows at once."""
    dds_rgba(folder / 'assets/ingested/nlam_m.a.rtex.dds', (255, 255, 255, 255))
    dds_rgba(folder / 'assets/ingested/nlam_n.a.rtex.dds', (128, 128, 255, 255))
    dds_rgba(folder / 'assets/ingested/nlam_r.a.rtex.dds', (8, 8, 8, 255))
    inputs = ''.join(TOOLKIT_INPUT.format(name=n, file=f, label=l) for n, f, l in (
        ('metallic_texture', 'nlam_m.a.rtex.dds', 'Metallic Map'),
        ('normalmap_texture', 'nlam_n.a.rtex.dds', 'Normal Map'),
        ('reflectionroughness_texture', 'nlam_r.a.rtex.dds', 'Roughness Map')))
    body = ''.join(f'        over "mat_{h}"\n        {{\n            over "Shader"\n            {{\n{inputs}'
                   f'            }}\n        }}\n' for h in hashes)
    text = ('#usda 1.0\n(\n    customLayerData = {\n        dictionary remix_metadata = {\n'
            '            bool remix_replacement = 1\n        }\n    }\n    upAxis = "Z"\n)\n\n'
            'over "RootNode"\n{\n    over "Looks"\n    {\n' + body + '    }\n}\n')
    (folder / 'mod.usda').write_text(text, encoding='utf-8', newline='\n')
    return text


def control_mod(folder: Path, hashes: list[str]) -> str:
    """The format rpai writes (sourceAsset given), with a red albedo."""
    dds_rgba(folder / 'textures/red.dds', (255, 0, 0, 255))
    dds_rgba(folder / 'textures/rough.dds', (128, 128, 128, 255))
    body = ''.join(f'''        over "mat_{h}"
        {{
            over "Shader"
            {{
                uniform asset info:mdl:sourceAsset = @AperturePBR_Opacity.mdl@
                uniform token info:mdl:sourceAsset:subIdentifier = "AperturePBR_Opacity"
                asset inputs:diffuse_texture = @./textures/red.dds@
                asset inputs:reflectionroughness_texture = @./textures/rough.dds@
            }}
        }}
''' for h in hashes)
    text = ('#usda 1.0\n(\n    upAxis = "Z"\n)\n\nover "RootNode"\n{\n    over "Looks"\n    {\n' + body
            + '    }\n}\n')
    (folder / 'mod.usda').write_text(text, encoding='utf-8', newline='\n')
    return text


class Probe(r12a.Probe):
    """R12-A's console driver; markers are found anywhere in a console line."""

    def wait(self, marker, offset=None, timeout=240):
        start = self.offset if offset is None else offset
        deadline = time.monotonic() + timeout
        while time.monotonic() < deadline:
            for line in poc.read_shared(self.log, start).splitlines():
                at = line.find(marker)
                if at >= 0:
                    value = line[at + len(marker):].strip()
                    self.events.append(dict(marker=marker, value=value))
                    print(marker, value[:300], flush=True)
                    return value
            if self.session and self.session.poll() is not None:
                raise RuntimeError('owning PoC session ended before ' + marker)
            time.sleep(.25)
        raise RuntimeError('timeout: ' + marker)


def launch(probe: Probe, name: str) -> None:
    env = dict(os.environ, TEMP=str(REPO / 'out/tmp'), TMP=str(REPO / 'out/tmp'))
    command = [sys.executable, str(TOOLS / 'poc_session.py'), '--evidence', str(probe.out / ('poc-' + name)), 'run',
               '--name', name, '--addons', '--map', 'gm_construct', '--width', '1600', '--height', '900', '--settle',
               '0', '--screenshots', '0', '--lua-shots', '2400', '--console', 'sv_cheats 1', '--timeout', '900',
               '--hang-grace', '600']
    if probe.log.exists():
        probe.log.rename(probe.out / f'console-before-{name}.log')  # not read: only this run's lines count
    with (probe.out / f'owner-{name}.log').open('w', encoding='utf8') as output:
        probe.session = subprocess.Popen(command, cwd=REPO, env=env, stdout=output, stderr=subprocess.STDOUT)
    probe.offset = 0
    probe.wait('Clientside Lua startup!', 0, timeout=900)
    probe.quiet()
    probe.offset = 0


def setup(probe: Probe) -> dict:
    first_json(probe.call(PROBE.read_text(encoding='utf-8'), 'NLAM_INSTALLED ', False))
    for command in ('sv_cheats 1', 'ai_disabled 1', 'nativeloader_sky_time_passes 0', 'nativeloader_sky_time 14',
                    'setang 12 180 0'):
        probe.send(command)
    time.sleep(.5)
    spawned = first_json(probe.call(SPAWN, 'NLAM_SPAWNED ', True))
    time.sleep(8)  # the props and the view model drawn, their textures uploaded
    return spawned


def shot(probe: Probe, label: str) -> None:
    probe.call('NLAM.CloseUI()', 'NLAM_CLOSED ', False)
    time.sleep(3)
    probe.shot(label)


def end(probe: Probe, name: str) -> None:
    if probe.session and probe.session.poll() is None:
        try:
            probe.lua('print("NL_SHOT_DONE")', False)
        except RuntimeError:
            with contextlib.suppress(RuntimeError):
                probe.send('quit')
        probe.session.wait(timeout=240)
    if probe.log.exists():
        shutil.copy2(probe.log, probe.out / f'console-{name}.log')
    remix = vs.POC / 'rtx-remix/logs/remix-dxvk.log'
    if remix.exists():
        shutil.copy2(remix, probe.out / f'remix-dxvk-{name}.log')


def mod_loads(text: str) -> dict:
    """[RTX Mod Load] lines by mod: materials and textures walked at the mod's first load (runtime patch 0086)."""
    return {m.group(1): {'materials': int(m.group(2)), 'textures': int(m.group(3))} for m in MOD_LOAD.finditer(text)}


def judge(summary: dict) -> list[str]:
    """Why the run does not show that the authored mods load and keep their materials (empty: it passes)."""
    reasons = []
    toolkit, control = summary.get('toolkit_hashes') or [], summary.get('control_hashes') or []
    loads = summary.get('mod_loads') or {}
    if not toolkit or not control:
        reasons.append('no texture hashes to write the test mods for')
    if loads.get(TOOLKIT, {}).get('materials') != len(toolkit) or loads.get(TOOLKIT, {}).get('textures') != 3 * len(toolkit):
        reasons.append(f'{TOOLKIT} did not load its {len(toolkit)} materials and their maps: {loads.get(TOOLKIT)}')
    if loads.get(CONTROL, {}).get('materials') != len(control):
        reasons.append(f'{CONTROL} did not load its {len(control)} materials: {loads.get(CONTROL)}')
    if summary.get('worker_failures'):
        reasons.append(f'{summary["worker_failures"]} USD mod worker failure(s) in the Remix log')
    covered = [h for h, present in (summary.get('topbr_has') or {}).items() if present]
    if covered:
        reasons.append('ToPBR published materials for authored hashes: ' + ', '.join(covered))
    return reasons


def main(argv=None) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--evidence', type=Path, required=True, help='a new folder under this repository\'s out')
    parser.add_argument('--package', type=Path, help='the RTX package (.gma) to deploy')
    parser.add_argument('--topbr-wait', type=int, default=90, help='seconds ToPBR runs at scope 2 before the last shot')
    parser.add_argument('--lock-timeout', type=int, default=6 * 3600)
    parser.add_argument('--keep-copies', action='store_true')
    parser.add_argument('--rollback', action='store_true', help='restore the PoC after an interrupted run')
    args = parser.parse_args(argv)
    main_root = vs.main_checkout()
    evidence = vs.inside_out(args.evidence, main_root)
    if not args.rollback and (not args.package or not args.package.is_file()):
        parser.error('--package must name a built .gma')
    summary, reasons = {}, ['the run did not finish']
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
        if poc.game_processes(vs.POC):
            raise RuntimeError('a game is already running in the PoC')
        protected = {str(p): vs.sha256(p) for p in vs.POC.rglob('user.conf')}
        registry = r12a.video_settings()
        vs.write_json(evidence / 'plan.json', {'args': {k: str(v) for k, v in vars(args).items()},
                                               'package_sha256': vs.sha256(args.package)})
        vs.command(['tools/field_snapshot.py', '--snapshot', evidence / 'snapshot', 'snapshot', '--root', vs.POC,
                    '--manifests-from', vs.FIELD], evidence, 'snapshot')
        probe = Probe(evidence, None, True)
        try:
            vs.preserve(vs.POC, evidence)
            vs.command(['tools/poc_session.py', '--evidence', evidence / 'poc', 'install', '--allow-local',
                        args.package.resolve(), '--remix', 'on', '--replace-config'], evidence, 'install')
            summary['field_games'] = r12a.end_field_games()
            launch(probe, 'base')
            spawned = setup(probe)
            hashes = first_json(probe.call(f'NLAM.Hashes({spawned["a"]}, {spawned["b"]})', 'NLAM_HASHES ', False))
            summary['hashes'] = hashes
            shot(probe, '01-base')
            end(probe, 'base')
            vm = [norm(m.get('hash')) for m in (hashes.get('viewmodel') or {}).get('materials', [])]
            props = hashes.get('props') or [{}, {}]
            barrel = [norm(m.get('hash')) for m in props[0].get('materials', [])]
            crate = [norm(m.get('hash')) for m in props[1].get('materials', [])]
            toolkit = sorted({h for h in vm + barrel if h})
            control = sorted({h for h in crate if h} - set(toolkit))
            summary['toolkit_hashes'], summary['control_hashes'] = toolkit, control
            if not toolkit or not control:
                raise RuntimeError('no hashes to write: ' + json.dumps(hashes)[:400])
            mods = vs.POC / 'rtx-remix/mods'
            toolkit_mod(mods / TOOLKIT, toolkit)
            control_mod(mods / CONTROL, control)
            shutil.copytree(mods / TOOLKIT, evidence / 'mods' / TOOLKIT)
            shutil.copytree(mods / CONTROL, evidence / 'mods' / CONTROL)
            launch(probe, 'mods')
            setup(probe)
            shot(probe, '02-mods-topbr-off')
            for command in ('rtx_topbr_scope 2', 'rtx_topbr_enabled 1'):
                probe.send(command)
            time.sleep(args.topbr_wait)
            shot(probe, '03-mods-topbr-on')
            topbr = mods / '~gmod_topbr/materials.usda'
            if topbr.exists():
                shutil.copy2(topbr, evidence / 'topbr-materials.usda')
                text = topbr.read_text(encoding='utf-8', errors='replace')
                summary['topbr_has'] = {h: f'mat_{h}' in text for h in toolkit + control}
            for command in ('rtx_topbr_enabled 0', 'rtx_topbr_scope 0'):
                probe.send(command)
            end(probe, 'mods')
            remix = (evidence / 'remix-dxvk-mods.log').read_text(encoding='utf-8', errors='replace')
            summary['mod_loads'] = mod_loads(remix)
            summary['worker_failures'] = remix.count('USD mod worker failed')
            reasons = judge(summary)
        finally:
            with contextlib.suppress(Exception):
                end(probe, 'last')
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
    loads = summary.get('mod_loads') or {}
    print(f'{verdict}' + (f' ({"; ".join(reasons)})' if reasons else '') +
          f'; {TOOLKIT}: {loads.get(TOOLKIT)}; {CONTROL}: {loads.get(CONTROL)}; ToPBR on authored hashes: '
          f'{summary.get("topbr_has")}')
    return 1 if reasons else 0


if __name__ == '__main__':
    raise SystemExit(main())
