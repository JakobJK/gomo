extends HBoxContainer

@onready var _btn_object:         Button       = $ObjectModeButton
@onready var _btn_vertex:         Button       = $VertexModeButton
@onready var _btn_edge:           Button       = $EdgeModeButton
@onready var _btn_face:           Button       = $FaceModeButton
@onready var _btn_move:           Button       = $MoveButton
@onready var _btn_rotate:         Button       = $RotateButton
@onready var _btn_scale:          Button       = $ScaleButton
@onready var _btn_shaded:         Button       = $ShadedButton
@onready var _btn_wireframe:      Button       = $WireframeButton
@onready var _btn_wire_on_shade:  Button       = $WireOnShadedButton
@onready var _btn_add_box:        Button       = $AddBoxButton
@onready var _btn_add_cylinder:   Button       = $AddCylinderButton
@onready var _btn_delete:         Button       = $DeleteObjectButton
@onready var _spin_subdiv:        SpinBox      = $BakeSubdivSpin
@onready var _btn_bake:           Button       = $BakeNormalMapButton
@onready var _chk_auto_bake:      CheckButton  = $AutoBakeCheck

var _mode_group   := ButtonGroup.new()
var _render_group := ButtonGroup.new()

func _ready() -> void:
	_btn_object.icon         = _load_icon("box")
	_btn_object.tooltip_text = "Object"
	_btn_vertex.icon         = _load_icon("circle")
	_btn_vertex.tooltip_text = "Vertex"
	_btn_edge.icon           = _load_icon("git-commit")
	_btn_edge.tooltip_text   = "Edge"
	_btn_face.icon           = _load_icon("square")
	_btn_face.tooltip_text   = "Face"

	for btn in [_btn_object, _btn_vertex, _btn_edge, _btn_face]:
		btn.button_group = _mode_group
		btn.toggle_mode  = true
		btn.flat         = true

	_btn_object.pressed.connect(func(): _on_mode_pressed(GomoMesh.Mode.OBJECT))
	_btn_vertex.pressed.connect(func(): _on_mode_pressed(GomoMesh.Mode.VERTEX))
	_btn_edge.pressed.connect(func(): _on_mode_pressed(GomoMesh.Mode.EDGE))
	_btn_face.pressed.connect(func(): _on_mode_pressed(GomoMesh.Mode.FACE))

	_btn_move.toggle_mode   = false
	_btn_move.icon          = _load_icon("move")
	_btn_move.tooltip_text  = "Move  W"
	_btn_move.pressed.connect(_on_move_pressed)

	_btn_rotate.toggle_mode  = false
	_btn_rotate.icon         = _load_icon("rotate-cw")
	_btn_rotate.tooltip_text = "Rotate  E"
	_btn_rotate.pressed.connect(_on_rotate_pressed)

	_btn_scale.toggle_mode   = false
	_btn_scale.icon          = _load_icon("maximize-2")
	_btn_scale.tooltip_text  = "Scale  R"
	_btn_scale.pressed.connect(_on_scale_pressed)

	_btn_shaded.icon            = _load_icon("sun")
	_btn_shaded.tooltip_text    = "Shaded"
	_btn_wireframe.icon         = _load_icon("triangle")
	_btn_wireframe.tooltip_text = "Wireframe"
	_btn_wire_on_shade.icon         = _load_icon("layers")
	_btn_wire_on_shade.tooltip_text = "Wireframe on Shaded"

	_btn_add_box.icon         = _load_icon("box")
	_btn_add_box.tooltip_text = "Add Box"
	_btn_add_box.flat         = true
	_btn_add_box.pressed.connect(func(): EventBus.instance.request_add_box.emit())

	_btn_add_cylinder.icon         = _load_icon("circle")
	_btn_add_cylinder.tooltip_text = "Add Cylinder"
	_btn_add_cylinder.flat         = true
	_btn_add_cylinder.pressed.connect(func(): EventBus.instance.request_add_cylinder.emit())

	_btn_delete.icon         = _load_icon("trash-2")
	_btn_delete.tooltip_text = "Delete  Del"
	_btn_delete.flat         = true
	_btn_delete.disabled     = true
	_btn_delete.pressed.connect(func(): EventBus.instance.request_delete_selected.emit())

	_btn_bake.icon         = _load_icon("image")
	_btn_bake.tooltip_text = "Bake Normal Map"
	_btn_bake.pressed.connect(_on_bake_pressed)

	_chk_auto_bake.tooltip_text = "Auto-bake on normal map preview"
	EventBus.instance.display_normal_map_requested.connect(_on_display_normal_map_requested)

	for btn in [_btn_shaded, _btn_wireframe, _btn_wire_on_shade]:
		btn.button_group = _render_group
		btn.toggle_mode  = true
		btn.flat         = true

	_btn_shaded.pressed.connect(func(): _on_render_pressed(SelectionState.RENDER_SHADED))
	_btn_wireframe.pressed.connect(func(): _on_render_pressed(SelectionState.RENDER_WIREFRAME))
	_btn_wire_on_shade.pressed.connect(func(): _on_render_pressed(SelectionState.RENDER_WIREFRAME_ON_SHADED))

	EventBus.instance.tool_changed.connect(_on_tool_changed)
	EventBus.instance.mode_changed.connect(_on_mode_changed)
	EventBus.instance.render_mode_changed.connect(_on_render_mode_changed)
	EventBus.instance.selection_changed.connect(_on_selection_changed)

	_on_mode_changed(GomoMesh.Mode.OBJECT)
	_on_render_mode_changed(SelectionState.RENDER_SHADED)

