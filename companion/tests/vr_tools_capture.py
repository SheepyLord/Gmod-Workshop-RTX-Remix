"""Independent drawn-beam/model/capture checks for the T evidence reader."""
import json
import math
import struct


def centre_tangents(eyes):
    # Frozen selected runtime: union at infinity and the fixed 0.4 m projection bound.
    tx = ty = 0.0
    for eye in eyes:
        m = eye["eyeToHead"]
        for x in (eye["tanLeft"], eye["tanRight"]):
            for y in (eye["tanTop"], eye["tanBottom"]):
                ray = [m[i][0] * x - m[i][1] * y - m[i][2] for i in range(3)]
                if ray[2] >= -0.01:
                    raise ValueError("invalid eye ray")
                tx, ty = max(tx, abs(ray[0] / ray[2])), max(ty, abs(ray[1] / ray[2]))
                t = (-0.4 - m[2][3]) / ray[2]
                tx, ty = max(tx, abs((m[0][3] + t * ray[0]) / 0.4)), max(ty, abs((m[1][3] + t * ray[1]) / 0.4))
    return tx, ty


def project(point, camera, eyes, size):
    from vr_tools_check import vector, basis
    d = [a - b for a, b in zip(vector(point), vector(camera["origin"]))]
    forward, right, up = basis(camera["angles"])
    depth = sum(a * b for a, b in zip(d, forward))
    if depth <= 0:
        return None
    tx, ty = centre_tangents(eyes)
    return ((0.5 + sum(a * b for a, b in zip(d, right)) / depth / tx / 2) * size[0],
            (0.5 - sum(a * b for a, b in zip(d, up)) / depth / ty / 2) * size[1])


def visible_start(directory, row, camera, size, muzzle, endpoint):
    """Find the first unoccluded point using the captured opaque view-depth buffer."""
    from PIL import Image
    from vr_tools_check import vector, basis
    with Image.open(directory / "centre_depth.png") as depth_image:
        width, height = depth_image.size
    depth = (directory / "centre_depth.f32").read_bytes()
    if len(depth) != width * height * 4:
        raise ValueError("truncated centre depth capture")
    forward = basis(camera["angles"])[0]
    z = [sum((v - o) * f for v, o, f in zip(vector(row[key]), vector(camera["origin"]), forward))
         for key in ("model_muzzle", "endpoint")]
    length, consecutive = math.dist(muzzle, endpoint), 0
    for along in range(math.ceil(length * 0.95)):
        t = along / length
        pixel = [muzzle[i] + (endpoint[i] - muzzle[i]) * t for i in range(2)]
        x, y = int(pixel[0] * width / size[0]), int(pixel[1] * height / size[1])
        if not (0 <= x < width and 0 <= y < height):
            consecutive = 0
            continue
        # Captured depth is signed axial depth in Source units, at internal resolution.
        surface = abs(struct.unpack_from("<f", depth, (y * width + x) * 4)[0])
        beam_depth = 1 / ((1 - t) / z[0] + t / z[1])
        if math.isfinite(surface) and surface >= beam_depth - 0.4:
            consecutive += 1
            if consecutive == 1:
                first = pixel, along
            if consecutive == 3:
                return first
        else:
            consecutive = 0
    return None, None


