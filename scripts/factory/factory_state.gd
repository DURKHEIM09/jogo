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
var simulation_time := 0.0
var parts := 0
var ore_stored := 0
var produced_times := []
var power_used := 0
var power_capacity := 0

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
	simulation_time += dt
	var changed_this_tick := recalculate_power()

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
		_update_rate_window()
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

func get_parts_per_minute() -> int:
	_update_rate_window()
	return produced_times.size()

func get_building(cell: Vector2i) -> Dictionary:
	if not buildings.has(cell):
		return {}
	return buildings[cell]

func recalculate_power() -> bool:
	var generators: Array[Dictionary] = []
	for building in buildings.values():
		var building_type := String(building.get("type", ""))
		if building_type == Config.TOOL_GENERATOR:
			generators.append(building)

	var previous_used := power_used
	var previous_capacity := power_capacity
	var next_capacity := generators.size() * Config.POWER_GENERATOR_OUTPUT
	var remaining := next_capacity
	var next_used := 0
	var changed_power_state := false

	for key in buildings.keys():
		var cell: Vector2i = key
		var building: Dictionary = buildings[cell]
		var building_type := String(building.get("type", ""))
		var previous_powered := bool(building.get("powered", true))
		var need := Config.power_need(building_type)
		var next_powered := true

		if need > 0:
			next_powered = _is_covered_by_generator(cell, generators) and remaining >= need
			if next_powered:
				remaining -= need
				next_used += need

		building["powered"] = next_powered
		buildings[cell] = building
		if previous_powered != next_powered:
			changed_power_state = true

	power_capacity = next_capacity
	power_used = next_used
	changed_power_state = changed_power_state or previous_used != power_used or previous_capacity != power_capacity
	return changed_power_state

func save_to_disk(path := Config.SAVE_PATH) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		push_error("FACTORYOPS_SAVE_FAILED:%s" % path)
		return false

	file.store_string(JSON.stringify(to_snapshot()))
	return true

func load_from_disk(path := Config.SAVE_PATH) -> bool:
	if not FileAccess.file_exists(path):
		return false

	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("FACTORYOPS_LOAD_FAILED:%s" % path)
		return false

	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("FACTORYOPS_LOAD_INVALID_JSON:%s" % path)
		return false

	return load_snapshot(parsed)

func to_snapshot() -> Dictionary:
	return {
		"version": Config.SAVE_VERSION,
		"money": money,
		"selected_tool": selected_tool,
		"selected_dir": selected_dir,
		"simulation_time": simulation_time,
		"parts": parts,
		"ore_stored": ore_stored,
		"produced_times": produced_times.duplicate(true),
		"buildings": _serialize_buildings(),
		"resources": _serialize_resources(),
		"items": _serialize_items(items),
	}

func load_snapshot(snapshot: Dictionary) -> bool:
	money = int(snapshot.get("money", Config.INITIAL_MONEY))
	selected_tool = String(snapshot.get("selected_tool", Config.TOOL_BELT))
	if not Config.is_known_tool(selected_tool):
		selected_tool = Config.TOOL_BELT
	selected_dir = posmod(int(snapshot.get("selected_dir", 0)), Config.DIRECTION_COUNT)
	simulation_time = maxf(0.0, float(snapshot.get("simulation_time", 0.0)))
	parts = max(0, int(snapshot.get("parts", 0)))
	ore_stored = max(0, int(snapshot.get("ore_stored", 0)))
	produced_times = _deserialize_float_array(snapshot.get("produced_times", []))

	buildings.clear()
	for raw_building in _as_array(snapshot.get("buildings", [])):
		var building := _deserialize_building(raw_building)
		if building.is_empty():
			continue
		var cell: Vector2i = building["cell"]
		if _is_cell_in_bounds(cell):
			buildings[cell] = building

	resources.clear()
	for raw_resource in _as_array(snapshot.get("resources", [])):
		var resource := _deserialize_resource(raw_resource)
		if resource.is_empty():
			continue
		var cell: Vector2i = resource["cell"]
		if _is_cell_in_bounds(cell) and int(resource.get("amount", 0)) > 0:
			resources[cell] = resource

	items = _deserialize_items(snapshot.get("items", []))
	recalculate_power()
	_update_rate_window()
	emit_signal("changed")
	return true

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
	recalculate_power()
	emit_signal("changed")
	return _result(true, "placed", "Construido.", cell, -cost)

