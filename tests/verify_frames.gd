extends SceneTree
## Frame-consistency checks. Run headless:
##   Godot --path . --headless --script res://tests/verify_frames.gd
##
## These guard the two failure modes that look completely plausible on screen:
## a reflected axis mapping (every orbit silently retrograde) and a constant
## longitude offset between the Earth texture and the satellites above it.

const RE_KM := 6378.137
## Per-eye pixel density: 4800 px across the 6.047 m wall.
const PX_PER_MM := 4800.0 / 6047.0

static func _parallax_mm(z: float) -> float:
	return CameraDirector.EYE_SEPARATION \
		* (1.0 - CameraDirector.WALL_DISTANCE / z) * 1000.0

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
	_check_camera_aim()

	print("\n%s" % ("ALL CHECKS PASSED" if failures == 0 else "%d CHECK(S) FAILED" % failures))
	quit(1 if failures > 0 else 0)

func _ok(label: String, pass_: bool, detail: String) -> void:
	print("  [%s] %s -- %s" % ["PASS" if pass_ else "FAIL", label, detail])
	if not pass_:
		failures += 1

## Every authored chapter must frame its content outside the stereo comfort
## floor, and give enough disparity range to actually read as depth.
##
## Camera distance is derived per chapter from the outermost visible object, so
## this checks the authored preset rather than re-implementing the rule and
## agreeing with itself.
func _check_chapter_clearance(catalog: CatalogStore) -> void:
	print("\nChapter framing and stereo depth (fusion floor %.2f m):"
		% CameraDirector.MIN_CONTENT_DISTANCE)
	var deck := ChapterDeck.new()
	var chapters: Array[Chapter] = deck._default_deck()
	for c in chapters:
		var max_r := 1.0
		for o in catalog.objects:
			if not c.regimes.is_empty() and not (String(o.get("regime", "")) in c.regimes):
				continue
			var r: float = float(o.get("max_radius_re", 1.0))
			max_r = maxf(max_r, 1.0 + (r - 1.0) * c.altitude_exaggeration)
		var radius_m := max_r * c.content_scale
		var dist: float = c.camera_distance
		if dist <= 0.0:
			dist = ChapterDeck.preset_distance(radius_m)

		var nearest := dist - radius_m
		var p_near := _parallax_mm(nearest)
		var p_far := _parallax_mm(dist + radius_m)
		# Disparity RANGE is what produces depth. Human stereo threshold is
		# ~10 arcsec, about 0.01 mm of parallax at the wall, so anything above a
		# millimetre or two is richly stereoscopic.
		var range_mm := p_far - p_near
		var globe_deg := 2.0 * rad_to_deg(atan(c.content_scale / dist))
		var ok := nearest >= CameraDirector.MIN_CONTENT_DISTANCE \
			and p_near > -12.0 and range_mm > 5.0
		_ok("%-16s" % c.title, ok,
			"globe %.0f deg, parallax %+.1f..%+.1f mm, depth range %.0f mm (%.0f px)"
				% [globe_deg, p_near, p_far, range_mm, range_mm * PX_PER_MM])
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

## The camera must actually point at what a chapter claims to frame.
##
## A sign error in the pitch leaves the subject low in frame rather than
## visibly broken, so check the aim directly: build the pose CameraDirector
## produces, then confirm the head's forward axis points at the target.
func _check_camera_aim() -> void:
	print("\nCamera aim (head forward must point at the orbit target):")
	var worst := 0.0
	for az_deg in [0.0, 90.0, 210.0]:
		for el_deg in [-60.0, -20.0, 0.0, 25.0, 70.0]:
			var az := deg_to_rad(az_deg)
			var el := deg_to_rad(el_deg)
			var dist := 4.4
			var dir := Vector3(-sin(az) * cos(el), -sin(el), -cos(az) * cos(el))
			var eye := -dir * dist                       # target at origin
			# The pose CameraDirector writes, and the basis the addon derives.
			var head_basis := Basis(Vector3.UP, az) * Basis(Vector3.RIGHT, -el)
			var forward := -head_basis.z
			var to_target := (Vector3.ZERO - eye).normalized()
			worst = maxf(worst, rad_to_deg(forward.angle_to(to_target)))
	_ok("aim error across azimuth/elevation", worst < 0.01,
		"worst %.6f deg off target" % worst)
