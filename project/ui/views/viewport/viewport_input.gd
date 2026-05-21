extends SubViewportContainer
class_name ViewportInput

var world:       Node3D   = null
var camera_ctrl: Camera3D = null

@onready var _subvp: SubViewport = $SubViewport

const DRAG_THRESHOLD := 5.0

var _pressing    := false
var _dragging    := false
var _press_local := Vector2.ZERO
var _cur_local   := Vector2.ZERO
var _press_subvp := Vector2.ZERO
var _cur_subvp   := Vector2.ZERO

func _local_to_subvp(local_pos: Vector2) -> Vector2:
	var sz := get_size()
	if sz.x <= 0.0: return local_pos
	return local_pos / sz * Vector2(_subvp.size)

func _gui_input(event: InputEvent) -> void:
	if not event is InputEventMouse: return

	# Camera gets first pass — ALT+mouse, scroll wheel
	if camera_ctrl != null and camera_ctrl.handle_mouse(event):
		accept_event()
		return

	var subvp_pos := _local_to_subvp(event.position)

	# Active tool gizmos and mesh tools (crease MMB, etc.)
	if world != null and world.handle_tool_mouse(event):
		accept_event()
		return

	# Marquee / click selection
	if _handle_selection(event, event.position, subvp_pos):
		accept_event()

func _handle_selection(event: InputEvent, local_pos: Vector2, subvp_pos: Vector2) -> bool:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_pressing    = true
			_dragging    = false
			_press_local = local_pos
			_press_subvp = subvp_pos
			return true
		elif _pressing:
			_pressing = false
			if _dragging:
				_dragging = false
				queue_redraw()
				world.marquee_select(Rect2(_press_subvp, _cur_subvp - _press_subvp).abs(), event.shift_pressed)
			else:
				world.click_select(_press_subvp, event.shift_pressed)
			return true

	elif event is InputEventMouseMotion and _pressing:
		_cur_local = local_pos
		_cur_subvp = subvp_pos
		if not _dragging and local_pos.distance_to(_press_local) > DRAG_THRESHOLD:
			_dragging = true
		if _dragging:
			queue_redraw()
		return true

	return false

func _draw() -> void:
	if not _dragging: return
	var r := Rect2(_press_local, _cur_local - _press_local).abs()
	draw_rect(r, Color(1.0, 0.6, 0.1, 0.08), true)
	draw_rect(r, Color(1.0, 0.6, 0.1, 0.9),  false)
