class_name VehicleFinanceSystem
extends RefCounted

## Realistic single-vehicle ownership, financing, insurance, fuel, maintenance,
## depreciation, and repossession. Runtime data lives in state.flags so old saves
## remain valid without a LifeGameState schema migration.

const DATA_PATH := "res://data/vehicles.json"
const STATE_FLAG := "vehicle_finance"
const STATE_VERSION := 1

var _catalog: Array[Dictionary] = []
var _by_id: Dictionary = {}
var load_errors: Array[String] = []
var last_result: Dictionary = {}


func _init() -> void:
	_load_content()


func get_catalog() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for vehicle in _catalog:
		result.append(vehicle.duplicate(true))
	return result


func get_vehicle(vehicle_id: String) -> Dictionary:
	if not _by_id.has(vehicle_id):
		return {}
	return (_by_id[vehicle_id] as Dictionary).duplicate(true)


func get_owned(state) -> Dictionary:
	var runtime := _ensure_state(state)
	var current: Variant = runtime.get("current", {})
	if not current is Dictionary or current.is_empty():
		return {}
	var result: Dictionary = current.duplicate(true)
	var definition := get_vehicle(str(result.get("vehicle_id", "")))
	for key in definition:
		if not result.has(key):
			result[key] = definition[key]
	result["equity"] = maxi(0, int(result.get("current_value", 0)) - get_loan_balance(state))
	result["loan_balance"] = get_loan_balance(state)
	return result


func get_summary(state) -> Dictionary:
	var owned := get_owned(state)
	if owned.is_empty():
		return {
			"owned": false,
			"vehicle_value": 0,
			"loan_balance": 0,
			"equity": 0,
			"monthly_cost": 0,
			"weekly_fuel": 0,
			"arrears": 0,
		}
	var loan: Dictionary = owned.get("loan", {}) if owned.get("loan", {}) is Dictionary else {}
	return {
		"owned": true,
		"vehicle_id": str(owned.get("vehicle_id", "")),
		"name": str(owned.get("name", "Vehicle")),
		"vehicle_value": int(owned.get("current_value", 0)),
		"loan_balance": maxi(0, int(loan.get("balance", 0))),
		"equity": int(owned.get("current_value", 0)) - maxi(0, int(loan.get("balance", 0))),
		"monthly_payment": maxi(0, int(loan.get("monthly_payment", 0))),
		"insurance_monthly": maxi(0, int(owned.get("insurance_monthly", 0))),
		"maintenance_monthly": maxi(0, int(owned.get("maintenance_monthly", 0))),
		"monthly_cost": maxi(0, int(loan.get("monthly_payment", 0))) + maxi(0, int(owned.get("insurance_monthly", 0))) + maxi(0, int(owned.get("maintenance_monthly", 0))),
		"weekly_fuel": maxi(0, int(owned.get("fuel_weekly", 0))),
		"arrears": maxi(0, int(owned.get("arrears", 0))) + maxi(0, int(loan.get("arrears", 0))),
		"condition": clampi(int(owned.get("condition_score", 100)), 0, 100),
		"mileage": maxi(0, int(owned.get("mileage", 0))),
		"operational": bool(owned.get("operational", true)),
	}


func quote_cash_purchase(state, vehicle_id: String) -> Dictionary:
	var definition := get_vehicle(vehicle_id)
	if definition.is_empty():
		return {"valid": false, "vehicle_id": vehicle_id, "total": 0}
	var price := maxi(0, int(definition.get("purchase_price", 0)))
	var registration := maxi(180, _basis_point_amount(price, 125))
	var monthly_running := int(definition.get("insurance_monthly", 0)) + int(definition.get("maintenance_monthly", 0)) + roundi(float(int(definition.get("fuel_weekly", 0))) * 52.0 / 12.0)
	return {
		"valid": true,
		"vehicle_id": vehicle_id,
		"purchase_price": price,
		"registration_and_title": registration,
		"total": price + registration,
		"estimated_monthly_ownership": monthly_running,
		"cash_after": int(state.cash) - price - registration,
	}


