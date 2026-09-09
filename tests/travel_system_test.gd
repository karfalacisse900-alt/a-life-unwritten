extends SceneTree

const StateClass = preload("res://scripts/core/LifeGameState.gd")
const CalendarClass = preload("res://scripts/systems/CalendarSystem.gd")
const EconomyClass = preload("res://scripts/systems/EconomySystem.gd")
const AssetClass = preload("res://scripts/systems/AssetSystem.gd")
const TravelClass = preload("res://scripts/systems/TravelSystem.gd")

var failures: Array[String] = []


func _initialize() -> void:
	_test_catalog_and_quotes()
	_test_trip_execution()
	_test_relocation_and_save()
	_test_payroll_tax_commute_and_idempotence()
	_test_upcoming_biweekly_tax()
	_test_city_housing_adjustment()
	_test_owned_car_transport()
	if failures.is_empty():
		print("TRAVEL_SYSTEM_TEST_PASS: six cities, route quotes, relocation, housing, transit, commute, tax, ledger, idempotence, and save compatibility")
		quit(0)
		return
	for failure in failures:
		push_error("TRAVEL_TEST_FAIL: %s" % failure)
	quit(1)


func _test_catalog_and_quotes() -> void:
	var state = StateClass.new(8101)
	var travel = TravelClass.new()
	_check(travel.load_errors.is_empty(), "City content must load and validate: %s" % " ".join(travel.load_errors))
	_check(travel.get_cities(state).size() >= 5, "At least five fictional cities should load.")
	_check(travel.get_current_city_id(state) == "bellwether", "A new state should start in Bellwether.")
	var virelia := travel.get_city_financial_profile("virelia")
	var dunmarrow := travel.get_city_financial_profile("dunmarrow")
	_check(int(virelia.get("rent_index_basis_points", 0)) > int(dunmarrow.get("rent_index_basis_points", 0)), "Virelia should be meaningfully more expensive than Dunmarrow.")
	_check(travel.get_job_market_factor("virelia") > travel.get_job_market_factor("dunmarrow"), "City job-market factors must differ.")
	_check(travel.adjusted_salary("virelia", 1000) == 1280, "Salary multiplier should produce an exact integer quote.")
	state.cash = 5000
	var rail := travel.trip_quote(state, "virelia", "rail", true)
	_check(bool(rail.get("eligible", false)), "A funded player should be able to quote a Bellwether–Virelia round trip by rail: %s" % str(rail.get("reason", "")))
	_check(int(rail.get("distance_km", 0)) == 410 and int(rail.get("total_distance_km", 0)) == 820, "Round-trip distance should contain exactly two route legs.")
	_check(int(rail.get("total_cost", 0)) > 0 and int(rail.get("time_hours", 0)) > 0, "Trip quote should include price and weekly time.")
	var car := travel.trip_quote(state, "virelia", "own_car", true)
	_check(not bool(car.get("eligible", true)) and str(car.get("reason", "")).contains("working car"), "Driving intercity should be blocked until the player owns a car.")
	state.flags["vehicle_finance"] = {"current": {"vehicle_id": "wayline_compact", "operational": true, "condition_score": 82}}
	car = travel.trip_quote(state, "virelia", "own_car", true)
	_check(bool(car.get("eligible", false)), "A working VehicleFinanceSystem car should unlock intercity driving.")
	state.flags["vehicle_finance"] = {"current": {"vehicle_id": "wayline_compact", "operational": false, "condition_score": 82}}
	car = travel.trip_quote(state, "virelia", "own_car", true)
	_check(not bool(car.get("eligible", true)), "A broken financed vehicle must not satisfy the working-car requirement.")
	var unavailable_flight := travel.trip_quote(state, "dunmarrow", "flight", true)
	_check(not bool(unavailable_flight.get("eligible", true)), "A city without an airport should not offer a flight.")


