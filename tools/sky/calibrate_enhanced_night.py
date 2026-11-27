"""Measure the Night sky editor's galaxy band and NUMOS's Gaia background in linear light."""

import argparse
import json
import math
from pathlib import Path
import struct

import numpy as np
from PIL import Image


LUMINANCE = np.array([0.2126, 0.7152, 0.0722])
EDITOR_BRIGHTNESS = 0.12
BAND_SIN_HALF_WIDTH = 0.642788  # evalStarMap's 40-degree half-width
NUMOS_ASSET_SCALE = 1e10


def image_mean(path):
    with Image.open(path) as image:
        if image.format != "DDS" or image.mode != "RGBA":
            raise ValueError("expected the NightSky HD RGBA galaxy DDS")
        summed = np.zeros(3)
        for y in range(0, image.height, 32):
            tile = image.crop((0, y, image.width, min(y + 32, image.height)))
            rgba = np.asarray(tile, dtype=np.float64) / 255
            summed += np.power(rgba[:, :, :3] * rgba[:, :, 3:], 2.2).sum(axis=(0, 1))
        # The three repetitions have the same mean. v is linear in sin(latitude);
        # the band occupies this fraction of the sphere and the rest contributes zero.
        return float(summed @ LUMINANCE) * BAND_SIN_HALF_WIDTH * EDITOR_BRIGHTNESS / (image.width * image.height)


def gaia_mean(path):
    with path.open("rb") as source:
        magic, version, width, height = struct.unpack("<4sIII", source.read(16))
        if magic != b"NMWY" or version != 1 or not width or not height:
            raise ValueError("expected a version 1 NUMOS Milky Way asset")
        if path.stat().st_size != 16 + 4 * width * height:
            raise ValueError("Milky Way dimensions do not match its RGB9E5 payload")
        words = np.fromfile(source, dtype="<u4").reshape(height, width)
    scale = np.exp2((words >> 27).astype(np.float64) - 24) / NUMOS_ASSET_SCALE
    edges = np.cos(np.linspace(0, math.pi, height + 1))
    row_weight = (edges[:-1] - edges[1:]) * 0.5
    return sum(float((((words >> shift) & 511) * scale).mean(axis=1) @ row_weight) * weight
               for shift, weight in zip((0, 9, 18), LUMINANCE))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("galaxy_dds", type=Path)
    parser.add_argument("milkyway_bin", type=Path)
    args = parser.parse_args()
    image = image_mean(args.galaxy_dds)
    if image <= 0:
        parser.error("the image band has zero light")
    gaia = gaia_mean(args.milkyway_bin)
    print(json.dumps({"image_mean": image, "gaia_mean": gaia, "image_scale": gaia / image}, indent=2))


if __name__ == "__main__":
    main()
