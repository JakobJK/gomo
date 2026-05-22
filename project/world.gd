extends Node3D

var camera: Camera3D:
	set(v):
		camera = v
		for obj in mesh_objects:
			obj.camera = v


var mesh_objects:    Array[GomoMesh] = []
var focused_object:  GomoMesh        = null
var _obj_drag_init:  Dictionary      = {}

func _ready() -> void:
	Keymap.setup()
	get_viewport().msaa_3d = Viewport.MSAA_4X

	var key := DirectionalLight3D.new()
	key.rotation_degrees = Vector3(-35, 50, 0)
	key.light_color      = Color(1.0, 0.93, 0.82)
	key.light_energy     = 1.6
	add_child(key)

	# Fill light — cool, front-left, softens shadows
	var fill := DirectionalLight3D.new()
	fill.rotation_degrees = Vector3(-15, -130, 0)
	fill.light_color      = Color(0.75, 0.85, 1.0)
	fill.light_energy     = 0.45
	add_child(fill)

	# Rim light — back, separates the silhouette
	var rim := DirectionalLight3D.new()
	rim.rotation_degrees = Vector3(25, 175, 0)
	rim.light_color      = Color(0.9, 0.92, 1.0)
	rim.light_energy     = 0.5
	add_child(rim)

	# Ambient
	var env := Environment.new()
	env.background_mode        = Environment.BG_COLOR
	env.background_color       = Color(0.1, 0.1, 0.13)
	env.ambient_light_source   = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color    = Color(0.3, 0.32, 0.38)
	env.ambient_light_energy   = 0.4
	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

func setup() -> void:
	EventBus.instance.request_undo.connect(func(): if focused_object: focused_object.do_undo())
	EventBus.instance.request_redo.connect(func(): if focused_object: focused_object.do_redo())
	EventBus.instance.request_add_box.connect(_on_add_box)
	EventBus.instance.request_add_cylinder.connect(_on_add_cylinder)
	EventBus.instance.request_delete_selected.connect(_on_delete_selected)
	var obj := _spawn_mesh_object()
	obj.build_box(2.0, 2.0, 2.0,3,1,1)
	var s := _spawn_mesh_object()
	s.build_box()


func handle_tool_mouse(event: InputEvent) -> bool:
	for obj in mesh_objects:
		if obj.mode != GomoMesh.Mode.OBJECT:
			if State.active_tool == null: continue
			obj.sync_tool_state()
			if State.active_tool.handle_input(event, obj.hem, obj.camera):
				obj.refresh()
				return true

	if focused_object != null and focused_object.mode == GomoMesh.Mode.OBJECT:
		if State.active_tool == null or not State.has(focused_object):
			return false
		var tool := State.active_tool as MoveTool
		if tool != null:
			tool.skip_vertex_ops = true
		var was_dragging: bool = tool != null and tool.is_dragging
		if not was_dragging:
			focused_object.sync_tool_state()
		var consumed := State.active_tool.handle_input(event, focused_object.hem, focused_object.camera)
		if consumed: focused_object.refresh()

		if tool != null:
			if not was_dragging and tool.is_dragging:
				_obj_drag_init.clear()
				for obj: GomoMesh in State.objects:
					_obj_drag_init[obj] = obj.global_position
			elif was_dragging and not tool.is_dragging:
				_obj_drag_init.clear()
			elif tool.is_dragging and event is InputEventMouseMotion:
				for obj: GomoMesh in _obj_drag_init:
					obj.global_position = _obj_drag_init[obj] + tool.drag_world_delta
				EventBus.instance.object_changed.emit(focused_object)

		return consumed

	return false

