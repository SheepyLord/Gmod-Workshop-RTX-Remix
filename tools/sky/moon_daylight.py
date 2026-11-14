"""The Moon against the day sky, from the runtime's own formulas (ADR 0207).

Rebuilds, in numpy, what the Remix runtime's physical sky computes for one direction: the
transmittance and multiple-scattering LUTs (transmittance_lut.comp.slang, multiscattering_lut.comp.slang,
same sizes and texel mapping, read bilinearly) and evalAtmosphereRadiance's 32-step march
(atmosphere_common.slangh), with a weather preset's air, aerosol and sun. Against that sky it puts
moon 0 as evalTexturedMoon (atmosphere_sky.slangh) lights it: the sun's illuminance through the
Kasten-Young air mass towards the Moon, times brightness / pi, the near-side mean albedo and the
Lunar-Lambert term, plus earthshine. The sun and the Moon stand where the companion's sky model
(companion/nativeloader/lua/nativeloader/sky_model.lua) puts them for a time of day, a season and a
phase.

It prints, for each time and phase with both above the horizon, the sky's luminance where the Moon
stands, the Moon's mean luminance over its lit part (and over the whole disc), and their ratio: the
contrast the Moon makes once its light is added to the sky in front of it. A column gives the same
for a real Moon of the same full brightness (Allen's phase law), for comparison. No GPU, no game.

    python -I tools/sky/moon_daylight.py [--weather clear|partlyCloudy|hazy] [--season summer]
                                          [--json out.json]
"""

import argparse
import json
import math
import sys

import numpy as np

PI = math.pi

# The runtime's constants (rtx_atmosphere.h, atmosphere_common.slangh).
PLANET_RADIUS = 6371.0
ATMOSPHERE_THICKNESS = 100.0
ATMOSPHERE_RADIUS = PLANET_RADIUS + ATMOSPHERE_THICKNESS
RAYLEIGH_SCALE_HEIGHT = 8.0
MIE_SCALE_HEIGHT = 1.2
TRANSMITTANCE_LUT = (512, 128)
MULTISCATTERING_LUT = 32
GROUND_ALBEDO = 0.3
MIE_SCATTERING = np.array([3.996e-3, 3.996e-3, 3.996e-3])
MIE_ABSORPTION = np.array([4.4e-3, 4.4e-3, 4.4e-3])
OZONE_ABSORPTION = np.array([0.650e-3, 1.881e-3, 0.085e-3])
OZONE_ALTITUDE = 25.0
OZONE_WIDTH = 15.0
LUMA = np.array([0.2126, 0.7152, 0.0722])

# Weather presets' atmosphere (companion/nativeloader/lua/nativeloader/weather_presets.lua).
WEATHERS = {
    "clear": dict(air=0.95, aerosol=0.7, absorption=1.0, g=0.97, sun=(20.0, 20.0, 20.0)),
    "partlyCloudy": dict(air=1.0, aerosol=1.0, absorption=1.0, g=0.97, sun=(19.0, 19.0, 19.0)),
    "hazy": dict(air=1.0, aerosol=3.0, absorption=0.12, g=0.8, sun=(20.0, 19.4, 18.2)),
}
RAYLEIGH_BASE = np.array([0.0058, 0.0135, 0.0331])

# The Moon as the companion sets it (nativeloader_sky.lua LOOK) over the runtime's defaults.
MOON_TEXTURE_ALBEDO = 0.12      # rtx.atmosphere.moonTextureAlbedo: the near side's mean
MOON_BRIGHTNESS = 1.0           # rtx.atmosphere.moon0.brightness
MOON_DARK_SIDE = 0.005          # rtx.atmosphere.moon0.darkSideBrightness
MOON_RADIUS_DEG = 0.8           # rtx.atmosphere.moon0.angularRadius 1.6 is the diameter

