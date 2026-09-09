class_name TradeTicket
extends Control

signal completed(result: String, success: bool)
signal cancelled

var market: MarketSystem
var state: LifeGameState
var economy: EconomySystem
var symbol := ""
var side := "buy"
var quantity_units := 0
var submitting := false
var amount: LineEdit
var heading: Label
var subtitle: Label
var amount_label: Label
var preview: Label
var validation: Label
var confirm: Button
var buy_button: Button
var sell_button: Button
var dialog: PanelContainer
var scroll: ScrollContainer
var presets: HBoxContainer

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	size = Vector2(540, 960)
	mouse_filter = Control.MOUSE_FILTER_STOP
	z_index = 100
	theme = Theme.new()
	theme.default_font = load("res://assets/fonts/DM-Sans.ttf")
	var shade := ColorRect.new()
	shade.color = Color(0.04, 0.08, 0.13, 0.7)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(shade)
	dialog = PanelContainer.new()
	dialog.position = Vector2(18, 96)
	dialog.size = Vector2(504, 704)
	dialog.add_theme_stylebox_override("panel", _box(Color("fbfaf7"), Color("d8d9d4"), 18))
	add_child(dialog)
	var margins := MarginContainer.new()
	for edge in ["left", "right", "top", "bottom"]: margins.add_theme_constant_override("margin_" + edge, 24)
	dialog.add_child(margins)
	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", 14)
	margins.add_child(layout)
	var top := HBoxContainer.new()
	layout.add_child(top)
	heading = _label("Order", 26, Color("172c29"))
	heading.add_theme_font_override("font", load("res://assets/fonts/LibreBaskerville.ttf"))
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	top.add_child(heading)
	var close := _button("×", _cancel, false)
	close.custom_minimum_size = Vector2(46, 44)
	close.size_flags_horizontal = Control.SIZE_SHRINK_END
	top.add_child(close)
	subtitle = _label("", 13, Color("66736f"))
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layout.add_child(subtitle)
	scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	layout.add_child(scroll)
	var content := VBoxContainer.new()
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content.add_theme_constant_override("separation", 14)
	scroll.add_child(content)
	var sides := HBoxContainer.new()
	sides.add_theme_constant_override("separation", 10)
	content.add_child(sides)
	buy_button = _button("BUY", func(): _set_side("buy"), true)
	sell_button = _button("SELL", func(): _set_side("sell"), false)
	sides.add_child(buy_button)
	sides.add_child(sell_button)
	amount_label = _label("Amount", 13, Color("42534e"))
	content.add_child(amount_label)
	amount = LineEdit.new()
	amount.custom_minimum_size = Vector2(0, 66)
	amount.placeholder_text = "0.00"
	amount.max_length = 24
	amount.virtual_keyboard_enabled = true
	amount.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER_DECIMAL
	amount.add_theme_font_size_override("font_size", 28)
	amount.add_theme_color_override("font_color", Color("172c29"))
	amount.add_theme_stylebox_override("normal", _box(Color.WHITE, Color("c5cdc6"), 8))
	amount.add_theme_stylebox_override("focus", _box(Color.WHITE, Color("267564"), 8))
	amount.text_changed.connect(func(_text): _refresh())
	# Enter dismisses the mobile keyboard. A distinct confirmation tap submits.
	amount.text_submitted.connect(func(_text): amount.release_focus())
	content.add_child(amount)
	presets = HBoxContainer.new()
	presets.add_theme_constant_override("separation", 8)
	content.add_child(presets)
	preview = _label("", 15, Color("203c33"))
	preview.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	preview.add_theme_constant_override("line_spacing", 9)
	content.add_child(preview)
	validation = _label("", 13, Color("ac403a"))
	validation.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	validation.custom_minimum_size.y = 18
	content.add_child(validation)
	var note := _label("Game prices • Orders fill at the displayed simulated quote. Brokerage change remains in your account.", 12, Color("6a7771"))
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(note)
	confirm = _button("CONFIRM BUY", _submit, true)
	confirm.custom_minimum_size.y = 54
	layout.add_child(confirm)
	hide()

func open_order(game_state: LifeGameState, market_system: MarketSystem, economy_system: EconomySystem, asset_symbol: String, order_side: String) -> void:
	state = game_state
	market = market_system
	economy = economy_system
	symbol = asset_symbol
	side = order_side
	submitting = false
	var definition := market.get_asset(symbol)
	heading.text = str(definition.get("name", symbol))
	amount_label.text = "Amount in %s" % symbol if int(definition.get("unit_scale", 1)) > 1 else "Number of shares"
	for child in presets.get_children():
		presets.remove_child(child)
		child.queue_free()
	var choices := ["0.01", "0.1", "1"] if int(definition.get("unit_scale", 1)) > 1 else ["1", "5", "10"]
	for value in choices:
		presets.add_child(_button(str(value), func(): _set_amount(str(value)), false))
	presets.add_child(_button("MAX", _set_maximum, false))
	amount.text = "0.01" if int(definition.get("unit_scale", 1)) > 1 else "1"
	scroll.scroll_vertical = 0
	show()
	_refresh()

