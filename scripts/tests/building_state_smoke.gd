extends Node

const Config := preload("res://scripts/config/bootstrap_config.gd")
const FactoryStateScript := preload("res://scripts/factory/factory_state.gd")

func _ready() -> void:
	var state = FactoryStateScript.new()
	state.shop_spawn_timer = 999.0
	if not _expect(state.money == Config.INITIAL_MONEY, "initial money mismatch"):
		return
	if not _expect(state.get_resources().is_empty(), "resource patches should not exist"):
		return
	if not _expect(not state.has_resource(Vector2i(0, 0)), "resource lookup should stay empty"):
		return
	if not _expect(Config.production_cost(Config.ITEM_ORE) == 1, "ore production cost mismatch"):
		return
	if not _expect(Config.production_cost(Config.ITEM_PART) == 4, "part production cost mismatch"):
		return
	if not _expect(state.is_market_bid_factor_safe(), "market bid/ask factors are unsafe"):
		return

	var initial_market: Dictionary = state.get_market_report()
	var initial_ore_quote: Dictionary = initial_market["ore"]
	var initial_part_quote: Dictionary = initial_market["part"]
	if not _expect(int(initial_ore_quote["bid"]) == 1 and int(initial_ore_quote["ask"]) == 2, "ore market quote mismatch"):
		return
	if not _expect(int(initial_part_quote["bid"]) == 2 and int(initial_part_quote["ask"]) == 6, "part market quote mismatch"):
		return
	if not _expect(Config.ASSEMBLER_INPUT_PER_PART * int(initial_ore_quote["ask"]) < Config.SHOP_INITIAL_PRICE, "store loop is not profitable"):
		return
	if not _expect(Config.tool_label(Config.TOOL_BUYER) == "Comprador", "buyer label mismatch"):
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

	while state.selected_dir != 0:
		state.rotate_selection()

	var buyer_cell := Vector2i(2, 3)
	var generator_cell := _generator_cell_for(buyer_cell)
	state.select_tool(Config.TOOL_GENERATOR)
	var placed_generator: Dictionary = state.try_apply_tool(generator_cell)
	if not _expect(bool(placed_generator["ok"]), "generator placement failed"):
		return
	if not _expect(state.power_capacity == Config.POWER_GENERATOR_OUTPUT, "generator capacity mismatch"):
		return

	var money_after_generator := expected_money - Config.tool_cost(Config.TOOL_GENERATOR)

	state.select_tool(Config.TOOL_BUYER)
	var placed_buyer: Dictionary = state.try_apply_tool(buyer_cell)
	if not _expect(bool(placed_buyer["ok"]), "buyer placement failed"):
		return
	if not _expect(state.money == money_after_generator - Config.tool_cost(Config.TOOL_BUYER), "buyer cost mismatch"):
		return
	if not _expect(bool(state.get_building(buyer_cell).get("powered", false)), "covered buyer should be powered"):
		return
	if not _expect(state.power_used == Config.POWER_USAGE_BUYER, "buyer power usage mismatch"):
		return

	var buyer_money_wait_before: int = state.money
	_advance(state, Config.BUYER_INTERVAL * 2.0)
	if not _expect(state.get_items().is_empty(), "buyer should wait for belt output"):
		return
	if not _expect(state.money == buyer_money_wait_before, "buyer spent money without output"):
		return
	if not _expect(int(state.get_market_report()["ore_bought"]) == 0, "buyer bought ore without output"):
		return

	state.select_tool(Config.TOOL_BELT)
	var belt_cell := buyer_cell + Config.direction_offset(0)
	var placed_belt: Dictionary = state.try_apply_tool(belt_cell)
	if not _expect(bool(placed_belt["ok"]), "belt placement for buyer output failed"):
		return

	var buyer_money_before: int = state.money
	var input_spend_before: int = int(state.get_market_report()["input_spend"])
	var ore_bought_before: int = int(state.get_market_report()["ore_bought"])
	var ore_ask: int = int(state.get_market_quote(Config.ITEM_ORE)["ask"])
	_advance(state, Config.BUYER_INTERVAL * 2.0)
	var buyer_report: Dictionary = state.get_market_report()
	var bought_delta: int = int(buyer_report["ore_bought"]) - ore_bought_before
	var spend_delta: int = int(buyer_report["input_spend"]) - input_spend_before
	if not _expect(state.get_items().size() >= 1, "buyer did not spawn ore item"):
		return
	if not _expect(bought_delta >= 1, "buyer did not count bought ore"):
		return
	if not _expect(spend_delta == bought_delta * ore_ask, "buyer input spend mismatch"):
		return
	if not _expect(state.money == buyer_money_before - spend_delta, "buyer did not pay market ask"):
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
	var first_part_quality := float(first_part.get("quality", Config.DEFAULT_ITEM_QUALITY))
	var first_part_premium := bool(first_part.get("premium", false))

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

	var expected_power_used := (
		Config.POWER_USAGE_BUYER
		+ Config.POWER_USAGE_INSERTER * 3
		+ Config.POWER_USAGE_ASSEMBLER
	)
	if not _expect(state.power_used == expected_power_used, "factory power usage mismatch"):
		return

	_advance(state, 2.0)
	if not _expect(state.parts >= 1, "storage did not receive produced part"):
		return
	if not _expect(state.get_parts_per_minute() >= 1, "parts per minute rate did not update"):
		return
	if not _expect(state.get_shop_stock() == state.parts, "warehouse did not feed shop stock"):
		return
	if not _expect(_shop_has_part(state, first_part_quality, first_part_premium), "shop stock did not preserve part quality"):
		return
	if not _expect(state.get_shop_base_stock() + state.get_shop_premium_stock() == state.get_shop_stock(), "shop base/premium split mismatch"):
		return
	var shop_report: Dictionary = state.get_shop_report()
	if not _expect(int(shop_report["stock"]) == state.get_shop_stock(), "shop report stock mismatch"):
		return
	if not _expect(float(shop_report["average_quality"]) >= Config.MIN_QUALITY, "shop average quality below minimum"):
		return
	var market_report: Dictionary = state.get_market_report()
	var market_part_quote: Dictionary = market_report["part"]
	if not _expect(int(market_part_quote["cost"]) == Config.production_cost(Config.ITEM_PART), "market report part cost mismatch"):
		return
	if not _expect(int(market_report["premium_stock"]) == state.get_shop_premium_stock(), "market premium signal mismatch"):
		return
	if not _expect(int(market_report["input_spend"]) > 0, "market report did not track input spend"):
		return
	if not _expect(state.set_mode(Config.MODE_SHOP) and state.mode == Config.MODE_SHOP, "shop mode switch failed"):
		return

	var snapshot := state.to_snapshot()
	if not _expect(not _snapshot_persists_powered(snapshot), "snapshot should not persist raw powered"):
		return
	if not _expect(snapshot.has("market"), "snapshot missing market"):
		return
	if not _expect(_as_array(snapshot.get("resources", [])).is_empty(), "snapshot should not persist resource patches"):
		return
	var restored = FactoryStateScript.new()
	if not _expect(restored.load_snapshot(snapshot), "snapshot load failed"):
		return
	if not _expect(restored.parts == state.parts, "snapshot parts mismatch"):
		return
	if not _expect(restored.get_buildings().size() == state.get_buildings().size(), "snapshot building count mismatch"):
		return
	if not _expect(restored.power_used == state.power_used and restored.power_capacity == state.power_capacity, "snapshot power totals mismatch"):
		return
	if not _expect(bool(restored.get_building(buyer_cell).get("powered", false)), "snapshot did not recalculate buyer power"):
		return
	if not _expect(restored.mode == Config.MODE_SHOP, "snapshot mode mismatch"):
		return
	if not _expect(restored.get_shop_stock() == state.get_shop_stock(), "snapshot shop stock mismatch"):
		return
	if not _expect(_shop_has_part(restored, first_part_quality, first_part_premium), "snapshot lost shop part quality"):
		return
	var restored_market: Dictionary = restored.get_market_report()
	var restored_part_quote: Dictionary = restored_market["part"]
	if not _expect(int(restored_part_quote["bid"]) == int(market_part_quote["bid"]), "snapshot market quote mismatch"):
		return
	if not _expect(int(restored_market["input_spend"]) == int(market_report["input_spend"]), "snapshot input spend mismatch"):
		return

	var legacy_snapshot: Dictionary = snapshot.duplicate(true)
	legacy_snapshot.erase("shop")
	var legacy_restored = FactoryStateScript.new()
	if not _expect(legacy_restored.load_snapshot(legacy_snapshot), "legacy snapshot load failed"):
		return
	if not _expect(legacy_restored.get_shop_stock() == legacy_restored.parts, "legacy parts did not migrate to shop stock"):
		return
	if not _expect(legacy_restored.get_shop_base_stock() == legacy_restored.parts, "legacy migrated stock should be base stock"):
		return

	var legacy_resource_snapshot: Dictionary = snapshot.duplicate(true)
	legacy_resource_snapshot["resources"] = [
		{"cell": {"x": 1, "y": 1}, "amount": 99, "phase": 0.0}
	]
	var resource_restored = FactoryStateScript.new()
	if not _expect(resource_restored.load_snapshot(legacy_resource_snapshot), "legacy resource snapshot load failed"):
		return
	if not _expect(resource_restored.get_resources().is_empty(), "legacy resources should be ignored"):
		return

	var legacy_buyer_snapshot := FactoryStateScript.new().to_snapshot()
	legacy_buyer_snapshot["buildings"] = [
		{
			"type": Config.TOOL_LEGACY_MINER,
			"cell": {"x": 3, "y": 3},
			"dir": 0,
			"timer": 0.0,
			"input_ore": 0,
			"output_parts": 0,
			"output_queue": [],
			"held": {},
			"progress": 0.0,
		}
	]
	var legacy_buyer = FactoryStateScript.new()
	if not _expect(legacy_buyer.load_snapshot(legacy_buyer_snapshot), "legacy miner snapshot load failed"):
		return
	if not _expect(String(legacy_buyer.get_building(Vector2i(3, 3)).get("type", "")) == Config.TOOL_BUYER, "legacy miner should migrate to buyer"):
		return

	var save_path := "user://factoryops_smoke_save.json"
	if not _expect(state.save_to_disk(save_path), "save_to_disk failed"):
		return
	var loaded = FactoryStateScript.new()
	if not _expect(loaded.load_from_disk(save_path), "load_from_disk failed"):
		return
	if not _expect(loaded.parts == state.parts, "disk save parts mismatch"):
		return
	if not _expect(loaded.power_used == state.power_used and loaded.power_capacity == state.power_capacity, "disk save power totals mismatch"):
		return
	if not _expect(loaded.mode == Config.MODE_SHOP, "disk save mode mismatch"):
		return
	if not _expect(loaded.get_shop_stock() == state.get_shop_stock(), "disk save shop stock mismatch"):
		return
	if not _expect(_shop_has_part(loaded, first_part_quality, first_part_premium), "disk save lost shop part quality"):
		return
	var loaded_market: Dictionary = loaded.get_market_report()
	var loaded_part_quote: Dictionary = loaded_market["part"]
	if not _expect(int(loaded_part_quote["ask"]) == int(market_part_quote["ask"]), "disk save market quote mismatch"):
		return
	if not _expect(int(loaded_market["input_spend"]) == int(market_report["input_spend"]), "disk save input spend mismatch"):
		return
	DirAccess.remove_absolute(ProjectSettings.globalize_path(save_path))

	state.select_tool(Config.TOOL_ERASE)
	var removed_generator: Dictionary = state.try_apply_tool(generator_cell)
	if not _expect(bool(removed_generator["ok"]), "generator removal failed"):
		return
	if not _expect(state.power_capacity == 0 and state.power_used == 0, "generator removal did not clear power totals"):
		return
	if not _expect(not bool(state.get_building(buyer_cell).get("powered", true)), "buyer stayed powered after generator removal"):
		return

	var parts_before_unpowered: int = state.parts
	_advance(state, Config.BUYER_INTERVAL * 2.0)
	if not _expect(state.parts == parts_before_unpowered, "unpowered factory kept producing after generator removal"):
		return

	var no_cash_buyer = FactoryStateScript.new()
	no_cash_buyer.shop_spawn_timer = 999.0
	no_cash_buyer.select_tool(Config.TOOL_GENERATOR)
	no_cash_buyer.try_apply_tool(Vector2i(1, 2))
	no_cash_buyer.select_tool(Config.TOOL_BUYER)
	no_cash_buyer.try_apply_tool(Vector2i(1, 1))
	no_cash_buyer.select_tool(Config.TOOL_BELT)
	no_cash_buyer.try_apply_tool(Vector2i(2, 1))
	no_cash_buyer.money = 0
	_advance(no_cash_buyer, Config.BUYER_INTERVAL * 2.0)
	var no_cash_report: Dictionary = no_cash_buyer.get_market_report()
	if not _expect(no_cash_buyer.money == 0, "no-cash buyer should not create debt"):
		return
	if not _expect(no_cash_buyer.get_items().is_empty(), "no-cash buyer should not spawn ore"):
		return
	if not _expect(int(no_cash_report["ore_bought"]) == 0 and int(no_cash_report["input_spend"]) == 0, "no-cash buyer should not buy ore"):
		return

	var sale_stock_before := state.get_shop_stock()
	var sale_money_before: int = state.money
	var sale_reputation_before: float = state.shop_reputation
	var sale_price: int = state.shop_price
	state.spawn_shop_customer(sale_price)
	_advance(state, 5.5)
	if not _expect(state.shop_sales == 1, "customer did not buy stocked item"):
		return
	if not _expect(state.shop_customers_served == 1, "served customer count did not update"):
		return
	if not _expect(state.money == sale_money_before + sale_price, "sale did not add money"):
		return
	if not _expect(state.shop_revenue == sale_price, "sale revenue mismatch"):
		return
	if not _expect(state.get_shop_stock() == sale_stock_before - 1, "sale did not consume shop stock"):
		return
	if not _expect(state.shop_reputation > sale_reputation_before, "sale did not improve reputation"):
		return

	var empty_shop = FactoryStateScript.new()
	empty_shop.shop_spawn_timer = 999.0
	var empty_reputation_before: float = empty_shop.shop_reputation
	empty_shop.spawn_shop_customer(Config.SHOP_MAX_PRICE)
	_advance(empty_shop, 5.5)
	if not _expect(empty_shop.shop_customers_lost == 1, "stockout customer did not count as lost"):
		return
	if not _expect(empty_shop.shop_reputation < empty_reputation_before, "stockout did not reduce reputation"):
		return

	var expensive_shop = FactoryStateScript.new()
	expensive_shop.shop_spawn_timer = 999.0
	expensive_shop._store_part(_test_part(Config.DEFAULT_ITEM_QUALITY))
	expensive_shop.shop_price = Config.SHOP_MAX_PRICE
	var expensive_reputation_before: float = expensive_shop.shop_reputation
	expensive_shop.spawn_shop_customer(Config.SHOP_MIN_PRICE)
	_advance(expensive_shop, 5.5)
	if not _expect(expensive_shop.shop_customers_lost == 1, "overpriced customer did not count as lost"):
		return
	if not _expect(expensive_shop.get_shop_stock() == 1, "overpriced customer consumed stock"):
		return
	if not _expect(expensive_shop.shop_reputation < expensive_reputation_before, "overprice did not reduce reputation"):
		return

	var demand_shop = FactoryStateScript.new()
	demand_shop.shop_spawn_timer = 999.0
	var empty_demand: float = demand_shop.get_shop_demand()
	demand_shop._store_part(_test_part(Config.DEFAULT_ITEM_QUALITY))
	var stocked_demand: float = demand_shop.get_shop_demand()
	if not _expect(stocked_demand > empty_demand, "demand did not react to available stock"):
		return
	if not _expect(demand_shop.set_shop_price(Config.SHOP_MAX_PRICE + 10), "shop price did not clamp to max"):
		return
	if not _expect(demand_shop.shop_price == Config.SHOP_MAX_PRICE, "shop max price clamp mismatch"):
		return
	var high_price_demand: float = demand_shop.get_shop_demand()
	if not _expect(demand_shop.adjust_shop_price(-1000), "shop price did not adjust down"):
		return
	if not _expect(demand_shop.shop_price == Config.SHOP_MIN_PRICE, "shop min price clamp mismatch"):
		return
	var low_price_demand: float = demand_shop.get_shop_demand()
	if not _expect(low_price_demand > high_price_demand, "demand did not react to price"):
		return
	demand_shop.shop_reputation = 10.0
	var low_reputation_demand: float = demand_shop.get_shop_demand()
	demand_shop.shop_reputation = 90.0
	var high_reputation_demand: float = demand_shop.get_shop_demand()
	if not _expect(high_reputation_demand > low_reputation_demand, "demand did not react to reputation"):
		return

	var employee_shop = FactoryStateScript.new()
	employee_shop.shop_spawn_timer = 999.0
	var initial_employee: Dictionary = employee_shop.get_employee_report()
	if not _expect(not bool(initial_employee["hired"]) and String(initial_employee["status"]) == "vaga", "employee should start vacant"):
		return
	if not _expect(employee_shop.get_customer_capacity() == Config.SHOP_CUSTOMER_CAPACITY, "base customer capacity mismatch"):
		return
	for _index in range(Config.SHOP_CUSTOMER_CAPACITY):
		employee_shop.spawn_shop_customer(Config.SHOP_INITIAL_PRICE)
	if not _expect(employee_shop.get_shop_customers().size() == Config.SHOP_CUSTOMER_CAPACITY, "base customer capacity did not cap at 6"):
		return
	if not _expect(employee_shop.spawn_shop_customer(Config.SHOP_INITIAL_PRICE).is_empty(), "base customer capacity accepted extra customer"):
		return

	var employee_money_before: int = employee_shop.money
	var hired_result: Dictionary = employee_shop.toggle_employee()
	if not _expect(bool(hired_result["ok"]) and String(hired_result["action"]) == "hired", "employee hire failed"):
		return
	if not _expect(employee_shop.money == employee_money_before - Config.EMPLOYEE_HIRING_COST, "employee hire cost mismatch"):
		return
	if not _expect(employee_shop.employee_available(), "employee should be active after hire"):
		return
	if not _expect(employee_shop.get_customer_capacity() == Config.EMPLOYEE_CUSTOMER_CAPACITY, "employee did not increase customer capacity"):
		return
	for _index in range(Config.EMPLOYEE_CUSTOMER_CAPACITY - Config.SHOP_CUSTOMER_CAPACITY):
		employee_shop.spawn_shop_customer(Config.SHOP_INITIAL_PRICE)
	if not _expect(employee_shop.get_shop_customers().size() == Config.EMPLOYEE_CUSTOMER_CAPACITY, "employee capacity did not cap at 10"):
		return
	if not _expect(employee_shop.spawn_shop_customer(Config.SHOP_INITIAL_PRICE).is_empty(), "employee capacity accepted extra customer"):
		return
	var employee_hire_report: Dictionary = employee_shop.get_shop_report()
	if not _expect(int(employee_hire_report["hiring"]) == Config.EMPLOYEE_HIRING_COST, "employee hiring cost missing from report"):
		return
	if not _expect(int(employee_hire_report["gross_profit"]) == -Config.EMPLOYEE_HIRING_COST, "employee hiring cost not deducted from gross profit"):
		return

	var dismissed_result: Dictionary = employee_shop.toggle_employee()
	if not _expect(bool(dismissed_result["ok"]) and String(dismissed_result["action"]) == "dismissed", "employee dismiss failed"):
		return
	if not _expect(not employee_shop.employee_available() and employee_shop.get_customer_capacity() == Config.SHOP_CUSTOMER_CAPACITY, "dismissed employee should remove active capacity"):
		return

	var broke_shop = FactoryStateScript.new()
	broke_shop.money = Config.EMPLOYEE_HIRING_COST - 1
	var blocked_hire: Dictionary = broke_shop.toggle_employee()
	if not _expect(not bool(blocked_hire["ok"]), "employee hire should require credits"):
		return
	if not _expect(not bool(broke_shop.get_employee_report()["hired"]), "blocked hire should not hire employee"):
		return

	var payroll_shop = FactoryStateScript.new()
	payroll_shop.shop_spawn_timer = 999.0
	payroll_shop.toggle_employee()
	var payroll_money_after_hire: int = payroll_shop.money
	_advance(payroll_shop, Config.EMPLOYEE_WAGE_CYCLE + 0.25)
	var payroll_employee: Dictionary = payroll_shop.get_employee_report()
	if not _expect(int(payroll_employee["salary_paid"]) == Config.EMPLOYEE_WAGE, "employee salary was not paid"):
		return
	if not _expect(payroll_shop.money == payroll_money_after_hire - Config.EMPLOYEE_WAGE, "employee salary did not debit money"):
		return
	if not _expect(bool(payroll_employee["active"]), "employee should stay active after paid salary"):
		return
	if not _expect(float(payroll_employee["morale"]) > Config.EMPLOYEE_INITIAL_MORALE, "paid salary did not improve morale"):
		return
	var payroll_report: Dictionary = payroll_shop.get_shop_report()
	if not _expect(int(payroll_report["gross_profit"]) == -(Config.EMPLOYEE_HIRING_COST + Config.EMPLOYEE_WAGE), "salary/hiring not deducted from report profit"):
		return
	var payroll_snapshot: Dictionary = payroll_shop.to_snapshot()
	var payroll_restored = FactoryStateScript.new()
	if not _expect(payroll_restored.load_snapshot(payroll_snapshot), "employee snapshot load failed"):
		return
	var payroll_restored_employee: Dictionary = payroll_restored.get_employee_report()
	if not _expect(bool(payroll_restored_employee["hired"]) and bool(payroll_restored_employee["active"]), "employee snapshot lost active hire"):
		return
	if not _expect(int(payroll_restored_employee["salary_paid"]) == Config.EMPLOYEE_WAGE, "employee snapshot salary mismatch"):
		return

	var late_shop = FactoryStateScript.new()
	late_shop.shop_spawn_timer = 999.0
	late_shop.toggle_employee()
	late_shop.money = 0
	var late_reputation_before: float = late_shop.shop_reputation
	_advance(late_shop, Config.EMPLOYEE_WAGE_CYCLE + 0.25)
	var late_employee: Dictionary = late_shop.get_employee_report()
	if not _expect(not bool(late_employee["active"]), "late payroll should deactivate employee"):
		return
	if not _expect(int(late_employee["missed_payroll"]) == 1, "late payroll count mismatch"):
		return
	if not _expect(float(late_employee["morale"]) < Config.EMPLOYEE_INITIAL_MORALE, "late payroll did not reduce morale"):
		return
	if not _expect(late_shop.shop_reputation < late_reputation_before, "late payroll did not reduce reputation"):
		return
	late_shop.money = Config.EMPLOYEE_WAGE
	_advance(late_shop, Config.EMPLOYEE_WAGE_RETRY_DELAY + 0.25)
	var recovered_employee: Dictionary = late_shop.get_employee_report()
	if not _expect(bool(recovered_employee["active"]) and int(recovered_employee["salary_paid"]) == Config.EMPLOYEE_WAGE, "employee did not recover after late payroll payment"):
		return

	var service_shop = FactoryStateScript.new()
	service_shop.shop_spawn_timer = 999.0
	service_shop.toggle_employee()
	for _index in range(12):
		service_shop._get_shopping_wait()
	var service_employee: Dictionary = service_shop.get_employee_report()
	if not _expect(int(service_employee["service_count"]) > 0, "employee reliability never produced faster service"):
		return
	if not _expect(float(service_employee["effective_reliability"]) > 0.0, "employee effective reliability missing"):
		return

	var employee_sale_shop = FactoryStateScript.new()
	employee_sale_shop.shop_spawn_timer = 999.0
	employee_sale_shop._store_part(_test_part(Config.DEFAULT_ITEM_QUALITY))
	employee_sale_shop.toggle_employee()
	var employee_sale_reputation_before: float = employee_sale_shop.shop_reputation
	employee_sale_shop.spawn_shop_customer(employee_sale_shop.shop_price)
	_advance(employee_sale_shop, 8.0)
	if not _expect(employee_sale_shop.shop_sales == 1, "employee shop customer did not buy"):
		return
	if not _expect(employee_sale_shop.shop_reputation >= employee_sale_reputation_before + 0.6, "employee sale did not improve reputation more"):
		return

	var setup_quality_shop = FactoryStateScript.new()
	var setup_cell := Vector2i(1, 1)
	var setup_building := {"powered": true}
	var setup_without_employee: float = setup_quality_shop._get_setup_quality(setup_cell, setup_building)
	setup_quality_shop.toggle_employee()
	var setup_with_employee: float = setup_quality_shop._get_setup_quality(setup_cell, setup_building)
	if not _expect(is_equal_approx(setup_without_employee, setup_with_employee), "employee should not change factory setup quality"):
		return

	var ore_market = FactoryStateScript.new()
	ore_market.shop_spawn_timer = 999.0
	ore_market.select_tool(Config.TOOL_STORAGE)
	var ore_storage_cell := Vector2i(5, 5)
	var placed_ore_storage: Dictionary = ore_market.try_apply_tool(ore_storage_cell)
	if not _expect(bool(placed_ore_storage["ok"]), "market ore storage placement failed"):
		return
	var ore_money_before: int = ore_market.money
	var ore_bid: int = int(ore_market.get_market_quote(Config.ITEM_ORE)["bid"])
	var dropped_ore: bool = ore_market._drop_from_inserter(ore_storage_cell - Config.direction_offset(0), 0, _test_ore())
	if not _expect(dropped_ore, "ore drop into storage failed"):
		return
	if not _expect(ore_market.money == ore_money_before + ore_bid, "ore auto-sale did not pay market bid"):
		return
	if not _expect(ore_market.ore_stored == 1, "ore auto-sale did not count stored ore"):
		return
	var ore_market_report: Dictionary = ore_market.get_market_report()
	if not _expect(int(ore_market_report["ore_sold"]) == 1, "ore market sale count mismatch"):
		return
	if not _expect(int(ore_market_report["ore_bought"]) == 0, "manual ore liquidation should not count as bought"):
		return

	var part_market = FactoryStateScript.new()
	part_market.shop_spawn_timer = 999.0
	part_market._store_part(_test_part(Config.DEFAULT_ITEM_QUALITY))
	part_market._store_part(_test_part(Config.PREMIUM_THRESHOLD))
	var part_bid: int = int(part_market.get_market_quote(Config.ITEM_PART)["bid"])
	var part_money_before: int = part_market.money
	var part_revenue: int = part_market.sell_base_part_to_market(1)
	if not _expect(part_revenue == part_bid, "base part market sale revenue mismatch"):
		return
	if not _expect(part_market.money == part_money_before + part_bid, "base part market sale did not add money"):
		return
	if not _expect(part_market.get_shop_base_stock() == 0 and part_market.get_shop_premium_stock() == 1, "premium should remain outside NPC corridor"):
		return
	var premium_revenue: int = part_market.sell_base_part_to_market(1)
	if not _expect(premium_revenue == 0, "premium part should not sell to NPC corridor"):
		return
	if not _expect(part_market.get_shop_premium_stock() == 1, "premium stock was consumed by NPC market"):
		return
	var part_market_snapshot: Dictionary = part_market.to_snapshot()
	var market_restored = FactoryStateScript.new()
	if not _expect(market_restored.load_snapshot(part_market_snapshot), "market snapshot load failed"):
		return
	var market_restored_report: Dictionary = market_restored.get_market_report()
	if not _expect(int(market_restored_report["part_sold"]) == 1, "market snapshot part sold mismatch"):
		return
	if not _expect(int(market_restored_report["revenue"]) == part_bid, "market snapshot revenue mismatch"):
		return

	print("FACTORYOPS_BUILDING_STATE_SMOKE_OK")
	get_tree().quit(0)

