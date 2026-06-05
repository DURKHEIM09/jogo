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
var mode := Config.MODE_FACTORY
var shop_inventory := []
var shop_price := Config.SHOP_INITIAL_PRICE
var shop_reputation := Config.SHOP_INITIAL_REPUTATION
var shop_customers_served := 0
var shop_customers_lost := 0
var shop_sales := 0
var shop_revenue := 0
var shop_quality_sum := 0.0
var shop_quality_count := 0
var shop_best_quality := Config.DEFAULT_ITEM_QUALITY
var shop_premium_produced := 0
var shop_consumed_base := 0
var shop_consumed_premium := 0
var shop_spawn_timer := Config.SHOP_CUSTOMER_INITIAL_SPAWN
var shop_customers := []
var shop_employee := {}
var market_timer := Config.MARKET_INITIAL_TIMER
var market_quotes := {}
var market_ore_sold := 0
var market_part_sold := 0
var market_revenue := 0

func _init() -> void:
	rng.randomize()
	_reset_shop_state()
	_reset_market_state()
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
	changed_this_tick = _update_market(dt) or changed_this_tick
	changed_this_tick = _update_employee(dt) or changed_this_tick
	changed_this_tick = _update_shop(dt) or changed_this_tick

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

func set_mode(next_mode: String) -> bool:
	if not Config.is_known_mode(next_mode):
		return false
	if mode == next_mode:
		return true
	mode = next_mode
	emit_signal("changed")
	return true

func toggle_mode() -> void:
	if mode == Config.MODE_FACTORY:
		set_mode(Config.MODE_SHOP)
	else:
		set_mode(Config.MODE_FACTORY)

func get_shop_inventory() -> Array:
	return shop_inventory.duplicate(true)

func get_shop_customers() -> Array:
	return shop_customers.duplicate(true)

func get_shop_stock() -> int:
	return shop_inventory.size()

func get_shop_base_stock() -> int:
	var count := 0
	for item in shop_inventory:
		var part: Dictionary = item
		if not bool(part.get("premium", false)):
			count += 1
	return count

func get_shop_premium_stock() -> int:
	var count := 0
	for item in shop_inventory:
		var part: Dictionary = item
		if bool(part.get("premium", false)):
			count += 1
	return count

func get_shop_average_quality() -> float:
	if shop_quality_count <= 0:
		return Config.DEFAULT_ITEM_QUALITY
	return shop_quality_sum / float(shop_quality_count)

func get_shop_employee() -> Dictionary:
	return shop_employee.duplicate(true)

func employee_available() -> bool:
	return bool(shop_employee.get("hired", false)) and bool(shop_employee.get("active", false))

func get_customer_capacity() -> int:
	return Config.EMPLOYEE_CUSTOMER_CAPACITY if employee_available() else Config.SHOP_CUSTOMER_CAPACITY

func set_shop_price(next_price: int) -> bool:
	var clamped_price: int = max(Config.SHOP_MIN_PRICE, min(Config.SHOP_MAX_PRICE, next_price))
	if shop_price == clamped_price:
		return false
	shop_price = clamped_price
	emit_signal("changed")
	return true

func adjust_shop_price(delta: int) -> bool:
	return set_shop_price(shop_price + delta)

func get_shop_demand() -> float:
	var price_pressure := clampf(
		Config.SHOP_DEMAND_PRICE_ANCHOR / maxf(1.0, float(shop_price)),
		Config.SHOP_DEMAND_PRICE_MIN,
		Config.SHOP_DEMAND_PRICE_MAX
	)
	var reputation_boost := clampf(
		shop_reputation / Config.SHOP_INITIAL_REPUTATION,
		Config.SHOP_DEMAND_REPUTATION_MIN,
		Config.SHOP_DEMAND_REPUTATION_MAX
	)
	var stock_boost := 1.0 if get_shop_stock() > 0 else Config.SHOP_EMPTY_STOCK_DEMAND_FACTOR
	return price_pressure * reputation_boost * stock_boost

func get_shop_report() -> Dictionary:
	var demand := get_shop_demand()
	var employee_report := get_employee_report()
	var direct_costs := int(employee_report["salary_paid"]) + int(employee_report["hiring_paid"])
	return {
		"stock": get_shop_stock(),
		"base_stock": get_shop_base_stock(),
		"premium_stock": get_shop_premium_stock(),
		"price": shop_price,
		"reputation": shop_reputation,
		"demand": demand,
		"demand_label": _shop_demand_label(demand),
		"customers_served": shop_customers_served,
		"customers_lost": shop_customers_lost,
		"customers_active": shop_customers.size(),
		"customer_capacity": get_customer_capacity(),
		"sales": shop_sales,
		"revenue": shop_revenue,
		"salaries": int(employee_report["salary_paid"]),
		"hiring": int(employee_report["hiring_paid"]),
		"direct_costs": direct_costs,
		"gross_profit": shop_revenue - direct_costs,
		"average_quality": get_shop_average_quality(),
		"best_quality": shop_best_quality,
		"premium_produced": shop_premium_produced,
		"employee": employee_report,
		"bottleneck": _get_shop_bottleneck(demand),
	}

