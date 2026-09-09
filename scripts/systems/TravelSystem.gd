class_name TravelSystem
extends RefCounted

## Data-driven intercity travel, relocation, and commuting. Runtime data lives in
## state.flags[TRAVEL_FLAG], which keeps the system save-compatible without adding
## fields to LifeGameState. Call process_week after EconomySystem so local income
## tax is calculated from the paycheck that actually reached the ledger.

const DATA_PATH := "res://data/cities.json"
const BASE_HOUSING_PATH := "res://data/housing.json"
const TRAVEL_FLAG := "travel"
const STATE_VERSION := 1
const MAX_TRIP_HISTORY := 40
const ASSET_SYSTEM_PATH := "res://scripts/systems/AssetSystem.gd"

var _cities: Array[Dictionary] = []
var _modes: Array[Dictionary] = []
var _city_by_id: Dictionary = {}
var _mode_by_id: Dictionary = {}
var _base_housing_by_id: Dictionary = {}
var _default_city_id := "bellwether"

var load_errors: Array[String] = []
var last_result: Dictionary = {}


func _init() -> void:
	_load_content()
	_load_base_housing()


func get_cities(state = null) -> Array[Dictionary]:
	var current_id := ""
	if state != null:
		current_id = str(_ensure_travel_state(state).get("current_city_id", _default_city_id))
	var result: Array[Dictionary] = []
	for city in _cities:
		var copy := city.duplicate(true)
		copy["is_current"] = str(copy.get("id", "")) == current_id
		copy["rent_index_percent"] = float(int(copy.get("rent_index_basis_points", 10000))) / 100.0
		copy["utility_index_percent"] = float(int(copy.get("utility_index_basis_points", 10000))) / 100.0
		copy["income_tax_percent"] = float(int(copy.get("income_tax_basis_points", 0))) / 100.0
		copy["job_market_percent"] = float(int(copy.get("job_market_basis_points", 10000))) / 100.0
		copy["salary_index_percent"] = float(int(copy.get("salary_index_basis_points", 10000))) / 100.0
		result.append(copy)
	return result


func get_city(city_id: String) -> Dictionary:
	var city: Variant = _city_by_id.get(city_id, {})
	return city.duplicate(true) if city is Dictionary else {}


func get_current_city(state) -> Dictionary:
	var travel := _ensure_travel_state(state)
	var city := get_city(str(travel.get("current_city_id", _default_city_id)))
	city["is_current"] = true
	return city


func get_current_city_id(state) -> String:
	return str(_ensure_travel_state(state).get("current_city_id", _default_city_id))


func get_city_financial_profile(city_id: String) -> Dictionary:
	var city := get_city(city_id)
	if city.is_empty():
		return {}
	return {
		"city_id": city_id,
		"city_name": str(city.get("name", city_id)),
		"rent_index_basis_points": int(city.get("rent_index_basis_points", 10000)),
		"utility_index_basis_points": int(city.get("utility_index_basis_points", 10000)),
		"income_tax_basis_points": int(city.get("income_tax_basis_points", 0)),
		"job_market_basis_points": int(city.get("job_market_basis_points", 10000)),
		"salary_index_basis_points": int(city.get("salary_index_basis_points", 10000)),
		"rent_index_percent": float(int(city.get("rent_index_basis_points", 10000))) / 100.0,
		"utility_index_percent": float(int(city.get("utility_index_basis_points", 10000))) / 100.0,
		"income_tax_percent": float(int(city.get("income_tax_basis_points", 0))) / 100.0,
		"job_market_percent": float(int(city.get("job_market_basis_points", 10000))) / 100.0,
		"salary_index_percent": float(int(city.get("salary_index_basis_points", 10000))) / 100.0,
	}


func get_job_market_factor(city_id: String) -> float:
	var city := get_city(city_id)
	return float(int(city.get("job_market_basis_points", 10000))) / 10000.0 if not city.is_empty() else 1.0


func get_salary_multiplier(city_id: String) -> float:
	var city := get_city(city_id)
	return float(int(city.get("salary_index_basis_points", 10000))) / 10000.0 if not city.is_empty() else 1.0


func adjusted_salary(city_id: String, base_amount: int) -> int:
	return maxi(0, roundi(float(maxi(0, base_amount)) * get_salary_multiplier(city_id)))


func get_travel_modes() -> Array[Dictionary]:
	return _modes.duplicate(true)


func get_housing_options(city_id: String, state = null) -> Array[Dictionary]:
	var city := get_city(city_id)
	var result: Array[Dictionary] = []
	if city.is_empty():
		return result
	var current_city_id := get_current_city_id(state) if state != null else ""
	var raw_housing: Variant = city.get("housing", [])
	if not raw_housing is Array:
		return result
	for raw_option in raw_housing:
		if not raw_option is Dictionary:
			continue
		var option: Dictionary = raw_option.duplicate(true)
		option["city_id"] = city_id
		option["city_name"] = str(city.get("name", city_id))
		option["monthly_total"] = int(option.get("monthly_rent", 0)) + int(option.get("monthly_utilities", 0))
		option["lease_signing_total"] = int(option.get("deposit", 0)) + int(option.get("monthly_rent", 0))
		option["is_current"] = state != null and current_city_id == city_id and str(state.housing_id) == str(option.get("id", ""))
		result.append(option)
	return result


func get_current_housing_contract(state) -> Dictionary:
	var travel := _ensure_travel_state(state)
	var raw: Variant = travel.get("housing_contract", {})
	return raw.duplicate(true) if raw is Dictionary else {}


## Returns a UI-ready quote. Visits are round trips by default; relocation uses a
## one-way route internally. No state changes occur while quoting.
func trip_quote(state, destination_city_id: String, mode_id: String, round_trip: bool = true) -> Dictionary:
	var origin_id := get_current_city_id(state)
	var quote := _route_quote(state, origin_id, destination_city_id, mode_id, round_trip)
	var reasons: Array[String] = _string_array(quote.get("reasons", []))
	if bool(state.crime.get("in_jail", false)) or int(state.crime.get("jail_weeks", state.crime.get("sentence_remaining", 0))) > 0:
		reasons.append("Travel is unavailable while you are jailed.")
	if int(state.cash) < int(quote.get("total_cost", 0)):
		reasons.append("The trip costs $%s; you have $%s in cash." % [_money(int(quote.get("total_cost", 0))), _money(int(state.cash))])
	if int(state.weekly_time) < int(quote.get("time_hours", 0)):
		reasons.append("The trip needs %d free hours this week; you have %d." % [int(quote.get("time_hours", 0)), int(state.weekly_time)])
	quote["eligible"] = reasons.is_empty()
	quote["reasons"] = reasons
	quote["reason"] = _join_strings(reasons)
	quote["cash_after"] = int(state.cash) - int(quote.get("total_cost", 0))
	return quote


