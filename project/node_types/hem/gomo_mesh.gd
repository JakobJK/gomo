extends Node3D
class_name GomoMesh


enum Mode { OBJECT, VERTEX, EDGE, FACE }

var mode:   Mode         = Mode.OBJECT
var hem:    HalfEdgeMesh = HalfEdgeMesh.new()
var camera: Camera3D     = null

var _mesh_instance:   MeshInstance3D
var _overlay:         MeshInstance3D
var _subdiv_instance: MeshInstance3D
var _subdiv_levels:      int              = 4
var _subdiv_visible:     bool             = false
var _normal_map_tex:     ImageTexture     = null
var _normal_map_visible: bool             = false

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
var _mat_wire_crease:  StandardMaterial3D
var _mat_wire_object:  StandardMaterial3D
var _mat_tool_preview: StandardMaterial3D

var _mat_subdiv:    StandardMaterial3D
var _mat_mesh_nm:   ShaderMaterial

func _ready() -> void:
	EventBus.instance.render_mode_changed.connect(func(_m): refresh())
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
	_mat_wire_crease  = _make_wire(Color(0.2,  0.6,  1.0))
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
	mat.cull_mode    = BaseMaterial3D.CULL_DISABLED
	mat.albedo_color = color
	return mat

func _process(_delta: float) -> void:
	if camera == null:
		return
	var vp_mouse := _subvp_mouse()
	if mode == Mode.OBJECT:
		if SelectionState.active_tool != null and SelectionState.context == self:
			sync_tool_state()
			SelectionState.active_tool.handle_hover(vp_mouse, hem, camera)
			_draw_overlay()
		return
	if SelectionState.active_tool != null:
		sync_tool_state()
		SelectionState.active_tool.handle_hover(vp_mouse, hem, camera)
	else:
		_update_hover(vp_mouse)
	_draw_overlay()

# --- Public API ---

func apply_baked_normal_map(subdiv_levels: int = 2, resolution: int = 2048) -> void:
	var image := hem.bake_normal_map(subdiv_levels, resolution)
	if image == null:
		return
	_normal_map_tex = ImageTexture.create_from_image(image)
	var shader := load("res://shaders/object_space_normal.gdshader")
	_mat_mesh_nm = ShaderMaterial.new()
	_mat_mesh_nm.shader = shader
	_mat_mesh_nm.set_shader_parameter("normal_map_tex", _normal_map_tex)
	set_display_mode(DisplayMode.NORMAL_MAP)
	EventBus.instance.normal_map_baked.emit(image)

enum DisplayMode { BASE, SUBDIVIDED, NORMAL_MAP }
var display_mode: DisplayMode = DisplayMode.BASE

func set_display_mode(dm: DisplayMode, levels: int = 4) -> void:
	display_mode    = dm
	_subdiv_levels  = levels
	_subdiv_visible = dm == DisplayMode.SUBDIVIDED
	_normal_map_visible = dm == DisplayMode.NORMAL_MAP and _mat_mesh_nm != null
	match dm:
		DisplayMode.BASE:
			_subdiv_instance.visible         = false
			_mesh_instance.material_override = null
			_mesh_instance.visible           = SelectionState.render_mode != SelectionState.RENDER_WIREFRAME
		DisplayMode.SUBDIVIDED:
			_subdiv_instance.mesh    = hem.subdivide_to_mesh(_subdiv_levels)
			_subdiv_instance.visible = true
			_mesh_instance.visible   = false
			_mesh_instance.material_override = null
		DisplayMode.NORMAL_MAP:
			if _mat_mesh_nm == null:
				return
			_subdiv_instance.visible         = false
			_mesh_instance.visible           = SelectionState.render_mode != SelectionState.RENDER_WIREFRAME
			_mesh_instance.material_override = _mat_mesh_nm

func _update_subdiv() -> void:
	if _subdiv_visible:
		_subdiv_instance.mesh    = hem.subdivide_to_mesh(_subdiv_levels)
		_subdiv_instance.visible = true
		_mesh_instance.visible   = false
	else:
		_subdiv_instance.visible = false
		_mesh_instance.visible   = SelectionState.render_mode != SelectionState.RENDER_WIREFRAME