func get_employee_report() -> Dictionary:
	var hired := bool(shop_employee.get("hired", false))
	var active := bool(shop_employee.get("active", false))
	var status := "vaga"
	if hired:
		status = "ativa" if active else "sem salario"
	return {
		"hired": hired,
		"active": active,
		"status": status,
		"name": String(shop_employee.get("name", Config.EMPLOYEE_NAME)),
		"role": String(shop_employee.get("role", Config.EMPLOYEE_ROLE)),
		"hiring_cost": int(shop_employee.get("hiring_cost", Config.EMPLOYEE_HIRING_COST)),
		"wage": int(shop_employee.get("wage", Config.EMPLOYEE_WAGE)),
		"wage_cycle": float(shop_employee.get("wage_cycle", Config.EMPLOYEE_WAGE_CYCLE)),
		"wage_timer": float(shop_employee.get("wage_timer", Config.EMPLOYEE_WAGE_CYCLE)),
		"productivity": float(shop_employee.get("productivity", Config.EMPLOYEE_PRODUCTIVITY)),
		"reliability": float(shop_employee.get("reliability", Config.EMPLOYEE_RELIABILITY)),
		"effective_reliability": _employee_effective_reliability(),
		"morale": float(shop_employee.get("morale", Config.EMPLOYEE_INITIAL_MORALE)),
		"salary_paid": int(shop_employee.get("salary_paid", 0)),
		"hiring_paid": int(shop_employee.get("hiring_paid", 0)),
		"service_count": int(shop_employee.get("service_count", 0)),
		"service_fails": int(shop_employee.get("service_fails", 0)),
		"missed_payroll": int(shop_employee.get("missed_payroll", 0)),
	}

func toggle_employee() -> Dictionary:
	if bool(shop_employee.get("hired", false)):
		shop_employee["hired"] = false
		shop_employee["active"] = false
		shop_employee["wage_timer"] = Config.EMPLOYEE_WAGE_CYCLE
		emit_signal("changed")
		return {
			"ok": true,
			"action": "dismissed",
			"message": "Nina demitida.",
			"money": money,
			"money_delta": 0,
		}

	var hiring_cost := int(shop_employee.get("hiring_cost", Config.EMPLOYEE_HIRING_COST))
	if money < hiring_cost:
		return {
			"ok": false,
			"action": "blocked",
			"message": "Creditos insuficientes para contratar Nina.",
			"money": money,
			"money_delta": 0,
		}

	money -= hiring_cost
	shop_employee["hiring_paid"] = int(shop_employee.get("hiring_paid", 0)) + hiring_cost
	shop_employee["hired"] = true
	shop_employee["active"] = true
	shop_employee["wage_timer"] = Config.EMPLOYEE_WAGE_CYCLE
	shop_employee["morale"] = Config.EMPLOYEE_INITIAL_MORALE
	emit_signal("changed")
	return {
		"ok": true,
		"action": "hired",
		"message": "Nina contratada.",
		"money": money,
		"money_delta": -hiring_cost,
	}

func get_market_quote(item_type: String) -> Dictionary:
	_ensure_market_quotes()
	if not market_quotes.has(item_type):
		return _create_market_quote(item_type)
	return Dictionary(market_quotes[item_type]).duplicate(true)

func get_market_report() -> Dictionary:
	return {
		"ore": get_market_quote(Config.ITEM_ORE),
		"part": get_market_quote(Config.ITEM_PART),
		"ore_sold": market_ore_sold,
		"part_sold": market_part_sold,
		"revenue": market_revenue,
		"premium_stock": get_shop_premium_stock(),
		"average_quality": get_shop_average_quality(),
		"best_quality": shop_best_quality,
		"bid_factor_safe": is_market_bid_factor_safe(),
	}

func is_market_bid_factor_safe() -> bool:
	return Config.MARKET_BID_FACTOR < 1.0 and Config.MARKET_ASK_FACTOR > 1.0

func sell_ore_to_market(amount := 1) -> int:
	return _sell_to_market(Config.ITEM_ORE, max(0, amount))

func sell_base_part_to_market(amount := 1) -> int:
	var quantity := _consume_base_shop_stock(max(0, amount))
	if quantity <= 0:
		return 0
	return _sell_to_market(Config.ITEM_PART, quantity)

func spawn_shop_customer(budget: int = -1, notify: bool = true) -> Dictionary:
	if shop_customers.size() >= get_customer_capacity():
		return {}

	var next_budget := int(budget)
	if next_budget < 0:
		next_budget = (
			Config.SHOP_CUSTOMER_BUDGET_BASE
			+ rng.randi_range(0, Config.SHOP_CUSTOMER_BUDGET_RANGE - 1)
			+ int(floor(shop_reputation / Config.SHOP_CUSTOMER_BUDGET_REPUTATION_DIVISOR))
		)

	var customer := {
		"x": 0.12,
		"y": 0.92,
		"target_x": 0.34,
		"target_y": 0.58,
		"state": Config.CUSTOMER_ENTERING,
		"wait": 0.0,
		"color_index": rng.randi_range(0, 2),
		"budget": next_budget,
		"done": false,
		"bought": false,
		"lost_reason": "",
	}
	shop_customers.append(customer)
	if notify:
		emit_signal("changed")
	return customer

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
		"mode": mode,
		"selected_tool": selected_tool,
		"selected_dir": selected_dir,
		"simulation_time": simulation_time,
		"parts": parts,
		"ore_stored": ore_stored,
		"produced_times": produced_times.duplicate(true),
		"buildings": _serialize_buildings(),
		"resources": _serialize_resources(),
		"items": _serialize_items(items),
		"shop": _serialize_shop(),
		"market": _serialize_market(),
	}

