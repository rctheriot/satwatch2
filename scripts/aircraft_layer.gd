class_name AircraftLayer
extends MultiMeshInstance3D
## Live ADS-B aircraft, from tools/fetch_aircraft.py.
##
## This is the domain immediately below the one the rest of the demo is about,
## and that is the whole reason it is here. Airliners cruise near 10-12 km,
## about 0.0017 Earth radii. The lowest tracked satellites are roughly forty
## times higher. Numbers do not convey that; two layers on the same globe do.
##
## A child of the Earth mesh, because positions are geographic and must inherit
## the GMST rotation exactly as the surface imagery does.
##
## Altitude is exaggerated hard -- at true scale this layer is thinner than the
## coastline -- and the panel says by how much.

const RE_KM := 6378.137
const STRIDE := 16                 ## Same MultiMesh layout as SatelliteField.

@export var altitude_exaggeration: float = 28.0
@export var point_size: float = 0.8
## Length of the drawn track, in SIMULATION seconds.
##
## Two limits, and the shorter one wins. These are dead-reckoned from a single
## snapshot rather than recorded history, so a long trail claims more than the
## data supports. And visually, half an hour of great-circle flight is about
## 450 km, which at this density stops reading as tracks and starts reading as
## spines radiating off the globe. Ten minutes is roughly 150 km: clearly a
## direction of travel, without either overstatement.
@export var trail_seconds: float = 900.0

var loaded := false
var count := 0
var source := ""
var snapshot_unix := 0.0
var median_altitude_km := 0.0
var fetched_utc := ""

## Unit position and unit eastward-of-heading tangent at the snapshot, so a
## position at any later time is one rotation in that plane. Precomputed because
## the great-circle formula per aircraft per frame is far more trigonometry than
## this needs.
var _base: PackedFloat32Array = PackedFloat32Array()     ## 3 per aircraft
var _tangent: PackedFloat32Array = PackedFloat32Array()  ## 3 per aircraft
var _radius: PackedFloat32Array = PackedFloat32Array()   ## 1 per aircraft
var _omega: PackedFloat32Array = PackedFloat32Array()    ## radians/second
var _buffer: PackedFloat32Array = PackedFloat32Array()
var _trail_buffer: PackedFloat32Array = PackedFloat32Array()
var trails: MultiMeshInstance3D

func load_from(path: String) -> bool:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return false                   # Optional layer; the demo runs without it.
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("AircraftLayer: %s is not valid JSON." % path)
		return false

	var d: Dictionary = parsed
	var rows: Array = d.get("aircraft", [])
	if rows.is_empty():
		return false
	source = String(d.get("source", ""))
	snapshot_unix = float(d.get("snapshot_unix", 0))
	median_altitude_km = float(d.get("median_altitude_km", 0.0))
	fetched_utc = String(d.get("fetched_utc", ""))
	count = rows.size()

	_base.resize(count * 3)
	_tangent.resize(count * 3)
	_radius.resize(count)
	_omega.resize(count)

	for i in count:
		var row: Array = rows[i]
		var lat := deg_to_rad(float(row[0]))
		var lon := deg_to_rad(float(row[1]))
		var alt_km := float(row[2])
		var speed := float(row[3])          # m/s
		var heading := deg_to_rad(float(row[4]))

		# Same Earth-fixed convention as GroundSites and earth.gdshader.
		var up := Vector3(cos(lat) * cos(lon), sin(lat), -cos(lat) * sin(lon))
		# Local north and east, to turn a compass heading into a direction.
		var north := Vector3(-sin(lat) * cos(lon), cos(lat), sin(lat) * sin(lon))
		var east := Vector3(-sin(lon), 0.0, -cos(lon))
		var course := (north * cos(heading) + east * sin(heading)).normalized()

		var b := i * 3
		_base[b] = up.x
		_base[b + 1] = up.y
		_base[b + 2] = up.z
		_tangent[b] = course.x
		_tangent[b + 1] = course.y
		_tangent[b + 2] = course.z
		_radius[i] = 1.0 + (alt_km / RE_KM) * altitude_exaggeration
		# Ground speed as an angular rate about the Earth's centre.
		_omega[i] = speed / (RE_KM * 1000.0)

	_build_multimesh()
	_build_trails()
	loaded = true
	print("AircraftLayer: %d aircraft, median %.1f km, snapshot %s"
		% [count, median_altitude_km, fetched_utc.left(19)])
	return true

