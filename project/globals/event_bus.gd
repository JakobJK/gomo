class_name EventBus
extends RefCounted

static var instance := EventBus.new()

signal selection_changed(nodes: Array[Node])
signal object_changed(obj: Node3D)
