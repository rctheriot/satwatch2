class_name ChapterDeck
extends Node
## Drives the presentation. Chapters are authored data; this only sequences them.

signal chapter_changed(chapter: Chapter, index: int, total: int)

## Outermost radius of what is actually DRAWN, in world metres. The satellite
## field stays populated when hidden, so anything reading its extent for a
## chapter that does not show it gets an answer eight Earth radii too large.
var visible_radius_m: float = 1.0

## Clearance kept between the eye and the nearest visible object when a chapter
## derives its own camera distance. MIN_CONTENT_DISTANCE is the *borderline* of
## comfortable fusion, so presets sit back from it -- and at ~2.05 m the nearest
## content is barely in front of the wall plane, which keeps the inevitable
## frame-edge cropping of the shell harmless.
const PRESET_CLEARANCE := 0.55

var chapters: Array[Chapter] = []
var index: int = 0

var camera: CameraDirector
var sensors: SensorNetwork
var aircraft: AircraftLayer
var tec: MeshInstance3D
var winds: WindLayer
var rig: ContentRig
var field: SatelliteField
var catalog: CatalogStore
var clock: SimClock

func _ready() -> void:
	if chapters.is_empty():
		chapters = _default_deck()

## Built in code rather than as .tres so the deck is reviewable in one place and
## survives a resource re-import.
##
## Ordered as an argument, not a catalogue: build up one regime at a time from
## the crowded shells outward, put them together at true scale, and only then go
## to specific events. The full-catalog view means much more once the viewer has
## already been told what each population is.
func _default_deck() -> Array[Chapter]:
	var out: Array[Chapter] = []

	# --- Build-up: one regime at a time ---------------------------------------
	var leo := Chapter.new()
	leo.title = "LOW EARTH ORBIT"
	leo.subtitle = "Below 2,000 km — where the traffic is"
	leo.explanation = """Every point is a tracked object below 2,000 km — working satellites, spent rocket bodies, and debris. They are not spread evenly. The bands are the orbits everyone wants: sun-synchronous paths for imaging, and the shells the large constellations fly in.

An orbit here takes about 90 minutes, so a satellite passes over any given point briefly and often.

Altitude is exaggerated x2 so the shells separate. At true scale this entire layer sits within a few percent of the globe's own radius."""
	leo.regimes = ["LEO"]
	leo.content_scale = 1.45
	leo.altitude_exaggeration = 2.0
	out.append(leo)

	var meo := Chapter.new()
	meo.title = "MEDIUM EARTH ORBIT"
	meo.subtitle = "Navigation, around 20,000 km"
	meo.explanation = """Far fewer objects, much further out. This is navigation: GPS, GLONASS, Galileo and BeiDou near 20,000 km, where one orbit takes about twelve hours.

Height buys coverage. From up here each satellite sees a huge fraction of the Earth at once, so around thirty give continuous global service — against thousands needed in low orbit.

Notice the globe has shrunk. The scale changed, not the Earth."""
	meo.regimes = ["MEO"]
	meo.content_scale = 0.40
	meo.altitude_exaggeration = 1.0
	out.append(meo)

	var geo := Chapter.new()
	geo.title = "GEOSTATIONARY BELT"
	geo.subtitle = "35,786 km — one orbit per day"
	geo.explanation = """At 35,786 km an orbit takes exactly one sidereal day. A satellite over the equator therefore turns with the Earth and appears to hold still, so a ground antenna can point once and stay pointed.

That single fact makes this ring the most valuable real estate in space: communications, weather, and missile warning all live here.

It is also fixed, crowded and entirely predictable — which cuts both ways. Everything in this belt knows where everything else is, and so does everyone on the ground."""
	geo.regimes = ["GEO"]
	geo.content_scale = 0.40
	geo.altitude_exaggeration = 1.0
	geo.elevation = 0.05
	out.append(geo)

	var heo := Chapter.new()
	heo.title = "HIGHLY ELLIPTICAL"
	heo.subtitle = "Fast at perigee, loitering at apogee"
	heo.explanation = """These orbits trade a fast, low perigee for a slow, high apogee. A Molniya orbit spends most of its twelve hours loitering over one hemisphere and crosses the rest quickly.

That buys long dwell over high latitudes, which a geostationary satellite sitting on the equator cannot see well.

They also cut through every other regime on the way past, which is what makes them matter for anyone tracking what is up there."""
	heo.regimes = ["HEO"]
	heo.content_scale = 0.40
	heo.altitude_exaggeration = 1.0
	heo.elevation = 0.3
	out.append(heo)

	# --- Everything together --------------------------------------------------
	# The payoff. A LEO-tuned scale cannot hold this: the outermost object is
	# 8 Earth radii out, so at the previous scale the belt would be metres behind
	# the viewer's head. Scale is per-chapter, and this transition is the reveal.
	var full := Chapter.new()
	full.title = "THE FULL CATALOG"
	full.subtitle = "All of it, at one scale"
	full.explanation = """All four populations at once, at true scale.

The bright ball is the whole of low orbit, compressed against the planet. Green is the navigation constellations; the outer ring is the geostationary belt; red is the elliptical orbits cutting through everything.

Almost all of the objects are in the ball. Almost all of the value is in the ring. That mismatch is most of what makes this problem hard."""
	full.regimes = []
	full.content_scale = 0.40
	full.altitude_exaggeration = 1.0
	full.point_size = 0.85
	full.elevation = 0.35
	full.transition_seconds = 5.0
	out.append(full)

	# --- Specific cases -------------------------------------------------------
	var starlink := Chapter.new()
	starlink.title = "CONSTELLATION"
	starlink.subtitle = "One operator against everything else in LEO"
	starlink.explanation = """Green is Starlink. A single operator now accounts for a large share of everything in low orbit, flown as a tightly managed shell at one altitude.

Blue is every other tracked object in LEO, at the same scale.

The contrast is the point: the shape of the low-orbit population changed in under a decade, and it was one decision that changed it."""
	starlink.regimes = ["LEO"]
	starlink.highlight_name = "STARLINK"
	starlink.highlight_color = Color(0.36, 1.0, 0.52)
	starlink.content_scale = 1.2
	starlink.altitude_exaggeration = 2.0
	out.append(starlink)

	var fengyun := Chapter.new()
	fengyun.title = "BREAKUP: FENGYUN-1C"
	fengyun.subtitle = "2007 ASAT test — still on orbit"
	fengyun.explanation = """In 2007 an anti-satellite test destroyed the Fengyun-1C weather satellite at 865 km.

Red is the debris from that single event still being tracked today, nearly twenty years later. The breakup spread it into a shell crossing most other low orbits.

At that altitude there is too little atmosphere to pull it down on any useful timescale. One test, thousands of objects, indefinitely."""
	fengyun.regimes = ["LEO"]
	fengyun.highlight_intl_prefix = "1999-025"
	fengyun.content_scale = 1.45
	fengyun.altitude_exaggeration = 2.0
	fengyun.elevation = 0.55
	out.append(fengyun)

	var collision := Chapter.new()
	collision.title = "COLLISION: 2009"
	collision.subtitle = "Cosmos 2251 and Iridium 33"
	collision.explanation = """In 2009 the defunct Cosmos 2251 struck the working Iridium 33 satellite at 790 km, closing at roughly 11 km/s.

Red is the debris still catalogued from it. One collision produced two expanding clouds at an altitude already heavily used.

This is the mechanism behind the concern that debris begets debris: every fragment is itself a projectile, in the orbit band that everything else needs."""
	collision.regimes = ["LEO"]
	collision.highlight_intl_prefix = "1993-036"
	collision.content_scale = 1.45
	collision.altitude_exaggeration = 2.0
	collision.elevation = 0.5
	out.append(collision)

	var sensors := Chapter.new()
	sensors.title = "SURVEILLANCE NETWORK"
	sensors.subtitle = "What the ground can actually see, right now"
	sensors.explanation = """Green objects are in view of at least one ground site right now. Red are seen by nobody.

Blue volumes are radar coverage: everything above a site's 3-degree horizon mask, out to a nominal range. They look flat because they are — a 3-degree mask means an 87-degree half-angle, so a surveillance radar really does see close to a hemisphere. That is how a handful of sites watch most of low orbit.

Amber markers are optical telescopes. They are not drawn as volumes because they are narrow-field instruments that stare at one patch and track individual objects, rather than sweeping a fence.

Watch where the red is. The network is concentrated in the northern hemisphere, and the southern gap is real.

Optical sites need darkness on the ground and sunlight on the target at once, so most are off at any moment. Counts are exact geometry; ranges are nominal."""
	sensors.regimes = ["LEO"]
	sensors.show_sensors = true
	# Green in view, red out of view. Both states matter here, so neither is
	# pushed into the background.
	sensors.highlight_color = Color(0.32, 1.0, 0.45)
	sensors.base_color = Color(1.0, 0.26, 0.22, 1.0)
	sensors.dim_others = 0.62
	sensors.content_scale = 1.45
	sensors.altitude_exaggeration = 2.0
	sensors.elevation = 0.45
	out.append(sensors)

	return out

