#!/usr/bin/env python3
"""Propagate a CelesTrak GP snapshot with SGP4 into a quantized ephemeris buffer.

Output (data/ephemeris.bin) is sample-major so the two time slabs bracketing any
instant are contiguous and can be uploaded as-is. Positions are TEME, in Earth
radii, quantized to int16.

TEME is deliberate: SGP4's native frame. The Earth mesh is rotated by GMST(t) at
runtime instead, which keeps ground tracks correct and skips nutation/polar motion
(sub-km -- invisible at wall scale).
"""
import argparse
import datetime as dt
import json
import math
import pathlib
import struct
import sys

import numpy as np

from sgp4.api import SatrecArray, Satrec, jday
from sgp4 import omm

ROOT = pathlib.Path(__file__).resolve().parent.parent
CACHE_DIR = ROOT / "data" / "gp_cache"
RE_KM = 6378.137
MAGIC = b"SATE"
VERSION = 2
MAX_RADIUS = 8.0           # Earth radii; objects beyond this are dropped as off-scene

# Positions are float32, not quantized. int16 would halve the file, but GDScript has
# no bulk int16 decode -- only per-element decode_s16() -- whereas
# PackedByteArray.to_float32_array() is a single C++ call. At 20k objects that is the
# difference between a frame budget and a slideshow. float32 also feeds Phase B's
# Image.FORMAT_RGBF texture directly. 20k x 360 samples = 86 MB, which is fine.

# Canonical python-sgp4 documentation TLE. Used only as a self-test fixture;
# verified here to give 409.0 km altitude and 7.665 km/s.
ISS_TLE = (
    "1 25544U 98067A   19343.69339541  .00001764  00000-0  38792-4 0  9991",
    "2 25544  51.6439 211.2001 0007417  17.6667  85.6398 15.50103472202482",
)


def teme_to_godot(x, y, z):
    """ECI/TEME (Z-up, right-handed) -> Godot (Y-up, right-handed, -Z forward).

    This mapping has determinant +1. The seductive (x, z, y) is a REFLECTION
    (det -1): it silently reverses every orbit's direction and still looks
    entirely plausible. selftest_handedness() guards against that.
    """
    return (x, z, -y)


def selftest_handedness():
    sat = Satrec.twoline2rv(*ISS_TLE)
    jd, fr = jday(2019, 12, 9, 16, 38, 0)
    err, r, v = sat.sgp4(jd, fr)
    if err != 0:
        raise SystemExit(f"self-test: SGP4 error {err}")

    alt = math.dist(r, (0.0, 0.0, 0.0)) - RE_KM
    speed = math.dist(v, (0.0, 0.0, 0.0))
    if not 380.0 < alt < 440.0:
        raise SystemExit(f"self-test: ISS altitude {alt:.1f} km out of range")
    if not 7.5 < speed < 7.8:
        raise SystemExit(f"self-test: ISS speed {speed:.3f} km/s out of range")

    rg = teme_to_godot(*r)
    vg = teme_to_godot(*v)
    l_y = rg[2] * vg[0] - rg[0] * vg[2]     # y-component of r x v, Godot frame
    if l_y <= 0.0:
        raise SystemExit(
            "self-test: FAILED -- ISS (inclination 51.6 deg, prograde) propagates "
            "RETROGRADE in Godot coordinates. teme_to_godot() is a reflection."
        )

    print(f"  self-test: ISS alt {alt:.1f} km, speed {speed:.3f} km/s")
    print(f"  self-test: angular momentum L_y = +{l_y:.0f} -> prograde (west->east) OK")


def gmst_rad(jd_ut1):
    """Greenwich Mean Sidereal Time, IAU-82. Runtime mirrors this in sim_clock.gd."""
    t = (jd_ut1 - 2451545.0) / 36525.0
    sec = (67310.54841
           + (876600.0 * 3600.0 + 8640184.812866) * t
           + 0.093104 * t * t
           - 6.2e-6 * t * t * t)
    return math.radians((sec % 86400.0) / 240.0) % (2.0 * math.pi)


def subpoint(r_teme, jd, fr):
    """Geodetic-ish sub-satellite lat/lon in degrees (spherical Earth is fine here)."""
    x, y, z = r_teme
    lat = math.degrees(math.asin(z / math.dist(r_teme, (0.0, 0.0, 0.0))))
    lon = math.degrees((math.atan2(y, x) - gmst_rad(jd + fr) + math.pi) % (2.0 * math.pi) - math.pi)
    return lat, lon


