extends ModellingTool
class_name MoveTool

const _AXIS_X  := 0
const _AXIS_Y  := 1
const _AXIS_Z  := 2
const _AXIS_XY := 3
const _AXIS_XZ := 4
const _AXIS_YZ := 5
const _NONE    := -1

const _PICK_AXIS_PX  := 14.0
const _PICK_PLANE_PX := 18.0

const _COL_X      := Color(0.9,  0.18, 0.18)
const _COL_Y      := Color(0.18, 0.85, 0.18)
const _COL_Z      := Color(0.18, 0.38, 0.9)
const _COL_XY     := Color(0.9,  0.18, 0.9)
const _COL_XZ     := Color(0.9,  0.85, 0.18)
const _COL_YZ     := Color(0.18, 0.9,  0.9)
const _COL_HOVER  := Color(1.0,  0.9,  0.1)

var _camera:          Camera3D = null
var _gizmo_centroid:  Vector3  = Vector3.ZERO
var _hovered_part:    int      = _NONE
var _active_part:     int      = _NONE

var _is_dragging:      bool               = false
var _drag_indices:     PackedInt32Array   = PackedInt32Array()
var _drag_initial_pos: PackedVector3Array = PackedVector3Array()
var _drag_plane:       Plane              = Plane()
var _drag_start_proj:  float              = 0.0
var _drag_start_hit:   Vector3            = Vector3.ZERO
var _drag_centroid:    Vector3            = Vector3.ZERO

const _AXIS_VECS = [Vector3(1,0,0), Vector3(0,1,0), Vector3(0,0,1)]

func _init() -> void:
	tool_name = "Move"

# ---------------------------------------------------------------------------

func handle_hover(mouse_pos: Vector2, hem: HalfEdgeMesh, camera: Camera3D) -> void:
	_camera = camera
	_update_centroid(hem)
	if not _is_dragging:
		_update_hover(mouse_pos, camera)

func handle_input(event: InputEvent, hem: HalfEdgeMesh, camera: Camera3D) -> bool:
	_camera = camera

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if _hovered_part == _NONE:
				return false  # fall through to GomoMesh selection
			var verts := _moveable_vertices(hem)
			if verts.is_empty():
				return false
			_drag_indices = verts
			_drag_initial_pos.clear()
			for i in verts:
				_drag_initial_pos.push_back(hem.get_vertex_position(i))
			_active_part   = _hovered_part
			_drag_centroid = _gizmo_centroid
			_begin_drag(event.position, camera)
			_is_dragging = true
			return true
		else:
			if _is_dragging:
				hem.record_move_vertices(_drag_indices, _drag_initial_pos)
				_is_dragging = false
				_active_part = _NONE
			return false

	if event is InputEventMouseMotion and _is_dragging:
		_continue_drag(event.position, hem, camera)
		return true

	return false

func on_deactivate() -> void:
	_is_dragging = false
	_active_part = _NONE
	_hovered_part = _NONE


func draw_preview(im: ImmediateMesh, hem: HalfEdgeMesh) -> void:
	if not _is_dragging:
		_update_centroid(hem)

	var verts := _moveable_vertices(hem)
	if verts.is_empty() or _camera == null:
		im.surface_begin(Mesh.PRIMITIVE_LINES)
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
		return

	var cam_local:   Vector3 = object_transform.affine_inverse() * _camera.global_position
	var gizmo_scale: float   = cam_local.distance_to(_gizmo_centroid) * 0.18
	var shaft:       float   = gizmo_scale
	var cone_start:  float   = shaft * 0.80
	var cone_r:      float   = gizmo_scale * 0.08
	var cone_steps:  int     = 10
	var ph_off:      float   = gizmo_scale * 0.28
	var ph_sz:       float   = gizmo_scale * 0.14

	var axis_colors := [_COL_X, _COL_Y, _COL_Z]

	# Surface 1: Lines — shafts only
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	for a in 3:
		var col: Color   = axis_colors[a]
		if _hovered_part == a: col = _COL_HOVER
		var dir: Vector3 = _AXIS_VECS[a]
		im.surface_set_color(col); im.surface_add_vertex(_gizmo_centroid)
		im.surface_set_color(col); im.surface_add_vertex(_gizmo_centroid + dir * cone_start)
	im.surface_end()

	# Surface 2: Triangles — filled cones + filled plane handles
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for a in 3:
		var col: Color   = axis_colors[a]
		if _hovered_part == a: col = _COL_HOVER
		var dir:  Vector3 = _AXIS_VECS[a]
		var tip:  Vector3 = _gizmo_centroid + dir * shaft
		var base: Vector3 = _gizmo_centroid + dir * cone_start

		var perp1: Vector3 = dir.cross(Vector3.UP)
		if perp1.length_squared() < 0.001:
			perp1 = dir.cross(Vector3.RIGHT)
		perp1 = perp1.normalized() * cone_r
		var perp2: Vector3 = dir.cross(perp1).normalized() * cone_r

		for step in cone_steps:
			var a0: float   = TAU * step / cone_steps
			var a1: float   = TAU * (step + 1) / cone_steps
			var p0: Vector3 = base + perp1 * cos(a0) + perp2 * sin(a0)
			var p1: Vector3 = base + perp1 * cos(a1) + perp2 * sin(a1)
			# Cone side
			im.surface_set_color(col); im.surface_add_vertex(tip)
			im.surface_set_color(col); im.surface_add_vertex(p0)
			im.surface_set_color(col); im.surface_add_vertex(p1)
			# Cone base cap
			im.surface_set_color(col); im.surface_add_vertex(base)
			im.surface_set_color(col); im.surface_add_vertex(p1)
			im.surface_set_color(col); im.surface_add_vertex(p0)

	_fill_plane_handle(im, Vector3(1,0,0), Vector3(0,1,0), _AXIS_XY, _COL_XY, ph_off, ph_sz)
	_fill_plane_handle(im, Vector3(1,0,0), Vector3(0,0,1), _AXIS_XZ, _COL_XZ, ph_off, ph_sz)
	_fill_plane_handle(im, Vector3(0,1,0), Vector3(0,0,1), _AXIS_YZ, _COL_YZ, ph_off, ph_sz)
	im.surface_end()

