extends SceneTree

const StateClass = preload("res://scripts/core/LifeGameState.gd")
const CalendarClass = preload("res://scripts/systems/CalendarSystem.gd")
const EconomyClass = preload("res://scripts/systems/EconomySystem.gd")
const MarketClass = preload("res://scripts/systems/MarketSystem.gd")
const TravelClass = preload("res://scripts/systems/TravelSystem.gd")
const VehicleClass = preload("res://scripts/systems/VehicleFinanceSystem.gd")

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run_integration")


func _run_integration() -> void:
	var scene: PackedScene = load("res://main.tscn")
	_check(scene != null, "The main scene must load.")
	if scene == null:
		_finish()
		return

	var game: Node = scene.instantiate()
	game.set("persistence_enabled", false)
	root.add_child(game)
	await process_frame
	_check(str(game.get("screen_mode")) == "welcome", "A normal, QA-disabled launch should open the welcome screen.")

	# Exercise the same public action path used by mouse/touch input.
	game.call("_action", "new_game", null)
	_check(str(game.get("screen_mode")) == "create", "New Life should open character creation.")
	game.set("character_form", {
		"name": "Integration Vale",
		"pronouns": "they/them",
		"appearance": 4,
		"background": "fresh_start",
		"traits": ["resilient"],
	})
	game.call("_action", "finish_character", null)
	_check(str(game.get("screen_mode")) == "housing", "A valid character should continue to housing.")
	game.call("_action", "choose_housing", "family_home")

	var state: LifeGameState = game.get("state")
	var economy: EconomySystem = game.get("economy")
	var market: MarketSystem = game.get("market_system")
	var travel: TravelSystem = game.get("travel_system")
	var vehicles: VehicleFinanceSystem = game.get("vehicle_system")
	_check(bool(state.created) and str(state.housing_id) == "family_home", "Character setup should complete with the selected home.")
	_check(economy.is_realistic_finances_enabled(state), "Normal character setup should enable realistic finances.")
	var finance_profile := economy.get_financial_profile(state)
	_check(int(finance_profile.get("payroll", {}).get("cadence_weeks", 0)) == 2, "Normal payroll should be configured for a two-week cadence.")
	_check(str(finance_profile.get("transport_mode", "")) == "travel_managed", "TravelSystem should own commute costs and local payroll tax.")
	_check(travel.get_current_city_id(state) == "bellwether", "A normal new life should have a persistent starting city.")
	game.call("_action", "close_message", null)

	# Give the candidate an unambiguous interview score while retaining the normal
	# job application, schedule, payroll, tax, and commute paths.
	state.health = 95
	state.reputation = 90
	state.skills["practical"] = 80
	state.skills["fitness"] = 80
	state.skills["driving"] = 50
	game.call("_action", "apply_job", "warehouse_worker")
	_check(str(state.employment.get("job_id", "")) == "warehouse_worker", "The normal controller job application should hire an eligible candidate.")
	var weekly_gross := int(state.employment.get("weekly_pay", 0))
	_check(weekly_gross > 0, "The accepted job should expose its city-adjusted weekly gross wage.")
	game.call("_action", "close_message", null)

	# Initialize the same market snapshot for an observer with no trades. Prices
	# must later be identical even though only the player buys assets.
	market.get_market_list(state)
	var initial_prices: Dictionary = market.get_portfolio(state).get("prices_cents", {}).duplicate(true)
	var observer = StateClass.new(1)
	_check(observer.from_dict(state.to_dict()), "A pre-trade observer snapshot should deserialize.")
	var observer_market = MarketClass.new()
	var observer_calendar = CalendarClass.new()
	var observer_economy = EconomyClass.new()

	var cash_before_stock := state.cash
	var ledger_before_stock := state.ledger.size()
	game.call("_action", "buy_market", "MCW")
	var ticket: TradeTicket = game.get("trade_ticket")
	_check(ticket.visible and ticket.symbol == "MCW" and ticket.side == "buy", "Buy should open a native stock order ticket.")
	_check(state.cash == cash_before_stock and state.ledger.size() == ledger_before_stock and market.get_holdings(state).is_empty(), "Opening an order ticket must not spend cash or create a holding.")
	ticket._set_amount("1")
	_check(not ticket.confirm.disabled, "The one-share stock order should be confirmable.")
	ticket.confirm.pressed.emit()
	_check(not ticket.visible and bool(market.last_result.get("ok", false)), "Confirming the ticket should buy one fictional stock through the controller.")
	game.call("_action", "close_message", null)
	var cash_before_crypto := state.cash
	var ledger_before_crypto := state.ledger.size()
	game.call("_action", "buy_market", "TDB")
	_check(ticket.visible and ticket.symbol == "TDB" and ticket.side == "buy", "Buy should open a native crypto order ticket.")
	_check(state.cash == cash_before_crypto and state.ledger.size() == ledger_before_crypto, "Opening a crypto ticket must leave cash and ledger unchanged.")
	ticket._set_amount("1")
	_check(not ticket.confirm.disabled, "The one-coin crypto order should be confirmable.")
	ticket.confirm.pressed.emit()
	_check(not ticket.visible and bool(market.last_result.get("ok", false)), "Confirming the ticket should buy one fictional crypto coin through the controller.")
	game.call("_action", "close_message", null)
	_check(_holding_class_count(market.get_holdings(state), "stock") == 1, "The portfolio should retain the stock holding.")
	_check(_holding_class_count(market.get_holdings(state), "crypto") == 1, "The portfolio should retain the crypto holding.")
	_check(_category_count(state, "market_purchase") == 2, "Both market purchases should reconcile through the transaction ledger.")

	# Week one is the intentionally partial first pay period.
	var starting_week := int(state.calendar.get("week_index", 0))
	game.call("_action", "next_week", null)
	_check(int(state.calendar.get("week_index", 0)) == starting_week + 1, "Next Week should advance exactly one calendar week.")
	_check(str(game.get("overlay_mode")) == "summary", "A processed week should open its readable summary.")
	var first_pay_ledger_size := state.ledger.size()
	var first_pay_week := int(state.calendar.get("week_index", 0))
	_check(_category_count(state, "employment_income") == 1, "Week one should post the first partial paycheck once.")
	_check(_category_amounts(state, "employment_income") == [weekly_gross], "The first partial paycheck should contain exactly one earned week.")
	_check(_category_count(state, "paycheck_net") == 1, "The first partial check should record its net-deposit memo.")
	_check(_category_count(state, "federal_tax") == 1 and _category_count(state, "state_tax") == 1 and _category_count(state, "payroll_tax") == 1, "The first paycheck should have itemized federal, state, and payroll tax rows.")
	_check(_category_count(state, "city_tax") == 0, "EconomySystem must not duplicate city tax when TravelSystem owns it.")
	_check(_category_count(state, "local_income_tax") == 1 and _category_weeks(state, "local_income_tax") == [first_pay_week], "Travel local tax should post in the actual first pay week only.")

	# A second click while the summary is open must not process anything twice.
	game.call("_action", "next_week", null)
	_check(int(state.calendar.get("week_index", 0)) == first_pay_week and state.ledger.size() == first_pay_ledger_size, "Repeated Next Week input must not process the same week twice.")

	# The observer advances only its fictional market. Matching prices prove that
	# the player's stock/crypto orders do not steer the seeded weekly market.
	observer_calendar.advance_one_week(observer)
	observer_market.process_week(observer, observer_economy)
	var player_prices: Dictionary = market.get_portfolio(state).get("prices_cents", {})
	var observer_prices: Dictionary = observer_market.get_portfolio(observer).get("prices_cents", {})
	_check(player_prices == observer_prices, "Weekly stock and crypto prices should be independent of the player's trades and unrelated simulation RNG.")
	_check(market.get_price_history(state, "MCW").size() == 2 and market.get_price_history(state, "TDB").size() == 2, "Owned stock and crypto should each receive one weekly market close.")
	_check(int(player_prices.get("MCW", 0)) != int(initial_prices.get("MCW", 0)) or int(player_prices.get("TDB", 0)) != int(initial_prices.get("TDB", 0)), "At least one owned market instrument should move at the first simulated close.")
	_dismiss_week_ui(game)

	# Week two accrues wages but is deliberately not a payday.
	game.call("_action", "next_week", null)
	var second_week := int(state.calendar.get("week_index", 0))
	_check(second_week == first_pay_week + 1, "The second valid click should advance one more week.")
	_check(_category_count(state, "employment_income") == 1 and _category_count(state, "paycheck_net") == 1, "The off-pay week should accrue wages without depositing another check.")
	_check(_category_count(state, "local_income_tax") == 1 and _category_weeks(state, "local_income_tax") == [first_pay_week], "Travel must not invent local tax during the off-pay week.")
	_dismiss_week_ui(game)

	# Week three is the next real payday and contains two full earned weeks.
	game.call("_action", "next_week", null)
	var third_week := int(state.calendar.get("week_index", 0))
	_check(third_week == second_week + 1, "The third valid click should advance one more week.")
	_check(_category_count(state, "employment_income") == 2 and _category_count(state, "paycheck_net") == 2, "The regular biweekly payday should post exactly one additional check.")
	_check(_category_amounts(state, "employment_income") == [weekly_gross, weekly_gross * 2], "The regular check should contain exactly two earned weeks of gross salary.")
	_check(_category_count(state, "federal_tax") == 2 and _category_count(state, "state_tax") == 2 and _category_count(state, "payroll_tax") == 2, "Every deposited paycheck should retain its itemized taxes.")
	_check(_category_count(state, "local_income_tax") == 2 and _category_weeks(state, "local_income_tax") == [first_pay_week, third_week], "Travel local tax should exist on the two pay weeks and nowhere else.")

	# Real-world travel and relocation quotes must include route, housing, cash,
	# transport, and time instead of acting as free menu changes.
	var trip_quote := travel.trip_quote(state, "dunmarrow", "coach", true)
	_check(bool(trip_quote.get("eligible", false)) and int(trip_quote.get("total_cost", 0)) > 0 and int(trip_quote.get("time_hours", 0)) > 0, "A funded intercity visit should quote both money and weekly time.")
	var move_quote := travel.move_quote(state, "dunmarrow", "rented_room", "coach")
	_check(bool(move_quote.get("eligible", false)), "A funded worker should qualify for the quoted Dunmarrow room: %s" % str(move_quote.get("reason", "")))
	_check(int(move_quote.get("net_cash_needed", 0)) == int(move_quote.get("travel_cost", 0)) + int(move_quote.get("deposit", 0)) + int(move_quote.get("first_month_rent", 0)) + int(move_quote.get("moving_service", 0)) + int(move_quote.get("local_transport_setup", 0)) - int(move_quote.get("refundable_deposit", 0)), "The relocation quote should reconcile transport, deposit, first rent, movers, and local transit.")

	# Vehicle financing remains optional, but its normal quote/purchase path should
	# expose realistic due-today and monthly ownership costs and survive saving.
	var vehicle_quote := vehicles.quote_finance(state, "parkside_compact_2014")
	var vehicle_eligibility := vehicles.eligibility_details(state, "parkside_compact_2014", "finance")
	_check(bool(vehicle_quote.get("valid", false)) and int(vehicle_quote.get("due_today", 0)) > 0 and int(vehicle_quote.get("monthly_payment", 0)) > 0 and int(vehicle_quote.get("estimated_monthly_ownership", 0)) > int(vehicle_quote.get("monthly_payment", 0)), "A vehicle finance quote should disclose cash due, loan payment, insurance, fuel, and maintenance.")
	_check(bool(vehicle_eligibility.get("eligible", false)), "The employed, licensed player should qualify for the starter vehicle: %s" % str(vehicle_eligibility.get("reason", "")))
	game.call("_action", "finance_vehicle", "parkside_compact_2014")
	_check(bool(vehicles.last_result.get("ok", false)) and not vehicles.get_owned(state).is_empty(), "The eligible finance offer should create one owned vehicle.")
	_check(_category_count(state, "vehicle_down_payment") == 1 and vehicles.get_loan_balance(state) > 0, "Vehicle down payment and secured loan balance should be tracked separately.")

	var restored = StateClass.new(1)
	_check(restored.from_dict(state.to_dict()), "The full integrated state should deserialize through the versioned save contract.")
	_check(EconomyClass.new().is_realistic_finances_enabled(restored), "Realistic-finance configuration should survive save/load.")
	_check(TravelClass.new().get_current_city_id(restored) == travel.get_current_city_id(state), "Current city should survive save/load.")
	_check(MarketClass.new().get_holdings(restored).size() == market.get_holdings(state).size(), "Stock and crypto holdings should survive save/load.")
	_check(str(VehicleClass.new().get_owned(restored).get("vehicle_id", "")) == "parkside_compact_2014", "The financed vehicle and loan should survive save/load.")

	game.free()
	_finish()


