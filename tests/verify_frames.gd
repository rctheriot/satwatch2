extends SceneTree
## Frame-consistency checks. Run headless:
##   Godot --path . --headless --script res://tests/verify_frames.gd
##
## These guard the two failure modes that look completely plausible on screen:
## a reflected axis mapping (every orbit silently retrograde) and a constant
## longitude offset between the Earth texture and the satellites above it.

const RE_KM := 6378.137

var failures := 0

func _init() -> void:
	var store := EphemerisStore.new()
	var catalog := CatalogStore.new()
	if store.load_from("res://data/ephemeris.bin") != OK \
			or catalog.load_from("res://data/catalog.json") != OK:
		push_error("verify_frames: no ephemeris. Run tools/build_ephemeris.py.")
		quit(1)
		return

	var clock := SimClock.new()
	clock.configure(store.epoch_unix, store.span_seconds())

	_check_prograde(store, catalog, clock)
	_check_subpoint(store, catalog, clock)
	_check_altitudes(store, catalog, clock)
	_check_geo_stationarity(store, catalog, clock)
	_check_chapter_clearance(catalog)

	print("\n%s" % ("ALL CHECKS PASSED" if failures == 0 else "%d CHECK(S) FAILED" % failures))
	quit(1 if failures > 0 else 0)

func _ok(label: String, pass_: bool, detail: String) -> void:
	print("  [%s] %s -- %s" % ["PASS" if pass_ else "FAIL", label, detail])
	if not pass_:
		failures += 1

## Every authored chapter must keep all its visible content outside the stereo
## comfort floor. RigController clamps this at runtime, so a bad chapter would
## be silently corrected rather than crash -- meaning the authored framing would
## quietly not be what appears on the wall. Worse, if the clamp itself were ever
## wrong, the failure is viewer discomfort at a briefing, not a visible bug.
## Nothing else in the suite exercises this.
func _check_chapter_clearance(catalog: CatalogStore) -> void:
	print("\nChapter framing: fusion floor %.2f m, and frame-edge cropping only "
		% RigController.MIN_CONTENT_DISTANCE + "near the wall plane:")
	var deck := ChapterDeck.new()
	var chapters: Array[Chapter] = deck._default_deck()
	for c in chapters:
		var max_r := 1.0
		for o in catalog.objects:
			if not c.regimes.is_empty() and not (String(o.get("regime", "")) in c.regimes):
				continue
			var r: float = float(o.get("max_radius_re", 1.0))
			max_r = maxf(max_r, 1.0 + (r - 1.0) * c.altitude_exaggeration)
		# Same derivation the runtime uses, so this checks the authored chapter
		# rather than re-implementing the rule and agreeing with itself.
		var dist := RigController.safe_center_distance(
			c.center_distance, c.rig_scale, max_r, 0.55)
		var nearest := dist - max_r * c.rig_scale
		var globe_deg := 2.0 * rad_to_deg(atan(c.rig_scale / dist))
		# Parallax at the nearest point. The shell overruns a 2.04 m wall in
		# every chapter worth looking at, so it is always cut by the frame edge;
		# what keeps that harmless is the cut content sitting near the wall
		# plane rather than floating well in front of it.
		var p_mm := RigController.EYE_SEPARATION \
			* (1.0 - RigController.WALL_DISTANCE / nearest) * 1000.0
		var ok := nearest >= RigController.MIN_CONTENT_DISTANCE and p_mm > -12.0
		_ok("%-16s" % c.title, ok,
			"nearest %.2f m (%+.1f mm parallax), centre %.2f m, globe %.0f deg"
				% [nearest, p_mm, dist, globe_deg])
	deck.free()

## Right ascension / declination of a point in the inertial (Godot-mapped TEME)
## frame, using the same convention as earth.gdshader's geo_uv().
static func ra_dec(p: Vector3) -> Vector2:
	return Vector2(atan2(-p.z, p.x), asin(clampf(p.y / p.length(), -1.0, 1.0)))

## Geographic longitude = right ascension minus GMST.
static func geo_lon_deg(p: Vector3, gmst: float) -> float:
	return rad_to_deg(wrapf(ra_dec(p).x - gmst, -PI, PI))

func _find(catalog: CatalogStore, name: String) -> int:
	var hits := catalog.indices_matching_name(name)
	return hits[0] if hits.size() > 0 else -1

func _check_prograde(store: EphemerisStore, catalog: CatalogStore, clock: SimClock) -> void:
	print("\nPrograde motion (catches a reflected axis mapping):")
	var iss := _find(catalog, "ISS (ZARYA)")
	if iss < 0:
		_ok("ISS present", false, "not in catalog")
		return
	var t0 := store.epoch_unix
	var a := store.position_at(iss, t0)
	var b := store.position_at(iss, t0 + 60.0)
	# Angular momentum about +Y must be positive for a prograde orbit.
	var l_y := a.z * b.x - a.x * b.z
	_ok("ISS is prograde", l_y > 0.0, "L_y = %+.4f (must be > 0)" % l_y)

