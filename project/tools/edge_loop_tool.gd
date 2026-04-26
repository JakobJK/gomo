extends ModellingTool
class_name EdgeLoopTool

const PICK_EDGE_PX := 12.0

var _hovered_edge: int = -1
var _loop_edges:   Array[int] = []

func _init() -> void:
	tool_name = "Insert Edge Loop"

func handle_hover(mouse_pos: Vector2, hem: HalfEdgeMesh, camera: Camera3D) -> void:
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
		var d  := _dist_sq_point_segment(mouse_pos, s0, s1)
		if d < best_dist:
			best_dist = d
			best_idx  = i

	if best_idx != _hovered_edge:
		_hovered_edge = best_idx
		if _hovered_edge != -1:
			_loop_edges = _find_loop(hem, _hovered_edge)
		else:
			_loop_edges.clear()

func handle_input(event: InputEvent, _hem: HalfEdgeMesh, _camera: Camera3D) -> bool:
	if event is InputEventMouseButton \
			and event.button_index == MOUSE_BUTTON_LEFT \
			and event.pressed \
			and _hovered_edge != -1:
		# TODO: call hem.insert_edge_loop(_hovered_edge) once C++ side is implemented
		return true
	return false

func draw_preview(im: ImmediateMesh, hem: HalfEdgeMesh) -> void:
	const _COL := Color(0.2, 1.0, 0.4)
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	if _loop_edges.size() > 0:
		for he in _loop_edges:
			var v0 := hem.get_half_edge_vertex(he)
			var v1 := hem.get_half_edge_vertex(hem.get_half_edge_next(he))
			var p0 := hem.get_vertex_position(v0)
			var p1 := hem.get_vertex_position(v1)
			im.surface_set_color(_COL); im.surface_add_vertex(p0.lerp(p1, 0.5))
			var he_next := hem.get_half_edge_next(he)
			var he_opp  := hem.get_half_edge_next(he_next)
			var vo0 := hem.get_half_edge_vertex(he_opp)
			var vo1 := hem.get_half_edge_vertex(hem.get_half_edge_next(he_opp))
			im.surface_set_color(_COL)
			im.surface_add_vertex(
				hem.get_vertex_position(vo0).lerp(hem.get_vertex_position(vo1), 0.5))
	else:
		im.surface_set_color(Color.TRANSPARENT)
		im.surface_add_vertex(Vector3.ZERO)
		im.surface_set_color(Color.TRANSPARENT)
		im.surface_add_vertex(Vector3.ZERO)
	im.surface_end()
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	im.surface_set_color(Color.TRANSPARENT)
	im.surface_add_vertex(Vector3.ZERO)
	im.surface_set_color(Color.TRANSPARENT)
	im.surface_add_vertex(Vector3.ZERO)
	im.surface_set_color(Color.TRANSPARENT)
	im.surface_add_vertex(Vector3.ZERO)
	im.surface_end()

func on_deactivate() -> void:
	_hovered_edge = -1
	_loop_edges   = []

func _find_loop(hem: HalfEdgeMesh, start_he: int) -> Array[int]:
	var loop: Array[int] = []
	var he := start_he
	for _i in hem.get_edge_count():
		loop.append(he)
		var opp  := hem.get_half_edge_next(hem.get_half_edge_next(he))
		var twin := hem.get_half_edge_twin(opp)
		if twin == -1:
			break
		he = twin
		if he == start_he:
			break
	return loop

func _dist_sq_point_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab     := b - a
	var len_sq := ab.length_squared()
	if len_sq < 0.0001:
		return p.distance_squared_to(a)
	var t := clampf((p - a).dot(ab) / len_sq, 0.0, 1.0)
	return p.distance_squared_to(a + ab * t)
