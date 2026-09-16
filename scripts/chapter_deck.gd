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

## Catalog indices the CURRENT chapter highlights, e.g. a debris cloud or one
## constellation -- empty when the chapter highlights nothing. main.gd reads
## this to decide which indices the orbit-trail toggle draws: a chapter that
## calls out a specific subset should trail that subset, not its whole
## (possibly capped-out) filtered population. Set alongside field.set_highlight()
## in apply(), from the same computed indices, so the two never disagree.
var highlighted_indices: PackedInt32Array = PackedInt32Array()

var camera: CameraDirector
var sensors: SensorNetwork
var tec: MeshInstance3D
var winds: WindLayer
var aurora: MeshInstance3D
var rig: ContentRig
var field: SatelliteField
var catalog: CatalogStore
var clock: SimClock

func _ready() -> void:
	if chapters.is_empty():
		chapters = _default_deck()

## _default_deck() runs from _ready(), which for a child node happens before
## main.gd's own _ready() body has set `catalog` -- and tests call
## _default_deck() directly with no catalog at all -- so it cannot depend on
## catalog being available. main.gd calls this afterward, once catalog is
## actually loaded, to fill in the live Starlink count.
func refresh_catalog_text() -> void:
	if catalog == null:
		return
	for c in chapters:
		if c.title != "STARLINK'S CONSTELLATION":
			continue
		var starlink_n := catalog.indices_matching_name("STARLINK").size()
		var leo_n := int(catalog.regime_counts.get("LEO", 0))
		if leo_n <= 0:
			return
		var pct := 100.0 * float(starlink_n) / float(leo_n)
		c.explanation += "\n\nRight now, %s of the %s tracked objects in low Earth orbit are Starlink satellites, about %d%% of everything up there." \
			% [_comma(starlink_n), _comma(leo_n), roundi(pct)]

