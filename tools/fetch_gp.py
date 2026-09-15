#!/usr/bin/env python3
"""Fetch CelesTrak GP element sets to data/gp_cache/.

CelesTrak enforces one download per update cycle (data refreshes every 2 hours).
A second request inside that window returns HTTP 403, and repeated abuse gets the
client IP firewalled. So this script refuses locally rather than letting the server
refuse us -- see https://celestrak.org/NORAD/documentation/gp-data-formats.php
"""
import argparse
import datetime as dt
import json
import pathlib
import sys
import urllib.error
import time
import urllib.request

GP_URL = "https://celestrak.org/NORAD/elements/gp.php"
# Fallback mirror. CelesTrak is the source of record, but it is unreachable from
# some networks (it was from the dev laptop -- DNS resolves, TCP times out).
# This one serves the same elements as TLE line pairs, 100 per page.
TLEAPI_URL = "https://tle.ivanstanojevic.me/api/tle/"
CACHE_DIR = pathlib.Path(__file__).resolve().parent.parent / "data" / "gp_cache"
MIN_REFETCH_INTERVAL = dt.timedelta(hours=2)
STAMP_FORMAT = "%Y%m%dT%H%M%SZ"
USER_AGENT = "lava-orbital-density-wall/0.1 (University of Hawaii LAVA Lab)"


def cache_files(group):
    return sorted(CACHE_DIR.glob(f"{group}_*.json"))


def newest_cache(group):
    files = cache_files(group)
    return files[-1] if files else None


def stamp_of(path):
    stamp = path.stem.rsplit("_", 1)[-1]
    return dt.datetime.strptime(stamp, STAMP_FORMAT).replace(tzinfo=dt.timezone.utc)


def fetch_tleapi():
    """Page through the fallback mirror, emitting records in TLE-pair shape.

    Deduplicated by NORAD ID. The mirror pages a LIVE dataset, and a full pass
    takes tens of minutes, so records shift between pages as objects are updated:
    a raw paged pull returned 25,706 records containing 7,579 duplicates -- 30%
    of the catalog -- which silently inflates object counts and density, and
    makes conjunction screening report objects colliding with themselves at
    0.000 km. The same reshuffling means some objects are MISSED, so the
    coverage figure is reported rather than assumed.
    """
    by_id, page, raw_count = {}, 1, 0
    while True:
        url = f"{TLEAPI_URL}?page-size=100&page={page}"
        req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT,
                                                   "Accept": "application/json"})
        with urllib.request.urlopen(req, timeout=60) as resp:
            body = json.loads(resp.read().decode("utf-8"))
        members = body.get("member", [])
        if not members:
            break
        for m in members:
            raw_count += 1
            rec = {"OBJECT_NAME": m["name"], "NORAD_CAT_ID": m["satelliteId"],
                   "EPOCH": m.get("date", ""),
                   "TLE_LINE1": m["line1"], "TLE_LINE2": m["line2"]}
            prev = by_id.get(rec["NORAD_CAT_ID"])
            # Keep the freshest elements when the same object appears twice.
            if prev is None or rec["EPOCH"] > prev["EPOCH"]:
                by_id[rec["NORAD_CAT_ID"]] = rec
        total = body.get("totalItems", 0)
        print(f"  page {page}: {len(by_id)} unique / {raw_count} fetched "
              f"of {total}", end="\r", flush=True)
        if raw_count >= total:
            break
        page += 1
        time.sleep(0.15)
    print()
    dupes = raw_count - len(by_id)
    print(f"  {len(by_id)} unique objects "
          f"({dupes} duplicate records dropped, {100.0 * dupes / max(raw_count, 1):.0f}%)")
    if total:
        print(f"  coverage: {100.0 * len(by_id) / total:.1f}% of the mirror's "
              f"reported {total} objects")
    return list(by_id.values())


def fetch(group):
    url = f"{GP_URL}?GROUP={group}&FORMAT=json"
    req = urllib.request.Request(url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(req, timeout=120) as resp:
        body = resp.read().decode("utf-8")
    data = json.loads(body)
    if not isinstance(data, list) or not data:
        raise SystemExit(f"Unexpected GP payload for GROUP={group}: {body[:200]!r}")
    return data


def main():
    ap = argparse.ArgumentParser(description=__doc__)
    ap.add_argument("--group", default="active", help="CelesTrak GROUP (default: active)")
    ap.add_argument("--source", choices=("celestrak", "tleapi"), default="celestrak",
                    help="celestrak is the source of record; tleapi is a reachable mirror")
    ap.add_argument("--force", action="store_true",
                    help="Bypass the 2-hour guard. Risks a 403 and an IP ban. Don't.")
    args = ap.parse_args()

    CACHE_DIR.mkdir(parents=True, exist_ok=True)
    now = dt.datetime.now(dt.timezone.utc)

    newest = newest_cache(args.group)
    if newest is not None:
        age = now - stamp_of(newest)
        if age < MIN_REFETCH_INTERVAL and not args.force:
            remaining = MIN_REFETCH_INTERVAL - age
            mins = int(remaining.total_seconds() // 60)
            print(f"REFUSING: {newest.name} is {int(age.total_seconds() // 60)} min old.")
            print(f"CelesTrak updates every 2h; wait {mins} more min (or use the cache as-is).")
            print("The cached snapshot is fine for building ephemeris -- run build_ephemeris.py.")
            return 0

    try:
        if args.source == "tleapi":
            print("Fetching full catalog from fallback mirror ...")
            data = fetch_tleapi()
        else:
            print(f"Fetching GROUP={args.group} from CelesTrak ...")
            data = fetch(args.group)
    except urllib.error.HTTPError as exc:
        if exc.code == 403:
            print("HTTP 403 -- CelesTrak says this data has not updated since our last "
                  "download. Use the existing cache.", file=sys.stderr)
            return 1
        raise
    except urllib.error.URLError as exc:
        print(f"Network error reaching {args.source}: {exc.reason}", file=sys.stderr)
        if args.source == "celestrak":
            print("CelesTrak is unreachable from some networks. "
                  "Retry with --source tleapi.", file=sys.stderr)
        return 1

    out = CACHE_DIR / f"{args.group}_{now.strftime(STAMP_FORMAT)}.json"
    out.write_text(json.dumps(data), encoding="utf-8")
    print(f"Wrote {out.relative_to(CACHE_DIR.parent.parent)} ({len(data)} objects)")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