func _test_trip_execution() -> void:
	var state = StateClass.new(8202)
	var travel = TravelClass.new()
	var economy = EconomyClass.new()
	state.cash = 3000
	var quote := travel.trip_quote(state, "dunmarrow", "coach", true)
	var cash_before: int = state.cash
	var time_before: int = state.weekly_time
	var result := travel.travel(state, "dunmarrow", "coach", economy, true)
	_check(bool(travel.last_result.get("ok", false)), "A valid coach visit should complete: %s" % result)
	_check(state.cash == cash_before - int(quote.get("total_cost", 0)), "Trip cost must match the quote exactly.")
	_check(state.weekly_time == time_before - int(quote.get("time_hours", 0)), "Trip must consume the quoted weekly time exactly.")
	_check(_ledger_category_count(state, "intercity_travel") == 1, "A trip should produce one reasoned travel ledger row.")
	_check(travel.get_current_city_id(state) == "bellwether", "A visit should not silently relocate the player's home.")
	_check((state.flags.get("travel", {}) as Dictionary).get("trip_history", []).size() == 1, "Completed trips should be retained in save-compatible history.")


func _test_relocation_and_save() -> void:
	var state = StateClass.new(8303)
	var travel = TravelClass.new()
	var economy = EconomyClass.new()
	state.cash = 12000
	state.housing_id = "rented_room"
	state.flags["housing_deposits"] = {"rented_room": 500}
	var quote := travel.move_quote(state, "dunmarrow", "rented_room", "coach")
	_check(bool(quote.get("eligible", false)), "A funded player should qualify for a room in Dunmarrow: %s" % str(quote.get("reason", "")))
	var expected_components := int(quote.get("travel_cost", 0)) + int(quote.get("deposit", 0)) + int(quote.get("first_month_rent", 0)) + int(quote.get("moving_service", 0)) + int(quote.get("local_transport_setup", 0))
	_check(int(quote.get("gross_move_in_total", -1)) == expected_components, "Move quote must include transport, deposit, first rent, movers, and destination transport.")
	_check(int(quote.get("net_cash_needed", -1)) == expected_components - 500, "The old held deposit should reduce net move-in cash.")
	var cash_before: int = state.cash
	var moved := travel.relocate(state, "dunmarrow", "rented_room", "coach", economy)
	_check(bool(travel.last_result.get("ok", false)), "Qualified relocation should complete: %s" % moved)
	_check(travel.get_current_city_id(state) == "dunmarrow" and state.housing_id == "rented_room", "Relocation should update both city and stable housing id.")
	_check(state.cash == cash_before - int(quote.get("net_cash_needed", 0)), "Relocation ledger must reconcile to the net quote.")
	_check(_ledger_category_count(state, "housing_deposit_refund") == 1 and _ledger_category_count(state, "housing_deposit") == 1, "Relocation should refund the old deposit and hold the new one.")
	_check(_ledger_category_count(state, "housing_rent_prepaid") == 1 and _ledger_category_count(state, "relocation_transport") == 1, "First rent and one-way transport should have distinct ledger reasons.")
	var contract := travel.get_current_housing_contract(state)
	_check(int(contract.get("monthly_rent", 0)) == 490 and int(contract.get("monthly_utilities", 0)) == 95, "Destination lease should preserve its local rent and utilities.")
	var restored = StateClass.new(1)
	_check(restored.from_dict(state.to_dict()), "A relocated state should deserialize.")
	var restored_travel = TravelClass.new()
	_check(restored_travel.get_current_city_id(restored) == "dunmarrow", "Current city must survive the existing save contract through flags.")
	_check(restored_travel.get_current_housing_contract(restored) == contract, "Full city housing contract must survive save/load.")


