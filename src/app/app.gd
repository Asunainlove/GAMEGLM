extends Node

@onready var world_host: Node2D = %WorldHost
@onready var modal_layer: CanvasLayer = %ModalLayer
@onready var ui_layer: CanvasLayer = %UILayer


func _ready() -> void:
	assert(world_host != null)
	assert(modal_layer != null)
	assert(ui_layer != null)