def intl_designator(sat, rec):
    """Full international designator, e.g. "1998-067A".

    The OMM feed carries OBJECT_ID directly, but the TLE-pair mirror does not --
    it is only encoded in columns 10-17 of line 1, which sgp4 exposes as
    intldesg ("98067A"). Without expanding it, every debris-family query is
    silently empty, because the field exists but is blank.
    """
    direct = rec.get("OBJECT_ID", "")
    if direct:
        return direct
    raw = (getattr(sat, "intldesg", "") or "").strip()
    if len(raw) < 5 or not raw[:5].isdigit():
        return ""
    yy = int(raw[:2])
    # Two-digit launch years: Sputnik was 1957, so anything below 57 is 20xx.
    year = 1900 + yy if yy >= 57 else 2000 + yy
    return f"{year}-{raw[2:5]}{raw[5:]}"


def classify(apo_km, peri_km, period_min, ecc):
    if ecc > 0.25:
        return "HEO"
    if apo_km < 2000.0:
        return "LEO"
    if 1400.0 < period_min < 1470.0:
        return "GEO"
    return "MEO"


def load_gp(path):
    data = json.loads(path.read_text(encoding="utf-8"))

    # Deduplicate by NORAD ID regardless of source. A duplicated object is not
    # a harmless extra row: it doubles that object's contribution to the density
    # the whole demo is about, and conjunction screening reports it colliding
    # with itself at 0.000 km.
    seen, unique = {}, []
    for rec in data:
        nid = int(rec.get("NORAD_CAT_ID", 0))
        epoch = str(rec.get("EPOCH", ""))
        if nid in seen:
            if epoch > seen[nid][0]:
                unique[seen[nid][1]] = rec
                seen[nid] = (epoch, seen[nid][1])
            continue
        seen[nid] = (epoch, len(unique))
        unique.append(rec)
    if len(unique) != len(data):
        print(f"  dropped {len(data) - len(unique)} duplicate records "
              f"({len(unique)} unique objects)")
    data = unique

    sats, meta = [], []
    for rec in data:
        try:
            if "TLE_LINE1" in rec:
                sat = Satrec.twoline2rv(rec["TLE_LINE1"], rec["TLE_LINE2"])
            else:
                sat = Satrec()
                omm.initialize(sat, rec)
        except (ValueError, KeyError, RuntimeError):
            continue
        # no_kozai is rad/min: rev/day = rad/min * 1440 min/day / 2pi rad/rev.
        n = sat.no_kozai * 1440.0 / (2.0 * math.pi)        # rev/day
        if n <= 0.0:
            continue
        a = (398600.4418 / ((sat.no_kozai / 60.0) ** 2)) ** (1.0 / 3.0)
        apo = a * (1.0 + sat.ecco) - RE_KM
        peri = a * (1.0 - sat.ecco) - RE_KM
        period = 1440.0 / n
        sats.append(sat)
        meta.append({
            "name": rec.get("OBJECT_NAME", "UNKNOWN"),
            "norad_id": int(rec.get("NORAD_CAT_ID", 0)),
            "intl_des": intl_designator(sat, rec),
            "epoch": rec.get("EPOCH", ""),
            "regime": classify(apo, peri, period, sat.ecco),
            "apogee_km": round(apo, 1),
            "perigee_km": round(peri, 1),
            "inclination_deg": round(math.degrees(sat.inclo), 3),
            "period_min": round(period, 2),
            "ecc": round(sat.ecco, 6),
        })
    return sats, meta


PATH_POINTS = 96
PATH_MAGIC = b"OPTH"
PATH_VERSION = 1


