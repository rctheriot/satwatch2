# Orbital Density Wall

Stereoscopic visualization of the tracked-object catalog for LAVA's 6 m display
wall (Godot 4.7). A successor to the 2016 [SatelliteWatch](https://github.com/rctheriot/SatelliteWatch)
Vive demo, rebuilt for a fixed, shared, ultra-wide stereo wall.

The wall is the design constraint. It is not a headset: there is one correct
viewing position, the audience stands, and nobody can walk through the scene.
What this display does that a monitor cannot is make **the layered shell
structure of Earth orbit legible in depth**. That is the demo; everything else
is a chapter on top of it.

## Quick start

```bash
python3 -m venv .venv && .venv/bin/pip install -r tools/requirements.txt
.venv/bin/python tools/fetch_gp.py --source tleapi    # or --source celestrak
.venv/bin/python tools/build_ephemeris.py
/Applications/Godot.app/Contents/MacOS/Godot --path . --headless --import
/Applications/Godot.app/Contents/MacOS/Godot --path .
```

Earth textures are not committed — see `assets/README.md`. Without them the
globe falls back to flat shading and everything else still runs.

## Controls

The viewer never moves. Every control transforms the **content**.

Zoom range: the globe spans roughly 27 % to 56 % of the wall width.

| Action | Gamepad | Keyboard / mouse |
|---|---|---|
| Orbit globe | Right stick | Drag LMB |
| Zoom | Left stick Y | `W` / `S`, wheel |
| Time rate | Shoulders | `[` / `]` |
| Play / pause | A | `Space` |
| Chapter | D-pad ←→ | `←` `→` |
| Select under reticle | X | RMB |

## Scene structure

`main.tscn` holds the real node tree, editable in the Godot editor — EarthRig,
EarthMesh, Atmosphere, SatelliteField, UIRig, Selection, SimClock, ChapterDeck,
WorldEnvironment and Sun, with their meshes, shader materials and exported
properties set there. `scripts/main.gd` only wires them together and drives the
per-frame updates.

Two things are still created at runtime, because they are data-driven and
authoring them would just mean they drift from the builder output:

- the `MultiMesh` inside `SatelliteField` (instance count = catalog size)
- the `SubViewport` panels inside `UIRig` (content depends on the catalog)

Chapter presets live in `scripts/chapter_deck.gd:_default_deck()` rather than as
`.tres` files, so the whole deck is reviewable in one place.

## Architecture notes

These are the non-obvious constraints. Each one produced a bug during
development that still looked plausible on screen.

**The addon's virtual wall is head-relative.**
`stereo_wall_display.gd:_update_stereo_cameras()` rebuilds the screen corners
from the camera pivot every frame, so moving or turning the player shears the
whole scene against a wall that is physically fixed. There is no fly-through.
The addon is neutralised by zeroing `move_speed`, `look_sensitivity` and
`controller_look_speed` in `main.tscn` — it is not forked — and
`scripts/rig_controller.gd` drives an `EarthRig` instead.

**All UI is world-space 3D.** The addon composites the two eye viewports into
`CanvasLayer` 100 as side-by-side `TextureRect`s. A second 2D UI layer lands on
one eye's half of the output window. Every panel is a `SubViewport` on a quad —
see `scripts/ui/world_panel.gd`.

**`display/window/stretch/mode` must stay `disabled`.** Any stretch mode
rescales the compositing CanvasLayer against the project's base resolution.
Verified: with `canvas_items`, a 1920x324 stereo window rendered both eyes into
960x162 — still recognisably stereo, just small and in a corner.

**Satellites stay in TEME; the Earth rotates by GMST(t).** TEME is SGP4's native
frame. Rotating the globe instead of converting every satellite to ECEF is
cheaper and sidesteps nutation and polar motion (sub-km, invisible here).

**ECI → Godot is `(x, z, -y)`.** The obvious `(x, z, y)` is a reflection: every
orbit silently runs retrograde and looks entirely plausible. Asserted in both
`tools/build_ephemeris.py` and `tests/verify_frames.gd`.

**Earth UV is derived, not taken from `SphereMesh`.** `earth.gdshader:geo_uv()`
computes equirectangular UV from the mesh-local normal. Trusting the engine's UV
convention puts every continent at a constant unknown longitude offset — the
terminator is the right *shape*, just over the wrong ocean.

**Scale is per-chapter.** At the LEO-tuned scale (0.75, centre 3.0 m) the GEO
belt's near side sits 1.96 m *behind the viewer's head* and is culled. The
pull-back from LEO to GEO is chapter 1 → 2 and is the best beat in the deck.

**Stereo comfort is enforced, not documented.** `RigController` clamps all
content to ≥ 1.5 m from the viewer. Parallax is `p = IOD·(1 − D/z)`: −33 mm at
1.5 m (borderline), −81 mm at 1.0 m (unfusable for many viewers). Dolly and
altitude exaggeration compound and are clamped jointly.

**Zoom pushes content away rather than being capped.** The first design fixed
the rig distance and clamped scale for comfort, which capped zoom at roughly the
default framing — at the LEO chapter the maximum safe scale was 0.838 against a
default of 0.75, so zoom did essentially nothing. Now
`RigController.safe_center_distance()` derives distance from scale, so zooming in
moves the content back by exactly enough to hold the near clearance. Ordinary
dolly-zoom: the globe still grows (apparent half-angle rises toward
`atan(1/r)`), the clearance never shrinks, and there is no cap.

**The comfort target is set by window violations, not by fusion.** Once the
globe is large enough to be worth looking at, the shell around it necessarily
overruns a 2.04 m tall wall and gets cut by the frame edge. Cropping content
*behind* the screen is just looking through a window; cropping content that
floats *in front* of it is the contradiction that hurts. So the nearest object
sits at ~2.05 m — about −7 mm of parallax, barely in front of the wall plane —
which makes the overrun harmless. The 1.5 m fusion floor remains as a hard stop.

**Points have a minimum projected size** (`min_pixel_size`, 1.7 px). Below about
a pixel, a point lands on a sample or misses it depending on sub-pixel position,
so the field blinks as it moves — and because the two eyes sample from slightly
different positions, they blink *independently*, which is retinal rivalry rather
than depth. The enlargement is energy-normalised (alpha scales by 1/k²), because
holding 20k LEO points at the floor while zoomed out otherwise deposits far more
light than the geometry would and washes the globe out to white.

**The mouse cursor is released explicitly.** The addon captures it in
`_initialize()` to drive mouse-look; since `look_sensitivity` is zeroed, the
capture only hid the cursor and left no way to see where a click would land.
`main.gd:_release_mouse()` undoes it — child `_ready()` runs before parent
`_ready()`, so this reliably wins.

**Rotating the content must carry the lighting with it.** The wall is fixed, so
"orbiting the camera" is simulated by turning the content — which is only
equivalent to a real orbit if *everything* in the inertial frame turns together.
`sun_direction()` is an inertial vector and the Earth shader dots it against a
world-space normal that already carries the rig rotation, so passing the raw
vector left the sun behind: dragging slid the terminator across the continents
and the globe appeared to change time of day. `main.gd` now rotates the sun into
world space with the rig, and samples the starfield through the inverse rotation
so the stars sweep past as they would if the viewer were really moving.
`tests/verify_lighting.gd` asserts this (drift 0.000002° versus 89.6° for the
old behaviour).

## Does a field of points actually read in stereo?

Yes, and the numbers are in `tests/verify_frames.gd` output. At the LEO chapter:

| Feature | Distance | Parallax | On wall |
|---|---|---|---|
| Nearest shell point | 2.05 m | −7.1 mm | −5.7 px |
| Globe near limb | 2.96 m | +14.4 mm | +11.5 px |
| Globe centre | 4.41 m | +30.4 mm | +24.1 px |
| Farthest shell point | 6.77 m | +41.8 mm | +33.2 px |

**49 mm of disparity range, 39 px per eye.** The stereo detection threshold is
about 10 arcsec, which at 2.282 m is roughly 0.01 mm of parallax — so the scene
spans thousands of times the threshold. The globe alone is 19 px limb-to-limb.
Depth is not the scarce resource here.

The real risk with a dense point field is the opposite problem: **false
matching**. The shell projects to 2.89 m wide carrying ~20k points, giving a
mean on-screen spacing of ~14 px against a 39 px disparity range — so a point's
true partner in the other eye is frequently *farther away than its nearest
neighbour*. With interchangeable dots that is the classic wallpaper condition:
the visual system pairs a point in one eye with the wrong point in the other and
either fuses phantom depth or fails to settle.

The mitigation is `SatelliteField._jitter()`: stable per-object size and
brightness variation, seeded from NORAD ID so it is identical in both eyes,
across frames, and across rebuilds. Correlating size with brightness reads as a
natural magnitude spread and makes each point more distinctive than varying
either alone. Regime colour already separates the four buckets, but within LEO
all 20k objects would otherwise be identical.

This is a perceptual property, so it cannot be settled off the wall — it is the
main thing to look for in the comfort pass.

**One comfort parameter is not covered by the tests.**
`satellites.gdshader`'s `zoom_compensation` (0.55) makes point size vary with
zoom, so apparent size no longer tracks distance exactly. Size is a monocular
depth cue, and when it disagrees with disparity, fusion gets harder. It was
tuned against single-eye captures, and `verify_stereo.gd` measures a centroid,
not point size. Confirm it during the wall's 15-minute comfort pass alongside
`eye_separation`.

**Altitude exaggeration is labelled on screen** whenever it is not 1.0. At true
scale the LEO shell sits ~1 % off the globe and the structure is invisible;
overstating fidelity to this audience costs more than the demo can buy back.
Same reason the provenance plate names the source, the epoch spread, and that
SGP4 error grows to kilometres per day.

## Data

`tools/fetch_gp.py` caches CelesTrak GP data. CelesTrak enforces **one download
per 2-hour update cycle** (HTTP 403 otherwise, repeat abuse → IP firewalled), so
the script refuses locally rather than letting the server refuse us. CelesTrak
was unreachable from the dev laptop entirely — DNS resolves, TCP times out — so
`--source tleapi` pages a mirror serving the same elements.

`tools/build_ephemeris.py` propagates with SGP4 into `data/ephemeris.bin`:
a 32-byte header then sample-major float32 TEME positions in Earth radii,
already mapped to Godot axes. Defaults to a 3-hour span at 30 s steps, which
loops cleanly and covers one to two LEO revolutions. float32 rather than int16
because GDScript has no bulk int16 decode, only per-element `decode_s16()`,
while `PackedByteArray.to_float32_array()` is one engine call.

The builder drops three classes of object and reports each separately:
SGP4 errors (decayed or bad elements), anything beyond 8 R⊕ (off-scene), and
element sets whose propagation contradicts their own mean elements. That last
filter matters more than it sounds: a single junk object labelled LEO but
propagating out to 8 R⊕ would drive the stereo comfort clamp and shrink the
entire LEO chapter to accommodate content that should not be there.

It also records, per object, the maximum radius actually ATTAINED in the window
(`max_radius_re`) — not orbit apogee. The comfort clamp is driven by what is on
screen; an HEO object near perigee for the whole span never reaches its apogee.

**Deduplication is not optional.** The mirror pages a live dataset and a full
pass takes tens of minutes, so records shift between pages: a raw pull returned
25,706 records containing **7,579 duplicates — 30% of the catalog**. Duplicates
are not harmless extra rows; they double an object's contribution to the very
density this demo is about, and conjunction screening reports objects colliding
with themselves at 0.000 km. Deduped at all three layers (fetch, build, screen),
and fetch reports coverage against the mirror's own total, because the same
reshuffling means some objects are missed.

International designators are expanded from TLE line 1 when the feed omits
`OBJECT_ID` (the mirror does). Without that the field is present but blank, and
every debris-family query silently returns nothing.

Current build: 16,282 objects (14,745 LEO / 845 GEO / 435 HEO / 257 MEO), 70 MB.

## Conjunction screening

`tools/find_conjunctions.py` is a two-stage screen. A KD-tree per 30 s sample
flags candidate pairs, then each candidate is re-propagated at 1 s to find the
actual time of closest approach. The refinement is not optional: at 30 s spacing
and closing speeds up to 15 km/s, objects move hundreds of km between samples,
so reporting stage-1 separations as miss distances would be badly wrong.

Two filters that the data forced:

- **Self-pairs** from duplicate records (fixed upstream, guard retained).
- **Co-orbital pairs.** Docked spacecraft pass every distance test at 0.000 km —
  ISS modules with their visiting Dragon/Progress/Cygnus, the Chinese station
  with Tianzhou. They are physically attached but tracked separately, so they
  share one TLE. Relative velocity separates them: a conjunction that matters is
  fast. 51 pairs excluded below 0.1 km/s.

Current screen finds sub-kilometre approaches at up to 9.1 km/s.

**This is not an operational conjunction product.** It screens public GP data
with no covariance; real assessment uses special-perturbations ephemeris and
owner-operator data. SGP4 error here is comparable to the miss distances
themselves, and the UI says so.

**Export packaging:** `*.bin` and `*.json` are non-resource files and will
silently vanish from a Windows export unless added to the export preset's
non-resource file filter.

## Performance

M1 Max, full catalog, `-- --benchmark 6 --chapter 1`:

| Window | Frame time | FPS | `update_positions` |
|---|---|---|---|
| 1920×648, 14,745 objects | 6.49 ms | 154.2 | dominant cost |
| 1920×648, 20,757 objects | 8.09 ms | 123.7 | 7.61 ms (94 %) |

Frame time is **flat across a 5× pixel range** — this is CPU-bound, not
fill-bound. `SatelliteField.update_positions()` is now 94 % of the frame:
20,757 instances interpolated and written to the MultiMesh buffer in GDScript.

**This is the Phase B case, measured.** Moving interpolation to a vertex shader
sampling a `Texture2DArray` (layer = time sample, texel = object) removes that
7.6 ms and leaves the data path unchanged. Not needed at 123 FPS, but it is the
first thing to do if the wall's hardware is slower than this laptop.

An earlier build ran at 69 FPS. The difference was `RigController` recomputing
the outermost-object radius every frame — 20k dictionary lookups per frame for a
value that only changes on a filter or exaggeration change. Caching it in
`SatelliteField.max_content_radius()` cost ~6.4 ms/frame. Worth knowing before
reaching for the GPU path: measure which half of the frame is actually yours.

Caveat: macOS clamped the test window to 5120×1288, so the wall's true
9600×1620 (15.5 Mpix) was not reproducible here. Given zero fill sensitivity
from 1.2 to 6.2 Mpix, the CPU bound should dominate there too — but confirm it
on the wall.

## Verification

See `tests/README.md`. Both suites run headless and have been checked against a
known-bad case, not just a passing one.
