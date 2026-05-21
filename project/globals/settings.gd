class_name Settings
extends RefCounted

static var instance := Settings.new()

const PATH := "user://settings.cfg"
var _cfg   := ConfigFile.new()

var viewport := ViewportSettings.new(self)
var uv       := UvSettings.new(self)
var bake     := BakeSettings.new(self)

func _init() -> void:
	_cfg.load(PATH)

func _save() -> void:
	_cfg.save(PATH)

# --- Categories ---

class ViewportSettings:
	var _s
	func _init(s) -> void: _s = s

	var vertex_dot_size: float:
		get: return _s._cfg.get_value("viewport", "vertex_dot_size", 0.007)
		set(v): _s._cfg.set_value("viewport", "vertex_dot_size", v); _s._save()

class UvSettings:
	var _s
	func _init(s) -> void: _s = s

	var edge_line_width: float:
		get: return _s._cfg.get_value("uv", "edge_line_width", 1.0)
		set(v): _s._cfg.set_value("uv", "edge_line_width", v); _s._save()

	var vert_dot_size: float:
		get: return _s._cfg.get_value("uv", "vert_dot_size", 5.0)
		set(v): _s._cfg.set_value("uv", "vert_dot_size", v); _s._save()

class BakeSettings:
	var _s
	func _init(s) -> void: _s = s

	var auto_bake: bool:
		get: return _s._cfg.get_value("bake", "auto_bake", false)
		set(v): _s._cfg.set_value("bake", "auto_bake", v); _s._save()

	var subdiv_level: int:
		get: return _s._cfg.get_value("bake", "subdiv_level", 2)
		set(v): _s._cfg.set_value("bake", "subdiv_level", v); _s._save()
