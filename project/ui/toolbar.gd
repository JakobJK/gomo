extends HBoxContainer

const _MoveTool = preload("res://tools/move_tool.gd")

@onready var _btn_move: Button = $MoveButton

func _ready() -> void:
	_btn_move.icon         = _load_icon("res://icons/move.svg")
	_btn_move.tooltip_text = "Move  W"
	_btn_move.pressed.connect(_on_move_pressed)

func _load_icon(path: String) -> ImageTexture:
	var svg := FileAccess.get_file_as_string(path)
	svg = svg.replace("currentColor", "white")
	var img := Image.new()
	img.load_svg_from_string(svg)
	return ImageTexture.create_from_image(img)

func _process(_delta: float) -> void:
	_btn_move.button_pressed = SelectionState.active_tool is _MoveTool

func _on_move_pressed() -> void:
	if SelectionState.active_tool is _MoveTool:
		SelectionState.set_tool(null)
	else:
		SelectionState.set_tool(_MoveTool.new())
	for obj in SelectionState.objects:
		obj.redraw()
