class_name InputActions
extends RefCounted
## Registers the input map at runtime.
##
## Deliberately code rather than project.godot's [input] section: that format
## serialises Object(InputEventKey, ...) literals which are easy to corrupt by
## hand and impossible to review. Here the whole control scheme is one table.
##
## The viewer never moves -- every action transforms the CONTENT. See
## CameraDirector for why the camera, not the content, is what moves.

const RIGHT_STICK_X := JOY_AXIS_RIGHT_X
const RIGHT_STICK_Y := JOY_AXIS_RIGHT_Y
const LEFT_STICK_Y := JOY_AXIS_LEFT_Y

static func register() -> void:
	_axis("rig_orbit_left",  RIGHT_STICK_X, -1.0)
	_axis("rig_orbit_right", RIGHT_STICK_X,  1.0)
	_axis("rig_orbit_up",    RIGHT_STICK_Y, -1.0)
	_axis("rig_orbit_down",  RIGHT_STICK_Y,  1.0)

	_action("rig_zoom_in",  [_key(KEY_W)], [], [[LEFT_STICK_Y, -1.0]])
	_action("rig_zoom_out", [_key(KEY_S)], [], [[LEFT_STICK_Y,  1.0]])

	_action("chapter_next", [_key(KEY_RIGHT)], [JOY_BUTTON_DPAD_RIGHT])
	_action("chapter_prev", [_key(KEY_LEFT)],  [JOY_BUTTON_DPAD_LEFT])
	_action("time_pause",   [_key(KEY_SPACE)], [JOY_BUTTON_A])
	_action("time_faster",  [_key(KEY_BRACKETRIGHT)], [JOY_BUTTON_RIGHT_SHOULDER])
	_action("time_slower",  [_key(KEY_BRACKETLEFT)],  [JOY_BUTTON_LEFT_SHOULDER])
	_action("toggle_fly", [_key(KEY_F)], [JOY_BUTTON_Y])

static func _key(keycode: Key) -> InputEventKey:
	var e := InputEventKey.new()
	e.physical_keycode = keycode
	return e

static func _fresh(action: String) -> void:
	if InputMap.has_action(action):
		InputMap.erase_action(action)
	InputMap.add_action(action, 0.2)

static func _axis(action: String, axis: JoyAxis, value: float) -> void:
	_fresh(action)
	var e := InputEventJoypadMotion.new()
	e.axis = axis
	e.axis_value = value
	InputMap.action_add_event(action, e)

static func _action(action: String, keys: Array, buttons: Array,
		axes: Array = [], mouse_buttons: Array = []) -> void:
	_fresh(action)
	for k in keys:
		InputMap.action_add_event(action, k)
	for b in buttons:
		var e := InputEventJoypadButton.new()
		e.button_index = b
		InputMap.action_add_event(action, e)
	for a in axes:
		var m := InputEventJoypadMotion.new()
		m.axis = a[0]
		m.axis_value = a[1]
		InputMap.action_add_event(action, m)
	for mb in mouse_buttons:
		var e := InputEventMouseButton.new()
		e.button_index = mb
		InputMap.action_add_event(action, e)