func _expect(condition: bool, message: String) -> bool:
	if condition:
		return true
	push_error("FACTORYOPS_BUILDING_STATE_SMOKE_FAIL:" + message)
	get_tree().quit(1)
	return false

func _generator_cell_for(target_cell: Vector2i) -> Vector2i:
	if target_cell.y + 1 < Config.GRID_ROWS:
		return target_cell + Vector2i.DOWN
	return target_cell + Vector2i.UP

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

func _snapshot_persists_powered(snapshot: Dictionary) -> bool:
	for raw_building in snapshot.get("buildings", []):
		if typeof(raw_building) == TYPE_DICTIONARY and Dictionary(raw_building).has("powered"):
			return true
	return false

func _as_array(value: Variant) -> Array:
	if typeof(value) != TYPE_ARRAY:
		return []
	return value

func _test_part(quality: float) -> Dictionary:
	return {
		"type": Config.ITEM_PART,
		"tier": Config.DEFAULT_ITEM_TIER,
		"quality": quality,
		"premium": quality >= Config.PREMIUM_THRESHOLD,
	}

func _test_ore() -> Dictionary:
	return {
		"type": Config.ITEM_ORE,
		"tier": Config.DEFAULT_ITEM_TIER,
		"quality": Config.DEFAULT_ITEM_QUALITY,
		"premium": false,
	}

func _shop_has_part(state, quality: float, premium: bool) -> bool:
	for item in state.get_shop_inventory():
		var part: Dictionary = item
		if bool(part.get("premium", false)) != premium:
			continue
		if absf(float(part.get("quality", 0.0)) - quality) <= 0.001:
			return true
	return false
