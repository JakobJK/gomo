extends Node3D
class_name GomoMesh

const _MoveTool = preload("res://tools/move_tool.gd")

enum Mode { OBJECT, VERTEX, EDGE, FACE }

var mode:   Mode         = Mode.OBJECT
var hem:    HalfEdgeMesh = HalfEdgeMesh.new()
var camera: Camera3D     = null

var _mesh_instance:   MeshInstance3D
var _overlay:         MeshInstance3D
var _subdiv_instance: MeshInstance3D
var _subdiv_levels:   int  = 2
var _subdiv_visible:  bool = false

var hovered_vertex: int = -1
var hovered_edge:   int = -1
var hovered_face:   int = -1

const PICK_VERTEX_PX := 20.0
const PICK_EDGE_PX   := 12.0

# --- Materials ---
var _mat_mesh:         StandardMaterial3D
var _mat_wire_dim:     StandardMaterial3D
var _mat_wire_bright:  StandardMaterial3D
var _mat_wire_sel:     StandardMaterial3D
var _mat_wire_hover:   StandardMaterial3D
var _mat_wire_object:  StandardMaterial3D
var _mat_tool_preview: StandardMaterial3D

var _mat_subdiv: StandardMaterial3D

func _ready() -> void:
	_mesh_instance = MeshInstance3D.new()
	add_child(_mesh_instance)
	_overlay = MeshInstance3D.new()
	add_child(_overlay)
	_subdiv_instance = MeshInstance3D.new()
	_subdiv_instance.visible = false
	add_child(_subdiv_instance)

	_mat_mesh = StandardMaterial3D.new()
	_mat_mesh.albedo_color     = Color(0.78, 0.47, 0.18)
	_mat_mesh.roughness        = 0.35
	_mat_mesh.metallic_specular = 0.65

	_mat_wire_dim     = _make_wire(Color(0.25, 0.25, 0.25))
	_mat_wire_bright  = _make_wire(Color(0.8,  0.8,  0.8))
	_mat_wire_sel     = _make_wire(Color(1.0,  0.55, 0.1))
	_mat_wire_hover   = _make_wire(Color(1.0,  0.9,  0.2))
	_mat_wire_object  = _make_wire(Color(1.0,  1.0,  1.0))
	_mat_tool_preview = StandardMaterial3D.new()
	_mat_tool_preview.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_mat_tool_preview.vertex_color_use_as_albedo = true
	_mat_tool_preview.no_depth_test = true
	_mat_tool_preview.cull_mode = BaseMaterial3D.CULL_DISABLED

	_mat_subdiv = StandardMaterial3D.new()
	_mat_subdiv.albedo_color      = Color(0.78, 0.47, 0.18)
	_mat_subdiv.roughness         = 0.25
	_mat_subdiv.metallic_specular = 0.75
	_subdiv_instance.material_override = _mat_subdiv

func _make_wire(color: Color) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = color
	return mat

func _process(_delta: float) -> void:
	if camera == null:
		return
	if mode == Mode.OBJECT:
		if SelectionState.active_tool != null and SelectionState.has(self):
			_sync_tool_state()
			SelectionState.active_tool.handle_hover(get_viewport().get_mouse_position(), hem, camera)
			_draw_overlay()
		return
	if SelectionState.active_tool != null:
		_sync_tool_state()
		SelectionState.active_tool.handle_hover(get_viewport().get_mouse_position(), hem, camera)
	else:
		_update_hover(get_viewport().get_mouse_position())
	_draw_overlay()

# --- Public API ---

func toggle_subdiv_preview(levels: int = 2) -> void:
	_subdiv_visible = not _subdiv_visible
	_subdiv_levels  = levels
	_update_subdiv()

func _update_subdiv() -> void:
	if _subdiv_visible:
		_subdiv_instance.mesh    = hem.subdivide_to_mesh(_subdiv_levels)
		_subdiv_instance.visible = true
		_mesh_instance.visible   = false
	else:
		_subdiv_instance.visible = false
		_mesh_instance.visible   = true

