# SatWatch 2

A stereoscopic 3D visualization of what is in Earth orbit, built in Godot 4.7
for the University of Hawai‘i [LAVA Lab](https://lava.manoa.hawaii.edu/)
display wall.

It draws the tracked-object catalogue — roughly 16,000 satellites, rocket bodies
and debris — around a physically-sized Earth, and layers live data over it:
ground-sensor coverage, the auroral oval, ionospheric electron content, and the
jet stream. A presenter walks through it as a sequence of chapters, each
explaining what it shows.

Successor to the 2016 HTC Vive demo
[SatelliteWatch](https://github.com/rctheriot/SatelliteWatch), rebuilt for a
fixed, shared, 6-metre stereo wall.

## Quick start

Open `project.godot` in Godot 4.7 and press play. That is the whole setup.

Every dataset is committed, including the propagated ephemeris, so a fresh
clone runs immediately with no toolchain, no API keys and no network. **The demo
never touches the network at any point** — every layer reads a local file, so it
cannot stall mid-presentation.

To refresh the data before a demo (needs Python and a connection):

```bash
python3 -m venv .venv
.venv/bin/pip install -r tools/requirements.txt
.venv/bin/python tools/refresh_all.py
```

## Controls

The camera orbits the globe; the viewer stays put on the wall's sweet spot.

| Action | Gamepad | Keyboard / mouse |
|---|---|---|
| Orbit | Right stick | Drag left mouse |
| Zoom | Left stick Y | `W` / `S`, wheel |
| Next / previous chapter | D-pad ← → | `←` `→` |
| Play / pause time | A | `Space` |
| Time rate | Shoulders | `[` `]` |
| Free-fly camera | Y | `F` |
| Reset / quit | — | `R` / `Esc` |

Grabbing the controls during a chapter transition cancels it — the viewer always
wins.

## Chapters

Ordered as an argument rather than a catalogue: build up one orbital regime at a
time, put them together at true scale, then look at specific events.

| | Chapter | Shows |
|---|---|---|
| 1 | Low Earth Orbit | The crowded shells below 2,000 km |
| 2 | Medium Earth Orbit | Navigation constellations near 20,000 km |
| 3 | Geostationary Orbit | 35,786 km, one orbit per day |
| 4 | Highly Elliptical Orbit | Long dwell over one hemisphere |
| 5 | The Full Catalog | All four populations at true scale |
| 6 | Starlink's Constellation | Starlink against the rest of LEO |
| 7 | A Satellite Breakup | 2007 ASAT debris, still tracked |
| 8 | A Satellite Collision | Cosmos 2251 / Iridium 33 |
| 9 | The Tracking Network | Ground coverage and live in-view counts |
| 10 | The Jet Stream | 250 hPa winds at cruise altitude |
| 11 | Space Weather | Auroral oval and ionospheric TEC |

Chapters 9–11 depend on live data. If a dataset is missing, that chapter is
simply absent rather than showing an empty globe.

## Data

Everything is real and attributed on screen, including its limitations.

| Layer | Source |
|---|---|
| Orbital elements | CelesTrak GP, with a reachable mirror fallback |
| Propagation | SGP4/SDP4 via the `sgp4` Python package |
| Earth imagery | NASA Visible Earth (Blue Marble, Black Marble) |
| Aurora, Kp, X-ray flux | NOAA SWPC |
| Ionosphere (TEC) | NOAA SWPC GloTEC |
| Upper winds | Open-Meteo (NOAA GFS) |

This is not an operational product. It screens public general-perturbation
element sets whose positional error grows to kilometres per day, and the
interface says so rather than implying precision it does not have. Altitude is
exaggerated in some chapters to make orbital shells legible; whenever it is, the
panel states the factor.

## Layout

```
main.tscn            the scene; every node is editable in the Godot editor
scripts/             simulation, camera, layers, chapter deck
scripts/ui/          world-space panels (the wall cannot use 2D UI)
shaders/             Earth, aurora, TEC, satellites, trails, starfield
tools/               Python: fetch data, propagate orbits, build assets
tests/               headless checks, run without a GPU
data/                generated — not all of it is in git
docs/                architecture, data, deployment, testing
addons/              the LAVA stereo wall display addon
```

## Documentation

- [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) — how it works, and the
  non-obvious constraints of rendering for a stereo wall
- [docs/DATA.md](docs/DATA.md) — pipelines, honesty, and what each source can
  and cannot support
- [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md) — moving to the wall machine and
  exporting
- [docs/TESTING.md](docs/TESTING.md) — the headless suites and what each guards

## License

MIT — see [LICENSE](LICENSE). Bundled data is redistributed from public sources
under their own terms, listed there.

## Credits

Built by the UH Mānoa LAVA Lab. Stereo wall rendering uses the lab's
`stereo_wall_display` Godot addon (MIT). Earth imagery courtesy of NASA. Space
weather and ionospheric data courtesy of NOAA SWPC.
