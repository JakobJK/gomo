extends Node

@onready var world:             Node3D          = $World
@onready var view_panel:        ViewPanel       = $UI/ViewPanel
@onready var scene_graph:       SceneGraph      = $UI/SceneGraph
@onready var properties_panel:  PropertiesPanel = $UI/PropertiesPanel

func _ready() -> void:
	var remote := world.get_node("perspective/RemoteTransform3D") as RemoteTransform3D
	remote.remote_path = remote.get_path_to(view_panel.camera)
	world.camera = view_panel.camera
	scene_graph.world = world
	scene_graph.selection_changed.connect(world.set_selection)
	world.setup()
