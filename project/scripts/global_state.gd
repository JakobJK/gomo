class_name GlobalState
extends RefCounted

# --- Active Tool ---

static var active_tool: ModellingTool = null

static func set_tool(tool: ModellingTool) -> void:
	if active_tool != null:
		active_tool.on_deactivate()
	active_tool = tool
	if active_tool != null:
		active_tool.on_activate()

# --- Selection ---

static var objects:  Array[MeshObject] = []
static var context:  MeshObject        = null
static var vertices: PackedInt32Array  = []
static var edges:    PackedInt32Array  = []
static var faces:    PackedInt32Array  = []

static func add(obj: MeshObject) -> void:
	if obj not in objects: objects.append(obj)

static func remove(obj: MeshObject) -> void:
	objects.erase(obj)

static func has(obj: MeshObject) -> bool:
	return obj in objects

static func set_context(obj: MeshObject) -> void:
	if context != obj:
		clear_components()
		context = obj

static func clear_components() -> void:
	vertices = PackedInt32Array()
	edges    = PackedInt32Array()
	faces    = PackedInt32Array()

static func add_vertex(i: int) -> void:
	if i not in vertices: vertices.push_back(i)

static func remove_vertex(i: int) -> void:
	vertices = _filter(vertices, i)

static func toggle_vertex(i: int) -> void:
	if i in vertices: remove_vertex(i)
	else:             add_vertex(i)

static func add_edge(i: int) -> void:
	if i not in edges: edges.push_back(i)

static func remove_edge(i: int) -> void:
	edges = _filter(edges, i)

static func toggle_edge(i: int) -> void:
	if i in edges: remove_edge(i)
	else:          add_edge(i)

static func add_face(i: int) -> void:
	if i not in faces: faces.push_back(i)

static func remove_face(i: int) -> void:
	faces = _filter(faces, i)

static func toggle_face(i: int) -> void:
	if i in faces: remove_face(i)
	else:          add_face(i)

static func _filter(arr: PackedInt32Array, val: int) -> PackedInt32Array:
	var out := PackedInt32Array()
	for v in arr:
		if v != val: out.push_back(v)
	return out
