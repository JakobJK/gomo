extends ViewportController
class_name RotateTool

const _AXIS_X    := 0
const _AXIS_Y    := 1
const _AXIS_Z    := 2
const _NONE      := -1
const _SEGMENTS  := 48
const _PICK_PX   := 10.0

const _COL_X     := Color(0.9,  0.18, 0.18)
const _COL_Y     := Color(0.18, 0.85, 0.18)
const _COL_Z     := Color(0.18, 0.38, 0.9)
const _COL_HOVER := Color(1.0,  0.9,  0.1)

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
var _drag_start_angle: float             = 0.0
var _drag_local_u:     Vector3           = Vector3.ZERO
var _drag_local_v:     Vector3           = Vector3.ZERO

func _init() -> void:
	tool_name = "Rotate"

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

	im.surface_begin(Mesh.PRIMITIVE_LINES)
	for a in 3:
		var cols := [_COL_X, _COL_Y, _COL_Z]
		var col: Color   = _COL_HOVER if _hovered_part == a else cols[a]
		var axis: Vector3 = _AXIS_VECS[a]
		var u: Vector3    = _perp(axis)
		var v: Vector3    = axis.cross(u).normalized()
		for seg in _SEGMENTS:
			var a0: float   = TAU * seg / _SEGMENTS
			var a1: float   = TAU * (seg + 1) / _SEGMENTS
			var p0: Vector3 = _gizmo_centroid + (u * cos(a0) + v * sin(a0)) * gizmo_scale
			var p1: Vector3 = _gizmo_centroid + (u * cos(a1) + v * sin(a1)) * gizmo_scale
			im.surface_set_color(col); im.surface_add_vertex(p0)
			im.surface_set_color(col); im.surface_add_vertex(p1)
	im.surface_end()

	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	im.surface_set_color(Color.TRANSPARENT); im.surface_add_vertex(Vector3.ZERO)
	im.surface_set_color(Color.TRANSPARENT); im.surface_add_vertex(Vector3.ZERO)
	im.surface_set_color(Color.TRANSPARENT); im.surface_add_vertex(Vector3.ZERO)
	im.surface_end()

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
	for a in 3:
		var axis: Vector3 = _AXIS_VECS[a]
		var u: Vector3    = _perp(axis)
		var v: Vector3    = axis.cross(u).normalized()
		for seg in _SEGMENTS:
			var a0: float   = TAU * seg / _SEGMENTS
			var a1: float   = TAU * (seg + 1) / _SEGMENTS
			var p0: Vector3 = object_transform * (_gizmo_centroid + (u * cos(a0) + v * sin(a0)) * gizmo_scale)
			var p1: Vector3 = object_transform * (_gizmo_centroid + (u * cos(a1) + v * sin(a1)) * gizmo_scale)
			var s0: Vector2 = camera.unproject_position(p0)
			var s1: Vector2 = camera.unproject_position(p1)
			if _dist_sq_seg(mouse_pos, s0, s1) < _PICK_PX * _PICK_PX:
				_hovered_part = a
				return

func _begin_drag(mouse_pos: Vector2, camera: Camera3D) -> void:
	var axis:     Vector3 = _AXIS_VECS[_active_part]
	_drag_local_u = _perp(axis)
	_drag_local_v = axis.cross(_drag_local_u).normalized()
	var world_n:  Vector3 = (object_transform.basis * axis).normalized()
	_drag_plane = Plane(world_n, object_transform * _drag_centroid)
	var ray_from: Vector3 = camera.project_ray_origin(mouse_pos)
	var ray_dir:  Vector3 = camera.project_ray_normal(mouse_pos)
	var hit: Variant = _drag_plane.intersects_ray(ray_from, ray_dir)
	if hit != null:
		var rel: Vector3 = object_transform.affine_inverse() * (hit as Vector3) - _drag_centroid
		_drag_start_angle = atan2(rel.dot(_drag_local_v), rel.dot(_drag_local_u))

func _continue_drag(mouse_pos: Vector2, hem: HalfEdgeMesh, camera: Camera3D) -> void:
	var ray_from: Vector3 = camera.project_ray_origin(mouse_pos)
	var ray_dir:  Vector3 = camera.project_ray_normal(mouse_pos)
	var hit: Variant = _drag_plane.intersects_ray(ray_from, ray_dir)
	if hit == null: return
	var rel:   Vector3 = object_transform.affine_inverse() * (hit as Vector3) - _drag_centroid
	var angle: float   = atan2(rel.dot(_drag_local_v), rel.dot(_drag_local_u))
	var delta: float   = angle - _drag_start_angle
	var axis:  Vector3 = _AXIS_VECS[_active_part]
	var c: float = cos(delta)
	var s: float = sin(delta)
	for i in _drag_indices.size():
		var r: Vector3 = _drag_initial_pos[i] - _drag_centroid
		hem.set_vertex_position(_drag_indices[i],
			_drag_centroid + r * c + axis.cross(r) * s + axis * axis.dot(r) * (1.0 - c))