func _build_multimesh() -> void:
	multimesh = MultiMesh.new()
	multimesh.transform_format = MultiMesh.TRANSFORM_3D
	multimesh.use_custom_data = true
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	multimesh.mesh = quad
	multimesh.instance_count = count
	multimesh.visible_instance_count = count

	_buffer.resize(count * STRIDE)
	for i in count:
		var o := i * STRIDE
		_buffer[o] = 1.0
		_buffer[o + 5] = 1.0
		_buffer[o + 10] = 1.0
		_buffer[o + 12] = 0.0            # regime slot, unused here
		_buffer[o + 13] = 1.0            # never dimmed
		_buffer[o + 14] = point_size
		# Stable per-object variation, as for satellites: a dense field of
		# identical points invites the two eyes to pair up the wrong ones.
		_buffer[o + 15] = SatelliteField._jitter(i * 2654435761 + 12345)

## Trails live on their own MultiMesh so they can use a ribbon shader. Each
## instance's transform carries the segment: translation = trail start, basis X
## column = the vector to the current position.
func _build_trails() -> void:
	trails = MultiMeshInstance3D.new()
	trails.name = "Trails"
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	mm.mesh = quad
	mm.instance_count = count
	mm.visible_instance_count = count
	trails.multimesh = mm
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/flight_trail.gdshader")
	trails.material_override = mat
	# Drawn before the aircraft so the gold markers sit on top of their tracks.
	add_child(trails)
	_trail_buffer.resize(count * 12)

## Position on the great circle at an arbitrary time, as a rotation of the
## precomputed snapshot position and tangent.
func _position_at(i: int, elapsed: float) -> Vector3:
	var b := i * 3
	var theta: float = _omega[i] * elapsed
	var c := cos(theta)
	var sn := sin(theta)
	var r: float = _radius[i]
	return Vector3(
		(_base[b] * c + _tangent[b] * sn) * r,
		(_base[b + 1] * c + _tangent[b + 1] * sn) * r,
		(_base[b + 2] * c + _tangent[b + 2] * sn) * r)

## Dead-reckon along each aircraft's great circle. Rotating the precomputed
## position/tangent pair is two trig calls per aircraft; the full spherical
## formula would be several times that for no visible gain.
func update_positions(unix_seconds: float) -> void:
	if not loaded:
		return
	var elapsed := unix_seconds - snapshot_unix
	var tail_elapsed := elapsed - trail_seconds
	for i in count:
		var p := _position_at(i, elapsed)
		var o := i * STRIDE
		_buffer[o + 3] = p.x
		_buffer[o + 7] = p.y
		_buffer[o + 11] = p.z

		# Trail instance: translation is the tail, basis X is the segment to the
		# aircraft. The other two basis columns are unused by the shader but must
		# not be zero, or the instance is culled as degenerate.
		var tail := _position_at(i, tail_elapsed)
		var seg := p - tail
		var t := i * 12
		_trail_buffer[t] = seg.x
		_trail_buffer[t + 1] = 0.0
		_trail_buffer[t + 2] = 0.0
		_trail_buffer[t + 3] = tail.x
		_trail_buffer[t + 4] = seg.y
		_trail_buffer[t + 5] = 1.0
		_trail_buffer[t + 6] = 0.0
		_trail_buffer[t + 7] = tail.y
		_trail_buffer[t + 8] = seg.z
		_trail_buffer[t + 9] = 0.0
		_trail_buffer[t + 10] = 1.0
		_trail_buffer[t + 11] = tail.z
	multimesh.buffer = _buffer
	if trails != null:
		trails.multimesh.buffer = _trail_buffer

## Outermost aircraft radius in Earth radii, after exaggeration. Used to frame
## the chapter: the satellite field is hidden here, so its 8-Earth-radii extent
## must not be what the camera distance is derived from.
func max_radius() -> float:
	var m := 1.0
	for r in _radius:
		m = maxf(m, r)
	return m

func summary() -> String:
	return "%d AIRCRAFT AIRBORNE · median %.1f km · %s" % [
		count, median_altitude_km, source]