func _test_payroll_tax_commute_and_idempotence() -> void:
	var state = StateClass.new(8404)
	var travel = TravelClass.new()
	var economy = EconomyClass.new()
	var calendar = CalendarClass.new()
	state.cash = 2000
	state.housing_id = "family_home"
	state.employment = {"job_id": "office_assistant", "title": "Office Assistant", "weekly_pay": 1000, "active": true, "suspended": false}
	# Initialize travel at week zero so the first processed turn is week one.
	travel.get_current_city(state)
	calendar.advance_one_week(state)
	# This represents a biweekly gross paycheck paid during this exact turn.
	economy.record(state, 2000, "Biweekly paycheck — Office Assistant", "employment_income")
	var cash_before: int = state.cash
	var time_before: int = state.weekly_time
	var summary := travel.process_week(state, economy)
	_check(_ledger_category_count(state, "local_income_tax") == 1, "One local tax row should be recorded when a paycheck actually arrives.")
	_check(_ledger_category_amount(state, "local_income_tax") == -54, "Bellwether's 2.70% local tax on $2,000 gross should be $54.")
	_check(_ledger_category_count(state, "work_commute") == 1 and _ledger_category_amount(state, "work_commute") == -24, "Default pay-as-you-go commute should cost $24 for the work week.")
	_check(state.cash == cash_before - 78, "Tax and commute charges should reconcile exactly.")
	_check(state.weekly_time <= time_before - 5, "A work commute must consume its stated weekly travel time.")
	_check(not summary.is_empty(), "Weekly processing should explain tax and commuting costs.")
	var ledger_size: int = state.ledger.size()
	var cash_after: int = state.cash
	travel.process_week(state, economy)
	_check(state.ledger.size() == ledger_size and state.cash == cash_after, "Repeated processing of the same week must not duplicate tax or commute charges.")

	calendar.advance_one_week(state)
	travel.process_week(state, economy)
	_check(_ledger_category_count(state, "local_income_tax") == 1, "No local income tax should be invented during an unpaid week.")
	_check(_ledger_category_count(state, "work_commute") == 2, "An employed player still incurs the next week's commute cost.")


func _test_city_housing_adjustment() -> void:
	var state = StateClass.new(8505)
	var travel = TravelClass.new()
	var economy = EconomyClass.new()
	var calendar = CalendarClass.new()
	state.cash = 15000
	var moved := travel.relocate(state, "dunmarrow", "rented_room", "coach", economy)
	_check(bool(travel.last_result.get("ok", false)), "Test setup relocation should succeed: %s" % moved)
	state.ledger.clear()
	state.flags["ledger_sequence"] = 0
	state.cash = 5000
	state.calendar = {"year": 2026, "month": 1, "day": 26, "week": 4, "week_index": 0}
	state.flags["last_economy_week_index"] = 0
	var travel_state: Dictionary = state.flags.get("travel", {})
	travel_state["last_processed_week"] = 0
	state.flags["travel"] = travel_state
	state.employment = {"job_id": "", "title": "Unemployed", "weekly_pay": 0, "active": false}
	calendar.advance_one_week(state)
	var cash_before: int = state.cash
	economy.process_week(state, _load_json("res://data/housing.json"))
	travel.process_week(state, economy)
	# Economy charges the stable $620+$110 base. Travel credits $130+$15 to
	# reach local prices, then applies the $490 rent already paid at move-in. Only
	# $95 utilities and the separate $64 transit pass remain at this boundary.
	_check(state.cash == cash_before - 95 - 64, "Prepaid first rent must not be charged again; only $95 utilities and the separate $64 transit pass are due.")
	_check(_ledger_category_amount(state, "city_rent_adjustment") == 130 and _ledger_category_amount(state, "city_utility_adjustment") == 15, "Lower local rent and utilities should appear as transparent ledger credits.")
	_check(_ledger_category_amount(state, "housing_rent_prepaid_credit") == 490, "The first boundary after relocation must apply the exact prepaid local rent once.")
	_check(not bool(travel.get_current_housing_contract(state).get("first_month_prepaid", true)), "The prepaid-rent marker must clear after one use.")


func _test_upcoming_biweekly_tax() -> void:
	var state = StateClass.new(8454)
	var travel = TravelClass.new()
	state.employment = {"job_id": "retail_assistant", "title": "Retail Assistant", "weekly_pay": 700, "active": true, "suspended": false}
	state.calendar["week_index"] = 5
	state.flags["realistic_finances"] = {
		"enabled": true,
		"payroll": {"cadence_weeks": 2, "next_pay_week": 7, "accrued_gross": 180, "accrued_weeks": 1},
	}
	var tax_bill: Dictionary = {}
	for obligation in travel.upcoming_obligations(state):
		if str(obligation.get("id", "")) == "local_income_tax":
			tax_bill = obligation
			break
	_check(not tax_bill.is_empty(), "An upcoming biweekly paycheck should expose its estimated local tax.")
	_check(int(tax_bill.get("gross", 0)) == 1580, "Tax forecast should combine $180 accrued gross with two remaining $700 work weeks.")
	_check(int(tax_bill.get("amount", 0)) == 43, "Bellwether local tax should round 2.70% of the forecast $1,580 gross to $43.")
	_check(int(tax_bill.get("due_in_days", 0)) == 14 and str(tax_bill.get("schedule", "")).contains("biweekly"), "Tax obligation should align with payroll's next pay week and cadence.")