def build_orbit_paths(sats, meta, start):
    """One closed loop per object, sampled evenly across that object's OWN
    orbital period, independent of --hours/--step.

    This exists because the position ephemeris above is a single window shared
    by every object regardless of period -- 3 hours by default. That is fine
    for interpolating where an object is RIGHT NOW (a LEO object laps it
    several times over), but a HEO object with an ~12h period only traces a
    quarter of its ellipse in that window: not a wrong picture, an incomplete
    one, and the incompleteness is exactly where an orbit's shape -- fast at
    perigee, slow at apogee -- would otherwise read clearly.

    Extending the shared window to cover HEO's period would either quadruple
    the ephemeris (same step, longer span) or coarsen the interpolation every
    other object uses (same sample count, longer span) for a chapter this
    change does not need. Giving every object its own period-length loop,
    fixed at PATH_POINTS samples regardless of how long that period is, costs
    a few tens of MB and touches nothing about the live position data.

    Genuine SGP4 propagation, same as the main ephemeris -- not an idealized
    two-body ellipse. A handful of objects fail to propagate a full period
    ahead even when the main window succeeds (elements are only trustworthy
    near their epoch); those degenerate to a single repeated point, which
    draws nothing rather than a corrupt shape.
    """
    jd0, fr0 = jday(start.year, start.month, start.day,
                    start.hour, start.minute, start.second)
    n_obj = len(sats)
    out = np.empty((n_obj, PATH_POINTS, 3), dtype="<f4")
    n_degenerate = 0
    for i, (sat, m) in enumerate(zip(sats, meta)):
        period_s = m["period_min"] * 60.0
        step_s = period_s / PATH_POINTS
        frac = fr0 + (np.arange(PATH_POINTS) * step_s) / 86400.0
        jd_i = jd0 + np.floor(frac)
        fr_i = frac - np.floor(frac)
        err, r, _v = sat.sgp4_array(jd_i, fr_i)
        if (err != 0).any():
            n_degenerate += 1
            out[i, :, :] = teme_to_godot(*sat.sgp4(jd0, fr0)[1])
            continue
        gx, gy, gz = teme_to_godot(r[:, 0], r[:, 1], r[:, 2])
        out[i, :, 0] = gx
        out[i, :, 1] = gy
        out[i, :, 2] = gz
    out /= RE_KM
    if n_degenerate:
        print(f"  {n_degenerate} objects could not propagate a full period "
              "ahead; drawn as a single point instead of a corrupt loop")
    return out


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--gp", type=pathlib.Path, help="GP JSON (default: newest in data/gp_cache)")
    ap.add_argument("--hours", type=float, default=3.0, help="Span to propagate (default 3)")
    ap.add_argument("--step", type=float, default=30.0, help="Sample step, seconds (default 30)")
    ap.add_argument("--selftest-only", action="store_true")
    args = ap.parse_args()

    print("Self-checks:")
    selftest_handedness()
    if args.selftest_only:
        return 0

    gp_path = args.gp
    if gp_path is None:
        candidates = sorted(CACHE_DIR.glob("*.json"))
        if not candidates:
            print(f"\nNo GP snapshot in {CACHE_DIR}. Run tools/fetch_gp.py first.", file=sys.stderr)
            return 1
        gp_path = candidates[-1]
    print(f"\nSource: {gp_path.name}")

    sats, meta = load_gp(gp_path)
    print(f"  {len(sats)} objects with usable elements")

    n_samples = int(args.hours * 3600.0 / args.step)
    start = dt.datetime.now(dt.timezone.utc).replace(second=0, microsecond=0)
    jd0, fr0 = jday(start.year, start.month, start.day,
                    start.hour, start.minute, start.second)

    jds, frs = [], []
    for i in range(n_samples):
        frac = fr0 + i * args.step / 86400.0
        jds.append(jd0 + math.floor(frac))
        frs.append(frac - math.floor(frac))

    print(f"  propagating {n_samples} samples x {args.step:.0f}s "
          f"({args.hours:.1f}h) from {start.isoformat()}")

    arr = SatrecArray(sats)
    jd_a = np.array(jds)
    fr_a = np.array(frs)
    err, r, _v = arr.sgp4(jd_a, fr_a)          # r: (n_sats, n_samples, 3) km

    # Drop anything that ever errored or ever leaves the quantization range.
    rad = np.linalg.norm(r, axis=2) / RE_KM
    good = (err == 0).all(axis=1)
    near = (rad < MAX_RADIUS).all(axis=1)

    # Consistency: the propagated orbit must agree with the mean elements it came
    # from. A handful of element sets in the public catalog are internally
    # inconsistent -- SGP4 returns no error, but an object whose mean elements say
    # "apogee 500 km" propagates out past 7 Re. They are junk, and because the
    # stereo comfort clamp is driven by the OUTERMOST visible object, a single one
    # of them mislabelled LEO would shrink the entire LEO chapter to accommodate
    # content that should not be there at all.
    apo_re = np.array([1.0 + m["apogee_km"] / RE_KM for m in meta])
    consistent = rad.max(axis=1) <= apo_re * 1.15 + 0.05

    ok = good & near & consistent
    r, meta = r[ok], [m for m, keep in zip(meta, ok) if keep]
    sats = [s for s, keep in zip(sats, ok) if keep]
    n_obj = len(meta)
    print(f"  dropped {int((~good).sum())} with SGP4 errors (decayed / bad elements)")
    print(f"  dropped {int((good & ~near).sum())} beyond {MAX_RADIUS} Re (off-scene)")
    print(f"  dropped {int((good & near & ~consistent).sum())} whose propagation "
          f"contradicts their own mean elements")
    print(f"  keeping {n_obj}")

    # Max radius each object actually ATTAINS inside the propagated window.
    # This is not the same as catalog apogee: an HEO object sitting near perigee
    # for the whole 3-hour span never gets near its 23 Re apogee. The runtime
    # stereo comfort clamp must be driven by what is on screen, not by the full
    # orbit, or it shrinks every wide chapter for content that is never drawn.
    max_r = rad[ok].max(axis=1)
    for m, mr in zip(meta, max_r):
        m["max_radius_re"] = round(float(mr), 4)

    # TEME km -> Godot Earth radii, then quantize. (x, z, -y) -- see teme_to_godot.
    g = np.empty_like(r)
    g[:, :, 0] = r[:, :, 0]
    g[:, :, 1] = r[:, :, 2]
    g[:, :, 2] = -r[:, :, 1]
    q = (g / RE_KM).astype("<f4")
    q = np.ascontiguousarray(q.transpose(1, 0, 2))     # -> sample-major

    out = ROOT / "data" / "ephemeris.bin"
    epoch_unix = start.timestamp()
    header = struct.pack("<4sIII d f f", MAGIC, VERSION, n_obj, n_samples,
                         epoch_unix, args.step, 0.0)
    assert len(header) == 32, len(header)
    with out.open("wb") as fh:
        fh.write(header)
        fh.write(q.tobytes())

    print(f"\n  building orbit paths ({PATH_POINTS} points/object, one full "
          "period each)...")
    paths = build_orbit_paths(sats, meta, start)
    paths_out = ROOT / "data" / "orbit_paths.bin"
    paths_header = struct.pack("<4sIII", PATH_MAGIC, PATH_VERSION, n_obj, PATH_POINTS)
    assert len(paths_header) == 16, len(paths_header)
    with paths_out.open("wb") as fh:
        fh.write(paths_header)
        fh.write(np.ascontiguousarray(paths).tobytes())
    paths_mb = paths_out.stat().st_size / 1e6
    print(f"  wrote data/orbit_paths.bin  {paths_mb:.1f} MB")

    counts = {}
    for m in meta:
        counts[m["regime"]] = counts.get(m["regime"], 0) + 1

    # Ground-track registration reference, written into the catalog so
    # tests/verify_frames.gd can check the engine against it without hardcoding
    # values that go stale the moment the ephemeris is rebuilt. Python computes
    # this with its own GMST implementation, so agreement is a genuine
    # cross-implementation check rather than a tautology.
    reference = None
    for i, m in enumerate(meta):
        if m["regime"] == "LEO" and m["norad_id"] == 25544:
            lat, lon = subpoint(tuple(r[i, 0]), jds[0], frs[0])
            reference = {"norad_id": m["norad_id"], "name": m["name"],
                         "unix": epoch_unix, "lat_deg": round(lat, 4),
                         "lon_deg": round(lon, 4)}
            break
    if reference is None:
        for i, m in enumerate(meta):
            if m["regime"] == "LEO":
                lat, lon = subpoint(tuple(r[i, 0]), jds[0], frs[0])
                reference = {"norad_id": m["norad_id"], "name": m["name"],
                             "unix": epoch_unix, "lat_deg": round(lat, 4),
                             "lon_deg": round(lon, 4)}
                break
    (ROOT / "data" / "catalog.json").write_text(json.dumps({
        "source": gp_path.name,
        "built_utc": dt.datetime.now(dt.timezone.utc).isoformat(),
        "propagator": "SGP4/SDP4 (general perturbations)",
        "frame": "TEME",
        "position_dtype": "float32",
        "epoch_unix": epoch_unix,
        "step_seconds": args.step,
        "n_samples": n_samples,
        "regime_counts": counts,
        "registration_reference": reference,
        "objects": meta,
    }), encoding="utf-8")

    mb = out.stat().st_size / 1e6
    print(f"\n  wrote data/ephemeris.bin  {mb:.1f} MB  ({n_obj} objects x {n_samples} samples)")
    print(f"  wrote data/catalog.json   {counts}")

    if reference is not None:
        print(f"\n  texture-registration reference (also in catalog.json):")
        print(f"    {reference['name']} (NORAD {reference['norad_id']}) at {start.isoformat()}")
        print(f"    sub-satellite point: lat {reference['lat_deg']:+.2f}, "
              f"lon {reference['lon_deg']:+.2f}")
        print(f"    -> in-engine, this object must sit over that lat/lon.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
