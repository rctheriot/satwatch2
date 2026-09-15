class_name ChapterDeck
extends Node
## Drives the presentation. Chapters are authored data; this only sequences them.

signal chapter_changed(chapter: Chapter, index: int, total: int)

## Clearance kept between the eye and the nearest visible object when a chapter
## derives its own camera distance. MIN_CONTENT_DISTANCE is the *borderline* of
## comfortable fusion, so presets sit back from it -- and at ~2.05 m the nearest
## content is barely in front of the wall plane, which keeps the inevitable
## frame-edge cropping of the shell harmless.
const PRESET_CLEARANCE := 0.55

var chapters: Array[Chapter] = []
var index: int = 0

var camera: CameraDirector
var conjunctions: ConjunctionStore
var sensors: SensorNetwork
var inset: ConjunctionInset
var rig: ContentRig
var field: SatelliteField
var catalog: CatalogStore
var clock: SimClock

func _ready() -> void:
	if chapters.is_empty():
		chapters = _default_deck()

## Appended after load, because it depends on data that may not be built yet.
## tools/find_conjunctions.py is optional -- without it the deck is just shorter.
func add_conjunction_chapter(index: int, e: Dictionary) -> void:
	var c := Chapter.new()
	c.title = "CLOSE APPROACH"
	c.subtitle = "%s / %s — %.0f m at %.1f km/s" % [
		e.get("a_name", "?"), e.get("b_name", "?"),
		float(e.get("miss_km", 0.0)) * 1000.0,
		float(e.get("relative_speed_kms", 0.0))]
	c.regimes = ["LEO"]
	c.conjunction_index = index
	c.content_scale = 1.45
	c.altitude_exaggeration = 2.0
	c.elevation = 0.35
	chapters.append(c)

