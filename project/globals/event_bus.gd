class_name EventBus
extends RefCounted

static var instance := EventBus.new()

signal selection_changed(nodes: Array[Node])
signal object_changed(obj: Node3D)
signal tool_changed(tool: ViewportController)
signal mode_changed(mode: int)
signal render_mode_changed(mode: int)
signal normal_map_baked(image: Image)
signal request_add_box
signal request_add_cylinder
signal request_delete_selected