func _check_subpoint(store: EphemerisStore, catalog: CatalogStore, clock: SimClock) -> void:
	print("\nSub-satellite point vs. the builder's independent computation:")
	var ref := catalog.registration_reference
	if ref.is_empty():
		_ok("registration reference present", false,
			"catalog.json has none -- rebuild with tools/build_ephemeris.py")
		return
	var i := -1
	for n in catalog.objects.size():
		if int(catalog.objects[n].get("norad_id", -1)) == int(ref.get("norad_id", -2)):
			i = n
			break
	if i < 0:
		_ok("reference object present", false, "NORAD %s not in catalog" % ref.get("norad_id"))
		return

	var t: float = ref.get("unix", store.epoch_unix)
	clock.now_unix = t
	var p := store.position_at(i, t)
	var lat := rad_to_deg(ra_dec(p).y)
	var lon := geo_lon_deg(p, clock.gmst())
	var ref_lat: float = ref.get("lat_deg", 0.0)
	var ref_lon: float = ref.get("lon_deg", 0.0)
	var d_lat: float = absf(lat - ref_lat)
	var d_lon: float = absf(wrapf(lon - ref_lon, -180.0, 180.0))
	# Python and GDScript implement GMST separately, so agreement here means both
	# share one frame convention -- it is not a tautology.
	_ok("%s latitude" % ref.get("name", "?"), d_lat < 0.5,
		"engine %+.2f vs builder %+.2f (d=%.3f)" % [lat, ref_lat, d_lat])
	_ok("%s longitude" % ref.get("name", "?"), d_lon < 0.5,
		"engine %+.2f vs builder %+.2f (d=%.3f)" % [lon, ref_lon, d_lon])

func _check_altitudes(store: EphemerisStore, catalog: CatalogStore, _clock: SimClock) -> void:
	print("\nAltitudes agree with catalog apogee/perigee:")
	for name in ["ISS (ZARYA)", "HST"]:
		var i := _find(catalog, name)
		if i < 0:
			continue
		var peri: float = catalog.objects[i].get("perigee_km", 0.0)
		var apo: float = catalog.objects[i].get("apogee_km", 0.0)
		var lo := 1e9
		var hi := -1e9
		for s in store.n_samples:
			var alt := (store.position_at(i, store.epoch_unix + s * store.step_seconds)
				.length() - 1.0) * RE_KM
			lo = minf(lo, alt)
			hi = maxf(hi, alt)
		var inside := lo > peri - 60.0 and hi < apo + 60.0
		_ok("%s altitude band" % name, inside,
			"propagated %.0f-%.0f km, catalog %.0f-%.0f km" % [lo, hi, peri, apo])

func _check_geo_stationarity(store: EphemerisStore, catalog: CatalogStore,
		clock: SimClock) -> void:
	print("\nGEO objects hold longitude (catches a GMST sign or rate error):")
	# The GEO bucket is geoSYNCHRONOUS, which includes eccentric and drifting
	# derelicts whose longitude genuinely swings by degrees within an hour.
	# Only near-circular, near-equatorial objects are actually station-kept, and
	# only those say anything about whether our frame is right.
	var geo := PackedInt32Array()
	for i in catalog.indices_where("regime", "GEO"):
		var o: Dictionary = catalog.objects[i]
		if float(o.get("ecc", 1.0)) < 0.0005 and float(o.get("inclination_deg", 90.0)) < 0.5:
			geo.append(i)
	if geo.is_empty():
		_ok("station-kept GEO objects present", false, "none matched")
		return
	var worst := 0.0
	var checked := 0
	for i in geo:
		if checked >= 40:
			break
		checked += 1
		var t0 := store.epoch_unix
		var t1 := t0 + 3000.0
		clock.now_unix = t0
		var lon0 := geo_lon_deg(store.position_at(i, t0), clock.gmst())
		clock.now_unix = t1
		var lon1 := geo_lon_deg(store.position_at(i, t1), clock.gmst())
		worst = maxf(worst, absf(wrapf(lon1 - lon0, -180.0, 180.0)))
	# A station-kept geostationary satellite holds longitude to a small fraction
	# of a degree over 50 minutes. If the Earth rotation sign or rate were wrong,
	# this would be tens of degrees.
	_ok("station-kept GEO longitude drift", worst < 0.5,
		"worst drift %.4f deg over 50 min across %d objects" % [worst, checked])
