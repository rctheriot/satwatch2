# Verification

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
object at least 1.5 m from the viewer. `RigController` clamps this at runtime,
so a bad chapter is silently corrected rather than crashing -- meaning the
authored framing quietly would not be what reaches the wall. When this check was
first added, 4 of 7 chapters failed, one at -6.96 m.

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

## Only on the wall (Windows)

- Full-resolution frame rate at 9600x1620 with the whole catalog.
- 15-minute comfort pass at the real `eye_separation`.
- `wall_center_height` (1.75, editor gizmos only) against `_camera_pivot.y`
  (1.64, what the runtime projection actually uses) — an 11 cm discrepancy in
  the addon that needs LAVA's calibration to resolve.
- Gamepad reachability from the presenter's standing position.