static func _comma(n: int) -> String:
	var s := str(n)
	var out := ""
	var count := 0
	for i in range(s.length() - 1, -1, -1):
		out = s[i] + out
		count += 1
		if count % 3 == 0 and i != 0:
			out = "," + out
	return out

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
	leo.subtitle = "Below 2,000 kilometers, where most satellites are"
	leo.explanation = """This is low Earth orbit: everything flying below 2,000 kilometers up. It's the most crowded layer in space, home to working satellites, old rocket stages, and leftover debris from decades of launches.

A satellite here circles the planet in about 90 minutes, so it passes overhead often but stays in view for only a few minutes at a time. That's why watching any one spot on Earth takes a lot of satellites working together.

To make the layers easier to see, altitudes in this scene are stretched to twice their real size. At true scale, this entire band would sit almost flush against the globe."""
	leo.regimes = ["LEO"]
	leo.content_scale = 1.45
	leo.altitude_exaggeration = 2.0
	out.append(leo)

	var meo := Chapter.new()
	meo.title = "MEDIUM EARTH ORBIT"
	meo.subtitle = "Navigation satellites, about 20,000 kilometers up"
	meo.explanation = """Much farther out, and with far fewer satellites, this is where navigation systems live: GPS and its counterparts from other countries, orbiting near 20,000 kilometers up. A satellite here takes about twelve hours to circle the Earth once.

Being higher up means seeing more of the planet at once. A single satellite up here can be in view across a huge stretch of Earth, so it takes only about thirty of them, spread around the globe, to give steady worldwide coverage. Low Earth orbit needs thousands to do the same job.

Notice the globe looks smaller here. That's the camera pulling back to fit the wider orbit in view. The Earth hasn't changed size, only the scale of the picture."""
	meo.regimes = ["MEO"]
	meo.content_scale = 0.40
	meo.altitude_exaggeration = 1.0
	out.append(meo)

	var geo := Chapter.new()
	geo.title = "GEOSTATIONARY ORBIT"
	geo.subtitle = "35,786 kilometers up, one lap per day"
	geo.explanation = """At exactly 35,786 kilometers above the equator, a satellite takes one full day to circle the Earth, the same time it takes the planet to spin once. That means the satellite appears to hang still over one spot on the ground.

That's an extremely useful trick. A satellite dish can point at one fixed spot in the sky and never have to move. Because of that, this ring holds some of the most valuable real estate in space: communications, weather forecasting, and early warning satellites all live here.

It's also crowded and completely predictable. Every operator up here knows exactly where every other satellite is, and so does everyone tracking from the ground."""
	geo.regimes = ["GEO"]
	geo.content_scale = 0.40
	geo.altitude_exaggeration = 1.0
	geo.elevation = 0.05
	out.append(geo)

	var heo := Chapter.new()
	heo.title = "HIGHLY ELLIPTICAL ORBIT"
	heo.subtitle = "Fast down low, slow way up high"
	heo.explanation = """These orbits are stretched into long ellipses instead of circles. A satellite on one of these paths swings in close to Earth and moves very fast for a short time, then climbs out to a high, slow arc where it lingers for hours before swinging back.

That long, slow stretch is useful for watching places a satellite parked over the equator can't see well, like the far north or far south. A satellite on one of these paths can spend most of its time hovering over one hemisphere before racing back around.

Because these paths stretch from close to Earth all the way out past the other orbit types, they cut through every other layer on this wall on their way past."""
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
	full.subtitle = "Every tracked object, at true scale"
	full.explanation = """This is everything at once, drawn at true scale. No exaggeration this time.

The bright, crowded ball hugging the planet is low Earth orbit. Green shows the navigation satellites farther out. The thin outer ring is the geostationary belt. Red marks the stretched, looping orbits that cut across everything else.

Almost all of the tracked objects are packed into that inner ball. Almost all of the value sits in the thin outer ring. That mismatch, thousands of objects crowded low and a handful of critical satellites spread thin and far out, is most of what makes keeping track of space traffic hard."""
	full.regimes = []
	full.content_scale = 0.40
	full.altitude_exaggeration = 1.0
	full.point_size = 0.85
	full.elevation = 0.35
	full.transition_seconds = 5.0
	full.legend = [
		{"color": PanelTheme.REGIME_COLORS["LEO"], "label": "Low Earth orbit"},
		{"color": PanelTheme.REGIME_COLORS["MEO"], "label": "Medium Earth orbit (navigation)"},
		{"color": PanelTheme.REGIME_COLORS["GEO"], "label": "Geostationary belt"},
		{"color": PanelTheme.REGIME_COLORS["HEO"], "label": "Highly elliptical orbits"},
	]
	out.append(full)

	# --- Specific cases -------------------------------------------------------
	var starlink := Chapter.new()
	starlink.title = "STARLINK'S CONSTELLATION"
	starlink.subtitle = "One company's satellites against everything else in low orbit"
	starlink.explanation = """Green marks satellites from Starlink, a single company's constellation, flown together at one altitude as a tightly managed fleet. Blue is every other tracked object in low Earth orbit, at the same scale.

This one constellation now accounts for a large share of everything flying in low orbit. That shift happened in under a decade, and it was one company's decision that drove it."""
	starlink.regimes = ["LEO"]
	starlink.highlight_name = "STARLINK"
	starlink.highlight_color = Color(0.36, 1.0, 0.52)
	starlink.content_scale = 1.2
	starlink.altitude_exaggeration = 2.0
	starlink.legend = [
		{"color": Color(0.36, 1.0, 0.52), "label": "This constellation"},
		{"color": PanelTheme.REGIME_COLORS["LEO"], "label": "Everything else in low orbit"},
	]
	out.append(starlink)

	var fengyun := Chapter.new()
	fengyun.title = "A SATELLITE BREAKUP"
	fengyun.subtitle = "A 2007 test, and debris still in orbit today"
	fengyun.explanation = """In 2007, a missile test deliberately destroyed a weather satellite called Fengyun-1C, orbiting about 865 kilometers up. Red marks the debris from that single event that is still being tracked today, nearly twenty years later.

The explosion scattered wreckage into a wide shell of orbits, crossing paths with most other satellites in low Earth orbit.

At that altitude there's too little air to drag the debris back down anytime soon. One test created thousands of fragments that will, for practical purposes, stay in orbit indefinitely."""
	fengyun.regimes = ["LEO"]
	fengyun.highlight_intl_prefix = "1999-025"
	fengyun.content_scale = 1.45
	fengyun.altitude_exaggeration = 2.0
	fengyun.elevation = 0.55
	fengyun.legend = [
		{"color": fengyun.highlight_color, "label": "Debris from this event"},
		{"color": PanelTheme.REGIME_COLORS["LEO"], "label": "Other tracked objects"},
	]
	out.append(fengyun)

	var collision := Chapter.new()
	collision.title = "A SATELLITE COLLISION"
	collision.subtitle = "2009: two satellites destroyed in low orbit"
	collision.explanation = """In 2009, a defunct Russian satellite called Cosmos 2251 collided with a working American communications satellite, Iridium 33, at about 790 kilometers up. They struck each other at roughly 11 kilometers per second, over 20 times the speed of a rifle bullet.

Red marks the debris still tracked from that single crash. One collision produced two separate, expanding clouds of wreckage, right in an altitude band that's heavily used.

This is the risk experts worry about most: every fragment becomes its own hazard, in the same crowded band everyone else needs to fly through."""
	collision.regimes = ["LEO"]
	collision.highlight_intl_prefix = "1993-036"
	collision.content_scale = 1.45
	collision.altitude_exaggeration = 2.0
	collision.elevation = 0.5
	collision.legend = [
		{"color": collision.highlight_color, "label": "Debris from this collision"},
		{"color": PanelTheme.REGIME_COLORS["LEO"], "label": "Other tracked objects"},
	]
	out.append(collision)

	var sensors := Chapter.new()
	sensors.title = "THE TRACKING NETWORK"
	sensors.subtitle = "What ground radar can actually see, right now"
	sensors.explanation = """Green objects are currently in view of at least one radar site on the ground. Red objects aren't being seen by anyone at this moment.

These are sites in the US Space Surveillance Network: mostly operated by the US Space Force, plus a few run by allied countries hosting a site, like the United Kingdom and Norway. It's one specific network, not every tracking system on Earth. Other countries, including Russia and China, run their own separate networks that aren't shown here.

The wide blue domes are each site's coverage, reaching out to a representative range. They look almost flat on top because they nearly are: a radar that can see down to 3 degrees above the horizon covers almost half the sky, which is how a handful of ground sites can watch most of low orbit between them.

Notice where the red clusters: coverage is heaviest in the northern hemisphere, and that gap in the south is real. The counts shown here come from exact geometry. The coverage domes themselves are representative, not exact sensor specifications, which aren't public."""
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
	sensors.legend = [
		{"color": sensors.highlight_color, "label": "Currently tracked"},
		{"color": sensors.base_color, "label": "Not currently tracked"},
		{"color": PanelTheme.ACCENT, "label": "Radar coverage"},
	]
	out.append(sensors)

	return out

