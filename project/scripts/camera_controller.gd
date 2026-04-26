extends Camera3D

@export var orbit_speed  := 0.005
@export var pan_speed    := 0.002
@export var zoom_speed   := 0.3
@export var min_distance := 0.5
@export var max_distance := 100.0

var _pivot       := Vector3.ZERO
var _distance    := 4.0
var _yaw         := 0.0
var _pitch       := 0.3

enum Mode { NONE, ORBIT, PAN }
var _mode := Mode.NONE

func _ready() -> void:
	_apply_transform()

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton:
		var mod := Input.is_key_pressed(Keymap.CAMERA_MODIFIER)
		match event.button_index:
			Keymap.CAMERA_ORBIT_BTN:
				_mode = Mode.ORBIT if (mod and event.pressed) else Mode.NONE
				if mod and event.pressed:
					get_viewport().set_input_as_handled()
			Keymap.CAMERA_PAN_BTN:
				_mode = Mode.PAN if (mod and event.pressed) else Mode.NONE
				if mod and event.pressed:
					get_viewport().set_input_as_handled()
			Keymap.CAMERA_DOLLY_BTN:
				_mode = Mode.NONE
		if event.is_action_pressed("cam_zoom_in"):
			_distance = clampf(_distance - zoom_speed * _distance * 0.3, min_distance, max_distance)
			_apply_transform()
			get_viewport().set_input_as_handled()
		elif event.is_action_pressed("cam_zoom_out"):
			_distance = clampf(_distance + zoom_speed * _distance * 0.3, min_distance, max_distance)
			_apply_transform()
			get_viewport().set_input_as_handled()

	elif event is InputEventMouseMotion:
		if not Input.is_key_pressed(Keymap.CAMERA_MODIFIER):
			_mode = Mode.NONE
			return

		match _mode:
			Mode.ORBIT:
				_yaw   -= event.relative.x * orbit_speed
				_pitch += event.relative.y * orbit_speed
				_pitch  = clampf(_pitch, -PI * 0.49, PI * 0.49)
				_apply_transform()
				get_viewport().set_input_as_handled()
			Mode.PAN:
				var right := global_basis.x
				var up    := global_basis.y
				_pivot -= right * event.relative.x * pan_speed * _distance
				_pivot += up    * event.relative.y * pan_speed * _distance
				_apply_transform()
				get_viewport().set_input_as_handled()

		if Input.is_mouse_button_pressed(Keymap.CAMERA_DOLLY_BTN):
			var delta: float = event.relative.x - event.relative.y
			_distance = clampf(_distance - delta * zoom_speed * 0.01 * _distance,
								min_distance, max_distance)
			_apply_transform()
			get_viewport().set_input_as_handled()

func _apply_transform() -> void:
	var offset := Vector3(
		_distance * cos(_pitch) * sin(_yaw),
		_distance * sin(_pitch),
		_distance * cos(_pitch) * cos(_yaw)
	)
	global_position = _pivot + offset
	look_at(_pivot, Vector3.UP)
