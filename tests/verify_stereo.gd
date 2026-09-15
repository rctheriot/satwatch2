extends SceneTree
## Measures horizontal parallax in a stereo capture.
##
##   Godot --path . res://tests/stereo_check.tscn -- --capture shot.png
##   Godot --path . --headless --script res://tests/verify_stereo.gd -- shot.png
##
## Checks the thing that is nearly impossible to eyeball and catastrophic to get
## wrong: whether the right eye's image is displaced in the correct DIRECTION.
## Reversed eyes still look like stereo -- the depth is simply inverted, and
## viewers report eye strain rather than "the image is backwards".
##
## Convention: parallax = x_right - x_left. Positive means the content sits
## BEHIND the wall plane, which is where this scene's globe centre and all four
## UI panels live.

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.is_empty():
		push_error("usage: -- <capture.png>")
		quit(1)
		return

	var img := Image.new()
	if img.load(args[0]) != OK:
		push_error("cannot load %s" % args[0])
		quit(1)
		return

	var w := img.get_width()
	var h := img.get_height()
	if w % 2 != 0:
		push_error("capture width %d is not an even split" % w)
		quit(1)
		return
	var half := w / 2

	# Restrict to the middle band, where the globe and satellite field are, and
	# away from the side gutters that hold the static UI panels.
	var x0 := int(half * 0.30)
	var x1 := int(half * 0.70)
	var left := _centroid_x(img, 0, x0, x1, h)
	var right := _centroid_x(img, half, x0, x1, h)

	if left < 0.0 or right < 0.0:
		push_error("no bright content found in either eye -- is the scene rendering?")
		quit(1)
		return

	var parallax := right - left
	print("  left-eye centroid  x = %.3f px (within its half)" % left)
	print("  right-eye centroid x = %.3f px (within its half)" % right)
	print("  parallax (right - left) = %+.3f px" % parallax)

	var ok := parallax > 0.05
	print("  [%s] right eye displaced correctly for content behind the wall plane"
		% ("PASS" if ok else "FAIL"))
	if not ok:
		print("       Negative or zero parallax here means the eyes are swapped")
		print("       (check swap_eyes) or eye_separation is 0.")
	print("\n%s" % ("STEREO CHECK PASSED" if ok else "STEREO CHECK FAILED"))
	quit(0 if ok else 1)

## Luminance-weighted horizontal centroid of a band, relative to x_off.
func _centroid_x(img: Image, x_off: int, x0: int, x1: int, h: int) -> float:
	var sum_w := 0.0
	var sum_x := 0.0
	for y in range(0, h, 2):
		for x in range(x0, x1):
			var c := img.get_pixel(x_off + x, y)
			# Bias toward the bright satellite points and lit limb; the near-black
			# background contributes almost nothing.
			var lum: float = c.r * 0.3 + c.g * 0.6 + c.b * 0.1
			if lum < 0.04:
				continue
			sum_w += lum
			sum_x += lum * float(x)
	return -1.0 if sum_w <= 0.0 else sum_x / sum_w
