class_name SelectionController
extends Node3D
## Reticle-based picking.
##
## Godot's get_viewport() mouse picking does not work in stereo mode -- the
## composited window is two eye images side by side, so viewport coordinates
## have no single meaning. Selection is therefore a ray from the head along the
## rig's view direction, matched against the nearest satellite by angle.

signal selection_changed(catalog_index: int)

## Half-angle of the pick cone. Generous, because on a 6 m wall the presenter is
## aiming a reticle from across the room, not pixel-hunting with a cursor.
const PICK_CONE_RAD := 0.035

var field: SatelliteField
var rig: ContentRig
var catalog: CatalogStore
var camera: CameraDirector
var clock: SimClock

var selected: int = -1
var _marker: MeshInstance3D
var _label: Label3D
var _reticle: MeshInstance3D

func _ready() -> void:
	_build_reticle()
	_build_marker()
	set_process(true)

func _build_reticle() -> void:
	var torus := TorusMesh.new()
	torus.inner_radius = 0.010
	torus.outer_radius = 0.013
	_reticle = MeshInstance3D.new()
	_reticle.mesh = torus
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(1.0, 1.0, 1.0, 0.55)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_reticle.material_override = m
	add_child(_reticle)

func _build_marker() -> void:
	var ring := TorusMesh.new()
	ring.inner_radius = 0.030
	ring.outer_radius = 0.038
	_marker = MeshInstance3D.new()
	_marker.mesh = ring
	var m := StandardMaterial3D.new()
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.albedo_color = Color(1.0, 0.95, 0.5)
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	_marker.material_override = m
	_marker.visible = false
	add_child(_marker)

	_label = Label3D.new()
	_label.font_size = 40
	_label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	_label.modulate = Color(1.0, 0.95, 0.5)
	_label.outline_size = 10
	_label.visible = false
	add_child(_label)

func clear() -> void:
	selected = -1
	_marker.visible = false
	_label.visible = false
	selection_changed.emit(-1)

func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("select_object"):
		_pick()

func _pick() -> void:
	if field == null or field.active.is_empty():
		return
	var head := camera.head_transform()
	var origin := head.origin
	var dir := -head.basis.z
	var t: float = _clock_time()

	var best := -1
	var best_angle := PICK_CONE_RAD
	for i in field.active:
		var world: Vector3 = rig.to_global(field.rendered_position(i, t))
		var to_obj := world - origin
		# Behind the viewer, or effectively at the eye -- not selectable.
		if to_obj.length_squared() < 0.0001 or to_obj.dot(dir) <= 0.0:
			continue
		var angle := to_obj.normalized().angle_to(dir)
		if angle < best_angle:
			best_angle = angle
			best = i

	selected = best
	_marker.visible = best >= 0
	_label.visible = best >= 0
	if best >= 0:
		_label.text = String(catalog.objects[best].get("name", ""))
	selection_changed.emit(best)

func _clock_time() -> float:
	return clock.now_unix if clock != null else 0.0

## Parented to the head, not copied from it -- same reason as the panels. The
## reticle sits on the wall plane so it fuses at the physical screen depth,
## which is where it is comfortable to rest the eyes.
func attach_to_head(head: Node3D) -> void:
	if head == null or _reticle == null:
		return
	if _reticle.get_parent() != head:
		_reticle.get_parent().remove_child(_reticle)
		head.add_child(_reticle)
	_reticle.transform = Transform3D(Basis(Vector3.RIGHT, PI / 2.0),
		Vector3(0.0, 0.0, -CameraDirector.WALL_DISTANCE))


func _process(_delta: float) -> void:
	if selected < 0 or field == null:
		return
	# Labels must track their target's depth exactly. A label left at screen
	# depth while its target sits half a metre deeper forces the eyes to fuse
	# two different distances at once, which is genuinely uncomfortable.
	var world: Vector3 = rig.to_global(field.rendered_position(selected, _clock_time()))
	_marker.global_position = world
	_label.global_position = world + Vector3(0.0, 0.06, 0.0)
	# Constant apparent size regardless of how far the camera has dollied.
	var d: float = maxf(camera.distance_to(world), 0.2)
	_marker.scale = Vector3.ONE * d * 0.035
