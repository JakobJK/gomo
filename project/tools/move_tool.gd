extends ModellingTool
class_name MoveTool

var _is_dragging:      bool               = false
var _drag_indices:     PackedInt32Array   = []
var _drag_initial_pos: PackedVector3Array = []
var _drag_plane:       Plane              = Plane()
var _drag_origin:      Vector3            = Vector3.ZERO
var _drag_offset:      Vector3            = Vector3.ZERO

func _init() -> void:
	tool_name = "Move"

func handle_input(event: InputEvent, hem: HalfEdgeMesh, camera: Camera3D) -> bool:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var verts := _moveable_vertices(hem)
			if verts.is_empty():
				return false  # let MeshObject handle selection

			_drag_indices = verts
			_drag_initial_pos.clear()
			var centroid := Vector3.ZERO
			for i in verts:
				var p := hem.get_vertex_position(i)
				_drag_initial_pos.push_back(p)
				centroid += p
			centroid /= verts.size()

			_drag_origin = object_transform * centroid
			_drag_plane  = Plane(-camera.global_basis.z, _drag_origin)
			var ray_from := camera.project_ray_origin(event.position)
			var ray_dir  := camera.project_ray_normal(event.position)
			var hit: Variant = _drag_plane.intersects_ray(ray_from, ray_dir)
			_drag_offset = (hit - _drag_origin) if hit != null else Vector3.ZERO
			_is_dragging = true
			return true
		else:
			if _is_dragging:
				hem.record_move_vertices(_drag_indices, _drag_initial_pos)
				_is_dragging = false
			return false

	if event is InputEventMouseMotion and _is_dragging:
		var ray_from := camera.project_ray_origin(event.position)
		var ray_dir  := camera.project_ray_normal(event.position)
		var hit: Variant = _drag_plane.intersects_ray(ray_from, ray_dir)
		if hit != null:
			var world_delta: Vector3 = (hit as Vector3) - _drag_origin - _drag_offset
			var local_delta: Vector3 = object_transform.basis.inverse() * world_delta
			for i in _drag_indices.size():
				hem.set_vertex_position(_drag_indices[i], _drag_initial_pos[i] + local_delta)
		return true

	return false

func on_deactivate(_hem: HalfEdgeMesh) -> void:
	_is_dragging = false

func _moveable_vertices(hem: HalfEdgeMesh) -> PackedInt32Array:
	var verts := PackedInt32Array()
	if current_mode == 1:  # VERTEX
		return selected_vertices.duplicate()
	elif current_mode == 2:  # EDGE
		for he in selected_edges:
			var v0 := hem.get_half_edge_vertex(he)
			var v1 := hem.get_half_edge_vertex(hem.get_half_edge_next(he))
			if v0 not in verts: verts.push_back(v0)
			if v1 not in verts: verts.push_back(v1)
	elif current_mode == 3:  # FACE
		for fi in selected_faces:
			for v in hem.get_face_vertex_indices(fi):
				if v not in verts: verts.push_back(v)
	return verts