func can_travel(state, destination_city_id: String, mode_id: String, round_trip: bool = true) -> bool:
	return bool(trip_quote(state, destination_city_id, mode_id, round_trip).get("eligible", false))


func travel(state, destination_city_id: String, mode_id: String, economy = null, round_trip: bool = true) -> String:
	var quote := trip_quote(state, destination_city_id, mode_id, round_trip)
	if not bool(quote.get("eligible", false)):
		last_result = {"ok": false, "action": "travel", "quote": quote, "message": str(quote.get("reason", "That trip is unavailable."))}
		return "You cannot make that trip: %s" % str(quote.get("reason", "requirements are not met."))
	var time_hours := int(quote.get("time_hours", 0))
	if not _spend_time(state, time_hours, "%s trip to %s" % [str(quote.get("mode_name", "Intercity")), str(quote.get("destination_name", "another city"))]):
		last_result = {"ok": false, "action": "travel", "quote": quote, "message": "Not enough free time."}
		return "There is not enough free time left for that trip."
	var cost := int(quote.get("total_cost", 0))
	_record_money(state, economy, -cost, "%s trip to %s" % [str(quote.get("mode_name", "Intercity")), str(quote.get("destination_name", "another city"))], "intercity_travel")
	var travel_state := _ensure_travel_state(state)
	var entry := {
		"week_index": int(state.calendar.get("week_index", 0)),
		"date": _date_key(state.calendar),
		"origin_city_id": str(quote.get("origin_city_id", "")),
		"destination_city_id": destination_city_id,
		"mode_id": mode_id,
		"round_trip": round_trip,
		"distance_km": int(quote.get("total_distance_km", 0)),
		"cost": cost,
		"time_hours": time_hours,
		"purpose": "visit",
	}
	var history: Array = travel_state.get("trip_history", []) if travel_state.get("trip_history", []) is Array else []
	history.append(entry)
	while history.size() > MAX_TRIP_HISTORY:
		history.pop_front()
	travel_state["trip_history"] = history
	travel_state["last_trip"] = entry
	travel_state["total_travel_spend"] = int(travel_state.get("total_travel_spend", 0)) + cost
	state.flags[TRAVEL_FLAG] = travel_state
	state.happiness = clampi(int(state.happiness) + 1, 0, 100)
	state.add_history("Visited %s by %s." % [str(quote.get("destination_name", "another city")), str(quote.get("mode_name", "intercity transport"))])
	last_result = {"ok": true, "action": "travel", "quote": quote, "entry": entry, "message": "Trip completed."}
	return "You visited %s by %s for $%s and used %d hours." % [str(quote.get("destination_name", "another city")), str(quote.get("mode_name", "transport")), _money(cost), time_hours]


## A relocation quote includes transport, destination housing deposit, the first
## month of rent, movers, and the first local transport month. Any held security
## deposit at the old home is shown as a credit.
func move_quote(state, destination_city_id: String, housing_id: String, mode_id: String) -> Dictionary:
	var origin_id := get_current_city_id(state)
	var destination := get_city(destination_city_id)
	var housing := _find_city_housing(destination_city_id, housing_id)
	var route := _route_quote(state, origin_id, destination_city_id, mode_id, false)
	var reasons: Array[String] = _string_array(route.get("reasons", []))
	if destination.is_empty():
		reasons.append("That destination city does not exist.")
	if origin_id == destination_city_id:
		reasons.append("You already live in %s." % str(destination.get("name", destination_city_id)))
	if housing.is_empty():
		reasons.append("That home is not available in the destination city.")
	if bool(state.crime.get("in_jail", false)) or int(state.crime.get("jail_weeks", state.crime.get("sentence_remaining", 0))) > 0:
		reasons.append("You cannot relocate while jailed.")

	var destination_transport := _get_default_transport(destination_city_id)
	var transport_setup := _monthly_fixed_transport_cost(destination_transport)
	var transport_reasons := _transport_requirement_reasons(state, destination_transport)
	# A city's default is always public transport in the shipped content. This
	# defensive fallback prevents imported content from requiring an unowned car.
	if not transport_reasons.is_empty():
		destination_transport = _first_eligible_transport(state, destination_city_id)
		transport_setup = _monthly_fixed_transport_cost(destination_transport)

	var deposit := maxi(0, int(housing.get("deposit", 0)))
	var first_month_rent := maxi(0, int(housing.get("monthly_rent", 0)))
	var moving_service := maxi(0, int(destination.get("moving_base_cost", 0))) + maxi(0, int(housing.get("moving_fee", 0)))
	var travel_cost := maxi(0, int(route.get("total_cost", 0)))
	var refundable_deposit := _held_housing_deposit(state)
	var gross_move_in := travel_cost + deposit + first_month_rent + moving_service + transport_setup
	var net_cash_needed := maxi(0, gross_move_in - refundable_deposit)
	var cash_after := int(state.cash) + refundable_deposit - gross_move_in
	var moving_hours := 6
	var total_hours := int(route.get("time_hours", 0)) + moving_hours
	var min_income := maxi(0, int(housing.get("min_weekly_income", 0)))
	var weekly_income := maxi(0, int(state.employment.get("weekly_pay", 0)))
	var min_cash_after := maxi(0, int(housing.get("min_cash_after_move", 0)))
	if weekly_income < min_income:
		reasons.append("The lease requires $%s weekly income; your documented income is $%s." % [_money(min_income), _money(weekly_income)])
	if cash_after < min_cash_after:
		reasons.append("You need $%s left after moving; this move would leave $%s." % [_money(min_cash_after), _money(cash_after)])
	if int(state.weekly_time) < total_hours:
		reasons.append("Travel and moving need %d free hours this week; you have %d." % [total_hours, int(state.weekly_time)])

	return {
		"eligible": reasons.is_empty(),
		"reasons": reasons,
		"reason": _join_strings(reasons),
		"origin_city_id": origin_id,
		"origin_name": str(get_city(origin_id).get("name", origin_id)),
		"destination_city_id": destination_city_id,
		"destination_name": str(destination.get("name", destination_city_id)),
		"housing_id": housing_id,
		"housing_name": str(housing.get("name", housing_id)),
		"mode_id": mode_id,
		"mode_name": str(route.get("mode_name", mode_id)),
		"distance_km": int(route.get("distance_km", 0)),
		"travel_cost": travel_cost,
		"deposit": deposit,
		"first_month_rent": first_month_rent,
		"monthly_utilities": maxi(0, int(housing.get("monthly_utilities", 0))),
		"moving_service": moving_service,
		"destination_transport_id": str(destination_transport.get("id", "")),
		"destination_transport_name": str(destination_transport.get("name", "Local transport")),
		"local_transport_setup": transport_setup,
		"refundable_deposit": refundable_deposit,
		"gross_move_in_total": gross_move_in,
		"net_cash_needed": net_cash_needed,
		"cash_after": cash_after,
		"time_hours": total_hours,
		"moving_hours": moving_hours,
		"monthly_housing_total": first_month_rent + maxi(0, int(housing.get("monthly_utilities", 0))),
	}