# Sky model (sky_model.lua).
OBLIQUITY = 23.44
LATITUDE = 40.0
SEASONS = {"spring": 80, "summer": 172, "autumn": 266, "winter": 355}
ECLIPSE_PENUMBRA = 4.8
PHASES = [("waxing crescent", 0.15), ("first quarter", 0.25), ("waxing gibbous", 0.35), ("full", 0.5),
          ("waning gibbous", 0.65), ("last quarter", 0.75), ("waning crescent", 0.85)]


class Atmosphere:
    def __init__(self, weather, ground_row_altitude=0.001):
        """ground_row_altitude: where the multiple-scattering LUT's bottom row samples, in km. The
        runtime samples exactly on the ground, where its planet test finds the ground at distance 0 in
        every direction: in exact arithmetic the row is black (0 here reproduces that). 0.001 (1 m)
        gives the row the physics intends."""
        self.ground_row_altitude = ground_row_altitude
        w = WEATHERS[weather]
        self.rayleigh = RAYLEIGH_BASE * w["air"]
        self.mie = MIE_SCATTERING * w["aerosol"]
        self.mie_absorption = MIE_ABSORPTION * (w["aerosol"] * w["absorption"])
        self.g = min(w["g"], 0.999)
        self.sun = np.array(w["sun"])
        self.transmittance_lut = self._bake_transmittance()
        self.multiscattering_lut = self._bake_multiscattering()

    # ------------------------------------------------------------------ medium
    def medium(self, altitude):
        """(rayleigh scattering, mie scattering, scattering, extinction), each (..., 3)."""
        a = np.maximum(altitude, 0.0)[..., None]
        d_r = np.exp(-a / RAYLEIGH_SCALE_HEIGHT)
        d_m = np.exp(-a / MIE_SCALE_HEIGHT)
        d_o = np.maximum(0.0, 1.0 - np.abs(altitude[..., None] - OZONE_ALTITUDE) / OZONE_WIDTH)
        s_r = self.rayleigh * d_r
        s_m = self.mie * d_m
        s = s_r + s_m
        e = s + self.mie_absorption * d_m + OZONE_ABSORPTION * d_o
        return s_r, s_m, s, e

    # ------------------------------------------------------------------ transmittance LUT
    def _bake_transmittance(self):
        width, height = TRANSMITTANCE_LUT
        x_mu = np.arange(width) / (width - 1)
        x_r = np.arange(height) / (height - 1)
        x_mu, x_r = np.meshgrid(x_mu, x_r)                         # (height, width)
        h = math.sqrt(ATMOSPHERE_RADIUS ** 2 - PLANET_RADIUS ** 2)
        rho = h * x_r
        altitude = np.sqrt(rho ** 2 + PLANET_RADIUS ** 2) - PLANET_RADIUS
        r = altitude + PLANET_RADIUS
        d_min = ATMOSPHERE_RADIUS - r
        d_max = rho + h
        d = d_min + x_mu * (d_max - d_min)
        with np.errstate(divide="ignore", invalid="ignore"):
            mu = np.where(d == 0.0, 1.0, (h * h - rho * rho - d * d) / (2.0 * r * d))
        mu = np.clip(mu, -1.0, 1.0)
        return self._transmittance(np.clip(altitude, 0.0, ATMOSPHERE_THICKNESS), mu)

    def _transmittance(self, altitude, mu):
        """computeTransmittance: 40 power-distributed steps to the top of the atmosphere."""
        origin_y = altitude + PLANET_RADIUS                        # from the planet's centre
        sin_z = np.sqrt(np.maximum(0.0, 1.0 - mu * mu))
        # Exit distance through the top sphere from inside it.
        b = origin_y * mu
        t_end = -b + np.sqrt(np.maximum(b * b - (origin_y ** 2 - ATMOSPHERE_RADIUS ** 2), 0.0))
        steps = 40
        edges = (np.arange(steps + 1) / steps) ** 2
        depth = np.zeros(altitude.shape + (3,))
        for i in range(steps):
            t = (edges[i] + 0.5 * (edges[i + 1] - edges[i])) * t_end
            dt = (edges[i + 1] - edges[i]) * t_end
            px, py = sin_z * t, origin_y + mu * t
            alt = np.clip(np.sqrt(px * px + py * py) - PLANET_RADIUS, 0.0, ATMOSPHERE_THICKNESS)
            depth += self.medium(alt)[3] * dt[..., None]
        return np.exp(-np.minimum(depth, 1e3))

    def sample_transmittance(self, altitude, mu):
        width, height = TRANSMITTANCE_LUT
        h = math.sqrt(ATMOSPHERE_RADIUS ** 2 - PLANET_RADIUS ** 2)
        altitude = np.asarray(altitude, dtype=float)
        rho = np.sqrt(np.maximum(0.0, altitude * altitude + 2.0 * PLANET_RADIUS * altitude))
        r = altitude + PLANET_RADIUS
        mu = np.clip(mu, -1.0, 1.0)
        d = np.maximum(0.0, -r * mu + np.sqrt(np.maximum(0.0, r * r * (mu * mu - 1.0) + ATMOSPHERE_RADIUS ** 2)))
        d_min = np.maximum(0.0, ATMOSPHERE_RADIUS - r)
        d_max = rho + h
        x_mu = np.clip((d - d_min) / np.maximum(d_max - d_min, 1e-6), 0.0, 1.0)
        x_r = np.clip(rho / h, 0.0, 1.0)
        return bilinear(self.transmittance_lut, x_mu * (width - 1), x_r * (height - 1))

    def sun_shadowing(self, pos, sun_dir, clamp_to_surface=False):
        """evalSunShadowing (and its ClampedToSurface variant). pos: (..., 3) in the frame whose
        origin is on the ground; the planet's centre is (0, -R, 0)."""
        rel = pos + np.array([0.0, PLANET_RADIUS, 0.0])
        radius = np.linalg.norm(rel, axis=-1)
        if clamp_to_surface:
            scale = np.where(radius < PLANET_RADIUS, PLANET_RADIUS / np.maximum(radius, 1e-3), 1.0)
            rel = rel * scale[..., None]
            radius = np.linalg.norm(rel, axis=-1)
        # Planet shadow: the ray to the sun meets the (slightly shrunk) planet ahead.
        shadow_r = PLANET_RADIUS * (1.0 - 1e-5)
        b = np.sum(rel * sun_dir, axis=-1)
        c = radius * radius - shadow_r * shadow_r
        disc = b * b - c
        sq = np.sqrt(np.maximum(disc, 0.0))
        t1 = -b + sq
        lit = ~((disc >= -1e-6 / 4.0) & (t1 >= 0.0))
        cos_sun = b / np.maximum(radius, 1e-3)
        trans = self.sample_transmittance(np.maximum(radius - PLANET_RADIUS, 0.0), cos_sun)
        return trans * lit[..., None]

    # ------------------------------------------------------------------ multiscattering LUT
    def _bake_multiscattering(self):
        n = MULTISCATTERING_LUT
        cos_sun = np.arange(n) / (n - 1) * 2.0 - 1.0
        altitude = np.arange(n) / (n - 1) * ATMOSPHERE_THICKNESS
        lut = np.zeros((n, n, 3))
        altitude[0] = self.ground_row_altitude
        for j, alt in enumerate(altitude):
            for i, cs in enumerate(cos_sun):
                lut[j, i] = self._multiscattering(alt, cs)
        return lut

    def _multiscattering(self, altitude, cos_sun):
        sample = np.array([0.0, min(max(altitude, 0.0), ATMOSPHERE_THICKNESS), 0.0])
        sin_sun = math.sqrt(max(0.0, 1.0 - cos_sun * cos_sun))
        sun_dir = np.array([sin_sun, cos_sun, 0.0])
        sun_dir /= np.linalg.norm(sun_dir)
        u = (np.arange(8) + 0.5) / 8
        theta = 2.0 * PI * u[:, None] * np.ones((1, 8))
        cos_phi = (1.0 - 2.0 * u)[None, :] * np.ones((8, 1))
        sin_phi = np.sqrt(np.maximum(0.0, 1.0 - cos_phi ** 2))
        dirs = np.stack([sin_phi * np.cos(theta), cos_phi, sin_phi * np.sin(theta)], axis=-1).reshape(-1, 3)
        rel = sample + np.array([0.0, PLANET_RADIUS, 0.0])
        b = dirs @ rel
        c_top = rel @ rel - ATMOSPHERE_RADIUS ** 2
        t_top = -b + np.sqrt(np.maximum(b * b - c_top, 0.0))
        c_ground = rel @ rel - PLANET_RADIUS ** 2
        disc = b * b - c_ground
        sq = np.sqrt(np.maximum(disc, 0.0))
        t0, t1 = -b - sq, -b + sq
        t_ground = np.where(t1 < 0.0, -1.0, np.where(t0 < 0.0, t1, t0))
        t_ground = np.where(disc < -1e-6 / 4.0, -1.0, t_ground)
        hits = t_ground >= 0.0
        t_end = np.where(hits, t_ground, np.maximum(t_top, 0.0))
        # integrateDirection returns nothing for a direction that leaves no distance to march.
        marched = t_end > 0.0
        hits = hits & marched
        steps = 20
        edges = (np.arange(steps + 1) / steps) ** 2
        second = np.zeros((len(dirs), 3))
        transfer = np.zeros((len(dirs), 3))
        throughput = np.ones((len(dirs), 3))
        for i in range(steps):
            t = (edges[i] + 0.5 * (edges[i + 1] - edges[i])) * t_end
            dt = ((edges[i + 1] - edges[i]) * t_end)[:, None]
            pos = sample + dirs * t[:, None]
            alt = np.clip(np.linalg.norm(pos + np.array([0.0, PLANET_RADIUS, 0.0]), axis=-1) - PLANET_RADIUS,
                          0.0, ATMOSPHERE_THICKNESS)
            _, _, s, e = self.medium(alt)
            st = np.clip(np.exp(-e * dt), 0.0, 1.0)
            ce = np.maximum(e, 1e-7)
            in_scatter = s * (1.0 / (4.0 * PI)) * self.sun_shadowing(pos, sun_dir)
            second += throughput * (in_scatter - in_scatter * st) / ce
            transfer += throughput * (s - s * st) / ce
            throughput *= st
        ground = sample + dirs * t_end[:, None]
        normal = ground + np.array([0.0, PLANET_RADIUS, 0.0])
        normal /= np.linalg.norm(normal, axis=-1, keepdims=True)
        ndotl = normal @ sun_dir
        add = hits & (ndotl > 0.0)
        second += (throughput * self.sun_shadowing(ground, sun_dir) * (ndotl * GROUND_ALBEDO / PI)[:, None]) * add[:, None]
        weight = 1.0 / len(dirs)
        second = (second * marched[:, None]).sum(axis=0) * weight
        transfer = (transfer * marched[:, None]).sum(axis=0) * weight
        return np.maximum(second / (1.0 - np.clip(transfer, 0.0, 0.999)), 0.0)

    def sample_multiscattering(self, altitude, cos_sun):
        n = MULTISCATTERING_LUT
        fx = (np.clip(cos_sun, -1.0, 1.0) + 1.0) * 0.5 * (n - 1)
        fy = np.clip(altitude / ATMOSPHERE_THICKNESS, 0.0, 1.0) * (n - 1)
        return bilinear(self.multiscattering_lut, fx, fy)

    # ------------------------------------------------------------------ the sky
    def sky_radiance(self, view_dir, sun_dir):
        """evalAtmosphereRadiance from the ground with 32 steps (the sky-view LUT's bake)."""
        view_dir = np.asarray(view_dir, dtype=float)
        rel = np.array([0.0, PLANET_RADIUS, 0.0])
        b = view_dir @ rel
        t_end = -b + math.sqrt(max(b * b - (rel @ rel - ATMOSPHERE_RADIUS ** 2), 0.0))
        cos_theta = float(view_dir @ sun_dir)
        phase_r = 3.0 / (16.0 * PI) * (1.0 + cos_theta ** 2)
        g = self.g
        phase_m = (1.0 - g * g) / max(4.0 * PI * (1.0 + g * g - 2.0 * g * cos_theta) ** 1.5, 1e-3)
        steps = 32
        edges = (np.arange(steps + 1) / steps) ** 2
        t = (edges[:-1] + 0.5 * np.diff(edges)) * t_end
        dt = (np.diff(edges) * t_end)[:, None]
        pos = view_dir[None, :] * t[:, None]
        centre_rel = pos + rel
        alt = np.clip(np.linalg.norm(centre_rel, axis=-1) - PLANET_RADIUS, 0.0, ATMOSPHERE_THICKNESS)
        s_r, s_m, s, e = self.medium(alt)
        up = centre_rel / np.linalg.norm(centre_rel, axis=-1, keepdims=True)
        cos_sun = up @ sun_dir
        sun_trans = self.sun_shadowing(pos, sun_dir, clamp_to_surface=True)
        ms = self.sample_multiscattering(alt, cos_sun)
        scattered = self.sun * sun_trans * (s_r * phase_r + s_m * phase_m) + self.sun * s * ms
        st = np.clip(np.exp(-e * dt), 0.0, 1.0)
        integ = (scattered - scattered * st) / np.maximum(e, 1e-7)
        trans_before = np.vstack([np.ones((1, 3)), np.cumprod(st, axis=0)[:-1]])
        return np.maximum((trans_before * integ).sum(axis=0), 0.0)

    def air_transmittance(self, direction):
        """getAtmosphericTransmittanceForDir: Kasten-Young air mass, the moons' and the clouds' model."""
        y = float(direction[1])
        if y > 0.01:
            zenith = math.degrees(math.acos(min(max(y, -1.0), 1.0)))
            air_mass = 1.0 / (y + 0.15 * (93.885 - zenith) ** -1.253)
        else:
            air_mass = 40.0 * math.exp(-y * 10.0)
        air_mass = min(air_mass, 200.0)
        ozone_mass = 1.0 / math.sqrt(max(y * y + 2.0 * OZONE_ALTITUDE / PLANET_RADIUS, 1e-6))
        t = np.exp(-self.rayleigh * RAYLEIGH_SCALE_HEIGHT * air_mass
                   - (self.mie + self.mie_absorption) * MIE_SCALE_HEIGHT * air_mass
                   - OZONE_ABSORPTION * OZONE_WIDTH * ozone_mass)
        if y < 0.0:
            t = t * math.exp(y * 15.0)
        return t