func quote_finance(state, vehicle_id: String, down_payment_percent: int = -1) -> Dictionary:
	var definition := get_vehicle(vehicle_id)
	if definition.is_empty():
		return {"valid": false, "vehicle_id": vehicle_id, "due_today": 0}
	var price := maxi(0, int(definition.get("purchase_price", 0)))
	var minimum_percent := clampi(int(definition.get("minimum_down_payment_percent", 10)), 0, 100)
	var chosen_percent := minimum_percent if down_payment_percent < 0 else clampi(down_payment_percent, minimum_percent, 100)
	var down_payment := _basis_point_amount(price, chosen_percent * 100)
	var registration := maxi(180, _basis_point_amount(price, 125))
	var origination_fee := maxi(95, _basis_point_amount(price - down_payment, 100))
	var principal := maxi(0, price - down_payment)
	var term := maxi(1, int(definition.get("loan_term_months", 48)))
	var apr_bp := maxi(0, int(definition.get("apr_basis_points", 0)))
	var monthly_payment := _amortized_payment(principal, apr_bp, term)
	var monthly_running := int(definition.get("insurance_monthly", 0)) + int(definition.get("maintenance_monthly", 0)) + roundi(float(int(definition.get("fuel_weekly", 0))) * 52.0 / 12.0)
	return {
		"valid": true,
		"vehicle_id": vehicle_id,
		"purchase_price": price,
		"down_payment_percent": chosen_percent,
		"down_payment": down_payment,
		"registration_and_title": registration,
		"origination_fee": origination_fee,
		"due_today": down_payment + registration + origination_fee,
		"principal": principal,
		"apr_basis_points": apr_bp,
		"term_months": term,
		"monthly_payment": monthly_payment,
		"estimated_monthly_running": monthly_running,
		"estimated_monthly_ownership": monthly_payment + monthly_running,
		"estimated_total_payments": monthly_payment * term,
		"cash_after": int(state.cash) - down_payment - registration - origination_fee,
	}


func eligibility_details(state, vehicle_id: String, purchase_mode: String = "finance", down_payment_percent: int = -1) -> Dictionary:
	var reasons: Array[String] = []
	var definition := get_vehicle(vehicle_id)
	if definition.is_empty():
		reasons.append("That vehicle is no longer offered.")
		return {"eligible": false, "ok": false, "reasons": reasons}
	if not get_owned(state).is_empty():
		reasons.append("Sell your current vehicle before buying another one.")
	var driving_required := maxi(0, int(definition.get("minimum_driving_skill", 0)))
	if int(state.skills.get("driving", 0)) < driving_required:
		reasons.append("Requires driving %d; yours is %d." % [driving_required, int(state.skills.get("driving", 0))])
	var quote := quote_cash_purchase(state, vehicle_id) if purchase_mode == "cash" else quote_finance(state, vehicle_id, down_payment_percent)
	var due_today := int(quote.get("total", 0)) if purchase_mode == "cash" else int(quote.get("due_today", 0))
	if int(state.cash) < due_today:
		reasons.append("You need $%s today; you have $%s." % [_money(due_today), _money(int(state.cash))])
	if purchase_mode == "finance":
		var weekly_gross := maxi(0, int(state.employment.get("weekly_pay", 0)))
		var monthly_income := roundi(float(weekly_gross * 52) / 12.0)
		var payment := int(quote.get("estimated_monthly_ownership", quote.get("monthly_payment", 0)))
		if weekly_gross <= 0:
			reasons.append("Financing requires current employment.")
		elif payment > roundi(float(monthly_income) * 0.28):
			reasons.append("The estimated $%s monthly ownership cost is too high for your current income." % _money(payment))
	return {"eligible": reasons.is_empty(), "ok": reasons.is_empty(), "reasons": reasons, "reason": " ".join(reasons), "quote": quote}


