extends Node

const Config := preload("res://scripts/config/bootstrap_config.gd")
const FactoryStateScript := preload("res://scripts/factory/factory_state.gd")

func _ready() -> void:
	var state = FactoryStateScript.new()
	if not _expect(state.money == Config.INITIAL_MONEY, "initial money mismatch"):
		return

	var cell := Vector2i(2, 3)
	var placed: Dictionary = state.try_apply_tool(cell)
	if not _expect(bool(placed["ok"]), "belt placement failed"):
		return
	if not _expect(state.money == Config.INITIAL_MONEY - Config.tool_cost(Config.TOOL_BELT), "belt cost mismatch"):
		return

	state.rotate_selection()
	var rotated: Dictionary = state.try_apply_tool(cell)
	if not _expect(bool(rotated["ok"]) and String(rotated["action"]) == "rotated", "same tool should rotate existing building"):
		return
	if not _expect(state.money == Config.INITIAL_MONEY - Config.tool_cost(Config.TOOL_BELT), "rotation changed money"):
		return

	state.select_tool(Config.TOOL_ERASE)
	var removed: Dictionary = state.try_apply_tool(cell)
	if not _expect(bool(removed["ok"]), "remove failed"):
		return
	var expected_money := Config.INITIAL_MONEY - Config.tool_cost(Config.TOOL_BELT) + Config.tool_refund(Config.TOOL_BELT)
	if not _expect(state.money == expected_money, "refund mismatch"):
		return

	if not _expect(state.get_resources().size() > 0, "resources were not generated"):
		return

	var empty_cell := _first_empty_resource_cell(state)
	if not _expect(empty_cell != Vector2i(-1, -1), "could not find empty resource cell"):
		return

	state.select_tool(Config.TOOL_MINER)
	var blocked_miner: Dictionary = state.try_apply_tool(empty_cell)
	if not _expect(not bool(blocked_miner["ok"]), "miner should require ore cell"):
		return
	if not _expect(state.money == expected_money, "blocked miner changed money"):
		return

	while state.selected_dir != 0:
		state.rotate_selection()

	var ore_cell: Vector2i = _first_ore_cell_with_right_room(state, 8)
	if not _expect(ore_cell != Vector2i(-1, -1), "could not find ore cell with enough right-side room"):
		return
	var placed_miner: Dictionary = state.try_apply_tool(ore_cell)
	if not _expect(bool(placed_miner["ok"]), "miner placement on ore failed"):
		return
	if not _expect(state.money == expected_money - Config.tool_cost(Config.TOOL_MINER), "miner cost mismatch"):
		return

	var amount_before := state.get_resource_amount(ore_cell)
	_advance(state, Config.MINER_INTERVAL * 2.0)
	if not _expect(state.get_items().is_empty(), "miner should wait for belt output"):
		return
	if not _expect(state.get_resource_amount(ore_cell) == amount_before, "miner consumed resource without belt"):
		return

	state.select_tool(Config.TOOL_BELT)
	var belt_cell := ore_cell + Config.direction_offset(0)
	var placed_belt: Dictionary = state.try_apply_tool(belt_cell)
	if not _expect(bool(placed_belt["ok"]), "belt placement for miner output failed"):
		return

	_advance(state, Config.MINER_INTERVAL * 2.0)
	var spawned_items := state.get_items().size()
	if not _expect(spawned_items >= 1, "miner did not spawn ore item"):
		return
	if not _expect(state.get_resource_amount(ore_cell) == amount_before - spawned_items, "miner resource consumption mismatch"):
		return
	if not _expect(_has_item_at(state, belt_cell), "belt did not move ore item into its cell"):
		return

	var inserter_cell := belt_cell + Config.direction_offset(0)
	var drop_cell := inserter_cell + Config.direction_offset(0)

	state.select_tool(Config.TOOL_INSERTER)
	var placed_inserter: Dictionary = state.try_apply_tool(inserter_cell)
	if not _expect(bool(placed_inserter["ok"]), "inserter placement failed"):
		return

	state.select_tool(Config.TOOL_BELT)
	var placed_drop_belt: Dictionary = state.try_apply_tool(drop_cell)
	if not _expect(bool(placed_drop_belt["ok"]), "drop belt placement failed"):
		return

	_advance(state, 1.2)
	if not _expect(_has_item_at(state, drop_cell), "inserter did not move item to drop belt"):
		return

	var feed_inserter_cell := drop_cell + Config.direction_offset(0)
	var assembler_cell := feed_inserter_cell + Config.direction_offset(0)

	state.select_tool(Config.TOOL_INSERTER)
	var placed_feed_inserter: Dictionary = state.try_apply_tool(feed_inserter_cell)
	if not _expect(bool(placed_feed_inserter["ok"]), "feed inserter placement failed"):
		return

	state.select_tool(Config.TOOL_ASSEMBLER)
	var placed_assembler: Dictionary = state.try_apply_tool(assembler_cell)
	if not _expect(bool(placed_assembler["ok"]), "assembler placement failed"):
		return

	_advance(state, 12.0)
	var assembler: Dictionary = state.get_building(assembler_cell)
	if not _expect(int(assembler.get("output_parts", 0)) >= 1, "assembler did not produce part"):
		return

	var output_queue: Array = assembler.get("output_queue", [])
	if not _expect(not output_queue.is_empty(), "assembler output queue missing part"):
		return
	var first_part: Dictionary = output_queue[0]
	if not _expect(String(first_part.get("type", "")) == Config.ITEM_PART, "assembler output is not part"):
		return
	if not _expect(float(first_part.get("quality", 0.0)) >= Config.MIN_QUALITY, "part quality below minimum"):
		return

	var output_inserter_cell := assembler_cell + Config.direction_offset(0)
	var storage_cell := output_inserter_cell + Config.direction_offset(0)

	state.select_tool(Config.TOOL_INSERTER)
	var placed_output_inserter: Dictionary = state.try_apply_tool(output_inserter_cell)
	if not _expect(bool(placed_output_inserter["ok"]), "output inserter placement failed"):
		return

	state.select_tool(Config.TOOL_STORAGE)
	var placed_storage: Dictionary = state.try_apply_tool(storage_cell)
	if not _expect(bool(placed_storage["ok"]), "storage placement failed"):
		return

	_advance(state, 2.0)
	if not _expect(state.parts >= 1, "storage did not receive produced part"):
		return
	if not _expect(state.get_parts_per_minute() >= 1, "parts per minute rate did not update"):
		return

	print("FACTORYOPS_BUILDING_STATE_SMOKE_OK")
	get_tree().quit(0)

func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("FACTORYOPS_BUILDING_STATE_SMOKE_FAIL:" + message)
	get_tree().quit(1)
	return false

func _first_empty_resource_cell(state) -> Vector2i:
	for y in range(Config.GRID_ROWS):
		for x in range(Config.GRID_COLUMNS):
			var cell := Vector2i(x, y)
			if not state.has_resource(cell):
				return cell
	return Vector2i(-1, -1)

func _first_ore_cell_with_right_room(state, right_room: int) -> Vector2i:
	for resource in state.get_resources():
		var cell: Vector2i = resource.get("cell", Vector2i(-1, -1))
		if cell.x + right_room < Config.GRID_COLUMNS:
			return cell
	return Vector2i(-1, -1)

func _advance(state, seconds: float) -> void:
	var remaining := seconds
	while remaining > 0.0:
		var dt: float = minf(Config.SIMULATION_DT_CLAMP, remaining)
		state.tick(dt)
		remaining -= dt

func _has_item_at(state, cell: Vector2i) -> bool:
	for item in state.get_items():
		var item_cell: Vector2i = item.get("cell", Vector2i(-1, -1))
		if item_cell == cell:
			return true
	return false
