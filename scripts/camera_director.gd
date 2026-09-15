class_name CameraDirector
extends Node
## Moves the viewer. The camera really does move -- it orbits a world-space
## target by driving StereoWallDisplay's player body.
##
## The addon builds its virtual screen and both eye positions from one head
## pose, so they translate and rotate RIGIDLY together. That models a viewer
## with a wall fixed in front of them navigating the world, which is the
## standard non-head-tracked powerwall arrangement: moving the player carries
## the whole viewing apparatus through the scene and the projection stays
## correct. (It would only be wrong under head TRACKING, where the head moves
## relative to a physically fixed wall.)
##
## We drive the player body rather than using the addon's own WASD/mouse-look
## because orbit-around-target is far better for a presenter than free flight.
## FREE_FLY hands control back to the addon for when you do want to fly.

enum Mode { ORBIT, FREE_FLY }

## Physical wall geometry, from the StereoWallDisplay defaults.
const WALL_DISTANCE := 2.282        ## Viewer to wall plane, metres.
const EYE_SEPARATION := 0.063       ## Interocular distance, metres.
## Below this, screen parallax passes -33 mm and fusion gets hard for many
## viewers. Chapter presets stay outside it; free navigation may cross it, and
## the HUD says so rather than the camera refusing to move.
const MIN_CONTENT_DISTANCE := 1.5

## The addon parents its camera pivot at this height on the player body.
const PIVOT_HEIGHT := 1.64

@export var orbit_speed := 1.8
@export var dolly_speed := 1.4
@export var min_distance := 0.15
@export var max_distance := 400.0

var wall: Node                       ## StereoWallDisplay
var target: Vector3 = Vector3.ZERO   ## World point we orbit.
var mode: Mode = Mode.ORBIT

var azimuth := 0.0
var elevation := 0.2
var distance := 4.4

var _dragging := false
var _body: CharacterBody3D
var _pivot: Node3D

func _ready() -> void:
	set_process(true)

## The addon creates these in its own _ready() and recreates them on _rebuild()
## (which the --stereo flag triggers), so look them up rather than caching.
func _resolve() -> bool:
	if _body != null and is_instance_valid(_body) and _pivot != null \
			and is_instance_valid(_pivot):
		return true
	if wall == null:
		return false
	_body = wall.get_node_or_null("_PlayerBody") as CharacterBody3D
	_pivot = wall.get_node_or_null("_PlayerBody/_CameraPivot") as Node3D
	return _body != null and _pivot != null

func set_mode(m: Mode) -> void:
	mode = m
	if wall == null:
		return
	# In FREE_FLY the addon's own input drives the body; in ORBIT we do, so its
	# gains are zeroed to stop the two fighting over the same transform.
	var free := m == Mode.FREE_FLY
	wall.move_speed = 4.0 if free else 0.0
	wall.look_sensitivity = 0.002 if free else 0.0
	wall.controller_look_speed = 0.05 if free else 0.0
	if not free:
		_sync_from_body()

func toggle_mode() -> void:
	set_mode(Mode.FREE_FLY if mode == Mode.ORBIT else Mode.ORBIT)

## Adopt the current body pose as orbit state, so switching back from free
## flight does not snap the view.
func _sync_from_body() -> void:
	if not _resolve():
		return
	var eye := _pivot.global_position
	var to_target := target - eye
	distance = clampf(to_target.length(), min_distance, max_distance)
	if distance > 0.001:
		var d := to_target / distance
		azimuth = atan2(-d.x, -d.z)
		elevation = clampf(asin(clampf(-d.y, -1.0, 1.0)), -1.45, 1.45)

func head_transform() -> Transform3D:
	if not _resolve():
		return Transform3D(Basis.IDENTITY, Vector3(0.0, PIVOT_HEIGHT, 0.0))
	return _pivot.global_transform

func eye_position() -> Vector3:
	return head_transform().origin

func distance_to(point: Vector3) -> float:
	return eye_position().distance_to(point)

## Screen parallax in millimetres for content at distance z. Negative is in
## front of the wall plane.
static func parallax_mm(z: float) -> float:
	if z <= 0.01:
		return -999.0
	return EYE_SEPARATION * (1.0 - WALL_DISTANCE / z) * 1000.0

func _unhandled_input(event: InputEvent) -> void:
	if mode != Mode.ORBIT:
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_LEFT:
			_dragging = event.pressed
		elif event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			distance = clampf(distance / 1.10, min_distance, max_distance)
		elif event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			distance = clampf(distance * 1.10, min_distance, max_distance)
	elif event is InputEventMouseMotion and _dragging:
		_orbit(event.relative.x * 0.005, event.relative.y * 0.005)

func _orbit(d_az: float, d_el: float) -> void:
	azimuth = fposmod(azimuth + d_az, TAU)
	# Stop short of the poles: at the singularity the up vector flips and, in
	# stereo, that reads as the whole scene lurching sideways.
	elevation = clampf(elevation + d_el, -1.45, 1.45)

func _process(delta: float) -> void:
	if mode != Mode.ORBIT or not _resolve():
		return

	var stick := Input.get_vector("rig_orbit_left", "rig_orbit_right",
		"rig_orbit_up", "rig_orbit_down")
	if stick.length() > 0.001:
		_orbit(stick.x * orbit_speed * delta, stick.y * orbit_speed * delta)

	var dolly := Input.get_axis("rig_zoom_out", "rig_zoom_in")
	if absf(dolly) > 0.001:
		# Exponential so the feel is constant across three orders of distance.
		distance = clampf(distance * exp(-dolly * dolly_speed * delta),
			min_distance, max_distance)

	_apply()

func _apply() -> void:
	if not _resolve():
		return
	# Spherical position around the target, then aim back at it. The addon reads
	# yaw off the body and pitch off the pivot, so they must be set separately --
	# a look_at() on the pivot alone would leave the wall's yaw wrong.
	var dir := Vector3(
		-sin(azimuth) * cos(elevation),
		-sin(elevation),
		-cos(azimuth) * cos(elevation))
	var eye := target - dir * distance
	_body.velocity = Vector3.ZERO
	_body.global_position = eye - Vector3(0.0, PIVOT_HEIGHT, 0.0)
	_body.rotation.y = azimuth
	# NEGATIVE elevation. The addon builds its head basis as
	# Basis(UP, yaw) * Basis(RIGHT, pitch), whose forward (-Z) has
	# y = +sin(pitch) -- it pitches UP for positive pitch. Positive elevation
	# puts the eye ABOVE the target, so the view has to tilt DOWN to hold it in
	# frame. Getting this backwards leaves the subject low in frame rather than
	# obviously broken, which is how it first shipped.
	_pivot.rotation.x = -elevation

func goto(p_azimuth: float, p_elevation: float, p_distance: float,
		duration: float) -> void:
	# Take the short way round rather than unwinding the long way.
	var az := azimuth + wrapf(p_azimuth - azimuth, -PI, PI)
	if duration <= 0.0:
		azimuth = az
		elevation = p_elevation
		distance = p_distance
		_apply()
		return
	var tw := create_tween().set_parallel(true).set_trans(Tween.TRANS_CUBIC) \
		.set_ease(Tween.EASE_IN_OUT)
	tw.tween_property(self, "azimuth", az, duration)
	tw.tween_property(self, "elevation", p_elevation, duration)
	tw.tween_property(self, "distance", p_distance, duration)
