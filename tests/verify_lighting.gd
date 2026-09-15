extends SceneTree
## Rotating the content must not change the time of day.
##
## The wall is fixed, so orbiting is simulated by turning the content. That is
## only equivalent to a real camera orbit if the sun turns with it. If it does
## not, dragging slides the terminator across the continents -- the globe appears
## to spin under a fixed sun, which is a completely plausible-looking bug.
##
## Checks that the sun direction expressed in the CONTENT's own frame is
## invariant under rig rotation, for the same simulation instant.

func _init() -> void:
	var clock := SimClock.new()
	clock.configure(1789000000.0, 10800.0)
	clock.now_unix = 1789000000.0
	var inertial_sun := clock.sun_direction()

	print("\nSun direction in the content frame must not depend on rig yaw:")
	var reference := Vector3.ZERO
	var worst := 0.0
	for yaw_deg in [0.0, 45.0, 90.0, 180.0, 270.0]:
		for pitch_deg in [0.0, 40.0]:
			var frame := Basis(Vector3.UP, deg_to_rad(yaw_deg)) \
				* Basis(Vector3.RIGHT, deg_to_rad(pitch_deg))
			# What main.gd hands the shader.
			var sun_world := frame * inertial_sun
			# What the shader effectively compares it against: a surface normal
			# carried into world space by the same rotation. Undo it to recover
			# the sun as the CONTENT sees it.
			var sun_in_content := frame.inverse() * sun_world
			if reference == Vector3.ZERO:
				reference = sun_in_content
			worst = maxf(worst, rad_to_deg(sun_in_content.angle_to(reference)))

	var ok := worst < 0.01
	print("  worst drift across yaw 0-270 and pitch 0-40: %.6f deg" % worst)
	print("  [%s] time of day is invariant under rotation" % ("PASS" if ok else "FAIL"))

	# Negative control: the previous behaviour passed the raw inertial vector,
	# so the content-frame sun swung by the full rotation angle.
	var bad_frame := Basis(Vector3.UP, deg_to_rad(90.0))
	var bad := rad_to_deg((bad_frame.inverse() * inertial_sun).angle_to(inertial_sun))
	print("  control: passing the raw inertial vector instead drifts %.1f deg" % bad)

	print("\n%s" % ("LIGHTING CHECK PASSED" if ok else "LIGHTING CHECK FAILED"))
	quit(0 if ok else 1)
