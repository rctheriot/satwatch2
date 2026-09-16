#!/usr/bin/env python3
"""Fetch NOAA SWPC GloTEC: global total electron content.

TEC is the number of electrons in a column through the ionosphere, in TECU
(10^16 electrons per square metre). It matters here because it is the direct
cause of GNSS ranging error: a signal crossing a dense ionosphere arrives late,
and the receiver reports the wrong distance. High and, more importantly, sharply
VARYING TEC is why GPS accuracy degrades during solar activity.

That makes it the operational consequence of the same disturbance the aurora
layer shows the visible signature of.

Outputs:
  data/tec.png       72x72, red channel = TEC scaled to TEC_FULL_SCALE
  data/tec.json      timestamp, observed range, and the scale used
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
INDEX_URL = "https://services.swpc.noaa.gov/products/glotec/geojson_2d_urt.json"
BASE = "https://services.swpc.noaa.gov"
USER_AGENT = "satwatch2/1.0 (University of Hawaii LAVA Lab)"

# GloTEC grid: 5 degrees of longitude by 2.5 of latitude.
GRID_W, GRID_H = 72, 72
LON_STEP, LAT_STEP = 5.0, 2.5
LON0, LAT0 = -177.5, -88.75
## Quiet mid-latitude TEC is 10-30 TECU; severe storms reach well past 100.
## Fixed rather than auto-scaled so the colour of a region means the same thing
## from one fetch to the next -- an auto-scaled map hides a storm by redefining
## what red means.
TEC_FULL_SCALE = 120.0


def get(url):
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(req, timeout=90) as resp:
        return json.loads(resp.read().decode("utf-8"))


def write_gray_png(path, width, height, rows):
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


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--offline-ok", action="store_true")
    args = ap.parse_args()

    DATA.mkdir(parents=True, exist_ok=True)
    try:
        index = get(INDEX_URL)
        latest = max(index, key=lambda e: e["time_tag"])
        grid = get(BASE + latest["url"])
    except (urllib.error.URLError, urllib.error.HTTPError, TimeoutError,
            ValueError) as exc:
        print(f"SWPC GloTEC unreachable: {exc}")
        return 0 if args.offline_ok else 1

    features = grid.get("features", [])
    if not features:
        print("GloTEC returned no features")
        return 0 if args.offline_ok else 1

    # Rows north to south, matching the equirectangular convention the Earth
    # shader already uses (v = 0 at +90 latitude).
    rows = [[0] * GRID_W for _ in range(GRID_H)]
    values = []
    for feat in features:
        tec = feat["properties"].get("tec")
        if tec is None:
            continue
        lon, lat = feat["geometry"]["coordinates"]
        x = int(round((lon - LON0) / LON_STEP)) % GRID_W
        y = GRID_H - 1 - int(round((lat - LAT0) / LAT_STEP))
        if 0 <= y < GRID_H:
            rows[y][x] = max(0, min(255, int(tec / TEC_FULL_SCALE * 255)))
            values.append(tec)

    write_gray_png(DATA / "tec.png", GRID_W, GRID_H, rows)
    (DATA / "tec.json").write_text(json.dumps({
        "fetched_utc": dt.datetime.now(dt.timezone.utc).isoformat(),
        "observation_utc": grid.get("time_tag", latest["time_tag"]),
        "source": "NOAA SWPC GloTEC (assimilative ionosphere model)",
        "product": grid.get("product", ""),
        "grid": {"width": GRID_W, "height": GRID_H,
                 "lon_step": LON_STEP, "lat_step": LAT_STEP},
        "full_scale_tecu": TEC_FULL_SCALE,
        "min_tecu": round(min(values), 2),
        "max_tecu": round(max(values), 2),
        "mean_tecu": round(sum(values) / len(values), 2),
        "note": ("TEC drives GNSS ranging error. A model assimilating ground "
                 "and space observations, not a direct measurement."),
    }, indent=1), encoding="utf-8")

    print(f"  tec.png    {GRID_W}x{GRID_H}, {len(values)} cells")
    print(f"  observed   {grid.get('time_tag', '?')}")
    print(f"  TEC        {min(values):.1f} .. {max(values):.1f} TECU "
          f"(mean {sum(values) / len(values):.1f}), full scale {TEC_FULL_SCALE:.0f}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
