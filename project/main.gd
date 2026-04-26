extends Node3D

const _MoveTool = preload("res://tools/move_tool.gd")

@onready var camera: Camera3D = $perspective

var mesh_objects:   Array[MeshObject] = []
var focused_object: MeshObject        = null

func _ready() -> void:
	Keymap.setup()
	get_viewport().msaa_3d = Viewport.MSAA_4X

	# Key light — warm, front-right, main source of specular highlights
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

	var obj := _spawn_mesh_object()
	obj.build_box()

func _spawn_mesh_object() -> MeshObject:
	var obj := MeshObject.new()
	obj.camera = camera
	add_child(obj)
	mesh_objects.append(obj)
	return obj

func _input(event: InputEvent) -> void:
	# Object-mode tool shortcuts — scene-wide, not per-object
	if focused_object != null and focused_object.mode == MeshObject.Mode.OBJECT:
		if event.is_action_pressed("tool_move"):
			GlobalState.set_tool(null if GlobalState.active_tool is _MoveTool else _MoveTool.new())
			focused_object.redraw()
			get_viewport().set_input_as_handled()
			return
		if event.is_action_pressed("tool_none"):
			GlobalState.set_tool(null)
			focused_object.redraw()
			get_viewport().set_input_as_handled()
			return

	# Mode switching
	if focused_object != null:
		var mode_key := -1
		if   event.is_action_pressed("mode_object"): mode_key = MeshObject.Mode.OBJECT
		elif event.is_action_pressed("mode_vertex"): mode_key = MeshObject.Mode.VERTEX
		elif event.is_action_pressed("mode_edge"):   mode_key = MeshObject.Mode.EDGE
		elif event.is_action_pressed("mode_face"):   mode_key = MeshObject.Mode.FACE
		if mode_key != -1:
			focused_object.set_mode(mode_key as MeshObject.Mode)
			get_viewport().set_input_as_handled()
			return

	# Non-object mode objects get first pass at all events
	for obj in mesh_objects:
		if obj.mode != MeshObject.Mode.OBJECT:
			if obj.handle_input(event):
				get_viewport().set_input_as_handled()
				return

	# Focused object in object mode gets input for tool activation and gizmo use
	if focused_object != null and focused_object.mode == MeshObject.Mode.OBJECT:
		if focused_object.handle_input(event):
			get_viewport().set_input_as_handled()
			return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
		var ray_from := camera.project_ray_origin(event.position)
		var ray_dir  := camera.project_ray_normal(event.position)

		for obj in mesh_objects:
			if obj.mode == MeshObject.Mode.OBJECT and obj.ray_hits(ray_from, ray_dir):
				_focus(obj)
				get_viewport().set_input_as_handled()
				return

		# Clicked empty space — deselect
		if focused_object != null and focused_object.mode == MeshObject.Mode.OBJECT:
			GlobalState.remove(focused_object)
			focused_object.redraw()
			focused_object = null

func _focus(obj: MeshObject) -> void:
	if focused_object != null and focused_object != obj:
		GlobalState.remove(focused_object)
		focused_object.redraw()
	focused_object = obj
	GlobalState.add(obj)
	obj.redraw()
