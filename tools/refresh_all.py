#!/usr/bin/env python3
"""Refresh every live dataset and rebuild the ephemeris, in one command.

Run this BEFORE a demo, on a machine with network access. Nothing in the engine
touches the network -- every layer reads a local file that these tools produce.
That is deliberate: a demo that makes HTTP requests while running is a demo that
can stall in front of an audience, and several of these endpoints are slow or,
like CelesTrak, unreachable from some networks entirely.

Each step is independent and failure is non-fatal: a layer whose data is missing
simply drops its chapter (see tests/verify_optional_data.gd), so a partial
refresh degrades rather than breaks.
"""
import pathlib
import subprocess
import sys

TOOLS = pathlib.Path(__file__).resolve().parent
PYTHON = sys.executable

STEPS = [
    ("Orbital elements", ["fetch_gp.py", "--source", "tleapi"], True),
    ("Ephemeris", ["build_ephemeris.py"], False),
    ("Space weather", ["fetch_space_weather.py", "--offline-ok"], True),
    ("Ionosphere (TEC)", ["fetch_tec.py", "--offline-ok"], True),
    ("Upper winds", ["fetch_winds.py", "--offline-ok"], True),
]


def main():
    failures = []
    for label, argv, optional in STEPS:
        script = TOOLS / argv[0]
        if not script.exists():
            print(f"\n=== {label}: {argv[0]} not present, skipping ===")
            continue
        print(f"\n=== {label} ===")
        result = subprocess.run([PYTHON, str(script)] + argv[1:])
        if result.returncode != 0:
            failures.append(label)
            if not optional:
                print(f"\n{label} failed and is required -- stopping.")
                return 1

    print("\n" + "=" * 60)
    if failures:
        print("Refreshed with failures in: " + ", ".join(failures))
        print("Those layers will drop their chapters rather than break the deck.")
    else:
        print("All datasets refreshed. The demo now runs entirely offline.")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
