class_name MainScene
extends Node2D

const Config := preload("res://scripts/config/bootstrap_config.gd")

@onready var camera: Camera2D = $Camera2D
@onready var grid_view: Node2D = $GridView

func _ready() -> void:
	camera.position = Vector2(Config.VIEWPORT_SIZE) * 0.5
	camera.make_current()
	grid_view.position = Config.GRID_ORIGIN

	if OS.is_debug_build():
		print("FACTORYOPS_MAIN_SCENE_READY")

func _draw() -> void:
	var viewport_size := Vector2(Config.VIEWPORT_SIZE)
	var grid_size := Vector2(
		Config.GRID_COLUMNS * Config.CELL_SIZE,
		Config.GRID_ROWS * Config.CELL_SIZE
	)
	var board_padding := 16.0
	var board_rect := Rect2(
		Config.GRID_ORIGIN - Vector2.ONE * board_padding,
		grid_size + Vector2.ONE * board_padding * 2.0
	)

	draw_rect(Rect2(Vector2.ZERO, viewport_size), Config.COLOR_BACKGROUND)
	draw_rect(board_rect, Config.COLOR_BACKGROUND_PANEL)