func load_snapshot(snapshot: Dictionary) -> bool:
	money = int(snapshot.get("money", Config.INITIAL_MONEY))
	mode = String(snapshot.get("mode", Config.MODE_FACTORY))
	if not Config.is_known_mode(mode):
		mode = Config.MODE_FACTORY
	selected_tool = String(snapshot.get("selected_tool", Config.TOOL_BELT))
	if not Config.is_known_tool(selected_tool):
		selected_tool = Config.TOOL_BELT
	selected_dir = posmod(int(snapshot.get("selected_dir", 0)), Config.DIRECTION_COUNT)
	simulation_time = maxf(0.0, float(snapshot.get("simulation_time", 0.0)))
	parts = max(0, int(snapshot.get("parts", 0)))
	ore_stored = max(0, int(snapshot.get("ore_stored", 0)))
	produced_times = _deserialize_float_array(snapshot.get("produced_times", []))
	var has_shop_snapshot := snapshot.has("shop")
	_load_shop_snapshot(snapshot.get("shop", {}))
	if not has_shop_snapshot and parts > 0:
		_seed_shop_from_legacy_parts(parts)
	_load_market_snapshot(snapshot.get("market", {}))

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
			sell_ore_to_market(1)
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

func _update_market(dt: float) -> bool:
	_ensure_market_quotes()
	var changed_market := false
	changed_market = _decay_market_pressure(Config.ITEM_ORE, Config.MARKET_PRESSURE_DECAY_ORE, dt) or changed_market
	changed_market = _decay_market_pressure(Config.ITEM_PART, Config.MARKET_PRESSURE_DECAY_PART, dt) or changed_market

	market_timer -= dt
	if market_timer > 0.0:
		return changed_market

	market_timer = Config.MARKET_TIMER_MIN + rng.randf() * Config.MARKET_TIMER_VARIANCE
	_update_market_item(Config.ITEM_ORE, Config.MARKET_ORE_DEMAND_MIN, Config.MARKET_ORE_DEMAND_MAX, Config.MARKET_ORE_VOLATILITY)
	_update_market_item(Config.ITEM_PART, Config.MARKET_PART_DEMAND_MIN, Config.MARKET_PART_DEMAND_MAX, Config.MARKET_PART_VOLATILITY)
	return true

func _update_market_item(item_type: String, min_demand: float, max_demand: float, volatility: float) -> void:
	var quote: Dictionary = market_quotes.get(item_type, _create_market_quote(item_type))
	var demand := float(quote.get("demand", 1.0))
	var random_walk := (rng.randf() - 0.48) * volatility
	var recovery := (1.0 - demand) * 0.08
	quote["demand"] = clampf(demand + random_walk + recovery, min_demand, max_demand)
	market_quotes[item_type] = _refresh_market_quote(quote, item_type)

func _decay_market_pressure(item_type: String, decay: float, dt: float) -> bool:
	var quote: Dictionary = market_quotes.get(item_type, _create_market_quote(item_type))
	var previous_pressure := float(quote.get("pressure", 0.0))
	if previous_pressure <= 0.0:
		return false
	quote["pressure"] = maxf(0.0, previous_pressure - dt * decay)
	market_quotes[item_type] = quote
	return not is_equal_approx(previous_pressure, float(quote["pressure"]))

func _sell_to_market(item_type: String, quantity: int) -> int:
	if quantity <= 0:
		return 0

	var quote := get_market_quote(item_type)
	var price := int(quote.get("bid", 1))
	var revenue := price * quantity
	money += revenue
	market_revenue += revenue

	var stored_quote: Dictionary = market_quotes.get(item_type, _create_market_quote(item_type))
	if item_type == Config.ITEM_PART:
		market_part_sold += quantity
		stored_quote["pressure"] = float(stored_quote.get("pressure", 0.0)) + Config.MARKET_SELL_PRESSURE_PART * quantity
	else:
		market_ore_sold += quantity
		stored_quote["pressure"] = float(stored_quote.get("pressure", 0.0)) + Config.MARKET_SELL_PRESSURE_ORE * quantity
	market_quotes[item_type] = _refresh_market_quote(stored_quote, item_type)
	return revenue

