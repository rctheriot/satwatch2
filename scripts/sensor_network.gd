class_name SensorNetwork
extends Node3D
## Space Surveillance Network sites, their visibility volumes, and a live count
## of what each can actually see.
##
## The counts are the honest part and the interesting part. Geometric access is
## exact (GroundSites.is_visible), so "412 tracked objects are above Eglin's
## horizon right now" is a real number, not an estimate. Optical sites carry the
## two further real constraints -- the site must be in darkness while the target
## is still sunlit -- which is why deep-space surveillance only works in a window
## each night. That falls out of the data instead of being asserted.
##
## Ranges are NOMINAL, representing a class of sensor. Real detection capability
## needs power, aperture and target cross-section, none of which is public.
## Nothing here should be read as actual sensor performance.

const RE_KM := 6378.137
## Optical sites need real darkness, not just night.
const DARK_SUN_ELEVATION := -12.0

## How far the volumes are DRAWN, which is not how far the sensors reach.
##
## Drawn at their nominal ranges the picture is unreadable: ten radar cones at
## an 87-degree half-angle merge into one opaque shell around the planet, and
## the optical volumes run off the wall entirely at 45,000 km. Both are
## geometrically correct and neither tells the viewer anything.
##
## So the volumes are drawn truncated -- radar to the top of the LEO shell,
## which is the part of their coverage that matters for what is on screen, and
## optical as a pointing indication rather than a reach. The panel states the
## nominal ranges, and the VISIBILITY COUNTS are computed against the full
## range regardless of what is drawn. The picture is cropped; the numbers are not.
const RADAR_DRAW_KM := 3000.0

var field: SatelliteField
var store: EphemerisStore

var site_counts: PackedInt32Array = PackedInt32Array()
var site_active: Array[bool] = []
var total_visible: int = 0

var _ups_ecef: Array[Vector3] = []
var _tan_masks: PackedFloat32Array = PackedFloat32Array()
var _markers: Array[MeshInstance3D] = []
## One entry per site; null for optical sites, which are not drawn as volumes.
var _volumes: Array = []
var _visible_flags: PackedByteArray = PackedByteArray()
var _cursor := 0
var _updated := false

## How many sites are evaluated per frame -- a straight trade between frame rate
## and how smoothly the colouring updates.
##
## Measured on an M1 Max with 14,745 LEO objects at 1920x648:
##
##     sites/frame    frame time    FPS    full pass
##         5            21.9 ms      46     3 frames
##         3            17.1 ms      58     5 frames
##         2            14.7 ms      68     7 frames
##
## against ~9 ms (108 fps) for a chapter with no sensor layer. Three is the
## balance: near 60 fps with a complete pass about twelve times a second. At the
## demo's 60x time rate an object crosses a site's coverage in roughly 0.2 s of
## real time, so that is a couple of updates per crossing -- enough not to read
## as ticking, which one site per frame (4 Hz) plainly did.
##
## This is a GDScript ceiling, not an algorithmic one. A full pass is 15 sites x
## 14,745 objects = 221,000 evaluations; the arithmetic is already square-root
## free and inlined, and caching r^2 bought almost nothing, which says the cost
## is array reads and loop overhead rather than maths. Moving the test to a
## compute shader is the real fix and would make this constant irrelevant.
const SITES_PER_FRAME := 3
var _pending: PackedByteArray = PackedByteArray()

func build() -> void:
	for c in get_children():
		c.queue_free()
	_ups_ecef.clear()
	_markers.clear()
	_volumes.clear()
	site_counts.resize(GroundSites.SITES.size())
	site_active.resize(GroundSites.SITES.size())
	_tan_masks.resize(GroundSites.SITES.size())

	for i in GroundSites.SITES.size():
		var s: Array = GroundSites.SITES[i]
		var up: Vector3 = GroundSites.site_up(s[1], s[2])
		_ups_ecef.append(up)
		_tan_masks[i] = tan(deg_to_rad(float(s[5])))
		site_counts[i] = 0
		site_active[i] = true
		_markers.append(_make_marker(up, s[3]))
		# Only radars get a drawn volume. Optical sites are narrow-field
		# telescopes that stare at one patch and track individual objects, so
		# any volume drawn for them is really an arrow saying "pointing up" --
		# it added clutter without adding information. They still appear as
		# markers and still carry exact in-view counts, including the darkness
		# constraint that turns them off in daylight.
		_volumes.append(_make_volume(up, s[3], float(s[4]), float(s[5]))
			if int(s[3]) == GroundSites.Kind.RADAR else null)