def bilinear(lut, fx, fy):
    """A linear, clamp-to-edge read of lut (rows, cols, 3) at texel coordinates (fx, fy)."""
    rows, cols = lut.shape[:2]
    fx = np.clip(np.asarray(fx, dtype=float), 0.0, cols - 1)
    fy = np.clip(np.asarray(fy, dtype=float), 0.0, rows - 1)
    x0 = np.minimum(np.floor(fx).astype(int), cols - 2)
    y0 = np.minimum(np.floor(fy).astype(int), rows - 2)
    ax = (fx - x0)[..., None]
    ay = (fy - y0)[..., None]
    top = lut[y0, x0] * (1 - ax) + lut[y0, x0 + 1] * ax
    bottom = lut[y0 + 1, x0] * (1 - ax) + lut[y0 + 1, x0 + 1] * ax
    return top * (1 - ay) + bottom * ay


# ---------------------------------------------------------------------- the Moon's face
def moon_lit_terms(phase, samples=401):
    """evalTexturedMoon's Lunar-Lambert term with earthshine over the disc of a smooth sphere:
    returns (mean over the disc, mean over the lit part, lit fraction of the disc). The Moon's
    in-plane orientation does not change these means."""
    x = np.linspace(-1.0, 1.0, samples)
    dx, dy = np.meshgrid(x, x)
    r2 = dx * dx + dy * dy
    inside = r2 <= 0.9999
    z = np.sqrt(np.maximum(1.0 - r2, 0.0))
    phase_angle = abs(PI - 2.0 * PI * (phase % 1.0))
    light = np.array([math.sin(phase_angle), 0.0, math.cos(phase_angle)])
    n_dot_l = dx * light[0] + z * light[2]
    width = 0.01
    terminator = np.clip((n_dot_l + width) / (2 * width), 0.0, 1.0)
    terminator = terminator * terminator * (3 - 2 * terminator)
    softness = 0.02
    cos_i = softness * np.log1p(np.exp(np.minimum(n_dot_l / softness, 30.0)))
    cos_e = np.maximum(z, 1e-3)
    lit = terminator * (0.75 * 2.0 * cos_i / (cos_i + cos_e) + 0.25 * cos_i)
    earthshine = MOON_DARK_SIDE * (0.5 - 0.5 * math.cos(phase_angle))
    total = lit + earthshine
    lit_part = inside & (terminator > 0.5)
    mean_disc = float(total[inside].mean())
    mean_lit = float(total[lit_part].mean()) if lit_part.any() else 0.0
    return mean_disc, mean_lit, float(lit_part.sum() / inside.sum())