func _update_employee(dt: float) -> bool:
	if not bool(shop_employee.get("hired", false)):
		return false

	shop_employee["wage_timer"] = float(shop_employee.get("wage_timer", Config.EMPLOYEE_WAGE_CYCLE)) - dt
	if float(shop_employee["wage_timer"]) > 0.0:
		return false

	if money >= int(shop_employee.get("wage", Config.EMPLOYEE_WAGE)):
		var wage := int(shop_employee.get("wage", Config.EMPLOYEE_WAGE))
		money -= wage
		shop_employee["salary_paid"] = int(shop_employee.get("salary_paid", 0)) + wage
		shop_employee["wage_timer"] = float(shop_employee.get("wage_timer", 0.0)) + Config.EMPLOYEE_WAGE_CYCLE
		shop_employee["active"] = true
		shop_employee["morale"] = minf(100.0, float(shop_employee.get("morale", Config.EMPLOYEE_INITIAL_MORALE)) + Config.EMPLOYEE_PAY_MORALE_GAIN)
		return true

	shop_employee["active"] = false
	shop_employee["missed_payroll"] = int(shop_employee.get("missed_payroll", 0)) + 1
	shop_employee["wage_timer"] = Config.EMPLOYEE_WAGE_RETRY_DELAY
	shop_employee["morale"] = maxf(0.0, float(shop_employee.get("morale", Config.EMPLOYEE_INITIAL_MORALE)) - Config.EMPLOYEE_MISSED_PAYROLL_MORALE_PENALTY)
	shop_reputation = maxf(0.0, shop_reputation - Config.EMPLOYEE_MISSED_PAYROLL_REPUTATION_PENALTY)
	return true

func _update_shop(dt: float) -> bool:
	var changed_shop := false
	shop_spawn_timer -= dt * get_shop_demand()
	if shop_spawn_timer <= 0.0 and shop_customers.size() < get_customer_capacity():
		spawn_shop_customer(-1, false)
		shop_spawn_timer = Config.SHOP_CUSTOMER_SPAWN_MIN + rng.randf() * Config.SHOP_CUSTOMER_SPAWN_VARIANCE
		changed_shop = true

	for index in range(shop_customers.size() - 1, -1, -1):
		var customer: Dictionary = shop_customers[index]
		changed_shop = _update_customer(customer, dt) or changed_shop
		if bool(customer.get("done", false)):
			shop_customers.remove_at(index)
			changed_shop = true
		else:
			shop_customers[index] = customer

	return changed_shop

func _update_customer(customer: Dictionary, dt: float) -> bool:
	var customer_state := String(customer.get("state", Config.CUSTOMER_ENTERING))
	if customer_state == Config.CUSTOMER_ENTERING:
		_move_customer(customer, dt, float(customer.get("target_x", 0.34)), float(customer.get("target_y", 0.58)))
		if _customer_distance_squared(customer, float(customer.get("target_x", 0.34)), float(customer.get("target_y", 0.58))) < Config.SHOP_CUSTOMER_TARGET_EPSILON:
			customer["state"] = Config.CUSTOMER_SHOPPING
			customer["wait"] = _get_shopping_wait()
		return true

	if customer_state == Config.CUSTOMER_SHOPPING:
		customer["wait"] = float(customer.get("wait", 0.0)) - dt
		if float(customer["wait"]) <= 0.0:
			_try_customer_purchase(customer)
		return true

	if customer_state == Config.CUSTOMER_CHECKOUT:
		_move_customer(customer, dt, 0.68, 0.64)
		if _customer_distance_squared(customer, 0.68, 0.64) < Config.SHOP_CUSTOMER_TARGET_EPSILON:
			customer["state"] = Config.CUSTOMER_LEAVING
		return true

	if customer_state == Config.CUSTOMER_LEAVING:
		_move_customer(customer, dt, 0.92, 0.92)
		if float(customer.get("x", 0.0)) > 0.88 and float(customer.get("y", 0.0)) > 0.88:
			customer["done"] = true
		return true

	return false

func _move_customer(customer: Dictionary, dt: float, target_x: float, target_y: float) -> void:
	var current_x := float(customer.get("x", 0.0))
	var current_y := float(customer.get("y", 0.0))
	var dx := target_x - current_x
	var dy := target_y - current_y
	var distance := sqrt(dx * dx + dy * dy)
	if distance <= 0.0:
		customer["x"] = target_x
		customer["y"] = target_y
		return

	var step := minf(Config.SHOP_CUSTOMER_SPEED * dt, distance)
	customer["x"] = current_x + (dx / distance) * step
	customer["y"] = current_y + (dy / distance) * step

func _customer_distance_squared(customer: Dictionary, target_x: float, target_y: float) -> float:
	var dx := float(customer.get("x", 0.0)) - target_x
	var dy := float(customer.get("y", 0.0)) - target_y
	return dx * dx + dy * dy

func _get_shopping_wait() -> float:
	var base_wait := Config.SHOP_CUSTOMER_WAIT_MIN + rng.randf() * Config.SHOP_CUSTOMER_WAIT_VARIANCE
	if not employee_available():
		return base_wait

	if rng.randf() <= _employee_effective_reliability():
		shop_employee["service_count"] = int(shop_employee.get("service_count", 0)) + 1
		shop_employee["morale"] = minf(100.0, float(shop_employee.get("morale", Config.EMPLOYEE_INITIAL_MORALE)) + Config.EMPLOYEE_SERVICE_MORALE_GAIN)
		return base_wait / float(shop_employee.get("productivity", Config.EMPLOYEE_PRODUCTIVITY))

	shop_employee["service_fails"] = int(shop_employee.get("service_fails", 0)) + 1
	shop_employee["morale"] = maxf(0.0, float(shop_employee.get("morale", Config.EMPLOYEE_INITIAL_MORALE)) - Config.EMPLOYEE_SERVICE_FAIL_MORALE_PENALTY)
	return base_wait * Config.EMPLOYEE_SERVICE_FAIL_WAIT_MULTIPLIER