func purchase_cash(state, vehicle_id: String, economy) -> String:
	var details := eligibility_details(state, vehicle_id, "cash")
	if not bool(details.get("eligible", false)):
		return str(details.get("reason", "That purchase is unavailable."))
	var definition := get_vehicle(vehicle_id)
	var quote: Dictionary = details.get("quote", {})
	economy.record(state, -int(quote.get("purchase_price", 0)), "Cash purchase — %s" % str(definition.get("name", "vehicle")), "vehicle_purchase")
	economy.record(state, -int(quote.get("registration_and_title", 0)), "Registration and title — %s" % str(definition.get("name", "vehicle")), "vehicle_registration")
	_set_current_vehicle(state, definition, {}, "cash")
	_set_owned_transport(state, economy)
	last_result = {"ok": true, "mode": "cash", "vehicle_id": vehicle_id, "quote": quote}
	return "Bought %s for cash. Insurance, fuel, and maintenance now apply." % str(definition.get("name", "the vehicle"))


func purchase_financed(state, vehicle_id: String, economy, down_payment_percent: int = -1) -> String:
	var details := eligibility_details(state, vehicle_id, "finance", down_payment_percent)
	if not bool(details.get("eligible", false)):
		return str(details.get("reason", "That financing offer is unavailable."))
	var definition := get_vehicle(vehicle_id)
	var quote: Dictionary = details.get("quote", {})
	economy.record(state, -int(quote.get("down_payment", 0)), "Vehicle down payment — %s" % str(definition.get("name", "vehicle")), "vehicle_down_payment")
	economy.record(state, -int(quote.get("registration_and_title", 0)), "Registration and title — %s" % str(definition.get("name", "vehicle")), "vehicle_registration")
	economy.record(state, -int(quote.get("origination_fee", 0)), "Auto loan origination fee", "vehicle_loan_fee")
	var loan := {
		"original_principal": int(quote.get("principal", 0)),
		"balance": int(quote.get("principal", 0)),
		"apr_basis_points": int(quote.get("apr_basis_points", 0)),
		"term_months": int(quote.get("term_months", 0)),
		"remaining_payments": int(quote.get("term_months", 0)),
		"monthly_payment": int(quote.get("monthly_payment", 0)),
		"arrears": 0,
		"missed_payments": 0,
		"last_payment_week": -1,
	}
	_set_current_vehicle(state, definition, loan, "finance")
	_set_owned_transport(state, economy)
	last_result = {"ok": true, "mode": "finance", "vehicle_id": vehicle_id, "quote": quote}
	return "Financed %s with $%s due today and a $%s monthly payment." % [str(definition.get("name", "the vehicle")), _money(int(quote.get("due_today", 0))), _money(int(quote.get("monthly_payment", 0)))]


func buy_cash(state, vehicle_id: String, economy) -> String:
	return purchase_cash(state, vehicle_id, economy)


func finance(state, vehicle_id: String, economy, down_payment_percent: int = -1) -> String:
	return purchase_financed(state, vehicle_id, economy, down_payment_percent)


