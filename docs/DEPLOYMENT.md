# Deployment

## Short answer

Copy the folder, run one command, open it in Godot. **The running demo never
touches the network** — every layer reads a local file. But two generated files
are deliberately not in git, so run the refresh once on a machine that does have
a connection:

```
python -m venv .venv
.venv\Scripts\pip install -r tools\requirements.txt      # Windows
.venv\Scripts\python tools\refresh_all.py
```

Then open `project.godot` in Godot 4.7 and export with the **Wall (Windows)**
preset, or just run it from the editor.

## What travels with the folder

| | Status | Size |
|---|---|---|
| Earth day / night textures | in git | 3.0 MB |
| Aurora, TEC, space weather, winds, aircraft | in git | ~1 MB |
| `data/catalog.json` (object metadata) | in git | 4 MB |
| `data/ephemeris.bin` (propagated positions) | **not in git** | 70 MB |
| `data/gp_cache/*.json` (raw elements) | **not in git** | 6.5 MB |

`ephemeris.bin` is excluded because it is rebuilt every time elements are
refreshed, and committing it would add another 70 MB blob to history each time.
If you are copying the **folder** rather than cloning, it comes along with
everything else and nothing needs regenerating at all.

So:

- **Copying the folder** (USB, network share, zip): everything is already there.
  Nothing to fetch. It will run offline immediately.
- **Cloning from git**: run `tools/refresh_all.py` once.

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
TEC, winds and aircraft are snapshots of the moment and are worth refreshing the
morning of a demo. CelesTrak allows one download per two-hour update cycle and
the fetch tool enforces that locally.

## Platform notes

- `project.godot` sets `rendering_device/driver.windows="d3d12"`.
- The stereo output is 9600x1620 borderless at 0,0 — `edit_mode = false` on the
  `StereoWallDisplay` node, or run with `-- --stereo 4800 1620`.
- Development happens on macOS, so full-resolution stereo comfort has never been
  validated off the wall. See [TESTING.md](TESTING.md) for what can only be checked
  there.
