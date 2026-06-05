class_name GridView
extends Node2D

const Config := preload("res://scripts/config/bootstrap_config.gd")
const INVALID_CELL := Vector2i(-1, -1)

signal cell_clicked(cell: Vector2i)

var hovered_cell := INVALID_CELL
var selected_cell := INVALID_CELL
var factory_state = null

func set_factory_state(next_factory_state) -> void:
	factory_state = next_factory_state
	queue_redraw()

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
				cell_clicked.emit(cell)
				queue_redraw()

func _draw() -> void:
	var grid_size := Vector2(
		Config.GRID_COLUMNS * Config.CELL_SIZE,
		Config.GRID_ROWS * Config.CELL_SIZE
	)

	draw_rect(Rect2(Vector2.ZERO, grid_size), Config.COLOR_GRID_FILL_A)
	_draw_checker_cells()
	_draw_buildings()
	_draw_items()
	_draw_selection()
	_draw_grid_lines(grid_size)

func _draw_checker_cells() -> void:
	for y in range(Config.GRID_ROWS):
		for x in range(Config.GRID_COLUMNS):
			if (x + y) % 2 == 0:
				continue
			draw_rect(_cell_rect(Vector2i(x, y)), Config.COLOR_GRID_FILL_B)

func _draw_buildings() -> void:
	if factory_state == null:
		return

	for building in factory_state.get_buildings():
		var tool := String(building.get("type", ""))
		var cell: Vector2i = building.get("cell", INVALID_CELL)
		if not _is_valid_cell(cell):
			continue

		var rect := _cell_rect(cell).grow(-4.0)
		draw_rect(rect, Config.tool_color(tool))
		draw_rect(rect, Config.COLOR_BUILDING_BORDER, false, 2.0)
		_draw_building_symbol(rect, building)
		if Config.power_need(tool) > 0 and not bool(building.get("powered", true)):
			_draw_unpowered_warning(rect)

func _draw_building_symbol(rect: Rect2, building: Dictionary) -> void:
	var tool := String(building.get("type", ""))
	var center := rect.get_center()

	if Config.is_directional_tool(tool):
		var dir := Config.direction_vector(int(building.get("dir", 0)))
		var end := center + dir * 9.0
		draw_line(center - dir * 5.0, end, Config.COLOR_BUILDING_BORDER, 2.5)
		draw_circle(end, 3.0, Config.COLOR_BUILDING_BORDER)
		if tool == Config.TOOL_INSERTER and not Dictionary(building.get("held", {})).is_empty():
			var progress: float = clampf(float(building.get("progress", 0.0)), 0.0, 1.0)
			draw_circle(center + dir * lerpf(-6.0, 9.0, progress), 4.0, Config.COLOR_ITEM_ORE)
		return

	if tool == Config.TOOL_STORAGE:
		draw_rect(Rect2(center - Vector2(7.0, 7.0), Vector2(14.0, 14.0)), Config.COLOR_BUILDING_BORDER, false, 2.0)
	elif tool == Config.TOOL_GENERATOR:
		draw_circle(center, 7.0, Config.COLOR_BUILDING_BORDER)
	elif tool == Config.TOOL_ASSEMBLER:
		_draw_assembler_counters(center, building)

func _draw_items() -> void:
	if factory_state == null:
		return

	for item in factory_state.get_items():
		var cell: Vector2i = item.get("cell", INVALID_CELL)
		if not _is_valid_cell(cell):
			continue

		var rect := _cell_rect(cell)
		var dir := Config.direction_vector(int(item.get("dir", 0)))
		var progress: float = clampf(float(item.get("progress", 0.0)), 0.0, 1.0)
		var center := rect.get_center() + dir * float(Config.CELL_SIZE) * progress
		draw_circle(center, 5.0, _item_color(item))
		draw_circle(center, 7.0, Config.COLOR_ORE_GLOW)

func _draw_selection() -> void:
	if _is_valid_cell(selected_cell):
		draw_rect(_cell_rect(selected_cell), Config.COLOR_SELECTED)
		draw_rect(_cell_rect(selected_cell), Config.COLOR_SELECTED_BORDER, false, 2.0)

	if _is_valid_cell(hovered_cell) and hovered_cell != selected_cell:
		draw_rect(_cell_rect(hovered_cell), Config.COLOR_HOVER)

func _draw_unpowered_warning(rect: Rect2) -> void:
	draw_rect(rect, Config.COLOR_UNPOWERED_FILL)
	draw_rect(rect, Config.COLOR_UNPOWERED, false, 2.4)
	var top := rect.position + Vector2(rect.size.x * 0.62, rect.size.y * 0.20)
	var mid := rect.position + Vector2(rect.size.x * 0.38, rect.size.y * 0.53)
	var bottom := rect.position + Vector2(rect.size.x * 0.58, rect.size.y * 0.53)
	var tail := rect.position + Vector2(rect.size.x * 0.36, rect.size.y * 0.82)
	draw_polyline(PackedVector2Array([top, mid, bottom, tail]), Config.COLOR_UNPOWERED, 2.6)

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

func _draw_assembler_counters(center: Vector2, building: Dictionary) -> void:
	var input_count: int = min(4, int(building.get("input_ore", 0)))
	for index in range(input_count):
		draw_circle(center + Vector2(-9.0 + float(index) * 6.0, 7.0), 2.0, Config.COLOR_ITEM_ORE)

	var output_count: int = min(3, int(building.get("output_parts", 0)))
	for index in range(output_count):
		draw_circle(center + Vector2(-6.0 + float(index) * 6.0, -7.0), 2.4, Config.COLOR_ITEM_PART)

func _item_color(item: Dictionary) -> Color:
	if String(item.get("type", "")) == Config.ITEM_PART:
		return Config.COLOR_ITEM_PREMIUM if bool(item.get("premium", false)) else Config.COLOR_ITEM_PART
	return Config.COLOR_ITEM_ORE