func _employee_effective_reliability() -> float:
	if not bool(shop_employee.get("hired", false)):
		return 0.0
	var morale_factor := clampf(
		float(shop_employee.get("morale", Config.EMPLOYEE_INITIAL_MORALE)) / Config.EMPLOYEE_INITIAL_MORALE,
		Config.EMPLOYEE_MORALE_FACTOR_MIN,
		Config.EMPLOYEE_MORALE_FACTOR_MAX
	)
	return clampf(
		float(shop_employee.get("reliability", Config.EMPLOYEE_RELIABILITY)) * morale_factor,
		Config.EMPLOYEE_RELIABILITY_MIN,
		Config.EMPLOYEE_RELIABILITY_MAX
	)

func _try_customer_purchase(customer: Dictionary) -> void:
	if get_shop_stock() <= 0:
		shop_customers_lost += 1
		shop_reputation = maxf(0.0, shop_reputation - Config.SHOP_REPUTATION_STOCKOUT_PENALTY)
		customer["lost_reason"] = "stock"
		customer["state"] = Config.CUSTOMER_LEAVING
		return

	if shop_price > int(customer.get("budget", 0)):
		shop_customers_lost += 1
		shop_reputation = maxf(0.0, shop_reputation - Config.SHOP_REPUTATION_PRICE_PENALTY)
		customer["lost_reason"] = "price"
		customer["state"] = Config.CUSTOMER_LEAVING
		return

	if _consume_shop_stock(1) <= 0:
		shop_customers_lost += 1
		shop_reputation = maxf(0.0, shop_reputation - Config.SHOP_REPUTATION_STOCKOUT_PENALTY)
		customer["lost_reason"] = "stock"
		customer["state"] = Config.CUSTOMER_LEAVING
		return

	shop_sales += 1
	shop_customers_served += 1
	shop_revenue += shop_price
	money += shop_price
	shop_reputation = minf(100.0, shop_reputation + _sale_reputation_gain())
	customer["bought"] = true
	customer["state"] = Config.CUSTOMER_CHECKOUT

func _sale_reputation_gain() -> float:
	return Config.EMPLOYEE_REPUTATION_SALE_GAIN if employee_available() else Config.SHOP_REPUTATION_SALE_GAIN

func _consume_shop_stock(amount: int, premium_only := false) -> int:
	var consumed := 0
	while consumed < amount:
		var stock_index := _find_consumable_shop_stock(premium_only)
		if stock_index < 0:
			break

		var part: Dictionary = shop_inventory[stock_index]
		shop_inventory.remove_at(stock_index)
		if bool(part.get("premium", false)):
			shop_consumed_premium += 1
		else:
			shop_consumed_base += 1
		consumed += 1

	return consumed

func _consume_base_shop_stock(amount: int) -> int:
	var consumed := 0
	while consumed < amount:
		var stock_index := _find_base_shop_stock()
		if stock_index < 0:
			break

		shop_inventory.remove_at(stock_index)
		shop_consumed_base += 1
		consumed += 1

	return consumed

func _find_consumable_shop_stock(premium_only: bool) -> int:
	for index in range(shop_inventory.size()):
		var base_candidate: Dictionary = shop_inventory[index]
		if bool(base_candidate.get("premium", false)):
			continue
		if not premium_only:
			return index

	for index in range(shop_inventory.size()):
		var premium_candidate: Dictionary = shop_inventory[index]
		if bool(premium_candidate.get("premium", false)):
			return index

	return -1

func _find_base_shop_stock() -> int:
	for index in range(shop_inventory.size()):
		var base_candidate: Dictionary = shop_inventory[index]
		if not bool(base_candidate.get("premium", false)):
			return index
	return -1

func _store_part(part: Dictionary) -> void:
	var stored_part := _make_stored_part(part)
	shop_inventory.append(stored_part)
	shop_quality_sum += float(stored_part.get("quality", Config.DEFAULT_ITEM_QUALITY))
	shop_quality_count += 1
	shop_best_quality = maxf(shop_best_quality, float(stored_part.get("quality", Config.DEFAULT_ITEM_QUALITY)))
	if bool(stored_part.get("premium", false)):
		shop_premium_produced += 1

	parts += 1
	produced_times.append(simulation_time)

func _make_stored_part(raw_part: Dictionary) -> Dictionary:
	var part := _normalize_item(raw_part)
	var quality := clampf(float(part.get("quality", Config.DEFAULT_ITEM_QUALITY)), Config.MIN_QUALITY, Config.MAX_QUALITY)
	part["type"] = Config.ITEM_PART
	part["tier"] = max(1, int(part.get("tier", Config.DEFAULT_ITEM_TIER)))
	part["quality"] = quality
	part["premium"] = quality >= Config.PREMIUM_THRESHOLD
	part["cell"] = Vector2i(-1, -1)
	part["dir"] = 0
	part["progress"] = 0.0
	part["age"] = 0.0
	return part

