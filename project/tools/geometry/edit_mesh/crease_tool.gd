extends ViewportController
class_name CreaseTool

const PICK_EDGE_PX   := 12.0
const DRAG_SCALE     := 0.05   # crease units per pixel

var _hovered_edge:      int   = -1
var _dragging:          bool  = false
var _drag_edge:         int   = -1
var _drag_start_crease: float = 0.0
var _drag_accum:        float = 0.0

func _init() -> void:
	tool_name = "Crease"

func handle_hover(mouse_pos: Vector2, hem: HalfEdgeMesh, camera: Camera3D) -> void:
	if _dragging:
		return
	var best_idx  := -1
	var best_dist := PICK_EDGE_PX * PICK_EDGE_PX
	for i in hem.get_edge_count():
		var twin: int = hem.get_half_edge_twin(i)
		if twin != -1 and i > twin:
			continue
		var p0 := object_transform * hem.get_vertex_position(hem.get_half_edge_vertex(i))
		var p1 := object_transform * hem.get_vertex_position(hem.get_half_edge_vertex(hem.get_half_edge_next(i)))
		var s0 := camera.unproject_position(p0)
		var s1 := camera.unproject_position(p1)
		var d  := _dist_sq_seg(mouse_pos, s0, s1)
		if d < best_dist:
			best_dist = d
			best_idx  = i
	_hovered_edge = best_idx

func _target_edges() -> PackedInt32Array:
	return selected_edges

func handle_input(event: InputEvent, hem: HalfEdgeMesh, _camera: Camera3D) -> bool:
	if event is InputEventMouseButton:
		match event.button_index:
			MOUSE_BUTTON_MIDDLE:
				if event.pressed:
					var targets := _target_edges()
					if targets.is_empty(): return false
					_dragging          = true
					_drag_edge         = targets[0]
					_drag_start_crease = hem.get_crease(targets[0])
					_drag_accum        = 0.0
					return true
				elif not event.pressed and _dragging:
					_dragging = false
					return true
	if event is InputEventMouseMotion and _dragging:
		_drag_accum += event.relative.x
		var new_crease := clampf(_drag_start_crease + _drag_accum * DRAG_SCALE, 0.0, 10.0)
		for e in _target_edges():
			hem.set_crease(e, new_crease)
		return true
	return false

func draw_preview(im: ImmediateMesh, hem: HalfEdgeMesh) -> void:
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	var draw_edge := _drag_edge if _dragging else _hovered_edge
	if draw_edge != -1:
		var v0 := hem.get_half_edge_vertex(draw_edge)
		var v1 := hem.get_half_edge_vertex(hem.get_half_edge_next(draw_edge))
		im.surface_set_color(Color(1.0, 0.9, 0.2))
		im.surface_add_vertex(hem.get_vertex_position(v0))
		im.surface_set_color(Color(1.0, 0.9, 0.2))
		im.surface_add_vertex(hem.get_vertex_position(v1))
	else:
		im.surface_set_color(Color.TRANSPARENT); im.surface_add_vertex(Vector3.ZERO)
		im.surface_set_color(Color.TRANSPARENT); im.surface_add_vertex(Vector3.ZERO)
	im.surface_end()
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	im.surface_set_color(Color.TRANSPARENT); im.surface_add_vertex(Vector3.ZERO)
	im.surface_set_color(Color.TRANSPARENT); im.surface_add_vertex(Vector3.ZERO)
	im.surface_set_color(Color.TRANSPARENT); im.surface_add_vertex(Vector3.ZERO)
	im.surface_end()

func on_deactivate() -> void:
	_hovered_edge = -1
	_dragging     = false
	_drag_edge    = -1
