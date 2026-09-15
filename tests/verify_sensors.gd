extends SceneTree
## Ground-site visibility geometry.
##
##   Godot --path . --headless --script res://tests/verify_sensors.gd
##
## The cheap squared-form elevation test and the Earth-fixed axis convention are
## both easy to get subtly wrong in ways that still look like a plausible globe
## with plausible cones -- sites in the wrong hemisphere, or coverage that is
## quietly inverted. Both are checked against direct computation here.

var failures := 0

func _init() -> void:
	_check_axes()
	_check_elevation()
	_check_shadow()
	_check_site_sanity()
	print("\n%s" % ("ALL CHECKS PASSED" if failures == 0
		else "%d CHECK(S) FAILED" % failures))
	quit(1 if failures > 0 else 0)

func _ok(label: String, pass_: bool, detail: String) -> void:
	print("  [%s] %s -- %s" % ["PASS" if pass_ else "FAIL", label, detail])
	if not pass_:
		failures += 1

## Same convention as earth.gdshader's geo_uv and the ephemeris builder. If this
## drifts, every site moves to the wrong place on a globe that still looks fine.
func _check_axes() -> void:
	print("\nEarth-fixed axis convention:")
	for row in [[0.0, 0.0, Vector3(1, 0, 0), "0N 0E"],
			[90.0, 0.0, Vector3(0, 1, 0), "north pole"],
			[0.0, 90.0, Vector3(0, 0, -1), "0N 90E"],
			[0.0, 180.0, Vector3(-1, 0, 0), "0N 180E"]]:
		var got: Vector3 = GroundSites.site_up(row[0], row[1])
		_ok("site_up %s" % row[3], got.is_equal_approx(row[2]),
			"%v (expected %v)" % [got, row[2]])

## The squared form drops a square root from a test that runs for every object
## against every site. It must agree exactly with the direct computation.
func _check_elevation() -> void:
	print("\nSquared-form elevation test vs. direct computation:")
	var rng := RandomNumberGenerator.new()
	rng.seed = 20260915
	var disagreements := 0
	var trials := 0
	for i in 40000:
		var p := Vector3(rng.randfn(), rng.randfn(), rng.randfn())
		if p.length() < 0.01:
			continue
		p = p.normalized() * rng.randf_range(1.01, 8.0)
		var u := Vector3(rng.randfn(), rng.randfn(), rng.randfn()).normalized()
		for mask in [0.0, 3.0, 20.0]:
			trials += 1
			var elev: float = 90.0 - rad_to_deg((p - u).normalized().angle_to(u))
			var direct: bool = elev >= mask
			var fast: bool = GroundSites.is_visible(p, u, tan(deg_to_rad(mask)))
			# Ignore ties exactly on the mask, where float noise decides.
			if direct != fast and absf(elev - mask) > 1e-4:
				disagreements += 1
	_ok("agreement", disagreements == 0,
		"%d disagreements in %d trials" % [disagreements, trials])

func _check_shadow() -> void:
	print("\nCylindrical umbra test:")
	var sun := Vector3(1, 0, 0)
	_ok("behind Earth, on axis", not GroundSites.is_sunlit(Vector3(-1.2, 0, 0), sun),
		"in shadow")
	_ok("sunward side", GroundSites.is_sunlit(Vector3(1.2, 0, 0), sun), "lit")
	_ok("behind but off axis", GroundSites.is_sunlit(Vector3(-1.2, 1.5, 0), sun),
		"lit -- clears the shadow cylinder")
	# A high object behind the Earth is still in shadow near the axis.
	_ok("far behind, near axis", not GroundSites.is_sunlit(Vector3(-6.6, 0.5, 0), sun),
		"in shadow")

## Sites must land where their coordinates say. A hemisphere flip is the classic
## failure and is invisible on a globe unless checked.
func _check_site_sanity() -> void:
	print("\nSite placement:")
	for i in GroundSites.SITES.size():
		var s: Array = GroundSites.SITES[i]
		var up: Vector3 = GroundSites.site_up(s[1], s[2])
		var lat := rad_to_deg(asin(clampf(up.y, -1.0, 1.0)))
		var lon := rad_to_deg(atan2(-up.z, up.x))
		var ok: bool = absf(lat - float(s[1])) < 0.01 \
			and absf(wrapf(lon - float(s[2]), -180.0, 180.0)) < 0.01
		if not ok:
			_ok(String(s[0]), false,
				"round-trips to %.2f, %.2f" % [lat, lon])
	_ok("all %d sites round-trip" % GroundSites.SITES.size(), true,
		"latitude and longitude recovered from the unit vector")
