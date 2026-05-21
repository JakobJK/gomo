class_name ScenePanel
extends PanelContainer

signal selection_changed(nodes: Array[Node])

@onready var _tree: Tree = $VBox/Tree

var _syncing := false

var world: Node3D:
	set(v):
		if world != null:
			world.child_entered_tree.disconnect(_on_world_changed)
			world.child_exiting_tree.disconnect(_on_world_changed)
		world = v
		if world != null:
			world.child_entered_tree.connect(_on_world_changed)
			world.child_exiting_tree.connect(_on_world_changed)
		_refresh()

func _ready() -> void:
	_tree.focus_mode = Control.FOCUS_NONE
	_tree.item_selected.connect(_on_item_selected)
	_tree.multi_selected.connect(func(_i, _c, _s): _on_item_selected())
	EventBus.instance.selection_changed.connect(sync_selection)
	EventBus.instance.object_changed.connect(_on_object_changed)

func _on_world_changed(_node: Node) -> void:
	_refresh()

func sync_selection(nodes: Array[Node]) -> void:
	_syncing = true
	var item := _tree.get_root()
	if item != null:
		item = item.get_first_child()
		while item != null:
			if item.has_meta("node") and item.get_meta("node") in nodes:
				item.select(0)
			else:
				item.deselect(0)
			item = item.get_next()
	_syncing = false

func _on_item_selected() -> void:
	if _syncing:
		return
	var nodes: Array[Node] = []
	var item := _tree.get_next_selected(null)
	while item != null:
		if item.has_meta("node"):
			var node = item.get_meta("node")
			if is_instance_valid(node):
				nodes.append(node as Node)
		item = _tree.get_next_selected(item)
	selection_changed.emit(nodes)

func _refresh() -> void:
	_syncing = true
	_tree.clear()
	_syncing = false
	if world == null:
		return
	var root := _tree.create_item()
	root.set_text(0, "World")
	for child in world.get_children():
		if (child is GomoMesh) and not child.is_queued_for_deletion():
			var item := _tree.create_item(root)
			var def := TypeRegistry.get_for(child)
			if def != null:
				item.set_icon(0, def.icon)
			item.set_text(0, child.name)
			item.set_meta("node", child)

func _on_object_changed(obj: Node3D) -> void:
	var item := _tree.get_root()
	if item == null: return
	item = item.get_first_child()
	while item != null:
		if item.has_meta("node") and is_instance_valid(item.get_meta("node")) \
				and item.get_meta("node") == obj:
			item.set_text(0, obj.name)
			return
		item = item.get_next()
