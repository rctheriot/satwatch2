#!/usr/bin/env python3
"""Fetch a global 250 hPa wind field (the jet stream level) from Open-Meteo/GFS.

250 hPa is roughly 10.5 km -- airliner cruise altitude, and where the jet
streams live. Winds there routinely exceed 200 km/h and directly set transit
times, fuel loads and route choice, which is why this sits alongside the live
aircraft layer rather than being weather decoration.

Open-Meteo caps a request URI at roughly a hundred coordinates, so the grid is
fetched in batches. It is paced deliberately: this is a free public service.

Output: data/winds.json -- grid definition plus eastward/northward components
in m/s, which is what a particle advection needs. Storing speed and a
meteorological direction instead would mean re-deriving the vector every frame,
and inviting the classic "direction the wind comes FROM" sign error at runtime.
"""
import argparse
import datetime as dt
import json
import math
import pathlib
import time
import urllib.error
import urllib.parse
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parent.parent
DATA = ROOT / "data"
URL = "https://api.open-meteo.com/v1/forecast"
USER_AGENT = "lava-orbital-density-wall/0.1 (University of Hawaii LAVA Lab)"

## 10 degrees, not 5. Open-Meteo's free tier weights a request by the number of
## locations in it, so a 5-degree grid (2,376 points) hit HTTP 429 a quarter of
## the way through. A jet stream is a feature about a thousand kilometres wide,
## so 10 degrees still resolves it, and bilinear sampling at runtime smooths the
## rest. Resolution is cheap to raise later if a paid key is available.
LON_STEP = 10.0
LAT_STEP = 10.0
LAT_MIN, LAT_MAX = -80.0, 80.0
BATCH = 100
## Between batches. Deliberately unhurried: this is a free public service and
## the whole grid is fetched once, before a demo, not during one.
PACE_SECONDS = 2.0
MAX_RETRIES = 4
PRESSURE_LEVEL = "250hPa"


def grid_points():
    lons = [-180.0 + i * LON_STEP for i in range(int(360 / LON_STEP))]
    lats = [LAT_MIN + j * LAT_STEP
            for j in range(int((LAT_MAX - LAT_MIN) / LAT_STEP) + 1)]
    return lons, lats


def fetch_batch(coords):
    """One batch, with backoff. A 429 here is a pacing problem, not a failure:
    waiting and retrying costs seconds and saves the whole fetch."""
    for attempt in range(MAX_RETRIES):
        try:
            return _fetch_batch_once(coords)
        except urllib.error.HTTPError as exc:
            if exc.code != 429 or attempt == MAX_RETRIES - 1:
                raise
            wait = PACE_SECONDS * (2 ** (attempt + 1))
            print(f"\n  rate limited, waiting {wait:.0f}s ...", flush=True)
            time.sleep(wait)
    raise RuntimeError("unreachable")


def _fetch_batch_once(coords):
    q = urllib.parse.urlencode({
        "latitude": ",".join(f"{c[0]:.2f}" for c in coords),
        "longitude": ",".join(f"{c[1]:.2f}" for c in coords),
        "hourly": f"wind_speed_{PRESSURE_LEVEL},wind_direction_{PRESSURE_LEVEL}",
        "forecast_days": "1",
        "models": "gfs_seamless",
    })
    req = urllib.request.Request(f"{URL}?{q}", headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(req, timeout=120) as resp:
        body = json.loads(resp.read().decode("utf-8"))
    return body if isinstance(body, list) else [body]


def pick_hour(entry):
    """Index of the hour nearest now, so the field is current rather than 00Z."""
    times = entry.get("hourly", {}).get("time", [])
    if not times:
        return None
    now = dt.datetime.now(dt.timezone.utc).replace(tzinfo=None)
    best, best_delta = 0, None
    for i, t in enumerate(times):
        delta = abs((dt.datetime.fromisoformat(t) - now).total_seconds())
        if best_delta is None or delta < best_delta:
            best, best_delta = i, delta
    return best


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--offline-ok", action="store_true")
    args = ap.parse_args()

    DATA.mkdir(parents=True, exist_ok=True)
    lons, lats = grid_points()
    coords = [(lat, lon) for lat in lats for lon in lons]
    total = len(coords)
    print(f"Fetching {PRESSURE_LEVEL} winds on a {len(lons)}x{len(lats)} grid "
          f"({total} points, {math.ceil(total / BATCH)} requests) ...")

    u_flat = [0.0] * total
    v_flat = [0.0] * total
    speeds = []
    valid_time = ""
    try:
        for start in range(0, total, BATCH):
            chunk = coords[start:start + BATCH]
            results = fetch_batch(chunk)
            for k, entry in enumerate(results):
                idx = pick_hour(entry)
                if idx is None:
                    continue
                h = entry["hourly"]
                if not valid_time:
                    valid_time = h["time"][idx]
                speed_kmh = h[f"wind_speed_{PRESSURE_LEVEL}"][idx]
                direction = h[f"wind_direction_{PRESSURE_LEVEL}"][idx]
                if speed_kmh is None or direction is None:
                    continue
                speed = speed_kmh / 3.6
                # Meteorological convention: direction is where the wind comes
                # FROM, so the vector it blows TOWARD is the negative.
                rad = math.radians(direction)
                u_flat[start + k] = -speed * math.sin(rad)   # eastward
                v_flat[start + k] = -speed * math.cos(rad)   # northward
                speeds.append(speed)
            print(f"  {min(start + BATCH, total)}/{total}", end="\r", flush=True)
            time.sleep(PACE_SECONDS)
        print()
    except (urllib.error.URLError, urllib.error.HTTPError, TimeoutError,
            ValueError) as exc:
        print(f"\nOpen-Meteo unreachable: {exc}")
        return 0 if args.offline_ok else 1

    if not speeds:
        print("No wind data returned")
        return 0 if args.offline_ok else 1

    peak = max(speeds)
    (DATA / "winds.json").write_text(json.dumps({
        "fetched_utc": dt.datetime.now(dt.timezone.utc).isoformat(),
        "valid_time": valid_time,
        "source": "Open-Meteo (NOAA GFS)",
        "level": PRESSURE_LEVEL,
        "approx_altitude_km": 10.5,
        "lon_min": -180.0, "lon_step": LON_STEP, "lon_count": len(lons),
        "lat_min": LAT_MIN, "lat_step": LAT_STEP, "lat_count": len(lats),
        "peak_speed_ms": round(peak, 1),
        "mean_speed_ms": round(sum(speeds) / len(speeds), 1),
        "u": [round(x, 2) for x in u_flat],
        "v": [round(x, 2) for x in v_flat],
        "note": "Eastward/northward components in m/s at the jet stream level.",
    }), encoding="utf-8")

    print(f"  valid {valid_time}")
    print(f"  peak {peak:.0f} m/s ({peak * 3.6:.0f} km/h), "
          f"mean {sum(speeds) / len(speeds):.0f} m/s")
    print(f"  -> data/winds.json")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