func _shop_demand_label(demand: float) -> String:
	if demand >= 1.12:
		return "alta"
	if demand <= 0.72:
		return "baixa"
	return "ok"

func _get_shop_bottleneck(demand: float) -> String:
	if get_shop_stock() <= 0:
		return "estoque"
	if bool(shop_employee.get("hired", false)) and not bool(shop_employee.get("active", false)):
		return "salario"
	if shop_customers.size() >= get_customer_capacity() - 1:
		return "fila"
	if not employee_available() and shop_customers.size() >= 3:
		return "atendimento"
	if int(shop_employee.get("service_fails", 0)) > max(2, int(float(shop_employee.get("service_count", 0)) * 0.35)):
		return "confiab."
	if demand <= 0.72:
		return "demanda"
	if shop_price >= 20 and shop_customers_lost > max(1, shop_customers_served):
		return "preco"
	return "ok"

func _update_rate_window() -> void:
	var cutoff := simulation_time - Config.RATE_WINDOW_SECONDS
	produced_times = produced_times.filter(func(stamp): return float(stamp) >= cutoff)

func _serialize_buildings() -> Array:
	var result: Array = []
	for building in buildings.values():
		result.append(_serialize_building(building))
	return result

func _serialize_shop() -> Dictionary:
	return {
		"stock": get_shop_stock(),
		"price": shop_price,
		"reputation": shop_reputation,
		"customers_served": shop_customers_served,
		"customers_lost": shop_customers_lost,
		"sales": shop_sales,
		"revenue": shop_revenue,
		"spawn_timer": shop_spawn_timer,
		"base_stock": get_shop_base_stock(),
		"premium_stock": get_shop_premium_stock(),
		"quality_sum": shop_quality_sum,
		"quality_count": shop_quality_count,
		"best_quality": shop_best_quality,
		"premium_produced": shop_premium_produced,
		"consumed_base": shop_consumed_base,
		"consumed_premium": shop_consumed_premium,
		"employee": _serialize_employee(),
		"inventory": _serialize_items(shop_inventory),
	}

func _serialize_employee() -> Dictionary:
	return {
		"hired": bool(shop_employee.get("hired", false)),
		"active": bool(shop_employee.get("active", false)),
		"name": String(shop_employee.get("name", Config.EMPLOYEE_NAME)),
		"role": String(shop_employee.get("role", Config.EMPLOYEE_ROLE)),
		"hiring_cost": int(shop_employee.get("hiring_cost", Config.EMPLOYEE_HIRING_COST)),
		"wage": int(shop_employee.get("wage", Config.EMPLOYEE_WAGE)),
		"wage_cycle": float(shop_employee.get("wage_cycle", Config.EMPLOYEE_WAGE_CYCLE)),
		"wage_timer": float(shop_employee.get("wage_timer", Config.EMPLOYEE_WAGE_CYCLE)),
		"productivity": float(shop_employee.get("productivity", Config.EMPLOYEE_PRODUCTIVITY)),
		"reliability": float(shop_employee.get("reliability", Config.EMPLOYEE_RELIABILITY)),
		"morale": float(shop_employee.get("morale", Config.EMPLOYEE_INITIAL_MORALE)),
		"salary_paid": int(shop_employee.get("salary_paid", 0)),
		"hiring_paid": int(shop_employee.get("hiring_paid", 0)),
		"service_count": int(shop_employee.get("service_count", 0)),
		"service_fails": int(shop_employee.get("service_fails", 0)),
		"missed_payroll": int(shop_employee.get("missed_payroll", 0)),
	}

func _serialize_market() -> Dictionary:
	_ensure_market_quotes()
	return {
		"timer": market_timer,
		"ore_sold": market_ore_sold,
		"part_sold": market_part_sold,
		"revenue": market_revenue,
		"ore": _serialize_market_quote(market_quotes[Config.ITEM_ORE]),
		"part": _serialize_market_quote(market_quotes[Config.ITEM_PART]),
	}

func _serialize_market_quote(quote: Dictionary) -> Dictionary:
	return {
		"cost": int(quote.get("cost", 1)),
		"bid": int(quote.get("bid", 1)),
		"ask": int(quote.get("ask", 2)),
		"price": int(quote.get("price", quote.get("bid", 1))),
		"base": int(quote.get("base", quote.get("cost", 1))),
		"demand": float(quote.get("demand", 1.0)),
		"pressure": float(quote.get("pressure", 0.0)),
		"last_price": int(quote.get("last_price", quote.get("lastPrice", quote.get("bid", 1)))),
	}

