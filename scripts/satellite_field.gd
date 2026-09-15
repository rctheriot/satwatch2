class_name SatelliteField
extends MultiMeshInstance3D
## Renders the tracked-object catalog as billboarded points.
##
## Phase A: CPU interpolates both bracketing ephemeris slabs and rewrites the
## MultiMesh translation components each frame. Only translations move -- the
## basis stays identity (the shader billboards) and custom data is written once
## at build time. If this stops holding frame rate at full catalog size, the
## Phase B swap is to move interpolation into a vertex shader sampling a
## Texture2DArray; the EphemerisStore data path does not change.

## MultiMesh TRANSFORM_3D is 12 floats; use_custom_data adds 4. use_colors stays
## off -- regime is encoded in custom data and resolved to colour in the shader.
const STRIDE := 16
const TRANSLATION_OFFSETS := [3, 7, 11]

const REGIME_IDS := {"LEO": 0.0, "MEO": 1.0, "GEO": 2.0, "HEO": 3.0}

## Per-regime size multiplier. Crowding is wildly uneven -- 20,866 LEO objects
## against 1,231 GEO and 352 MEO -- so one global point size cannot serve both:
## the size that keeps the sparse GEO belt readable turns LEO into a solid
## additive disc that washes the globe white. Shrink the crowded bucket instead
## of dimming everything.
const REGIME_SIZE := {"LEO": 0.60, "MEO": 1.45, "GEO": 1.45, "HEO": 1.30}

## Dimensionless multiplier on the shader's screen-space target size. It used
## to be a world size, which made it interact with the framing; now a chapter
## asking for 0.8 gets points 80% the size in every chapter.
@export var point_size: float = 1.0
@export_range(1.0, 10.0) var altitude_exaggeration: float = 3.0:
	set(v):
		altitude_exaggeration = v
		_radius_dirty = true

var store: EphemerisStore
var catalog: Array = []
var active: PackedInt32Array = PackedInt32Array()   ## Catalog indices currently shown.

var _buffer: PackedFloat32Array
var _highlight: PackedFloat32Array                  ## Per-catalog-object brightness.

## Microseconds spent in the last update_positions(). Read by Benchmark, which
## must NOT call update_positions() itself to time it -- doing that doubles the
## per-frame work and inflates the very number it is trying to measure.
var last_update_usec: int = 0

## Applied to highlighted objects; set per chapter. Pushed to the shader by
## main.gd, since the material is shared.
var highlight_color: Color = Color(1.0, 0.28, 0.24)
## Alpha 0 means un-highlighted objects keep their regime colour.
var base_color: Color = Color(0, 0, 0, 0)
var dim_others: float = 0.28

## Cached outermost exaggerated radius, in Earth radii. ContentRig needs this
## every frame for the stereo comfort clamp, but it only changes when the filter
## or the exaggeration changes -- recomputing it per frame meant 20k dictionary
## lookups every frame at the full-catalog chapter, for an answer that was
## already known.
var _max_radius: float = 1.0
var _radius_dirty: bool = true

func setup(p_store: EphemerisStore, p_catalog: Array) -> void:
	store = p_store
	catalog = p_catalog
	_highlight = PackedFloat32Array()
	_highlight.resize(catalog.size())
	_highlight.fill(1.0)

	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_custom_data = true
	multimesh.mesh = _point_mesh()
	multimesh.instance_count = catalog.size()

	_buffer = PackedFloat32Array()
	_buffer.resize(catalog.size() * STRIDE)
	# Identity basis for every instance; the shader does the billboarding.
	for i in catalog.size():
		var b := i * STRIDE
		_buffer[b] = 1.0
		_buffer[b + 5] = 1.0
		_buffer[b + 10] = 1.0
	set_filter([])

func _point_mesh() -> Mesh:
	var q := QuadMesh.new()
	q.size = Vector2.ONE
	return q

## Show only these regimes; an empty array means all of them.
func set_filter(regimes: Array) -> void:
	var out := PackedInt32Array()
	for i in catalog.size():
		if regimes.is_empty() or catalog[i].get("regime", "") in regimes:
			out.append(i)
	active = out
	_radius_dirty = true
	# Filtered objects are packed to the front and the tail is hidden, because
	# MultiMesh can only draw a contiguous prefix of its instances.
	multimesh.visible_instance_count = active.size()
	_write_custom_data()