## Appended after load, because the wind field is optional data.
func add_wind_chapter(layer: WindLayer) -> void:
	var c := Chapter.new()
	c.title = "THE JET STREAM"
	c.subtitle = "Real wind data, about 10 kilometers up"
	c.explanation = """These streamlines follow real wind data at around 10.5 kilometers up, roughly the cruising height of an airliner and where the jet streams live.

Color shows wind speed on a fixed scale, so it means the same thing no matter when you're looking: blue is calm, moving up through green and orange to red at the fastest winds, above about 65 meters per second (234 kilometers per hour). A jet stream is usually defined as a core faster than about 30 meters per second. Streak length also shows speed, so fast air draws long streaks and slow air draws short ones.

This isn't just weather trivia. A strong jet stream core can top 300 kilometers per hour, and flying with it or against it can mean very different flight times and fuel needs. Notice the pattern: strong winds blowing west to east around the middle latitudes, and weaker, often reversed winds near the equator."""
	c.show_winds = true
	c.show_satellites = false
	c.content_scale = 1.6
	c.elevation = 0.3
	c.legend = [
		{"color": Color(0.08, 0.28, 0.85), "label": "Calm"},
		{"color": Color(0.28, 0.92, 0.48), "label": "~30 m/s, jet stream threshold"},
		{"color": Color(1.00, 0.55, 0.14), "label": "~52 m/s"},
		{"color": Color(1.00, 0.18, 0.16), "label": "65+ m/s (234+ km/h)"},
	]
	chapters.append(c)

