class_name PropertiesPanel
extends PanelContainer

@onready var _vbox: VBoxContainer = $m/VBox

var _target:     Node3D        = null
var _updating    := false

var _name_field: LineEdit
var _pos_fields: Array[SpinBox] = []
var _rot_fields: Array[SpinBox] = []
var _scl_fields: Array[SpinBox] = []

func _ready() -> void:
	_name_field = _add_text_row("Name")
	_name_field.text_submitted.connect(_on_name_submitted)
	_name_field.focus_exited.connect(_on_name_focus_exited)

	_pos_fields = _add_vec3_row("Position")
	_rot_fields = _add_vec3_row("Rotation")
	_scl_fields = _add_vec3_row("Scale")

	for spin in _all_spin_fields():
		spin.value_changed.connect(func(_v): _on_transform_changed())

	_set_editable(false)
	EventBus.instance.selection_changed.connect(set_selection)
	EventBus.instance.object_changed.connect(_on_object_changed)

func _on_object_changed(obj: Node3D) -> void:
	if obj == _target:
		_write_fields()

func set_selection(nodes: Array[Node]) -> void:
	set_target(nodes.back() as Node3D if not nodes.is_empty() else null)

func set_target(node: Node3D) -> void:
	_target = node
	_set_editable(node != null)
	if node == null:
		_name_field.text = ""
		for f in _all_spin_fields(): f.value = 0.0
		return
	_name_field.text = node.name
	_write_fields()

func _process(_delta: float) -> void:
	if _target == null or _updating or _any_spin_focused():
		return
	_updating = true
	_write_vec3(_pos_fields, _target.position)
	_write_vec3(_rot_fields, _target.rotation_degrees)
	_write_vec3(_scl_fields, _target.scale)
	_updating = false

func _on_name_submitted(text: String) -> void:
	if _target == null:
		return
	_target.name = text
	_name_field.text = _target.name
	EventBus.instance.object_changed.emit(_target)

func _on_name_focus_exited() -> void:
	_on_name_submitted(_name_field.text)

func _on_transform_changed() -> void:
	if _target == null or _updating:
		return
	_target.position         = _read_vec3(_pos_fields)
	_target.rotation_degrees = _read_vec3(_rot_fields)
	_target.scale            = _read_vec3(_scl_fields)

func _write_fields() -> void:
	_updating = true
	_write_vec3(_pos_fields, _target.position)
	_write_vec3(_rot_fields, _target.rotation_degrees)
	_write_vec3(_scl_fields, _target.scale)
	_updating = false

func _write_vec3(fields: Array[SpinBox], v: Vector3) -> void:
	fields[0].value = v.x
	fields[1].value = v.y
	fields[2].value = v.z

func _read_vec3(fields: Array[SpinBox]) -> Vector3:
	return Vector3(fields[0].value, fields[1].value, fields[2].value)

func _any_spin_focused() -> bool:
	for f in _all_spin_fields():
		if f.get_line_edit().has_focus():
			return true
	return false

func _all_spin_fields() -> Array[SpinBox]:
	var all: Array[SpinBox] = []
	all.append_array(_pos_fields)
	all.append_array(_rot_fields)
	all.append_array(_scl_fields)
	return all

func _set_editable(enabled: bool) -> void:
	_name_field.editable = enabled
	for f in _all_spin_fields():
		f.editable = enabled

func _add_text_row(label: String) -> LineEdit:
	var hbox := HBoxContainer.new()
	_vbox.add_child(hbox)
	var lbl := Label.new()
	lbl.text = label
	lbl.custom_minimum_size.x = 55
	hbox.add_child(lbl)
	var field := LineEdit.new()
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	hbox.add_child(field)
	return field

func _add_vec3_row(label: String) -> Array[SpinBox]:
	var lbl := Label.new()
	lbl.text = label
	_vbox.add_child(lbl)
	var hbox := HBoxContainer.new()
	_vbox.add_child(hbox)
	var result: Array[SpinBox] = []
	for axis in ["X", "Y", "Z"]:
		var spin := SpinBox.new()
		spin.min_value = -9999.0
		spin.max_value =  9999.0
		spin.step      =  0.001
		spin.prefix    = axis
		spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		hbox.add_child(spin)
		result.append(spin)
	return result