func can_relocate(state, destination_city_id: String, housing_id: String, mode_id: String) -> bool:
	return bool(move_quote(state, destination_city_id, housing_id, mode_id).get("eligible", false))


func relocate(state, destination_city_id: String, housing_id: String, mode_id: String, economy = null) -> String:
	var quote := move_quote(state, destination_city_id, housing_id, mode_id)
	if not bool(quote.get("eligible", false)):
		last_result = {"ok": false, "action": "relocate", "quote": quote, "message": str(quote.get("reason", "That move is unavailable."))}
		return "You cannot relocate: %s" % str(quote.get("reason", "requirements are not met."))
	if not _spend_time(state, int(quote.get("time_hours", 0)), "Relocate to %s" % str(quote.get("destination_name", "another city"))):
		last_result = {"ok": false, "action": "relocate", "quote": quote, "message": "Not enough free time."}
		return "There is not enough free time left to relocate."

	var old_housing_name := str(get_current_housing_contract(state).get("housing_name", "Previous home"))
	var refundable := int(quote.get("refundable_deposit", 0))
	if refundable > 0:
		_record_money(state, economy, refundable, "%s security deposit returned" % old_housing_name, "housing_deposit_refund")
		_set_held_housing_deposit(state, str(state.housing_id), 0)
	var travel_cost := int(quote.get("travel_cost", 0))
	if travel_cost > 0:
		_record_money(state, economy, -travel_cost, "One-way %s to %s" % [str(quote.get("mode_name", "transport")), str(quote.get("destination_name", "new city"))], "relocation_transport")
	var moving_service := int(quote.get("moving_service", 0))
	if moving_service > 0:
		_record_money(state, economy, -moving_service, "Moving service to %s" % str(quote.get("destination_name", "new city")), "relocation_moving")
	var deposit := int(quote.get("deposit", 0))
	if deposit > 0:
		_record_money(state, economy, -deposit, "%s security deposit" % str(quote.get("housing_name", "New home")), "housing_deposit")
	var first_month := int(quote.get("first_month_rent", 0))
	if first_month > 0:
		_record_money(state, economy, -first_month, "First month rent — %s" % str(quote.get("housing_name", "New home")), "housing_rent_prepaid")
	var transport_setup := int(quote.get("local_transport_setup", 0))
	if transport_setup > 0:
		_record_money(state, economy, -transport_setup, "First month — %s" % str(quote.get("destination_transport_name", "local transport")), "transport_activation")

	state.housing_id = housing_id
	_set_held_housing_deposit(state, housing_id, deposit)
	var housing := _find_city_housing(destination_city_id, housing_id)
	var base_housing := _base_housing(housing_id)
	var contract := {
		"city_id": destination_city_id,
		"housing_id": housing_id,
		"housing_name": str(housing.get("name", housing_id)),
		"monthly_rent": int(housing.get("monthly_rent", 0)),
		"monthly_utilities": int(housing.get("monthly_utilities", 0)),
		"base_monthly_rent": int(base_housing.get("monthly_rent", 0)),
		"base_monthly_utilities": int(base_housing.get("monthly_utilities", 0)),
		"deposit": deposit,
		"started_date": _date_key(state.calendar),
		"first_month_prepaid": true,
	}
	var travel_state := _ensure_travel_state(state)
	travel_state["current_city_id"] = destination_city_id
	travel_state["transport_id"] = str(quote.get("destination_transport_id", ""))
	travel_state["transport_paid_through_month"] = _month_key(state.calendar) if transport_setup > 0 else ""
	travel_state["housing_contract"] = contract
	travel_state["relocations"] = int(travel_state.get("relocations", 0)) + 1
	travel_state["total_travel_spend"] = int(travel_state.get("total_travel_spend", 0)) + travel_cost
	travel_state["last_relocation"] = {
		"week_index": int(state.calendar.get("week_index", 0)),
		"date": _date_key(state.calendar),
		"from_city_id": str(quote.get("origin_city_id", "")),
		"to_city_id": destination_city_id,
		"housing_id": housing_id,
		"net_cost": int(quote.get("net_cash_needed", 0)),
	}
	state.flags[TRAVEL_FLAG] = travel_state
	state.happiness = clampi(int(state.happiness) + 2, 0, 100)
	state.stress = clampi(int(state.stress) + 2, 0, 100)
	state.add_history("Relocated to %s and moved into %s." % [str(quote.get("destination_name", destination_city_id)), str(quote.get("housing_name", housing_id))])
	last_result = {"ok": true, "action": "relocate", "quote": quote, "contract": contract, "message": "Relocation completed."}
	return "You relocated to %s. After the returned deposit, travel, movers, lease, first rent, and local transport cost $%s; $%s remains." % [str(quote.get("destination_name", destination_city_id)), _money(int(quote.get("net_cash_needed", 0))), _money(int(state.cash))]


func get_local_transport_options(state, city_id: String = "") -> Array[Dictionary]:
	var target_city_id := city_id if not city_id.is_empty() else get_current_city_id(state)
	var city := get_city(target_city_id)
	var selected := str(_ensure_travel_state(state).get("transport_id", "")) if target_city_id == get_current_city_id(state) else ""
	var result: Array[Dictionary] = []
	var raw_options: Variant = city.get("local_transport", [])
	if not raw_options is Array:
		return result
	for raw_option in raw_options:
		if not raw_option is Dictionary:
			continue
		var option: Dictionary = _transport_cost_profile(state, raw_option)
		var reasons := _transport_requirement_reasons(state, option)
		option["city_id"] = target_city_id
		option["selected"] = str(option.get("id", "")) == selected
		option["eligible"] = reasons.is_empty()
		option["reasons"] = reasons
		option["reason"] = _join_strings(reasons)
		option["monthly_fixed_cost"] = _monthly_fixed_transport_cost(option)
		option["weekly_commute_cost"] = _weekly_transport_cost(option)
		option["estimated_monthly_total"] = _monthly_fixed_transport_cost(option) + roundi(float(_weekly_transport_cost(option)) * 52.0 / 12.0)
		result.append(option)
	return result


