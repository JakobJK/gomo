extends Node

@onready var world:             Node3D          = $World
@onready var view_panel:        GomoViewport    = $UI/Viewport
@onready var scene_panel:       ScenePanel      = $UI/ScenePanel
@onready var properties_panel:  PropertiesPanel = $UI/PropertiesPanel

func _ready() -> void:
	var remote := world.get_node("perspective/RemoteTransform3D") as RemoteTransform3D
	remote.remote_path = remote.get_path_to(view_panel.camera)
	world.camera = view_panel.camera
	scene_panel.world = world
	scene_panel.selection_changed.connect(world.set_selection)
	world.setup()
