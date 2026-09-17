extends Node3D
## SatWatch 2 -- wiring and per-frame updates.
##
## The scene graph lives in main.tscn and is editable in the Godot editor:
## EarthRig, EarthMesh, Atmosphere, SatelliteField, UIRig, Selection, SimClock
## and ChapterDeck are all real nodes with their materials and exported
## properties set there. This script does not build them.
##
## Two things are still created at runtime, because they are data-driven and
## authoring them would just mean they drift from the builder output:
##   - the MultiMesh inside SatelliteField (instance count = catalog size)
##   - the SubViewport panels inside UIRig (content depends on the catalog)

const EPHEMERIS_PATH := "res://data/ephemeris.bin"
const CATALOG_PATH := "res://data/catalog.json"
const SPACE_WEATHER_PATH := "res://data/space_weather.json"
const TEC_PATH := "res://data/tec.json"
const TEC_TEXTURE_PATH := "res://data/tec.png"
const WINDS_PATH := "res://data/winds.json"
## tools/find_conjunctions.py is a standalone analysis utility and is not wired
## into the demo -- see docs/DATA.md.
const AURORA_TEXTURE_PATH := "res://data/aurora.png"
const ORBIT_PATHS_PATH := "res://data/orbit_paths.bin"
const ISS_MODEL_PATH := "res://assets/ISS/ISS_stationary.glb"
## Real model is ~112 m across (solar array tip to tip). Scaled down to
## roughly match the on-screen size other chapters display content at,
## rather than the true ~6,378 km : 1 world-unit ratio the rest of the demo
## uses -- there is no Earth in this chapter for that ratio to mean anything
## relative to.
const ISS_MODEL_SCALE := 0.03
## Clouds slip this fraction of the Earth's own rotation per sidereal day --
## real jet-stream-level winds are a small delta on top of bulk co-rotation,
## not an independent speed. Purely a decorative constant, tuned by eye.
const CLOUD_DRIFT_FRACTION := 0.05

@onready var clock: SimClock = $SimClock
@onready var rig: ContentRig = $EarthRig
@onready var earth: MeshInstance3D = $EarthRig/EarthMesh
@onready var atmosphere: MeshInstance3D = $EarthRig/Atmosphere
@onready var field: SatelliteField = $EarthRig/SatelliteField
@onready var orbit_trails: OrbitTrails = $EarthRig/OrbitTrails
@onready var iss_rig: Node3D = $ISSRig
@onready var hud: Hud = $UIRig
@onready var deck: ChapterDeck = $ChapterDeck
@onready var camera: CameraDirector = $CameraDirector
@onready var sensors: SensorNetwork = $EarthRig/EarthMesh/SensorNetwork
@onready var tec: MeshInstance3D = $EarthRig/EarthMesh/TecShell
@onready var winds: WindLayer = $EarthRig/EarthMesh/WindLayer
@onready var aurora: MeshInstance3D = $EarthRig/EarthMesh/Aurora
@onready var clouds: MeshInstance3D = $EarthRig/EarthMesh/Clouds
@onready var sun_light: DirectionalLight3D = $Sun
@onready var music: AudioStreamPlayer = $Music
@onready var wall: Node = $StereoWallDisplay

var store := EphemerisStore.new()
var catalog := CatalogStore.new()
var weather := SpaceWeatherStore.new()
var tec_store := TecStore.new()
var orbit_path_store := OrbitPathStore.new()
## Global and persistent across chapters -- see OrbitTrails' class comment for
## why this is not a per-chapter Chapter field.
var _orbit_trails_on := false
var _current_chapter: Chapter = null
## See _apply_forced_orbit_trails(). _orbit_trails_forced is true while the
## CURRENT chapter is the one that borrowed the toggle, so leaving it (to
## any chapter without force_orbit_trails) is what triggers the restore.
var _orbit_trails_saved_state := false
var _orbit_trails_forced := false

var _earth_material: ShaderMaterial
var _atmo_material: ShaderMaterial
var _sat_material: ShaderMaterial
var _sky_material: ShaderMaterial
var _aurora_material: ShaderMaterial
var _clouds_material: ShaderMaterial
var _tec_material: ShaderMaterial
var _wind_material: ShaderMaterial
var _ready_ok := false