func sell(state, economy) -> String:
	var runtime := _ensure_state(state)
	var current: Dictionary = runtime.get("current", {}) if runtime.get("current", {}) is Dictionary else {}
	if current.is_empty():
		return "You do not own a financed vehicle to sell."
	var name := str(current.get("name", "Vehicle"))
	var sale_price := maxi(0, int(current.get("current_value", 0)))
	var dealer_fee := _basis_point_amount(sale_price, 300)
	var loan: Dictionary = current.get("loan", {}) if current.get("loan", {}) is Dictionary else {}
	var payoff := maxi(0, int(loan.get("balance", 0))) + maxi(0, int(loan.get("arrears", 0)))
	var ownership_arrears := maxi(0, int(current.get("arrears", 0)))
	economy.record(state, sale_price, "Vehicle sale — %s" % name, "vehicle_sale")
	if dealer_fee > 0:
		economy.record(state, -dealer_fee, "Dealer sale fee — %s" % name, "vehicle_sale_fee")
	if payoff > 0:
		economy.record(state, -payoff, "Auto loan payoff — %s" % name, "vehicle_loan_payoff")
	if ownership_arrears > 0:
		economy.record(state, -ownership_arrears, "Past-due vehicle costs — %s" % name, "vehicle_arrears_payoff")
	if int(state.cash) < 0:
		var deficiency := -int(state.cash)
		state.debt += deficiency
		economy.record(state, deficiency, "Unsecured debt for vehicle payoff deficiency", "debt_draw")
	var history: Array = runtime.get("history", []) if runtime.get("history", []) is Array else []
	history.append({"vehicle_id": str(current.get("vehicle_id", "")), "ended_week": int(state.calendar.get("week_index", 0)), "reason": "sold", "sale_price": sale_price, "loan_payoff": payoff})
	runtime["history"] = history
	runtime["current"] = {}
	state.flags[STATE_FLAG] = runtime
	_set_public_transport(state, economy)
	last_result = {"ok": true, "sale_price": sale_price, "fee": dealer_fee, "payoff": payoff, "arrears_paid": ownership_arrears}
	return "Sold %s for $%s; fees and any loan payoff were itemized." % [name, _money(sale_price)]


func repair(state, economy) -> String:
	var runtime := _ensure_state(state)
	var current: Dictionary = runtime.get("current", {}) if runtime.get("current", {}) is Dictionary else {}
	if current.is_empty():
		return "You do not own a vehicle to repair."
	if bool(current.get("operational", true)):
		return "Your vehicle does not currently need an emergency repair."
	var cost := maxi(350, roundi(float(int(current.get("purchase_price", 0))) * 0.035))
	if int(state.cash) < cost:
		return "The repair costs $%s; you have $%s." % [_money(cost), _money(int(state.cash))]
	economy.record(state, -cost, "Repair — %s" % str(current.get("name", "vehicle")), "vehicle_repair")
	current["operational"] = true
	current["condition_score"] = mini(100, int(current.get("condition_score", 50)) + 18)
	runtime["current"] = current
	state.flags[STATE_FLAG] = runtime
	return "%s is operational again after a $%s repair." % [str(current.get("name", "Your vehicle")), _money(cost)]


func get_loan_balance(state) -> int:
	var runtime := _ensure_state(state)
	var current: Dictionary = runtime.get("current", {}) if runtime.get("current", {}) is Dictionary else {}
	var loan: Dictionary = current.get("loan", {}) if current.get("loan", {}) is Dictionary else {}
	return maxi(0, int(loan.get("balance", 0))) + maxi(0, int(loan.get("arrears", 0)))


func get_access_tags(state) -> Array[String]:
	var owned := get_owned(state)
	var result: Array[String] = []
	if owned.is_empty() or not bool(owned.get("operational", true)):
		return result
	var tags: Variant = owned.get("access_tags", [])
	if tags is Array:
		for tag in tags:
			if not str(tag).is_empty():
				result.append(str(tag))
	return result


