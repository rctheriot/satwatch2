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
var rig: ContentRig
var field: SatelliteField
var catalog: CatalogStore
var clock: SimClock

func _ready() -> void:
	if chapters.is_empty():
		chapters = _default_deck()

## Built in code rather than as .tres so the deck is reviewable in one place and
## survives a resource re-import.
func _default_deck() -> Array[Chapter]:
	var out: Array[Chapter] = []

	var leo := Chapter.new()
	leo.title = "LOW EARTH ORBIT"
	leo.subtitle = "Tracked objects below 2,000 km"
	leo.regimes = ["LEO"]
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
	full.content_scale = 0.40
	full.altitude_exaggeration = 1.0
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
	starlink.highlight_name = "STARLINK"
	starlink.content_scale = 1.2
	starlink.altitude_exaggeration = 2.0
	out.append(starlink)

	return out

## Distance that keeps the outermost visible object PRESET_CLEARANCE beyond the
## fusion floor. Chapters with camera_distance = 0 use this.
static func preset_distance(content_radius_m: float) -> float:
	return CameraDirector.MIN_CONTENT_DISTANCE + PRESET_CLEARANCE + content_radius_m

func apply(i: int, animate: bool = true) -> void:
	if chapters.is_empty():
		return
	index = posmod(i, chapters.size())
	var c := chapters[index]

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