func build_box(width: float = 2.0, height: float = 2.0, depth: float = 2.0,
			   width_segments: int = 1, height_segments: int = 1, depth_segments: int = 1) -> void:
	hem.build_box(width, height, depth, width_segments, height_segments, depth_segments)
	refresh()

func build_sphere(lat_segments: int = 8, lon_segments: int = 16) -> void:
	hem.build_sphere(lat_segments, lon_segments)
	refresh()

func build_cylinder(sides: int = 8, radius: float = 1.0, height: float = 2.0) -> void:
	hem.build_cylinder(sides, radius, height)
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
	EventBus.instance.mode_changed.emit(mode)
	refresh()

func set_tool(tool: ViewportController) -> void:
	SelectionState.set_tool(tool)
	if SelectionState.active_tool != null:
		sync_tool_state()
	_draw_overlay()

func redraw() -> void:
	_draw_overlay()

func do_undo() -> void:
	if hem.undo(): _clear_selection(); refresh()

func do_redo() -> void:
	if hem.redo(): _clear_selection(); refresh()

func ray_hits(ray_from: Vector3, ray_dir: Vector3) -> bool:
	var local_from := global_transform.affine_inverse() * ray_from
	var local_dir  := global_transform.basis.inverse() * ray_dir
	return hem.pick_face(local_from, local_dir) != -1

# Keyboard-only input — called by world._unhandled_input
func handle_key(event: InputEvent) -> bool:
	if event.is_action_pressed("redo", false, true):
		var changed := hem.redo()
		if changed: _clear_selection(); refresh()
		return true
	if event.is_action_pressed("undo", false, true):
		var changed := hem.undo()
		if changed: _clear_selection(); refresh()
		return true

	if mode == Mode.OBJECT: return false

	if event.is_action_pressed("tool_edge_loop", false, true) and mode == Mode.EDGE:
		set_tool(null if SelectionState.active_tool is EdgeLoopTool else EdgeLoopTool.new())
		return true
	if event.is_action_pressed("tool_crease", false, true) and mode == Mode.EDGE:
		set_tool(null if SelectionState.active_tool is CreaseTool else CreaseTool.new())
		return true

	if event.is_action_pressed("op_extrude", false, true): return _do_extrude()
	if event.is_action_pressed("op_delete",  false, true): return _do_delete()

	return false

# --- Operations ---

func _do_extrude() -> bool:
	match mode:
		Mode.EDGE:
			if SelectionState.edges.is_empty(): return false
			var boundary_edges := PackedInt32Array()
			for he in SelectionState.edges:
				if hem.get_half_edge_twin(he) == -1:
					boundary_edges.append(he)
			if boundary_edges.is_empty(): return false
			var new_edges := hem.extrude_edges(boundary_edges)
			SelectionState.clear_components()
			for i in new_edges:
				SelectionState.add_edge(i)
			sync_tool_state()
			refresh()
			return true
		Mode.FACE:
			if SelectionState.faces.is_empty(): return false
			var new_faces := hem.extrude_faces(PackedInt32Array(SelectionState.faces))
			SelectionState.clear_components()
			for fi in new_faces:
				SelectionState.add_face(fi)
			sync_tool_state()
			refresh()
			return true
	return false

func _do_delete() -> bool:
	if mode == Mode.FACE and not SelectionState.faces.is_empty():
		for fi in SelectionState.faces:
			hem.delete_face(fi)
		SelectionState.clear_components()
		sync_tool_state()
		refresh()
		return true
	return false


# --- Selection ---
func click_select(pos: Vector2, additive: bool) -> void:
	_handle_selection_click(pos, additive)