func _color_for(kind: int) -> Color:
	return Color(0.42, 0.82, 1.00) if kind == GroundSites.Kind.RADAR \
		else Color(1.00, 0.80, 0.36)

func _make_marker(up: Vector3, kind: int) -> MeshInstance3D:
	var s := SphereMesh.new()
	s.radius = 0.012
	s.height = 0.024
	s.radial_segments = 12
	s.rings = 6
	var m := MeshInstance3D.new()
	m.mesh = s
	m.position = up
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = _color_for(kind)
	m.material_override = mat
	add_child(m)
	return m

## The volume a site can geometrically see: a cone with its apex at the site,
## axis along local zenith, half-angle (90 - elevation mask), out to the nominal
## slant range.
##
## Note how flat and wide these are -- a 3 degree mask gives an 87 degree
## half-angle, so a surveillance radar's access volume really is close to a
## hemisphere. That is not an exaggeration for effect; it is what a horizon mask
## means, and it is why a handful of sites can cover so much of LEO.
##
## Drawn as an open surface rather than a solid: fifteen overlapping solids
## become an opaque mess, while overlapping shells still read as separate
## volumes.
func _make_volume(up: Vector3, kind: int, range_km: float, mask_deg: float) -> MeshInstance3D:
	var half_angle := deg_to_rad(90.0 - mask_deg)
	var slant := RADAR_DRAW_KM / RE_KM

	var height := slant * cos(half_angle)
	var radius := slant * sin(half_angle)

	var st := SurfaceTool.new()
	st.begin(Mesh.PRIMITIVE_TRIANGLES)
	var segments := 48
	for i in segments:
		var a0 := TAU * float(i) / float(segments)
		var a1 := TAU * float(i + 1) / float(segments)
		var p0 := Vector3(cos(a0) * radius, height, sin(a0) * radius)
		var p1 := Vector3(cos(a1) * radius, height, sin(a1) * radius)
		# Both windings, so the shell is visible from inside and out.
		st.add_vertex(Vector3.ZERO); st.add_vertex(p0); st.add_vertex(p1)
		st.add_vertex(Vector3.ZERO); st.add_vertex(p1); st.add_vertex(p0)
	st.generate_normals()

	var m := MeshInstance3D.new()
	m.mesh = st.commit()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	# Very faint: these overlap heavily, and at 15.5 Mpix additive overdraw is
	# the most expensive thing that can be on screen. The rim below is what
	# actually makes each volume legible.
	mat.albedo_color = Color(_color_for(kind), 0.022)
	m.material_override = mat

	# A bright rim at the truncation. Ten translucent volumes pile into an
	# undifferentiated haze, but ten outlined edges still read as ten volumes --
	# the rim is doing the work that the fill cannot.
	var rim := MeshInstance3D.new()
	var torus := TorusMesh.new()
	torus.inner_radius = radius * 0.988
	torus.outer_radius = radius
	torus.rings = 48
	rim.mesh = torus
	var rim_mat := StandardMaterial3D.new()
	rim_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	rim_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	rim_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	rim_mat.albedo_color = Color(_color_for(kind), 0.42)
	rim.material_override = rim_mat
	rim.position = Vector3(0.0, height, 0.0)
	m.add_child(rim)

	# Point local +Y along the site's zenith.
	var axis := Vector3.UP.cross(up)
	m.transform = Transform3D(
		Basis.IDENTITY if axis.length() < 1e-6
			else Basis(axis.normalized(), Vector3.UP.angle_to(up)),
		up)
	add_child(m)
	return m