func click_select(subvp_pos: Vector2, additive: bool) -> void:
	for obj in mesh_objects:
		if obj.mode != GomoMesh.Mode.OBJECT:
			obj.click_select(subvp_pos, additive)
			return
	var ray_from := camera.project_ray_origin(subvp_pos)
	var ray_dir  := camera.project_ray_normal(subvp_pos)
	for obj in mesh_objects:
		if obj.mode == GomoMesh.Mode.OBJECT and obj.ray_hits(ray_from, ray_dir):
			set_selection([obj])
			return
	if focused_object != null and focused_object.mode == GomoMesh.Mode.OBJECT:
		set_selection([])

func marquee_select(rect: Rect2, additive: bool) -> void:
	for obj in mesh_objects:
		if obj.mode != GomoMesh.Mode.OBJECT:
			obj.marquee_select(rect, additive)
			return
	if not additive:
		set_selection([])
	var hits: Array[Node] = []
	for obj in mesh_objects:
		if obj.mode != GomoMesh.Mode.OBJECT: continue
		for fi in obj.hem.get_face_count():
			if not obj.hem.is_face_valid(fi): continue
			if rect.has_point(camera.unproject_position(obj.global_transform * obj.hem.get_face_center(fi))):
				hits.append(obj)
				break
	if not hits.is_empty():
		set_selection(hits)

# --- Object management ---
func _on_add_box() -> void:
	var obj := _spawn_mesh_object()
	obj.build_box()
	set_selection([obj])

func _on_add_cylinder() -> void:
	var obj := _spawn_mesh_object()
	obj.build_cylinder()
	set_selection([obj])

func _on_delete_selected() -> void:
	var to_delete: Array[GomoMesh] = State.objects.duplicate()
	set_selection([])
	for obj in to_delete:
		mesh_objects.erase(obj)
		obj.queue_free()

func _spawn_mesh_object() -> GomoMesh:
	var obj := GomoMesh.new()
	obj.camera = camera
	add_child(obj)
	mesh_objects.append(obj)
	return obj

# --- Keyboard input only ---

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouse: return

	if event.is_action_pressed("tool_none", false, true) and State.active_tool != null:
		State.set_tool(null)
		for obj in State.objects:
			obj.redraw()
		get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("tool_move", false, true):
		State.set_tool(State.move_tool)
		for obj in State.objects: obj.redraw()
		get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("tool_rotate", false, true):
		State.set_tool(State.rotate_tool)
		for obj in State.objects: obj.redraw()
		get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("tool_scale", false, true):
		State.set_tool(State.scale_tool)
		for obj in State.objects: obj.redraw()
		get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("display_base", false, true) and focused_object != null:
		focused_object.set_display_mode(GomoMesh.DisplayMode.BASE)
		get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("display_subdiv", false, true) and focused_object != null:
		focused_object.set_display_mode(GomoMesh.DisplayMode.SUBDIVIDED)
		get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("display_normal_map", false, true) and focused_object != null:
		EventBus.instance.display_normal_map_requested.emit()
		get_viewport().set_input_as_handled()
		return

	if event.is_action_pressed("delete_object", false, true) and focused_object != null \
			and focused_object.mode == GomoMesh.Mode.OBJECT:
		_on_delete_selected()
		get_viewport().set_input_as_handled()
		return


	# Per-object keyboard (undo, ops, specialized tools)
	for obj in mesh_objects:
		if obj.mode != GomoMesh.Mode.OBJECT:
			if obj.handle_key(event):
				get_viewport().set_input_as_handled()
				return

	if focused_object != null and focused_object.mode == GomoMesh.Mode.OBJECT:
		if focused_object.handle_key(event):
			get_viewport().set_input_as_handled()
			return

func set_selection(nodes: Array[Node]) -> void:
	_obj_drag_init.clear()
	for obj in mesh_objects:
		if State.has(obj):
			State.remove(obj)
	focused_object = null
	for node in nodes:
		if node is GomoMesh:
			State.add(node)
			focused_object = node
	State.set_context(focused_object)
	for obj in mesh_objects:
		obj.redraw()
	EventBus.instance.selection_changed.emit(nodes)
