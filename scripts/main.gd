extends Node3D
## Orbital Density Wall -- assembly and per-frame wiring.
##
## The scene is built in code rather than authored as a .tscn because almost
## every node here is data-driven (instance counts, panel sizes, chapter presets)
## and a hand-edited .tscn would drift from the builder output.

const EPHEMERIS_PATH := "res://data/ephemeris.bin"
const CATALOG_PATH := "res://data/catalog.json"

## Viewer head position. Must match StereoWallDisplay: the addon parents its
## camera pivot at y = 1.64 on the player body at start_position.
const HEAD := Vector3(0.0, 1.64, 0.0)

var store := EphemerisStore.new()
var catalog := CatalogStore.new()

var clock: SimClock
var rig: RigController
var field: SatelliteField
var earth: MeshInstance3D
var atmosphere: MeshInstance3D
var hud: Hud
var deck: ChapterDeck
var selection: SelectionController

var _earth_material: ShaderMaterial
var _atmo_material: ShaderMaterial
var _sat_material: ShaderMaterial
var _sun_light: DirectionalLight3D

func _ready() -> void:
	InputActions.register()

	if store.load_from(EPHEMERIS_PATH) != OK or catalog.load_from(CATALOG_PATH) != OK:
		_show_missing_data_notice()
		return
	if store.n_objects != catalog.objects.size():
		push_error("Ephemeris has %d objects but catalog has %d. They are written "
			% [store.n_objects, catalog.objects.size()]
			+ "together by build_ephemeris.py -- rebuild both.")
		return

	_build_environment()
	_build_clock()
	_build_rig()
	_build_earth()
	_build_field()
	_build_hud()
	_build_selection()
	_build_deck()

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

func _build_environment() -> void:
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ShaderMaterial.new()
	sky_mat.shader = load("res://shaders/starfield.gdshader")
	sky.sky_material = sky_mat
	env.sky = sky
	# Almost no ambient: the globe should be lit by the sun term in its own
	# shader, so the terminator stays the sharp feature it is in reality.
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.06, 0.08, 0.12)
	env.ambient_light_energy = 0.18
	# Glow is deliberately off. Additive satellite billboards through a bloom
	# pass at 15.5 Mpix is the single most expensive thing this scene could do,
	# and in stereo the bloom halo has no disparity, so it actively fights the
	# depth cue of the point it surrounds.
	env.glow_enabled = false
	env.tonemap_mode = Environment.TONE_MAPPER_ACES

	var we := WorldEnvironment.new()
	we.name = "WorldEnvironment"
	we.environment = env
	add_child(we)

	# One directional light for the globe's specular; the day/night mix itself
	# is computed from sun_direction in earth.gdshader.
	var sun := DirectionalLight3D.new()
	sun.name = "Sun"
	sun.light_energy = 0.9
	sun.shadow_enabled = false
	add_child(sun)
	_sun_light = sun


func _build_clock() -> void:
	clock = SimClock.new()
	clock.name = "SimClock"
	add_child(clock)
	clock.configure(store.epoch_unix, store.span_seconds())

func _build_rig() -> void:
	rig = RigController.new()
	rig.name = "EarthRig"
	rig.head_position = HEAD
	add_child(rig)

func _build_earth() -> void:
	var sphere := SphereMesh.new()
	sphere.radius = 1.0
	sphere.height = 2.0
	# Dense enough that the limb stays smooth: a faceted silhouette is far more
	# obvious in stereo than it is flat, because the two eyes see different facets.
	sphere.radial_segments = 128
	sphere.rings = 64

	earth = MeshInstance3D.new()
	earth.name = "EarthMesh"
	earth.mesh = sphere
	_earth_material = ShaderMaterial.new()
	_earth_material.shader = load("res://shaders/earth.gdshader")
	_apply_earth_textures()
	earth.material_override = _earth_material
	rig.add_child(earth)

	var shell := SphereMesh.new()
	shell.radius = 1.025
	shell.height = 2.05
	shell.radial_segments = 96
	shell.rings = 48
	atmosphere = MeshInstance3D.new()
	atmosphere.name = "Atmosphere"
	atmosphere.mesh = shell
	_atmo_material = ShaderMaterial.new()
	_atmo_material.shader = load("res://shaders/atmosphere.gdshader")
	atmosphere.material_override = _atmo_material
	rig.add_child(atmosphere)