func _try_remove(cell: Vector2i) -> Dictionary:
	if not buildings.has(cell):
		return _result(false, "blocked", "Nada para remover.", cell, 0)

	var building: Dictionary = buildings[cell]
	var refund := Config.tool_refund(String(building.get("type", "")))
	buildings.erase(cell)
	money += refund
	recalculate_power()
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
	if not _output_can_accept(cell, int(building.get("dir", 0)), Config.ITEM_ORE):
		buildings[cell] = building
		return false

	building["timer"] = float(building["timer"]) - Config.MINER_INTERVAL
	buildings[cell] = building
	_consume_resource(cell)
	_spawn_item(cell, int(building.get("dir", 0)), Config.ITEM_ORE)
	return true

func _output_can_accept(cell: Vector2i, dir: int, item_type: String) -> bool:
	if item_type != Config.ITEM_ORE:
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
			output_queue.append(_make_item(Config.ITEM_PART))

		var picked_from_assembler: Dictionary = output_queue.pop_front() if not output_queue.is_empty() else _make_item(Config.ITEM_PART)
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
	var item_type := String(held.get("type", Config.ITEM_ORE))

	if target_type == Config.TOOL_BELT:
		if _item_count_at_cell(drop_cell) >= Config.BELT_CELL_ITEM_CAP:
			return false
		held["cell"] = drop_cell
		held["dir"] = int(target.get("dir", 0))
		held["progress"] = Config.BELT_INSERT_PROGRESS
		held["age"] = 0.0
		items.append(held)
		return true

	if target_type == Config.TOOL_ASSEMBLER and item_type == Config.ITEM_ORE and int(target.get("input_ore", 0)) < Config.ASSEMBLER_INPUT_CAP:
		target["input_ore"] = int(target.get("input_ore", 0)) + 1
		buildings[drop_cell] = target
		return true

	if target_type == Config.TOOL_STORAGE:
		if item_type == Config.ITEM_PART:
			_store_part(held)
		elif item_type == Config.ITEM_ORE:
			ore_stored += 1
		return true

	return false

func _update_assembler(cell: Vector2i, building: Dictionary, dt: float) -> bool:
	if not bool(building.get("powered", true)):
		return false

	var output_queue: Array = building.get("output_queue", [])
	building["output_parts"] = output_queue.size()

	if int(building.get("input_ore", 0)) < Config.ASSEMBLER_INPUT_PER_PART:
		var previous_timer := float(building.get("timer", 0.0))
		building["timer"] = maxf(0.0, previous_timer - dt * Config.ASSEMBLER_TIMER_DECAY)
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
	building["input_ore"] = int(building.get("input_ore", 0)) - Config.ASSEMBLER_INPUT_PER_PART
	output_queue.append(_make_item(Config.ITEM_PART, _roll_part_quality(cell, building)))
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
		"type": String(item.get("type", Config.ITEM_ORE)),
		"tier": int(item.get("tier", Config.DEFAULT_ITEM_TIER)),
		"quality": float(item.get("quality", Config.DEFAULT_ITEM_QUALITY)),
		"premium": bool(item.get("premium", false)),
		"cell": item.get("cell", Vector2i(-1, -1)),
		"dir": int(item.get("dir", 0)),
		"progress": float(item.get("progress", 0.0)),
		"age": float(item.get("age", 0.0)),
	}