func get_upcoming_costs(state) -> Array[Dictionary]:
	var owned := get_owned(state)
	if owned.is_empty():
		return []
	var result: Array[Dictionary] = []
	var days_until := _days_until_next_month(state.calendar)
	var due_in := "next week" if days_until <= 7 else "in %d days" % days_until
	var loan: Dictionary = owned.get("loan", {}) if owned.get("loan", {}) is Dictionary else {}
	if int(loan.get("balance", 0)) > 0:
		result.append({"id": "vehicle_payment", "name": "Auto loan payment", "label": "Auto loan payment", "amount": int(loan.get("monthly_payment", 0)) + int(loan.get("arrears", 0)), "due_in_days": days_until, "due_in": due_in})
	var monthly_pairs := [["vehicle_insurance", "Car insurance", int(owned.get("insurance_monthly", 0))], ["vehicle_maintenance", "Vehicle maintenance", int(owned.get("maintenance_monthly", 0))]]
	for pair in monthly_pairs:
		if int(pair[2]) > 0:
			result.append({"id": pair[0], "name": pair[1], "label": pair[1], "amount": pair[2], "due_in_days": days_until, "due_in": due_in})
	var fuel := maxi(0, int(owned.get("fuel_weekly", 0)))
	if fuel > 0:
		result.append({"id": "vehicle_fuel", "name": "Fuel or charging", "label": "Fuel or charging", "amount": fuel, "due_in_days": 7, "due_in": "next week"})
	return result


func process_week(state, economy) -> Array[String]:
	var summary: Array[String] = []
	var runtime := _ensure_state(state)
	var week_index := int(state.calendar.get("week_index", 0))
	if int(runtime.get("last_processed_week", 0)) >= week_index:
		return summary
	runtime["last_processed_week"] = week_index
	var current: Dictionary = runtime.get("current", {}) if runtime.get("current", {}) is Dictionary else {}
	if current.is_empty():
		state.flags[STATE_FLAG] = runtime
		return summary

	var employed := not str(state.employment.get("job_id", "")).is_empty()
	var finance_profile: Dictionary = state.flags.get("realistic_finances", {}) if state.flags.get("realistic_finances", {}) is Dictionary else {}
	var using_vehicle := str(finance_profile.get("transport_mode", "owned_vehicle")) == "owned_vehicle"
	var prior_ownership_arrears := maxi(0, int(current.get("arrears", 0)))
	if prior_ownership_arrears > 0 and int(state.cash) > 0:
		var arrears_payment := mini(prior_ownership_arrears, int(state.cash))
		economy.record(state, -arrears_payment, "Past-due vehicle costs — %s" % str(current.get("name", "vehicle")), "vehicle_overdue_payment")
		current["arrears"] = prior_ownership_arrears - arrears_payment
		summary.append("Paid $%s toward past-due vehicle costs; $%s remains." % [_money(arrears_payment), _money(int(current.get("arrears", 0)))])
	var fuel := maxi(0, int(current.get("fuel_weekly", 0)))
	if not using_vehicle or not employed:
		# A parked car still has personal errands and occasional charging/fuel use.
		fuel = roundi(float(fuel) * 0.35)
	if fuel > 0:
		var unpaid_fuel := _pay_available(state, economy, fuel, "Fuel or charging — %s" % str(current.get("name", "vehicle")), "vehicle_fuel")
		if unpaid_fuel > 0:
			current["arrears"] = int(current.get("arrears", 0)) + unpaid_fuel
			summary.append("Fuel cost $%s; $%s is now overdue." % [_money(fuel), _money(unpaid_fuel)])
		else:
			summary.append("%s fuel or charging cost $%s." % ["Commute" if using_vehicle and employed else "Personal", _money(fuel)])
	current["mileage"] = int(current.get("mileage", 0)) + (int(current.get("miles_per_work_week", 120)) if using_vehicle and employed else 35)

	var depreciation := maxi(0, int(current.get("weekly_depreciation_basis_points", 25)))
	current["current_value"] = maxi(roundi(float(int(current.get("purchase_price", 1))) * 0.18), int(current.get("current_value", 1)) - _basis_point_amount(int(current.get("current_value", 1)), depreciation))
	current["condition_score"] = maxi(15, int(current.get("condition_score", 100)) - (1 if week_index % 4 == 0 else 0))

	if _crossed_month_boundary(state):
		var before_monthly: Dictionary = current.duplicate(true)
		_process_monthly_vehicle_costs(state, economy, current, summary)
		if current.is_empty():
			var history: Array = runtime.get("history", []) if runtime.get("history", []) is Array else []
			history.append({
				"vehicle_id": str(before_monthly.get("vehicle_id", "")),
				"name": str(before_monthly.get("name", "Vehicle")),
				"ended_week": week_index,
				"reason": "repossessed",
				"value_at_end": int(before_monthly.get("current_value", 0)),
			})
			runtime["history"] = history
			runtime["current"] = {}
			state.flags[STATE_FLAG] = runtime
			return summary

	var reliability := clampi(int(current.get("reliability", 70)), 1, 100)
	var condition := clampi(int(current.get("condition_score", 100)), 0, 100)
	var breakdown_chance := 0.002 + float(100 - reliability) / 2500.0 + float(100 - condition) / 3000.0
	if bool(current.get("operational", true)) and state.randf_seeded() < breakdown_chance:
		current["operational"] = false
		state.stress = clampi(int(state.stress) + 6, 0, 100)
		economy.record(state, 0, "%s broke down and requires repair" % str(current.get("name", "Vehicle")), "vehicle_breakdown")
		summary.append("%s broke down. It cannot provide transport until repaired." % str(current.get("name", "Your vehicle")))

	runtime["current"] = current
	state.flags[STATE_FLAG] = runtime
	state.state_changed.emit()
	return summary


