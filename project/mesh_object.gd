extends Node3D
class_name MeshObject

const _MoveTool = preload("res://tools/move_tool.gd")

enum Mode { OBJECT, VERTEX, EDGE, FACE }

var mode:   Mode         = Mode.OBJECT
var hem:    HalfEdgeMesh = HalfEdgeMesh.new()
var camera: Camera3D     = null

var _mesh_instance: MeshInstance3D
var _overlay:       MeshInstance3D

# --- Selection ---
var selected_vertices: PackedInt32Array = []
var selected_edges:    PackedInt32Array = []
var selected_faces:    PackedInt32Array = []

var hovered_vertex: int = -1
var hovered_edge:   int = -1
var hovered_face:   int = -1

var is_selected: bool          = false
var active_tool: ModellingTool = null

const PICK_VERTEX_PX := 20.0
const PICK_EDGE_PX   := 12.0

# --- Materials ---
var _shader_face:      Shader
var _mat_face:         ShaderMaterial
var _mat_wire_dim:     StandardMaterial3D
var _mat_wire_bright:  StandardMaterial3D
var _mat_wire_sel:     StandardMaterial3D
var _mat_wire_hover:   StandardMaterial3D
var _mat_wire_object:  StandardMaterial3D
var _mat_tool_preview: StandardMaterial3D

var _face_textures:  Array[ImageTexture]   = []
var _face_materials: Array[ShaderMaterial] = []
var _debug_normals:  bool                  = false

func _ready() -> void:
	_mesh_instance = MeshInstance3D.new()
	add_child(_mesh_instance)
	_overlay = MeshInstance3D.new()
	add_child(_overlay)

	_shader_face = Shader.new()
	_shader_face.code = """
shader_type spatial;
render_mode diffuse_lambert;
uniform sampler2D local_nmap : hint_default_white, filter_linear;
uniform bool debug_normals = false;
void fragment() {
	vec3 local_n = normalize(texture(local_nmap, UV).rgb * 2.0 - 1.0);
	if (debug_normals) {
		ALBEDO   = vec3(0.0);
		EMISSION = local_n * 0.5 + 0.5;
	} else {
		ALBEDO    = vec3(0.78, 0.47, 0.18);
		ROUGHNESS = 0.35;
		SPECULAR  = 0.65;
		NORMAL    = normalize((VIEW_MATRIX * MODEL_MATRIX * vec4(local_n, 0.0)).xyz);
	}
}
"""
	_mat_face = ShaderMaterial.new()
	_mat_face.shader = _shader_face

	_mat_wire_dim     = _make_wire(Color(0.25, 0.25, 0.25))
	_mat_wire_bright  = _make_wire(Color(0.8,  0.8,  0.8))
	_mat_wire_sel     = _make_wire(Color(1.0,  0.55, 0.1))
	_mat_wire_hover   = _make_wire(Color(1.0,  0.9,  0.2))
	_mat_wire_object  = _make_wire(Color(1.0,  1.0,  1.0))
	_mat_tool_preview = _make_wire(Color(0.2,  1.0,  0.4))

