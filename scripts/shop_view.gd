class_name ShopView
extends Node2D

const Config := preload("res://scripts/config/bootstrap_config.gd")

var factory_state = null

func set_factory_state(next_factory_state) -> void:
	factory_state = next_factory_state
	queue_redraw()

func _draw() -> void:
	var view_size := Config.SHOP_SIZE
	draw_rect(Rect2(Vector2.ZERO, view_size), Config.COLOR_SHOP_FLOOR)
	_draw_floor_grid(view_size)
	_draw_wall(view_size)
	_draw_shelves(view_size)
	_draw_checkout(view_size)
	_draw_door(view_size)
	_draw_stock(view_size)

func _draw_floor_grid(view_size: Vector2) -> void:
	for x in range(0, int(view_size.x), Config.CELL_SIZE):
		draw_line(Vector2(float(x), view_size.y * 0.16), Vector2(float(x), view_size.y), Config.COLOR_GRID_LINE, 1.0)
	for y in range(int(view_size.y * 0.20), int(view_size.y), Config.CELL_SIZE):
		draw_line(Vector2.ZERO + Vector2(0.0, float(y)), Vector2(view_size.x, float(y)), Config.COLOR_GRID_LINE, 1.0)

func _draw_wall(view_size: Vector2) -> void:
	draw_rect(Rect2(Vector2.ZERO, Vector2(view_size.x, view_size.y * 0.16)), Config.COLOR_SHOP_WALL)
	draw_rect(Rect2(Vector2(0.0, view_size.y * 0.16), Vector2(view_size.x, 2.0)), Config.COLOR_BUILDING_BORDER)

func _draw_shelves(view_size: Vector2) -> void:
	_draw_shelf(Vector2(view_size.x * 0.15, view_size.y * 0.28), Vector2(view_size.x * 0.36, view_size.y * 0.10))
	_draw_shelf(Vector2(view_size.x * 0.15, view_size.y * 0.48), Vector2(view_size.x * 0.36, view_size.y * 0.10))
	_draw_shelf(Vector2(view_size.x * 0.15, view_size.y * 0.68), Vector2(view_size.x * 0.36, view_size.y * 0.10))

func _draw_shelf(position: Vector2, size: Vector2) -> void:
	var rect := Rect2(position, size)
	draw_rect(rect, Config.COLOR_SHOP_SHELF)
	draw_rect(rect, Config.COLOR_BUILDING_BORDER, false, 2.0)
	draw_line(position + Vector2(0.0, size.y * 0.5), position + Vector2(size.x, size.y * 0.5), Config.COLOR_BUILDING_BORDER, 1.0)

func _draw_checkout(view_size: Vector2) -> void:
	var rect := Rect2(Vector2(view_size.x * 0.62, view_size.y * 0.58), Vector2(view_size.x * 0.24, view_size.y * 0.14))
	draw_rect(rect, Config.COLOR_SHOP_COUNTER)
	draw_rect(rect, Config.COLOR_BUILDING_BORDER, false, 2.0)
	draw_rect(Rect2(rect.position + Vector2(rect.size.x * 0.62, 8.0), Vector2(rect.size.x * 0.24, rect.size.y - 16.0)), Config.COLOR_BACKGROUND_PANEL)

func _draw_door(view_size: Vector2) -> void:
	var rect := Rect2(Vector2(view_size.x * 0.08, view_size.y - 38.0), Vector2(72.0, 28.0))
	draw_rect(rect, Config.COLOR_BACKGROUND_PANEL)
	draw_rect(rect, Config.COLOR_SELECTED_BORDER, false, 2.0)

func _draw_stock(view_size: Vector2) -> void:
	if factory_state == null:
		return

	var stock: Array = factory_state.get_shop_inventory()
	var max_visible: int = min(18, stock.size())
	for index in range(max_visible):
		var item: Dictionary = stock[index]
		var row: int = int(floor(float(index) / 6.0))
		var column: int = index % 6
		var position := Vector2(
			view_size.x * 0.18 + float(column) * 32.0,
			view_size.y * 0.30 + float(row) * 54.0
		)
		var color := Config.COLOR_ITEM_PREMIUM if bool(item.get("premium", false)) else Config.COLOR_ITEM_PART
		draw_circle(position, 7.0, color)
		draw_circle(position, 10.0, Color(color.r, color.g, color.b, 0.22))
