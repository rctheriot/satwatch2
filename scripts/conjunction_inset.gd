class_name ConjunctionInset
extends Node3D
## Magnified view of one close approach, in the CO-MOVING frame.
##
## A conjunction cannot be drawn honestly at one fixed scale. The miss distance
## here is ~600 m while the objects close from hundreds of kilometres: at a
## scale that shows the approach the miss is sub-pixel, and at a scale that
## shows the miss the other object is sixty metres off screen for all but a
## third of a second.
##
## So two things happen. The primary object is fixed at the origin and the
## secondary is plotted RELATIVE to it -- the relative track is then a
## near-straight line passing the origin at exactly the miss distance, which is
## also how encounter geometry is normally presented. And the magnification
## RAMPS: far out it is set so the secondary sits at a constant radius (you see
## it close), and it stops tightening once the miss distance fills the reference
## ring (you see the number).
##
## The ring is always drawn at exactly the miss distance and a scale bar states
## the current magnification, so the zoom is never something taken on trust.

## Radius the miss distance is drawn at once fully zoomed in, in metres.
const MISS_RADIUS_M := 0.105
## Radius the secondary is held at while still approaching.
const APPROACH_RADIUS_M := 0.30
## Relative track is clipped to this radius so it stays inside the inset.
const CLIP_RADIUS_M := 0.44
## Rebuild the track mesh when the scale has moved this much, so the tube keeps
## a sensible thickness without rebuilding every frame.
const REBUILD_RATIO := 1.12

var primary_color := Color(0.42, 0.80, 1.00)
var secondary_color := Color(1.00, 0.62, 0.35)

var event: Dictionary = {}
var km_to_m: float = 1.0

var _primary: MeshInstance3D
var _secondary: MeshInstance3D
var _track: MeshInstance3D
var _ring: MeshInstance3D
var _label_a: Label3D
var _label_b: Label3D
var _readout: Label3D
var _scale_note: Label3D
var _tca_unix := 0.0
var _miss_km := 1.0
var _track_built_at := 0.0

func _ready() -> void:
	visible = false

func show_event(e: Dictionary) -> void:
	event = e
	_miss_km = maxf(float(e.get("miss_km", 1.0)), 0.001)
	_tca_unix = float(e.get("tca_unix", 0.0))
	km_to_m = MISS_RADIUS_M / _miss_km
	_track_built_at = 0.0

	for c in get_children():
		c.queue_free()
	_primary = _marker(primary_color, 0.014)
	_secondary = _marker(secondary_color, 0.014)
	_ring = _miss_ring()
	_track = MeshInstance3D.new()
	add_child(_track)

	_label_a = _text(String(e.get("a_name", "")), primary_color, 30)
	_label_b = _text(String(e.get("b_name", "")), secondary_color, 30)
	_readout = _text("", Color(0.88, 0.94, 1.00), 32)
	_readout.position = Vector3(0.0, -0.30, 0.0)
	_scale_note = _text("", Color(0.55, 0.66, 0.78), 24)
	_scale_note.position = Vector3(0.0, -0.36, 0.0)
	visible = true

func _marker(c: Color, r: float) -> MeshInstance3D:
	var s := SphereMesh.new()
	s.radius = r
	s.height = r * 2.0
	s.radial_segments = 20
	s.rings = 12
	var m := MeshInstance3D.new()
	m.mesh = s
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = c
	m.material_override = mat
	add_child(m)
	return m

func _text(s: String, c: Color, font_size: int) -> Label3D:
	var l := Label3D.new()
	l.text = s
	l.font_size = font_size
	# Label3D defaults to 0.005 m per pixel, which makes a 30 pt label 15 cm
	# tall -- it swamped the whole wall. Size it for reading at ~2.4 m instead.
	l.pixel_size = 0.0009
	l.modulate = c
	l.outline_size = 8
	l.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	l.no_depth_test = false
	add_child(l)
	return l

