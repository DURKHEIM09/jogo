class_name FactoryState
extends RefCounted

signal changed

const Config := preload("res://scripts/config/bootstrap_config.gd")

var money := Config.INITIAL_MONEY
var selected_tool := Config.TOOL_BELT
var selected_dir := 0

var buildings := {}
var resources := {}
var items := []
var rng := RandomNumberGenerator.new()

func _init() -> void:
	rng.randomize()
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

func tick(delta: float) -> void:
	var dt: float = minf(delta, Config.SIMULATION_DT_CLAMP)
	var changed_this_tick := false

	for key in buildings.keys():
		var cell: Vector2i = key
		var building: Dictionary = buildings[cell]
		var building_type := String(building.get("type", ""))

		if building_type == Config.TOOL_MINER:
			changed_this_tick = _update_miner(cell, building, dt) or changed_this_tick
		elif building_type == Config.TOOL_INSERTER:
			changed_this_tick = _update_inserter(cell, building, dt) or changed_this_tick
		elif building_type == Config.TOOL_ASSEMBLER:
			changed_this_tick = _update_assembler(cell, building, dt) or changed_this_tick

	changed_this_tick = _update_items(dt) or changed_this_tick

	if changed_this_tick:
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

func get_items() -> Array:
	return items

func has_resource(cell: Vector2i) -> bool:
	return resources.has(cell) and int(resources[cell].get("amount", 0)) > 0

func get_resource_amount(cell: Vector2i) -> int:
	if not resources.has(cell):
		return 0
	return int(resources[cell].get("amount", 0))

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
		"output_queue": [],
		"held": {},
		"progress": 0.0,
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

func _update_miner(cell: Vector2i, building: Dictionary, dt: float) -> bool:
	if not bool(building.get("powered", true)):
		return false
	if not has_resource(cell):
		return false
	if items.size() >= Config.ITEM_CAP:
		return false

	building["timer"] = float(building.get("timer", 0.0)) + dt
	if float(building["timer"]) < Config.MINER_INTERVAL:
		buildings[cell] = building
		return false
	if not _output_can_accept(cell, int(building.get("dir", 0)), "ore"):
		buildings[cell] = building
		return false

	building["timer"] = float(building["timer"]) - Config.MINER_INTERVAL
	buildings[cell] = building
	_consume_resource(cell)
	_spawn_item(cell, int(building.get("dir", 0)), "ore")
	return true

func _output_can_accept(cell: Vector2i, dir: int, item_type: String) -> bool:
	if item_type != "ore":
		return false

	var target_cell := cell + Config.direction_offset(dir)
	if not _is_cell_in_bounds(target_cell):
		return false

	var target := get_building(target_cell)
	return String(target.get("type", "")) == Config.TOOL_BELT

func _consume_resource(cell: Vector2i) -> void:
	if not resources.has(cell):
		return

	var resource: Dictionary = resources[cell]
	resource["amount"] = max(0, int(resource.get("amount", 0)) - 1)
	if int(resource["amount"]) <= 0:
		resources.erase(cell)
		return

	resources[cell] = resource

func _spawn_item(cell: Vector2i, dir: int, item_type: String) -> void:
	var item: Dictionary = {
		"type": item_type,
		"cell": cell,
		"dir": dir,
		"progress": 0.0,
		"age": 0.0,
	}
	items.append(item)

func _update_inserter(cell: Vector2i, building: Dictionary, dt: float) -> bool:
	if not bool(building.get("powered", true)):
		return false

	var held: Dictionary = building.get("held", {})
	if held.is_empty():
		var picked := _pick_for_inserter(cell, int(building.get("dir", 0)))
		if picked.is_empty():
			return false

		building["held"] = picked
		building["progress"] = 0.0
		buildings[cell] = building
		return true

	building["progress"] = float(building.get("progress", 0.0)) + dt * Config.INSERTER_SPEED
	if float(building["progress"]) < 1.0:
		buildings[cell] = building
		return true

	if _drop_from_inserter(cell, int(building.get("dir", 0)), held):
		building["held"] = {}
		building["progress"] = 0.0
	else:
		building["progress"] = 0.86

	buildings[cell] = building
	return true

