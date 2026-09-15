class_name RigController
extends Node3D
## Transforms the content, never the viewer.
##
## StereoWallDisplay derives the virtual screen corners from the camera pivot
## every frame, so the wall is head-RELATIVE. Moving or turning the player
## therefore shears the whole scene against a wall that is physically fixed.
## The addon is neutralised by zeroing move_speed / look_sensitivity /
## controller_look_speed in main.tscn; this node drives the content instead.
##
## This node also owns the stereo comfort clamp -- see _effective_distance().

## Physical wall geometry, from the StereoWallDisplay defaults.
const WALL_DISTANCE := 2.282        ## Viewer to wall plane, metres.
const EYE_SEPARATION := 0.063       ## Interocular distance, metres.

## Hard floor on how close rendered content may come to the viewer.
## Screen parallax is p = IOD * (1 - D/z). At z = 1.5 m that is -33 mm, already
## at the edge of comfortable fusion; 1.0 m gives -81 mm, which many viewers
## cannot fuse at all. Nothing is allowed inside this.
const MIN_CONTENT_DISTANCE := 1.5

@export var orbit_speed := 1.6
@export var dolly_speed := 1.4
## Preferred distance from the viewer to the rig origin. A FLOOR, not a fixed
## value -- see _effective_distance().
@export var center_distance := 3.0
@export var rig_scale := 0.75
@export var min_scale := 0.05
## Zoom is not limited by comfort (distance absorbs that), so this is only a
## sanity stop. The globe reaches an apparent-size asymptote long before it.
@export var max_scale := 12.0
## Extra clearance beyond MIN_CONTENT_DISTANCE, putting the nearest object at
## about 2.05 m -- roughly 23 cm in front of the wall plane, i.e. -7 mm of
## parallax.
##
## This is set by the WINDOW VIOLATION constraint, not by fusion comfort. Once
## the globe is large enough to be worth looking at, the orbital shell around it
## necessarily overruns a 2.04 m tall wall, so it WILL be cut by the frame edge.
## Cropping content that sits behind the screen is fine -- that is just looking
## through a window. Cropping content that floats in front of the screen is the
## contradiction that makes viewers' eyes hurt. Keeping the near limit to a few
## millimetres of negative parallax means the overrun is harmless.
@export var comfort_margin := 0.55

var field: SatelliteField
var head_position: Vector3 = Vector3(0.0, 1.64, 0.0)
var head_yaw: float = 0.0

var _yaw := 0.0
var _pitch := 0.2
var _dragging := false

func _ready() -> void:
	set_process(true)

## Largest content radius in Earth radii, after exaggeration. The field caches
## this; it only changes on a filter or exaggeration change.
func _content_radius() -> float:
	if field == null or field.catalog.is_empty() or field.active.is_empty():
		return 1.0
	return field.max_content_radius()

## Distance from viewer to rig origin, guaranteeing comfort by CONSTRUCTION.
##
## The earlier design fixed the distance and clamped the scale, which capped
## zoom at roughly the default framing -- at the LEO chapter the maximum safe
## scale was 0.838 against a default of 0.75, so zoom did almost nothing.
##
## Instead, zooming in pushes the content further away by exactly enough to keep
## the nearest object outside the floor. That is an ordinary dolly-zoom: the
## globe still grows on screen (apparent half-angle atan(s / (floor + r*s)),
## rising toward atan(1/r)), while the near clearance never shrinks.
static func safe_center_distance(preferred: float, scale: float,
		content_radius: float, margin: float) -> float:
	return maxf(preferred, MIN_CONTENT_DISTANCE + margin + content_radius * scale)

func _effective_distance() -> float:
	return safe_center_distance(center_distance, rig_scale, _content_radius(),
		comfort_margin)

func clamp_scale(s: float) -> float:
	return clampf(s, min_scale, max_scale)

## Screen parallax in millimetres for content at distance z. Negative is in
## front of the wall.
func parallax_mm(z: float) -> float:
	if z <= 0.01:
		return -999.0
	return EYE_SEPARATION * (1.0 - WALL_DISTANCE / z) * 1000.0

func nearest_content_distance() -> float:
	return _effective_distance() - _content_radius() * rig_scale

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_dragging = event.pressed
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			rig_scale = clamp_scale(rig_scale * 1.10)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			rig_scale = clamp_scale(rig_scale / 1.10)
	elif event is InputEventMouseMotion and _dragging:
		_orbit(-event.relative.x * 0.004, -event.relative.y * 0.004)

func _orbit(dyaw: float, dpitch: float) -> void:
	_yaw = fposmod(_yaw + dyaw, TAU)
	# Stop short of the poles: at the singularity the globe's spin axis snaps
	# and, in stereo, that reads as the whole scene lurching sideways.
	_pitch = clampf(_pitch + dpitch, -1.45, 1.45)

func _process(delta: float) -> void:
	var stick := Input.get_vector("rig_orbit_left", "rig_orbit_right",
		"rig_orbit_up", "rig_orbit_down")
	if stick.length() > 0.001:
		_orbit(-stick.x * orbit_speed * delta, -stick.y * orbit_speed * delta)

	var dolly := Input.get_axis("rig_zoom_out", "rig_zoom_in")
	if absf(dolly) > 0.001:
		# Exponential so the feel is constant across three orders of scale.
		rig_scale = clamp_scale(rig_scale * exp(dolly * dolly_speed * delta))

	_apply()

func _apply() -> void:
	rig_scale = clamp_scale(rig_scale)
	var forward := Basis(Vector3.UP, head_yaw) * Vector3(0.0, 0.0, -1.0)
	var origin := head_position + forward * _effective_distance()
	var basis := Basis(Vector3.UP, _yaw + head_yaw) * Basis(Vector3.RIGHT, _pitch)
	transform = Transform3D(basis.scaled(Vector3.ONE * rig_scale), origin)

## Move to a chapter preset. Distance is derived, so the tween cannot pass
## through an unsafe state even mid-transition.
func goto(p_center_distance: float, p_scale: float, p_yaw: float, p_pitch: float,
		duration: float) -> Tween:
	var tw := create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC) \
		.set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(self, "center_distance", p_center_distance, duration)
	tw.tween_property(self, "rig_scale", clamp_scale(p_scale), duration)
	tw.tween_property(self, "_yaw", p_yaw, duration)
	tw.tween_property(self, "_pitch", p_pitch, duration)
	return tw
