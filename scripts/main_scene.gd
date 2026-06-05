class_name MainScene
extends Node2D

const Config := preload("res://scripts/config/bootstrap_config.gd")
const FactoryStateScript := preload("res://scripts/factory/factory_state.gd")
const ShopViewScript := preload("res://scripts/shop_view.gd")

@onready var camera: Camera2D = $Camera2D
@onready var grid_view: Node2D = $GridView

var factory_state = null
var shop_view: Node2D
var hud_label: Label
var last_action := "Pronto."

func _ready() -> void:
	factory_state = FactoryStateScript.new()

	camera.position = Vector2(Config.VIEWPORT_SIZE) * 0.5
	camera.make_current()
	grid_view.position = Config.GRID_ORIGIN
	grid_view.call("set_factory_state", factory_state)
	grid_view.connect("cell_clicked", Callable(self, "_on_grid_cell_clicked"))
	shop_view = ShopViewScript.new()
	shop_view.name = "ShopView"
	shop_view.position = Config.SHOP_ORIGIN
	shop_view.call("set_factory_state", factory_state)
	add_child(shop_view)
	factory_state.connect("changed", Callable(self, "_on_factory_state_changed"))
	_create_hud()
	_sync_mode_view()
	_update_hud()

	if OS.is_debug_build():
		print("FACTORYOPS_MAIN_SCENE_READY")

func _process(delta: float) -> void:
	if factory_state != null:
		factory_state.tick(delta)

func _unhandled_input(event: InputEvent) -> void:
	if event is not InputEventKey:
		return

	var key_event := event as InputEventKey
	if not key_event.pressed or key_event.echo:
		return

	if key_event.keycode == KEY_F5:
		var saved: bool = factory_state.save_to_disk()
		last_action = "Jogo salvo." if saved else "Falha ao salvar."
		_update_hud()
		print("FACTORYOPS_SAVE:%s" % ["ok" if saved else "fail"])
		return

	if key_event.keycode == KEY_F9:
		var loaded: bool = factory_state.load_from_disk()
		last_action = "Jogo carregado." if loaded else "Save nao encontrado."
		_sync_mode_view()
		_update_hud()
		grid_view.queue_redraw()
		shop_view.queue_redraw()
		print("FACTORYOPS_LOAD:%s" % ["ok" if loaded else "miss"])
		return

	if key_event.keycode == KEY_TAB:
		factory_state.toggle_mode()
		last_action = "Loja aberta." if factory_state.mode == Config.MODE_SHOP else "Fabrica aberta."
		_sync_mode_view()
		_update_hud()
		queue_redraw()
		return

	var next_tool := _tool_from_key(key_event.keycode)
	if next_tool != "":
		factory_state.select_tool(next_tool)
		last_action = "%s selecionado." % Config.tool_label(next_tool)
		_update_hud()
		return

	if key_event.keycode == KEY_R or key_event.keycode == KEY_E:
		factory_state.rotate_selection()
		last_action = "Direcao alterada."
		_update_hud()

func _on_grid_cell_clicked(cell: Vector2i) -> void:
	var result: Dictionary = factory_state.try_apply_tool(cell)
	last_action = "%s (%d,%d)" % [String(result["message"]), cell.x, cell.y]
	grid_view.queue_redraw()
	_update_hud()
	print(
		"FACTORYOPS_BUILD_ACTION:%s:%d,%d:money=%d:delta=%d" %
		[String(result["action"]), cell.x, cell.y, int(result["money"]), int(result["money_delta"])]
	)

func _on_factory_state_changed() -> void:
	_sync_mode_view()
	grid_view.queue_redraw()
	shop_view.queue_redraw()
	queue_redraw()
	_update_hud()

func _create_hud() -> void:
	var hud_layer := CanvasLayer.new()
	hud_layer.name = "HUD"
	add_child(hud_layer)

	hud_label = Label.new()
	hud_label.name = "Status"
	hud_label.position = Vector2(24.0, 18.0)
	hud_label.add_theme_color_override("font_color", Config.COLOR_TEXT)
	hud_label.add_theme_color_override("font_shadow_color", Color(0.0, 0.0, 0.0, 0.75))
	hud_label.add_theme_constant_override("shadow_offset_x", 1)
	hud_label.add_theme_constant_override("shadow_offset_y", 1)
	hud_label.size = Vector2(1232.0, 80.0)
	hud_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hud_layer.add_child(hud_label)

func _update_hud() -> void:
	if hud_label == null:
		return

	var selected_tool := String(factory_state.selected_tool)
	if factory_state.mode == Config.MODE_SHOP:
		var report: Dictionary = factory_state.get_shop_report()
		hud_label.text = "Modo: Loja   Creditos: %d   Estoque: %d   Base/Prem: %d/%d   Qualidade: %.2f   Melhor: %.2f   Preco: $%d\nDemanda: %s   Reputacao: %d   Receita: %d   Vendas: %d   Gargalo: %s   %s" % [
			int(factory_state.money),
			int(report["stock"]),
			int(report["base_stock"]),
			int(report["premium_stock"]),
			float(report["average_quality"]),
			float(report["best_quality"]),
			int(report["price"]),
			String(report["demand_label"]),
			int(round(float(report["reputation"]))),
			int(report["revenue"]),
			int(report["sales"]),
			String(report["bottleneck"]),
			last_action,
		]
		return

	hud_label.text = "Modo: Fabrica   Creditos: %d   Pecas: %d   Loja: %d   Itens: %d   Energia: %d/%d   Taxa: %d/min   Ferramenta: %s $%d   %s" % [
		int(factory_state.money),
		int(factory_state.parts),
		factory_state.get_shop_stock(),
		factory_state.get_items().size(),
		int(factory_state.power_used),
		int(factory_state.power_capacity),
		factory_state.get_parts_per_minute(),
		Config.tool_label(selected_tool),
		Config.tool_cost(selected_tool),
		last_action,
	]

func _sync_mode_view() -> void:
	var show_shop: bool = factory_state != null and factory_state.mode == Config.MODE_SHOP
	grid_view.visible = not show_shop
	if shop_view != null:
		shop_view.visible = show_shop

func _tool_from_key(keycode: Key) -> String:
	match keycode:
		KEY_1:
			return Config.TOOL_BELT
		KEY_2:
			return Config.TOOL_INSERTER
		KEY_3:
			return Config.TOOL_MINER
		KEY_4:
			return Config.TOOL_ASSEMBLER
		KEY_5:
			return Config.TOOL_STORAGE
		KEY_6:
			return Config.TOOL_GENERATOR
		KEY_7, KEY_X, KEY_DELETE:
			return Config.TOOL_ERASE
		_:
			return ""

func _draw() -> void:
	var viewport_size := Vector2(Config.VIEWPORT_SIZE)
	var grid_size := Vector2(
		Config.GRID_COLUMNS * Config.CELL_SIZE,
		Config.GRID_ROWS * Config.CELL_SIZE
	)
	var board_padding := 16.0
	var board_rect := Rect2(
		Config.GRID_ORIGIN - Vector2.ONE * board_padding,
		grid_size + Vector2.ONE * board_padding * 2.0
	)

	draw_rect(Rect2(Vector2.ZERO, viewport_size), Config.COLOR_BACKGROUND)
	draw_rect(board_rect, Config.COLOR_BACKGROUND_PANEL)