func _apply_earth_textures() -> void:
	# Textures are not committed (they are large NASA Blue Marble downloads).
	# Fall back to a flat globe rather than failing, so the geometry, clock and
	# satellite field can be worked on before the art lands.
	for pair in [["day_texture", "res://assets/earth_day.jpg"],
			["night_texture", "res://assets/earth_night.jpg"],
			["ocean_mask", "res://assets/earth_ocean.png"]]:
		if ResourceLoader.exists(pair[1]):
			_earth_material.set_shader_parameter(pair[0], load(pair[1]))
		elif pair[0] == "day_texture":
			push_warning("Missing %s -- see assets/README.md. Using a flat globe."
				% pair[1])

func _build_field() -> void:
	field = SatelliteField.new()
	field.name = "SatelliteField"
	rig.add_child(field)
	field.setup(store, catalog.objects)
	_sat_material = ShaderMaterial.new()
	_sat_material.shader = load("res://shaders/satellites.gdshader")
	field.material_override = _sat_material
	rig.field = field

func _build_hud() -> void:
	hud = Hud.new()
	hud.name = "UIRig"
	add_child(hud)
	hud.build(catalog)

func _build_selection() -> void:
	selection = SelectionController.new()
	selection.name = "Selection"
	selection.field = field
	selection.rig = rig
	selection.catalog = catalog
	selection.head_position = HEAD
	add_child(selection)
	selection.selection_changed.connect(_on_selection_changed)

func _build_deck() -> void:
	deck = ChapterDeck.new()
	deck.name = "ChapterDeck"
	deck.rig = rig
	deck.field = field
	deck.catalog = catalog
	deck.clock = clock
	add_child(deck)
	deck.chapter_changed.connect(_on_chapter_changed)

func _on_chapter_changed(c: Chapter, idx: int, total: int) -> void:
	hud.set_chapter(c, idx, total)
	hud.set_exaggeration(c.altitude_exaggeration)
	selection.clear()

func _on_selection_changed(index: int) -> void:
	hud.set_selection(null if index < 0 else catalog.objects[index])

func _process(_delta: float) -> void:
	if not store.is_loaded():
		return
	var t := clock.now_unix

	field.update_positions(t)
	# Earth spins under the satellites rather than the other way round -- the
	# field stays in TEME, which is what SGP4 actually produces.
	earth.rotation.y = clock.gmst()

	var sun := clock.sun_direction()
	_earth_material.set_shader_parameter("sun_direction", sun)
	_atmo_material.set_shader_parameter("sun_direction", sun)
	# The billboard shader sizes points in world units; the rig's scale would
	# otherwise shrink them to nothing as we pull back to the GEO view.
	_sat_material.set_shader_parameter("rig_scale", rig.rig_scale)
	# Point the light down-sun so the globe's ocean specular agrees with the
	# terminator the Earth shader draws from the same vector.
	_sun_light.look_at_from_position(sun * 50.0, Vector3.ZERO, Vector3.UP)

	hud.set_time(clock.utc_string(), clock.rate_label())

func _unhandled_input(event: InputEvent) -> void:
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

func _show_missing_data_notice() -> void:
	# Deliberately a 3D label, not a CanvasLayer: on the wall a CanvasLayer
	# would be drawn into one eye's half of the composited window.
	var l := Label3D.new()
	l.text = "No ephemeris.\n\nRun:  tools/fetch_gp.py  then  tools/build_ephemeris.py"
	l.font_size = 96
	l.position = HEAD + Vector3(0.0, 0.0, -2.4)
	l.billboard = BaseMaterial3D.BILLBOARD_DISABLED
	add_child(l)