func _fill_plane_handle(im: ImmediateMesh, a1: Vector3, a2: Vector3, pid: int,
		base_col: Color, ph_off: float, ph_sz: float) -> void:
	var col: Color   = _COL_HOVER if _hovered_part == pid else base_col
	var o:   Vector3 = _gizmo_centroid + a1 * ph_off + a2 * ph_off
	var c0:  Vector3 = o
	var c1:  Vector3 = o + a1 * ph_sz
	var c2:  Vector3 = o + a1 * ph_sz + a2 * ph_sz
	var c3:  Vector3 = o + a2 * ph_sz
	im.surface_set_color(col); im.surface_add_vertex(c0)
	im.surface_set_color(col); im.surface_add_vertex(c1)
	im.surface_set_color(col); im.surface_add_vertex(c2)
	im.surface_set_color(col); im.surface_add_vertex(c0)
	im.surface_set_color(col); im.surface_add_vertex(c2)
	im.surface_set_color(col); im.surface_add_vertex(c3)

# ---------------------------------------------------------------------------

func _update_centroid(hem: HalfEdgeMesh) -> void:
	var verts := _moveable_vertices(hem)
	if verts.is_empty(): return
	var c := Vector3.ZERO
	for i in verts:
		c += hem.get_vertex_position(i)
	_gizmo_centroid = c / verts.size()

func _update_hover(mouse_pos: Vector2, camera: Camera3D) -> void:
	_hovered_part = _NONE
	var cam_local:   Vector3 = object_transform.affine_inverse() * camera.global_position
	var gizmo_scale: float   = cam_local.distance_to(_gizmo_centroid) * 0.18
	var shaft:       float   = gizmo_scale
	var ph_off:      float   = gizmo_scale * 0.28
	var ph_sz:       float   = gizmo_scale * 0.14

	# Test axes
	for a in 3:
		var dir:        Vector3 = _AXIS_VECS[a]
		var world_base: Vector3 = object_transform * _gizmo_centroid
		var world_tip:  Vector3 = object_transform * (_gizmo_centroid + dir * shaft)
		var s0: Vector2 = camera.unproject_position(world_base)
		var s1: Vector2 = camera.unproject_position(world_tip)
		if _dist_sq_seg(mouse_pos, s0, s1) < _PICK_AXIS_PX * _PICK_AXIS_PX:
			_hovered_part = a
			return

	# Test plane handles
	_test_plane_hover(mouse_pos, camera, Vector3(1,0,0), Vector3(0,1,0), _AXIS_XY, ph_off, ph_sz)
	if _hovered_part != _NONE: return
	_test_plane_hover(mouse_pos, camera, Vector3(1,0,0), Vector3(0,0,1), _AXIS_XZ, ph_off, ph_sz)
	if _hovered_part != _NONE: return
	_test_plane_hover(mouse_pos, camera, Vector3(0,1,0), Vector3(0,0,1), _AXIS_YZ, ph_off, ph_sz)

