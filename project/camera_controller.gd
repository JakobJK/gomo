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
		var alt := Input.is_key_pressed(KEY_ALT)
		match event.button_index:
			MOUSE_BUTTON_LEFT:
				_mode = Mode.ORBIT if (alt and event.pressed) else Mode.NONE
			MOUSE_BUTTON_MIDDLE:
				_mode = Mode.PAN  if (alt and event.pressed) else Mode.NONE
			MOUSE_BUTTON_RIGHT:
				_mode = Mode.NONE
				if alt and event.pressed:
					_mode = Mode.NONE  # handled below via scroll-like drag
			MOUSE_BUTTON_WHEEL_UP:
				_distance = clampf(_distance - zoom_speed * _distance * 0.3, min_distance, max_distance)
				_apply_transform()
				get_viewport().set_input_as_handled()
			MOUSE_BUTTON_WHEEL_DOWN:
				_distance = clampf(_distance + zoom_speed * _distance * 0.3, min_distance, max_distance)
				_apply_transform()
				get_viewport().set_input_as_handled()

	elif event is InputEventMouseMotion:
		var alt := Input.is_key_pressed(KEY_ALT)
		if not alt:
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

		# Alt + RMB drag = dolly zoom
		if Input.is_mouse_button_pressed(MOUSE_BUTTON_RIGHT):
			_distance = clampf(_distance - event.relative.y * zoom_speed * 0.01 * _distance,
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