func build_box(width: float = 2.0, height: float = 2.0, depth: float = 2.0,
			   width_segments: int = 1, height_segments: int = 1, depth_segments: int = 1) -> void:
	hem.build_box(width, height, depth, width_segments, height_segments, depth_segments)
	refresh()

func build_sphere(lat_segments: int = 8, lon_segments: int = 16) -> void:
	hem.build_sphere(lat_segments, lon_segments)
	refresh()

func set_mode(new_mode: Mode) -> void:
	if mode == new_mode:
		return
	mode = new_mode
	_clear_selection()
	if mode == Mode.OBJECT:
		SelectionState.set_context(null)
	else:
		SelectionState.set_context(self)
	set_tool(null)
	refresh()

func set_tool(tool: ModellingTool) -> void:
	SelectionState.set_tool(tool)
	if SelectionState.active_tool != null:
		_sync_tool_state()
	_draw_overlay()

func redraw() -> void:
	_draw_overlay()

func ray_hits(ray_from: Vector3, ray_dir: Vector3) -> bool:
	var local_from := global_transform.affine_inverse() * ray_from
	var local_dir  := global_transform.basis.inverse() * ray_dir
	return hem.pick_face(local_from, local_dir) != -1

# Called by main. Returns true if event was consumed.
func handle_input(event: InputEvent) -> bool:
	# Undo/redo always first
	if event.is_action_pressed("redo"):
		var changed := hem.redo()
		if changed: _clear_selection(); refresh()
		return true
	if event.is_action_pressed("undo"):
		var changed := hem.undo()
		if changed: _clear_selection(); refresh()
		return true

	if mode == Mode.OBJECT:
		if not SelectionState.has(self): return false
		if SelectionState.active_tool != null:
			_sync_tool_state()
			if SelectionState.active_tool.handle_input(event, hem, camera):
				refresh()
				return true
		return false

	# Tool switching
	if event.is_action_pressed("tool_none"):
		set_tool(null)
		return true
	if event.is_action_pressed("tool_move"):
		set_tool(null if SelectionState.active_tool is _MoveTool else _MoveTool.new())
		return true
	if event.is_action_pressed("tool_sculpt") and mode == Mode.FACE:
		set_tool(null if SelectionState.active_tool is SculptTool else SculptTool.new())
		return true
	if event.is_action_pressed("tool_flatten") and mode == Mode.FACE:
		set_tool(null if SelectionState.active_tool is FlattenTool else FlattenTool.new())
		return true
	if event.is_action_pressed("tool_edge_loop") and mode == Mode.EDGE:
		set_tool(null if SelectionState.active_tool is EdgeLoopTool else EdgeLoopTool.new())
		return true

	# Delegate to active tool
	if SelectionState.active_tool != null:
		_sync_tool_state()
		if SelectionState.active_tool.handle_input(event, hem, camera):
			refresh()
			return true

	# Operations
	if event.is_action_pressed("op_extrude"): return _do_extrude()
	if event.is_action_pressed("op_delete"):  return _do_delete()

	# Selection
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		if Input.is_key_pressed(Keymap.CAMERA_MODIFIER):
			return false
		_handle_selection_click(event.position, event.shift_pressed)
		return true

	return false

# --- Operations ---

func _do_extrude() -> bool:
	match mode:
		Mode.EDGE:
			if SelectionState.edges.is_empty(): return false
			var he := SelectionState.edges[0]
			if hem.get_half_edge_twin(he) != -1: return false
			hem.extrude_edge(he)
			SelectionState.clear_components()
			refresh()
			return true
		Mode.FACE:
			if SelectionState.faces.is_empty(): return false
			hem.extrude_face(SelectionState.faces[0])
			SelectionState.clear_components()
			_sync_tool_state()
			refresh()
			return true
	return false

