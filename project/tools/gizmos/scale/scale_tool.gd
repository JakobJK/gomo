extends ViewportController
class_name ScaleTool

const _AXIS_X       := 0
const _AXIS_Y       := 1
const _AXIS_Z       := 2
const _AXIS_UNIFORM := 3
const _NONE         := -1

const _PICK_AXIS_PX   := 14.0
const _PICK_CENTER_PX := 16.0

const _COL_X       := Color(0.9,  0.18, 0.18)
const _COL_Y       := Color(0.18, 0.85, 0.18)
const _COL_Z       := Color(0.18, 0.38, 0.9)
const _COL_UNIFORM := Color(0.9,  0.9,  0.9)
const _COL_HOVER   := Color(1.0,  0.9,  0.1)

const _AXIS_VECS := [Vector3(1, 0, 0), Vector3(0, 1, 0), Vector3(0, 0, 1)]

var _camera:           Camera3D          = null
var _gizmo_centroid:   Vector3           = Vector3.ZERO
var _hovered_part:     int               = _NONE
var _active_part:      int               = _NONE
var _is_dragging:      bool              = false
var _drag_indices:     PackedInt32Array  = PackedInt32Array()
var _drag_initial_pos: PackedVector3Array = PackedVector3Array()
var _drag_plane:       Plane             = Plane()
var _drag_centroid:    Vector3           = Vector3.ZERO
var _drag_start_proj:  float             = 0.0
var _drag_start_screen: Vector2          = Vector2.ZERO

func _init() -> void:
	tool_name = "Scale"

func handle_hover(mouse_pos: Vector2, hem: HalfEdgeMesh, camera: Camera3D) -> void:
	_camera = camera
	_update_centroid(hem)
	if not _is_dragging:
		_update_hover(mouse_pos, camera)

func handle_input(event: InputEvent, hem: HalfEdgeMesh, camera: Camera3D) -> bool:
	_camera = camera
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			if _hovered_part == _NONE: return false
			var verts := _moveable_vertices(hem)
			if verts.is_empty(): return false
			_drag_indices = verts
			_drag_initial_pos.clear()
			for i in verts: _drag_initial_pos.push_back(hem.get_vertex_position(i))
			_active_part   = _hovered_part
			_drag_centroid = _gizmo_centroid
			_begin_drag(_subvp_mouse(camera), camera)
			_is_dragging = true
			return true
		else:
			if _is_dragging:
				hem.record_move_vertices(_drag_indices, _drag_initial_pos)
				_is_dragging = false
				_active_part = _NONE
			return false
	if event is InputEventMouseMotion and _is_dragging:
		_continue_drag(_subvp_mouse(camera), hem, camera)
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
		super.draw_preview(im, hem)
		return

	var cam_local:   Vector3 = object_transform.affine_inverse() * _camera.global_position
	var gizmo_scale: float   = cam_local.distance_to(_gizmo_centroid) * 0.18
	var shaft:       float   = gizmo_scale
	var box_half:    float   = gizmo_scale * 0.07
	var axis_cols            := [_COL_X, _COL_Y, _COL_Z]
	var center_col: Color    = _COL_HOVER if _hovered_part == _AXIS_UNIFORM else _COL_UNIFORM

	im.surface_begin(Mesh.PRIMITIVE_LINES)
	for a in 3:
		var col: Color   = _COL_HOVER if _hovered_part == a else axis_cols[a]
		var dir: Vector3 = _AXIS_VECS[a]
		im.surface_set_color(col); im.surface_add_vertex(_gizmo_centroid)
		im.surface_set_color(col); im.surface_add_vertex(_gizmo_centroid + dir * shaft)
	im.surface_end()

	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for a in 3:
		var col: Color = _COL_HOVER if _hovered_part == a else axis_cols[a]
		_fill_box(im, _gizmo_centroid + _AXIS_VECS[a] * shaft, box_half, col)
	_fill_box(im, _gizmo_centroid, box_half * 1.4, center_col)
	im.surface_end()

