#!/usr/bin/env python3
"""Screen the propagated catalog for close approaches.

Two stages, because neither alone is honest:

  1. COARSE -- a KD-tree per 30 s ephemeris sample flags pairs within a generous
     radius. At 30 s spacing and closing speeds up to ~15 km/s, objects move
     hundreds of km between samples, so the sampled minimum is not the real
     miss distance. The coarse radius only has to be wide enough not to miss a
     candidate.

  2. REFINE -- each candidate pair is re-propagated with SGP4 at 1 s around the
     flagged time to find the actual time of closest approach and miss
     distance.

Reporting stage-1 numbers as miss distances would be badly wrong, which is why
the refinement is not optional.

This is NOT an operational conjunction product. It screens public GP (SGP4 mean
element) data with no covariance; real conjunction assessment uses special
perturbations ephemeris and owner-operator data. Positional error here grows to
kilometres per day -- comparable to the miss distances themselves.
"""
import argparse
import datetime as dt
import json
import math
import pathlib
import struct

import numpy as np
from scipy.spatial import cKDTree
from sgp4.api import Satrec, jday
from sgp4 import omm

ROOT = pathlib.Path(__file__).resolve().parent.parent
RE_KM = 6378.137
HEADER_SIZE = 32


def load_ephemeris(path):
    raw = path.read_bytes()
    magic, version, n_obj, n_samples, epoch_unix, step, _ = struct.unpack(
        "<4sIII d f f", raw[:HEADER_SIZE])
    if magic != b"SATE":
        raise SystemExit(f"{path} is not an ephemeris file")
    pos = np.frombuffer(raw, dtype="<f4", offset=HEADER_SIZE)
    pos = pos.reshape(n_samples, n_obj, 3)
    return pos, epoch_unix, step


def rebuild_satrecs(gp_path, norad_ids):
    """Re-create Satrec objects for just the candidates, keyed by NORAD ID."""
    wanted = set(norad_ids)
    out = {}
    for rec in json.loads(gp_path.read_text(encoding="utf-8")):
        nid = int(rec.get("NORAD_CAT_ID", 0))
        if nid not in wanted:
            continue
        try:
            if "TLE_LINE1" in rec:
                out[nid] = Satrec.twoline2rv(rec["TLE_LINE1"], rec["TLE_LINE2"])
            else:
                sat = Satrec()
                omm.initialize(sat, rec)
                out[nid] = sat
        except (ValueError, KeyError, RuntimeError):
            pass
    return out


def track(sat_a, sat_b, tca_unix, half_window_s, step_s):
    """Fine relative geometry around TCA, for the magnified inset.

    The 30 s ephemeris cannot show a 1 km approach -- the objects move hundreds
    of km between samples -- so the inset needs its own track. Positions are in
    km relative to the pair's midpoint at TCA, which is the natural frame for a
    magnified view and keeps the numbers small.
    """
    mid = None
    rows = []
    n = int(2 * half_window_s / step_s) + 1
    for i in range(n):
        t = tca_unix - half_window_s + i * step_s
        d = dt.datetime.fromtimestamp(t, dt.timezone.utc)
        jd, fr = jday(d.year, d.month, d.day, d.hour, d.minute,
                      d.second + d.microsecond * 1e-6)
        ea, ra, _ = sat_a.sgp4(jd, fr)
        eb, rb, _ = sat_b.sgp4(jd, fr)
        if ea != 0 or eb != 0:
            continue
        if mid is None and abs(t - tca_unix) < step_s / 2.0:
            mid = [(ra[k] + rb[k]) / 2.0 for k in range(3)]
        rows.append((t, ra, rb))
    if mid is None:
        return []
    out = []
    for t, ra, rb in rows:
        out.append([round(t - tca_unix, 2)]
                   + [round(ra[k] - mid[k], 4) for k in range(3)]
                   + [round(rb[k] - mid[k], 4) for k in range(3)])
    return out


