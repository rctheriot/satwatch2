# Data

Every dataset is fetched by a Python tool at **build time** and written to
`data/`. The engine only reads those files — there is no `HTTPRequest` anywhere
in `scripts/`. A demo that makes network calls while running is a demo that can
stall in front of an audience, and several of these endpoints are slow or, like
CelesTrak, unreachable from some networks entirely.

Run everything with:

```bash
.venv/bin/python tools/refresh_all.py
```

Each step is independent and non-fatal: a layer whose data is missing drops its
chapter rather than breaking the deck.

## Orbital elements — `tools/fetch_gp.py`

CelesTrak GP data, cached to `data/gp_cache/`.

CelesTrak enforces **one download per two-hour update cycle**; a second request
returns HTTP 403 and repeated abuse gets the IP firewalled. The tool refuses
locally rather than letting the server refuse us.

CelesTrak was unreachable from the development network entirely — DNS resolves,
TCP times out — so `--source tleapi` pages a mirror serving the same elements as
TLE line pairs.

**Deduplication is not optional.** The mirror pages a live dataset and a full
pass takes tens of minutes, so records shift between pages: a raw pull returned
25,706 records containing **7,579 duplicates — 30 % of the catalogue**. A
duplicate is not a harmless extra row; it doubles that object's contribution to
the very density this demo is about, and makes conjunction screening report
objects colliding with themselves at 0.000 km. Deduplicated at fetch, build and
analysis, and the fetch reports coverage against the mirror's own total because
the same reshuffling means some objects are *missed*.

## Propagation — `tools/build_ephemeris.py`

SGP4/SDP4 via the `sgp4` package, into `data/ephemeris.bin`: a 32-byte header
then sample-major `float32` TEME positions in Earth radii, already mapped to
Godot axes. Default span is 3 hours at 30 s steps, which loops cleanly and
covers one to two LEO revolutions.

`float32` rather than `int16` because GDScript has no bulk int16 decode, only
per-element `decode_s16()`, while `PackedByteArray.to_float32_array()` is one
engine call. At 20k objects that is the difference between a frame budget and a
slideshow. 30 s **linear** interpolation is sufficient — LEO chord error is
about 1.0 km, roughly 0.12 mm on the wall.

Three classes of object are dropped, each reported separately:

- SGP4 errors (decayed or bad elements).
- Anything beyond 8 R⊕ (off-scene).
- Element sets whose propagation **contradicts their own mean elements**. That
  last filter matters more than it sounds: a single junk object labelled LEO but
  propagating out to 8 R⊕ would drive the stereo comfort clamp and shrink the
  entire LEO chapter to accommodate content that should not be there.

It also records `max_radius_re` — the radius each object actually *attains* in
the window, not orbit apogee. The comfort clamp is driven by what is on screen;
an HEO object near perigee for the whole span never reaches its apogee.

International designators are expanded from TLE line 1 when the feed omits
`OBJECT_ID` (the mirror does). Without that the field is present but blank and
every debris-family query silently returns nothing.

**Self-checks run on every build** and are not optional: ISS altitude and speed
against known values, and an assertion that orbits sweep west-to-east. The
prograde check is what catches a reflected axis mapping.

The same run also writes `data/orbit_paths.bin`, loaded by `OrbitPathStore`
and drawn by `OrbitTrails` behind the orbit-path toggle (T / gamepad B).
Deliberately a *separate* file rather than a longer `--hours`: the position
ephemeris above is one window shared by every object regardless of period,
which is fine for interpolating where a LEO object is right now — it laps
the 3-hour window several times over — but leaves a 12-hour HEO object only
a quarter of its ellipse traced. `build_orbit_paths()` instead gives every
object its own 96-point loop across exactly ONE of its own orbital periods,
real SGP4 propagation at each point, not an idealized two-body ellipse. A
handful of objects can't be propagated a full period ahead even when the
main window succeeds — elements are only trustworthy near their epoch —
and those degenerate to a single repeated point rather than a corrupt
shape.

## Space weather — `tools/fetch_space_weather.py`

NOAA SWPC: the OVATION auroral oval, planetary Kp, and GOES X-ray flux. On
mission rather than scenery — geomagnetic activity expands the thermosphere,
raising drag in low LEO, so orbits decay faster and predictions degrade.

SWPC's grid carries **spurious values on its equator row**: latitude 0 returns
up to 11 % probability across 299 of 360 cells while ±10° are exactly zero. Left
in, it paints a faint band around the equator that anyone who knows the
phenomenon would spot. Cells below 40° latitude are dropped.