def real_moon_relative(phase_angle_deg):
    """A real Moon's light relative to full (Allen's phase law), and its lit fraction."""
    a = abs(phase_angle_deg)
    light = 10.0 ** (-0.4 * (0.026 * a + 4.0e-9 * a ** 4))
    lit_fraction = 0.5 * (1.0 + math.cos(math.radians(a)))
    return light, lit_fraction


def drawn_moon_light(a):
    """rtx_moon_daylight.h drawnMoonLight: the Lunar-Lambert disc integral relative to full."""
    a = min(abs(a), PI)
    if a >= PI - 1e-6:
        return 0.0
    ls = 1.0 if a <= 1e-6 else 1.0 - math.sin(0.5 * a) * math.tan(0.5 * a) * math.log(1.0 / math.tan(0.25 * a))
    lambert = (math.sin(a) + (PI - a) * math.cos(a)) / PI
    return max(0.75 * ls + 0.25 * (2.0 / 3.0) * lambert, 0.0) / (0.75 + 0.25 * 2.0 / 3.0)


def daytime_light_scale(phase):
    """rtx_moon_daylight.h daytimeLightScale: the real law over the drawn one, held from 150 degrees."""
    a = min(abs(PI - 2.0 * PI * (phase % 1.0)), math.radians(150.0))
    drawn = drawn_moon_light(a)
    if drawn <= 0.0:
        return 1.0
    return min(max(real_moon_relative(math.degrees(a))[0] / drawn, 0.0), 1.0)


