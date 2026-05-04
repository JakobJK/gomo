class_name UvView
extends PanelContainer

@onready var _canvas: Control = $VBox/Canvas

func _ready() -> void:
	EventBus.instance.selection_changed.connect(_on_selection_changed)

func _on_selection_changed(nodes: Array[Node]) -> void:
	var gomo: GomoMesh = null
	for n in nodes:
		if n is GomoMesh:
			gomo = n
			break
	set_mesh(gomo)

func set_mesh(gomo: GomoMesh) -> void:
	_canvas.gomo_mesh = gomo
	_canvas.edges = gomo.hem.get_uv_edges() if gomo != null else PackedVector2Array()
	_canvas.reset_view()