func transport_eligibility_details(state, transport_id: String, city_id: String = "") -> Dictionary:
	var target_city_id := city_id if not city_id.is_empty() else get_current_city_id(state)
	var option := _transport_cost_profile(state, _find_local_transport(target_city_id, transport_id))
	var reasons: Array[String] = []
	if option.is_empty():
		reasons.append("That transport option is not available in this city.")
	else:
		reasons = _transport_requirement_reasons(state, option)
	if target_city_id != get_current_city_id(state):
		reasons.append("Move to this city before choosing its local transport.")
	if str(_ensure_travel_state(state).get("transport_id", "")) == transport_id and target_city_id == get_current_city_id(state):
		reasons.append("This is already your selected commute.")
	var activation := _monthly_fixed_transport_cost(option)
	if int(state.cash) < activation:
		reasons.append("Starting this option costs $%s; you have $%s." % [_money(activation), _money(int(state.cash))])
	if int(state.weekly_time) < 1:
		reasons.append("Changing your commute needs 1 free hour this week.")
	return {
		"eligible": reasons.is_empty(),
		"reasons": reasons,
		"reason": _join_strings(reasons),
		"city_id": target_city_id,
		"transport_id": transport_id,
		"activation_cost": activation,
		"weekly_commute_cost": _weekly_transport_cost(option),
		"monthly_fixed_cost": _monthly_fixed_transport_cost(option),
	}


func select_local_transport(state, transport_id: String, economy = null) -> String:
	var city_id := get_current_city_id(state)
	var details := transport_eligibility_details(state, transport_id, city_id)
	if not bool(details.get("eligible", false)):
		last_result = {"ok": false, "action": "select_transport", "details": details, "message": str(details.get("reason", "Unavailable."))}
		return "You cannot choose that commute: %s" % str(details.get("reason", "requirements are not met."))
	var option := _transport_cost_profile(state, _find_local_transport(city_id, transport_id))
	if not _spend_time(state, 1, "Arrange %s" % str(option.get("name", "local transport"))):
		return "There is not enough free time to arrange that commute."
	var activation := int(details.get("activation_cost", 0))
	if activation > 0:
		_record_money(state, economy, -activation, "Start %s" % str(option.get("name", "local transport")), "transport_activation")
	var travel_state := _ensure_travel_state(state)
	travel_state["transport_id"] = transport_id
	travel_state["transport_paid_through_month"] = _month_key(state.calendar) if activation > 0 else ""
	state.flags[TRAVEL_FLAG] = travel_state
	last_result = {"ok": true, "action": "select_transport", "details": details, "message": "Commute changed."}
	return "You will now use %s. Setup cost $%s; the estimated ongoing cost is $%s per month." % [str(option.get("name", transport_id)), _money(activation), _money(int(option.get("estimated_monthly_total", _monthly_fixed_transport_cost(option) + roundi(float(_weekly_transport_cost(option)) * 52.0 / 12.0))))]


func commute_profile(state) -> Dictionary:
	var travel := _ensure_travel_state(state)
	var city_id := str(travel.get("current_city_id", _default_city_id))
	var option := _find_local_transport(city_id, str(travel.get("transport_id", "")))
	if option.is_empty():
		option = _first_eligible_transport(state, city_id)
	option = _transport_cost_profile(state, option)
	var city := get_city(city_id)
	var result := option.duplicate(true)
	result["city_id"] = city_id
	result["city_name"] = str(city.get("name", city_id))
	result["monthly_fixed_cost"] = _monthly_fixed_transport_cost(option)
	result["weekly_commute_cost"] = _weekly_transport_cost(option)
	result["estimated_monthly_total"] = _monthly_fixed_transport_cost(option) + roundi(float(_weekly_transport_cost(option)) * 52.0 / 12.0)
	result["is_employed"] = _is_commuting(state)
	result["has_owned_vehicle"] = _has_owned_vehicle(state)
	return result


func upcoming_obligations(state) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var city := get_current_city(state)
	var commute := commute_profile(state)
	var days_until := _days_until_next_month(state.calendar)
	if _is_commuting(state):
		var weekly_cost := int(commute.get("weekly_commute_cost", 0))
		if weekly_cost > 0:
			result.append({"id": "weekly_commute", "name": "%s commute" % str(commute.get("name", "Work")), "amount": weekly_cost, "schedule": "next work week", "due_in_days": 7})
	var pay_forecast := _next_payroll_forecast(state)
	var estimated_gross := int(pay_forecast.get("gross", 0))
	var local_tax := _basis_point_amount(estimated_gross, int(city.get("income_tax_basis_points", 0)))
	if local_tax > 0:
		result.append({"id": "local_income_tax", "name": "%s local income tax (estimated)" % str(city.get("name", "City")), "amount": local_tax, "gross": estimated_gross, "schedule": "with the next %s paycheck" % str(pay_forecast.get("cadence_label", "scheduled")), "due_in_days": int(pay_forecast.get("due_in_days", 7)), "due_week": int(pay_forecast.get("due_week", int(state.calendar.get("week_index", 0)) + 1))})
	var monthly_fixed := int(commute.get("monthly_fixed_cost", 0))
	if monthly_fixed > 0:
		result.append({"id": "monthly_transport", "name": "%s monthly costs" % str(commute.get("name", "Transport")), "amount": monthly_fixed, "schedule": "monthly boundary", "due_in_days": days_until})
	var contract := get_current_housing_contract(state)
	if not contract.is_empty():
		var rent_due := 0 if bool(contract.get("first_month_prepaid", false)) else int(contract.get("monthly_rent", 0))
		result.append({"id": "city_housing", "name": "%s rent and utilities" % str(contract.get("housing_name", "Housing")), "amount": rent_due + int(contract.get("monthly_utilities", 0)), "rent": rent_due, "utilities": int(contract.get("monthly_utilities", 0)), "prepaid_rent_credit": int(contract.get("monthly_rent", 0)) if bool(contract.get("first_month_prepaid", false)) else 0, "schedule": "monthly boundary", "due_in_days": days_until, "consolidated": true})
	return result


## Processes local payroll tax, the selected work commute, and monthly city cost
## adjustments. It is idempotent per week, including seeded commute disruptions.
func process_week(state, economy = null) -> Array[String]:
	var summary: Array[String] = []
	var travel_state := _ensure_travel_state(state)
	var week_index := int(state.calendar.get("week_index", 0))
	if week_index <= int(travel_state.get("last_processed_week", 0)):
		return summary
	travel_state["last_processed_week"] = week_index
	state.flags[TRAVEL_FLAG] = travel_state

	var city := get_current_city(state)
	var city_name := str(city.get("name", "Your city"))
	var gross_pay := _gross_pay_this_week(state)
	if gross_pay > 0:
		var tax := _basis_point_amount(gross_pay, int(city.get("income_tax_basis_points", 0)))
		if tax > 0:
			_charge_obligation(state, economy, tax, "%s local income tax on $%s gross pay" % [city_name, _money(gross_pay)], "local_income_tax", summary)
			travel_state = _ensure_travel_state(state)
			travel_state["total_local_tax_paid"] = int(travel_state.get("total_local_tax_paid", 0)) + tax
			state.flags[TRAVEL_FLAG] = travel_state

	if _is_commuting(state):
		_process_commute(state, economy, city, summary)

	if _crossed_month_boundary(state):
		_process_monthly_transport(state, economy, city, summary)
		_process_city_housing_adjustments(state, economy, city, summary)

	state.state_changed.emit()
	return summary