def night_look(sun_elevation_deg):
    """evalSkyRadiance's moonFade: 0 with the sun up, 1 from 5.16 degrees down (sine 0.09)."""
    t = min(max(math.sin(math.radians(sun_elevation_deg)) / -0.09, 0.0), 1.0)
    return t * t * (3.0 - 2.0 * t)


# ---------------------------------------------------------------------- where they stand
def equatorial(longitude, latitude=0.0):
    l, b, e = math.radians(longitude), math.radians(latitude), math.radians(OBLIQUITY)
    ra = math.atan2(math.sin(l) * math.cos(b) * math.cos(e) - math.sin(b) * math.sin(e), math.cos(l) * math.cos(b))
    dec = math.asin(max(-1.0, min(1.0, math.sin(b) * math.cos(e) + math.cos(b) * math.sin(e) * math.sin(l))))
    return math.degrees(ra) % 360.0, math.degrees(dec)


def horizontal(hour_angle, declination, latitude):
    sl, cl = math.sin(math.radians(latitude)), math.cos(math.radians(latitude))
    sd, cd = math.sin(math.radians(declination)), math.cos(math.radians(declination))
    h = math.radians(hour_angle)
    se = max(-1.0, min(1.0, sl * sd + cl * cd * math.cos(h)))
    elevation = math.asin(se)
    denominator = math.cos(elevation) * cl
    azimuth = 0.0
    if abs(denominator) > 1e-6:
        azimuth = math.degrees(math.acos(max(-1.0, min(1.0, (sd - se * sl) / denominator))))
        if ((hour_angle + 180.0) % 360.0 - 180.0) > 0.0:
            azimuth = 360.0 - azimuth
    return math.degrees(elevation), azimuth