func _do_delete() -> bool:
	if mode == Mode.FACE and not SelectionState.faces.is_empty():
		for fi in SelectionState.faces:
			hem.delete_face(fi)
		SelectionState.clear_components()
		_sync_tool_state()
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
					SelectionState.toggle_vertex(picked)
				else:
					SelectionState.clear_components()
					SelectionState.add_vertex(picked)
			elif not additive:
				SelectionState.clear_components()

		Mode.EDGE:
			var picked := _pick_edge(mouse_pos)
			if picked != -1:
				var twin:      int = hem.get_half_edge_twin(picked)
				var canonical: int = mini(picked, twin) if twin != -1 else picked
				if additive:
					SelectionState.toggle_edge(canonical)
				else:
					SelectionState.clear_components()
					SelectionState.add_edge(canonical)
			elif not additive:
				SelectionState.clear_components()

		Mode.FACE:
			var ray_from := camera.project_ray_origin(mouse_pos)
			var ray_dir  := camera.project_ray_normal(mouse_pos)
			var lf := global_transform.affine_inverse() * ray_from
			var ld := global_transform.basis.inverse() * ray_dir
			var picked := hem.pick_face(lf, ld)
			if picked != -1:
				if additive:
					SelectionState.toggle_face(picked)
				else:
					SelectionState.clear_components()
					SelectionState.add_face(picked)
			elif not additive:
				SelectionState.clear_components()

	if SelectionState.active_tool != null:
		_sync_tool_state()
	_draw_overlay()

func _sync_tool_state() -> void:
	if SelectionState.active_tool == null: return
	SelectionState.active_tool.object_transform  = global_transform
	SelectionState.active_tool.current_mode      = mode
	SelectionState.active_tool.selected_vertices = SelectionState.vertices
	SelectionState.active_tool.selected_edges    = SelectionState.edges
	SelectionState.active_tool.selected_faces    = SelectionState.faces

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
	SelectionState.clear_components()
	hovered_vertex = -1
	hovered_edge   = -1
	hovered_face   = -1

# --- Rendering ---

func refresh() -> void:
	var array_mesh := hem.to_array_mesh()
	for i in array_mesh.get_surface_count():
		array_mesh.surface_set_material(i, _mat_mesh)
	_mesh_instance.mesh = array_mesh
	if _subdiv_visible:
		_update_subdiv()
	_draw_overlay()
	EventBus.instance.object_changed.emit(self)

