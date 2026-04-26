class_name Keymap
extends RefCounted

# Camera — modifier-based, not action-based
const CAMERA_MODIFIER  := KEY_ALT
const CAMERA_ORBIT_BTN := MOUSE_BUTTON_LEFT
const CAMERA_PAN_BTN   := MOUSE_BUTTON_MIDDLE
const CAMERA_DOLLY_BTN := MOUSE_BUTTON_RIGHT

static func setup() -> void:
	# Modes
	_key("mode_object",    KEY_1)
	_key("mode_vertex",    KEY_2)
	_key("mode_edge",      KEY_3)
	_key("mode_face",      KEY_4)
	# Tools
	_key("tool_move",      KEY_W)
	_key("tool_sculpt",    KEY_S)
	_key("tool_flatten",   KEY_F)
	_key("tool_edge_loop", KEY_R, true)
	_key("tool_none",      KEY_Q)
	# Mesh operations
	_key("op_extrude",     KEY_E)
	_key("op_delete",      KEY_X)
	# History
	_key("undo",           KEY_Z, true)
	_key("redo",           KEY_Z, true, true)
	# Camera zoom
	_mouse("cam_zoom_in",  MOUSE_BUTTON_WHEEL_UP)
	_mouse("cam_zoom_out", MOUSE_BUTTON_WHEEL_DOWN)

static func _key(action: String, key: Key, ctrl := false, shift := false) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var ev := InputEventKey.new()
	ev.keycode       = key
	ev.ctrl_pressed  = ctrl
	ev.shift_pressed = shift
	InputMap.action_add_event(action, ev)

static func _mouse(action: String, button: MouseButton) -> void:
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var ev := InputEventMouseButton.new()
	ev.button_index = button
	InputMap.action_add_event(action, ev)