def sky(hours, day, phase, latitude=LATITUDE):
    """sky_model.sky: the sun and the Moon (off the ecliptic as the companion puts it outside an
    eclipse) as runtime directions."""
    moon_latitude = (ECLIPSE_PENUMBRA + 1.0) * MOON_RADIUS_DEG + 1.0
    lam = 360.0 * (day - 80) / 365.25
    ra_sun, dec_sun = equatorial(lam)
    hour_sun = (hours - 12.0) * 15.0
    sun_el, sun_az = horizontal(hour_sun, dec_sun, latitude)
    ra_moon, dec_moon = equatorial(lam + 360.0 * phase, moon_latitude)
    moon_el, moon_az = horizontal(hour_sun - ((ra_moon - ra_sun + 180.0) % 360.0 - 180.0), dec_moon, latitude)
    return (sun_el, sun_az), (moon_el, moon_az)


def direction(elevation, azimuth):
    el, az = math.radians(elevation), math.radians(azimuth)
    return np.array([math.cos(el) * math.sin(az), math.sin(el), math.cos(el) * math.cos(az)])


# ---------------------------------------------------------------------- the table
TWILIGHT_FADE_DEPTH = 16.0     # rtx.atmosphere.twilightFadeDepth


def atmosphere_fade(sun_elevation_deg):
    """evalSkyRadiance's twilight fade of the sky-view LUT (R18)."""
    fade_end = min(-math.sin(math.radians(TWILIGHT_FADE_DEPTH)), -0.01)
    y = math.sin(math.radians(sun_elevation_deg))
    t = min(max((y - fade_end) / (0.5 * fade_end - fade_end), 0.0), 1.0)
    return t * t * (3.0 - 2.0 * t)