func _draw_overlay() -> void:
	var im := ImmediateMesh.new()

	match mode:
		Mode.OBJECT:
			if SelectionState.has(self):
				im.surface_begin(Mesh.PRIMITIVE_LINES)
				for i in hem.get_edge_count():
					var twin: int = hem.get_half_edge_twin(i)
					if twin != -1 and i > twin: continue
					im.surface_add_vertex(hem.get_vertex_position(hem.get_half_edge_vertex(i)))
					im.surface_add_vertex(hem.get_vertex_position(hem.get_half_edge_vertex(hem.get_half_edge_next(i))))
				im.surface_end()
				_ov_tool_preview(im)
				_overlay.mesh = im
				_overlay.set_surface_override_material(0, _mat_wire_object)
				_overlay.set_surface_override_material(1, _mat_tool_preview)
				_overlay.set_surface_override_material(2, _mat_tool_preview)
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
			if hovered_vertex != -1 and hovered_vertex not in SelectionState.vertices:
				_draw_dot(im, hem.get_vertex_position(hovered_vertex))
			else:
				_dummy(im)
			im.surface_end()
			# surf 4-5: tool preview (lines + triangles)
			_ov_tool_preview(im)
			_overlay.mesh = im
			_overlay.set_surface_override_material(0, _mat_wire_dim)
			_overlay.set_surface_override_material(1, _mat_wire_bright)
			_overlay.set_surface_override_material(2, _mat_wire_sel)
			_overlay.set_surface_override_material(3, _mat_wire_hover)
			_overlay.set_surface_override_material(4, _mat_tool_preview)
			_overlay.set_surface_override_material(5, _mat_tool_preview)

		Mode.EDGE:
			# surf 0: unselected non-hovered edges
			im.surface_begin(Mesh.PRIMITIVE_LINES)
			var drew := false
			for i in hem.get_edge_count():
				var twin: int = hem.get_half_edge_twin(i)
				if twin == -1 and hem.get_half_edge_face(i) == -1: continue
				if twin != -1 and i > twin: continue
				var canonical := mini(i, twin) if twin != -1 else i
				if canonical in SelectionState.edges: continue
				if i == hovered_edge or twin == hovered_edge: continue
				im.surface_add_vertex(hem.get_vertex_position(hem.get_half_edge_vertex(i)))
				im.surface_add_vertex(hem.get_vertex_position(hem.get_half_edge_vertex(hem.get_half_edge_next(i))))
				drew = true
			if not drew: _dummy(im)
			im.surface_end()
			# surf 1: selected edges
			im.surface_begin(Mesh.PRIMITIVE_LINES)
			drew = false
			for he in SelectionState.edges:
				im.surface_add_vertex(hem.get_vertex_position(hem.get_half_edge_vertex(he)))
				im.surface_add_vertex(hem.get_vertex_position(hem.get_half_edge_vertex(hem.get_half_edge_next(he))))
				drew = true
			if not drew: _dummy(im)
			im.surface_end()
			# surf 2: hovered edge
			im.surface_begin(Mesh.PRIMITIVE_LINES)
			if hovered_edge != -1 and hovered_edge not in SelectionState.edges:
				im.surface_add_vertex(hem.get_vertex_position(hem.get_half_edge_vertex(hovered_edge)))
				im.surface_add_vertex(hem.get_vertex_position(hem.get_half_edge_vertex(hem.get_half_edge_next(hovered_edge))))
			else:
				_dummy(im)
			im.surface_end()
			# surf 3-4: tool preview (lines + triangles)
			_ov_tool_preview(im)
			_overlay.mesh = im
			_overlay.set_surface_override_material(0, _mat_wire_dim)
			_overlay.set_surface_override_material(1, _mat_wire_sel)
			_overlay.set_surface_override_material(2, _mat_wire_hover)
			_overlay.set_surface_override_material(3, _mat_tool_preview)
			_overlay.set_surface_override_material(4, _mat_tool_preview)

		Mode.FACE:
			# surf 0: all edges dim
			_ov_all_edges(im)
			# surf 1: selected face outlines
			im.surface_begin(Mesh.PRIMITIVE_LINES)
			var drew := false
			for fi in SelectionState.faces:
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
			# surf 3-4: tool preview (lines + triangles)
			_ov_tool_preview(im)
			_overlay.mesh = im
			_overlay.set_surface_override_material(0, _mat_wire_dim)
			_overlay.set_surface_override_material(1, _mat_wire_sel)
			_overlay.set_surface_override_material(2, null)
			_overlay.set_surface_override_material(3, _mat_tool_preview)
			_overlay.set_surface_override_material(4, _mat_tool_preview)

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
		var is_sel := i in SelectionState.vertices
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
	if SelectionState.active_tool != null:
		SelectionState.active_tool.draw_preview(im, hem)
	else:
		im.surface_begin(Mesh.PRIMITIVE_LINES)
		_dummy(im)
		im.surface_end()
		im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
		_dummy_tri(im)
		im.surface_end()

func _dummy(im: ImmediateMesh) -> void:
	im.surface_set_color(Color.TRANSPARENT)
	im.surface_add_vertex(Vector3.ZERO)
	im.surface_set_color(Color.TRANSPARENT)
	im.surface_add_vertex(Vector3.ZERO)

func _dummy_tri(im: ImmediateMesh) -> void:
	im.surface_set_color(Color.TRANSPARENT)
	im.surface_add_vertex(Vector3.ZERO)
	im.surface_set_color(Color.TRANSPARENT)
	im.surface_add_vertex(Vector3.ZERO)
	im.surface_set_color(Color.TRANSPARENT)
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