func _make_item(item_type: String, quality := Config.DEFAULT_ITEM_QUALITY) -> Dictionary:
	return {
		"type": item_type,
		"tier": Config.DEFAULT_ITEM_TIER,
		"quality": quality,
		"premium": item_type == Config.ITEM_PART and quality >= Config.PREMIUM_THRESHOLD,
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

func _is_covered_by_generator(cell: Vector2i, generators: Array[Dictionary]) -> bool:
	for generator in generators:
		var generator_cell: Vector2i = generator.get("cell", Vector2i(-1, -1))
		var distance := absi(generator_cell.x - cell.x) + absi(generator_cell.y - cell.y)
		if distance <= Config.POWER_GENERATOR_RADIUS:
			return true

	return false

func _store_part(_part: Dictionary) -> void:
	parts += 1
	produced_times.append(simulation_time)

func _update_rate_window() -> void:
	var cutoff := simulation_time - Config.RATE_WINDOW_SECONDS
	produced_times = produced_times.filter(func(stamp): return float(stamp) >= cutoff)

func _serialize_buildings() -> Array:
	var result: Array = []
	for building in buildings.values():
		result.append(_serialize_building(building))
	return result

func _serialize_building(building: Dictionary) -> Dictionary:
	return {
		"type": String(building.get("type", "")),
		"cell": _serialize_cell(building.get("cell", Vector2i(-1, -1))),
		"dir": int(building.get("dir", 0)),
		"timer": float(building.get("timer", 0.0)),
		"input_ore": int(building.get("input_ore", 0)),
		"output_parts": int(building.get("output_parts", 0)),
		"output_queue": _serialize_items(building.get("output_queue", [])),
		"held": _serialize_optional_item(building.get("held", {})),
		"progress": float(building.get("progress", 0.0)),
	}

func _deserialize_building(raw_building: Variant) -> Dictionary:
	if typeof(raw_building) != TYPE_DICTIONARY:
		return {}

	var source: Dictionary = raw_building
	var cell := _deserialize_cell(source.get("cell", {}))
	var tool := String(source.get("type", ""))
	if not Config.is_known_tool(tool) or tool == Config.TOOL_ERASE:
		return {}

	var output_queue := _deserialize_items(source.get("output_queue", []))
	var held := _deserialize_optional_item(source.get("held", {}))
	return {
		"type": tool,
		"cell": cell,
		"dir": posmod(int(source.get("dir", 0)), Config.DIRECTION_COUNT),
		"timer": maxf(0.0, float(source.get("timer", 0.0))),
		"input_ore": max(0, int(source.get("input_ore", 0))),
		"output_parts": output_queue.size(),
		"output_queue": output_queue,
		"held": held,
		"progress": clampf(float(source.get("progress", 0.0)), 0.0, 1.0),
		"powered": true,
	}

func _serialize_resources() -> Array:
	var result: Array = []
	for resource in resources.values():
		result.append({
			"cell": _serialize_cell(resource.get("cell", Vector2i(-1, -1))),
			"amount": int(resource.get("amount", 0)),
			"phase": float(resource.get("phase", 0.0)),
		})
	return result

func _deserialize_resource(raw_resource: Variant) -> Dictionary:
	if typeof(raw_resource) != TYPE_DICTIONARY:
		return {}

	var source: Dictionary = raw_resource
	return {
		"cell": _deserialize_cell(source.get("cell", {})),
		"amount": max(0, int(source.get("amount", 0))),
		"phase": float(source.get("phase", 0.0)),
	}

func _serialize_items(source_items: Array) -> Array:
	var result: Array = []
	for item in source_items:
		result.append(_serialize_item(_normalize_item(item)))
	return result

func _deserialize_items(raw_items: Variant) -> Array:
	var result: Array = []
	for raw_item in _as_array(raw_items):
		var item := _deserialize_optional_item(raw_item)
		if not item.is_empty():
			result.append(item)
	return result

func _serialize_optional_item(raw_item: Variant) -> Dictionary:
	if typeof(raw_item) != TYPE_DICTIONARY or Dictionary(raw_item).is_empty():
		return {}
	return _serialize_item(_normalize_item(raw_item))

func _serialize_item(item: Dictionary) -> Dictionary:
	return {
		"type": String(item.get("type", Config.ITEM_ORE)),
		"tier": int(item.get("tier", Config.DEFAULT_ITEM_TIER)),
		"quality": float(item.get("quality", Config.DEFAULT_ITEM_QUALITY)),
		"premium": bool(item.get("premium", false)),
		"cell": _serialize_cell(item.get("cell", Vector2i(-1, -1))),
		"dir": int(item.get("dir", 0)),
		"progress": float(item.get("progress", 0.0)),
		"age": float(item.get("age", 0.0)),
	}

func _deserialize_optional_item(raw_item: Variant) -> Dictionary:
	if typeof(raw_item) != TYPE_DICTIONARY or Dictionary(raw_item).is_empty():
		return {}

	var source: Dictionary = raw_item
	var item_type := String(source.get("type", Config.ITEM_ORE))
	if item_type != Config.ITEM_ORE and item_type != Config.ITEM_PART:
		return {}

	return _normalize_item({
		"type": item_type,
		"tier": int(source.get("tier", Config.DEFAULT_ITEM_TIER)),
		"quality": float(source.get("quality", Config.DEFAULT_ITEM_QUALITY)),
		"premium": bool(source.get("premium", false)),
		"cell": _deserialize_cell(source.get("cell", {})),
		"dir": int(source.get("dir", 0)),
		"progress": float(source.get("progress", 0.0)),
		"age": float(source.get("age", 0.0)),
	})

func _serialize_cell(cell: Vector2i) -> Dictionary:
	return {"x": cell.x, "y": cell.y}

func _deserialize_cell(raw_cell: Variant) -> Vector2i:
	if typeof(raw_cell) != TYPE_DICTIONARY:
		return Vector2i(-1, -1)

	var source: Dictionary = raw_cell
	return Vector2i(int(source.get("x", -1)), int(source.get("y", -1)))

func _deserialize_float_array(raw_values: Variant) -> Array:
	var result: Array = []
	for raw_value in _as_array(raw_values):
		result.append(float(raw_value))
	return result

func _as_array(value: Variant) -> Array:
	if typeof(value) != TYPE_ARRAY:
		return []
	return value

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
		item["progress"] = Config.BLOCKED_ITEM_PROGRESS
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
		item["progress"] = Config.BLOCKED_ITEM_PROGRESS
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