func _process_monthly_vehicle_costs(state, economy, current: Dictionary, summary: Array[String]) -> void:
	var loan: Dictionary = current.get("loan", {}) if current.get("loan", {}) is Dictionary else {}
	if int(loan.get("balance", 0)) > 0:
		var monthly_rate := float(int(loan.get("apr_basis_points", 0))) / 10000.0 / 12.0
		var interest := maxi(0, roundi(float(int(loan.get("balance", 0))) * monthly_rate))
		var scheduled := mini(int(loan.get("monthly_payment", 0)), int(loan.get("balance", 0)) + interest)
		var prior_arrears := maxi(0, int(loan.get("arrears", 0)))
		var due := scheduled + prior_arrears
		var unpaid := _pay_available(state, economy, due, "Auto loan payment — %s" % str(current.get("name", "vehicle")), "vehicle_payment")
		var paid := due - unpaid
		var paid_to_current := maxi(0, paid - prior_arrears)
		var principal_paid := maxi(0, paid_to_current - interest)
		loan["balance"] = maxi(0, int(loan.get("balance", 0)) - principal_paid)
		loan["arrears"] = unpaid
		loan["last_interest"] = interest
		loan["last_principal"] = principal_paid
		loan["last_payment_week"] = int(state.calendar.get("week_index", 0))
		if unpaid > 0:
			loan["missed_payments"] = int(loan.get("missed_payments", 0)) + 1
			state.reputation = clampi(int(state.reputation) - 2, -100, 100)
			state.stress = clampi(int(state.stress) + 5, 0, 100)
			economy.record(state, 0, "Auto payment overdue: $%s" % _money(unpaid), "vehicle_payment_overdue")
			summary.append("Auto payment: $%s paid, $%s overdue." % [_money(paid), _money(unpaid)])
		else:
			loan["missed_payments"] = 0
			loan["remaining_payments"] = maxi(0, int(loan.get("remaining_payments", 1)) - 1)
			summary.append("Auto payment $%s: $%s interest and $%s principal." % [_money(paid), _money(interest), _money(principal_paid)])
		if int(loan.get("balance", 0)) <= 0 and int(loan.get("arrears", 0)) <= 0:
			loan = {}
			economy.record(state, 0, "Auto loan paid in full — %s" % str(current.get("name", "vehicle")), "vehicle_loan_complete")
			summary.append("The vehicle loan is paid in full.")
	current["loan"] = loan

	var insurance := maxi(0, int(current.get("insurance_monthly", 0)))
	if insurance > 0:
		var unpaid_insurance := _pay_available(state, economy, insurance, "Car insurance — %s" % str(current.get("name", "vehicle")), "vehicle_insurance")
		if unpaid_insurance > 0:
			current["arrears"] = int(current.get("arrears", 0)) + unpaid_insurance
			current["insurance_lapsed"] = true
			economy.record(state, 0, "Insurance balance overdue: $%s" % _money(unpaid_insurance), "vehicle_insurance_overdue")
			summary.append("Car insurance has an overdue $%s balance and coverage lapsed." % _money(unpaid_insurance))
		else:
			current["insurance_lapsed"] = false
			summary.append("Car insurance cost $%s." % _money(insurance))

	var maintenance := maxi(0, int(current.get("maintenance_monthly", 0)))
	if maintenance > 0:
		var unpaid_maintenance := _pay_available(state, economy, maintenance, "Routine vehicle maintenance — %s" % str(current.get("name", "vehicle")), "vehicle_maintenance")
		if unpaid_maintenance > 0:
			current["arrears"] = int(current.get("arrears", 0)) + unpaid_maintenance
			current["condition_score"] = maxi(10, int(current.get("condition_score", 100)) - 4)
			summary.append("You deferred $%s of vehicle maintenance; condition declined." % _money(unpaid_maintenance))
		else:
			current["condition_score"] = mini(100, int(current.get("condition_score", 100)) + 1)
			summary.append("Routine vehicle maintenance cost $%s." % _money(maintenance))

	if not loan.is_empty() and int(loan.get("missed_payments", 0)) >= 3:
		var name := str(current.get("name", "Your vehicle"))
		economy.record(state, 0, "%s was repossessed after three missed payments" % name, "vehicle_repossession")
		state.reputation = clampi(int(state.reputation) - 8, -100, 100)
		state.stress = clampi(int(state.stress) + 15, 0, 100)
		var remaining_debt := maxi(0, int(loan.get("balance", 0)) - int(current.get("current_value", 0))) + maxi(0, int(loan.get("arrears", 0)))
		if remaining_debt > 0:
			state.debt += remaining_debt
			economy.record(state, 0, "Repossession deficiency became unsecured debt: $%s" % _money(remaining_debt), "vehicle_repossession_debt")
		current.clear()
		_set_public_transport(state, economy)
		summary.append("%s was repossessed. Any loan deficiency became unsecured debt." % name)