## Mark a subset as highlighted.
##
## The sign of the stored value carries the flag: NEGATIVE means highlighted,
## and the shader swaps in a distinct colour for those. Brightness alone was not
## enough -- a highlighted object kept its regime colour, so picking it out of
## 14,745 similarly-coloured points meant hunting for slightly brighter dots.
##
## Because colour now does the separating, the rest can stay dimmer-but-legible
## rather than being pushed to near-black; the surrounding population is the
## context that makes a debris cloud mean anything.
func set_highlight(indices: PackedInt32Array) -> void:
	_highlight.fill(dim_others if indices.size() > 0 else 1.0)
	for i in indices:
		if i >= 0 and i < _highlight.size():
			_highlight[i] = -1.0
	_write_custom_data()

## Outermost radius among the currently visible objects, after exaggeration.
## This is what decides how close the field comes to the viewer's face, so
## ContentRig and ChapterDeck derive camera framing from it.
func max_content_radius() -> float:
	if _radius_dirty:
		_max_radius = 1.0
		for i in active:
			# max_radius_re is what the object actually REACHES inside the
			# propagated window, written by build_ephemeris.py. Orbit apogee is
			# the wrong input: an HEO object sitting near perigee for the whole
			# span never goes near its apogee, and clamping for it would shrink
			# every wide chapter to fit content that is never drawn.
			var r: float = catalog[i].get("max_radius_re", 1.0)
			_max_radius = maxf(_max_radius, 1.0 + (r - 1.0) * altitude_exaggeration)
		_radius_dirty = false
	return _max_radius


func _write_custom_data() -> void:
	if _buffer.is_empty():
		return
	for slot in active.size():
		var src: int = active[slot]
		var b := slot * STRIDE + 12
		_buffer[b] = REGIME_IDS.get(catalog[src].get("regime", "LEO"), 0.0)
		# Sign is the highlight flag; magnitude is brightness.
		_buffer[b + 1] = _highlight[src]
		_buffer[b + 2] = point_size * REGIME_SIZE.get(catalog[src].get("regime", "LEO"), 1.0)
		_buffer[b + 3] = _jitter(catalog[src].get("norad_id", src))

## Stable per-object variation in [0,1], used by the shader to vary size and
## brightness.
##
## This is a STEREO fix, not decoration. At the LEO framing the field's mean
## on-screen point spacing is about 14 px while the scene's disparity range is
## about 39 px -- so a point's true match in the other eye is frequently farther
## away than its nearest neighbour. With interchangeable dots that is the
## classic wallpaper condition: the visual system pairs a point in one eye with
## the WRONG point in the other and fuses phantom depth, or fails to settle at
## all. Giving every object its own size and brightness makes matches unique.
##
## Seeded from NORAD ID so it is identical in both eyes and across frames and
## rebuilds. Anything per-frame or per-eye here would be far worse than no
## jitter at all.
static func _jitter(seed_value: int) -> float:
	var h := int(seed_value) * 2654435761
	h = (h ^ (h >> 13)) * 1274126177
	return float(absi(h ^ (h >> 16)) % 4096) / 4096.0


func update_positions(unix_seconds: float) -> void:
	if store == null or not store.is_loaded() or active.is_empty():
		return
	var _t0 := Time.get_ticks_usec()

	var n := store.n_objects
	var cursor := store.sample_cursor(unix_seconds)
	var i0 := int(cursor)
	var i1 := (i0 + 1) % store.n_samples
	var t := cursor - float(i0)
	var base_a := i0 * n * 3
	var base_b := i1 * n * 3
	var pos := store.positions
	var k := altitude_exaggeration

	for slot in active.size():
		var src: int = active[slot]
		var a := base_a + src * 3
		var b := base_b + src * 3
		var x := pos[a] + (pos[b] - pos[a]) * t
		var y := pos[a + 1] + (pos[b + 1] - pos[a + 1]) * t
		var z := pos[a + 2] + (pos[b + 2] - pos[a + 2]) * t

		# Altitude exaggeration. At true scale the LEO shell sits ~1% off the
		# globe and the layered structure we are selling is invisible. Scaling
		# altitude-above-surface (not radius) keeps the surface fixed.
		if k != 1.0:
			var r := sqrt(x * x + y * y + z * z)
			if r > 0.0001:
				var s := (1.0 + (r - 1.0) * k) / r
				x *= s
				y *= s
				z *= s

		var o := slot * STRIDE
		_buffer[o + 3] = x
		_buffer[o + 7] = y
		_buffer[o + 11] = z

	multimesh.buffer = _buffer
	last_update_usec = Time.get_ticks_usec() - _t0

## World position of a catalog object, with the same exaggeration applied, so
## labels and selection markers land exactly on the rendered point.
func rendered_position(catalog_index: int, unix_seconds: float) -> Vector3:
	var p := store.position_at(catalog_index, unix_seconds)
	var r := p.length()
	if altitude_exaggeration != 1.0 and r > 0.0001:
		p *= (1.0 + (r - 1.0) * altitude_exaggeration) / r
	return p
