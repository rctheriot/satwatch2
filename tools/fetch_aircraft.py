#!/usr/bin/env python3
"""Fetch a live ADS-B aircraft snapshot from the OpenSky Network.

Why this belongs next to a satellite catalogue: it is the domain immediately
below. Airliners cruise near 10-12 km, which is about 0.0017 Earth radii. The
lowest tracked satellites are roughly forty times higher. Showing the air
picture makes the scale of the space picture concrete in a way no number does.

The result is a SNAPSHOT with velocity and heading, so the engine can
dead-reckon between refreshes rather than showing a frozen sky. That is an
approximation and the display says so.

Output: data/aircraft.json
"""
import argparse
import datetime as dt
import json
import pathlib
import urllib.error
import urllib.request

ROOT = pathlib.Path(__file__).resolve().parent.parent
DATA = ROOT / "data"
URL = "https://opensky-network.org/api/states/all"
USER_AGENT = "satwatch2/1.0 (University of Hawaii LAVA Lab)"

# OpenSky state vector indices.
I_CALLSIGN, I_COUNTRY = 1, 2
I_LON, I_LAT, I_BARO_ALT, I_ON_GROUND = 5, 6, 7, 8
I_VELOCITY, I_HEADING, I_GEO_ALT = 9, 10, 13


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--offline-ok", action="store_true",
                    help="Exit 0 if OpenSky is unreachable (the demo runs without it)")
    args = ap.parse_args()

    DATA.mkdir(parents=True, exist_ok=True)
    req = urllib.request.Request(URL, headers={"User-Agent": USER_AGENT})
    try:
        with urllib.request.urlopen(req, timeout=120) as resp:
            payload = json.loads(resp.read().decode("utf-8"))
    except (urllib.error.URLError, urllib.error.HTTPError, TimeoutError,
            json.JSONDecodeError) as exc:
        print(f"OpenSky unreachable: {exc}")
        return 0 if args.offline_ok else 1

    states = payload.get("states") or []
    out = []
    airborne = 0
    for st in states:
        lat, lon = st[I_LAT], st[I_LON]
        if lat is None or lon is None:
            continue
        if st[I_ON_GROUND]:
            continue                       # parked and taxiing aircraft are noise here
        # Prefer barometric altitude; it is the field most consistently present.
        alt = st[I_BARO_ALT] if st[I_BARO_ALT] is not None else st[I_GEO_ALT]
        if alt is None or alt <= 0:
            continue
        airborne += 1
        out.append([
            round(lat, 4), round(lon, 4), round(alt / 1000.0, 3),
            round(st[I_VELOCITY] or 0.0, 1), round(st[I_HEADING] or 0.0, 1),
            (st[I_CALLSIGN] or "").strip(),
        ])

    alts = sorted(a[2] for a in out)
    median = alts[len(alts) // 2] if alts else 0.0
    (DATA / "aircraft.json").write_text(json.dumps({
        "fetched_utc": dt.datetime.now(dt.timezone.utc).isoformat(),
        "snapshot_unix": payload.get("time", 0),
        "source": "OpenSky Network (ADS-B)",
        "count": len(out),
        "median_altitude_km": median,
        "max_altitude_km": alts[-1] if alts else 0.0,
        "fields": "lat_deg, lon_deg, alt_km, speed_ms, heading_deg, callsign",
        "note": ("Snapshot with velocity and heading; positions are "
                 "dead-reckoned between refreshes, not tracked."),
        "aircraft": out,
    }), encoding="utf-8")

    print(f"  {len(out)} airborne aircraft ({len(states)} state vectors, "
          f"{len(states) - airborne} on ground or incomplete)")
    print(f"  median altitude {median:.1f} km, max {alts[-1] if alts else 0:.1f} km")
    print(f"  snapshot {dt.datetime.fromtimestamp(payload.get('time', 0), dt.timezone.utc).isoformat()}")
    print(f"  -> data/aircraft.json")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