func _pick_for_inserter(cell: Vector2i, dir: int) -> Dictionary:
	var pickup_cell := cell - Config.direction_offset(dir)
	if not _is_cell_in_bounds(pickup_cell):
		return {}

	var source := get_building(pickup_cell)
	if String(source.get("type", "")) == Config.TOOL_ASSEMBLER and int(source.get("output_parts", 0)) > 0:
		var output_queue: Array = source.get("output_queue", [])
		while output_queue.size() < int(source.get("output_parts", 0)):
			output_queue.append(_make_item("part"))

		var picked_from_assembler: Dictionary = output_queue.pop_front() if not output_queue.is_empty() else _make_item("part")
		source["output_queue"] = output_queue
		source["output_parts"] = output_queue.size()
		buildings[pickup_cell] = source
		return picked_from_assembler

	var item_index := _find_item_index_at_cell(pickup_cell)
	if item_index < 0:
		return {}

	var picked: Dictionary = items[item_index]
	items.remove_at(item_index)
	return _normalize_item(picked)

func _drop_from_inserter(cell: Vector2i, dir: int, held_item: Dictionary) -> bool:
	var drop_cell := cell + Config.direction_offset(dir)
	if not _is_cell_in_bounds(drop_cell):
		return false

	var target := get_building(drop_cell)
	var target_type := String(target.get("type", ""))
	if target_type == "":
		return false

	var held := _normalize_item(held_item)
	var item_type := String(held.get("type", "ore"))

	if target_type == Config.TOOL_BELT:
		if _item_count_at_cell(drop_cell) >= Config.BELT_CELL_ITEM_CAP:
			return false
		held["cell"] = drop_cell
		held["dir"] = int(target.get("dir", 0))
		held["progress"] = 0.12
		held["age"] = 0.0
		items.append(held)
		return true

	if target_type == Config.TOOL_ASSEMBLER and item_type == "ore" and int(target.get("input_ore", 0)) < Config.ASSEMBLER_INPUT_CAP:
		target["input_ore"] = int(target.get("input_ore", 0)) + 1
		buildings[drop_cell] = target
		return true

	return false

func _update_assembler(cell: Vector2i, building: Dictionary, dt: float) -> bool:
	if not bool(building.get("powered", true)):
		return false

	var output_queue: Array = building.get("output_queue", [])
	building["output_parts"] = output_queue.size()

	if int(building.get("input_ore", 0)) < 2:
		var previous_timer := float(building.get("timer", 0.0))
		building["timer"] = maxf(0.0, previous_timer - dt * 0.5)
		buildings[cell] = building
		return float(building["timer"]) != previous_timer

	building["timer"] = float(building.get("timer", 0.0)) + dt
	if float(building["timer"]) < Config.ASSEMBLER_BUILD_TIME:
		buildings[cell] = building
		return false

	if output_queue.size() >= Config.ASSEMBLER_OUTPUT_CAP:
		buildings[cell] = building
		return false

	building["timer"] = float(building["timer"]) - Config.ASSEMBLER_BUILD_TIME
	building["input_ore"] = int(building.get("input_ore", 0)) - 2
	output_queue.append(_make_item("part", _roll_part_quality(cell, building)))
	building["output_queue"] = output_queue
	building["output_parts"] = output_queue.size()
	buildings[cell] = building
	return true

func _find_item_index_at_cell(cell: Vector2i) -> int:
	for index in range(items.size()):
		var item: Dictionary = items[index]
		var item_cell: Vector2i = item.get("cell", Vector2i(-1, -1))
		if item_cell == cell:
			return index
	return -1

func _item_count_at_cell(cell: Vector2i) -> int:
	var count := 0
	for item in items:
		var item_cell: Vector2i = item.get("cell", Vector2i(-1, -1))
		if item_cell == cell:
			count += 1
	return count