func _process_commute(state, economy, city: Dictionary, summary: Array[String]) -> void:
	var profile := commute_profile(state)
	if bool(profile.get("requires_owned_vehicle", false)) and not _has_owned_vehicle(state):
		var replacement := _first_eligible_transport(state, str(city.get("id", "")))
		var travel_state := _ensure_travel_state(state)
		travel_state["transport_id"] = str(replacement.get("id", "walk_cycle"))
		travel_state["transport_paid_through_month"] = ""
		state.flags[TRAVEL_FLAG] = travel_state
		profile = commute_profile(state)
		summary.append("After losing access to a car, your commute changed to %s." % str(profile.get("name", "local transport")))
	var weekly_cost := _weekly_transport_cost(profile)
	if weekly_cost > 0:
		var reason := "%s work commute" % str(profile.get("name", "Local transport"))
		if int(profile.get("weekly_fuel", 0)) > 0:
			reason = "%s fuel for work commute" % str(profile.get("name", "Car"))
		_charge_obligation(state, economy, weekly_cost, reason, "work_commute", summary)
		var travel_state := _ensure_travel_state(state)
		travel_state["total_commute_spend"] = int(travel_state.get("total_commute_spend", 0)) + weekly_cost
		state.flags[TRAVEL_FLAG] = travel_state
	var commute_hours := maxi(0, int(profile.get("commute_hours_weekly", 0)))
	if commute_hours > 0:
		var used_hours := mini(commute_hours, maxi(0, int(state.weekly_time)))
		state.weekly_time = maxi(0, int(state.weekly_time) - used_hours)
		if used_hours < commute_hours:
			state.stress = clampi(int(state.stress) + 2, 0, 100)
			summary.append("Your commute overran the free time available this week; stress rose.")
		else:
			summary.append("Commuting by %s used %d discretionary hours." % [str(profile.get("name", "local transport")), commute_hours])
	var reliability := clampi(int(profile.get("reliability_percent", 100)), 0, 100)
	if state.randf_seeded() * 100.0 >= float(reliability):
		var delay_hours := mini(2, maxi(0, int(state.weekly_time)))
		state.weekly_time = maxi(0, int(state.weekly_time) - delay_hours)
		state.stress = clampi(int(state.stress) + 2, 0, 100)
		summary.append("A commute delay cost %d extra hours and raised stress." % delay_hours)


func _process_monthly_transport(state, economy, city: Dictionary, summary: Array[String]) -> void:
	var profile := commute_profile(state)
	var city_name := str(city.get("name", "City"))
	var charges := [
		{"amount": int(profile.get("monthly_pass", 0)), "reason": "%s monthly pass — %s" % [str(profile.get("name", "Transit")), city_name], "category": "transport_pass"},
		{"amount": int(profile.get("monthly_insurance", 0)), "reason": "Monthly car insurance — %s" % city_name, "category": "car_insurance"},
		{"amount": int(profile.get("monthly_parking", 0)), "reason": "Monthly work parking — %s" % city_name, "category": "work_parking"},
	]
	var paid := 0
	for charge in charges:
		var amount := maxi(0, int(charge.get("amount", 0)))
		if amount > 0:
			_charge_obligation(state, economy, amount, str(charge.get("reason", "Transport")), str(charge.get("category", "transport")), summary)
			paid += amount
	if paid > 0:
		var travel_state := _ensure_travel_state(state)
		travel_state["total_commute_spend"] = int(travel_state.get("total_commute_spend", 0)) + paid
		travel_state["transport_paid_through_month"] = _month_key(state.calendar)
		state.flags[TRAVEL_FLAG] = travel_state


func _process_city_housing_adjustments(state, economy, city: Dictionary, summary: Array[String]) -> void:
	var contract := get_current_housing_contract(state)
	if contract.is_empty() or str(contract.get("housing_id", "")) != str(state.housing_id):
		return
	var city_name := str(city.get("name", "City"))
	var adjustments := [
		{"amount": int(contract.get("monthly_rent", 0)) - int(contract.get("base_monthly_rent", 0)), "reason": "%s local rent adjustment — %s" % [city_name, str(contract.get("housing_name", "Housing"))], "category": "city_rent_adjustment", "kind": "rent"},
		{"amount": int(contract.get("monthly_utilities", 0)) - int(contract.get("base_monthly_utilities", 0)), "reason": "%s utility-rate adjustment — %s" % [city_name, str(contract.get("housing_name", "Housing"))], "category": "city_utility_adjustment", "kind": "utilities"},
	]
	var adjustment_total := 0
	for adjustment in adjustments:
		var delta := int(adjustment.get("amount", 0))
		if delta > 0:
			_charge_obligation(state, economy, delta, str(adjustment.get("reason", "Local housing cost")), str(adjustment.get("category", "city_housing_adjustment")), summary)
			adjustment_total += delta
		elif delta < 0:
			_record_money(state, economy, -delta, str(adjustment.get("reason", "Local housing credit")), str(adjustment.get("category", "city_housing_adjustment")))
			adjustment_total += delta
			summary.append("Lower %s costs in %s reduced this month's housing charge by $%s." % [str(adjustment.get("kind", "housing")), city_name, _money(-delta)])
	var travel_state := _ensure_travel_state(state)
	if adjustment_total != 0:
		travel_state["total_housing_adjustments"] = int(travel_state.get("total_housing_adjustments", 0)) + adjustment_total
	# EconomySystem has already posted the stable base rent and the adjustment
	# above has brought it to the city's actual rent. A new lease collected its
	# first month on move-in, so credit that actual rent exactly once at the first
	# following monthly boundary. Utilities remain payable for actual usage.
	if bool(contract.get("first_month_prepaid", false)):
		var prepaid_rent := maxi(0, int(contract.get("monthly_rent", 0)))
		if prepaid_rent > 0:
			_record_money(state, economy, prepaid_rent, "Prepaid first-month rent applied — %s" % str(contract.get("housing_name", "Housing")), "housing_rent_prepaid_credit")
			summary.append("Your prepaid first month covered $%s of rent; only current utilities remain due." % _money(prepaid_rent))
			travel_state["prepaid_rent_credits"] = int(travel_state.get("prepaid_rent_credits", 0)) + prepaid_rent
		contract["first_month_prepaid"] = false
		travel_state["housing_contract"] = contract
	state.flags[TRAVEL_FLAG] = travel_state