def rows(atmosphere, day, hours_list, brightness=1.0, lowest_sun=0.0):
    """One row per time and phase with the sun at least lowest_sun degrees high and the Moon above
    the horizon. Luminances (Y of Rec. 709) in the runtime's units:
      sky        the sky where the Moon stands (the in-scatter in front of it)
      moon_lit   the drawn Moon's mean over its lit part, before any scale (the night's look)
      scale      what multiplies it now: the day's phase law times `brightness`, handed over to 1
      contrast   moon_lit * scale / sky: how much brighter the lit part is than the sky around it
      night_contrast, real_contrast  the same for the night's look and for a real Moon."""
    out = []
    full_disc, _, _ = moon_lit_terms(0.5)
    for hours in hours_list:
        for name, phase in PHASES:
            (sun_el, sun_az), (moon_el, moon_az) = sky(hours, day, phase)
            if sun_el < lowest_sun or moon_el < 1.0:
                continue
            sun_dir, moon_dir = direction(sun_el, sun_az), direction(moon_el, moon_az)
            sky_y = float(atmosphere.sky_radiance(moon_dir, sun_dir) @ LUMA) * atmosphere_fade(sun_el)
            sunlit = atmosphere.sun * atmosphere.air_transmittance(moon_dir) * (MOON_BRIGHTNESS / PI)
            sunlit_y = float(sunlit @ LUMA) * MOON_TEXTURE_ALBEDO
            mean_disc, mean_lit, lit_fraction = moon_lit_terms(phase)
            moon_lit_y = sunlit_y * mean_lit
            phase_angle = math.degrees(abs(PI - 2.0 * PI * (phase % 1.0)))
            real_light, real_fraction = real_moon_relative(phase_angle)
            real_lit_y = sunlit_y * full_disc * real_light / max(real_fraction, 1e-6)
            w = night_look(sun_el)
            scale = (1.0 - w) * brightness * daytime_light_scale(phase) + w
            separation = math.degrees(math.acos(max(-1.0, min(1.0, float(sun_dir @ moon_dir)))))
            sky_safe = max(sky_y, 1e-9)
            out.append(dict(hours=hours, phase=name, sun_elevation=round(sun_el, 1),
                            moon_elevation=round(moon_el, 1), separation=round(separation, 1),
                            sky=sky_y, moon_lit=moon_lit_y, moon_disc=sunlit_y * mean_disc, scale=scale,
                            contrast=moon_lit_y * scale / sky_safe, night_contrast=moon_lit_y / sky_safe,
                            real_contrast=real_lit_y / sky_safe, lit_fraction=lit_fraction))
    return out