func _dismiss_week_ui(game: Node) -> void:
	# Events have their own dedicated test suite. This integration keeps its focus
	# on exact week/pay-period sequencing while still using the normal week action.
	game.set("pending_event", {})
	game.set("overlay_mode", "")
	game.set("last_advance_msec", 0)


func _holding_class_count(holdings: Array, asset_class: String) -> int:
	var count := 0
	for holding in holdings:
		if holding is Dictionary and str(holding.get("asset_class", "")) == asset_class:
			count += 1
	return count


func _category_count(state, category: String) -> int:
	return _category_amounts(state, category).size()


func _category_amounts(state, category: String) -> Array[int]:
	var result: Array[int] = []
	for entry in state.ledger:
		if str(entry.get("category", "")) == category:
			result.append(int(entry.get("amount", 0)))
	return result


func _category_weeks(state, category: String) -> Array[int]:
	var result: Array[int] = []
	for entry in state.ledger:
		if str(entry.get("category", "")) == category:
			result.append(int(entry.get("week_index", -1)))
	return result


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)


func _finish() -> void:
	if failures.is_empty():
		print("REAL_LIFE_INTEGRATION_PASS: normal create/housing/job flow, biweekly partial/full payroll, itemized taxes, pay-week-only local tax, duplicate guard, independent stock/crypto market, travel/move quotes, vehicle finance, and save roundtrip")
		quit(0)
		return
	for failure in failures:
		push_error("REAL_LIFE_INTEGRATION_FAIL: %s" % failure)
	quit(1)
