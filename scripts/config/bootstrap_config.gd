class_name BootstrapConfig
extends RefCounted

const VIEWPORT_SIZE := Vector2i(1280, 720)
const SAVE_VERSION := 1
const SAVE_PATH := "user://factoryops_bootstrap_save.json"

const GRID_COLUMNS := 24
const GRID_ROWS := 14
const CELL_SIZE := 32
const GRID_ORIGIN := Vector2(80, 96)
const SHOP_ORIGIN := GRID_ORIGIN
const SHOP_SIZE := Vector2(GRID_COLUMNS * CELL_SIZE, GRID_ROWS * CELL_SIZE)

const COLOR_BACKGROUND := Color(0.047, 0.059, 0.075, 1.0)
const COLOR_BACKGROUND_PANEL := Color(0.066, 0.086, 0.105, 1.0)
const COLOR_GRID_FILL_A := Color(0.086, 0.112, 0.137, 1.0)
const COLOR_GRID_FILL_B := Color(0.074, 0.098, 0.121, 1.0)
const COLOR_GRID_LINE := Color(0.184, 0.239, 0.286, 1.0)
const COLOR_HOVER := Color(0.208, 0.690, 0.816, 0.35)
const COLOR_SELECTED := Color(0.929, 0.631, 0.235, 0.55)
const COLOR_SELECTED_BORDER := Color(1.0, 0.761, 0.333, 1.0)
const COLOR_TOOL_DISABLED := Color(0.475, 0.514, 0.553, 1.0)
const COLOR_BUILDING_BORDER := Color(0.855, 0.894, 0.925, 0.74)
const COLOR_TEXT := Color(0.914, 0.941, 0.965, 1.0)
const COLOR_TEXT_MUTED := Color(0.651, 0.702, 0.753, 1.0)
const COLOR_ORE_FILL := Color(0.780, 0.478, 0.243, 0.24)
const COLOR_ORE_DOT := Color(0.780, 0.478, 0.243, 1.0)
const COLOR_ORE_GLOW := Color(0.957, 0.714, 0.302, 0.38)
const COLOR_UNPOWERED := Color(0.984, 0.251, 0.337, 1.0)
const COLOR_UNPOWERED_FILL := Color(0.984, 0.251, 0.337, 0.22)
const COLOR_SHOP_FLOOR := Color(0.095, 0.137, 0.188, 1.0)
const COLOR_SHOP_WALL := Color(0.149, 0.208, 0.271, 1.0)
const COLOR_SHOP_SHELF := Color(0.525, 0.361, 0.247, 1.0)
const COLOR_SHOP_COUNTER := Color(0.184, 0.451, 0.420, 1.0)

