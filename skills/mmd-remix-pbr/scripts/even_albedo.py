"""Even out the colour blocks a character's sheet paints on separate UV islands (Linlong's hair, 2026-11-16).

Some game rips paint a strand sheet in large blocks of different tone (cream, pink, orange-brown) on
separate islands. On the mesh they meet with hard edges wherever the hair twists or lies in clumps, and
path tracing shows every one. This makes an evened copy for rpai's ``albedo_source``: in CIELAB the
lightness keeps its fine detail (the sheet minus a wide Gaussian blur) around one main tone, plus a share of
the broad shading; the colour (a*, b*) keeps a share of its fine detail only. The main tone is the median of
the sheets' bright, low-chroma texels (all sheets given together share it). Alpha is kept as it is.

    python even_albedo.py --sheet hair1.png --sheet hair2.png --out-dir <dir>
        [--sigma 28] [--keep-colour 0.35] [--keep-shading 0.15] [--tone L,a,b]

Writes <out-dir>/<stem>_even.png per sheet and even_preview.jpg (each original beside its copy); prints the
main tone and each sheet's broad lightness spread before and after. Documented in even_albedo.py.md.
"""
from __future__ import annotations

import argparse
from pathlib import Path

import numpy as np
from PIL import Image
from scipy.ndimage import gaussian_filter

WHITE = np.array([0.95047, 1.0, 1.08883])
TO_XYZ = np.array([[0.4124564, 0.3575761, 0.1804375], [0.2126729, 0.7151522, 0.0721750],
                   [0.0193339, 0.1191920, 0.9503041]])
TO_RGB = np.array([[3.2404542, -1.5371385, -0.4985314], [-0.9692660, 1.8760108, 0.0415560],
                   [0.0556434, -0.2040259, 1.0572252]])


def srgb_to_lab(rgb: np.ndarray) -> np.ndarray:
    c = rgb / 255.0
    lin = np.where(c <= 0.04045, c / 12.92, ((c + 0.055) / 1.055) ** 2.4)
    xyz = lin @ TO_XYZ.T / WHITE
    f = np.where(xyz > 216 / 24389, np.cbrt(xyz), (24389 / 27 * xyz + 16) / 116)
    return np.stack([116 * f[..., 1] - 16, 500 * (f[..., 0] - f[..., 1]), 200 * (f[..., 1] - f[..., 2])], axis=-1)


def lab_to_srgb(lab: np.ndarray) -> np.ndarray:
    fy = (lab[..., 0] + 16) / 116
    f = np.stack([fy + lab[..., 1] / 500, fy, fy - lab[..., 2] / 200], axis=-1)
    xyz = np.where(f ** 3 > 216 / 24389, f ** 3, (116 * f - 16) / (24389 / 27)) * WHITE
    lin = np.clip(xyz @ TO_RGB.T, 0, 1)
    c = np.where(lin <= 0.0031308, 12.92 * lin, 1.055 * lin ** (1 / 2.4) - 0.055)
    return np.clip(c * 255 + 0.5, 0, 255).astype(np.uint8)


def blur(channel: np.ndarray, sigma: float) -> np.ndarray:
    return gaussian_filter(channel.astype(np.float32), sigma, mode='wrap')


def main(argv=None) -> int:
    ap = argparse.ArgumentParser(description=__doc__.split('\n\n')[0])
    ap.add_argument('--sheet', action='append', required=True, type=Path, help='a sheet to even (repeatable)')
    ap.add_argument('--out-dir', required=True, type=Path)
    ap.add_argument('--sigma', type=float, default=28.0, help='blur radius in texels: wider than a strand, narrower than an island')
    ap.add_argument('--keep-colour', type=float, default=0.35, help='share of the fine a*/b* detail kept')
    ap.add_argument('--keep-shading', type=float, default=0.15, help='share of the broad lightness variation kept')
    ap.add_argument('--tone', help='the main tone as L,a,b (default: measured)')
    args = ap.parse_args(argv)
    args.out_dir.mkdir(parents=True, exist_ok=True)
    labs = {path: srgb_to_lab(np.asarray(Image.open(path).convert('RGB'), dtype=np.float32)) for path in args.sheet}
    if args.tone:
        base = np.array([float(v) for v in args.tone.split(',')])
    else:
        every = np.concatenate([lab.reshape(-1, 3) for lab in labs.values()])
        chroma = np.hypot(every[:, 1], every[:, 2])
        bright = every[(every[:, 0] > np.percentile(every[:, 0], 50)) & (chroma < np.percentile(chroma, 60))]
        base = np.median(bright, axis=0)
    print('main tone L*a*b*', ', '.join(f'{v:.1f}' for v in base))
    previews = []
    for path, lab in labs.items():
        result = np.empty_like(lab)
        broad = blur(lab[..., 0], args.sigma)
        result[..., 0] = base[0] + (lab[..., 0] - broad) + args.keep_shading * (broad - base[0])
        for k in (1, 2):
            result[..., k] = base[k] + args.keep_colour * (lab[..., k] - blur(lab[..., k], args.sigma))
        source = Image.open(path)
        image = Image.fromarray(lab_to_srgb(result), 'RGB')
        image.putalpha(source.getchannel('A') if 'A' in source.getbands() else Image.new('L', source.size, 255))
        target = args.out_dir / f'{path.stem}_even.png'
        image.save(target)
        print(f'{path.name} -> {target}: broad L* spread {broad.std():.1f} -> {blur(result[..., 0], args.sigma).std():.1f}')
        previews += [source.convert('RGB').resize((768, 768)), image.convert('RGB').resize((768, 768))]
    sheet = Image.new('RGB', (768 * len(previews), 768))
    for i, preview in enumerate(previews):
        sheet.paste(preview, (i * 768, 0))
    sheet.save(args.out_dir / 'even_preview.jpg', quality=90)
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
