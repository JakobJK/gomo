extends Control

@onready var viewport:       SubViewport   = $VBoxContainer/SubViewport/SubViewport
@onready var camera:         Camera3D      = $VBoxContainer/SubViewport/SubViewport/perspective
@onready var input_handler:  ViewportInput = $VBoxContainer/SubViewport