func marquee_select(rect: Rect2, additive: bool) -> void:
	if camera == null: return
	if not additive:
		SelectionState.clear_components()
	match mode:
		Mode.VERTEX:
			for i in hem.get_vertex_count():
				var sp := camera.unproject_position(global_transform * hem.get_vertex_position(i))
				if rect.has_point(sp):
					SelectionState.add_vertex(i)
		Mode.EDGE:
			for i in hem.get_edge_count():
				var twin: int = hem.get_half_edge_twin(i)
				if twin == -1 and hem.get_half_edge_face(i) == -1: continue
				if twin != -1 and i > twin: continue
				var canonical := mini(i, twin) if twin != -1 else i
				var p0 := global_transform * hem.get_vertex_position(hem.get_half_edge_vertex(i))
				var p1 := global_transform * hem.get_vertex_position(hem.get_half_edge_vertex(hem.get_half_edge_next(i)))
				if rect.has_point(camera.unproject_position(p0)) and rect.has_point(camera.unproject_position(p1)):
					SelectionState.add_edge(canonical)
		Mode.FACE:
			for fi in hem.get_face_count():
				if not hem.is_face_valid(fi): continue
				var sp := camera.unproject_position(global_transform * hem.get_face_center(fi))
				if rect.has_point(sp):
					SelectionState.add_face(fi)
	if SelectionState.active_tool != null:
		sync_tool_state()
	_draw_overlay()

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
		sync_tool_state()
	_draw_overlay()


func sync_tool_state() -> void:
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

func _subvp_mouse() -> Vector2:
	if camera == null: return Vector2.ZERO
	var subvp := camera.get_viewport()
	var container := subvp.get_parent() as SubViewportContainer
	if container == null: return subvp.get_mouse_position()
	var rect := container.get_global_rect()
	if rect.size.x <= 0.0: return subvp.get_mouse_position()
	var win_mouse := container.get_viewport().get_mouse_position()
	return (win_mouse - rect.position) / rect.size * Vector2(subvp.size)

# --- Rendering ---

func refresh() -> void:
	var array_mesh := hem.to_array_mesh()
	for i in array_mesh.get_surface_count():
		array_mesh.surface_set_material(i, _mat_mesh)
	_mesh_instance.mesh = array_mesh
	_mesh_instance.visible = SelectionState.render_mode != SelectionState.RENDER_WIREFRAME
	if _subdiv_visible:
		_update_subdiv()
	_draw_overlay()
	EventBus.instance.object_changed.emit(self)

