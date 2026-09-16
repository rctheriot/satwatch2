class_name OrbitTrails
extends MultiMeshInstance3D
## Draws one closed orbital path per object, toggled globally by the viewer
## (see main.gd's "toggle_orbit_trails" handling) rather than per chapter --
## a real control that persists across chapters, the same way free-fly mode
## does, rather than one the deck resets on every transition.
##
## A sibling of SatelliteField under EarthRig, not a child of EarthMesh: paths
## are TEME-fixed like the satellites themselves and must NOT spin with the
## ground's GMST rotation. Altitude exaggeration is applied per point with
## the same formula SatelliteField uses, so a path lines up with the shell its
## own dots are drawn in.

## Above this many objects, a chapter's population does not get trails: the
## segment count becomes a real per-toggle hitch to build, and for an
## un-highlighted filter (LEO's 14,744, the full catalog's 16,000+) there is
## no meaningful subset being traced anyway. Set high enough to still cover a
## HIGHLIGHTED population that is large but deliberate -- Starlink alone is
## ~8,300 objects, and tracing exactly that is the point of highlighting it
## (see main.gd's _refresh_orbit_trails()).
const MAX_TRAIL_OBJECTS := 9000

var store: OrbitPathStore
var _material: ShaderMaterial

func build(orbit_store: OrbitPathStore) -> void:
	store = orbit_store
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	mm.mesh = quad
	mm.instance_count = 0
	multimesh = mm

	_material = ShaderMaterial.new()
	_material.shader = load("res://shaders/orbit_trail.gdshader")
	material_override = _material
	visible = false

## Neutral default when tracing a chapter's whole filtered population (HEO,
## MEO, GEO) rather than something a chapter highlights -- see main.gd's
## _refresh_orbit_trails() for which case is which.
const DEFAULT_COLOR := Color(0.55, 0.68, 0.95, 0.16)

## Rebuilds the drawn set from scratch. Called whenever the chapter changes
## while the toggle is on, or when the toggle switches on -- never per frame,
## since the paths themselves are static and only the CURRENT-position dots
## need to move. `color` should match whatever the dots themselves are
## coloured when tracing a highlighted subset (debris red, one constellation
## green), so "just the red paths" reads as red, not the neutral default.
func show_paths(indices: PackedInt32Array, altitude_exaggeration: float,
		color: Color = DEFAULT_COLOR) -> void:
	if store == null or not store.is_loaded() or indices.is_empty() \
			or indices.size() > MAX_TRAIL_OBJECTS:
		visible = false
		multimesh.instance_count = 0
		return
	_material.set_shader_parameter("trail_color", color)

	var p := store.points_per_path
	var segs_per_obj := p - 1     # one full period is nearly closed already;
	                                # forcing a p-th segment back to point 0
	                                # would draw a chord across real precession
	                                # between the loop's start and end.
	var total := indices.size() * segs_per_obj
	multimesh.instance_count = total
	multimesh.visible_instance_count = total

	var pos := store.positions
	var k := altitude_exaggeration
	var slot := 0
	for idx in indices:
		if idx < 0 or idx >= store.n_objects:
			continue
		var base := idx * p * 3
		var prev := _exaggerated(pos, base, k)
		for i in range(1, p):
			var cur := _exaggerated(pos, base + i * 3, k)
			# Basis X column carries the segment vector; Y/Z are irrelevant to
			# the shader, which derives its own perpendicular from the view
			# direction each frame -- see orbit_trail.gdshader.
			var xf := Transform3D(Basis(), prev)
			xf.basis.x = cur - prev
			multimesh.set_instance_transform(slot, xf)
			slot += 1
			prev = cur
	visible = true

## Same altitude-exaggeration formula as SatelliteField.update_positions():
## scales altitude ABOVE the surface, not the raw radius, so the surface
## itself stays fixed and a path lines up with its object's exaggerated shell.
static func _exaggerated(pos: PackedFloat32Array, base: int, k: float) -> Vector3:
	var x := pos[base]
	var y := pos[base + 1]
	var z := pos[base + 2]
	if k == 1.0:
		return Vector3(x, y, z)
	var r := sqrt(x * x + y * y + z * z)
	if r <= 0.0001:
		return Vector3(x, y, z)
	var s := (1.0 + (r - 1.0) * k) / r
	return Vector3(x * s, y * s, z * s)
