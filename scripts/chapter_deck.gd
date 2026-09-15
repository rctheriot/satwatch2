class_name ChapterDeck
extends Node
## Drives the presentation. Chapters are authored data; this only sequences them.

signal chapter_changed(chapter: Chapter, index: int, total: int)

var chapters: Array[Chapter] = []
var index: int = 0

var rig: RigController
var field: SatelliteField
var catalog: CatalogStore
var clock: SimClock

func _ready() -> void:
	if chapters.is_empty():
		chapters = _default_deck()

## Built in code rather than as .tres so the deck is reviewable in one place and
## survives a resource re-import. Scale/distance pairs here are not free
## parameters -- see the note on chapter 2.
func _default_deck() -> Array[Chapter]:
	var out: Array[Chapter] = []

	var leo := Chapter.new()
	leo.title = "LOW EARTH ORBIT"
	leo.subtitle = "Tracked objects below 2,000 km"
	leo.regimes = ["LEO"]
	leo.center_distance = 3.0
	leo.rig_scale = 0.75
	leo.altitude_exaggeration = 2.5
	out.append(leo)

	# Centre distances below are not free parameters: tests/verify_frames.gd
	# asserts every chapter keeps its outermost visible object at least
	# RigController.MIN_CONTENT_DISTANCE (1.5 m) from the viewer. Pushing a
	# chapter wider without re-running that check will silently be corrected by
	# the runtime clamp, so what reaches the wall is not what was authored.

	# The pull-back. A LEO-tuned scale cannot hold MEO/GEO/HEO: at scale 0.75 the
	# GEO ring has a 4.96 m radius against a 3.0 m centre distance, putting its
	# near side 1.96 m BEHIND the viewer's head, where it is simply culled.
	# Scale and centre distance are therefore per-chapter, and this transition
	# is the reveal -- do not cut it.
	var geo := Chapter.new()
	geo.title = "THE FULL CATALOG"
	geo.subtitle = "LEO shells to the geostationary belt"
	geo.regimes = []
	geo.center_distance = 4.1
	geo.rig_scale = 0.30
	geo.altitude_exaggeration = 1.0
	geo.point_size = 0.0032
	geo.transition_seconds = 5.0
	out.append(geo)

	for r in ["LEO", "MEO", "GEO", "HEO"]:
		var c := Chapter.new()
		c.title = r
		c.subtitle = {"LEO": "Imaging, comms, the crowded shells",
			"MEO": "Navigation constellations",
			"GEO": "Fixed over one longitude",
			"HEO": "Highly elliptical, long dwell at apogee"}[r]
		c.regimes = [r]
		c.center_distance = 4.1
		c.rig_scale = 0.30
		c.altitude_exaggeration = 1.0
		c.point_size = 0.0032
		out.append(c)

	var starlink := Chapter.new()
	starlink.title = "CONSTELLATION"
	starlink.subtitle = "STARLINK against the rest of the LEO population"
	# Scoped to LEO deliberately. Starlink is a LEO constellation, and applying
	# altitude exaggeration to the whole catalog would push the outermost HEO
	# object to ~15 Re -- through the viewer and out the back of the room.
	starlink.regimes = ["LEO"]
	starlink.highlight_name = "STARLINK"
	starlink.center_distance = 3.4
	starlink.rig_scale = 0.45
	starlink.altitude_exaggeration = 2.0
	starlink.point_size = 0.0030
	out.append(starlink)

	return out

func apply(i: int, animate: bool = true) -> void:
	if chapters.is_empty():
		return
	index = posmod(i, chapters.size())
	var c := chapters[index]

	field.altitude_exaggeration = c.altitude_exaggeration
	field.point_size = c.point_size
	field.set_filter(c.regimes)
	if c.highlight_name.is_empty():
		field.set_highlight(PackedInt32Array())
	else:
		field.set_highlight(catalog.indices_matching_name(c.highlight_name))

	clock.rate_index = c.rate_index

	# set_filter changed which objects are active, so the safety clamp's notion
	# of the outermost object changed too. goto() re-clamps against it.
	rig.goto(c.center_distance, c.rig_scale, c.yaw, c.pitch,
		c.transition_seconds if animate else 0.0)

	chapter_changed.emit(c, index, chapters.size())

func next() -> void:
	apply(index + 1)

func prev() -> void:
	apply(index - 1)