func _ready() -> void:
	InputActions.register()
	_release_mouse()
	_apply_stereo_override()

	_earth_material = earth.material_override as ShaderMaterial
	_atmo_material = atmosphere.material_override as ShaderMaterial
	_sat_material = field.material_override as ShaderMaterial
	_aurora_material = aurora.material_override as ShaderMaterial
	_tec_material = tec.material_override as ShaderMaterial
	_clouds_material = clouds.material_override as ShaderMaterial
	_load_aurora()
	_load_tec()
	_load_music()
	var env: Environment = $WorldEnvironment.environment
	_sky_material = env.sky.sky_material as ShaderMaterial
	_apply_earth_textures()

	if store.load_from(EPHEMERIS_PATH) != OK or catalog.load_from(CATALOG_PATH) != OK:
		_show_missing_data_notice()
		return
	if store.n_objects != catalog.objects.size():
		push_error("Ephemeris has %d objects but catalog has %d. They are written "
			% [store.n_objects, catalog.objects.size()]
			+ "together by build_ephemeris.py -- rebuild both.")
		return

	clock.configure(store.epoch_unix, store.span_seconds())

	field.setup(store, catalog.objects)
	rig.field = field

	# Optional layer: orbit trails just stay unavailable without it -- the
	# toggle does nothing rather than erroring. Index order must match
	# EphemerisStore/CatalogStore exactly; see OrbitPathStore's class comment.
	if orbit_path_store.load_from(ORBIT_PATHS_PATH) == OK:
		orbit_trails.build(orbit_path_store)
	else:
		print("No orbit paths -- run tools/build_ephemeris.py for the trails toggle.")

	camera.wall = wall
	camera.target = rig.global_position
	camera.set_mode(CameraDirector.Mode.ORBIT)

	sensors.field = field
	sensors.store = store
	sensors.build()
	sensors.visible = false

	hud.build(catalog)

	deck.camera = camera
	deck.sensors = sensors
	deck.tec = tec
	deck.winds = winds
	deck.aurora = aurora
	deck.earth = earth
	deck.atmosphere = atmosphere
	deck.iss = iss_rig
	deck.rig = rig
	deck.field = field
	deck.catalog = catalog
	deck.refresh_catalog_text()
	deck.clock = clock
	deck.chapter_changed.connect(_on_chapter_changed)

	# Optional layers each add their own chapter only if their data is present.
	# A chapter that cannot draw its subject is worse than one that is absent:
	# on a wall, an empty globe reads as the demo being broken.
	if winds.load_from(WINDS_PATH):
		deck.add_wind_chapter(winds)
		# Colour is speed, so full scale is set from this field's own peak --
		# a fixed constant would wash out a calm day and clip a stormy one.
		_wind_material = winds.get_node("WindTrails").material_override
	else:
		winds.visible = false
		print("No wind field -- run tools/fetch_winds.py for the jet stream "
			+ "chapter.")

	if weather.loaded:
		deck.add_space_weather_chapter(weather, tec_store.loaded)

	_load_iss()

	_ready_ok = true
	deck.apply(0, false)
	print("SatWatch 2 ready: %d objects." % store.n_objects)

	var bench := Benchmark.from_command_line()
	if bench != null:
		bench.name = "Benchmark"
		bench.field = field
		if bench.chapter >= 0:
			deck.apply(bench.chapter, false)
		add_child(bench)

	var capture := FrameCapture.from_command_line()
	if capture != null:
		if capture.chapter >= 0:
			deck.apply(capture.chapter, false)
		capture.run(get_tree())

## Switch the wall addon into stereo output from the command line:
##   Godot --path . -- --stereo [width height]
##
## Done at runtime rather than with a duplicate scene. A second .tscn would have
## to mirror the whole node tree and would silently rot the moment main.tscn
## changed -- which is exactly what happened to the earlier stereo_check.tscn.
## The addon's edit_mode setter calls _rebuild(), so flipping it here works, as
## long as the resolution is set first: _rebuild -> _setup_production_window
## reads those values to size the borderless window.
func _apply_stereo_override() -> void:
	var args := OS.get_cmdline_user_args()
	var i := args.find("--stereo")
	if i < 0:
		return
	if i + 2 < args.size() and args[i + 1].is_valid_int():
		wall.resolution_width = int(args[i + 1])
		wall.resolution_height = int(args[i + 2])
	if args.has("--swap-eyes"):
		# Negative control for tests/verify_stereo.gd.
		wall.swap_eyes = true
	wall.edit_mode = false

