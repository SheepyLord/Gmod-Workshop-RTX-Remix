"""Convert an Unreal toon-shader texture set (Neverness to Everness style) to Remix roughness and metallic maps.

The game has no roughness or metallic map. Its toon material (CoreMaterials/Character/ToonMaterial)
reads, per material instance (the MI_*.json beside the textures):

    BaseColor  T_..._d    the colour (published as it is; rpai upscales it)
    NomralMap  T_..._n    a real tangent-space normal map (used as rpai's per-texture normal_map)
    LightMap   T_..._m    R: specular intensity (0 on skin and flat cloth, peaks on trim)
                          B: specular size, a flat value per material (0 matte fabric, ~70-100 satin
                             cloth, 120-140 gloves, lacquer and accessories); G, A constant 255
    ID_Tex     T_..._id   ramp and matcap selector: red 0 marks skin (where the LightMap is also 0)

From these (measured on Elyms' four outfits, 2026-11-03; the rules are an interpretation, not the
shader's own maths):

    gloss     = clip(B / 0.62, 0, 1);  roughness = 0.78 - 0.60 * gloss - 0.20 * clip(R / 0.40, 0, 1)
              clipped to 0.10-0.85 (matte fabric 0.78, satin cloth ~0.45, gloves and lacquer ~0.2)
    skin      = ID red < 24/255: roughness 0.70, metallic 0 (the standard for skin on a shared sheet)
    metallic  = smoothstep(R, 0.22, 0.36), only where the paint is bright silver (value >= 0.45,
              saturation <= 0.22) or gold (hue 28-55, saturation 0.25-0.75, value >= 0.50);
              dark and coloured glossy parts (gloves, pink and cyan gems) stay dielectric.
              Metal texels get roughness <= 0.30.

    python ue_toon_maps.py --d T_x_d.png --m T_x_m.png --id T_x_id.png --out-dir <dir> --name Clothes_1
        -> <dir>/<name>_rough.png, <dir>/<name>_metal.png (8-bit grey, the size of the LightMap)

Use them as the sheet's "rough_map" / "metal_map" next to its "normal_map" (rpai README, "The game's
own maps"). A set whose LightMap is a default grey (T_Linear_Gray) has nothing to convert: give only
the normal map.
"""
from __future__ import annotations

import argparse
from pathlib import Path

import numpy as np
from PIL import Image
from scipy import ndimage

Image.MAX_IMAGE_PIXELS = None


def smoothstep(x: np.ndarray, lo: float, hi: float) -> np.ndarray:
    t = np.clip((x - lo) / (hi - lo), 0, 1)
    return t * t * (3 - 2 * t)


def hue_deg(rgb: np.ndarray) -> np.ndarray:
    mx, mn = rgb.max(-1), rgb.min(-1)
    c = np.maximum(mx - mn, 1e-6)
    r, g, b = rgb[..., 0], rgb[..., 1], rgb[..., 2]
    h = np.where(mx == r, ((g - b) / c) % 6, np.where(mx == g, (b - r) / c + 2, (r - g) / c + 4))
    return h * 60


def convert(d_path: Path, m_path: Path, id_path: Path) -> dict[str, np.ndarray]:
    m = np.asarray(Image.open(m_path).convert("RGBA")).astype(np.float32) / 255
    size = m.shape[1::-1]

    def load(p: Path, mode: str) -> np.ndarray:
        im = Image.open(p).convert(mode)
        if im.size != size:
            im = im.resize(size, Image.BILINEAR)
        return np.asarray(im).astype(np.float32) / 255

    d = load(d_path, "RGB")
    idt = load(id_path, "RGB")
    R, B = m[..., 0], m[..., 2]
    gloss = np.clip(B / 0.62, 0, 1)
    rough = np.clip(0.78 - 0.60 * gloss - 0.20 * np.clip(R / 0.40, 0, 1), 0.10, 0.85)
    skin = ndimage.gaussian_filter((idt[..., 0] < 24 / 255).astype(np.float32), 1.0)
    mx, mn = d.max(-1), d.min(-1)
    sat = np.where(mx > 0, (mx - mn) / np.maximum(mx, 1e-6), 0)
    hue = hue_deg(d)
    silver = (mx >= 0.45) & (sat <= 0.22)
    gold = (hue >= 28) & (hue <= 55) & (sat >= 0.25) & (sat <= 0.75) & (mx >= 0.50)
    metal = smoothstep(R, 0.22, 0.36) * (silver | gold) * (1 - skin)
    metal = ndimage.gaussian_filter(metal, 0.8)
    rough = np.where(metal > 0.5, np.minimum(rough, 0.30), rough)
    rough = rough * (1 - skin) + 0.70 * skin
    metal = metal * (1 - skin)
    return {"rough": rough, "metal": np.clip(metal, 0, 1), "skin": skin}


def main() -> None:
    p = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    p.add_argument("--d", type=Path, required=True)
    p.add_argument("--m", type=Path, required=True)
    p.add_argument("--id", type=Path, required=True, dest="idmap")
    p.add_argument("--out-dir", type=Path, required=True)
    p.add_argument("--name", required=True)
    a = p.parse_args()
    maps = convert(a.d, a.m, a.idmap)
    a.out_dir.mkdir(parents=True, exist_ok=True)
    for kind in ("rough", "metal"):
        Image.fromarray((maps[kind] * 255 + 0.5).astype(np.uint8), "L").save(a.out_dir / f"{a.name}_{kind}.png", compress_level=1)
    r = maps["rough"]
    print(f"{a.name}: size {r.shape[1]}x{r.shape[0]}, roughness 10/50/90 pct "
          f"{np.percentile(r, 10):.2f}/{np.percentile(r, 50):.2f}/{np.percentile(r, 90):.2f}, "
          f"metal {float((maps['metal'] > 0.5).mean()) * 100:.2f}% of texels, skin {float((maps['skin'] > 0.5).mean()) * 100:.1f}%")


if __name__ == "__main__":
    main()
