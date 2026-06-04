class_name BootstrapConfig
extends RefCounted

const VIEWPORT_SIZE := Vector2i(1280, 720)

const GRID_COLUMNS := 24
const GRID_ROWS := 14
const CELL_SIZE := 32
const GRID_ORIGIN := Vector2(80, 96)

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

const INITIAL_MONEY := 320
const BUILDING_REFUND_RATE := 0.45
const DIRECTION_COUNT := 4

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
	match posmod(dir, DIRECTION_COUNT):
		0:
			return Vector2.RIGHT
		1:
			return Vector2.DOWN
		2:
			return Vector2.LEFT
		_:
			return Vector2.UP
