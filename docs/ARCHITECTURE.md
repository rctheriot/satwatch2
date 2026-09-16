# Architecture

How SatWatch 2 is put together, and — more usefully — the constraints that are
not obvious until they have already produced a bug. Most of what follows exists
because something looked completely plausible on screen while being wrong.

## The wall

The LAVA wall is 6.047 m × 2.042 m, driven as two 4800×1620 images (9600×1620
total) with the viewer 2.282 m away. That is a **3:1 aspect ratio**, about
15.5 megapixels per frame, and a single correct viewing position.

`addons/stereo_wall_display` builds an off-axis frustum per eye. Three
consequences shape everything else.

**The camera can move.** The addon derives the virtual screen corners *and* both
eye positions from one head pose, so they translate and rotate rigidly together.
That models a viewer with a wall fixed in front of them navigating the world —
the standard non-head-tracked powerwall arrangement. It would only be wrong
under head *tracking*, where the head moves relative to a physically fixed wall.
`CameraDirector` orbits a world-space target by driving the addon's player body,
with a free-fly mode on `F`.

**All UI is world-space 3D.** The addon composites the two eye viewports into
`CanvasLayer` 100 as side-by-side `TextureRect`s. A second 2D layer lands on one
eye's half of the output window — monocular garbage. Every panel is a
`SubViewport` on a quad; see `scripts/ui/world_panel.gd`.

**`display/window/stretch/mode` must stay `disabled`.** Any stretch mode
rescales that compositing layer against the project's base resolution. Verified:
with `canvas_items`, a 1920×324 stereo window rendered both eyes into 960×162 —
still recognisably stereo, just small and in a corner.

### Wall-fixed UI

Panels are **parented** to the camera pivot, not tracking it. Copying the head
transform each frame looked right but was one frame stale — Godot calls
`_process` parent-first, so `main.gd` read the pose before `CameraDirector`
updated it. Static that is invisible; while orbiting the panels swim.
`tests/verify_ui_anchor.gd` requires exactly zero drift and its `--copy` control
reproduces the old behaviour at 4.41 m of drift.

Panels also **do not depth-test**. They are real geometry 2.45 m out, so zooming
the content in pushed the globe through them and the UI vanished into the Earth.
A panel fixed to the physical wall is a window frame, not an object in the scene.

## Coordinate frames

**Satellites stay in TEME; the Earth rotates by GMST(t).** TEME is SGP4's native
frame. Rotating the globe instead of converting every object to ECEF is cheaper
and sidesteps nutation and polar motion — sub-kilometre, invisible here.

**ECI → Godot is `(x, z, −y)`.** The obvious `(x, z, y)` is a *reflection*:
every orbit silently runs retrograde and looks entirely plausible. Asserted in
both `tools/build_ephemeris.py` and `tests/verify_frames.gd`.

**Earth UV is derived, not taken from `SphereMesh`.** `earth.gdshader:geo_uv()`
computes equirectangular UV from the mesh-local normal. Trusting the engine's UV
convention puts every continent at a constant unknown longitude offset — the
terminator is the right *shape*, just over the wrong ocean. The same convention
is used by `GroundSites.site_up()`, `AircraftLayer` and `WindLayer`, so ground
positions agree with the imagery by construction.

**Rotating content must carry the lighting with it.** `sun_direction()` is an
inertial vector and the Earth shader dots it against a world-space normal. Early
on, the content rotated and the sun did not, so dragging slid the terminator
across the continents and appeared to change the time of day. The camera moves
instead of the world now, so the rig basis is identity — but the correction is
still applied rather than assumed, and `tests/verify_lighting.gd` guards it.

## Scale and stereo comfort

Earth radius = 1 world unit. **Scale and camera distance are per-chapter**, not
constants: at a LEO-tuned scale the geostationary belt's near side sits metres
*behind* the viewer's head and is culled.

Screen parallax is `p = IOD·(1 − D/z)` with D = 2.282 m, IOD = 63 mm:

| Object distance | Parallax |
|---|---|
| 2.25 m | −0.9 mm |
| 1.50 m | −33 mm (borderline fusion) |
| 1.00 m | −81 mm (unfusable for many) |

Chapter presets put the nearest object at about 2.05 m — roughly −7 mm, barely
in front of the wall plane. That figure is set by **window violations**, not by
fusion: once the globe is large enough to be worth looking at, the shell around
it necessarily overruns a 2.04 m tall wall and is cut by the frame edge.
Cropping content behind the screen is just looking through a window; cropping
content floating in front of it is the contradiction that hurts.