func _make_wire(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	return mat

func _process(_delta: float) -> void:
	if mode == Mode.OBJECT or camera == null:
		return
	if active_tool != null:
		_sync_tool_state()
		active_tool.handle_hover(get_viewport().get_mouse_position(), hem, camera)
	else:
		_update_hover(get_viewport().get_mouse_position())
	_draw_overlay()

# --- Public API ---

func build_box() -> void:
	hem.build_box()
	refresh()

func build_sphere(lat_segments: int = 8, lon_segments: int = 16) -> void:
	hem.build_sphere(lat_segments, lon_segments)
	refresh()

func set_mode(new_mode: Mode) -> void:
	if mode == new_mode:
		return
	mode = new_mode
	_clear_selection()
	set_tool(null)
	refresh()

func set_tool(tool: ModellingTool) -> void:
	if active_tool != null:
		active_tool.on_deactivate(hem)
	active_tool = tool
	if active_tool != null:
		active_tool.on_activate(hem)
		_sync_tool_state()
	_draw_overlay()

func toggle_debug_normals() -> void:
	_debug_normals = !_debug_normals
	for mat in _face_materials:
		if mat != null:
			mat.set_shader_parameter("debug_normals", _debug_normals)

func set_selected(value: bool) -> void:
	is_selected = value
	_draw_overlay()

func ray_hits(ray_from: Vector3, ray_dir: Vector3) -> bool:
	var local_from := global_transform.affine_inverse() * ray_from
	var local_dir  := global_transform.basis.inverse() * ray_dir
	return hem.pick_face(local_from, local_dir) != -1

# Called by main. Returns true if event was consumed.
func handle_input(event: InputEvent) -> bool:
	# Undo/redo always first
	if event is InputEventKey and event.pressed and not event.echo:
		if event.ctrl_pressed and event.keycode == KEY_Z:
			var changed := hem.redo() if event.shift_pressed else hem.undo()
			if changed:
				_clear_selection()
				refresh()
			return true

	if mode == Mode.OBJECT:
		return false

	# Tool switching
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_Q:
			set_tool(null)
			return true
		if event.keycode == KEY_W:
			if active_tool is _MoveTool: set_tool(null)
			else: set_tool(_MoveTool.new())
			return true
		if event.keycode == KEY_S and mode == Mode.FACE:
			if active_tool is SculptTool: set_tool(null)
			else: set_tool(SculptTool.new())
			return true
		if event.keycode == KEY_F and mode == Mode.FACE:
			if active_tool is FlattenTool: set_tool(null)
			else: set_tool(FlattenTool.new())
			return true
		if event.keycode == KEY_R and event.ctrl_pressed and mode == Mode.EDGE:
			if active_tool is EdgeLoopTool: set_tool(null)
			else: set_tool(EdgeLoopTool.new())
			return true

	# Delegate to active tool
	if active_tool != null:
		_sync_tool_state()
		if active_tool.handle_input(event, hem, camera):
			refresh()
			return true

	# Operations
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_E:
			return _do_extrude()
		if event.keycode == KEY_X:
			return _do_delete()

	# Selection
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		_handle_selection_click(event.position, event.shift_pressed)
		return true

	return false

# --- Operations ---

func _do_extrude() -> bool:
	match mode:
		Mode.EDGE:
			if selected_edges.is_empty(): return false
			var he := selected_edges[0]
			if hem.get_half_edge_twin(he) != -1: return false
			hem.extrude_edge(he)
			selected_edges = PackedInt32Array()
			refresh()
			return true
		Mode.FACE:
			if selected_faces.is_empty(): return false
			hem.extrude_face(selected_faces[0])
			selected_faces = PackedInt32Array()
			refresh()
			return true
	return false

func _do_delete() -> bool:
	if mode == Mode.FACE and not selected_faces.is_empty():
		for fi in selected_faces:
			hem.delete_face(fi)
		selected_faces = PackedInt32Array()
		refresh()
		return true
	return false

# --- Selection ---

func _handle_selection_click(mouse_pos: Vector2, additive: bool) -> void:
	match mode:
		Mode.VERTEX:
			var picked := _pick_vertex(mouse_pos)
			if picked != -1:
				if additive:
					if picked in selected_vertices:
						selected_vertices = _arr_remove(selected_vertices, picked)
					else:
						selected_vertices.push_back(picked)
				else:
					selected_vertices = PackedInt32Array([picked])
			elif not additive:
				selected_vertices = PackedInt32Array()

		Mode.EDGE:
			var picked := _pick_edge(mouse_pos)
			if picked != -1:
				var twin      := hem.get_half_edge_twin(picked)
				var canonical := mini(picked, twin) if twin != -1 else picked
				if additive:
					if canonical in selected_edges:
						selected_edges = _arr_remove(selected_edges, canonical)
					else:
						selected_edges.push_back(canonical)
				else:
					selected_edges = PackedInt32Array([canonical])
			elif not additive:
				selected_edges = PackedInt32Array()

		Mode.FACE:
			var ray_from := camera.project_ray_origin(mouse_pos)
			var ray_dir  := camera.project_ray_normal(mouse_pos)
			var lf := global_transform.affine_inverse() * ray_from
			var ld := global_transform.basis.inverse() * ray_dir
			var picked := hem.pick_face(lf, ld)
			if picked != -1:
				if additive:
					if picked in selected_faces:
						selected_faces = _arr_remove(selected_faces, picked)
					else:
						selected_faces.push_back(picked)
				else:
					selected_faces = PackedInt32Array([picked])
			elif not additive:
				selected_faces = PackedInt32Array()

	if active_tool != null:
		_sync_tool_state()
	_draw_overlay()

func _sync_tool_state() -> void:
	if active_tool == null: return
	active_tool.object_transform  = global_transform
	active_tool.current_mode      = mode
	active_tool.selected_vertices = selected_vertices
	active_tool.selected_edges    = selected_edges
	active_tool.selected_faces    = selected_faces

func _update_hover(mouse_pos: Vector2) -> void:
	match mode:
		Mode.VERTEX:
			hovered_vertex = _pick_vertex(mouse_pos)
		Mode.EDGE:
			hovered_edge = _pick_edge(mouse_pos)
		Mode.FACE:
			var ray_from := camera.project_ray_origin(mouse_pos)
			var ray_dir  := camera.project_ray_normal(mouse_pos)
			var lf := global_transform.affine_inverse() * ray_from
			var ld := global_transform.basis.inverse() * ray_dir
			hovered_face = hem.pick_face(lf, ld)

func _clear_selection() -> void:
	selected_vertices = PackedInt32Array()
	selected_edges    = PackedInt32Array()
	selected_faces    = PackedInt32Array()
	hovered_vertex = -1
	hovered_edge   = -1
	hovered_face   = -1

func _arr_remove(arr: PackedInt32Array, val: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	for v in arr:
		if v != val: out.push_back(v)
	return out

# --- Rendering ---

func refresh() -> void:
	var face_count := hem.get_face_count()
	_face_textures.resize(face_count)
	_face_materials.resize(face_count)

	var array_mesh := hem.to_array_mesh()

	var surface_idx := 0
	for fi in face_count:
		if not hem.is_face_valid(fi):
			continue
		var img: Image = hem.get_face_normal_map(fi)
		if _face_textures[fi] == null:
			_face_textures[fi] = ImageTexture.create_from_image(img)
		else:
			_face_textures[fi].update(img)

		if _face_materials[fi] == null:
			_face_materials[fi] = _mat_face.duplicate()
		var mat: ShaderMaterial = _face_materials[fi]
		mat.set_shader_parameter("local_nmap",    _face_textures[fi])
		mat.set_shader_parameter("debug_normals", _debug_normals)
		array_mesh.surface_set_material(surface_idx, mat)
		surface_idx += 1

	_mesh_instance.mesh = array_mesh
	_draw_overlay()

func _draw_overlay() -> void:
	var im := ImmediateMesh.new()

	match mode:
		Mode.OBJECT:
			if is_selected:
				im.surface_begin(Mesh.PRIMITIVE_LINES)
				for i in hem.get_edge_count():
					var twin: int = hem.get_half_edge_twin(i)
					if twin != -1 and i > twin: continue
					im.surface_add_vertex(hem.get_vertex_position(hem.get_half_edge_vertex(i)))
					im.surface_add_vertex(hem.get_vertex_position(hem.get_half_edge_vertex(hem.get_half_edge_next(i))))
				im.surface_end()
				_overlay.mesh = im
				_overlay.set_surface_override_material(0, _mat_wire_object)
			else:
				_overlay.mesh = null

		Mode.VERTEX:
			# surf 0: all edges dim
			_ov_all_edges(im)
			# surf 1: unselected vertex dots
			_ov_vertex_dots(im, false)
			# surf 2: selected vertex dots
			_ov_vertex_dots(im, true)
			# surf 3: hovered vertex dot
			im.surface_begin(Mesh.PRIMITIVE_LINES)
			if hovered_vertex != -1 and hovered_vertex not in selected_vertices:
				_draw_dot(im, hem.get_vertex_position(hovered_vertex))
			else:
				_dummy(im)
			im.surface_end()
			_overlay.mesh = im
			_overlay.set_surface_override_material(0, _mat_wire_dim)
			_overlay.set_surface_override_material(1, _mat_wire_bright)
			_overlay.set_surface_override_material(2, _mat_wire_sel)
			_overlay.set_surface_override_material(3, _mat_wire_hover)

		Mode.EDGE:
			# surf 0: unselected non-hovered edges
			im.surface_begin(Mesh.PRIMITIVE_LINES)
			var drew := false
			for i in hem.get_edge_count():
				var twin: int = hem.get_half_edge_twin(i)
				if twin == -1 and hem.get_half_edge_face(i) == -1: continue
				if twin != -1 and i > twin: continue
				var canonical := mini(i, twin) if twin != -1 else i
				if canonical in selected_edges: continue
				if i == hovered_edge or twin == hovered_edge: continue
				im.surface_add_vertex(hem.get_vertex_position(hem.get_half_edge_vertex(i)))
				im.surface_add_vertex(hem.get_vertex_position(hem.get_half_edge_vertex(hem.get_half_edge_next(i))))
				drew = true
			if not drew: _dummy(im)
			im.surface_end()
			# surf 1: selected edges
			im.surface_begin(Mesh.PRIMITIVE_LINES)
			drew = false
			for he in selected_edges:
				im.surface_add_vertex(hem.get_vertex_position(hem.get_half_edge_vertex(he)))
				im.surface_add_vertex(hem.get_vertex_position(hem.get_half_edge_vertex(hem.get_half_edge_next(he))))
				drew = true
			if not drew: _dummy(im)
			im.surface_end()
			# surf 2: hovered edge
			im.surface_begin(Mesh.PRIMITIVE_LINES)
			if hovered_edge != -1 and hovered_edge not in selected_edges:
				im.surface_add_vertex(hem.get_vertex_position(hem.get_half_edge_vertex(hovered_edge)))
				im.surface_add_vertex(hem.get_vertex_position(hem.get_half_edge_vertex(hem.get_half_edge_next(hovered_edge))))
			else:
				_dummy(im)
			im.surface_end()
			# surf 3: tool preview
			_ov_tool_preview(im)
			_overlay.mesh = im
			_overlay.set_surface_override_material(0, _mat_wire_dim)
			_overlay.set_surface_override_material(1, _mat_wire_sel)
			_overlay.set_surface_override_material(2, _mat_wire_hover)
			_overlay.set_surface_override_material(3, _mat_tool_preview)

		Mode.FACE:
			# surf 0: all edges dim
			_ov_all_edges(im)
			# surf 1: selected face outlines
			im.surface_begin(Mesh.PRIMITIVE_LINES)
			var drew := false
			for fi in selected_faces:
				if not hem.is_face_valid(fi): continue
				var fv := hem.get_face_vertex_indices(fi)
				for i in fv.size():
					im.surface_add_vertex(hem.get_vertex_position(fv[i]))
					im.surface_add_vertex(hem.get_vertex_position(fv[(i + 1) % fv.size()]))
				drew = true
			if not drew: _dummy(im)
			im.surface_end()
			# surf 2: unused
			im.surface_begin(Mesh.PRIMITIVE_LINES)
			_dummy(im)
			im.surface_end()
			# surf 3: tool preview
			_ov_tool_preview(im)
			_overlay.mesh = im
			_overlay.set_surface_override_material(0, _mat_wire_dim)
			_overlay.set_surface_override_material(1, _mat_wire_sel)
			_overlay.set_surface_override_material(2, null)
			_overlay.set_surface_override_material(3, _mat_tool_preview)

func _ov_all_edges(im: ImmediateMesh) -> void:
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	var drew := false
	for i in hem.get_edge_count():
		var twin: int = hem.get_half_edge_twin(i)
		if twin == -1 and hem.get_half_edge_face(i) == -1: continue
		if twin != -1 and i > twin: continue
		im.surface_add_vertex(hem.get_vertex_position(hem.get_half_edge_vertex(i)))
		im.surface_add_vertex(hem.get_vertex_position(hem.get_half_edge_vertex(hem.get_half_edge_next(i))))
		drew = true
	if not drew: _dummy(im)
	im.surface_end()

func _ov_vertex_dots(im: ImmediateMesh, only_selected: bool) -> void:
	im.surface_begin(Mesh.PRIMITIVE_LINES)
	var drew := false
	for i in hem.get_vertex_count():
		var is_sel := i in selected_vertices
		if is_sel != only_selected: continue
		_draw_dot(im, hem.get_vertex_position(i))
		drew = true
	if not drew: _dummy(im)
	im.surface_end()

func _draw_dot(im: ImmediateMesh, pos: Vector3) -> void:
	if camera == null: return
	var cam_local := global_transform.affine_inverse() * camera.global_position
	var sz    := pos.distance_to(cam_local) * 0.012
	var right := (global_transform.basis.inverse() * camera.global_basis.x).normalized() * sz
	var up    := (global_transform.basis.inverse() * camera.global_basis.y).normalized() * sz
	im.surface_add_vertex(pos + up);    im.surface_add_vertex(pos + right)
	im.surface_add_vertex(pos + right); im.surface_add_vertex(pos - up)
	im.surface_add_vertex(pos - up);    im.surface_add_vertex(pos - right)
	im.surface_add_vertex(pos - right); im.surface_add_vertex(pos + up)

func _ov_tool_preview(im: ImmediateMesh) -> void:
	if active_tool != null:
		active_tool.draw_preview(im, hem)
	else:
		im.surface_begin(Mesh.PRIMITIVE_LINES)
		_dummy(im)
		im.surface_end()

func _dummy(im: ImmediateMesh) -> void:
	im.surface_add_vertex(Vector3.ZERO)
	im.surface_add_vertex(Vector3.ZERO)

# --- Picking ---

func _pick_vertex(mouse_pos: Vector2) -> int:
	var positions := hem.get_vertex_positions()
	var best_idx  := -1
	var best_dist := PICK_VERTEX_PX * PICK_VERTEX_PX
	for i in positions.size():
		var world_pos := global_transform * positions[i]
		var d := mouse_pos.distance_squared_to(camera.unproject_position(world_pos))
		if d < best_dist:
			best_dist = d
			best_idx  = i
	return best_idx

func _pick_edge(mouse_pos: Vector2) -> int:
	var best_idx  := -1
	var best_dist := PICK_EDGE_PX * PICK_EDGE_PX
	for i in hem.get_edge_count():
		var twin: int = hem.get_half_edge_twin(i)
		if twin == -1 and hem.get_half_edge_face(i) == -1: continue
		if twin != -1 and i > twin: continue
		var p0 := global_transform * hem.get_vertex_position(hem.get_half_edge_vertex(i))
		var p1 := global_transform * hem.get_vertex_position(hem.get_half_edge_vertex(hem.get_half_edge_next(i)))
		var s0 := camera.unproject_position(p0)
		var s1 := camera.unproject_position(p1)
		var d  := _dist_sq_point_segment(mouse_pos, s0, s1)
		if d < best_dist:
			best_dist = d
			best_idx  = i
	return best_idx

func _dist_sq_point_segment(p: Vector2, a: Vector2, b: Vector2) -> float:
	var ab     := b - a
	var len_sq := ab.length_squared()
	if len_sq < 0.0001:
		return p.distance_squared_to(a)
	var t := clampf((p - a).dot(ab) / len_sq, 0.0, 1.0)
	return p.distance_squared_to(a + ab * t)
