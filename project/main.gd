extends Node3D

@onready var camera: Camera3D = $perspective

var mesh_objects:   Array[MeshObject] = []
var focused_object: MeshObject        = null

var _drag_object: MeshObject = null
var _drag_plane:  Plane
var _drag_offset: Vector3

func _ready() -> void:
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
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_N:
			for obj in mesh_objects:
				obj.toggle_debug_normals()
			get_viewport().set_input_as_handled()
			return

		# Mode switching — any component mode object gets first pass
		var mode_key := -1
		match event.keycode:
			KEY_1: mode_key = MeshObject.Mode.OBJECT
			KEY_2: mode_key = MeshObject.Mode.VERTEX
			KEY_3: mode_key = MeshObject.Mode.EDGE
			KEY_4: mode_key = MeshObject.Mode.FACE
		if mode_key != -1 and focused_object != null:
			focused_object.set_mode(mode_key as MeshObject.Mode)
			get_viewport().set_input_as_handled()
			return

	# Non-object mode objects get first pass at all events
	for obj in mesh_objects:
		if obj.mode != MeshObject.Mode.OBJECT:
			if obj.handle_input(event):
				get_viewport().set_input_as_handled()
				return

	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			var ray_from := camera.project_ray_origin(event.position)
			var ray_dir  := camera.project_ray_normal(event.position)

			for obj in mesh_objects:
				if obj.mode == MeshObject.Mode.OBJECT and obj.ray_hits(ray_from, ray_dir):
					_focus(obj)
					_drag_plane  = Plane(-camera.global_basis.z, obj.global_position)
					var hit: Variant = _drag_plane.intersects_ray(ray_from, ray_dir)
					_drag_offset = (hit - obj.global_position) if hit != null else Vector3.ZERO
					_drag_object = obj
					get_viewport().set_input_as_handled()
					return

			# Clicked empty space — deselect in object mode
			if focused_object != null and focused_object.mode == MeshObject.Mode.OBJECT:
				focused_object.set_selected(false)
				focused_object = null

		else:
			_drag_object = null

	elif event is InputEventMouseMotion and _drag_object != null:
		var ray_from := camera.project_ray_origin(event.position)
		var ray_dir  := camera.project_ray_normal(event.position)
		var hit: Variant = _drag_plane.intersects_ray(ray_from, ray_dir)
		if hit != null:
			_drag_object.global_position = hit - _drag_offset
		get_viewport().set_input_as_handled()

func _focus(obj: MeshObject) -> void:
	if focused_object != null and focused_object != obj:
		focused_object.set_selected(false)
	focused_object = obj
	obj.set_selected(true)