func _load_shop_snapshot(raw_shop: Variant) -> void:
	_reset_shop_state()
	if typeof(raw_shop) != TYPE_DICTIONARY:
		return

	var source: Dictionary = raw_shop
	shop_price = max(Config.SHOP_MIN_PRICE, min(Config.SHOP_MAX_PRICE, int(source.get("price", Config.SHOP_INITIAL_PRICE))))
	shop_reputation = clampf(float(source.get("reputation", Config.SHOP_INITIAL_REPUTATION)), 0.0, 100.0)
	shop_customers_served = max(0, int(source.get("customers_served", source.get("customersServed", 0))))
	shop_customers_lost = max(0, int(source.get("customers_lost", source.get("customersLost", 0))))
	shop_sales = max(0, int(source.get("sales", 0)))
	shop_revenue = max(0, int(source.get("revenue", 0)))
	shop_spawn_timer = maxf(0.1, float(source.get("spawn_timer", source.get("spawnTimer", Config.SHOP_CUSTOMER_INITIAL_SPAWN))))
	shop_consumed_base = max(0, int(source.get("consumed_base", source.get("consumedBase", 0))))
	shop_consumed_premium = max(0, int(source.get("consumed_premium", source.get("consumedPremium", 0))))
	shop_inventory = _deserialize_shop_inventory(source)
	shop_quality_sum = maxf(0.0, float(source.get("quality_sum", source.get("qualitySum", _sum_shop_inventory_quality()))))
	shop_quality_count = max(0, int(source.get("quality_count", source.get("qualityCount", shop_inventory.size()))))
	shop_best_quality = maxf(Config.DEFAULT_ITEM_QUALITY, float(source.get("best_quality", source.get("bestQuality", _best_shop_inventory_quality()))))
	shop_premium_produced = max(0, int(source.get("premium_produced", source.get("premiumProduced", get_shop_premium_stock()))))
	shop_employee = _deserialize_employee(source.get("employee", {}))

func _reset_shop_state() -> void:
	shop_inventory = []
	shop_price = Config.SHOP_INITIAL_PRICE
	shop_reputation = Config.SHOP_INITIAL_REPUTATION
	shop_customers_served = 0
	shop_customers_lost = 0
	shop_sales = 0
	shop_revenue = 0
	shop_quality_sum = 0.0
	shop_quality_count = 0
	shop_best_quality = Config.DEFAULT_ITEM_QUALITY
	shop_premium_produced = 0
	shop_consumed_base = 0
	shop_consumed_premium = 0
	shop_spawn_timer = Config.SHOP_CUSTOMER_INITIAL_SPAWN
	shop_customers = []
	shop_employee = _create_employee_state(false)

func _create_employee_state(hired: bool) -> Dictionary:
	return {
		"hired": hired,
		"active": hired,
		"name": Config.EMPLOYEE_NAME,
		"role": Config.EMPLOYEE_ROLE,
		"hiring_cost": Config.EMPLOYEE_HIRING_COST,
		"wage": Config.EMPLOYEE_WAGE,
		"wage_cycle": Config.EMPLOYEE_WAGE_CYCLE,
		"wage_timer": Config.EMPLOYEE_WAGE_CYCLE,
		"productivity": Config.EMPLOYEE_PRODUCTIVITY,
		"reliability": Config.EMPLOYEE_RELIABILITY,
		"morale": Config.EMPLOYEE_INITIAL_MORALE,
		"salary_paid": 0,
		"hiring_paid": 0,
		"service_count": 0,
		"service_fails": 0,
		"missed_payroll": 0,
	}

func _deserialize_employee(raw_employee: Variant) -> Dictionary:
	var employee := _create_employee_state(false)
	if typeof(raw_employee) != TYPE_DICTIONARY:
		return employee

	var source: Dictionary = raw_employee
	employee["hired"] = bool(source.get("hired", false))
	employee["active"] = bool(source.get("active", employee["hired"])) and bool(employee["hired"])
	employee["wage_timer"] = clampf(float(source.get("wage_timer", source.get("wageTimer", Config.EMPLOYEE_WAGE_CYCLE))), 1.0, Config.EMPLOYEE_WAGE_CYCLE)
	employee["productivity"] = maxf(0.1, float(source.get("productivity", Config.EMPLOYEE_PRODUCTIVITY)))
	employee["reliability"] = maxf(0.0, float(source.get("reliability", Config.EMPLOYEE_RELIABILITY)))
	employee["morale"] = clampf(float(source.get("morale", Config.EMPLOYEE_INITIAL_MORALE)), 0.0, 100.0)
	employee["salary_paid"] = max(0, int(source.get("salary_paid", source.get("salaryPaid", 0))))
	employee["hiring_paid"] = max(0, int(source.get("hiring_paid", source.get("hiringPaid", 0))))
	employee["service_count"] = max(0, int(source.get("service_count", source.get("serviceCount", 0))))
	employee["service_fails"] = max(0, int(source.get("service_fails", source.get("serviceFails", 0))))
	employee["missed_payroll"] = max(0, int(source.get("missed_payroll", source.get("missedPayroll", 0))))
	return employee

