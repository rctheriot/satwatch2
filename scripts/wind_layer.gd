class_name WindLayer
extends Node3D
## Jet-stream flow, drawn as particles advected through a real 250 hPa wind
## field from tools/fetch_winds.py.
##
## 250 hPa is about 10.5 km -- airliner cruise altitude. That is why this is
## more than weather decoration: these winds set transit times, fuel loads and
## route choice, and a 300 km/h tailwind is the difference between two very
## different flight plans.
##
## Particles are advected rather than drawn as static arrows because a flow
## field is about motion, and a barb chart of a jet stream conveys almost none
## of it. Each particle carries a short trail and is respawned on a stagger so
## the field never visibly resets.
##
## A child of the Earth mesh: the field is geographic and must turn with it.

const RE_KM := 6378.137
const TRAIL_STRIDE := 12          ## MultiMesh TRANSFORM_3D, no custom data.
## Speed mapped to the top of the colour ramp, in m/s. Fixed rather than taken
## from each fetch's own peak, so a colour means the same wind from one day to
## the next -- auto-scaling would make a calm day and a storm look identical.
const SPEED_FULL_SCALE_MS := 65.0

## Enough to read as a flow without the CPU advection becoming the frame budget.
## Every particle costs a bilinear sample and a great-circle step per frame.
@export var particle_count: int = 4500
@export var altitude_km: float = 10.5
@export var altitude_exaggeration: float = 28.0
## Simulation seconds of travel drawn behind each particle. The trail length is
## derived from the LOCAL WIND SPEED over this interval, not from how far the
## particle happened to move last frame -- that made length depend on frame rate
## and time rate, and at 60x it produced trails about three millimetres long.
@export var trail_seconds: float = 25200.0
## Simulation seconds before a particle is respawned somewhere new. Without
## this, everything drains into the jet cores and the rest of the globe empties.
@export var lifetime_seconds: float = 43200.0

var loaded := false
var source := ""
var valid_time := ""
var level := ""
var peak_speed_ms: float = 0.0
var mean_speed_ms: float = 0.0

var _lon_min: float
var _lon_step: float
var _lon_count: int
var _lat_min: float
var _lat_step: float
var _lat_count: int
var _u: PackedFloat32Array = PackedFloat32Array()
var _v: PackedFloat32Array = PackedFloat32Array()

## Particle state, in degrees. Kept in lat/lon rather than as vectors because
## sampling the field is a lat/lon lookup and converting back every frame would
## cost more than it saves.
var _lat: PackedFloat32Array = PackedFloat32Array()
var _lon: PackedFloat32Array = PackedFloat32Array()
var _age: PackedFloat32Array = PackedFloat32Array()
var _seed_lat: PackedFloat32Array = PackedFloat32Array()
var _seed_lon: PackedFloat32Array = PackedFloat32Array()

var _trails: MultiMeshInstance3D
var _trail_buffer: PackedFloat32Array = PackedFloat32Array()
var _radius: float = 1.0
var _last_time: float = 0.0
var _rng := RandomNumberGenerator.new()

func load_from(path: String) -> bool:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return false
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	f.close()
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("WindLayer: %s is not valid JSON." % path)
		return false

	var d: Dictionary = parsed
	var u: Array = d.get("u", [])
	var v: Array = d.get("v", [])
	if u.is_empty() or u.size() != v.size():
		return false

	source = String(d.get("source", ""))
	valid_time = String(d.get("valid_time", ""))
	level = String(d.get("level", ""))
	peak_speed_ms = float(d.get("peak_speed_ms", 0.0))
	mean_speed_ms = float(d.get("mean_speed_ms", 0.0))
	_lon_min = float(d.get("lon_min", -180.0))
	_lon_step = float(d.get("lon_step", 10.0))
	_lon_count = int(d.get("lon_count", 36))
	_lat_min = float(d.get("lat_min", -80.0))
	_lat_step = float(d.get("lat_step", 10.0))
	_lat_count = int(d.get("lat_count", 17))

	_u.resize(u.size())
	_v.resize(v.size())
	for i in u.size():
		_u[i] = float(u[i])
		_v[i] = float(v[i])

	_radius = 1.0 + (altitude_km / RE_KM) * altitude_exaggeration
	_rng.seed = 20260915
	_spawn_all()
	_build_trails()
	loaded = true
	print("WindLayer: %s field valid %s, peak %.0f m/s, %d particles"
		% [level, valid_time.left(16), peak_speed_ms, particle_count])
	return true

func _spawn_all() -> void:
	for arr in [_lat, _lon, _age, _seed_lat, _seed_lon]:
		arr.resize(particle_count)
	for i in particle_count:
		_respawn(i, _rng.randf() * lifetime_seconds)

func _respawn(i: int, start_age: float = 0.0) -> void:
	# Uniform by AREA, not by latitude: seeding uniformly in latitude crowds the
	# poles, where the cells are narrow, and thins the tropics.
	var lat: float = rad_to_deg(asin(_rng.randf_range(-0.985, 0.985)))
	_lat[i] = clampf(lat, _lat_min, _lat_min + _lat_step * (_lat_count - 1))
	_lon[i] = _rng.randf_range(-180.0, 180.0)
	_seed_lat[i] = _lat[i]
	_seed_lon[i] = _lon[i]
	_age[i] = start_age