func _route_quote(state, origin_city_id: String, destination_city_id: String, mode_id: String, round_trip: bool) -> Dictionary:
	var origin := get_city(origin_city_id)
	var destination := get_city(destination_city_id)
	var mode: Dictionary = _mode_by_id.get(mode_id, {}).duplicate(true) if _mode_by_id.get(mode_id, {}) is Dictionary else {}
	var reasons: Array[String] = []
	if origin.is_empty():
		reasons.append("The origin city does not exist.")
	if destination.is_empty():
		reasons.append("The destination city does not exist.")
	if mode.is_empty():
		reasons.append("That travel mode does not exist.")
	if origin_city_id == destination_city_id and not origin.is_empty():
		reasons.append("Choose a different city.")
	var distances: Variant = origin.get("distances_km", {})
	var distance := int((distances as Dictionary).get(destination_city_id, 0)) if distances is Dictionary else 0
	if distance <= 0 and origin_city_id != destination_city_id:
		reasons.append("No route distance is available between these cities.")
	var connection_key := str(mode.get("connection_key", "road"))
	var origin_connections: Variant = origin.get("connections", {})
	var destination_connections: Variant = destination.get("connections", {})
	if not mode.is_empty() and (not origin_connections is Dictionary or not bool((origin_connections as Dictionary).get(connection_key, false)) or not destination_connections is Dictionary or not bool((destination_connections as Dictionary).get(connection_key, false))):
		reasons.append("%s service does not connect both cities." % str(mode.get("name", mode_id)))
	var minimum_distance := maxi(0, int(mode.get("minimum_distance_km", 0)))
	if distance > 0 and distance < minimum_distance:
		reasons.append("%s is only offered on routes of at least %d km." % [str(mode.get("name", mode_id)), minimum_distance])
	if bool(mode.get("requires_owned_vehicle", false)) and not _has_owned_vehicle(state):
		reasons.append("You need to own a working car for this option.")
	var legs := 2 if round_trip else 1
	var one_way_cost := maxi(0, int(mode.get("base_fare", 0))) + ceili(float(distance * maxi(0, int(mode.get("rate_per_100_km", 0)))) / 100.0)
	var speed := maxf(1.0, float(mode.get("speed_kmh", 60.0)))
	var one_way_hours := float(mode.get("terminal_hours", 0.0)) + float(distance) / speed
	var total_hours := ceili(one_way_hours * float(legs))
	return {
		"eligible": reasons.is_empty(),
		"reasons": reasons,
		"reason": _join_strings(reasons),
		"origin_city_id": origin_city_id,
		"origin_name": str(origin.get("name", origin_city_id)),
		"destination_city_id": destination_city_id,
		"destination_name": str(destination.get("name", destination_city_id)),
		"mode_id": mode_id,
		"mode_name": str(mode.get("name", mode_id)),
		"round_trip": round_trip,
		"legs": legs,
		"distance_km": distance,
		"total_distance_km": distance * legs,
		"one_way_cost": one_way_cost,
		"total_cost": one_way_cost * legs,
		"one_way_hours": one_way_hours,
		"time_hours": total_hours,
	}


func _ensure_travel_state(state) -> Dictionary:
	var raw: Variant = state.flags.get(TRAVEL_FLAG, {})
	var travel: Dictionary = raw.duplicate(true) if raw is Dictionary else {}
	travel["version"] = STATE_VERSION
	var city_id := str(travel.get("current_city_id", _default_city_id))
	if not _city_by_id.has(city_id):
		city_id = _default_city_id
	travel["current_city_id"] = city_id
	var transport_id := str(travel.get("transport_id", ""))
	if _find_local_transport(city_id, transport_id).is_empty():
		var initial_transport := _find_local_transport(city_id, "payg_bus")
		if initial_transport.is_empty():
			initial_transport = _find_local_transport(city_id, "payg_metro")
		if initial_transport.is_empty():
			initial_transport = _get_default_transport(city_id)
		transport_id = str(initial_transport.get("id", "walk_cycle"))
	travel["transport_id"] = transport_id
	if not travel.has("housing_contract") or not travel.get("housing_contract") is Dictionary:
		travel["housing_contract"] = _contract_for_existing_housing(state, city_id)
	if not travel.has("trip_history") or not travel.get("trip_history") is Array:
		travel["trip_history"] = []
	if not travel.has("last_trip") or not travel.get("last_trip") is Dictionary:
		travel["last_trip"] = {}
	if not travel.has("last_relocation") or not travel.get("last_relocation") is Dictionary:
		travel["last_relocation"] = {}
	for key in ["relocations", "total_travel_spend", "total_commute_spend", "total_local_tax_paid", "total_housing_adjustments", "prepaid_rent_credits"]:
		travel[key] = int(travel.get(key, 0))
	if not travel.has("last_processed_week"):
		travel["last_processed_week"] = maxi(0, int(state.calendar.get("week_index", 0)) - 1)
	else:
		travel["last_processed_week"] = maxi(0, int(travel.get("last_processed_week", 0)))
	travel["transport_paid_through_month"] = str(travel.get("transport_paid_through_month", ""))
	state.flags[TRAVEL_FLAG] = travel
	return travel


func _contract_for_existing_housing(state, city_id: String) -> Dictionary:
	var housing_id := str(state.housing_id)
	if housing_id.is_empty():
		return {}
	var local := _find_city_housing(city_id, housing_id)
	if local.is_empty():
		return {}
	var base := _base_housing(housing_id)
	return {
		"city_id": city_id,
		"housing_id": housing_id,
		"housing_name": str(local.get("name", housing_id)),
		"monthly_rent": int(local.get("monthly_rent", 0)),
		"monthly_utilities": int(local.get("monthly_utilities", 0)),
		"base_monthly_rent": int(base.get("monthly_rent", 0)),
		"base_monthly_utilities": int(base.get("monthly_utilities", 0)),
		"deposit": _held_housing_deposit(state),
		"started_date": _date_key(state.calendar),
		"first_month_prepaid": false,
	}


func _find_city_housing(city_id: String, housing_id: String) -> Dictionary:
	var city := get_city(city_id)
	var raw: Variant = city.get("housing", [])
	if raw is Array:
		for option in raw:
			if option is Dictionary and str(option.get("id", "")) == housing_id:
				return option.duplicate(true)
	return {}


func _find_local_transport(city_id: String, transport_id: String) -> Dictionary:
	if transport_id.is_empty():
		return {}
	var city := get_city(city_id)
	var raw: Variant = city.get("local_transport", [])
	if raw is Array:
		for option in raw:
			if option is Dictionary and str(option.get("id", "")) == transport_id:
				return option.duplicate(true)
	return {}


func _get_default_transport(city_id: String) -> Dictionary:
	var city := get_city(city_id)
	var result := _find_local_transport(city_id, str(city.get("default_transport_id", "")))
	if result.is_empty():
		var raw: Variant = city.get("local_transport", [])
		if raw is Array and not raw.is_empty() and raw[0] is Dictionary:
			result = (raw[0] as Dictionary).duplicate(true)
	return result


