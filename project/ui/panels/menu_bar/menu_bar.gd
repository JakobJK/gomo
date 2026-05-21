extends MenuBar

func _ready() -> void:
	var file := _add_menu("File")
	file.add_item("New",       0)
	file.add_item("Open...",   1)
	file.add_separator()
	file.add_item("Save",      2)
	file.add_item("Save As...", 3)
	file.id_pressed.connect(_on_file)

	var edit := _add_menu("Edit")
	edit.add_item("Undo",          0)
	edit.add_item("Redo",          1)
	edit.add_separator()
	edit.add_item("Preferences...", 2)
	edit.id_pressed.connect(_on_edit)

	var object := _add_menu("Object")
	object.add_item("Add Box",      0)
	object.add_item("Add Cylinder", 1)
	object.add_separator()
	object.add_item("Delete",       2)
	object.id_pressed.connect(_on_object)

func _add_menu(title: String) -> PopupMenu:
	var pm := PopupMenu.new()
	pm.name = title
	add_child(pm)
	return pm

func _on_file(id: int) -> void:
	pass

func _on_edit(id: int) -> void:
	match id:
		0: EventBus.instance.request_undo.emit()
		1: EventBus.instance.request_redo.emit()
		2: pass  # Preferences — TODO

func _on_object(id: int) -> void:
	match id:
		0: EventBus.instance.request_add_box.emit()
		1: EventBus.instance.request_add_cylinder.emit()
		2: EventBus.instance.request_delete_selected.emit()