## Bilinear sample of the field, wrapping in longitude and clamping in latitude.
## Returns eastward/northward components in m/s.
func sample(lat: float, lon: float) -> Vector2:
	var fx := (wrapf(lon, -180.0, 180.0) - _lon_min) / _lon_step
	var fy := clampf((lat - _lat_min) / _lat_step, 0.0, float(_lat_count - 1))
	var x0: int = int(floor(fx)) % _lon_count
	if x0 < 0:
		x0 += _lon_count
	var x1 := (x0 + 1) % _lon_count
	var y0: int = int(floor(fy))
	var y1 := mini(y0 + 1, _lat_count - 1)
	var tx: float = fx - floor(fx)
	var ty: float = fy - float(y0)

	var i00 := y0 * _lon_count + x0
	var i10 := y0 * _lon_count + x1
	var i01 := y1 * _lon_count + x0
	var i11 := y1 * _lon_count + x1
	var u: float = lerpf(lerpf(_u[i00], _u[i10], tx), lerpf(_u[i01], _u[i11], tx), ty)
	var v: float = lerpf(lerpf(_v[i00], _v[i10], tx), lerpf(_v[i01], _v[i11], tx), ty)
	return Vector2(u, v)

func _build_trails() -> void:
	_trails = MultiMeshInstance3D.new()
	_trails.name = "WindTrails"
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	var quad := QuadMesh.new()
	quad.size = Vector2.ONE
	mm.mesh = quad
	mm.instance_count = particle_count
	mm.visible_instance_count = particle_count
	_trails.multimesh = mm
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/wind_trail.gdshader")
	_trails.material_override = mat
	add_child(_trails)
	_trail_buffer.resize(particle_count * TRAIL_STRIDE)

## Unit vector for a geographic position, on the same Earth-fixed axes as
## GroundSites and earth.gdshader.
static func _to_vector(lat_deg: float, lon_deg: float) -> Vector3:
	var la := deg_to_rad(lat_deg)
	var lo := deg_to_rad(lon_deg)
	return Vector3(cos(la) * cos(lo), sin(la), -cos(la) * sin(lo))

func update_positions(unix_seconds: float) -> void:
	if not loaded:
		return
	var dt := unix_seconds - _last_time
	_last_time = unix_seconds
	# Guard the first frame and any clock jump (a chapter change moves time).
	if dt <= 0.0 or dt > 600.0:
		dt = clampf(dt, 0.0, 600.0)

	var mm := _trails.multimesh
	for i in particle_count:
		_age[i] += dt
		if _age[i] > lifetime_seconds:
			_respawn(i)

		var lat: float = _lat[i]
		var lon: float = _lon[i]

		# Advance along the flow. Degrees per second: eastward displacement
		# shrinks with cos(latitude) because meridians converge.
		var w := sample(lat, lon)
		var cos_lat := maxf(cos(deg_to_rad(lat)), 0.15)
		var deg_per_m := 180.0 / (PI * RE_KM * 1000.0)
		lon += w.x * deg_per_m / cos_lat * dt
		lat += w.y * deg_per_m * dt

		# Reaching a pole is a coordinate problem, not a physical destination.
		var lat_max := _lat_min + _lat_step * (_lat_count - 1)
		if lat > lat_max or lat < _lat_min:
			_respawn(i)
			lat = _lat[i]
			lon = _lon[i]
		else:
			_lat[i] = lat
			_lon[i] = wrapf(lon, -180.0, 180.0)

		var head := _to_vector(_lat[i], _lon[i]) * _radius
		# Step BACK along the local flow by trail_seconds to find the tail. A
		# single step rather than an integration: over a few hours the field
		# barely turns, and a streamline is meant to show the flow here and now.
		# Deriving it from the wind rather than from frame motion makes the
		# length mean something -- it IS the distance air travels in that time.
		var back_cos: float = maxf(cos(deg_to_rad(_lat[i])), 0.15)
		var tail_lat: float = _lat[i] - w.y * deg_per_m * trail_seconds
		var tail_lon: float = _lon[i] - w.x * deg_per_m / back_cos * trail_seconds
		var start := _to_vector(clampf(tail_lat, -89.5, 89.5),
			wrapf(tail_lon, -180.0, 180.0)) * _radius
		var seg := head - start

		var t := i * TRAIL_STRIDE
		_trail_buffer[t] = seg.x
		_trail_buffer[t + 1] = 0.0
		_trail_buffer[t + 2] = 0.0
		_trail_buffer[t + 3] = start.x
		_trail_buffer[t + 4] = seg.y
		_trail_buffer[t + 5] = 1.0
		_trail_buffer[t + 6] = 0.0
		_trail_buffer[t + 7] = start.y
		_trail_buffer[t + 8] = seg.z
		_trail_buffer[t + 9] = 0.0
		_trail_buffer[t + 10] = 1.0
		_trail_buffer[t + 11] = start.z
	mm.buffer = _trail_buffer

func summary() -> String:
	return "%s WINDS  peak %.0f m/s (%.0f km/h) · %s · valid %s" % [
		level, peak_speed_ms, peak_speed_ms * 3.6, source, valid_time.left(16)]

## Colour key for the panel, in the units a forecaster uses.
static func speed_legend() -> String:
	return "blue <15 · green 27 · yellow 39 · orange 52 · red %.0f m/s" \
		% SPEED_FULL_SCALE_MS
