"""Offline vrprobe CLI integration checks: no OpenVR session or VR lock is taken."""
import argparse
import json
import os
from pathlib import Path
import subprocess
import tempfile


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--probe', required=True, type=Path)
    parser.add_argument('--scratch', required=True, type=Path)
    args = parser.parse_args()
    args.scratch.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix='cli-', dir=args.scratch) as scratch:
        root = Path(scratch)
        env = dict(os.environ, LOCALAPPDATA=str(root))

        def run(*options):
            return subprocess.run([str(args.probe), *options], env=env, capture_output=True,
                                  text=True, encoding='utf-8', timeout=10, check=False)

        def info():
            result = run('info')
            assert result.returncode == 0, result.stderr
            data = json.loads(result.stdout)
            assert data['openvr_loaded'] is False
            return data

        assert info()['installed'] is False
        runtime = root / 'SteamVR test runtime'
        runtime.mkdir()
        paths = root / 'openvr' / 'openvrpaths.vrpath'
        paths.parent.mkdir()
        paths.write_text(json.dumps({'runtime': [str(runtime)]}), encoding='utf-8')
        data = info()
        assert data['installed'] is True and data['runtime_paths'] == [str(runtime)]
        output = root / 'results' / 'info.json'
        result = run('info', '--out', str(output))
        assert result.returncode == 0 and not result.stdout and not result.stderr
        assert json.loads(output.read_text(encoding='utf-8'))['openvr_loaded'] is False
        paths.write_text(json.dumps({'runtime': []}), encoding='utf-8')
        assert info()['installed'] is False
        paths.write_text('{broken', encoding='utf-8')
        data = info()
        assert data['installed'] is False and data['error']
        result = run('submit', '--dll', 'unused.dll', '--seconds', 'NaN')
        assert result.returncode == 2
        assert json.loads(result.stdout)['phase'] == 'arguments'
        assert not result.stderr  # Argument failure does not load OpenVR or take its lock.
        result = run('--help')
        assert result.returncode == 0 and 'extensions' in result.stdout
    print('7 offline CLI scenarios passed (OpenVR never initialized)')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
