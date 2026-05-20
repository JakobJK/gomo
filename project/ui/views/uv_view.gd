class_name UvView
extends PanelContainer

@onready var _canvas: Control = $VBox/Canvas
@onready var _vbox = $VBox
@onready var _btn_unwrap:      Button = $VBox/uv_tools/UnwrapButton
@onready var _btn_seam:        Button = $VBox/uv_tools/MarkSeamButton
@onready var _btn_merge_seam:  Button = $VBox/uv_tools/MergeSeamButton
@onready var _btn_save:        Button = $VBox/uv_tools/SaveNormalMapButton

func _ready() -> void:
	EventBus.instance.selection_changed.connect(_on_selection_changed)
	_vbox.clip_contents = true
	_btn_unwrap.pressed.connect(_on_unwrap_pressed)
	_btn_seam.pressed.connect(_on_mark_seam_pressed)
	_btn_merge_seam.pressed.connect(_on_merge_seam_pressed)
	_btn_save.pressed.connect(_on_save_pressed)

func _on_unwrap_pressed() -> void:
	if _canvas.gomo_mesh == null:
		return
	_canvas.gomo_mesh.hem.unwrap_uvs()
	_canvas.gomo_mesh.refresh()
	_canvas.edges         = _canvas.gomo_mesh.hem.get_uv_edges()
	_canvas.seam_edges    = _canvas.gomo_mesh.hem.get_uv_seam_edges()
	_canvas.face_polygons = _canvas.gomo_mesh.hem.get_uv_face_polygons()
	_canvas.reset_view()

func _on_mark_seam_pressed() -> void:
	if _canvas.gomo_mesh == null:
		return
	for he in SelectionState.edges:
		_canvas.gomo_mesh.hem.set_seam(he, true)
	_canvas.seam_edges = _canvas.gomo_mesh.hem.get_uv_seam_edges()
	_canvas.queue_redraw()

func _on_merge_seam_pressed() -> void:
	if _canvas.gomo_mesh == null:
		return
	for he in SelectionState.edges:
		_canvas.gomo_mesh.hem.set_seam(he, false)
	_canvas.seam_edges = _canvas.gomo_mesh.hem.get_uv_seam_edges()
	_canvas.queue_redraw()

func _on_save_pressed() -> void:
	if _canvas.last_baked_image == null:
		return
	var dialog := FileDialog.new()
	dialog.file_mode  = FileDialog.FILE_MODE_SAVE_FILE
	dialog.filters    = PackedStringArray(["*.png ; PNG Image"])
	dialog.current_file = "normal_map.png"
	dialog.file_selected.connect(func(path: String) -> void:
		_canvas.last_baked_image.save_png(path)
		dialog.queue_free()
	)
	dialog.canceled.connect(func() -> void: dialog.queue_free())
	add_child(dialog)
	dialog.popup_centered(Vector2i(900, 600))

func _on_selection_changed(nodes: Array[Node]) -> void:
	var gomo: GomoMesh = null
	for n in nodes:
		if n is GomoMesh:
			gomo = n
			break
	set_mesh(gomo)

func set_mesh(gomo: GomoMesh) -> void:
	_canvas.gomo_mesh     = gomo
	_canvas.edges         = gomo.hem.get_uv_edges()         if gomo != null else PackedVector2Array()
	_canvas.seam_edges    = gomo.hem.get_uv_seam_edges()    if gomo != null else PackedVector2Array()
	_canvas.face_polygons = gomo.hem.get_uv_face_polygons() if gomo != null else []
	_canvas.reset_view()