def refine(sat_a, sat_b, t_center_unix, half_window_s, step_s):
    """True TCA and miss distance by 1 s propagation around the candidate."""
    best = (1e18, t_center_unix, 0.0)
    n = int(2 * half_window_s / step_s) + 1
    for i in range(n):
        t = t_center_unix - half_window_s + i * step_s
        d = dt.datetime.fromtimestamp(t, dt.timezone.utc)
        jd, fr = jday(d.year, d.month, d.day, d.hour, d.minute,
                      d.second + d.microsecond * 1e-6)
        ea, ra, va = sat_a.sgp4(jd, fr)
        eb, rb, vb = sat_b.sgp4(jd, fr)
        if ea != 0 or eb != 0:
            continue
        sep = math.dist(ra, rb)
        if sep < best[0]:
            rel = math.dist(va, vb)
            best = (sep, t, rel)
    return best


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--coarse-km", type=float, default=25.0,
                    help="Stage-1 flag radius (default 25)")
    ap.add_argument("--report-km", type=float, default=5.0,
                    help="Keep refined approaches closer than this (default 5)")
    ap.add_argument("--min-rel-kms", type=float, default=0.1,
                    help="Ignore approaches slower than this (default 0.1)")
    ap.add_argument("--top", type=int, default=40)
    ap.add_argument("--tracks", type=int, default=6,
                    help="How many top events get a fine track (default 6)")
    ap.add_argument("--gp", type=pathlib.Path)
    args = ap.parse_args()

    catalog = json.loads((ROOT / "data" / "catalog.json").read_text())
    objects = catalog["objects"]
    pos, epoch_unix, step = load_ephemeris(ROOT / "data" / "ephemeris.bin")
    n_samples, n_obj, _ = pos.shape
    if n_obj != len(objects):
        raise SystemExit("ephemeris and catalog disagree -- rebuild both")

    coarse_re = args.coarse_km / RE_KM
    print(f"Stage 1: screening {n_obj} objects over {n_samples} samples "
          f"at {args.coarse_km:.0f} km ...")

    # Keep the closest sampled separation per pair.
    candidates = {}
    for s in range(n_samples):
        tree = cKDTree(pos[s])
        for i, j in tree.query_pairs(coarse_re):
            d = float(np.linalg.norm(pos[s, i] - pos[s, j])) * RE_KM
            key = (i, j)
            if key not in candidates or d < candidates[key][0]:
                candidates[key] = (d, s)
    print(f"  {len(candidates)} candidate pairs")

    gp_path = args.gp
    if gp_path is None:
        gp_path = sorted((ROOT / "data" / "gp_cache").glob("*.json"))[-1]
    ids = {objects[i]["norad_id"] for pair in candidates for i in pair}
    print(f"Stage 2: refining at 1 s around each candidate "
          f"({len(ids)} distinct objects) ...")
    sats = rebuild_satrecs(gp_path, ids)

    results = []
    co_orbital = 0
    for (i, j), (coarse_d, s) in candidates.items():
        a, b = objects[i], objects[j]
        # An object cannot conjunct with itself. Should be impossible after the
        # builder's dedupe, but this is the place where such a bug is loudest
        # (0.000 km at 0.00 km/s), so it stays.
        if a["norad_id"] == b["norad_id"]:
            continue
        sa, sb = sats.get(a["norad_id"]), sats.get(b["norad_id"])
        if sa is None or sb is None:
            continue
        t_center = epoch_unix + s * step
        miss, tca, rel_v = refine(sa, sb, t_center, half_window_s=45.0, step_s=1.0)
        if miss > args.report_km:
            continue
        # Docked and formation-flying objects pass every distance test at
        # 0.000 km: ISS modules with their visiting Dragon/Progress/Cygnus, the
        # Chinese station with Tianzhou. They are physically ATTACHED but
        # tracked as separate objects, so they share essentially one TLE.
        # Relative velocity is what separates them from a real approach -- a
        # conjunction that matters is fast.
        if rel_v < args.min_rel_kms:
            co_orbital += 1
            continue
        results.append({
            "a_index": i, "b_index": j,
            "a_name": a["name"], "b_name": b["name"],
            "a_norad": a["norad_id"], "b_norad": b["norad_id"],
            "a_regime": a["regime"], "b_regime": b["regime"],
            "miss_km": round(miss, 3),
            "coarse_km": round(coarse_d, 1),
            "relative_speed_kms": round(rel_v, 3),
            "tca_unix": round(tca, 1),
            "tca_utc": dt.datetime.fromtimestamp(tca, dt.timezone.utc).isoformat(),
        })

    results.sort(key=lambda r: r["miss_km"])
    results = results[:args.top]

    # Fine tracks only for the events a chapter might actually show.
    print(f"  building fine tracks for the top {min(args.tracks, len(results))} ...")
    for r in results[:args.tracks]:
        sa, sb = sats[r["a_norad"]], sats[r["b_norad"]]
        r["track_step_s"] = 1.0
        r["track_half_window_s"] = 120.0
        # [t_offset, ax, ay, az, bx, by, bz], km from the pair midpoint at TCA,
        # in TEME. The engine maps to its own axes with the same (x, z, -y).
        r["track"] = track(sa, sb, r["tca_unix"], 120.0, 1.0)

    out = ROOT / "data" / "conjunctions.json"
    out.write_text(json.dumps({
        "built_utc": dt.datetime.now(dt.timezone.utc).isoformat(),
        "source": catalog.get("source", ""),
        "method": "SGP4 GP screening, 30 s coarse pass refined at 1 s",
        "caveat": ("Screening of public GP data without covariance. Not an "
                   "operational conjunction product; SGP4 positional error is "
                   "comparable to these miss distances."),
        "coarse_km": args.coarse_km,
        "report_km": args.report_km,
        "min_relative_speed_kms": args.min_rel_kms,
        "co_orbital_excluded": co_orbital,
        "events": results,
    }, indent=1), encoding="utf-8")

    print(f"\n  excluded {co_orbital} co-orbital pairs "
          f"(under {args.min_rel_kms} km/s -- docked or formation-flying)")
    print(f"  {len(results)} approaches under {args.report_km:.0f} km "
          f"-> data/conjunctions.json\n")
    for r in results[:12]:
        print(f"  {r['miss_km']:7.3f} km  {r['relative_speed_kms']:6.2f} km/s  "
              f"{r['tca_utc'][11:19]}  {r['a_name'][:26]:26s} / {r['b_name'][:26]}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