## Built in code rather than as .tres so the deck is reviewable in one place and
## survives a resource re-import.
func _default_deck() -> Array[Chapter]:
	var out: Array[Chapter] = []

	var leo := Chapter.new()
	leo.title = "LOW EARTH ORBIT"
	leo.subtitle = "Tracked objects below 2,000 km"
	leo.regimes = ["LEO"]
	leo.explanation = """Every point is a tracked object below 2,000 km — working satellites, spent rocket bodies, and debris. They are not spread evenly. The bands are the orbits everyone wants: sun-synchronous paths for imaging, and the shells the big constellations fly in.

Altitude is exaggerated x2 so the shells separate. At true scale this entire layer sits within a few percent of the globe's own radius."""
	leo.content_scale = 1.45
	leo.altitude_exaggeration = 2.0
	out.append(leo)

	# The pull-back. A LEO-tuned scale cannot hold MEO/GEO/HEO: the outermost
	# object is 8 Earth radii out, so at the LEO scale the GEO belt would be
	# metres behind the viewer's head. Scale is therefore per-chapter, and this
	# transition is the reveal -- do not cut it.
	var full := Chapter.new()
	full.title = "THE FULL CATALOG"
	full.subtitle = "LEO shells out to the geostationary belt"
	full.regimes = []
	full.explanation = """Pulled back to true scale, with no exaggeration.

The bright ball is everything from the previous view — all of low orbit, compressed against the planet. The outer ring is the geostationary belt at 35,786 km: one orbit per day, so a satellite there hangs over a single longitude. Green marks the navigation constellations in between; red marks highly elliptical orbits that climb far out and fall back.

Almost all the objects are in the ball. Almost all the value is in the ring."""
	full.content_scale = 0.40
	full.altitude_exaggeration = 1.0
	# The one genuinely over-dense view: every regime at once, packed small.
	full.point_size = 0.85
	full.elevation = 0.35
	full.transition_seconds = 5.0
	out.append(full)

	for r in ["LEO", "MEO", "GEO", "HEO"]:
		var c := Chapter.new()
		c.title = r
		c.subtitle = {"LEO": "Imaging, comms, the crowded shells",
			"MEO": "Navigation constellations",
			"GEO": "Fixed over one longitude",
			"HEO": "Highly elliptical, long dwell at apogee"}[r]
		c.regimes = [r]
		c.explanation = {"LEO": """Low Earth orbit, below 2,000 km. Imaging, weather, and the broadband constellations. An orbit takes about 90 minutes, so a satellite here passes over any given point briefly and often.

This is where the traffic is, and where almost all the debris is.""", "MEO": """Medium Earth orbit. This is navigation: GPS, GLONASS, Galileo and BeiDou near 20,000 km, where one orbit takes about twelve hours.

Higher orbits mean fewer satellites are needed for continuous global coverage — around thirty each, against thousands in low orbit.""",
			"GEO": """At 35,786 km an orbit takes exactly one sidereal day. A satellite over the equator therefore turns with the Earth and appears to hold still, so a ground antenna can simply point and stay pointed.

That makes this belt the most valuable real estate in space. It is also fixed, crowded, and entirely predictable — which cuts both ways.""", "HEO": """Highly elliptical orbits trade a fast, low perigee for a slow, high apogee. A Molniya orbit spends most of its twelve hours loitering over one hemisphere.

That buys coverage of high latitudes, which a geostationary satellite on the equator cannot see well."""}[r]
		c.content_scale = 1.45 if r == "LEO" else 0.40
		c.altitude_exaggeration = 2.0 if r == "LEO" else 1.0
		c.elevation = 0.05 if r == "GEO" else 0.3
		out.append(c)

	var starlink := Chapter.new()
	starlink.title = "CONSTELLATION"
	starlink.subtitle = "STARLINK against the rest of the LEO population"
	# Scoped to LEO deliberately: Starlink is a LEO constellation, and applying
	# altitude exaggeration to the whole catalog would push the outermost HEO
	# object far enough out to wreck the framing.
	starlink.regimes = ["LEO"]
	starlink.explanation = """Green is Starlink. A single operator now accounts for a large share of everything in low orbit, flown as a tightly managed shell at one altitude.

Blue is every other tracked object in LEO, at the same scale. The contrast is the point: the population changed shape in under a decade."""
	starlink.highlight_name = "STARLINK"
	# Green: an operational constellation, not a hazard.
	starlink.highlight_color = Color(0.36, 1.0, 0.52)
	starlink.content_scale = 1.2
	starlink.altitude_exaggeration = 2.0
	out.append(starlink)

	# --- Breakup events -------------------------------------------------------
	# Debris from one event shares its launch's international designator, so a
	# whole cloud is one prefix. Both of these are still the largest identifiable
	# families in the catalog, which is the point being made.
	var fengyun := Chapter.new()
	fengyun.title = "BREAKUP: FENGYUN-1C"
	fengyun.subtitle = "2007 ASAT test — debris still on orbit today"
	fengyun.regimes = ["LEO"]
	fengyun.explanation = """In 2007 an anti-satellite test destroyed the Fengyun-1C weather satellite at 865 km altitude.

Red is the debris from that single event still being tracked today, almost twenty years later. The breakup spread it into a shell crossing most other low orbits. At that altitude there is too little atmosphere to pull it down on any useful timescale, so it stays.

One test, thousands of objects, indefinitely."""
	fengyun.highlight_intl_prefix = "1999-025"
	fengyun.content_scale = 1.45
	fengyun.altitude_exaggeration = 2.0
	fengyun.elevation = 0.55
	out.append(fengyun)

	var collision := Chapter.new()
	collision.title = "COLLISION: 2009"
	collision.subtitle = "Cosmos 2251 and Iridium 33 — two clouds from one event"
	collision.regimes = ["LEO"]
	collision.explanation = """In 2009 the defunct Cosmos 2251 struck the working Iridium 33 satellite at 790 km, closing at roughly 11 km/s.

Red is the debris still catalogued from it. One collision produced two expanding clouds at an altitude already heavily used — the mechanism behind the concern that debris can beget more debris."""
	collision.highlight_intl_prefix = "1993-036"
	collision.content_scale = 1.45
	collision.altitude_exaggeration = 2.0
	collision.elevation = 0.5
	out.append(collision)

	var sensors := Chapter.new()
	sensors.title = "SURVEILLANCE NETWORK"
	sensors.subtitle = "What the ground can actually see, right now"
	sensors.explanation = """Blue cones are ground radars; amber are optical telescopes. Each cone is the volume that site can geometrically see — everything above its horizon mask, out to a nominal range.

Note how flat and wide the radar volumes are. A 3-degree mask means an 87-degree half-angle, so a surveillance radar's access volume really is close to a hemisphere. That is why a handful of sites can watch most of low orbit.

The optical sites behave differently. They see reflected sunlight, so they need darkness on the ground and sunlight on the target at the same time — watch them switch off as their site turns into daylight. That narrow window each night is when most deep-space surveillance actually happens.

Counts are exact geometry. Ranges are nominal: real detection capability depends on sensor parameters that are not public."""
	sensors.regimes = ["LEO"]
	sensors.show_sensors = true
	sensors.highlight_color = Color(0.45, 1.0, 0.75)
	sensors.content_scale = 1.45
	sensors.altitude_exaggeration = 2.0
	sensors.elevation = 0.45
	sensors.rate_index = 4
	out.append(sensors)

	return out

