extends SceneTree
## User input must take the camera away from a chapter transition.
##
##   Godot --path . --headless --script res://tests/verify_camera_control.gd
##
## A transition tweens azimuth, elevation and distance directly. If the viewer
## grabs the controls while one is running, the two write the same properties
## every frame and the scene appears to resist being moved -- the worst kind of
## bug, because it reads as the machine being broken rather than as a setting.
##
## Checks both directions: an uninterrupted transition still arrives, and an
## interrupted one stops dead and leaves the viewer in charge.

var failures := 0

func _init() -> void:
	var root = load("res://main.tscn").instantiate()
	get_root().add_child(root)
	await process_frame
	await process_frame

	var cam: CameraDirector = root.get_node("CameraDirector")
	var deck: ChapterDeck = root.get_node("ChapterDeck")

	# --- Control: left alone, a transition completes -------------------------
	print("\nUninterrupted transition still arrives:")
	deck.apply(0, false)
	await process_frame
	var start_distance := cam.distance
	deck.apply(4, true)               # a big framing change, animated
	# Waited on wall time, not a frame count: headless frames do not advance at
	# 60 Hz, so "400 frames" is not a predictable amount of tween time.
	var deadline := Time.get_ticks_msec() + 20000
	var settled := false
	while Time.get_ticks_msec() < deadline:
		await process_frame
		if not cam.is_transitioning():
			settled = true
			break
	_ok("transition completes", settled,
		"arrived, distance %.3f -> %.3f" % [start_distance, cam.distance])
	_ok("and actually moved", absf(cam.distance - start_distance) > 0.1,
		"a transition that never moves would pass the check above trivially")

	# --- The fix: input interrupts -------------------------------------------
	print("\nUser input takes control mid-transition:")
	deck.apply(0, false)
	await process_frame
	deck.apply(4, true)
	await process_frame
	await process_frame
	_ok("transition is running", cam.is_transitioning(), "tween active")

	# The viewer grabs it, exactly as the input handlers do.
	cam.apply_user_zoom(0.80)
	cam.apply_user_orbit(0.35, 0.10)
	var held_distance := cam.distance
	var held_azimuth := cam.azimuth
	_ok("transition cancelled", not cam.is_transitioning(), "tween killed")

	# Nothing may drag the camera back afterwards.
	var max_drift := 0.0
	for i in 120:
		await process_frame
		max_drift = maxf(max_drift, absf(cam.distance - held_distance))
	_ok("camera stays where the viewer put it", max_drift < 1e-5,
		"worst drift %.9f m over 120 frames" % max_drift)
	_ok("azimuth held", absf(cam.azimuth - held_azimuth) < 1e-5,
		"%.6f rad" % cam.azimuth)

	# --- A new chapter must still be able to take it back --------------------
	print("\nA later chapter change still moves the camera:")
	deck.apply(2, true)
	await process_frame
	_ok("new transition starts", cam.is_transitioning(),
		"chapter changes are not blocked by having taken control")

	print("\n%s" % ("ALL CHECKS PASSED" if failures == 0
		else "%d CHECK(S) FAILED" % failures))
	quit(1 if failures > 0 else 0)

func _ok(label: String, pass_: bool, detail: String) -> void:
	print("  [%s] %s -- %s" % ["PASS" if pass_ else "FAIL", label, detail])
	if not pass_:
		failures += 1