func _load_market_snapshot(raw_market: Variant) -> void:
	_reset_market_state()
	if typeof(raw_market) != TYPE_DICTIONARY:
		return

	var source: Dictionary = raw_market
	market_timer = maxf(0.0, float(source.get("timer", source.get("marketTimer", Config.MARKET_INITIAL_TIMER))))
	market_ore_sold = max(0, int(source.get("ore_sold", source.get("oreSold", 0))))
	market_part_sold = max(0, int(source.get("part_sold", source.get("partSold", 0))))
	market_revenue = max(0, int(source.get("revenue", 0)))
	market_quotes[Config.ITEM_ORE] = _deserialize_market_quote(source.get("ore", {}), Config.ITEM_ORE)
	market_quotes[Config.ITEM_PART] = _deserialize_market_quote(source.get("part", {}), Config.ITEM_PART)

func _reset_market_state() -> void:
	market_timer = Config.MARKET_INITIAL_TIMER
	market_ore_sold = 0
	market_part_sold = 0
	market_revenue = 0
	market_quotes = {
		Config.ITEM_ORE: _create_market_quote(Config.ITEM_ORE),
		Config.ITEM_PART: _create_market_quote(Config.ITEM_PART),
	}

func _ensure_market_quotes() -> void:
	if not market_quotes.has(Config.ITEM_ORE):
		market_quotes[Config.ITEM_ORE] = _create_market_quote(Config.ITEM_ORE)
	else:
		market_quotes[Config.ITEM_ORE] = _refresh_market_quote(market_quotes[Config.ITEM_ORE], Config.ITEM_ORE)

	if not market_quotes.has(Config.ITEM_PART):
		market_quotes[Config.ITEM_PART] = _create_market_quote(Config.ITEM_PART)
	else:
		market_quotes[Config.ITEM_PART] = _refresh_market_quote(market_quotes[Config.ITEM_PART], Config.ITEM_PART)

func _create_market_quote(item_type: String) -> Dictionary:
	var cost := Config.production_cost(item_type)
	var bid := Config.market_bid(cost)
	return {
		"item_type": item_type,
		"cost": cost,
		"bid": bid,
		"ask": Config.market_ask(cost),
		"price": bid,
		"base": cost,
		"demand": 1.0,
		"pressure": 0.0,
		"last_price": bid,
	}

func _refresh_market_quote(quote: Dictionary, item_type: String) -> Dictionary:
	var cost := Config.production_cost(item_type)
	var bid := Config.market_bid(cost)
	quote["item_type"] = item_type
	quote["cost"] = cost
	quote["base"] = cost
	quote["last_price"] = int(quote.get("price", quote.get("bid", bid)))
	quote["bid"] = bid
	quote["ask"] = Config.market_ask(cost)
	quote["price"] = bid
	return quote

func _deserialize_market_quote(raw_quote: Variant, item_type: String) -> Dictionary:
	var quote := _create_market_quote(item_type)
	if typeof(raw_quote) != TYPE_DICTIONARY:
		return quote

	var source: Dictionary = raw_quote
	quote["demand"] = clampf(float(source.get("demand", 1.0)), 0.0, 10.0)
	quote["pressure"] = maxf(0.0, float(source.get("pressure", 0.0)))
	quote["last_price"] = max(1, int(source.get("last_price", source.get("lastPrice", quote["bid"]))))
	return _refresh_market_quote(quote, item_type)

func _seed_shop_from_legacy_parts(count: int) -> void:
	for _index in range(max(0, count)):
		var part := _make_stored_part(_make_item(Config.ITEM_PART, Config.DEFAULT_ITEM_QUALITY))
		shop_inventory.append(part)
		shop_quality_sum += float(part.get("quality", Config.DEFAULT_ITEM_QUALITY))
		shop_quality_count += 1

func _deserialize_shop_inventory(source: Dictionary) -> Array:
	var inventory: Array = []
	for item in _deserialize_items(source.get("inventory", [])):
		var part: Dictionary = item
		if String(part.get("type", "")) == Config.ITEM_PART:
			inventory.append(_make_stored_part(part))

	if not inventory.is_empty():
		return inventory

	var stock: int = max(0, int(source.get("stock", 0)))
	var premium_count: int = max(0, int(source.get("premium_stock", source.get("premiumStock", 0))))
	var base_count: int = max(0, int(source.get("base_stock", source.get("baseStock", max(0, stock - premium_count)))))
	premium_count = min(premium_count, stock)
	base_count = min(base_count, max(0, stock - premium_count))

	for _index in range(base_count):
		inventory.append(_make_stored_part(_make_item(Config.ITEM_PART, Config.DEFAULT_ITEM_QUALITY)))
	for _index in range(premium_count):
		inventory.append(_make_stored_part(_make_item(Config.ITEM_PART, Config.PREMIUM_THRESHOLD)))

	return inventory

func _sum_shop_inventory_quality() -> float:
	var total := 0.0
	for item in shop_inventory:
		var part: Dictionary = item
		total += float(part.get("quality", Config.DEFAULT_ITEM_QUALITY))
	return total

func _best_shop_inventory_quality() -> float:
	var best := Config.DEFAULT_ITEM_QUALITY
	for item in shop_inventory:
		var part: Dictionary = item
		best = maxf(best, float(part.get("quality", Config.DEFAULT_ITEM_QUALITY)))
	return best

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