func _process(_delta: float) -> void:
	if not visible or dialog == null: return
	# Keep the confirmation reachable above the mobile keyboard; content scrolls.
	var window_height := maxi(1, DisplayServer.window_get_size().y)
	var keyboard := 0.0
	if DisplayServer.has_feature(DisplayServer.FEATURE_VIRTUAL_KEYBOARD):
		keyboard = float(DisplayServer.virtual_keyboard_get_height()) * 960.0 / float(window_height)
	var available := maxf(430.0, 960.0 - keyboard - 36.0)
	dialog.position.y = 24.0 if keyboard > 0 else 96.0
	dialog.size.y = minf(704.0, available - dialog.position.y)

func _unhandled_key_input(event: InputEvent) -> void:
	if visible and event.is_action_pressed("ui_cancel"):
		_cancel()
		get_viewport().set_input_as_handled()

func _set_amount(value: String) -> void:
	amount.text = value
	amount.release_focus()
	_refresh()

func _set_maximum() -> void:
	_set_amount(market.quantity_text(symbol, market.maximum_order_units(state, symbol, side)))

func _set_side(value: String) -> void:
	side = value
	_refresh()

func _refresh() -> void:
	if market == null or confirm == null: return
	var buy := side == "buy"
	buy_button.add_theme_stylebox_override("normal", _box(Color("1f5747") if buy else Color("edf0eb"), Color("c9d2ca"), 8))
	buy_button.add_theme_color_override("font_color", Color.WHITE if buy else Color("244d3e"))
	sell_button.add_theme_stylebox_override("normal", _box(Color("1f5747") if not buy else Color("edf0eb"), Color("c9d2ca"), 8))
	sell_button.add_theme_color_override("font_color", Color.WHITE if not buy else Color("244d3e"))
	var parsed := market.parse_quantity(symbol, amount.text)
	quantity_units = int(parsed.get("quantity_units", 0))
	var quote := market.quote_buy(state, symbol, quantity_units) if buy else market.quote_sell(state, symbol, quantity_units)
	var base_quote := market.quote_buy(state, symbol, market.default_order_units(symbol))
	subtitle.text = "%s · %s per %s · Game quote" % [symbol, market.format_price(int(base_quote.get("price_cents", 0))), "coin" if market.default_order_units(symbol) > 1 else "share"]
	var held := 0
	for holding in market.get_holdings(state):
		if str(holding.get("symbol", "")) == symbol: held = int(holding.get("quantity_units", 0))
	var value := int(quote.get("notional_cents", 0)) if buy else int(quote.get("gross_cents", 0))
	var total := int(quote.get("total_cents", 0)) if buy else int(quote.get("net_proceeds_cents", 0))
	preview.text = "Order value     %s\nTrading fee      %s\n%s     %s\n\nAvailable cash  %s\nYou own          %s" % [market.format_price(value), market.format_price(int(quote.get("fee_cents", 0))), "Total cost" if buy else "You receive", market.format_price(total), market.format_price(int(state.cash) * 100), market.format_quantity(symbol, held)]
	var details := market.can_buy(state, symbol, quantity_units) if buy else market.can_sell(state, symbol, quantity_units)
	validation.text = str(parsed.get("reason", "")) if not bool(parsed.get("ok", false)) else str(details.get("reason", ""))
	confirm.disabled = submitting or not bool(parsed.get("ok", false)) or not bool(details.get("ok", false))
	confirm.text = "CONFIRM %s · %s" % [side.to_upper(), market.format_price(total)]

func _submit() -> void:
	if not visible or submitting: return
	_refresh()
	if confirm.disabled: return
	submitting = true
	confirm.disabled = true
	amount.release_focus()
	var result := market.buy(state, symbol, quantity_units, economy) if side == "buy" else market.sell(state, symbol, quantity_units, economy)
	var success := bool(market.last_result.get("ok", false))
	hide()
	completed.emit(result, success)

func _cancel() -> void:
	if submitting: return
	amount.release_focus()
	hide()
	cancelled.emit()

func _label(value: String, font_size: int, color: Color) -> Label:
	var node := Label.new()
	node.text = value
	node.add_theme_font_size_override("font_size", font_size)
	node.add_theme_color_override("font_color", color)
	return node

func _button(value: String, callback: Callable, primary: bool) -> Button:
	var node := Button.new()
	node.text = value
	node.custom_minimum_size = Vector2(64, 44)
	node.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	node.add_theme_font_size_override("font_size", 14)
	node.add_theme_color_override("font_color", Color.WHITE if primary else Color("244d3e"))
	node.add_theme_color_override("font_hover_color", Color.WHITE if primary else Color("244d3e"))
	node.add_theme_stylebox_override("normal", _box(Color("1f5747") if primary else Color("edf0eb"), Color("c9d2ca"), 8))
	node.add_theme_stylebox_override("hover", _box(Color("39755f") if primary else Color("dfe7df"), Color("9bafa0"), 8))
	node.add_theme_stylebox_override("pressed", _box(Color("174534"), Color("174534"), 8))
	node.add_theme_stylebox_override("disabled", _box(Color("d6ded8"), Color("d6ded8"), 8))
	node.pressed.connect(callback)
	return node

func _box(background: Color, border: Color, radius: int) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = background
	style.border_color = border
	style.set_border_width_all(1)
	style.set_corner_radius_all(radius)
	style.content_margin_left = 12
	style.content_margin_right = 12
	style.content_margin_top = 6
	style.content_margin_bottom = 6
	return style
