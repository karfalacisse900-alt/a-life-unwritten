extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var market := MarketSystem.new()
	var state := LifeGameState.new(8821)
	var economy := EconomySystem.new()
	state.cash = 2500
	_check(market.load_errors.is_empty(), "Catalog validates")
	_check(int(market.parse_quantity("BTC", "0.00000001").get("quantity_units", 0)) == 1, "One satoshi parses exactly")
	_check(int(market.parse_quantity("SOL", "12.345678").get("quantity_units", 0)) == 12345678, "Six-decimal SOL parses exactly")
	_check(market.quantity_text("BTC", 1000001) == "0.01000001", "Eight-decimal BTC formats without rounding")
	for text in ["", "0", "-1", "1e3", "1,000", "0.000000001", "99999999999999999999"]:
		_check(not bool(market.parse_quantity("BTC", text).get("ok", false)), "Reject invalid BTC quantity: " + text)
	_check(not bool(market.parse_quantity("MCW", "1.1").get("ok", false)), "Shares require whole units")
	var amount := int(market.parse_quantity("BTC", "0.01").get("quantity_units", 0))
	var quote := market.quote_buy(state, "BTC", amount)
	_check(int(quote.get("notional_cents", 0)) == 68000, "0.01 BTC quote uses integer cents")
	var maximum := market.maximum_order_units(state, "BTC", "buy")
	_check(maximum > 0 and bool(market.can_buy(state, "BTC", maximum).get("ok", false)), "MAX is affordable including fees")
	_check(not bool(market.can_buy(state, "BTC", maximum + 1).get("ok", false)), "One unit above MAX is unaffordable")
	var wealthy := LifeGameState.new(9931)
	wealthy.cash = 1000000000
	market.buy(wealthy, "BTC", 1000000000000, economy)
	_check(bool(market.last_result.get("ok", false)), "Large precise quantity buys without overflow")
	var original_basis := int(market.get_holdings(wealthy)[0].get("cost_basis_cents", 0))
	var partial := market.quote_sell(wealthy, "BTC", 500000000000)
	_check(int(partial.get("estimated_cost_basis_cents", 0)) == original_basis / 2, "Large FIFO cost basis preserves cents without multiplication overflow")
	var ticket := TradeTicket.new()
	root.add_child(ticket)
	await process_frame
	ticket.open_order(state, market, economy, "BTC", "buy")
	_check(ticket.visible and ticket.amount is LineEdit, "Native trade amount field opens")
	_check(ticket.amount.virtual_keyboard_type == LineEdit.KEYBOARD_TYPE_NUMBER_DECIMAL, "Mobile numeric keyboard enabled")
	ticket._set_amount("0.000000001")
	_check(ticket.confirm.disabled, "Excess decimals disable confirmation")
	ticket._set_amount("1")
	_check(ticket.confirm.disabled, "Unaffordable full coin is blocked")
	ticket._set_amount("0.01")
	_check(not ticket.confirm.disabled, "Affordable fractional coin is enabled")
	var before_cash := state.cash
	ticket._submit()
	var ledger_count := state.ledger.size()
	ticket._submit()
	_check(not ticket.visible and state.ledger.size() == ledger_count, "Duplicate confirmation cannot submit twice")
	_check(int(market.get_holdings(state)[0].get("quantity_units", 0)) == amount, "Confirmed fraction becomes holding")
	_check(state.cash == before_cash - int(quote.get("cash_required_dollars", 0)), "Confirmed order matches cash preview")
	ticket.open_order(state, market, economy, "BTC", "sell")
	ticket._set_maximum()
	_check(ticket.quantity_units == amount, "Sell MAX equals exact fractional holding")
	ticket._submit()
	_check(market.get_holdings(state).is_empty(), "Fractional sell fully closes holding")
	var ledger_delta := 0
	for row in state.ledger: ledger_delta += int(row.get("amount", 0))
	_check(state.cash == 2500 + ledger_delta, "Custom order cash reconciles with ledger")
	ticket.free()
	var scene: PackedScene = load("res://main.tscn")
	var game := scene.instantiate()
	game.set("persistence_enabled", false)
	root.add_child(game)
	await process_frame
	game.call("_action", "new_game", null)
	var name_field: LineEdit = game.get("name_input")
	_check(name_field.visible and name_field.virtual_keyboard_enabled, "Character name uses a visible native mobile input")
	game.call("_action", "set_appearance", 6)
	_check(int(game.get("character_form").get("appearance", -1)) == 6, "Portrait selection supports direct touch choice")
	game.free()
	if failures.is_empty():
		print("TRADE_TICKET_PASS: precise fractions, invalid amounts, MAX, native input, quotes, ledger, custom buy/sell, duplicate guard")
		quit(0)
	else:
		for failure in failures: push_error(failure)
		quit(1)

func _check(condition: bool, message: String) -> void:
	if not condition: failures.append(message)
