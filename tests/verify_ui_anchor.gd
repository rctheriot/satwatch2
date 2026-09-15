extends SceneTree
## Wall-fixed UI must not drift while the camera moves.
##
##   Godot --path . --headless --script res://tests/verify_ui_anchor.gd
##
## The panels are meant to sit on the physical wall, so their pose relative to
## the head must be EXACTLY constant. Copying the head transform every frame
## looked correct but was one frame stale: Godot calls _process parent-first, so
## main.gd read the pose before CameraDirector had updated it. Static that is
## invisible; while orbiting or dollying the panels swim against the wall.
##
## This drives the camera hard and checks the panels never move relative to the
## head, which only holds if they are PARENTED to it rather than tracking it.

var failures := 0

func _init() -> void:
	var scene: PackedScene = load("res://main.tscn")
	var root := scene.instantiate()
	get_root().add_child(root)
	await process_frame
	await process_frame

	var camera: CameraDirector = root.get_node("CameraDirector")
	var head := camera.head_node()
	if head == null:
		push_error("no camera pivot -- did StereoWallDisplay initialise?")
		quit(1)
		return

	var hud: Node3D = root.get_node_or_null("UIRig")
	if hud == null:
		hud = head.get_node_or_null("UIRig")
	var inset: Node3D = head.get_node_or_null("ConjunctionInset")

	print("\nWall-fixed UI is parented to the head, not tracking it:")
	_ok("UIRig parent", hud != null and hud.get_parent() == head,
		"parent is %s" % ("<missing>" if hud == null else hud.get_parent().name))
	_ok("ConjunctionInset parent", inset != null and inset.get_parent() == head,
		"parent is %s" % ("<missing>" if inset == null
			else inset.get_parent().name))

	# Negative control: --copy reproduces the old behaviour (detach the panels
	# and copy the head transform each frame) so the check can be shown to fail
	# on the bug it exists for, rather than only ever passing.
	var copy_mode := OS.get_cmdline_user_args().has("--copy")
	if copy_mode:
		head.remove_child(hud)
		root.add_child(hud)
		print("\n[control] copying the head transform each frame instead")

	# Now move the camera the way a presenter would and watch for drift.
	print("\nPose relative to the head while orbiting and dollying:")
	var reference := head.global_transform.affine_inverse() * hud.global_transform
	var worst_pos := 0.0
	var worst_rot := 0.0
	for i in 40:
		camera.azimuth += 0.09
		camera.elevation = 0.6 * sin(float(i) * 0.31)
		camera.distance = 3.2 + 2.4 * absf(sin(float(i) * 0.17))
		camera._apply()
		if copy_mode:
			# Deliberately stale by one frame, exactly as the bug was: the pose
			# is read before the camera update that follows.
			hud.global_transform = head.global_transform
			await process_frame
		else:
			await process_frame
		var rel := head.global_transform.affine_inverse() * hud.global_transform
		worst_pos = maxf(worst_pos, (rel.origin - reference.origin).length())
		worst_rot = maxf(worst_rot,
			rad_to_deg((rel.basis.z).angle_to(reference.basis.z)))

	# Parenting makes this exact, not merely small.
	_ok("panel position drift", worst_pos < 1e-5, "worst %.9f m over 40 moves" % worst_pos)
	_ok("panel orientation drift", worst_rot < 1e-4, "worst %.9f deg" % worst_rot)

	print("\n%s" % ("UI ANCHOR CHECK PASSED" if failures == 0
		else "%d CHECK(S) FAILED" % failures))
	quit(1 if failures > 0 else 0)

func _ok(label: String, pass_: bool, detail: String) -> void:
	print("  [%s] %s -- %s" % ["PASS" if pass_ else "FAIL", label, detail])
	if not pass_:
		failures += 1
