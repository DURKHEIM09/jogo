class_name GridView
extends Node2D

const Config := preload("res://scripts/config/bootstrap_config.gd")
const INVALID_CELL := Vector2i(-1, -1)

var hovered_cell := INVALID_CELL
var selected_cell := INVALID_CELL

func _ready() -> void:
	set_process_input(true)
	queue_redraw()

	if OS.is_debug_build():
		print("FACTORYOPS_GRID_READY:%dx%d" % [Config.GRID_COLUMNS, Config.GRID_ROWS])

func _input(event: InputEvent) -> void:
	if event is InputEventMouseMotion:
		_set_hovered_cell(_cell_from_global_mouse())
	elif event is InputEventMouseButton:
		var mouse_event := event as InputEventMouseButton
		if mouse_event.button_index == MOUSE_BUTTON_LEFT and mouse_event.pressed:
			var cell := _cell_from_global_mouse()
			if _is_valid_cell(cell):
				selected_cell = cell
				hovered_cell = cell
				print("FACTORYOPS_GRID_CELL_SELECTED:%d,%d" % [cell.x, cell.y])
				queue_redraw()

func _draw() -> void:
	var grid_size := Vector2(
		Config.GRID_COLUMNS * Config.CELL_SIZE,
		Config.GRID_ROWS * Config.CELL_SIZE
	)

	draw_rect(Rect2(Vector2.ZERO, grid_size), Config.COLOR_GRID_FILL_A)
	_draw_checker_cells()
	_draw_selection()
	_draw_grid_lines(grid_size)

func _draw_checker_cells() -> void:
	for y in range(Config.GRID_ROWS):
		for x in range(Config.GRID_COLUMNS):
			if (x + y) % 2 == 0:
				continue
			draw_rect(_cell_rect(Vector2i(x, y)), Config.COLOR_GRID_FILL_B)

func _draw_selection() -> void:
	if _is_valid_cell(selected_cell):
		draw_rect(_cell_rect(selected_cell), Config.COLOR_SELECTED)
		draw_rect(_cell_rect(selected_cell), Config.COLOR_SELECTED_BORDER, false, 2.0)

	if _is_valid_cell(hovered_cell) and hovered_cell != selected_cell:
		draw_rect(_cell_rect(hovered_cell), Config.COLOR_HOVER)

func _draw_grid_lines(grid_size: Vector2) -> void:
	for x in range(Config.GRID_COLUMNS + 1):
		var line_x := float(x * Config.CELL_SIZE)
		draw_line(Vector2(line_x, 0.0), Vector2(line_x, grid_size.y), Config.COLOR_GRID_LINE, 1.0)

	for y in range(Config.GRID_ROWS + 1):
		var line_y := float(y * Config.CELL_SIZE)
		draw_line(Vector2(0.0, line_y), Vector2(grid_size.x, line_y), Config.COLOR_GRID_LINE, 1.0)

func _set_hovered_cell(cell: Vector2i) -> void:
	if hovered_cell == cell:
		return
	hovered_cell = cell
	queue_redraw()

func _cell_from_global_mouse() -> Vector2i:
	return _cell_from_local_position(to_local(get_global_mouse_position()))

func _cell_from_local_position(local_mouse_position: Vector2) -> Vector2i:
	if local_mouse_position.x < 0.0 or local_mouse_position.y < 0.0:
		return INVALID_CELL

	var grid_width := float(Config.GRID_COLUMNS * Config.CELL_SIZE)
	var grid_height := float(Config.GRID_ROWS * Config.CELL_SIZE)
	if local_mouse_position.x >= grid_width or local_mouse_position.y >= grid_height:
		return INVALID_CELL

	return Vector2i(
		int(floor(local_mouse_position.x / float(Config.CELL_SIZE))),
		int(floor(local_mouse_position.y / float(Config.CELL_SIZE)))
	)

func _cell_rect(cell: Vector2i) -> Rect2:
	return Rect2(
		Vector2(cell.x * Config.CELL_SIZE, cell.y * Config.CELL_SIZE),
		Vector2(Config.CELL_SIZE, Config.CELL_SIZE)
	)

func _is_valid_cell(cell: Vector2i) -> bool:
	return (
		cell.x >= 0
		and cell.y >= 0
		and cell.x < Config.GRID_COLUMNS
		and cell.y < Config.GRID_ROWS
	)
