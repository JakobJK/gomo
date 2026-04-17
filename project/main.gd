extends Node3D

@onready var camera: Camera3D = $Camera3D
@onready var mesh_instance: MeshInstance3D = $MeshInstance3D

var hem := HalfEdgeMesh.new()
var selected_vertex := -1
var drag_plane := Plane()

const PICK_RADIUS_PX := 20.0

func _ready() -> void:
	mesh_instance.transform = Transform3D.IDENTITY
	hem.build_from_triangles(PackedVector3Array([
		Vector3(-1.0, -1.0, 0.0),
		Vector3( 0.0,  1.0, 0.0),
		Vector3( 1.0, -1.0, 0.0),
	]))
	mesh_instance.mesh = _build_mesh()

func _build_mesh() -> ArrayMesh:
	var array_mesh := hem.to_array_mesh()
	var mat := StandardMaterial3D.new()
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.albedo_color = Color(0.8, 0.5, 0.2)
	array_mesh.surface_set_material(0, mat)
	return array_mesh

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			selected_vertex = _pick_vertex(event.position)
			if selected_vertex != -1:
				var vpos := hem.get_vertex_position(selected_vertex)
				drag_plane = Plane(-camera.global_basis.z, vpos)
				get_viewport().set_input_as_handled()
		else:
			selected_vertex = -1

	elif event is InputEventMouseMotion and selected_vertex != -1:
		var from := camera.project_ray_origin(event.position)
		var dir  := camera.project_ray_normal(event.position)
		var hit: Variant = drag_plane.intersects_ray(from, dir)
		if hit != null:
			hem.set_vertex_position(selected_vertex, hit)
			mesh_instance.mesh = _build_mesh()
			get_viewport().set_input_as_handled()

func _pick_vertex(mouse_pos: Vector2) -> int:
	var positions := hem.get_vertex_positions()
	var best_idx := -1
	var best_dist := PICK_RADIUS_PX * PICK_RADIUS_PX

	for i in positions.size():
		var screen_pos := camera.unproject_position(positions[i])
		var d := mouse_pos.distance_squared_to(screen_pos)
		if d < best_dist:
			best_dist = d
			best_idx = i

	return best_idx
