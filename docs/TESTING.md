# Testing

Six headless suites. None needs a GPU or a network, and all of them run in
seconds:

```bash
for t in frames lighting ui_anchor sensors optional_data camera_control; do
  /Applications/Godot.app/Contents/MacOS/Godot --path . --headless \
    --script res://tests/verify_$t.gd
done
```

Several carry a **negative control** — a switch that reproduces the bug the
check exists for. A test that has only ever passed is not evidence of anything;
these have been shown to fail on the specific defect they guard.


## Frame consistency (headless, no GPU needed)

    Godot --path . --headless --script res://tests/verify_frames.gd

Guards the failure modes that look completely plausible on screen:
a reflected axis mapping (every orbit silently retrograde) and a constant
longitude offset between the Earth texture and the satellites above it.
It cross-checks the engine against `tools/build_ephemeris.py`, which computes
GMST independently, so agreement means both share one frame convention. The
reference sub-satellite point is stored in `catalog.json` by the builder rather
than hardcoded here, so it stays valid across rebuilds.

It also asserts every chapter in the default deck keeps its outermost visible
object at least 1.5 m from the viewer, and enough disparity range to read as
depth. Camera distance is derived per chapter from the outermost visible
object, so this checks the authored preset rather than agreeing with itself.
When the check was first added, 4 of 7 chapters failed, one placing content
6.96 m behind the viewer's head.

## Lighting frame

    Godot --path . --headless --script res://tests/verify_lighting.gd

Asserts the sun direction expressed in the content's own frame does not change
when the rig rotates. If it does, dragging appears to change the time of day --
a very plausible-looking bug, since the terminator still has the right shape.
Includes the pre-fix behaviour as a printed control (89.6 deg of drift).

## Wall-fixed UI

    Godot --path . --headless --script res://tests/verify_ui_anchor.gd

Panels must not move relative to the head while the camera does. Add `--copy`
for the negative control, which reproduces the old copy-the-transform-each-frame
behaviour and drifts 4.41 m.

## Ground-site geometry

    Godot --path . --headless --script res://tests/verify_sensors.gd

Checks the Earth-fixed axis convention (a hemisphere flip puts every site in the
wrong place on a globe that still looks fine), the squared-form elevation test
against direct computation over 120,000 trials, and the shadow test.

## Camera control

    Godot --path . --headless --script res://tests/verify_camera_control.gd

A chapter transition must yield to the viewer. Checks that an uninterrupted
transition still arrives, and that an interrupted one stops dead rather than
dragging the camera back.

## Optional data

    Godot --path . --headless --script res://tests/verify_optional_data.gd

Aurora and conjunction data come from live endpoints that can be unreachable.
A chapter that cannot draw its subject is worse than one that is absent -- on
a wall, an empty globe reads as the demo being broken. Verified empirically
too: removing the data files takes the deck from 11 chapters to 9 with clean
messages and no errors.

## Stereo output

    Godot --path . -- --stereo 960 324 --capture shot.png --chapter 0
    Godot --path . --headless --script res://tests/verify_stereo.gd -- shot.png

`--stereo W H` flips the wall addon into stereo output at runtime (its
`edit_mode` setter rebuilds), giving a 2W x H window. There is deliberately no
separate stereo scene: a duplicate .tscn has to mirror the whole node tree and
rots the moment `main.tscn` changes, which is what happened to the earlier one.

**The test resolution must stay aspect-matched to the wall.**
`_apply_offaxis_projection()` sets only the frustum *height*; width comes from
the viewport aspect. 4800/1620 = 2.963 against 6.047/2.042 = 2.961, and
960/324 preserves that. A non-matching test resolution silently produces wrong
horizontal stereo and everything still looks fine.

`verify_stereo.gd` measures parallax as `x_right - x_left` and requires it
positive, which is correct for content behind the wall plane. Always pass
`--chapter` explicitly: parallax magnitude depends on the framing, so omitting
it makes the number non-reproducible.

Checked against a known-bad case, not just a passing one -- add `--swap-eyes`
and the same capture gives negative parallax and the check fails. Reversed eyes still look
like stereo -- depth is simply inverted, and viewers report eye strain rather
than "the image is backwards" -- so a test that only ever passes is worthless
here.

Also confirm by eye: two distinct eye images side by side, and nothing in front
of the wall plane touching a frame edge.

`verify_frames.gd` prints the parallax range per chapter (~49 mm / 39 px at the
LEO framing). What it cannot check is FALSE MATCHING in the dense field -- see
the README section on that. It is perceptual, so the wall is the only place to
settle it.

## Only on the wall (Windows)

- Full-resolution frame rate at 9600x1620 with the whole catalog.
- 15-minute comfort pass at the real `eye_separation`.
- `wall_center_height` (1.75, editor gizmos only) against `_camera_pivot.y`
  (1.64, what the runtime projection actually uses) — an 11 cm discrepancy in
  the addon that needs LAVA's calibration to resolve.
- Gamepad reachability from the presenter's standing position.

## Lighting frame

    Godot --path . --headless --script res://tests/verify_lighting.gd

Asserts the sun direction expressed in the content's own frame does not change
when the rig rotates. If it does, dragging appears to change the time of day — a
very plausible-looking bug, since the terminator still has the right shape.
Prints the pre-fix behaviour as a control (89.6° of drift).

## Camera control

    Godot --path . --headless --script res://tests/verify_camera_control.gd

A chapter transition must yield to the viewer. Checks both directions: an
uninterrupted transition still arrives *and demonstrably moves*, and an
interrupted one stops dead rather than dragging the camera back. Without the
first half, a build where transitions never ran would pass.

## Ground-site geometry

    Godot --path . --headless --script res://tests/verify_sensors.gd

The Earth-fixed axis convention (a hemisphere flip puts every site in the wrong
place on a globe that still looks fine), the square-root-free elevation test
against direct computation over 120,000 trials, and the shadow test.

## Optional data

    Godot --path . --headless --script res://tests/verify_optional_data.gd

Aurora, TEC and wind data come from live endpoints that can be unreachable.
A chapter that cannot draw its subject is worse than one that is absent.
Covers missing, empty and malformed payloads. Verified empirically too:
removing the data files takes the deck from 11 chapters to 9 with clean
messages and no errors.

## What cannot be checked here

Frame rate at 9600×1620, stereo comfort over a long pass at the real eye
separation, and whether the dense point field suffers false matching in
practice. That last one is perceptual and only the wall can settle it.