## StereoWallDisplay captures the mouse in its _initialize() so it can drive
## mouse-look. We zeroed look_sensitivity, so the capture only hides the cursor
## and leaves no way to see where a click will land. Child _ready() runs before
## parent _ready(), so releasing it here reliably wins.
func _release_mouse() -> void:
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE

func _apply_earth_textures() -> void:
	# NASA Blue Marble/Black Marble textures, committed under assets/ so a
	# clone runs with no setup. Still loaded defensively: without day_texture
	# the globe falls back to flat shading rather than failing outright.
	for pair in [["day_texture", "res://assets/earth_day.jpg"],
			["night_texture", "res://assets/earth_night.jpg"],
			["ocean_mask", "res://assets/earth_ocean.png"]]:
		if ResourceLoader.exists(pair[1]):
			_earth_material.set_shader_parameter(pair[0], load(pair[1]))
		elif pair[0] == "day_texture":
			push_warning("Missing %s -- see assets/README.md. Using a flat globe."
				% pair[1])
	if ResourceLoader.exists("res://assets/earth_clouds.png"):
		_clouds_material.set_shader_parameter("cloud_texture",
			load("res://assets/earth_clouds.png"))
	else:
		clouds.visible = false

## Optional layer: without the texture the shell simply draws nothing, since
## the shader discards at zero probability.
func _load_aurora() -> void:
	if weather.load_from(SPACE_WEATHER_PATH) != OK \
			or not ResourceLoader.exists(AURORA_TEXTURE_PATH):
		aurora.visible = false
		print("No space weather -- run tools/fetch_space_weather.py for the "
			+ "aurora layer.")
		return
	_aurora_material.set_shader_parameter("aurora_texture",
		load(AURORA_TEXTURE_PATH))
	print("Space weather: Kp %.0f (%s), aurora peak %d%%, forecast %s" % [
		weather.kp_index, weather.storm_label(), weather.aurora_peak_probability,
		weather.aurora_forecast_utc])


const MUSIC_PATH := "res://assets/background_music.mp3"

## Optional: silent without it. Loops for the length of the demo rather than
## once, since a wall running unattended between visitors should not go quiet
## partway through.
func _load_music() -> void:
	if not ResourceLoader.exists(MUSIC_PATH):
		return
	var stream: AudioStream = load(MUSIC_PATH)
	if stream is AudioStreamMP3:
		stream.loop = true
	music.stream = stream
	music.play()

## Optional: adds its own chapter only if the model is present, same pattern
## as every other optional layer. iss_rig stays an empty placeholder without
## it, and the chapter that would show it is simply never appended.
func _load_iss() -> void:
	if not ResourceLoader.exists(ISS_MODEL_PATH):
		print("No ISS model -- drop ISS_stationary.glb in assets/ISS/ for "
			+ "the ISS chapter.")
		return
	var packed: PackedScene = load(ISS_MODEL_PATH)
	var model := packed.instantiate()
	model.scale = Vector3.ONE * ISS_MODEL_SCALE
	iss_rig.add_child(model)
	deck.add_iss_chapter()

## Optional layer: without the texture the shell draws nothing.
func _load_tec() -> void:
	if not tec_store.load_from(TEC_PATH) \
			or not ResourceLoader.exists(TEC_TEXTURE_PATH):
		tec.visible = false
		print("No ionosphere data -- run tools/fetch_tec.py for the TEC layer.")
		return
	_tec_material.set_shader_parameter("tec_texture", load(TEC_TEXTURE_PATH))
	tec.visible = false            # the deck turns it on for its chapter
	print("Ionosphere: %.0f-%.0f TECU (mean %.0f), observed %s" % [
		tec_store.min_tecu, tec_store.max_tecu, tec_store.mean_tecu,
		tec_store.observation_utc])


func _on_chapter_changed(c: Chapter, idx: int, total: int) -> void:
	hud.set_chapter(c, idx, total)
	_current_chapter = c
	_apply_forced_orbit_trails(c)
	_refresh_orbit_trails()

## A chapter with force_orbit_trails (GPS) borrows the global toggle rather
## than owning its own copy of it: entering saves whatever the viewer had it
## set to and forces it on, leaving restores exactly that. If the viewer had
## already turned trails on before arriving, this is a no-op both ways --
## "restore" means back to what they had, not necessarily off.
func _apply_forced_orbit_trails(c: Chapter) -> void:
	if c.force_orbit_trails and not _orbit_trails_forced:
		_orbit_trails_saved_state = _orbit_trails_on
		_orbit_trails_on = true
		_orbit_trails_forced = true
	elif not c.force_orbit_trails and _orbit_trails_forced:
		_orbit_trails_on = _orbit_trails_saved_state
		_orbit_trails_forced = false