def main(argv=None):
    parser = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    parser.add_argument("--weather", choices=sorted(WEATHERS), default="partlyCloudy")
    parser.add_argument("--season", choices=sorted(SEASONS), default="summer")
    parser.add_argument("--hours", default="7,9,11,13,14.5,16,18,19",
                        help="comma-separated times of day")
    parser.add_argument("--brightness", type=float, default=1.0,
                        help="rtx.atmosphere.daytimeMoonBrightness (the companion's Moon by day / 100)")
    parser.add_argument("--lowest-sun", type=float, default=0.0,
                        help="leave out times with the sun lower than this, in degrees (twilight: -6)")
    parser.add_argument("--ground-row", type=float, default=0.001,
                        help="altitude in km of the multiple-scattering LUT's bottom row (0: as the runtime)")
    parser.add_argument("--json", help="also write the rows to this file")
    args = parser.parse_args(argv)
    hours = [float(h) for h in args.hours.split(",") if h.strip()]
    atmosphere = Atmosphere(args.weather, args.ground_row)
    table = rows(atmosphere, SEASONS[args.season], hours, args.brightness, args.lowest_sun)
    print(f"weather {args.weather}, {args.season}, latitude {LATITUDE:g}, day brightness {args.brightness:g}; "
          f"luminances in the runtime's units (sun illuminance {atmosphere.sun[0]:g})")
    print(f"{'time':>5} {'phase':<16} {'sun':>5} {'moon':>5} {'apart':>6} {'sky':>7} {'moon lit':>9} "
          f"{'scale':>6} {'shown':>7} {'night':>7} {'real':>7}")
    for r in table:
        print(f"{r['hours']:>5g} {r['phase']:<16} {r['sun_elevation']:>5.1f} {r['moon_elevation']:>5.1f} "
              f"{r['separation']:>6.1f} {r['sky']:>7.3f} {r['moon_lit']:>9.3f} {r['scale']:>6.3f} "
              f"{r['contrast']:>7.2f} {r['night_contrast']:>7.2f} {r['real_contrast']:>7.2f}")
    print("shown, night, real: the lit part's luminance over the sky's around it, as the runtime shows it now,"
          " as the night's look would by day, and for a real Moon")
    if args.json:
        with open(args.json, "w", encoding="utf-8") as f:
            json.dump(dict(weather=args.weather, season=args.season, brightness=args.brightness, rows=table),
                      f, indent=1)
    return 0


if __name__ == "__main__":
    sys.exit(main())
