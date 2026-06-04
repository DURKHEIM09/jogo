class_name FactoryState
extends RefCounted

signal changed

const Config := preload("res://scripts/config/bootstrap_config.gd")

var money := Config.INITIAL_MONEY
var selected_tool := Config.TOOL_BELT
var selected_dir := 0

var buildings := {}
var resources := {}

func _init() -> void:
	_generate_resources()

func select_tool(tool: String) -> bool:
	if not Config.is_known_tool(tool):
		return false
	selected_tool = tool
	emit_signal("changed")
	return true

func rotate_selection() -> void:
	selected_dir = (selected_dir + 1) % Config.DIRECTION_COUNT
	emit_signal("changed")

func try_apply_tool(cell: Vector2i) -> Dictionary:
	if not _is_cell_in_bounds(cell):
		return _result(false, "blocked", "Fora da grade.", cell, 0)
	if selected_tool == Config.TOOL_ERASE:
		return _try_remove(cell)
	return _try_place(cell)

func get_buildings() -> Array:
	return buildings.values()

func get_resources() -> Array:
	return resources.values()

func has_resource(cell: Vector2i) -> bool:
	return resources.has(cell) and int(resources[cell].get("amount", 0)) > 0

func get_building(cell: Vector2i) -> Dictionary:
	if not buildings.has(cell):
		return {}
	return buildings[cell]

func _try_place(cell: Vector2i) -> Dictionary:
	if buildings.has(cell):
		var existing: Dictionary = buildings[cell]
		if existing.get("type", "") == selected_tool and Config.is_directional_tool(selected_tool):
			existing["dir"] = selected_dir
			buildings[cell] = existing
			emit_signal("changed")
			return _result(true, "rotated", "Direcao atualizada.", cell, 0)
		return _result(false, "blocked", "Celula ocupada.", cell, 0)

	var cost := Config.tool_cost(selected_tool)
	if money < cost:
		return _result(false, "blocked", "Creditos insuficientes.", cell, 0)
	if selected_tool == Config.TOOL_MINER and not has_resource(cell):
		return _result(false, "blocked", "Minerador precisa de minerio.", cell, 0)

	var building := {
		"type": selected_tool,
		"cell": cell,
		"dir": selected_dir if Config.is_directional_tool(selected_tool) else 0,
		"timer": 0.0,
		"input_ore": 0,
		"output_parts": 0,
		"powered": true,
	}

	money -= cost
	buildings[cell] = building
	emit_signal("changed")
	return _result(true, "placed", "Construido.", cell, -cost)

func _try_remove(cell: Vector2i) -> Dictionary:
	if not buildings.has(cell):
		return _result(false, "blocked", "Nada para remover.", cell, 0)

	var building: Dictionary = buildings[cell]
	var refund := Config.tool_refund(String(building.get("type", "")))
	buildings.erase(cell)
	money += refund
	emit_signal("changed")
	return _result(true, "removed", "Removido.", cell, refund)

func _generate_resources() -> void:
	resources.clear()

	for spec in Config.ore_patch_specs():
		var center_ratio: Vector2 = spec["center"]
		var radius: Vector2i = spec["radius"]
		var center := Vector2i(
			int(floor(float(Config.GRID_COLUMNS) * center_ratio.x)),
			int(floor(float(Config.GRID_ROWS) * center_ratio.y))
		)
		_add_ore_patch(center, radius)

func _add_ore_patch(center: Vector2i, radius: Vector2i) -> void:
	var min_x: int = max(0, center.x - radius.x)
	var max_x: int = min(Config.GRID_COLUMNS - 1, center.x + radius.x)
	var min_y: int = max(0, center.y - radius.y)
	var max_y: int = min(Config.GRID_ROWS - 1, center.y + radius.y)

	for y in range(min_y, max_y + 1):
		for x in range(min_x, max_x + 1):
			var cell := Vector2i(x, y)
			var dx := float(x - center.x) / float(max(1, radius.x))
			var dy := float(y - center.y) / float(max(1, radius.y))
			var shape := dx * dx + dy * dy
			var noisy := shape + _cell_noise(cell, 17) * 0.42

			if noisy >= 1.05:
				continue

			resources[cell] = {
				"cell": cell,
				"amount": Config.ORE_BASE_AMOUNT + int(floor(_cell_noise(cell, 43) * float(Config.ORE_AMOUNT_VARIANCE))),
				"phase": _cell_noise(cell, 71) * TAU,
			}

func _cell_noise(cell: Vector2i, salt: int) -> float:
	var raw := cell.x * 928371 + cell.y * 689287 + salt * 283923
	return float(posmod(raw, 1000)) / 1000.0

func _is_cell_in_bounds(cell: Vector2i) -> bool:
	return (
		cell.x >= 0
		and cell.y >= 0
		and cell.x < Config.GRID_COLUMNS
		and cell.y < Config.GRID_ROWS
	)

func _result(ok: bool, action: String, message: String, cell: Vector2i, money_delta: int) -> Dictionary:
	return {
		"ok": ok,
		"action": action,
		"message": message,
		"cell": cell,
		"money": money,
		"money_delta": money_delta,
		"selected_tool": selected_tool,
	}
