extends Node

@onready var world:             Node3D          = $World
@onready var view_panel:        Control    = $UI/vbox/HBox/HSplit/Viewport
@onready var scene_panel:       ScenePanel      = $UI/vbox/HBox/ScenePanel
@onready var properties_panel:  PropertiesPanel = $UI/vbox/HBox/PropertiesPanel

func _input(event: InputEvent) -> void:
	if event is InputEventKey and event.keycode == KEY_TAB:
		get_viewport().set_input_as_handled()

func _ready() -> void:
	world.camera = view_panel.camera
	view_panel.input_handler.world       = world
	view_panel.input_handler.camera_ctrl = view_panel.camera
	scene_panel.world = world
	scene_panel.selection_changed.connect(world.set_selection)
	world.setup()