func _first_eligible_transport(state, city_id: String) -> Dictionary:
	var city := get_city(city_id)
	var raw: Variant = city.get("local_transport", [])
	if raw is Array:
		for option in raw:
			if option is Dictionary and _transport_requirement_reasons(state, option).is_empty():
				return option.duplicate(true)
	return {}


func _transport_requirement_reasons(state, option: Dictionary) -> Array[String]:
	var reasons: Array[String] = []
	if option.is_empty():
		return reasons
	if bool(option.get("requires_owned_vehicle", false)) and not _has_owned_vehicle(state):
		reasons.append("You need to own a working car.")
	return reasons


func _transport_cost_profile(state, option: Dictionary) -> Dictionary:
	var result := option.duplicate(true)
	if str(result.get("id", "")) == "own_car" and _vehicle_finance_manages_costs(state):
		result["vehicle_finance_insurance"] = maxi(0, int(result.get("monthly_insurance", 0)))
		result["vehicle_finance_fuel"] = maxi(0, int(result.get("weekly_fuel", 0)))
		result["monthly_insurance"] = 0
		result["weekly_fuel"] = 0
		result["vehicle_costs_managed_externally"] = true
	return result


func _vehicle_finance_manages_costs(state) -> bool:
	var raw: Variant = state.flags.get("vehicle_finance", {})
	if not raw is Dictionary:
		return false
	var current: Variant = (raw as Dictionary).get("current", {})
	return current is Dictionary and not (current as Dictionary).is_empty() and not str((current as Dictionary).get("vehicle_id", "")).is_empty()


func _has_owned_vehicle(state) -> bool:
	# The newer financing system is the authoritative home for cash-purchased and
	# financed road vehicles. Read its save-safe flag directly so this system also
	# works when VehicleFinanceSystem has not been instantiated by a test scene.
	var financed_runtime: Variant = state.flags.get("vehicle_finance", {})
	if financed_runtime is Dictionary:
		var financed_current: Variant = (financed_runtime as Dictionary).get("current", {})
		if financed_current is Dictionary and not (financed_current as Dictionary).is_empty():
			var working := bool((financed_current as Dictionary).get("operational", true))
			var condition := int((financed_current as Dictionary).get("condition_score", 100))
			if working and condition >= 15 and not str((financed_current as Dictionary).get("vehicle_id", "")).is_empty():
				return true

	# Retain compatibility with the first-milestone possessions catalog.
	if ResourceLoader.exists(ASSET_SYSTEM_PATH):
		var script: Script = load(ASSET_SYSTEM_PATH)
		var system: Variant = script.new()
		if system.has_method("get_owned"):
			var owned: Variant = system.get_owned(state, "vehicle")
			if owned is Array:
				for vehicle in owned:
					if vehicle is Dictionary and int(vehicle.get("quantity", 0)) > 0 and int(vehicle.get("condition", 100)) >= 15:
						return true
	# Compatibility with early saves or tests that only provide portfolio flags.
	var portfolio: Variant = state.flags.get("assets", {})
	if portfolio is Dictionary:
		var holdings: Variant = (portfolio as Dictionary).get("holdings", {})
		if holdings is Dictionary:
			for vehicle_id in ["metro_hatchback", "courier_van", "solace_electric_sedan"]:
				var holding: Variant = (holdings as Dictionary).get(vehicle_id, {})
				if holding is Dictionary and int((holding as Dictionary).get("quantity", 0)) > 0 and int((holding as Dictionary).get("condition", 100)) >= 15:
					return true
	return false


func _is_commuting(state) -> bool:
	if bool(state.crime.get("in_jail", false)) or int(state.crime.get("jail_weeks", state.crime.get("sentence_remaining", 0))) > 0:
		return false
	return bool(state.employment.get("active", not str(state.employment.get("job_id", "")).is_empty())) and not str(state.employment.get("job_id", "")).is_empty() and not bool(state.employment.get("suspended", false))


func _gross_pay_this_week(state) -> int:
	var week_index := int(state.calendar.get("week_index", 0))
	var gross := 0
	for entry in state.ledger:
		if int(entry.get("week_index", -1)) != week_index or int(entry.get("amount", 0)) <= 0:
			continue
		var category := str(entry.get("category", ""))
		if category in ["employment_income", "salary_income", "paycheck", "employment_paycheck"]:
			gross += int(entry.get("gross_amount", entry.get("amount", 0)))
	return gross


func _next_payroll_forecast(state) -> Dictionary:
	var week_index := int(state.calendar.get("week_index", 0))
	var weekly_gross := maxi(0, int(state.employment.get("weekly_pay", 0)))
	var raw_profile: Variant = state.flags.get("realistic_finances", {})
	if raw_profile is Dictionary and bool((raw_profile as Dictionary).get("enabled", false)):
		var raw_payroll: Variant = (raw_profile as Dictionary).get("payroll", {})
		if raw_payroll is Dictionary:
			var payroll: Dictionary = raw_payroll
			var cadence := maxi(1, int(payroll.get("cadence_weeks", 2)))
			var next_pay_week := maxi(week_index + 1, int(payroll.get("next_pay_week", week_index + 1)))
			var weeks_until := maxi(1, next_pay_week - week_index)
			var expected_new_accrual := weekly_gross * weeks_until if _is_commuting(state) else 0
			return {
				"gross": maxi(0, int(payroll.get("accrued_gross", 0))) + expected_new_accrual,
				"due_week": next_pay_week,
				"due_in_days": weeks_until * 7,
				"cadence_weeks": cadence,
				"cadence_label": "biweekly" if cadence == 2 else ("weekly" if cadence == 1 else "%d-week" % cadence),
			}
	return {"gross": weekly_gross, "due_week": week_index + 1, "due_in_days": 7, "cadence_weeks": 1, "cadence_label": "weekly"}


func _monthly_fixed_transport_cost(option: Dictionary) -> int:
	return maxi(0, int(option.get("monthly_pass", 0))) + maxi(0, int(option.get("monthly_insurance", 0))) + maxi(0, int(option.get("monthly_parking", 0)))


func _weekly_transport_cost(option: Dictionary) -> int:
	return maxi(0, int(option.get("weekly_fares", 0))) + maxi(0, int(option.get("weekly_fuel", 0)))


func _held_housing_deposit(state) -> int:
	var deposits: Variant = state.flags.get("housing_deposits", {})
	return maxi(0, int((deposits as Dictionary).get(str(state.housing_id), 0))) if deposits is Dictionary else 0


func _set_held_housing_deposit(state, housing_id: String, amount: int) -> void:
	var raw: Variant = state.flags.get("housing_deposits", {})
	var deposits: Dictionary = raw.duplicate(true) if raw is Dictionary else {}
	if amount <= 0:
		deposits.erase(housing_id)
	else:
		deposits[housing_id] = amount
	state.flags["housing_deposits"] = deposits


func _base_housing(housing_id: String) -> Dictionary:
	var value: Variant = _base_housing_by_id.get(housing_id, {})
	return value.duplicate(true) if value is Dictionary else {}