func _test_plane_hover(mouse_pos: Vector2, camera: Camera3D, a1: Vector3, a2: Vector3,
		pid: int, ph_off: float, ph_sz: float) -> void:
	var center_local: Vector3 = _gizmo_centroid + a1 * (ph_off + ph_sz * 0.5) + a2 * (ph_off + ph_sz * 0.5)
	var screen_c:     Vector2 = camera.unproject_position(object_transform * center_local)
	if mouse_pos.distance_squared_to(screen_c) < _PICK_PLANE_PX * _PICK_PLANE_PX:
		_hovered_part = pid

func _begin_drag(mouse_pos: Vector2, camera: Camera3D) -> void:
	var ray_from:      Vector3 = camera.project_ray_origin(mouse_pos)
	var ray_dir:       Vector3 = camera.project_ray_normal(mouse_pos)
	var cam_dir_local: Vector3 = object_transform.basis.inverse() * (-camera.global_basis.z)

	if _active_part <= _AXIS_Z:
		var axis:     Vector3 = _AXIS_VECS[_active_part]
		var helper_n: Vector3 = cam_dir_local - cam_dir_local.dot(axis) * axis
		if helper_n.length_squared() < 0.001:
			helper_n = axis.cross(Vector3.UP)
		helper_n = (object_transform.basis * helper_n.normalized()).normalized()
		_drag_plane = Plane(helper_n, object_transform * _drag_centroid)
		var hit: Variant = _drag_plane.intersects_ray(ray_from, ray_dir)
		if hit != null:
			var lh: Vector3 = object_transform.affine_inverse() * (hit as Vector3)
			_drag_start_proj = (lh - _drag_centroid).dot(axis)
	else:
		var local_n: Vector3 = _plane_normal(_active_part)
		var world_n: Vector3 = (object_transform.basis * local_n).normalized()
		_drag_plane = Plane(world_n, object_transform * _drag_centroid)
		var hit: Variant = _drag_plane.intersects_ray(ray_from, ray_dir)
		if hit != null:
			_drag_start_hit = object_transform.affine_inverse() * (hit as Vector3)

func _continue_drag(mouse_pos: Vector2, hem: HalfEdgeMesh, camera: Camera3D) -> void:
	var ray_from: Vector3 = camera.project_ray_origin(mouse_pos)
	var ray_dir:  Vector3 = camera.project_ray_normal(mouse_pos)
	var hit: Variant = _drag_plane.intersects_ray(ray_from, ray_dir)
	if hit == null: return
	var local_hit: Vector3 = object_transform.affine_inverse() * (hit as Vector3)

	if _active_part <= _AXIS_Z:
		var axis:  Vector3 = _AXIS_VECS[_active_part]
		var proj:  float   = (local_hit - _drag_centroid).dot(axis)
		var delta: Vector3 = axis * (proj - _drag_start_proj)
		for i in _drag_indices.size():
			hem.set_vertex_position(_drag_indices[i], _drag_initial_pos[i] + delta)
	else:
		var delta: Vector3 = local_hit - _drag_start_hit
		match _active_part:
			_AXIS_XY: delta.z = 0.0
			_AXIS_XZ: delta.y = 0.0
			_AXIS_YZ: delta.x = 0.0
		for i in _drag_indices.size():
			hem.set_vertex_position(_drag_indices[i], _drag_initial_pos[i] + delta)

func _plane_normal(part: int) -> Vector3:
	match part:
		_AXIS_XY: return Vector3(0, 0, 1)
		_AXIS_XZ: return Vector3(0, 1, 0)
		_AXIS_YZ: return Vector3(1, 0, 0)
	return Vector3.UP

func _moveable_vertices(hem: HalfEdgeMesh) -> PackedInt32Array:
	var verts := PackedInt32Array()
	if current_mode == 0:  # OBJECT - move all vertices together
		for i in hem.get_vertex_count():
			verts.push_back(i)
	elif current_mode == 1:  # VERTEX
		return selected_vertices.duplicate()
	elif current_mode == 2:  # EDGE
		for he in selected_edges:
			var v0: int = hem.get_half_edge_vertex(he)
			var v1: int = hem.get_half_edge_vertex(hem.get_half_edge_next(he))
			if v0 not in verts: verts.push_back(v0)
			if v1 not in verts: verts.push_back(v1)
	elif current_mode == 3:  # FACE
		for fi in selected_faces:
			if not hem.is_face_valid(fi): continue
			for v in hem.get_face_vertex_indices(fi):
				if v not in verts: verts.push_back(v)
	return verts

func _dist_sq_seg(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab:     Vector2 = b - a
	var len_sq: float   = ab.length_squared()
	if len_sq < 0.0001: return p.distance_squared_to(a)
	var t: float = clampf((p - a).dot(ab) / len_sq, 0.0, 1.0)
	return p.distance_squared_to(a + ab * t)