func _pay_available(state, economy, amount: int, reason: String, category: String) -> int:
	var paid := mini(maxi(0, amount), maxi(0, int(state.cash)))
	if paid > 0:
		economy.record(state, -paid, reason, category)
	return maxi(0, amount - paid)


func _set_current_vehicle(state, definition: Dictionary, loan: Dictionary, mode: String) -> void:
	var runtime := _ensure_state(state)
	runtime["current"] = {
		"vehicle_id": str(definition.get("id", "")),
		"name": str(definition.get("name", "Vehicle")),
		"purchase_mode": mode,
		"purchase_week": int(state.calendar.get("week_index", 0)),
		"purchase_price": int(definition.get("purchase_price", 0)),
		"current_value": int(definition.get("purchase_price", 0)),
		"condition_score": 100,
		"mileage": 0,
		"operational": true,
		"insurance_lapsed": false,
		"arrears": 0,
		"loan": loan.duplicate(true),
		"insurance_monthly": int(definition.get("insurance_monthly", 0)),
		"fuel_weekly": int(definition.get("fuel_weekly", 0)),
		"maintenance_monthly": int(definition.get("maintenance_monthly", 0)),
		"reliability": int(definition.get("reliability", 70)),
		"weekly_depreciation_basis_points": int(definition.get("weekly_depreciation_basis_points", 25)),
		"miles_per_work_week": int(definition.get("miles_per_work_week", 120)),
		"access_tags": definition.get("access_tags", []).duplicate(),
	}
	state.flags[STATE_FLAG] = runtime
	state.state_changed.emit()