## Recompute one site's visibility per frame, round-robin.
##
## A full pass is 15 sites x 16k objects. Done in one frame that is a visible
## stutter; spread across frames it is a few hundred microseconds each and the
## whole network refreshes four times a second, which is far faster than the
## picture meaningfully changes.
func update_visibility(unix_seconds: float, gmst: float, sun: Vector3) -> void:
	if field == null or store == null or not store.is_loaded():
		return
	var n := field.catalog.size()
	if _visible_flags.size() != n:
		_visible_flags.resize(n)
		_pending.resize(n)

	for _step in SITES_PER_FRAME:
		_update_one_site(unix_seconds, gmst, sun)

## True once per completed pass, then cleared. Callers use it to avoid redoing
## work that would produce an identical answer.
func consume_updated() -> bool:
	var was := _updated
	_updated = false
	return was

func _update_one_site(unix_seconds: float, gmst: float, sun: Vector3) -> void:
	var site := _cursor % GroundSites.SITES.size()
	_cursor += 1
	var s: Array = GroundSites.SITES[site]

	# Sites are Earth-fixed and the ephemeris is inertial (TEME), so rotate the
	# site into the inertial frame rather than every object into Earth-fixed.
	var up: Vector3 = Basis(Vector3.UP, gmst) * _ups_ecef[site]
	var tan_mask: float = _tan_masks[site]
	var optical: bool = int(s[3]) == GroundSites.Kind.OPTICAL
	var max_r: float = 1.0 + float(s[4]) / RE_KM

	# An optical site in daylight or twilight sees nothing, whatever is overhead.
	var dark := not optical \
		or GroundSites.sun_elevation_deg(up, sun) < DARK_SUN_ELEVATION
	site_active[site] = dark
	if _volumes[site] != null:
		_volumes[site].visible = dark

	var count := 0
	if dark:
		# The hot loop: five sites x ~15,000 objects, every frame. Written with
		# raw floats and no function calls because at 75,000 evaluations a frame
		# both Vector3 construction and GDScript call overhead are measurable --
		# this loop was 24 ms and took the chapter to 30 fps.
		#
		# The arithmetic is GroundSites.is_visible() and is_sunlit() inlined;
		# keep them in step. No square roots: see the derivation there.
		var xyz := field.current_positions
		var active := field.active
		var slots := mini(active.size(), xyz.size() / 4)
		var ux := up.x
		var uy := up.y
		var uz := up.z
		var sx := sun.x
		var sy := sun.y
		var sz := sun.z
		var t2 := tan_mask * tan_mask
		var max_r2 := max_r * max_r
		for slot in slots:
			var c := slot * 4
			var r2 := xyz[c + 3]
			if r2 > max_r2:
				continue
			var px := xyz[c]
			var py := xyz[c + 1]
			var pz := xyz[c + 2]
			var d := px * ux + py * uy + pz * uz
			if d <= 1.0:
				continue                    # at or below the local horizon
			var e := d - 1.0
			if e * e < t2 * (r2 - d * d):
				continue                    # inside the elevation mask
			if optical:
				# Optical sensors see reflected sunlight: a target in the
				# Earth's shadow is invisible even overhead on a clear night.
				var along := px * sx + py * sy + pz * sz
				if along < 0.0 and r2 - along * along <= 1.0:
					continue
			count += 1
			_pending[active[slot]] = 1
	site_counts[site] = count

	# One full pass round the network: publish and start the next.
	if _cursor % GroundSites.SITES.size() == 0:
		_visible_flags = _pending.duplicate()
		for i in _pending.size():
			_pending[i] = 0
		var t := 0
		for c in site_counts:
			t += c
		total_visible = t
		_updated = true

func visible_indices() -> PackedInt32Array:
	var out := PackedInt32Array()
	for i in _visible_flags.size():
		if _visible_flags[i] != 0:
			out.append(i)
	return out

## Sites ranked by what they can currently see, for the panel.
func ranked_sites(limit: int) -> Array:
	var rows := []
	for i in GroundSites.SITES.size():
		rows.append({"name": GroundSites.SITES[i][0], "count": site_counts[i],
			"kind": GroundSites.SITES[i][3], "active": site_active[i]})
	rows.sort_custom(func(a, b): return a["count"] > b["count"])
	return rows.slice(0, limit)