## Rebuilds the drawn trail set. A chapter that highlights a specific subset
## (a debris cloud, one constellation) trails THAT subset rather than its
## whole filtered population -- Starlink alone is a legible handful of
## ellipses; Starlink plus the other ~6,400 objects sharing its regime filter
## is the cap kicking in for no reason, since the highlighted objects were
## the only ones worth tracing anyway. Chapters with nothing highlighted
## (HEO, MEO, GEO) fall back to the whole filtered set, same as before.
## Cheap to call on every chapter change since it is the only time it runs --
## see OrbitTrails.show_paths() for the per-frame cost this avoids.
##
## The toggle is global and persists across chapters on purpose (see
## OrbitTrails' class comment), but a chapter that hides the satellite field
## entirely -- the jet stream -- has nothing for a SATELLITE orbit path to
## mean anything relative to. Rather than drawing a ghostly sphere of paths
## behind wind data, that chapter suppresses the toggle's effect without
## clearing it, so it's back the moment the viewer returns to a chapter it
## applies to.
func _refresh_orbit_trails() -> void:
	if _orbit_trails_on and _current_chapter != null and _current_chapter.show_satellites:
		var highlighted := not deck.highlighted_indices.is_empty()
		var indices := deck.highlighted_indices if highlighted else field.active
		# Tint to match the dots being traced -- "just the red paths" should
		# actually be red, not the neutral default used for an un-highlighted
		# population. Same low alpha either way; a chapter's highlight_color
		# is full-alpha for the DOTS, which would oversaturate at trail scale
		# once hundreds of paths overlap.
		var color := orbit_trails.DEFAULT_COLOR
		if highlighted and deck.index < deck.chapters.size():
			var hc := deck.chapters[deck.index].highlight_color
			color = Color(hc.r, hc.g, hc.b, orbit_trails.DEFAULT_COLOR.a)
		orbit_trails.show_paths(indices, field.altitude_exaggeration, color)
	else:
		orbit_trails.visible = false

## UI that must stay fixed on the physical wall is PARENTED to the camera pivot
## rather than having its transform copied each frame.
##
## Copying it looked right but drifted: Godot calls _process parent-first, so
## this node read the head pose before CameraDirector had updated it, leaving the
## panels one frame stale. Static they looked fine; while orbiting or dollying
## they swam against the wall. Parenting makes the transform inherited, so no
## processing order can desynchronise it.
##
## Re-checked each frame because the addon frees and rebuilds the pivot whenever
## edit_mode changes, which the --stereo flag does at startup.
func _attach_to_head() -> void:
	var head := camera.head_node()
	if head == null:
		return
	if hud.get_parent() != head:
		hud.get_parent().remove_child(hud)
		head.add_child(hud)
	hud.transform = Transform3D.IDENTITY


