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

	var ore_cell: Vector2i = state.get_resources()[0]["cell"]
	var placed_miner: Dictionary = state.try_apply_tool(ore_cell)
	if not _expect(bool(placed_miner["ok"]), "miner placement on ore failed"):
		return
	if not _expect(state.money == expected_money - Config.tool_cost(Config.TOOL_MINER), "miner cost mismatch"):
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
