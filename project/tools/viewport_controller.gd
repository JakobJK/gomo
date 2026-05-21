extends RefCounted
class_name ViewportController

var tool_name:         String           = ""
var icon:              Texture2D        = null
var object_transform:  Transform3D      = Transform3D.IDENTITY
var current_mode:      int              = 0
var selected_vertices: PackedInt32Array = []
var selected_edges:    PackedInt32Array = []
var selected_faces:    PackedInt32Array = []

func handle_hover(mouse_pos: Vector2, _hem: HalfEdgeMesh, _camera: Camera3D) -> void:
	pass

func handle_input(event: InputEvent, _hem: HalfEdgeMesh, _camera: Camera3D) -> bool:
	return false

func draw_preview(im: ImmediateMesh, _hem: HalfEdgeMesh) -> void:
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	im.surface_set_color(Color.TRANSPARENT); im.surface_add_vertex(Vector3.ZERO)
	im.surface_set_color(Color.TRANSPARENT); im.surface_add_vertex(Vector3.ZERO)
	im.surface_end()
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	im.surface_set_color(Color.TRANSPARENT); im.surface_add_vertex(Vector3.ZERO)
	im.surface_set_color(Color.TRANSPARENT); im.surface_add_vertex(Vector3.ZERO)
	im.surface_set_color(Color.TRANSPARENT); im.surface_add_vertex(Vector3.ZERO)
	im.surface_end()

func on_activate() -> void:
	pass

func on_deactivate() -> void:
	pass


func _moveable_vertices(hem: HalfEdgeMesh) -> PackedInt32Array:
	var verts := PackedInt32Array()
	if current_mode == 0:
		for i in hem.get_vertex_count(): verts.push_back(i)
	elif current_mode == 1:
		return selected_vertices.duplicate()
	elif current_mode == 2:
		for he in selected_edges:
			var v0: int = hem.get_half_edge_vertex(he)
			var v1: int = hem.get_half_edge_vertex(hem.get_half_edge_next(he))
			if v0 not in verts: verts.push_back(v0)
			if v1 not in verts: verts.push_back(v1)
	elif current_mode == 3:
		for fi in selected_faces:
			if not hem.is_face_valid(fi): continue
			for v in hem.get_face_vertex_indices(fi):
				if v not in verts: verts.push_back(v)
	return verts

static func _subvp_mouse(camera: Camera3D) -> Vector2:
	var subvp := camera.get_viewport()
	var container := subvp.get_parent() as SubViewportContainer
	if container == null: return subvp.get_mouse_position()
	var rect := container.get_global_rect()
	if rect.size.x <= 0.0: return subvp.get_mouse_position()
	var win_mouse := container.get_viewport().get_mouse_position()
	return (win_mouse - rect.position) / rect.size * Vector2(subvp.size)

static func _dist_sq_seg(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab: Vector2 = b - a
	var len_sq: float = ab.length_squared()
	if len_sq < 0.0001: return p.distance_squared_to(a)
	var t: float = clampf((p - a).dot(ab) / len_sq, 0.0, 1.0)
	return p.distance_squared_to(a + ab * t)

static func _perp(axis: Vector3) -> Vector3:
	var u := axis.cross(Vector3.UP)
	if u.length_squared() < 0.001:
		u = axis.cross(Vector3.RIGHT)
	return u.normalized()
