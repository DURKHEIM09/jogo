class_name SmokeRoot
extends Node2D

func _ready() -> void:
	print("FACTORYOPS_GODOT_MCP_SMOKE_OK")
	await get_tree().create_timer(1.0).timeout
	get_tree().quit()
