extends ModellingTool
class_name SculptTool

var brush_size     := 0.5   # world-space radius
var brush_strength := 0.3

var _hit_face   := -1
var _hit_pos    := Vector3.ZERO
var _hit_normal := Vector3.UP
var _is_painting := false

func _init() -> void:
	tool_name = "Sculpt"

func handle_hover(mouse_pos: Vector2, hem: HalfEdgeMesh, camera: Camera3D) -> void:
	_update_hit(mouse_pos, hem, camera)

func handle_input(event: InputEvent, hem: HalfEdgeMesh, camera: Camera3D) -> bool:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_is_painting = true
			if _hit_face != -1:
				hem.begin_tilt_stroke()
				hem.paint_at(_hit_pos, brush_strength, brush_size)
				return true
		else:
			hem.end_tilt_stroke()
			_is_painting = false
		return false

	if event is InputEventMouseMotion:
		_update_hit(event.position, hem, camera)
		if _is_painting and _hit_face != -1:
			hem.paint_at(_hit_pos, brush_strength, brush_size)
			return true

	return false

func draw_preview(im: ImmediateMesh, _hem: HalfEdgeMesh) -> void:
	if _hit_face == -1:
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
	im.surface_begin(Mesh.PRIMITIVE_LINE_STRIP)

	var radius := brush_size

	var tangent := _hit_normal.cross(Vector3.UP)
	if tangent.length_squared() < 0.01:
		tangent = _hit_normal.cross(Vector3.RIGHT)
	tangent = tangent.normalized()
	var bitangent := _hit_normal.cross(tangent).normalized()

	const STEPS := 32
	const _COL := Color(0.2, 1.0, 0.4)
	for i in STEPS + 1:
		var angle := TAU * i / STEPS
		im.surface_set_color(_COL)
		im.surface_add_vertex(_hit_pos + (tangent * cos(angle) + bitangent * sin(angle)) * radius)
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
	_hit_face    = -1
	_is_painting = false

func _update_hit(mouse_pos: Vector2, hem: HalfEdgeMesh, camera: Camera3D) -> void:
	var inv        := object_transform.affine_inverse()
	var ray_from   := inv * camera.project_ray_origin(mouse_pos)
	var ray_dir    := inv.basis * camera.project_ray_normal(mouse_pos)
	_hit_face = hem.pick_face(ray_from, ray_dir)
	if _hit_face != -1:
		_hit_normal = hem.get_face_normal(_hit_face)
		var plane   := Plane(_hit_normal, hem.get_face_center(_hit_face))
		var hit: Variant = plane.intersects_ray(ray_from, ray_dir)
		if hit != null:
			_hit_pos = hit