func _fill_box(im: ImmediateMesh, center: Vector3, half: float, col: Color) -> void:
	var h := half
	var quads := [
		[Vector3(-h,-h,-h), Vector3( h,-h,-h), Vector3( h, h,-h), Vector3(-h, h,-h)],
		[Vector3(-h,-h, h), Vector3(-h, h, h), Vector3( h, h, h), Vector3( h,-h, h)],
		[Vector3(-h,-h,-h), Vector3(-h, h,-h), Vector3(-h, h, h), Vector3(-h,-h, h)],
		[Vector3( h,-h,-h), Vector3( h,-h, h), Vector3( h, h, h), Vector3( h, h,-h)],
		[Vector3(-h,-h,-h), Vector3(-h,-h, h), Vector3( h,-h, h), Vector3( h,-h,-h)],
		[Vector3(-h, h,-h), Vector3( h, h,-h), Vector3( h, h, h), Vector3(-h, h, h)],
	]
	for q in quads:
		im.surface_set_color(col); im.surface_add_vertex(center + q[0])
		im.surface_set_color(col); im.surface_add_vertex(center + q[1])
		im.surface_set_color(col); im.surface_add_vertex(center + q[2])
		im.surface_set_color(col); im.surface_add_vertex(center + q[0])
		im.surface_set_color(col); im.surface_add_vertex(center + q[2])
		im.surface_set_color(col); im.surface_add_vertex(center + q[3])

func _update_centroid(hem: HalfEdgeMesh) -> void:
	var verts := _moveable_vertices(hem)
	if verts.is_empty(): return
	var c := Vector3.ZERO
	for i in verts: c += hem.get_vertex_position(i)
	_gizmo_centroid = c / verts.size()

func _update_hover(mouse_pos: Vector2, camera: Camera3D) -> void:
	_hovered_part = _NONE
	var cam_local:   Vector3 = object_transform.affine_inverse() * camera.global_position
	var gizmo_scale: float   = cam_local.distance_to(_gizmo_centroid) * 0.18
	var shaft:       float   = gizmo_scale

	var center_s: Vector2 = camera.unproject_position(object_transform * _gizmo_centroid)
	if mouse_pos.distance_squared_to(center_s) < _PICK_CENTER_PX * _PICK_CENTER_PX:
		_hovered_part = _AXIS_UNIFORM
		return

	for a in 3:
		var world_base: Vector3 = object_transform * _gizmo_centroid
		var world_tip:  Vector3 = object_transform * (_gizmo_centroid + _AXIS_VECS[a] * shaft)
		var s0: Vector2 = camera.unproject_position(world_base)
		var s1: Vector2 = camera.unproject_position(world_tip)
		if _dist_sq_seg(mouse_pos, s0, s1) < _PICK_AXIS_PX * _PICK_AXIS_PX:
			_hovered_part = a
			return

func _begin_drag(mouse_pos: Vector2, camera: Camera3D) -> void:
	if _active_part == _AXIS_UNIFORM:
		_drag_start_screen = mouse_pos
		return

	var ray_from: Vector3 = camera.project_ray_origin(mouse_pos)
	var ray_dir:  Vector3 = camera.project_ray_normal(mouse_pos)
	var axis:     Vector3 = _AXIS_VECS[_active_part]
	var cam_local: Vector3 = object_transform.basis.inverse() * (-camera.global_basis.z)
	var helper: Vector3 = cam_local - cam_local.dot(axis) * axis
	if helper.length_squared() < 0.001: helper = axis.cross(Vector3.UP)
	var world_n: Vector3 = (object_transform.basis * helper.normalized()).normalized()
	_drag_plane = Plane(world_n, object_transform * _drag_centroid)
	var hit: Variant = _drag_plane.intersects_ray(ray_from, ray_dir)
	if hit == null: return
	_drag_start_proj = (object_transform.affine_inverse() * (hit as Vector3) - _drag_centroid).dot(axis)

func _continue_drag(mouse_pos: Vector2, hem: HalfEdgeMesh, camera: Camera3D) -> void:
	var factor: float
	if _active_part == _AXIS_UNIFORM:
		factor = maxf(exp((mouse_pos.x - _drag_start_screen.x) / 150.0), 0.001)
		for i in _drag_indices.size():
			var r: Vector3 = _drag_initial_pos[i] - _drag_centroid
			hem.set_vertex_position(_drag_indices[i], _drag_centroid + r * factor)
	else:
		var ray_from: Vector3 = camera.project_ray_origin(mouse_pos)
		var ray_dir:  Vector3 = camera.project_ray_normal(mouse_pos)
		var hit: Variant = _drag_plane.intersects_ray(ray_from, ray_dir)
		if hit == null or absf(_drag_start_proj) < 0.0001: return
		var lh: Vector3 = object_transform.affine_inverse() * (hit as Vector3) - _drag_centroid
		factor = maxf(lh.dot(_AXIS_VECS[_active_part]) / _drag_start_proj, 0.001)
		var axis: Vector3 = _AXIS_VECS[_active_part]
		for i in _drag_indices.size():
			var r: Vector3 = _drag_initial_pos[i] - _drag_centroid
			hem.set_vertex_position(_drag_indices[i],
				_drag_centroid + r + axis * (r.dot(axis) * (factor - 1.0)))