## Appended after load rather than built into the deck, because the aurora layer
## is optional data.
func add_space_weather_chapter(weather: SpaceWeatherStore,
		tec_available: bool = false) -> void:
	var c := Chapter.new()
	c.title = "SPACE WEATHER"
	c.subtitle = "How the sun disturbs satellites and GPS"
	c.regimes = ["LEO"]
	c.explanation = """The green oval marks the aurora, drawn at the altitude where it actually glows, showing where charged particles from the sun are pouring into the upper atmosphere. This comes from a real forecasting model run by the US space weather agency, NOAA, not a live photograph.

The colored shell above it is the ionosphere: a layer of electrically charged particles high in the atmosphere, brighter where there are more of them. This is the layer that affects people on the ground. A GPS signal passing through a denser ionosphere arrives slightly late, so a receiver calculates the wrong distance and reports an inaccurate position, especially near the equator where this layer is thickest and most turbulent.

Right now, a scale called the Kp index, which runs from 0 to 9 and measures how disturbed Earth's magnetic field is, reads %.0f (%s). The same solar activity that causes the aurora also puffs up the outer atmosphere, adding drag to satellites in low orbit. One event causes all three effects at once: lights in the sky, worse GPS accuracy, and satellites losing altitude faster than expected.""" % [weather.kp_index, weather.storm_label()]
	c.content_scale = 1.45
	c.altitude_exaggeration = 2.0
	# Looking well down onto the pole, where the oval lives. The night side is
	# wherever the sun is not, so the presenter orbits in azimuth to find it --
	# which is itself the point being made.
	c.elevation = 1.15
	c.show_tec = tec_available
	c.show_aurora = true
	c.legend = [
		{"color": Color(0.22, 1.0, 0.55), "label": "Aurora (real-time forecast)"},
		{"color": Color(0.10, 0.55, 0.85), "label": "Ionosphere: fewer electrons"},
		{"color": Color(1.00, 0.72, 0.62), "label": "Ionosphere: more electrons"},
	]
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
		highlighted_indices = catalog.indices_with_intl_prefix(c.highlight_intl_prefix)
	elif not c.highlight_name.is_empty():
		highlighted_indices = catalog.indices_matching_name(c.highlight_name)
	else:
		highlighted_indices = PackedInt32Array()
	field.set_highlight(highlighted_indices)

	# The clock rate is deliberately untouched -- see Chapter's Time group.

	if sensors != null:
		sensors.visible = c.show_sensors
	if tec != null:
		tec.visible = c.show_tec
	if winds != null:
		winds.visible = c.show_winds
	if aurora != null:
		aurora.visible = c.show_aurora
	field.visible = c.show_satellites

	# set_filter and the scale change both move the outermost object, so the
	# derived distance has to be computed after them.
	# Frame on what is actually drawn. With the satellite field hidden, deriving
	# the distance from its extent put the camera 15 m back for content barely
	# larger than the globe, and the Earth came out a few degrees wide.
	var radius_m := rig.content_radius_m()
	if not c.show_satellites:
		radius_m = rig.content_scale

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
