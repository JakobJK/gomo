extends RefCounted
class_name ModellingTool

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

func on_activate() -> void:
	pass

func on_deactivate() -> void:
	pass