## A ring at exactly the miss distance, so the magnification is visible rather
## than asserted. Built at unit radius and scaled, since the scale ramps.
func _miss_ring() -> MeshInstance3D:
	var t := TorusMesh.new()
	t.inner_radius = 0.986
	t.outer_radius = 1.0
	var m := MeshInstance3D.new()
	m.mesh = t
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.55, 0.66, 0.78, 0.45)
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.material_override = mat
	add_child(m)
	return m

## Secondary minus primary, in km, on Godot axes. Same (x, z, -y) mapping the
## ephemeris builder uses, so this agrees with the main scene.
func _rel_km(row: Array) -> Vector3:
	return Vector3(float(row[4]) - float(row[1]),
		float(row[6]) - float(row[3]),
		-(float(row[5]) - float(row[2])))

func _rebuild_track() -> void:
	var pts := PackedVector3Array()
	for row in event.get("track", []):
		var p := _rel_km(row) * km_to_m
		if p.length() <= CLIP_RADIUS_M:
			pts.append(p)
	if pts.size() >= 2:
		_track.mesh = _tube(pts, 0.0020)
		var mat := StandardMaterial3D.new()
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.albedo_color = Color(secondary_color.r, secondary_color.g,
			secondary_color.b, 0.5)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		_track.material_override = mat
	else:
		_track.mesh = null
	_track_built_at = km_to_m

## A tube, not a line: 1 px lines shimmer, and in stereo the two eyes disagree
## about which pixels are lit, which reads as rivalry instead of depth.
func _tube(points: PackedVector3Array, radius: float) -> ArrayMesh:
	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var sides := 6
	for i in points.size() - 1:
		var a := points[i]
		var b := points[i + 1]
		var axis := b - a
		if axis.length() < 1e-9:
			continue
		axis = axis.normalized()
		var up := Vector3.UP if absf(axis.dot(Vector3.UP)) < 0.9 else Vector3.RIGHT
		var u := axis.cross(up).normalized() * radius
		var v := axis.cross(u.normalized()).normalized() * radius
		for k in sides:
			var t0 := TAU * float(k) / float(sides)
			var t1 := TAU * float(k + 1) / float(sides)
			var o0 := u * cos(t0) + v * sin(t0)
			var o1 := u * cos(t1) + v * sin(t1)
			for p in [a + o0, b + o0, b + o1, a + o0, b + o1, a + o1]:
				st.add_vertex(p)
	st.generate_normals()
	return st.commit()

func update_time(unix_seconds: float) -> void:
	if not visible or event.is_empty():
		return
	var rows: Array = event.get("track", [])
	if rows.is_empty():
		return

	var offset := unix_seconds - _tca_unix
	var step: float = maxf(float(event.get("track_step_s", 1.0)), 0.001)
	var half: float = float(event.get("track_half_window_s", 120.0))
	var idx := int(clampf((offset + half) / step, 0.0, float(rows.size() - 1)))
	var rel := _rel_km(rows[idx])
	var sep_km := maxf(rel.length(), 0.0001)

	# Ramp: hold the secondary at a constant radius while it closes, then stop
	# tightening once the miss distance fills the reference ring.
	km_to_m = minf(APPROACH_RADIUS_M / sep_km, MISS_RADIUS_M / _miss_km)

	if km_to_m > _track_built_at * REBUILD_RATIO \
			or km_to_m < _track_built_at / REBUILD_RATIO:
		_rebuild_track()

	_secondary.position = rel * km_to_m
	_ring.scale = Vector3.ONE * (_miss_km * km_to_m)
	_label_a.position = Vector3(0.0, 0.03, 0.0)
	_label_b.position = _secondary.position + Vector3(0.0, 0.03, 0.0)

	_readout.text = "T%+.0f s      %.2f km apart" % [offset, sep_km]
	_scale_note.text = "closing %.2f km/s   ·   miss %.0f m (ring)   ·   x%.0f" % [
		float(event.get("relative_speed_kms", 0.0)), _miss_km * 1000.0,
		km_to_m * 1000.0]