func _draw_overlay() -> void:
	var im := ImmediateMesh.new()

	match mode:
		Mode.OBJECT:
			var rm := SelectionState.render_mode
			var show_wire := SelectionState.has(self) or rm != SelectionState.RENDER_SHADED
			if show_wire:
				im.surface_begin(Mesh.PRIMITIVE_LINES)
				for i in hem.get_edge_count():
					var twin: int = hem.get_half_edge_twin(i)
					if twin == -1 and hem.get_half_edge_face(i) == -1: continue
					if twin != -1 and i > twin: continue
					im.surface_add_vertex(hem.get_vertex_position(hem.get_half_edge_vertex(i)))
					im.surface_add_vertex(hem.get_vertex_position(hem.get_half_edge_vertex(hem.get_half_edge_next(i))))
				im.surface_end()
				var is_selected := SelectionState.has(self)
				var is_context  := SelectionState.context == self
				if is_context:
					_ov_tool_preview(im)
				_overlay.mesh = im
				var wire_mat := _mat_wire_object if is_selected else _mat_wire_dim
				_overlay.set_surface_override_material(0, wire_mat)
				if is_context:
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
			im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
			if hovered_vertex != -1 and hovered_vertex not in SelectionState.vertices:
				_draw_dot(im, hem.get_vertex_position(hovered_vertex))
			else:
				_dummy_tri(im)
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
			# surf 0: unselected, non-creased, non-hovered edges
			im.surface_begin(Mesh.PRIMITIVE_LINES)
			var drew := false
			for i in hem.get_edge_count():
				var twin: int = hem.get_half_edge_twin(i)
				if twin == -1 and hem.get_half_edge_face(i) == -1: continue
				if twin != -1 and i > twin: continue
				var canonical := mini(i, twin) if twin != -1 else i
				if canonical in SelectionState.edges: continue
				if i == hovered_edge or twin == hovered_edge: continue
				if hem.get_crease(i) > 0.0: continue
				im.surface_add_vertex(hem.get_vertex_position(hem.get_half_edge_vertex(i)))
				im.surface_add_vertex(hem.get_vertex_position(hem.get_half_edge_vertex(hem.get_half_edge_next(i))))
				drew = true
			if not drew: _dummy(im)
			im.surface_end()
			# surf 1: unselected, creased, non-hovered edges
			im.surface_begin(Mesh.PRIMITIVE_LINES)
			drew = false
			for i in hem.get_edge_count():
				var twin: int = hem.get_half_edge_twin(i)
				if twin == -1 and hem.get_half_edge_face(i) == -1: continue
				if twin != -1 and i > twin: continue
				var canonical := mini(i, twin) if twin != -1 else i
				if canonical in SelectionState.edges: continue
				if i == hovered_edge or twin == hovered_edge: continue
				if hem.get_crease(i) <= 0.0: continue
				im.surface_add_vertex(hem.get_vertex_position(hem.get_half_edge_vertex(i)))
				im.surface_add_vertex(hem.get_vertex_position(hem.get_half_edge_vertex(hem.get_half_edge_next(i))))
				drew = true
			if not drew: _dummy(im)
			im.surface_end()
			# surf 2: selected edges
			im.surface_begin(Mesh.PRIMITIVE_LINES)
			drew = false
			for he in SelectionState.edges:
				im.surface_add_vertex(hem.get_vertex_position(hem.get_half_edge_vertex(he)))
				im.surface_add_vertex(hem.get_vertex_position(hem.get_half_edge_vertex(hem.get_half_edge_next(he))))
				drew = true
			if not drew: _dummy(im)
			im.surface_end()
			# surf 3: hovered edge
			im.surface_begin(Mesh.PRIMITIVE_LINES)
			if hovered_edge != -1 and hovered_edge not in SelectionState.edges:
				im.surface_add_vertex(hem.get_vertex_position(hem.get_half_edge_vertex(hovered_edge)))
				im.surface_add_vertex(hem.get_vertex_position(hem.get_half_edge_vertex(hem.get_half_edge_next(hovered_edge))))
			else:
				_dummy(im)
			im.surface_end()
			# surf 4-5: tool preview (lines + triangles)
			_ov_tool_preview(im)
			_overlay.mesh = im
			_overlay.set_surface_override_material(0, _mat_wire_dim)
			_overlay.set_surface_override_material(1, _mat_wire_crease)
			_overlay.set_surface_override_material(2, _mat_wire_sel)
			_overlay.set_surface_override_material(3, _mat_wire_hover)
			_overlay.set_surface_override_material(4, _mat_tool_preview)
			_overlay.set_surface_override_material(5, _mat_tool_preview)

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
	im.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	var drew := false
	for i in hem.get_vertex_count():
		var is_sel := i in SelectionState.vertices
		if is_sel != only_selected: continue
		_draw_dot(im, hem.get_vertex_position(i))
		drew = true
	if not drew: _dummy_tri(im)
	im.surface_end()

func _draw_dot(im: ImmediateMesh, pos: Vector3) -> void:
	if camera == null: return
	var cam_local := global_transform.affine_inverse() * camera.global_position
	var sz    := pos.distance_to(cam_local) * Settings.instance.viewport.vertex_dot_size
	var right := (global_transform.basis.inverse() * camera.global_basis.x).normalized() * sz
	var up    := (global_transform.basis.inverse() * camera.global_basis.y).normalized() * sz
	const SEGS := 10
	for i in SEGS:
		var a0 := TAU * i / SEGS
		var a1 := TAU * (i + 1) / SEGS
		im.surface_add_vertex(pos)
		im.surface_add_vertex(pos + right * cos(a0) + up * sin(a0))
		im.surface_add_vertex(pos + right * cos(a1) + up * sin(a1))

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