`tests/verify_frames.gd` asserts every chapter's framing and reports its
disparity range (about 49 mm, 39 px per eye, against a ~0.01 mm detection
threshold — depth is not the scarce resource).

## Rendering

**Points are sized in screen space.** They used to carry a world size scaled by
`pow(content_scale, −k)`, tuned when the camera was parked. Once the camera moved
too, the two compounded: LEO chapters projected to 0.70 px against 1.20 px
elsewhere and drew at 0.17 alpha against 0.50 — three times dimmer for no reason
a viewer could see. Targeting a pixel size directly makes visibility uniform by
construction. `depth_cue` keeps a partial perspective shrink so nearer objects
still read as nearer.

**Minimum projected size, energy-normalised.** Below about a pixel a point lands
on a sample or misses it depending on sub-pixel position, so the field blinks —
and the two eyes blink *independently*, which is retinal rivalry, not depth.
Enlarged points fade so a dense field held at the floor does not deposit more
light than the geometry would.

**Per-object jitter breaks false matching.** At the LEO framing the field's mean
on-screen point spacing is about 14 px while the scene's disparity range is
about 39 px — a point's true partner in the other eye is frequently farther than
its nearest neighbour. With interchangeable dots that is the classic wallpaper
condition: the visual system pairs the wrong points and fuses phantom depth.
`SatelliteField._jitter()` gives every object a stable size and brightness,
seeded from NORAD ID so it is identical in both eyes, across frames and across
rebuilds. Per-frame or per-eye jitter would be far worse than none.

**Ribbons, not lines.** One-pixel lines shimmer and disagree between the eyes.
Trails are camera-facing ribbons at constant pixel width.

**Colour ramps are pinned to fixed physical scales**, never auto-scaled to each
fetch's own peak — auto-scaling redefines what a colour means between fetches,
so a calm day and a storm look identical. TEC is fixed at 120 TECU; wind at
65 m/s with stops at speeds a forecaster recognises. The TEC ramp is monotonic
in lightness so its ordering survives greyscale and colour-blind viewing; the
wind ramp is the conventional blue-to-red, which is hue-dominated, so trail
*length* encodes speed redundantly.

## Chapters

`Chapter` is a plain resource: a camera pose, a content state, some explanatory
text, and flags for optional layers. `ChapterDeck` sequences them.

- Chapters **do not set the clock rate**. Each imposing its own speed made time
  jump between demos, which reads as the visualisation being inconsistent. Rate
  is a global control.
- Camera distance is **derived** from the outermost *visible* object. The
  satellite field stays populated when hidden, so a chapter that hides it must
  not read its extent — doing so framed the air-domain chapter 15 m back.
- Optional layers **gate their own chapters**. A chapter that cannot draw its
  subject is worse than one that is absent: on a wall, an empty globe reads as
  the demo being broken. `tests/verify_optional_data.gd` covers missing, empty
  and malformed payloads.
- **User input cancels a transition.** All camera input routes through
  `apply_user_orbit()` / `apply_user_zoom()`, which kill the tween first, so
  cancellation cannot be forgotten at one call site.

## Performance

Measured on an M1 Max at 1920×648, with the machine cool:

| | Frame | FPS |
|---|---|---|
| Baseline (LEO, 14,745 objects) | 8.3 ms | 120 |
| Jet stream (4,500 particles) | 15.6 ms | 64 |
| Surveillance network | 17.6 ms | 57 |

The heavy chapters are **CPU bound in GDScript**, not fill bound — frame time is
flat across a 5× pixel range. `SatelliteField.update_positions()` dominates the
baseline; visibility testing and particle advection dominate the others. Moving
those to compute shaders is the real fix and would make the tuning constants
irrelevant.

**Measure with the machine cool.** `update_positions` does identical work in
every chapter, so the benchmark prints it as a thermal probe. A back-to-back
sweep on a warm laptop produced 15 to 56 fps for the *same* configuration, and a
conclusion drawn from it ("particle count is a cliff") was entirely an artefact.
Two stable runs per configuration, with a pause between, or the numbers are
fiction.

## Things that can only be checked on the wall

- Full-resolution frame rate at 9600×1620.
- Stereo comfort over a 15-minute pass at the real `eye_separation`.
- Whether the dense point field suffers false matching in practice — this is a
  perceptual property and cannot be settled off the wall.
- `wall_center_height` (1.75, editor gizmos) against `_camera_pivot.y` (1.64,
  what the runtime projection uses). An 11 cm discrepancy in the addon that
  needs LAVA's calibration to resolve.