func _normalize_item(item: Dictionary) -> Dictionary:
	return {
		"type": String(item.get("type", "ore")),
		"tier": int(item.get("tier", 1)),
		"quality": float(item.get("quality", 1.0)),
		"premium": bool(item.get("premium", false)),
		"cell": item.get("cell", Vector2i(-1, -1)),
		"dir": int(item.get("dir", 0)),
		"progress": float(item.get("progress", 0.0)),
		"age": float(item.get("age", 0.0)),
	}

func _make_item(item_type: String, quality := 1.0) -> Dictionary:
	return {
		"type": item_type,
		"tier": 1,
		"quality": quality,
		"premium": item_type == "part" and quality >= Config.PREMIUM_THRESHOLD,
		"cell": Vector2i(-1, -1),
		"dir": 0,
		"progress": 0.0,
		"age": 0.0,
	}

func _roll_part_quality(cell: Vector2i, building: Dictionary) -> float:
	var setup_quality := _get_setup_quality(cell, building)
	var average := Config.BASE_QUALITY_MU * setup_quality
	var spread := Config.BASE_QUALITY_SIGMA / setup_quality
	return clampf(rng.randfn(average, spread), Config.MIN_QUALITY, Config.MAX_QUALITY)

func _get_setup_quality(cell: Vector2i, building: Dictionary) -> float:
	var power_bonus := 0.04 if bool(building.get("powered", true)) else 0.0
	var storage_bonus := 0.04 if _nearby_building_count(cell, Config.TOOL_STORAGE, 3) > 0 else 0.0
	var inserter_bonus := 0.08 if _nearby_building_count(cell, Config.TOOL_INSERTER, 2) >= 2 else 0.0
	return clampf(1.0 + power_bonus + storage_bonus + inserter_bonus, 0.8, 1.45)

func _nearby_building_count(cell: Vector2i, building_type: String, radius: int) -> int:
	var count := 0
	for key in buildings.keys():
		var candidate_cell: Vector2i = key
		var candidate: Dictionary = buildings[candidate_cell]
		if String(candidate.get("type", "")) != building_type:
			continue

		var distance := absi(candidate_cell.x - cell.x) + absi(candidate_cell.y - cell.y)
		if distance <= radius:
			count += 1

	return count

func _update_items(dt: float) -> bool:
	var changed_this_tick := false

	for index in range(items.size() - 1, -1, -1):
		var item: Dictionary = items[index]
		item["progress"] = float(item.get("progress", 0.0)) + dt * Config.ITEM_SPEED
		item["age"] = float(item.get("age", 0.0)) + dt

		if float(item["age"]) > Config.ITEM_MAX_AGE:
			items.remove_at(index)
			changed_this_tick = true
			continue

		var alive := true
		while float(item["progress"]) >= 1.0 and alive:
			item["progress"] = float(item["progress"]) - 1.0
			alive = _advance_item(item)
			changed_this_tick = true

		if alive:
			items[index] = item
		else:
			items.remove_at(index)

	return changed_this_tick

func _advance_item(item: Dictionary) -> bool:
	var cell: Vector2i = item.get("cell", Vector2i(-1, -1))
	var dir := int(item.get("dir", 0))
	var next_cell := cell + Config.direction_offset(dir)

	if not _is_cell_in_bounds(next_cell):
		return false

	var target := get_building(next_cell)
	if target.is_empty():
		item["progress"] = 0.98
		return true

	var target_type := String(target.get("type", ""))
	if target_type == Config.TOOL_BELT:
		item["cell"] = next_cell
		item["dir"] = int(target.get("dir", 0))
		return true

	if (
		target_type == Config.TOOL_ASSEMBLER
		or target_type == Config.TOOL_INSERTER
		or target_type == Config.TOOL_GENERATOR
		or target_type == Config.TOOL_STORAGE
	):
		item["progress"] = 0.98
		return true

	return false

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