const INITIAL_MONEY := 320
const BUILDING_REFUND_RATE := 0.45
const DIRECTION_COUNT := 4
const ORE_BASE_AMOUNT := 800
const ORE_AMOUNT_VARIANCE := 420
const MINER_INTERVAL := 1.18
const INSERTER_SPEED := 1.7
const ASSEMBLER_BUILD_TIME := 2.15
const ASSEMBLER_INPUT_PER_PART := 2
const ASSEMBLER_OUTPUT_CAP := 5
const ASSEMBLER_INPUT_CAP := 8
const ASSEMBLER_TIMER_DECAY := 0.5
const ITEM_SPEED := 2.65
const ITEM_MAX_AGE := 35.0
const ITEM_CAP := 220
const BELT_CELL_ITEM_CAP := 4
const BELT_INSERT_PROGRESS := 0.12
const BLOCKED_ITEM_PROGRESS := 0.98
const SIMULATION_DT_CLAMP := 0.25
const RATE_WINDOW_SECONDS := 60.0
const POWER_GENERATOR_OUTPUT := 90
const POWER_GENERATOR_RADIUS := 7
const POWER_USAGE_MINER := 10
const POWER_USAGE_ASSEMBLER := 18
const POWER_USAGE_INSERTER := 4
const COLOR_ITEM_ORE := Color(0.957, 0.714, 0.302, 1.0)
const COLOR_ITEM_PART := Color(0.322, 0.722, 0.910, 1.0)
const COLOR_ITEM_PREMIUM := Color(0.537, 0.918, 0.643, 1.0)
const PREMIUM_THRESHOLD := 1.22
const BASE_QUALITY_MU := 1.0
const BASE_QUALITY_SIGMA := 0.18
const MIN_QUALITY := 0.65
const MAX_QUALITY := 2.4
const DEFAULT_ITEM_TIER := 1
const DEFAULT_ITEM_QUALITY := 1.0
const SHOP_INITIAL_PRICE := 12
const SHOP_MIN_PRICE := 4
const SHOP_MAX_PRICE := 40
const SHOP_PRICE_STEP := 1
const SHOP_INITIAL_REPUTATION := 50.0
const SHOP_DEMAND_PRICE_ANCHOR := 18.0
const SHOP_DEMAND_PRICE_MIN := 0.35
const SHOP_DEMAND_PRICE_MAX := 1.65
const SHOP_DEMAND_REPUTATION_MIN := 0.45
const SHOP_DEMAND_REPUTATION_MAX := 1.7
const SHOP_EMPTY_STOCK_DEMAND_FACTOR := 0.35
const SHOP_CUSTOMER_CAPACITY := 6
const SHOP_CUSTOMER_INITIAL_SPAWN := 1.4
const SHOP_CUSTOMER_SPAWN_MIN := 2.4
const SHOP_CUSTOMER_SPAWN_VARIANCE := 2.8
const SHOP_CUSTOMER_SPEED := 0.18
const SHOP_CUSTOMER_TARGET_EPSILON := 0.002
const SHOP_CUSTOMER_BUDGET_BASE := 9
const SHOP_CUSTOMER_BUDGET_RANGE := 14
const SHOP_CUSTOMER_BUDGET_REPUTATION_DIVISOR := 18.0
const SHOP_CUSTOMER_WAIT_MIN := 1.1
const SHOP_CUSTOMER_WAIT_VARIANCE := 1.2
const SHOP_REPUTATION_STOCKOUT_PENALTY := 1.4
const SHOP_REPUTATION_PRICE_PENALTY := 0.9
const SHOP_REPUTATION_SALE_GAIN := 0.45
const MARKET_BID_FACTOR := 0.7
const MARKET_ASK_FACTOR := 1.5
const MARKET_COST_ORE := 1
const MARKET_COST_PART := 4
const MARKET_INITIAL_TIMER := 0.0
const MARKET_TIMER_MIN := 3.5
const MARKET_TIMER_VARIANCE := 2.5
const MARKET_ORE_DEMAND_MIN := 0.45
const MARKET_ORE_DEMAND_MAX := 1.85
const MARKET_ORE_VOLATILITY := 0.18
const MARKET_PART_DEMAND_MIN := 0.55
const MARKET_PART_DEMAND_MAX := 2.2
const MARKET_PART_VOLATILITY := 0.22
const MARKET_PRESSURE_DECAY_ORE := 0.035
const MARKET_PRESSURE_DECAY_PART := 0.025
const MARKET_SELL_PRESSURE_ORE := 0.018
const MARKET_SELL_PRESSURE_PART := 0.035
const COLOR_CUSTOMER_A := Color(0.463, 0.847, 1.0, 1.0)
const COLOR_CUSTOMER_B := Color(0.957, 0.714, 0.302, 1.0)
const COLOR_CUSTOMER_C := Color(1.0, 0.561, 0.639, 1.0)
const COLOR_CUSTOMER_BOUGHT := Color(0.537, 0.918, 0.643, 1.0)

const ITEM_ORE := "ore"
const ITEM_PART := "part"

const MODE_FACTORY := "factory"
const MODE_SHOP := "shop"
const CUSTOMER_ENTERING := "entering"
const CUSTOMER_SHOPPING := "shopping"
const CUSTOMER_CHECKOUT := "checkout"
const CUSTOMER_LEAVING := "leaving"

const TOOL_BELT := "belt"
const TOOL_INSERTER := "inserter"
const TOOL_MINER := "miner"
const TOOL_ASSEMBLER := "assembler"
const TOOL_STORAGE := "storage"
const TOOL_GENERATOR := "generator"
const TOOL_ERASE := "erase"

static func is_known_tool(tool: String) -> bool:
	return (
		tool == TOOL_BELT
		or tool == TOOL_INSERTER
		or tool == TOOL_MINER
		or tool == TOOL_ASSEMBLER
		or tool == TOOL_STORAGE
		or tool == TOOL_GENERATOR
		or tool == TOOL_ERASE
	)

static func is_known_mode(next_mode: String) -> bool:
	return next_mode == MODE_FACTORY or next_mode == MODE_SHOP

