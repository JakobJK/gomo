class_name TypeRegistry

class TypeDef:
	var id:           String
	var display_name: String
	var icon:         ImageTexture
	var check:        Callable  # (Node) -> bool
	var attributes:   Array     # Array[AttributeDef] — populated per-type as needed

	func matches(node: Node) -> bool:
		return check.call(node)

# ── registration ──────────────────────────────────────────────────────────────

static var _types: Array[TypeDef] = []
static var _ready := false

static func _ensure_ready() -> void:
	if _ready:
		return
	_ready = true
	_reg("mesh",   "Mesh",   "res://icons/box.svg",    func(n): return n is GomoMesh)
	_reg("camera", "Camera", "res://icons/camera.svg",  func(n): return n is Camera3D)

static func _reg(id: String, name: String, icon_path: String, check: Callable) -> void:
	var d       := TypeDef.new()
	d.id          = id
	d.display_name = name
	d.icon        = _load_icon(icon_path)
	d.check       = check
	d.attributes  = []
	_types.append(d)

static func _load_icon(path: String) -> ImageTexture:
	var svg := FileAccess.get_file_as_string(path)
	svg = svg.replace("currentColor", "white")
	var img := Image.new()
	img.load_svg_from_string(svg, 0.65)
	return ImageTexture.create_from_image(img)

# ── queries ───────────────────────────────────────────────────────────────────

static func get_for(node: Node) -> TypeDef:
	_ensure_ready()
	for d in _types:
		if d.matches(node):
			return d
	return null

static func get_by_id(id: String) -> TypeDef:
	_ensure_ready()
	for d in _types:
		if d.id == id:
			return d
	return null

static func all() -> Array[TypeDef]:
	_ensure_ready()
	return _types
