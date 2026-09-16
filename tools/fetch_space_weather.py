#!/usr/bin/env python3
"""Fetch NOAA SWPC space weather: the OVATION aurora oval and the Kp index.

Why this belongs in an SDA demo rather than being scenery: geomagnetic storms
heat and expand the thermosphere, which raises drag on everything in low LEO.
Orbits decay faster, predictions degrade, and objects get temporarily lost.
The aurora oval is the visible signature of the same disturbance.

Outputs:
  data/aurora.png          360x181 8-bit, red channel = probability (0-100%)
  data/space_weather.json  Kp, X-ray flux, and the aurora's own timestamps
"""
import argparse
import datetime as dt
import json
import pathlib
import struct
import urllib.error
import urllib.request
import zlib

ROOT = pathlib.Path(__file__).resolve().parent.parent
DATA = ROOT / "data"
USER_AGENT = "satwatch2/1.0 (University of Hawaii LAVA Lab)"

AURORA_URL = "https://services.swpc.noaa.gov/json/ovation_aurora_latest.json"
KP_URL = "https://services.swpc.noaa.gov/json/planetary_k_index_1m.json"
XRAY_URL = "https://services.swpc.noaa.gov/json/goes/primary/xrays-1-day.json"

GRID_W, GRID_H = 360, 181
## Aurora does not occur below this latitude; see build_aurora().
AURORA_MIN_LAT = 40


def get(url):
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(req, timeout=90) as resp:
        return json.loads(resp.read().decode("utf-8"))


def write_gray_png(path, width, height, rows):
    """Minimal 8-bit greyscale PNG. Avoids a Pillow dependency for one image."""
    raw = b"".join(b"\x00" + bytes(r) for r in rows)

    def chunk(tag, data):
        c = tag + data
        return (struct.pack(">I", len(data)) + c
                + struct.pack(">I", zlib.crc32(c) & 0xFFFFFFFF))

    ihdr = struct.pack(">IIBBBBB", width, height, 8, 0, 0, 0, 0)
    path.write_bytes(b"\x89PNG\r\n\x1a\n"
                     + chunk(b"IHDR", ihdr)
                     + chunk(b"IDAT", zlib.compress(raw, 9))
                     + chunk(b"IEND", b""))


def build_aurora(payload):
    """OVATION coordinates are [longitude 0..359, latitude -90..90, probability].

    Geographic, not inertial -- so in the engine this texture rides the Earth
    mesh and inherits its GMST rotation, exactly like the surface imagery.

    Image rows run north to south to match the equirectangular convention the
    Earth shader already uses (v = 0 at +90 latitude).
    """
    grid = [[0] * GRID_W for _ in range(GRID_H)]
    dropped = 0
    for lon, lat, prob in payload["coordinates"]:
        # SWPC's grid carries spurious values on the equator row: latitude 0
        # comes back with up to 11% probability across 299 of 360 cells, while
        # +/-10 are exactly zero. It is an artefact of their gridding, not
        # aurora, and left in it paints a faint band round the equator that
        # anyone who knows the phenomenon would spot immediately. Aurora does
        # not occur below about 40 degrees even in severe storms.
        if abs(lat) < AURORA_MIN_LAT:
            dropped += prob > 0
            continue
        x = int(lon) % GRID_W
        y = int(90 - lat)
        if 0 <= y < GRID_H:
            grid[y][x] = max(0, min(255, int(prob * 255 / 100)))
    if dropped:
        print(f"  dropped {dropped} nonzero cells below "
              f"{AURORA_MIN_LAT} deg latitude (SWPC gridding artefact)")
    return grid


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--offline-ok", action="store_true",
                    help="Exit 0 if SWPC is unreachable (the demo runs without it)")
    args = ap.parse_args()

    DATA.mkdir(parents=True, exist_ok=True)
    try:
        aurora = get(AURORA_URL)
        kp = get(KP_URL)
        xray = get(XRAY_URL)
    except (urllib.error.URLError, urllib.error.HTTPError, TimeoutError) as exc:
        print(f"SWPC unreachable: {exc}")
        return 0 if args.offline_ok else 1

    grid = build_aurora(aurora)
    write_gray_png(DATA / "aurora.png", GRID_W, GRID_H, grid)

    peak = max(max(r) for r in grid) * 100 // 255
    latest_kp = kp[-1] if kp else {}
    # The 1-day X-ray series interleaves both GOES energy bands.
    long_band = [x for x in xray if x.get("energy") == "0.1-0.8nm"]
    latest_xray = long_band[-1] if long_band else {}

    (DATA / "space_weather.json").write_text(json.dumps({
        "fetched_utc": dt.datetime.now(dt.timezone.utc).isoformat(),
        "source": "NOAA SWPC (OVATION aurora model, planetary K index, GOES XRS)",
        "aurora_observation_utc": aurora.get("Observation Time", ""),
        "aurora_forecast_utc": aurora.get("Forecast Time", ""),
        "aurora_peak_probability": peak,
        "kp_index": latest_kp.get("kp_index"),
        "kp_estimated": latest_kp.get("estimated_kp"),
        "kp_time_utc": latest_kp.get("time_tag", ""),
        "xray_flux_wm2": latest_xray.get("flux"),
        "xray_class": _xray_class(latest_xray.get("flux")),
        "note": ("Aurora is a model forecast, not an observation. Geomagnetic "
                 "activity raises thermospheric drag in low LEO, degrading "
                 "orbit prediction."),
    }, indent=1), encoding="utf-8")

    print(f"  aurora.png        {GRID_W}x{GRID_H}, peak probability {peak}%")
    print(f"  observation       {aurora.get('Observation Time', '?')}")
    print(f"  forecast          {aurora.get('Forecast Time', '?')}")
    print(f"  Kp                {latest_kp.get('kp_index')} "
          f"(estimated {latest_kp.get('estimated_kp')}) at "
          f"{latest_kp.get('time_tag', '?')}")
    print(f"  GOES X-ray        {latest_xray.get('flux')} W/m^2 "
          f"= class {_xray_class(latest_xray.get('flux'))}")
    return 0


def _xray_class(flux):
    if not flux:
        return "?"
    for threshold, letter in ((1e-4, "X"), (1e-5, "M"), (1e-6, "C"),
                              (1e-7, "B"), (0.0, "A")):
        if flux >= threshold:
            return f"{letter}{flux / max(threshold, 1e-8):.1f}"
    return "A"


if __name__ == "__main__":
    raise SystemExit(main())