def image_beam(image, muzzle, endpoint, occluded, render_size):
    """Fit captured beam pixels; never read the production draw-start argument."""
    if occluded is None:
        return {}
    length = math.dist(muzzle, endpoint)
    direction = [(endpoint[i] - muzzle[i]) / length for i in range(2)]
    normal = [-direction[1], direction[0]]

    def luminous(along, across):
        x, y = [round(muzzle[i] + direction[i] * along + normal[i] * across) for i in range(2)]
        if not (0 <= x < image.width and 0 <= y < image.height):
            return 0
        r, g, b = image.getpixel((x, y))
        return max(r, g, b) if ((g > 180 and b > 190 and r > 100 and (g > r + 8 or b > r + 8)) or min(r, g, b) > 240) else 0

    end = min(int(length * 0.8), occluded + 150)
    samples = []
    for along in range(occluded + 8, end + 1):
        pixels = [(across, luminous(along, across)) for across in range(-16, 17)]
        weight = sum(w for _, w in pixels)
        if weight:
            samples.append((along, sum(x * w for x, w in pixels) / weight))
    if len(samples) < 8 or samples[-1][0] - samples[0][0] < 8:
        return {}
    for _ in range(3):
        mean_x = sum(x for x, _ in samples) / len(samples)
        mean_y = sum(y for _, y in samples) / len(samples)
        variance = sum((x - mean_x) ** 2 for x, _ in samples)
        if variance == 0:
            return {}
        slope = sum((x - mean_x) * (y - mean_y) for x, y in samples) / variance
        intercept = mean_y - slope * mean_x
        selected = [(x, y) for x, y in samples if abs(y - intercept - slope * x) <= 2.5]
        if len(selected) < 8:
            return {}
        if len(selected) == len(samples):
            break
        samples = selected
    # Closest point on the image-fitted centreline to the expected attachment.
    # This measures lateral alignment only when opaque gun geometry hides the root.
    across = intercept / (1 + slope * slope)
    along = -slope * across
    root = [muzzle[i] + direction[i] * along + normal[i] * across for i in range(2)]
    first, consecutive = None, 0
    for along in range(end + 1):
        across = intercept + slope * along
        if sum(bool(luminous(along, across + n)) for n in (-1, 0, 1)) >= 2:
            consecutive += 1
            if consecutive == 1:
                first = [muzzle[i] + direction[i] * along + normal[i] * across for i in range(2)]
            if consecutive == 3:
                break
        else:
            consecutive = 0
            first = None
    if consecutive < 3:
        first = None
    expected = [muzzle[i] + direction[i] * occluded for i in range(2)]
    return {"image_line_origin_pixel": root, "image_line_muzzle_error_pixels": math.dist(root, muzzle),
            "image_line_muzzle_error_render_pixels": math.hypot((root[0] - muzzle[0]) * render_size[0] / image.width,
                                                                  (root[1] - muzzle[1]) * render_size[1] / image.height),
            "render_size": render_size,
            "image_visible_start_pixel": first,
            "first_luminous_gap_pixels": math.dist(first, expected) if first else None,
            "image_line_samples": len(samples)}


def accepted(row):
    return (row.get("image_line_muzzle_error_render_pixels") is not None and row["image_line_muzzle_error_render_pixels"] <= 2 and
            row.get("first_luminous_gap_pixels") is not None and row["first_luminous_gap_pixels"] <= 12)


def measure(folder, records, summary):
    captures = [r for r in records if r["name"] == "capture" and r.get("label") in ("tools-roll", "tools-pull") and r.get("ok")]
    observed = {r["frame"]: r for r in records if r["name"] == "beam-draw" and r.get("model_muzzle")}
    result = []
    for capture in captures:
        directory = folder / "captures" / capture["label"]
        timings = directory / "timings.json"
        if not timings.is_file() or not all((directory / name).is_file() for name in ("centre.png", "centre_depth.png", "centre_depth.f32")):
            continue
        seq = json.loads(timings.read_text(encoding="utf-8"))["pose"]
        row = observed.get(seq)
        if not row or not capture.get("camera") or not capture.get("info", {}).get("eyes"):
            continue
        from PIL import Image
        with Image.open(directory / "centre.png") as image:
            image = image.convert("RGB")
            muzzle = project(row["model_muzzle"], capture["camera"], capture["info"]["eyes"], image.size)
            endpoint = project(row["endpoint"], capture["camera"], capture["info"]["eyes"], image.size)
            if not muzzle or not endpoint:
                continue
            length = math.dist(muzzle, endpoint)
            if length < 1:
                continue
            visible, occluded = visible_start(directory, row, capture["camera"], image.size, muzzle, endpoint)
            with Image.open(directory / "centre_depth.png") as depth:
                measured = image_beam(image, muzzle, endpoint, occluded, depth.size)
        result.append({"label": capture["label"], "pose": seq, "model_muzzle_pixel": muzzle,
                       "visible_start_pixel": visible, "occluded_pixels": occluded,
                       **measured, "source": "captured beam pixels versus model projection/opaque depth; draw start unused"})
    return result