The aurora is a model **forecast**, not an observation, and the panel says so.

## Ionosphere — `tools/fetch_tec.py`

NOAA SWPC GloTEC, a 72×72 grid of total electron content in TECU.

TEC is the direct cause of GNSS ranging error: a signal crossing a dense
ionosphere arrives late and the receiver reports the wrong distance. Sharp
*gradients* matter more than absolute level, which is why accuracy degrades
during solar activity. It is the operational consequence of the same
disturbance the aurora shows the visible signature of, which is why it shares
that chapter rather than having its own.

GloTEC is an assimilative **model**, not a direct measurement.

## Upper winds — `tools/fetch_winds.py`

Open-Meteo (NOAA GFS) at 250 hPa — about 10.5 km, airliner cruise altitude and
where the jet streams live.

Stored as eastward/northward components in m/s, which is what particle
advection needs. Storing speed and a meteorological direction instead would mean
re-deriving the vector every frame and inviting the classic "direction the wind
comes *from*" sign error at runtime.

The grid is 10°, not 5°: Open-Meteo weights a request by location count and a
5° grid (2,376 points) returned HTTP 429 a quarter of the way through. A jet is
about a thousand kilometres wide, so 10° still resolves it and bilinear sampling
smooths the rest. Fetched in batches with backoff and deliberate pacing — it is
a free public service.

## Conjunction screening — `tools/find_conjunctions.py`

A standalone analysis utility. **Not wired into the demo** — the close-approach
chapter was cut because the events it finds are Starlink-on-Starlink, which
tells a viewer little. Kept because it works and found real results.

Two stages, because neither alone is honest: a KD-tree per 30 s sample flags
candidates, then each is re-propagated at 1 s to find the actual time of closest
approach. At 30 s spacing and closing speeds up to 15 km/s, objects move
hundreds of km between samples, so reporting stage-1 separations as miss
distances would be badly wrong.

Two filters the data forced:

- **Self-pairs** from duplicate records (fixed upstream; the guard remains).
- **Co-orbital pairs.** Docked spacecraft pass every distance test at 0.000 km —
  ISS modules with their visiting Dragon/Progress/Cygnus, the Chinese station
  with Tianzhou. They are physically attached but tracked separately, so they
  share one TLE. Relative velocity separates them: a conjunction that matters is
  fast.

**This is not an operational conjunction product.** It screens public GP data
with no covariance; real assessment uses special-perturbations ephemeris and
owner-operator data, and SGP4 error here is comparable to the miss distances
themselves.

## Ground sites — `scripts/ground_sites.gd`

Space Surveillance Network site locations from open sources, held in the engine
rather than fetched.

The distinction that decides what the display may claim:

- **Geometric visibility is exact** and needs no sensor specifications. Whether
  an object is above a site's horizon past an elevation mask is pure geometry,
  so the in-view counts are real numbers. Optical sites carry the two further
  real constraints — site in darkness, target still sunlit — both from the sun
  vector already in hand.
- **Detection capability is not computable.** It depends on transmit power,
  aperture, wavelength and target cross-section, none of which is public. Every
  range is nominal, represents a class of sensor, and is labelled as such.

What is *drawn* is cropped for legibility; what is *counted* is not. At their
nominal ranges ten radar cones at an 87° half-angle merge into one opaque shell.

## What is in git

**Everything**, including the ~67 MB propagated ephemeris and the raw element
snapshot it was built from. A clone runs immediately: no toolchain, no API keys,
no network. That is worth more than a small repository.

It does have a cost worth knowing. Each regenerated `ephemeris.bin` adds another
67 MB to history permanently — git cannot delta-compress it usefully. So
**regenerating is a deliberate act, not something to commit on every rebuild**.
Refresh when the data needs to be current for a demo, not as routine hygiene. If
history does become unwieldy, the answer is Git LFS for `*.bin`, not pruning.

Committing `data/gp_cache/` is also a provenance decision: the exact element set
every position was derived from stays with the build that used it.

## Honesty rules

These are not stylistic:

- Provenance, source and epoch spread are on screen.
- Propagation fidelity is stated — SGP4 error grows to kilometres per day.
- Whenever altitude is exaggerated, the panel gives the factor.
- Models are labelled as models; forecasts as forecasts.
- Nominal figures are labelled nominal.

Overstating fidelity to an audience that works this problem daily costs more
credibility than the demo can buy back.