func _test_owned_car_transport() -> void:
	var state = StateClass.new(8606)
	var travel = TravelClass.new()
	var economy = EconomyClass.new()
	var assets = AssetClass.new()
	var calendar = CalendarClass.new()
	state.cash = 30000
	state.skills["driving"] = 50
	assets.buy(state, "metro_hatchback", 1, economy)
	_check(bool(assets.last_result.get("ok", false)), "Test setup should buy a working car.")
	var details := travel.transport_eligibility_details(state, "own_car")
	_check(bool(details.get("eligible", false)), "An owned car should unlock car commuting: %s" % str(details.get("reason", "")))
	var selected := travel.select_local_transport(state, "own_car", economy)
	_check(bool(travel.last_result.get("ok", false)), "Car commuting should be selectable: %s" % selected)
	_check(int(details.get("activation_cost", 0)) == 181, "Bellwether car setup should disclose $126 insurance plus $55 parking.")
	state.calendar = {"year": 2026, "month": 1, "day": 26, "week": 4, "week_index": 0}
	var travel_state: Dictionary = state.flags.get("travel", {})
	travel_state["last_processed_week"] = 0
	state.flags["travel"] = travel_state
	state.employment = {"job_id": "security_guard", "title": "Security Guard", "weekly_pay": 700, "active": true, "suspended": false}
	calendar.advance_one_week(state)
	travel.process_week(state, economy)
	_check(_ledger_category_count(state, "car_insurance") == 1 and _ledger_category_amount(state, "car_insurance") == -126, "Monthly car insurance should be a distinct real-world bill.")
	_check(_ledger_category_count(state, "work_parking") == 1 and _ledger_category_amount(state, "work_parking") == -55, "Monthly work parking should be a distinct real-world bill.")
	_check(_ledger_category_count(state, "work_commute") == 1 and _ledger_category_amount(state, "work_commute") == -34, "Car commute should charge weekly fuel separately.")

	# A vehicle managed by VehicleFinanceSystem already owns insurance and fuel.
	# Travel keeps city parking and commute time, but must not bill either twice.
	var financed_state = StateClass.new(8707)
	var financed_travel = TravelClass.new()
	var financed_economy = EconomyClass.new()
	financed_state.cash = 5000
	financed_state.flags["vehicle_finance"] = {"current": {"vehicle_id": "wayline_compact", "operational": true, "condition_score": 90}}
	var financed_details := financed_travel.transport_eligibility_details(financed_state, "own_car")
	_check(int(financed_details.get("activation_cost", -1)) == 55, "A financed car's city activation should include parking, not duplicate insurance.")
	financed_travel.select_local_transport(financed_state, "own_car", financed_economy)
	financed_state.calendar = {"year": 2026, "month": 1, "day": 26, "week": 4, "week_index": 0}
	var financed_runtime: Dictionary = financed_state.flags.get("travel", {})
	financed_runtime["last_processed_week"] = 0
	financed_state.flags["travel"] = financed_runtime
	financed_state.employment = {"job_id": "office_assistant", "title": "Office Assistant", "weekly_pay": 700, "active": true, "suspended": false}
	calendar.advance_one_week(financed_state)
	financed_travel.process_week(financed_state, financed_economy)
	_check(_ledger_category_count(financed_state, "car_insurance") == 0, "Travel must not duplicate VehicleFinanceSystem car insurance.")
	_check(_ledger_category_count(financed_state, "work_commute") == 0, "Travel must not duplicate VehicleFinanceSystem fuel.")
	_check(_ledger_category_count(financed_state, "work_parking") == 1 and _ledger_category_amount(financed_state, "work_parking") == -55, "Travel should retain the city-specific parking bill for a financed car.")


func _ledger_category_count(state, category: String) -> int:
	var result := 0
	for entry in state.ledger:
		if str(entry.get("category", "")) == category:
			result += 1
	return result


func _ledger_category_amount(state, category: String) -> int:
	var result := 0
	for entry in state.ledger:
		if str(entry.get("category", "")) == category:
			result += int(entry.get("amount", 0))
	return result


func _load_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Dictionary else {}


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
