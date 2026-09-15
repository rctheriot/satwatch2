class_name ContentRig
extends Node3D
## Holds the world at a chosen scale, fixed at the world origin.
##
## Earlier this node also carried the viewpoint: the camera was parked and this
## rig was rotated and pushed around to fake camera motion. That was based on a
## misreading of the wall addon. StereoWallDisplay derives its virtual screen
## and both eye positions from a single head pose, so they move rigidly
## together -- moving the player carries the whole viewing apparatus through the
## world and the off-axis projection stays correct. The camera can simply move;
## see CameraDirector.
##
## So this node now does one thing: scale. The content sits at the origin and
## stays there, which also means its basis is identity, so inertial vectors
## (the sun, the starfield) need no correction.

@export var content_scale: float = 1.45:
	set(v):
		content_scale = maxf(v, 0.0001)
		scale = Vector3.ONE * content_scale

var field: SatelliteField

func _ready() -> void:
	position = Vector3.ZERO
	rotation = Vector3.ZERO
	scale = Vector3.ONE * content_scale

## Outermost visible content radius in world metres, after exaggeration.
func content_radius_m() -> float:
	if field == null or field.catalog.is_empty() or field.active.is_empty():
		return content_scale
	return field.max_content_radius() * content_scale
