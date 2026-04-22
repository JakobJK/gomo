extends SculptTool
class_name FlattenTool

func _init() -> void:
	tool_name = "Flatten"
	brush_strength = 1.0  # strong enough to flatten in a single stroke

func handle_input(event: InputEvent, hem: HalfEdgeMesh, camera: Camera3D) -> bool:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_is_painting = true
			if _hit_face != -1:
				hem.begin_tilt_stroke()
				hem.flatten_at(_hit_pos, brush_strength, brush_size)
				return true
		else:
			hem.end_tilt_stroke()
			_is_painting = false
		return false

	if event is InputEventMouseMotion:
		_update_hit(event.position, hem, camera)
		if _is_painting and _hit_face != -1:
			hem.flatten_at(_hit_pos, brush_strength, brush_size)
			return true

	return false