func _load_icon(name: String) -> ImageTexture:
	var svg := FileAccess.get_file_as_string("res://ui/icons/" + name + ".svg")
	svg = svg.replace("currentColor", "white")
	var img := Image.new()
	img.load_svg_from_string(svg)
	return ImageTexture.create_from_image(img)

func _on_mode_changed(mode: int) -> void:
	var btns := [_btn_object, _btn_vertex, _btn_edge, _btn_face]
	for i in btns.size():
		btns[i].modulate = Palette.ACTIVE if i == mode else Color.WHITE

func _on_render_mode_changed(mode: int) -> void:
	var btns := [_btn_shaded, _btn_wireframe, _btn_wire_on_shade]
	for i in btns.size():
		btns[i].modulate = Palette.ACTIVE if i == mode else Color.WHITE

func _on_tool_changed(tool: ViewportController) -> void:
	_btn_move.modulate    = Palette.ACTIVE if tool is MoveTool    else Color.WHITE
	_btn_rotate.modulate  = Palette.ACTIVE if tool is RotateTool  else Color.WHITE
	_btn_scale.modulate   = Palette.ACTIVE if tool is ScaleTool   else Color.WHITE

func _on_mode_pressed(mode: int) -> void:
	var context := SelectionState.context
	if context != null:
		context.set_mode(mode as GomoMesh.Mode)
	else:
		for obj in SelectionState.objects:
			obj.set_mode(mode as GomoMesh.Mode)

func _on_render_pressed(mode: int) -> void:
	SelectionState.set_render_mode(mode)

func _on_move_pressed() -> void:
	if SelectionState.active_tool is MoveTool: return
	SelectionState.set_tool(SelectionState.move_tool)
	for obj in SelectionState.objects: obj.redraw()

func _on_rotate_pressed() -> void:
	if SelectionState.active_tool is RotateTool: return
	SelectionState.set_tool(SelectionState.rotate_tool)
	for obj in SelectionState.objects: obj.redraw()

func _on_scale_pressed() -> void:
	if SelectionState.active_tool is ScaleTool: return
	SelectionState.set_tool(SelectionState.scale_tool)
	for obj in SelectionState.objects: obj.redraw()

func _on_selection_changed(nodes: Array[Node]) -> void:
	_btn_delete.disabled = nodes.is_empty()

func _on_display_normal_map_requested() -> void:
	var obj: GomoMesh = SelectionState.context
	if obj == null and not SelectionState.objects.is_empty():
		obj = SelectionState.objects[0]
	if obj == null:
		return
	if _chk_auto_bake.button_pressed:
		obj.apply_baked_normal_map(int(_spin_subdiv.value))
	else:
		obj.set_display_mode(GomoMesh.DisplayMode.NORMAL_MAP)

func _on_bake_pressed() -> void:
	var obj: GomoMesh = SelectionState.context
	if obj == null and not SelectionState.objects.is_empty():
		obj = SelectionState.objects[0]
	if obj == null: return
	obj.apply_baked_normal_map(int(_spin_subdiv.value))