## Appended after load, because the wind field is optional data.
func add_wind_chapter(layer: WindLayer) -> void:
	var c := Chapter.new()
	c.title = "THE JET STREAM"
	c.subtitle = "250 hPa winds, peak %.0f km/h" % (layer.peak_speed_ms * 3.6)
	c.explanation = """Streamlines through the real 250 hPa wind field — about 10.5 kilometres up, which is airliner cruise altitude.

Colour is wind speed, on a fixed scale so it means the same thing every day: violet below 15 m/s, magenta near 30 where a jet stream is conventionally declared, orange near 50, white at 65 and above. Trail length is speed too — each streak is seven hours of travel, so the fast air draws the long streaks.

These are not decoration. A jet stream core can exceed 300 km/h, and flying with it or against it is the difference between two very different flight plans — transit time, fuel load, and sometimes whether a route closes altogether.

Note the structure: strong westerlies in a band around each mid-latitude, weak and easterly across the tropics. The southern jets are the stronger ones at this time of year.

The aircraft in the previous chapter are flying through this."""
	c.show_winds = true
	c.show_satellites = false
	c.content_scale = 1.6
	c.elevation = 0.3
	chapters.append(c)

## Appended after load, because the aircraft snapshot is optional data.
func add_aircraft_chapter(layer: AircraftLayer) -> void:
	var c := Chapter.new()
	c.title = "THE AIR DOMAIN"
	c.subtitle = "%d aircraft airborne right now" % layer.count
	c.explanation = """Every gold point is a real aircraft, airborne at this moment, from live ADS-B tracking. The purple tracks behind them are ten minutes of flight, dead-reckoned from each aircraft's reported speed and heading — a direction of travel, not a recorded path.

This is the domain everyone already has an intuition for. Airliners cruise near 10 kilometres — and at true scale that layer is thinner than the coastlines drawn on this globe. It has been exaggerated heavily just to be visible at all.

Now consider what that means for everything else on this wall. The lowest tracked satellites are about forty times higher than these aircraft, and the geostationary belt is three thousand times higher.

The air picture is crowded, contested, and very well understood. The space picture is larger by orders of magnitude, and far less of it is watched."""
	c.show_aircraft = true
	c.show_satellites = false
	c.content_scale = 1.6
	c.elevation = 0.35
	chapters.append(c)