## Appended after load, like the conjunction chapter, because the aurora layer
## is optional data.
func add_space_weather_chapter(weather: SpaceWeatherStore) -> void:
	var c := Chapter.new()
	c.title = "SPACE WEATHER"
	c.subtitle = "Auroral oval, Kp %.0f (%s) — geomagnetic activity raises drag in low LEO" % [
		weather.kp_index, weather.storm_label()]
	c.regimes = ["LEO"]
	c.explanation = """The green oval is the auroral oval from NOAA's OVATION model, drawn at its real emission altitude rather than painted on the surface. It marks where charged particles from the solar wind are funnelling into the atmosphere.

It matters here because the same disturbance heats and expands the upper atmosphere. Drag rises on everything in low orbit, orbits decay faster than predicted, and objects can be temporarily lost and have to be re-acquired.

Space weather is why the predictions on this wall carry error bars."""
	c.content_scale = 1.45
	c.altitude_exaggeration = 2.0
	# Looking well down onto the pole, where the oval lives. The night side is
	# wherever the sun is not, so the presenter orbits in azimuth to find it --
	# which is itself the point being made.
	c.elevation = 1.15
	c.rate_index = 4
	chapters.append(c)

## Distance that keeps the outermost visible object PRESET_CLEARANCE beyond the
## fusion floor. Chapters with camera_distance = 0 use this.
static func preset_distance(content_radius_m: float) -> float:
	return CameraDirector.MIN_CONTENT_DISTANCE + PRESET_CLEARANCE + content_radius_m

func apply(i: int, animate: bool = true) -> void:
	if chapters.is_empty():
		return
	index = posmod(i, chapters.size())
	var c := chapters[index]

	field.highlight_color = c.highlight_color
	rig.content_scale = c.content_scale
	field.altitude_exaggeration = c.altitude_exaggeration
	field.point_size = c.point_size
	field.set_filter(c.regimes)

	if not c.highlight_intl_prefix.is_empty():
		field.set_highlight(catalog.indices_with_intl_prefix(c.highlight_intl_prefix))
	elif not c.highlight_name.is_empty():
		field.set_highlight(catalog.indices_matching_name(c.highlight_name))
	else:
		field.set_highlight(PackedInt32Array())

	clock.rate_index = c.rate_index

	# A conjunction chapter jumps the clock to the encounter and slows it down;
	# at 1 min/sec a 6 km/s approach is over before anyone sees it.
	if c.conjunction_index >= 0 and conjunctions != null \
			and c.conjunction_index < conjunctions.events.size():
		var e: Dictionary = conjunctions.events[c.conjunction_index]
		inset.show_event(e)
		clock.paused = false
		clock.rate_index = 1
		clock.now_unix = float(e.get("tca_unix", clock.now_unix)) - 45.0
		field.set_highlight(PackedInt32Array([
			int(e.get("a_index", -1)), int(e.get("b_index", -1))]))
	elif inset != null:
		inset.visible = false

	if sensors != null:
		sensors.visible = c.show_sensors

	# set_filter and the scale change both move the outermost object, so the
	# derived distance has to be computed after them.
	var dist := c.camera_distance
	if dist <= 0.0:
		dist = preset_distance(rig.content_radius_m())
	camera.goto(c.azimuth, c.elevation, dist,
		c.transition_seconds if animate else 0.0)

	chapter_changed.emit(c, index, chapters.size())

func next() -> void:
	apply(index + 1)

func prev() -> void:
	apply(index - 1)