static func customer_color(index: int, bought: bool) -> Color:
	if bought:
		return COLOR_CUSTOMER_BOUGHT
	match posmod(index, 3):
		0:
			return COLOR_CUSTOMER_A
		1:
			return COLOR_CUSTOMER_B
		_:
			return COLOR_CUSTOMER_C

static func production_cost(item_type: String, tier := DEFAULT_ITEM_TIER) -> int:
	var base_cost := MARKET_COST_ORE
	if item_type == ITEM_PART:
		base_cost = MARKET_COST_PART
	return int(base_cost * pow(2.0, float(max(0, tier - 1))))

static func market_bid(cost: int) -> int:
	return max(1, int(floor(float(cost) * MARKET_BID_FACTOR)))

static func market_ask(cost: int) -> int:
	var bid := market_bid(cost)
	return max(bid + 1, int(ceil(float(cost) * MARKET_ASK_FACTOR)))

static func market_item_label(item_type: String) -> String:
	match item_type:
		ITEM_PART:
			return "Peca"
		ITEM_ORE:
			return "Minerio"
		_:
			return "Item"

static func is_directional_tool(tool: String) -> bool:
	return (
		tool == TOOL_BELT
		or tool == TOOL_INSERTER
		or tool == TOOL_MINER
		or tool == TOOL_ASSEMBLER
	)

static func tool_cost(tool: String) -> int:
	match tool:
		TOOL_BELT:
			return 4
		TOOL_INSERTER:
			return 16
		TOOL_MINER:
			return 26
		TOOL_ASSEMBLER:
			return 46
		TOOL_STORAGE:
			return 24
		TOOL_GENERATOR:
			return 60
		_:
			return 0

static func power_need(tool: String) -> int:
	match tool:
		TOOL_MINER:
			return POWER_USAGE_MINER
		TOOL_ASSEMBLER:
			return POWER_USAGE_ASSEMBLER
		TOOL_INSERTER:
			return POWER_USAGE_INSERTER
		_:
			return 0

static func tool_refund(tool: String) -> int:
	return int(floor(float(tool_cost(tool)) * BUILDING_REFUND_RATE))

static func tool_color(tool: String) -> Color:
	match tool:
		TOOL_BELT:
			return Color(0.212, 0.255, 0.314, 1.0)
		TOOL_INSERTER:
			return Color(0.620, 0.451, 0.847, 1.0)
		TOOL_MINER:
			return Color(0.659, 0.404, 0.271, 1.0)
		TOOL_ASSEMBLER:
			return Color(0.204, 0.412, 0.510, 1.0)
		TOOL_STORAGE:
			return Color(0.153, 0.490, 0.412, 1.0)
		TOOL_GENERATOR:
			return Color(0.753, 0.612, 0.212, 1.0)
		TOOL_ERASE:
			return Color(0.875, 0.290, 0.349, 1.0)
		_:
			return COLOR_TOOL_DISABLED

static func tool_label(tool: String) -> String:
	match tool:
		TOOL_BELT:
			return "Esteira"
		TOOL_INSERTER:
			return "Braco"
		TOOL_MINER:
			return "Minerador"
		TOOL_ASSEMBLER:
			return "Montador"
		TOOL_STORAGE:
			return "Armazem"
		TOOL_GENERATOR:
			return "Gerador"
		TOOL_ERASE:
			return "Remover"
		_:
			return "Desconhecido"

static func tool_mark(tool: String) -> String:
	match tool:
		TOOL_BELT:
			return ">"
		TOOL_INSERTER:
			return "I"
		TOOL_MINER:
			return "M"
		TOOL_ASSEMBLER:
			return "A"
		TOOL_STORAGE:
			return "S"
		TOOL_GENERATOR:
			return "G"
		TOOL_ERASE:
			return "X"
		_:
			return "?"

static func direction_vector(dir: int) -> Vector2:
	return Vector2(direction_offset(dir))

static func direction_offset(dir: int) -> Vector2i:
	match posmod(dir, DIRECTION_COUNT):
		0:
			return Vector2i.RIGHT
		1:
			return Vector2i.DOWN
		2:
			return Vector2i.LEFT
		_:
			return Vector2i.UP

static func ore_patch_specs() -> Array:
	return [
		{"center": Vector2(0.22, 0.24), "radius": Vector2i(4, 6)},
		{"center": Vector2(0.76, 0.66), "radius": Vector2i(4, 5)},
		{"center": Vector2(0.35, 0.78), "radius": Vector2i(3, 4)},
	]