## Appended after load rather than built into the deck, because the aurora layer
## is optional data.
func add_space_weather_chapter(weather: SpaceWeatherStore,
		tec_available: bool = false) -> void:
	var c := Chapter.new()
	c.title = "SPACE WEATHER"
	c.subtitle = "Auroral oval, Kp %.0f (%s) — geomagnetic activity raises drag in low LEO" % [
		weather.kp_index, weather.storm_label()]
	c.regimes = ["LEO"]
	c.explanation = """The green oval is the auroral oval from NOAA's OVATION model, drawn at its real emission altitude. It marks where charged particles from the solar wind are funnelling into the atmosphere.

Above it, the coloured shell is ionospheric total electron content — the number of electrons in a column, from NOAA's GloTEC model. Brighter means denser.

That second layer is the one with operational teeth. A GNSS signal crossing a dense ionosphere arrives late, so the receiver reports the wrong range. It is not the absolute level that hurts so much as sharp gradients across it, which is why GPS accuracy degrades during solar activity — and why the equatorial band, where TEC is highest and most structured, is the worst place to need precision.

The same disturbance expands the upper atmosphere, raising drag on everything in low orbit. One event, three consequences: lights in the sky, degraded navigation, and orbits that decay faster than predicted."""
	c.content_scale = 1.45
	c.altitude_exaggeration = 2.0
	# Looking well down onto the pole, where the oval lives. The night side is
	# wherever the sun is not, so the presenter orbits in azimuth to find it --
	# which is itself the point being made.
	c.elevation = 1.15
	c.show_tec = tec_available
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
	field.base_color = c.base_color
	field.dim_others = c.dim_others
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

	# The clock rate is deliberately untouched -- see Chapter's Time group.

	if sensors != null:
		sensors.visible = c.show_sensors
	if aircraft != null:
		aircraft.visible = c.show_aircraft
	if tec != null:
		tec.visible = c.show_tec
	if winds != null:
		winds.visible = c.show_winds
	field.visible = c.show_satellites

	# set_filter and the scale change both move the outermost object, so the
	# derived distance has to be computed after them.
	# Frame on what is actually drawn. With the satellite field hidden, deriving
	# the distance from its extent put the camera 15 m back for content barely
	# larger than the globe, and the Earth came out a few degrees wide.
	var radius_m := rig.content_radius_m()
	if not c.show_satellites:
		radius_m = rig.content_scale * (aircraft.max_radius()
			if aircraft != null and c.show_aircraft and aircraft.loaded else 1.0)

	visible_radius_m = radius_m
	var dist := c.camera_distance
	if dist <= 0.0:
		dist = preset_distance(radius_m)
	camera.goto(c.azimuth, c.elevation, dist,
		c.transition_seconds if animate else 0.0)

	chapter_changed.emit(c, index, chapters.size())

func next() -> void:
	apply(index + 1)

func prev() -> void:
	apply(index - 1)
