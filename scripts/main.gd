extends Node3D
## Orbital Density Wall -- wiring and per-frame updates.
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
## tools/find_conjunctions.py still produces data/conjunctions.json as a
## standalone analysis product -- the close-approach chapter was cut because the
## events it finds are Starlink-on-Starlink, which tells a viewer little. The
## renderer for it is gone; recover it from git if a more telling event appears.
const AURORA_TEXTURE_PATH := "res://data/aurora.png"

@onready var clock: SimClock = $SimClock
@onready var rig: ContentRig = $EarthRig
@onready var earth: MeshInstance3D = $EarthRig/EarthMesh
@onready var atmosphere: MeshInstance3D = $EarthRig/Atmosphere
@onready var field: SatelliteField = $EarthRig/SatelliteField
@onready var hud: Hud = $UIRig
@onready var selection: SelectionController = $Selection
@onready var deck: ChapterDeck = $ChapterDeck
@onready var camera: CameraDirector = $CameraDirector
@onready var sensors: SensorNetwork = $EarthRig/EarthMesh/SensorNetwork
@onready var aurora: MeshInstance3D = $EarthRig/EarthMesh/Aurora
@onready var sun_light: DirectionalLight3D = $Sun
@onready var wall: Node = $StereoWallDisplay

var store := EphemerisStore.new()
var catalog := CatalogStore.new()
var weather := SpaceWeatherStore.new()

var _earth_material: ShaderMaterial
var _atmo_material: ShaderMaterial
var _sat_material: ShaderMaterial
var _sky_material: ShaderMaterial
var _aurora_material: ShaderMaterial
var _ready_ok := false

func _ready() -> void:
	InputActions.register()
	_release_mouse()
	_apply_stereo_override()

	_earth_material = earth.material_override as ShaderMaterial
	_atmo_material = atmosphere.material_override as ShaderMaterial
	_sat_material = field.material_override as ShaderMaterial
	_aurora_material = aurora.material_override as ShaderMaterial
	_load_aurora()
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

	camera.wall = wall
	camera.target = rig.global_position
	camera.set_mode(CameraDirector.Mode.ORBIT)

	sensors.field = field
	sensors.store = store
	sensors.build()
	sensors.visible = false

	hud.build(catalog, weather)

	selection.field = field
	selection.rig = rig
	selection.catalog = catalog
	selection.clock = clock
	selection.camera = camera
	selection.selection_changed.connect(_on_selection_changed)

	deck.camera = camera
	deck.sensors = sensors
	deck.rig = rig
	deck.field = field
	deck.catalog = catalog
	deck.clock = clock
	deck.chapter_changed.connect(_on_chapter_changed)

	if weather.loaded:
		deck.add_space_weather_chapter(weather)

	_ready_ok = true
	deck.apply(0, false)
	print("Orbital Density Wall ready: %d objects." % store.n_objects)

	var bench := Benchmark.from_command_line()
	if bench != null:
		bench.name = "Benchmark"
		bench.field = field
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
	# Textures are not committed (large NASA Blue Marble downloads). Fall back to
	# a flat globe rather than failing, so geometry, clock and field stay
	# workable before the art lands.
	for pair in [["day_texture", "res://assets/earth_day.jpg"],
			["night_texture", "res://assets/earth_night.jpg"],
			["ocean_mask", "res://assets/earth_ocean.png"]]:
		if ResourceLoader.exists(pair[1]):
			_earth_material.set_shader_parameter(pair[0], load(pair[1]))
		elif pair[0] == "day_texture":
			push_warning("Missing %s -- see assets/README.md. Using a flat globe."
				% pair[1])

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


func _on_chapter_changed(c: Chapter, idx: int, total: int) -> void:
	hud.set_chapter(c, idx, total)
	hud.set_exaggeration(c.altitude_exaggeration)
	selection.clear()

func _on_selection_changed(index: int) -> void:
	hud.set_selection(null if index < 0 else catalog.objects[index])

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
	selection.attach_to_head(head)


func _process(_delta: float) -> void:
	if not _ready_ok:
		return
	_attach_to_head()
	var t := clock.now_unix

	field.update_positions(t)
	# The Earth spins under the satellites rather than the other way round --
	# the field stays in TEME, which is what SGP4 actually produces.
	earth.rotation.y = clock.gmst()

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
	# Size target is honoured at the content centre, so it tracks the camera
	# rather than the content scale.
	_sat_material.set_shader_parameter("highlight_color", field.highlight_color)
	_sat_material.set_shader_parameter("reference_depth",
		maxf(camera.distance_to(rig.global_position), 0.2))
	sun_light.look_at_from_position(sun * 50.0, Vector3.ZERO, Vector3.UP)
	_sky_material.set_shader_parameter("frame_inverse", Basis(frame).inverse())
	if aurora.visible:
		_aurora_material.set_shader_parameter("sun_direction", sun)
		# Match the satellite field so the two layers stay consistent: if orbital
		# altitude is exaggerated, emission altitude has to be too.
		_aurora_material.set_shader_parameter("altitude_exaggeration",
			field.altitude_exaggeration)

	hud.set_comfort(camera.eye_position().distance_to(rig.global_position)
		- rig.content_radius_m())

	if sensors.visible:
		sensors.update_visibility(t, clock.gmst(), clock.sun_direction())
		hud.set_site_rows(sensors.ranked_sites(8), sensors.total_visible)
		field.set_highlight(sensors.visible_indices())

	hud.set_time(clock.utc_string(), clock.rate_label())

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

func _show_missing_data_notice() -> void:
	# Deliberately a 3D label, not a CanvasLayer: on the wall a CanvasLayer is
	# drawn into one eye's half of the composited window.
	var l := Label3D.new()
	l.text = "No ephemeris.\n\nRun:  tools/fetch_gp.py  then  tools/build_ephemeris.py"
	l.font_size = 96
	l.position = Vector3(0.0, 1.64, -2.4)
	l.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	add_child(l)