func _charge_obligation(state, economy, amount: int, reason: String, category: String, summary: Array[String]) -> void:
	if amount <= 0:
		return
	var cash_before := maxi(0, int(state.cash))
	_record_money(state, economy, -amount, reason, category)
	var shortfall := maxi(0, amount - cash_before)
	if shortfall > 0:
		state.debt = int(state.debt) + shortfall
		_record_money(state, economy, shortfall, "Emergency credit for %s" % reason, "debt_draw")
		state.stress = clampi(int(state.stress) + 3, 0, 100)
		state.reputation = clampi(int(state.reputation) - 1, -100, 100)
		state.flags["missed_obligations"] = int(state.flags.get("missed_obligations", 0)) + 1
		summary.append("%s cost $%s; $%s became debt." % [reason, _money(amount), _money(shortfall)])
	else:
		summary.append("%s cost $%s." % [reason, _money(amount)])


func _record_money(state, economy, amount: int, reason: String, category: String) -> void:
	if economy != null and economy.has_method("record"):
		economy.record(state, amount, reason, category)
		return
	state.cash = int(state.cash) + amount
	var sequence := maxi(int(state.flags.get("ledger_sequence", state.ledger.size())), state.ledger.size()) + 1
	state.flags["ledger_sequence"] = sequence
	state.ledger.append({
		"id": sequence,
		"week_index": int(state.calendar.get("week_index", 0)),
		"date": _date_key(state.calendar),
		"amount": amount,
		"balance_after": int(state.cash),
		"reason": reason,
		"category": category,
		"account": "cash",
	})


func _spend_time(state, hours: int, reason: String) -> bool:
	if hours <= 0:
		return true
	if state.has_method("spend_time"):
		return bool(state.spend_time(hours, reason))
	if int(state.weekly_time) < hours:
		return false
	state.weekly_time = int(state.weekly_time) - hours
	return true


func _crossed_month_boundary(state) -> bool:
	var boundary: Variant = state.flags.get("last_calendar_boundary", {})
	var week_index := int(state.calendar.get("week_index", 0))
	if boundary is Dictionary and int((boundary as Dictionary).get("to_week_index", -1)) == week_index:
		var months: Variant = (boundary as Dictionary).get("month_boundaries", [])
		return months is Array and not months.is_empty()
	return week_index > 0 and int(state.calendar.get("day", 8)) <= 7


func _days_until_next_month(calendar: Dictionary) -> int:
	var year := clampi(int(calendar.get("year", 2026)), 1900, 9999)
	var month := clampi(int(calendar.get("month", 1)), 1, 12)
	var day := clampi(int(calendar.get("day", 1)), 1, _days_in_month(year, month))
	return _days_in_month(year, month) - day + 1


func _days_in_month(year: int, month: int) -> int:
	match month:
		2:
			return 29 if year % 400 == 0 or (year % 4 == 0 and year % 100 != 0) else 28
		4, 6, 9, 11:
			return 30
		_:
			return 31


func _basis_point_amount(amount: int, basis_points: int) -> int:
	if amount <= 0 or basis_points <= 0:
		return 0
	return roundi(float(amount) * float(basis_points) / 10000.0)


func _date_key(calendar: Dictionary) -> String:
	return "%04d-%02d-%02d" % [int(calendar.get("year", 2026)), int(calendar.get("month", 1)), int(calendar.get("day", 1))]


func _month_key(calendar: Dictionary) -> String:
	return "%04d-%02d" % [int(calendar.get("year", 2026)), int(calendar.get("month", 1))]


func _join_strings(values: Array) -> String:
	var parts := PackedStringArray()
	for value in values:
		parts.append(str(value))
	return " ".join(parts)


func _string_array(value: Variant) -> Array[String]:
	var result: Array[String] = []
	if value is Array:
		for item in value:
			var clean := str(item).strip_edges()
			if not clean.is_empty():
				result.append(clean)
	return result


func _money(value: int) -> String:
	var raw := str(absi(value))
	var formatted := ""
	while raw.length() > 3:
		formatted = "," + raw.right(3) + formatted
		raw = raw.left(raw.length() - 3)
	formatted = raw + formatted
	return ("-" if value < 0 else "") + formatted


func _load_content() -> void:
	_cities.clear()
	_modes.clear()
	_city_by_id.clear()
	_mode_by_id.clear()
	load_errors.clear()
	if not FileAccess.file_exists(DATA_PATH):
		_add_load_error("City content is missing: %s" % DATA_PATH)
		return
	var file := FileAccess.open(DATA_PATH, FileAccess.READ)
	if file == null:
		_add_load_error("City content could not be opened: %s" % DATA_PATH)
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		_add_load_error("City content must be a JSON object.")
		return
	_default_city_id = str((parsed as Dictionary).get("default_city_id", "bellwether"))
	var raw_modes: Variant = (parsed as Dictionary).get("travel_modes", [])
	if raw_modes is Array:
		for raw_mode in raw_modes:
			if not raw_mode is Dictionary or str(raw_mode.get("id", "")).is_empty():
				_add_load_error("Each travel mode needs a stable id.")
				continue
			var mode: Dictionary = raw_mode.duplicate(true)
			var mode_id := str(mode.get("id", ""))
			if _mode_by_id.has(mode_id):
				_add_load_error("Duplicate travel mode id: %s" % mode_id)
				continue
			_modes.append(mode)
			_mode_by_id[mode_id] = mode
	var raw_cities: Variant = (parsed as Dictionary).get("cities", [])
	if raw_cities is Array:
		for raw_city in raw_cities:
			if not raw_city is Dictionary or str(raw_city.get("id", "")).is_empty():
				_add_load_error("Each city needs a stable id.")
				continue
			var city: Dictionary = raw_city.duplicate(true)
			var city_id := str(city.get("id", ""))
			if _city_by_id.has(city_id):
				_add_load_error("Duplicate city id: %s" % city_id)
				continue
			_cities.append(city)
			_city_by_id[city_id] = city
	if not _city_by_id.has(_default_city_id):
		_add_load_error("Default city '%s' is missing." % _default_city_id)
	if _cities.size() < 5:
		_add_load_error("At least five cities are required.")


func _load_base_housing() -> void:
	_base_housing_by_id.clear()
	if not FileAccess.file_exists(BASE_HOUSING_PATH):
		return
	var file := FileAccess.open(BASE_HOUSING_PATH, FileAccess.READ)
	if file == null:
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		return
	var raw: Variant = (parsed as Dictionary).get("housing", [])
	if raw is Array:
		for option in raw:
			if option is Dictionary and not str(option.get("id", "")).is_empty():
				_base_housing_by_id[str(option.get("id", ""))] = option.duplicate(true)


func _add_load_error(message: String) -> void:
	load_errors.append(message)
	push_error(message)