func _process(_delta: float) -> void:
	if not _ready_ok:
		return
	_attach_to_head()
	var t := clock.now_unix

	field.update_positions(t)
	# The Earth spins under the satellites rather than the other way round --
	# the field stays in TEME, which is what SGP4 actually produces.
	var gmst := clock.gmst()
	earth.rotation.y = gmst
	# Clouds are a child of EarthMesh, so they already co-rotate with the
	# ground perfectly. This adds a small SLIP on top, driven by the same
	# clock as the rotation itself so it stays proportional at any sim rate --
	# see the uniform's comment in clouds.gdshader for why that matters.
	_clouds_material.set_shader_parameter("drift_angle", gmst * CLOUD_DRIFT_FRACTION)

	# The wall is fixed, so "orbiting the camera" has to be done by rotating the
	# content. That is only equivalent to a real orbit if EVERYTHING in the
	# inertial frame turns together -- including the sun and the stars.
	#
	# sun_direction() is an inertial vector, and the Earth shader dots it against
	# a WORLD-space normal that already carries the rig's rotation. Passing the
	# raw vector therefore left the sun behind in world space, so dragging the
	# globe slid the terminator across the continents and appeared to change the
	# time of day. Rotating it into world space with the rig fixes that: drag now
	# reads as moving around a fixed, correctly-lit Earth.
	# The content sits at the origin with an identity basis, so inertial vectors
	# need no correction -- the camera moves instead of the world. The rig basis
	# is still applied rather than assumed, so this stays correct if the content
	# is ever rotated again.
	var frame := rig.global_transform.basis.orthonormalized()
	var sun := frame * clock.sun_direction()
	_earth_material.set_shader_parameter("sun_direction", sun)
	_atmo_material.set_shader_parameter("sun_direction", sun)
	_clouds_material.set_shader_parameter("sun_direction", sun)
	# Size target is honoured at the content centre, so it tracks the camera
	# rather than the content scale.
	_sat_material.set_shader_parameter("highlight_color", field.highlight_color)
	_sat_material.set_shader_parameter("base_color_override", field.base_color)
	_sat_material.set_shader_parameter("reference_depth",
		maxf(camera.distance_to(rig.global_position), 0.2))
	# The ISS chapter has its own dedicated key/fill lights (children of
	# ISSRig, gated by its visibility -- see main.tscn) rather than this
	# Earth-relative sun direction, which has no real relationship to a
	# free-standing model with no orbital position of its own. Left on, it
	# was a second, uncontrolled light source washing out the station's
	# shadow side from whatever angle the inertial sun happened to be at.
	var showing_iss := _current_chapter != null and _current_chapter.show_iss
	sun_light.visible = not showing_iss
	if not showing_iss:
		sun_light.look_at_from_position(sun * 50.0, Vector3.ZERO, Vector3.UP)
	_sky_material.set_shader_parameter("frame_inverse", Basis(frame).inverse())
	if aurora.visible:
		_aurora_material.set_shader_parameter("sun_direction", sun)
		# Match the satellite field so the two layers stay consistent: if orbital
		# altitude is exaggerated, emission altitude has to be too.
		_aurora_material.set_shader_parameter("altitude_exaggeration",
			field.altitude_exaggeration)

	if winds.visible:
		winds.update_positions(t)
		# Colour is speed, and a segment's length IS speed x trail_seconds, so
		# full scale is that distance for the field's own peak -- scaled by the
		# rig, since the shader measures the segment in world units.
		_wind_material.set_shader_parameter("speed_full_scale",
			WindLayer.SPEED_FULL_SCALE_MS * winds.trail_seconds
			/ 6378137.0 * rig.content_scale)
	if tec.visible:
		_tec_material.set_shader_parameter("sun_direction", sun)
		_tec_material.set_shader_parameter("altitude_exaggeration",
			field.altitude_exaggeration)

	if sensors.visible:
		sensors.update_visibility(t, clock.gmst(), clock.sun_direction())
		# Only rewrite the highlight when a full pass has published new results.
		# Doing it every frame rebuilt a 16k index array and rewrote custom data
		# for every instance, to produce an identical answer most of the time.
		if sensors.consume_updated():
			hud.set_site_rows(sensors.ranked_sites(7), sensors.total_visible)
			field.set_highlight(sensors.visible_indices())

	hud.set_time(clock.utc_string(), clock.rate_label(), clock.loop_progress(),
		clock.span_seconds / 3600.0)

func _unhandled_input(event: InputEvent) -> void:
	if not _ready_ok:
		return
	if event.is_action_pressed("chapter_next"):
		deck.next()
	elif event.is_action_pressed("chapter_prev"):
		deck.prev()
	elif event.is_action_pressed("time_pause"):
		clock.paused = not clock.paused
	elif event.is_action_pressed("time_faster"):
		clock.step_rate(1)
	elif event.is_action_pressed("time_slower"):
		clock.step_rate(-1)
	elif event.is_action_pressed("toggle_fly"):
		camera.toggle_mode()
	elif event.is_action_pressed("toggle_controls_help"):
		hud.toggle_controls_scheme()
	elif event.is_action_pressed("toggle_music"):
		music.stream_paused = not music.stream_paused
	elif event.is_action_pressed("toggle_orbit_trails"):
		_orbit_trails_on = not _orbit_trails_on
		_refresh_orbit_trails()
	elif event.is_action_pressed("toggle_menus"):
		hud.toggle_menus()

func _show_missing_data_notice() -> void:
	# Deliberately a 3D label, not a CanvasLayer: on the wall a CanvasLayer is
	# drawn into one eye's half of the composited window.
	var l := Label3D.new()
	l.text = "No ephemeris.\n\nRun:  tools/fetch_gp.py  then  tools/build_ephemeris.py"
	l.font_size = 96
	l.position = Vector3(0.0, 1.64, -2.4)
	l.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	add_child(l)
