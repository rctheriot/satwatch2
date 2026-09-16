# Deployment

## Short answer

Copy the folder or clone the repo, open `project.godot` in Godot 4.7, and run
it. Nothing needs fetching or generating — every dataset is committed, including
the propagated ephemeris. **The running demo never touches the network.**

Export with the **Wall (Windows)** preset when you need a standalone build.

Refresh the data before a demo, on a machine with a connection:

```
python -m venv .venv
.venv\Scripts\pip install -r tools\requirements.txt      # Windows
.venv\Scripts\python tools\refresh_all.py
```

## What travels with the folder

All of it — about 250 MB, of which 67 MB is the ephemeris and 3 MB is Earth
imagery. Copying the folder and cloning the repo give the same result.

Regenerating the ephemeris adds another 67 MB to git history permanently, so do
it when the data needs to be current rather than as routine hygiene.

## Why nothing fetches at runtime

Every dataset is pulled by a Python tool at build time and written to `data/`.
The engine only ever reads those files — there is no `HTTPRequest` anywhere in
`scripts/`. That is deliberate: a demo that makes network calls while running is
a demo that can stall in front of an audience, and several of these endpoints
are slow or, like CelesTrak, unreachable from some networks entirely.

Any layer whose data is missing drops its own chapter rather than showing an
empty globe, so a partial refresh degrades gracefully. Verified in
`tests/verify_optional_data.gd`.

## Exporting

`export_presets.cfg` carries a **Wall (Windows)** preset. The important part is
`include_filter`:

```
include_filter="data/*.bin,data/*.json,data/*.png,assets/*.jpg"
```

Godot's `all_resources` export does **not** include plain files, and the
ephemeris, catalog and every data snapshot are plain files. Without that filter
the build runs on the dev machine and shows an empty globe on the wall. The
exported `.pck` is self-contained — the wall machine needs neither Python nor a
network.

## Refreshing before a demo

```
.venv\Scripts\python tools\refresh_all.py
```

Runs every fetch and rebuilds the ephemeris. Orbital elements go stale slowly
(SGP4 error grows to kilometres per day, so within a few days is fine); aurora,
TEC and winds are snapshots of the moment and are worth refreshing the morning
of a demo. CelesTrak allows one download per two-hour update cycle and
the fetch tool enforces that locally.

## Platform notes

- `project.godot` sets `rendering_device/driver.windows="d3d12"`.
- The stereo output is 9600x1620 borderless at 0,0 — `edit_mode = false` on the
  `StereoWallDisplay` node, or run with `-- --stereo 4800 1620`.
- Development happens on macOS, so full-resolution stereo comfort has never been
  validated off the wall. See [TESTING.md](TESTING.md) for what can only be checked
  there.