func _set_owned_transport(state, economy) -> void:
	if economy != null and economy.has_method("set_transport_mode"):
		var current_mode := ""
		if economy.has_method("get_financial_profile"):
			current_mode = str(economy.get_financial_profile(state).get("transport_mode", ""))
		if current_mode != "travel_managed":
			economy.set_transport_mode(state, "owned_vehicle")


func _set_public_transport(state, economy) -> void:
	if economy != null and economy.has_method("set_transport_mode"):
		var current_mode := ""
		if economy.has_method("get_financial_profile"):
			current_mode = str(economy.get_financial_profile(state).get("transport_mode", ""))
		if current_mode != "travel_managed":
			economy.set_transport_mode(state, "public_transit")


func _ensure_state(state) -> Dictionary:
	var raw: Variant = state.flags.get(STATE_FLAG, {})
	var runtime: Dictionary = raw.duplicate(true) if raw is Dictionary else {}
	runtime["version"] = STATE_VERSION
	if not runtime.get("current") is Dictionary:
		runtime["current"] = {}
	if not runtime.get("history") is Array:
		runtime["history"] = []
	if not runtime.has("last_processed_week"):
		runtime["last_processed_week"] = maxi(0, int(state.calendar.get("week_index", 0)) - 1)
	else:
		runtime["last_processed_week"] = maxi(0, int(runtime.get("last_processed_week", 0)))
	state.flags[STATE_FLAG] = runtime
	return runtime


func _amortized_payment(principal: int, apr_basis_points: int, months: int) -> int:
	if principal <= 0:
		return 0
	if months <= 0:
		return principal
	var monthly_rate := float(maxi(0, apr_basis_points)) / 10000.0 / 12.0
	if monthly_rate <= 0.0:
		return ceili(float(principal) / float(months))
	var factor := pow(1.0 + monthly_rate, float(months))
	return maxi(1, ceili(float(principal) * monthly_rate * factor / (factor - 1.0)))


func _basis_point_amount(amount: int, basis_points: int) -> int:
	if amount <= 0 or basis_points <= 0:
		return 0
	return maxi(0, roundi(float(amount) * float(basis_points) / 10000.0))


func _crossed_month_boundary(state) -> bool:
	var boundary: Variant = state.flags.get("last_calendar_boundary", {})
	var week_index := int(state.calendar.get("week_index", 0))
	if boundary is Dictionary and int(boundary.get("to_week_index", -1)) == week_index:
		var months: Variant = boundary.get("month_boundaries", [])
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


func _money(value: int) -> String:
	var raw := str(absi(value))
	var formatted := ""
	while raw.length() > 3:
		formatted = "," + raw.right(3) + formatted
		raw = raw.left(raw.length() - 3)
	formatted = raw + formatted
	return ("-" if value < 0 else "") + formatted


func _load_content() -> void:
	_catalog.clear()
	_by_id.clear()
	load_errors.clear()
	if not FileAccess.file_exists(DATA_PATH):
		load_errors.append("Vehicle catalog is missing: %s" % DATA_PATH)
		push_error(load_errors[-1])
		return
	var file := FileAccess.open(DATA_PATH, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text()) if file != null else null
	if not parsed is Dictionary or not parsed.get("vehicles", []) is Array:
		load_errors.append("Vehicle catalog must contain a vehicles array.")
		push_error(load_errors[-1])
		return
	for raw_vehicle in parsed.get("vehicles", []):
		if not raw_vehicle is Dictionary:
			continue
		var vehicle: Dictionary = raw_vehicle.duplicate(true)
		var vehicle_id := str(vehicle.get("id", "")).strip_edges()
		if vehicle_id.is_empty() or _by_id.has(vehicle_id) or int(vehicle.get("purchase_price", 0)) <= 0:
			load_errors.append("Vehicle has an invalid or duplicate ID: %s" % vehicle_id)
			continue
		_by_id[vehicle_id] = vehicle
		_catalog.append(vehicle)
	for error_text in load_errors:
		push_error(error_text)
