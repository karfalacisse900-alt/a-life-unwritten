class_name EconomySystem
extends RefCounted

## Integer-dollar accounting and scheduled financial processing. Positive ledger
## amounts are income; negative amounts are expenses.

const BUSINESS_SYSTEM_PATH := "res://scripts/systems/BusinessSystem.gd"
const VEHICLE_FINANCE_SYSTEM_PATH := "res://scripts/systems/VehicleFinanceSystem.gd"
const REALISTIC_FINANCES_FLAG := "realistic_finances"
const PAYROLL_VERSION := 1
const DEFAULT_TAX_RATES := {
	"state_basis_points": 325,
	"city_basis_points": 125,
	"payroll_basis_points": 765,
}
const DEFAULT_LIVING_COSTS := {
	"phone": {"name": "Mobile phone plan", "amount": 72, "category": "phone_bill", "active": true},
	"groceries": {"name": "Groceries and household food", "amount": 380, "category": "groceries", "active": true},
	"household": {"name": "Household essentials", "amount": 85, "category": "basic_living", "active": true},
	"healthcare": {"name": "Health and pharmacy budget", "amount": 65, "category": "healthcare", "active": true},
}


func record(state: LifeGameState, amount: int, reason: String, category: String) -> Dictionary:
	var clean_reason := reason.strip_edges()
	if clean_reason.is_empty():
		clean_reason = "Transaction"
	var clean_category := category.strip_edges()
	if clean_category.is_empty():
		clean_category = "other"

	state.cash += int(amount)
	var sequence := maxi(int(state.flags.get("ledger_sequence", state.ledger.size())), state.ledger.size()) + 1
	state.flags["ledger_sequence"] = sequence
	var entry := {
		"id": sequence,
		"week_index": int(state.calendar.get("week_index", 0)),
		"date": _date_key(state.calendar),
		"amount": int(amount),
		"balance_after": state.cash,
		"reason": clean_reason.left(160),
		"category": clean_category.left(80),
		"account": "cash",
	}
	state.ledger.append(entry)
	state.state_changed.emit()
	return entry


## Idempotent for a given calendar.week_index. CalendarSystem must advance first.
## `content` accepts the combined catalog or a housing catalog directly.
func process_week(state: LifeGameState, content: Variant = {}) -> Array[String]:
	var summary: Array[String] = []
	var week_index := int(state.calendar.get("week_index", 0))
	var last_processed := int(state.flags.get("last_economy_week_index", 0))
	if week_index <= last_processed:
		return summary

	# Claim the week before invoking another system. A nested UI callback therefore
	# cannot duplicate wages or expenses for the same date.
	state.flags["last_economy_week_index"] = week_index

	_process_employment_income(state, summary)
	if is_realistic_finances_enabled(state):
		_process_overdue_obligations(state, summary)
	summary.append_array(_process_business(state))
	_process_market_prices(state, summary)
	_process_mining(state, content, summary)

	var month_boundaries := _month_boundaries_for_week(state)
	for billing_month in month_boundaries:
		_process_monthly_obligations(state, content, billing_month, summary)

	summary.append_array(_process_vehicle_finance(state))

	# Defensive recovery for imported/legacy states. Normal obligations already use
	# explicit credit draws and end at a zero cash balance when funds run short.
	if state.cash < 0:
		var legacy_shortfall := -state.cash
		state.debt += legacy_shortfall
		record(state, legacy_shortfall, "Emergency credit covered a negative balance", "debt_draw")
		summary.append("A $%d negative balance became debt." % legacy_shortfall)

	state.last_week_summary = summary.duplicate()
	state.state_changed.emit()
	return summary


func _process_employment_income(state: LifeGameState, summary: Array[String]) -> void:
	if is_realistic_finances_enabled(state):
		_process_biweekly_payroll(state, summary)
		return

	var job_id := str(state.employment.get("job_id", ""))
	var weekly_pay := maxi(0, int(state.employment.get("weekly_pay", 0)))
	var incarcerated := bool(state.crime.get("in_jail", false))
	var suspended := bool(state.employment.get("suspended", false))
	if not job_id.is_empty() and weekly_pay > 0 and not incarcerated and not suspended:
		var title := str(state.employment.get("title", "your job"))
		record(state, weekly_pay, "Weekly pay — %s" % title, "employment_income")
		summary.append("Work paid $%d from %s." % [weekly_pay, title])
	elif incarcerated and not job_id.is_empty():
		summary.append("Your job did not pay while you were in jail.")
	elif suspended and not job_id.is_empty():
		summary.append("Your suspended job did not pay this week.")
	else:
		summary.append("No employment income arrived this week.")


## Enables the detailed economy without changing legacy/imported saves silently.
## `options` may include city_id, city_name, cost_index_basis_points,
## tax_rates, living_costs, transport_mode, local_tax_managed_externally, and
## first_paycheck_wait_weeks. Use transport_mode="travel_managed" when the
## TravelSystem owns fares/fuel/passes/parking/insurance and local payroll tax.
func enable_realistic_finances(state: LifeGameState, options: Dictionary = {}) -> Dictionary:
	var existing: Variant = state.flags.get(REALISTIC_FINANCES_FLAG, {})
	var profile: Dictionary = existing.duplicate(true) if existing is Dictionary else {}
	profile["version"] = 1
	profile["enabled"] = true
	profile["city_id"] = str(options.get("city_id", profile.get("city_id", "bellwether"))).strip_edges()
	profile["city_name"] = str(options.get("city_name", profile.get("city_name", "Bellwether"))).strip_edges()
	profile["cost_index_basis_points"] = clampi(int(options.get("cost_index_basis_points", profile.get("cost_index_basis_points", 10000))), 5000, 25000)
	profile["transport_mode"] = str(options.get("transport_mode", profile.get("transport_mode", "public_transit")))
	profile["local_tax_managed_externally"] = bool(options.get("local_tax_managed_externally", profile.get("local_tax_managed_externally", profile["transport_mode"] == "travel_managed")))

	var tax_rates: Dictionary = DEFAULT_TAX_RATES.duplicate(true)
	var saved_taxes: Variant = profile.get("tax_rates", {})
	if saved_taxes is Dictionary:
		for key in saved_taxes:
			tax_rates[str(key)] = int(saved_taxes[key])
	var option_taxes: Variant = options.get("tax_rates", {})
	if option_taxes is Dictionary:
		for key in option_taxes:
			tax_rates[str(key)] = int(option_taxes[key])
	for key in tax_rates:
		tax_rates[key] = clampi(int(tax_rates[key]), 0, 3000)
	profile["tax_rates"] = tax_rates

	var living_costs: Dictionary = DEFAULT_LIVING_COSTS.duplicate(true)
	var saved_costs: Variant = profile.get("living_costs", {})
	if saved_costs is Dictionary:
		_merge_living_costs(living_costs, saved_costs)
	var option_costs: Variant = options.get("living_costs", {})
	if option_costs is Dictionary:
		_merge_living_costs(living_costs, option_costs)
	profile["living_costs"] = living_costs

	var week_index := int(state.calendar.get("week_index", 0))
	var wait_weeks := clampi(int(options.get("first_paycheck_wait_weeks", profile.get("first_paycheck_wait_weeks", 1))), 1, 2)
	profile["first_paycheck_wait_weeks"] = wait_weeks
	var payroll_raw: Variant = profile.get("payroll", {})
	var payroll: Dictionary = payroll_raw.duplicate(true) if payroll_raw is Dictionary else {}
	payroll["version"] = PAYROLL_VERSION
	payroll["cadence_weeks"] = 2
	payroll["next_pay_week"] = maxi(week_index + wait_weeks, int(payroll.get("next_pay_week", week_index + wait_weeks)))
	payroll["last_accrual_week"] = int(payroll.get("last_accrual_week", week_index))
	payroll["last_pay_week"] = int(payroll.get("last_pay_week", -1))
	payroll["accrued_gross"] = maxi(0, int(payroll.get("accrued_gross", 0)))
	payroll["accrued_weeks"] = maxi(0, int(payroll.get("accrued_weeks", 0)))
	payroll["ytd_gross"] = maxi(0, int(payroll.get("ytd_gross", 0)))
	payroll["ytd_withheld"] = maxi(0, int(payroll.get("ytd_withheld", 0)))
	payroll["ytd_net"] = maxi(0, int(payroll.get("ytd_net", 0)))
	profile["payroll"] = payroll
	if not profile.has("overdue_obligations") or not profile.get("overdue_obligations") is Array:
		profile["overdue_obligations"] = []
	state.flags[REALISTIC_FINANCES_FLAG] = profile
	state.state_changed.emit()
	return get_financial_profile(state)


func disable_realistic_finances(state: LifeGameState) -> void:
	var profile := _realistic_profile(state)
	profile["enabled"] = false
	state.flags[REALISTIC_FINANCES_FLAG] = profile
	state.state_changed.emit()


func is_realistic_finances_enabled(state: LifeGameState) -> bool:
	var raw: Variant = state.flags.get(REALISTIC_FINANCES_FLAG, {})
	return raw is Dictionary and bool(raw.get("enabled", false))


## Updates local tax/cost context after travel without resetting payroll history.
func configure_city_context(state: LifeGameState, context: Dictionary) -> Dictionary:
	if not is_realistic_finances_enabled(state):
		enable_realistic_finances(state)
	var profile := _realistic_profile(state)
	for key in ["city_id", "city_name", "transport_mode"]:
		if context.has(key):
			profile[key] = str(context[key]).strip_edges()
	if context.has("local_tax_managed_externally"):
		profile["local_tax_managed_externally"] = bool(context["local_tax_managed_externally"])
	elif str(context.get("transport_mode", "")) == "travel_managed":
		profile["local_tax_managed_externally"] = true
	if context.has("cost_index_basis_points"):
		profile["cost_index_basis_points"] = clampi(int(context["cost_index_basis_points"]), 5000, 25000)
	if context.get("tax_rates") is Dictionary:
		var rates: Dictionary = profile.get("tax_rates", DEFAULT_TAX_RATES.duplicate(true))
		for key in context["tax_rates"]:
			rates[str(key)] = clampi(int(context["tax_rates"][key]), 0, 3000)
		profile["tax_rates"] = rates
	if context.get("living_costs") is Dictionary:
		var costs: Dictionary = profile.get("living_costs", DEFAULT_LIVING_COSTS.duplicate(true))
		_merge_living_costs(costs, context["living_costs"])
		profile["living_costs"] = costs
	state.flags[REALISTIC_FINANCES_FLAG] = profile
	state.state_changed.emit()
	return get_financial_profile(state)


func set_transport_mode(state: LifeGameState, mode: String) -> String:
	var allowed := ["public_transit", "owned_vehicle", "walk_cycle", "rideshare", "travel_managed"]
	if not allowed.has(mode):
		return "Choose a supported transport option."
	if not is_realistic_finances_enabled(state):
		enable_realistic_finances(state)
	var profile := _realistic_profile(state)
	profile["transport_mode"] = mode
	if mode == "travel_managed":
		profile["local_tax_managed_externally"] = true
	state.flags[REALISTIC_FINANCES_FLAG] = profile
	state.state_changed.emit()
	return "Primary transport changed to %s." % mode.replace("_", " ")


func set_living_cost(state: LifeGameState, cost_id: String, amount: int, active: bool = true) -> Dictionary:
	if cost_id.strip_edges().is_empty():
		return {"ok": false, "reason": "A stable cost ID is required."}
	if not is_realistic_finances_enabled(state):
		enable_realistic_finances(state)
	var profile := _realistic_profile(state)
	var costs: Dictionary = profile.get("living_costs", DEFAULT_LIVING_COSTS.duplicate(true))
	var prior: Dictionary = costs.get(cost_id, {}) if costs.get(cost_id, {}) is Dictionary else {}
	prior["name"] = str(prior.get("name", cost_id.replace("_", " ").capitalize()))
	prior["amount"] = maxi(0, amount)
	prior["category"] = str(prior.get("category", cost_id))
	prior["active"] = active
	costs[cost_id] = prior
	profile["living_costs"] = costs
	state.flags[REALISTIC_FINANCES_FLAG] = profile
	state.state_changed.emit()
	return {"ok": true, "cost": prior.duplicate(true)}


func get_financial_profile(state: LifeGameState) -> Dictionary:
	var profile := _realistic_profile(state)
	var result := profile.duplicate(true)
	result["enabled"] = is_realistic_finances_enabled(state)
	result["paycheck"] = get_paycheck_preview(state)
	result["overdue_total"] = get_overdue_total(state)
	return result


func get_paycheck_preview(state: LifeGameState) -> Dictionary:
	var profile := _realistic_profile(state)
	var payroll: Dictionary = profile.get("payroll", {}) if profile.get("payroll", {}) is Dictionary else {}
	var weekly_gross := maxi(0, int(state.employment.get("weekly_pay", 0)))
	var cadence := maxi(1, int(payroll.get("cadence_weeks", 2)))
	var gross := weekly_gross * cadence
	var deductions := _payroll_deductions(gross, profile, cadence)
	var total_withheld := 0
	for amount in deductions.values():
		total_withheld += int(amount)
	return {
		"weekly_gross": weekly_gross,
		"annual_gross": weekly_gross * 52,
		"cadence_weeks": cadence,
		"gross": gross,
		"deductions": deductions,
		"total_withheld": total_withheld,
		"estimated_net": maxi(0, gross - total_withheld),
		"next_pay_week": int(payroll.get("next_pay_week", int(state.calendar.get("week_index", 0)) + 1)),
		"accrued_gross": maxi(0, int(payroll.get("accrued_gross", 0))),
		"accrued_weeks": maxi(0, int(payroll.get("accrued_weeks", 0))),
	}


func get_overdue_obligations(state: LifeGameState) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var profile := _realistic_profile(state)
	var raw: Variant = profile.get("overdue_obligations", [])
	if raw is Array:
		for item in raw:
			if item is Dictionary and int(item.get("amount", 0)) > 0:
				result.append(item.duplicate(true))
	return result


func get_overdue_total(state: LifeGameState) -> int:
	var total := 0
	for item in get_overdue_obligations(state):
		total += maxi(0, int(item.get("amount", 0)))
	return total


func _process_biweekly_payroll(state: LifeGameState, summary: Array[String]) -> void:
	var profile := _realistic_profile(state)
	var payroll: Dictionary = profile.get("payroll", {}) if profile.get("payroll", {}) is Dictionary else {}
	var week_index := int(state.calendar.get("week_index", 0))
	if int(payroll.get("last_accrual_week", -1)) >= week_index:
		return
	payroll["last_accrual_week"] = week_index

	var job_id := str(state.employment.get("job_id", ""))
	var weekly_pay := maxi(0, int(state.employment.get("weekly_pay", 0)))
	var incarcerated := bool(state.crime.get("in_jail", false))
	var suspended := bool(state.employment.get("suspended", false))
	if not job_id.is_empty() and weekly_pay > 0 and not incarcerated and not suspended:
		payroll["accrued_gross"] = int(payroll.get("accrued_gross", 0)) + weekly_pay
		payroll["accrued_weeks"] = int(payroll.get("accrued_weeks", 0)) + 1
		payroll["latest_job_id"] = job_id
		payroll["latest_job_title"] = str(state.employment.get("title", "your job"))
	else:
		if incarcerated and not job_id.is_empty():
			summary.append("No wages accrued while you were in jail.")
		elif suspended and not job_id.is_empty():
			summary.append("No wages accrued while your job was suspended.")
		else:
			summary.append("No employment wages accrued this week.")

	var next_pay_week := int(payroll.get("next_pay_week", week_index))
	var accrued_gross := maxi(0, int(payroll.get("accrued_gross", 0)))
	if week_index >= next_pay_week:
		if accrued_gross > 0:
			_post_paycheck(state, profile, payroll, summary)
		else:
			summary.append("Payday passed with no earned wages to deposit.")
		payroll["next_pay_week"] = week_index + maxi(1, int(payroll.get("cadence_weeks", 2)))
	profile["payroll"] = payroll
	state.flags[REALISTIC_FINANCES_FLAG] = profile


func _post_paycheck(state: LifeGameState, profile: Dictionary, payroll: Dictionary, summary: Array[String]) -> void:
	var gross := maxi(0, int(payroll.get("accrued_gross", 0)))
	var earned_weeks := maxi(1, int(payroll.get("accrued_weeks", 1)))
	var title := str(payroll.get("latest_job_title", state.employment.get("title", "your job")))
	var deductions := _payroll_deductions(gross, profile, earned_weeks)
	var gross_entry := record(state, gross, "Gross paycheck — %s (%d week%s)" % [title, earned_weeks, "" if earned_weeks == 1 else "s"], "employment_income")
	gross_entry["gross_pay"] = gross
	gross_entry["gross_amount"] = gross
	gross_entry["pay_period_weeks"] = earned_weeks
	state.ledger[state.ledger.size() - 1] = gross_entry
	var total_withheld := 0
	var labels := {
		"federal_tax": "Federal income tax withholding",
		"state_tax": "State income tax withholding",
		"city_tax": "City income tax withholding",
		"payroll_tax": "Social insurance and payroll tax",
	}
	for category in ["federal_tax", "state_tax", "city_tax", "payroll_tax"]:
		var amount := maxi(0, int(deductions.get(category, 0)))
		if amount <= 0:
			continue
		record(state, -amount, str(labels[category]), category)
		total_withheld += amount
	var net := maxi(0, gross - total_withheld)
	var net_entry := record(state, 0, "Net paycheck deposited: $%d" % net, "paycheck_net")
	net_entry["gross_pay"] = gross
	net_entry["total_withheld"] = total_withheld
	net_entry["net_pay"] = net
	net_entry["deductions"] = deductions.duplicate(true)
	state.ledger[state.ledger.size() - 1] = net_entry
	payroll["last_pay_week"] = int(state.calendar.get("week_index", 0))
	payroll["last_gross"] = gross
	payroll["last_withheld"] = total_withheld
	payroll["last_net"] = net
	payroll["ytd_gross"] = int(payroll.get("ytd_gross", 0)) + gross
	payroll["ytd_withheld"] = int(payroll.get("ytd_withheld", 0)) + total_withheld
	payroll["ytd_net"] = int(payroll.get("ytd_net", 0)) + net
	payroll["accrued_gross"] = 0
	payroll["accrued_weeks"] = 0
	summary.append("Biweekly paycheck: $%d gross − $%d tax = $%d deposited." % [gross, total_withheld, net])


func _payroll_deductions(gross: int, profile: Dictionary, pay_period_weeks: int = 2) -> Dictionary:
	var rates: Dictionary = profile.get("tax_rates", DEFAULT_TAX_RATES) if profile.get("tax_rates", DEFAULT_TAX_RATES) is Dictionary else DEFAULT_TAX_RATES
	var annualized := roundi(float(gross) * 52.0 / float(maxi(1, pay_period_weeks)))
	var federal_bp := _federal_tax_basis_points(annualized)
	return {
		"federal_tax": _basis_point_amount(gross, federal_bp),
		"state_tax": _basis_point_amount(gross, int(rates.get("state_basis_points", 325))),
		"city_tax": 0 if bool(profile.get("local_tax_managed_externally", false)) else _basis_point_amount(gross, int(rates.get("city_basis_points", 125))),
		"payroll_tax": _basis_point_amount(gross, int(rates.get("payroll_basis_points", 765))),
	}


func _federal_tax_basis_points(annualized_income: int) -> int:
	if annualized_income <= 15_000:
		return 0
	if annualized_income <= 30_000:
		return 350
	if annualized_income <= 55_000:
		return 650
	if annualized_income <= 100_000:
		return 1000
	if annualized_income <= 180_000:
		return 1450
	return 1900


func _process_business(state: LifeGameState) -> Array[String]:
	var result: Array[String] = []
	if not bool(state.business.get("active", false)):
		return result
	var week_index := int(state.calendar.get("week_index", 0))
	if int(state.business.get("last_processed_week", 0)) >= week_index:
		return result

	if ResourceLoader.exists(BUSINESS_SYSTEM_PATH):
		var script: Script = load(BUSINESS_SYSTEM_PATH)
		var system: Variant = script.new()
		var external_result: Variant = system.process_week(state, self)
		if external_result is Array:
			for line in external_result:
				result.append(str(line))
		return result

	# Small deterministic fallback keeps saves functional if optional business
	# content is absent during development. BusinessSystem supersedes this branch.
	var price := maxi(1, int(state.business.get("price", 12)))
	var capacity := maxi(1, int(state.business.get("capacity", 45)))
	var demand := clampi(int(state.business.get("demand", 50)), 0, 100)
	var customers := mini(capacity, maxi(0, roundi(float(capacity * demand) / 100.0 + state.randf_seeded() * 8.0 - 4.0)))
	var revenue := customers * price
	var expenses := maxi(60, 90 + int(state.business.get("staff", 0)) * 180 + int(state.business.get("marketing_budget", 0)) + int(state.business.get("maintenance_budget", 0)))
	if revenue > 0:
		record(state, revenue, "%s sales" % str(state.business.get("name", "Small business")), "business_revenue")
	_charge_obligation(state, expenses, "%s operating costs" % str(state.business.get("name", "Small business")), "business_expense", result)
	state.business["last_customers"] = customers
	state.business["last_revenue"] = revenue
	state.business["last_expenses"] = expenses
	state.business["lifetime_profit"] = int(state.business.get("lifetime_profit", 0)) + revenue - expenses
	state.business["weeks"] = int(state.business.get("weeks", 0)) + 1
	state.business["last_processed_week"] = week_index
	result.append("%s served %d customers: $%d revenue before $%d costs." % [str(state.business.get("name", "Your business")), customers, revenue, expenses])
	return result


func _process_market_prices(state: LifeGameState, summary: Array[String]) -> void:
	var coins_value: Variant = state.crypto.get("coins", {})
	if not coins_value is Dictionary:
		return
	var coins: Dictionary = coins_value
	var coin_ids: Array = coins.keys()
	coin_ids.sort()
	var news: Array = []
	for raw_coin_id in coin_ids:
		var coin_id := str(raw_coin_id)
		if not coins[raw_coin_id] is Dictionary:
			continue
		var coin: Dictionary = coins[raw_coin_id].duplicate(true)
		var old_price := maxi(1, int(coin.get("price", 1)))
		# Holdings are intentionally absent from this equation: the market evolves
		# independently of the player's trades.
		var random_change := (state.randf_seeded() * 20.0) - 10.0
		var new_price := maxi(1, roundi(float(old_price) * (1.0 + random_change / 100.0)))
		coin["price"] = new_price
		var history: Array = coin.get("price_history", [])
		history.append(new_price)
		if history.size() > 104:
			history.pop_front()
		coin["price_history"] = history
		coins[raw_coin_id] = coin
		if absf(random_change) >= 7.5:
			var direction := "rose" if new_price >= old_price else "fell"
			news.append("%s %s to $%d." % [str(coin.get("name", coin_id)), direction, new_price])
	state.crypto["coins"] = coins
	state.crypto["market_news"] = news
	if not news.is_empty():
		summary.append(str(news[0]))


func _process_mining(state: LifeGameState, content: Variant, summary: Array[String]) -> void:
	var mining_value: Variant = state.crypto.get("mining", {})
	if not mining_value is Dictionary:
		return
	var mining: Dictionary = mining_value
	var week_index := int(state.calendar.get("week_index", 0))
	if int(mining.get("last_processed_week", 0)) >= week_index:
		return
	mining["last_processed_week"] = week_index

	var rigs := maxi(0, int(mining.get("rigs", 0)))
	if rigs <= 0:
		state.crypto["mining"] = mining
		return
	var broken_rigs := clampi(int(mining.get("broken_rigs", 0)), 0, rigs)
	var allowed_rigs := _housing_mining_limit(state, content)
	var active_rigs := mini(maxi(0, rigs - broken_rigs), allowed_rigs)
	if active_rigs <= 0:
		summary.append("Your mining rigs stayed offline: this home lacks usable mining space.")
		state.crypto["mining"] = mining
		return

	var power_cost_total := maxi(0, int(mining.get("weekly_power_cost", 0)))
	var scaled_power_cost := roundi(float(power_cost_total * active_rigs) / float(maxi(1, rigs)))
	if scaled_power_cost > 0:
		_charge_obligation(state, scaled_power_cost, "Mining electricity", "mining_power", summary)

	var yield_total := maxi(0, int(mining.get("weekly_yield_milli", 0)))
	var coin_yield := roundi(float(yield_total * active_rigs) / float(maxi(1, rigs)))
	var coin_id := str(mining.get("coin_id", "lumen"))
	var coins: Dictionary = state.crypto.get("coins", {})
	if coins.has(coin_id) and coins[coin_id] is Dictionary and coin_yield > 0:
		var coin: Dictionary = coins[coin_id].duplicate(true)
		var price := maxi(1, int(coin.get("price", 1)))
		if bool(mining.get("auto_sell", false)):
			var proceeds := roundi(float(coin_yield * price) / 1000.0)
			if proceeds > 0:
				record(state, proceeds, "Auto-sold mined %s" % str(coin.get("symbol", coin_id)), "mining_income")
			summary.append("Mining produced %.3f %s and auto-sold it for $%d." % [float(coin_yield) / 1000.0, str(coin.get("symbol", coin_id)), proceeds])
		else:
			coin["holdings_milli"] = maxi(0, int(coin.get("holdings_milli", 0))) + coin_yield
			coins[coin_id] = coin
			state.crypto["coins"] = coins
			summary.append("Mining added %.3f %s to your holdings." % [float(coin_yield) / 1000.0, str(coin.get("symbol", coin_id))])

	var maintenance := clampi(int(mining.get("maintenance", 100)), 0, 100)
	var breakdown_chance := 0.02 + float(100 - maintenance) / 250.0
	if active_rigs > 0 and state.randf_seeded() < breakdown_chance:
		mining["broken_rigs"] = mini(rigs, broken_rigs + 1)
		summary.append("A mining rig broke down and needs repair.")
	state.crypto["mining"] = mining


func _process_monthly_obligations(state: LifeGameState, content: Variant, billing_month: Dictionary, summary: Array[String]) -> void:
	var month_name := _month_name(int(billing_month.get("month", 1)))
	var realistic := is_realistic_finances_enabled(state)
	var housing := _find_housing(state.housing_id, content)
	if not housing.is_empty():
		var housing_name := str(housing.get("name", "Housing"))
		var rent := maxi(0, int(housing.get("monthly_rent", 0)))
		var utilities := maxi(0, int(housing.get("monthly_utilities", 0)))
		if rent > 0:
			_charge_scheduled(state, rent, "%s rent — %s" % [month_name, housing_name], "housing_rent", summary, realistic)
		if utilities > 0:
			_charge_scheduled(state, utilities, "%s utilities — %s" % [month_name, housing_name], "housing_utilities", summary, realistic)
	else:
		var fallback_rent := maxi(0, int(state.flags.get("monthly_housing_rent", 0)))
		var fallback_utilities := maxi(0, int(state.flags.get("monthly_housing_utilities", 0)))
		if fallback_rent > 0:
			_charge_scheduled(state, fallback_rent, "%s housing payment" % month_name, "housing_rent", summary, realistic)
		if fallback_utilities > 0:
			_charge_scheduled(state, fallback_utilities, "%s utilities" % month_name, "housing_utilities", summary, realistic)

	var seen_bill_ids: Array[String] = []
	for raw_bill in _recurring_bills(state, content):
		if not raw_bill is Dictionary:
			continue
		var bill: Dictionary = raw_bill
		var bill_id := str(bill.get("id", bill.get("reason", "bill")))
		if seen_bill_ids.has(bill_id) or not bool(bill.get("active", true)):
			continue
		seen_bill_ids.append(bill_id)
		var amount := maxi(0, int(bill.get("amount", bill.get("monthly_amount", 0))))
		if amount > 0:
			_charge_scheduled(state, amount, str(bill.get("reason", bill.get("name", "Monthly bill"))), str(bill.get("category", "monthly_bill")), summary, realistic)

	if realistic:
		_process_realistic_living_costs(state, month_name, summary)

	_process_debt_payment(state, month_name, summary)


func _process_realistic_living_costs(state: LifeGameState, month_name: String, summary: Array[String]) -> void:
	for item in get_monthly_living_costs(state):
		var amount := maxi(0, int(item.get("amount", 0)))
		if amount <= 0 or not bool(item.get("active", true)):
			continue
		_charge_realistic_obligation(state, amount, "%s — %s" % [month_name, str(item.get("name", "Living expense"))], str(item.get("category", "living_cost")), summary)


func get_monthly_living_costs(state: LifeGameState, content: Variant = {}) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not is_realistic_finances_enabled(state):
		return result
	var profile := _realistic_profile(state)
	var cost_index := clampi(int(profile.get("cost_index_basis_points", 10000)), 5000, 25000)
	var living: Variant = profile.get("living_costs", DEFAULT_LIVING_COSTS)
	if living is Dictionary:
		var cost_ids: Array = living.keys()
		cost_ids.sort()
		for raw_cost_id in cost_ids:
			var cost_id := str(raw_cost_id)
			if not living[raw_cost_id] is Dictionary:
				continue
			var item: Dictionary = living[raw_cost_id].duplicate(true)
			item["id"] = cost_id
			item["amount"] = _basis_point_amount(maxi(0, int(item.get("amount", 0))), cost_index)
			result.append(item)

	var mode := str(profile.get("transport_mode", "public_transit"))
	var employed := not str(state.employment.get("job_id", "")).is_empty()
	var transport_base := 0
	var transport_name := "Transportation"
	match mode:
		"walk_cycle":
			transport_base = 24
			transport_name = "Walking and bicycle upkeep"
		"owned_vehicle", "travel_managed":
			# Fuel, insurance, and maintenance are itemized by VehicleFinanceSystem.
			# TravelSystem similarly itemizes fares, parking, and local mobility.
			transport_base = 0
			transport_name = "Itemized transportation costs"
		"rideshare":
			transport_base = 310 if employed else 135
			transport_name = "Rideshare transportation"
		_:
			transport_base = 128 if employed else 48
			transport_name = "Public transit pass"
	if transport_base > 0:
		result.append({
			"id": "transport",
			"name": transport_name,
			"amount": _basis_point_amount(transport_base, cost_index),
			"category": "transportation",
			"active": true,
		})
	return result


func _charge_scheduled(state: LifeGameState, amount: int, reason: String, category: String, summary: Array[String], realistic: bool) -> void:
	if realistic:
		_charge_realistic_obligation(state, amount, reason, category, summary)
	else:
		_charge_obligation(state, amount, reason, category, summary)


func _charge_realistic_obligation(state: LifeGameState, amount: int, reason: String, category: String, summary: Array[String]) -> void:
	if amount <= 0:
		return
	var paid := mini(amount, maxi(0, int(state.cash)))
	if paid > 0:
		record(state, -paid, reason, category)
	var unpaid := amount - paid
	if unpaid <= 0:
		summary.append("%s cost $%d." % [reason, amount])
		return
	_add_overdue(state, unpaid, reason, category)
	record(state, 0, "%s overdue: $%d" % [reason, unpaid], "%s_overdue" % category)
	state.flags["missed_obligations"] = int(state.flags.get("missed_obligations", 0)) + 1
	state.stress = clampi(state.stress + 3, 0, 100)
	state.reputation = clampi(state.reputation - 1, -100, 100)
	summary.append("Paid $%d of %s; $%d is overdue." % [paid, reason, unpaid])


func _add_overdue(state: LifeGameState, amount: int, reason: String, category: String) -> void:
	var profile := _realistic_profile(state)
	var items: Array = profile.get("overdue_obligations", []) if profile.get("overdue_obligations", []) is Array else []
	var merged := false
	for index in range(items.size()):
		if items[index] is Dictionary and str(items[index].get("category", "")) == category and str(items[index].get("reason", "")) == reason:
			var item: Dictionary = items[index]
			item["amount"] = maxi(0, int(item.get("amount", 0))) + amount
			item["missed_count"] = maxi(0, int(item.get("missed_count", 0))) + 1
			item["last_due_week"] = int(state.calendar.get("week_index", 0))
			items[index] = item
			merged = true
			break
	if not merged:
		items.append({
			"id": "%s_%d" % [category, int(state.calendar.get("week_index", 0))],
			"reason": reason,
			"category": category,
			"amount": amount,
			"missed_count": 1,
			"first_due_week": int(state.calendar.get("week_index", 0)),
			"last_due_week": int(state.calendar.get("week_index", 0)),
		})
	profile["overdue_obligations"] = items
	state.flags[REALISTIC_FINANCES_FLAG] = profile


func _process_overdue_obligations(state: LifeGameState, summary: Array[String]) -> void:
	var profile := _realistic_profile(state)
	var raw: Variant = profile.get("overdue_obligations", [])
	if not raw is Array or raw.is_empty():
		return
	var remaining: Array = []
	var total_paid := 0
	for raw_item in raw:
		if not raw_item is Dictionary:
			continue
		var item: Dictionary = raw_item.duplicate(true)
		var owed := maxi(0, int(item.get("amount", 0)))
		if owed <= 0:
			continue
		var payment := mini(owed, maxi(0, int(state.cash)))
		if payment > 0:
			record(state, -payment, "Overdue payment — %s" % str(item.get("reason", "bill")), "overdue_payment")
			owed -= payment
			total_paid += payment
		item["amount"] = owed
		if owed > 0:
			remaining.append(item)
	profile["overdue_obligations"] = remaining
	state.flags[REALISTIC_FINANCES_FLAG] = profile
	if total_paid > 0:
		summary.append("Automatic overdue payments used $%d; $%d remains past due." % [total_paid, get_overdue_total(state)])


func _process_debt_payment(state: LifeGameState, month_name: String, summary: Array[String]) -> void:
	if state.debt <= 0:
		return
	var configured := int(state.flags.get("monthly_debt_payment", 0))
	var minimum := configured if configured > 0 else maxi(50, ceili(float(state.debt) * 0.05))
	var due := mini(state.debt, minimum)
	var paid := mini(due, maxi(0, state.cash))
	if paid > 0:
		record(state, -paid, "%s debt payment" % month_name, "debt_payment")
		state.debt -= paid
		summary.append("Paid $%d toward debt; $%d remains." % [paid, state.debt])
	if paid < due:
		var missed := due - paid
		state.flags["missed_obligations"] = int(state.flags.get("missed_obligations", 0)) + 1
		state.stress = clampi(state.stress + 4, 0, 100)
		state.reputation = clampi(state.reputation - 1, -100, 100)
		record(state, 0, "Missed $%d of the %s debt payment" % [missed, month_name], "debt_missed")
		summary.append("You could not cover $%d of the debt payment; stress rose." % missed)


func _charge_obligation(state: LifeGameState, amount: int, reason: String, category: String, summary: Array[String]) -> void:
	if amount <= 0:
		return
	var cash_before := maxi(0, state.cash)
	record(state, -amount, reason, category)
	var shortfall := maxi(0, amount - cash_before)
	if shortfall > 0:
		state.debt += shortfall
		record(state, shortfall, "Emergency credit for %s" % reason, "debt_draw")
		state.flags["missed_obligations"] = int(state.flags.get("missed_obligations", 0)) + 1
		state.stress = clampi(state.stress + 3, 0, 100)
		state.reputation = clampi(state.reputation - 1, -100, 100)
		summary.append("%s cost $%d; $%d was added to debt." % [reason, amount, shortfall])
	else:
		summary.append("%s cost $%d." % [reason, amount])


func transfer_to_savings(state: LifeGameState, amount: int) -> String:
	if amount <= 0:
		return "Choose a positive amount."
	if state.cash < amount:
		return "You need $%d in cash for that transfer." % amount
	var entry := record(state, -amount, "Transfer to savings", "savings_transfer")
	state.savings += amount
	entry["savings_after"] = state.savings
	state.ledger[state.ledger.size() - 1] = entry
	return "Moved $%d into savings." % amount


func withdraw_from_savings(state: LifeGameState, amount: int) -> String:
	if amount <= 0:
		return "Choose a positive amount."
	if state.savings < amount:
		return "You only have $%d in savings." % state.savings
	state.savings -= amount
	var entry := record(state, amount, "Withdrawal from savings", "savings_transfer")
	entry["savings_after"] = state.savings
	state.ledger[state.ledger.size() - 1] = entry
	return "Moved $%d back to cash." % amount


func repay_debt(state: LifeGameState, amount: int) -> String:
	if amount <= 0:
		return "Choose a positive amount."
	if state.debt <= 0:
		return "You do not have debt to repay."
	var payment := mini(amount, state.debt)
	if state.cash < payment:
		return "You need $%d in cash for that payment." % payment
	record(state, -payment, "Extra debt payment", "debt_payment")
	state.debt -= payment
	return "Paid $%d toward debt; $%d remains." % [payment, state.debt]


func get_upcoming_obligations(state: LifeGameState, content: Variant = {}) -> Array[Dictionary]:
	var obligations: Array[Dictionary] = []
	var days_until := _days_until_next_month(state.calendar)
	var due_text := "next week" if days_until <= 7 else "in %d days" % days_until
	var housing := _find_housing(state.housing_id, content)
	if not housing.is_empty():
		var rent := maxi(0, int(housing.get("monthly_rent", 0)))
		var utilities := maxi(0, int(housing.get("monthly_utilities", 0)))
		if rent > 0:
			obligations.append({"id": "housing_rent", "name": "%s rent" % str(housing.get("name", "Housing")), "label": "%s rent" % str(housing.get("name", "Housing")), "amount": rent, "due_in_days": days_until, "due_in": due_text})
		if utilities > 0:
			obligations.append({"id": "housing_utilities", "name": "Utilities", "label": "Utilities", "amount": utilities, "due_in_days": days_until, "due_in": due_text})
	for raw_bill in _recurring_bills(state, content):
		if raw_bill is Dictionary and bool(raw_bill.get("active", true)):
			var amount := maxi(0, int(raw_bill.get("amount", raw_bill.get("monthly_amount", 0))))
			if amount > 0:
				var bill_name := str(raw_bill.get("reason", raw_bill.get("name", "Monthly bill")))
				obligations.append({"id": str(raw_bill.get("id", "bill")), "name": bill_name, "label": bill_name, "amount": amount, "due_in_days": days_until, "due_in": due_text})
	if is_realistic_finances_enabled(state):
		for item in get_monthly_living_costs(state, content):
			if bool(item.get("active", true)) and int(item.get("amount", 0)) > 0:
				obligations.append({
					"id": str(item.get("id", "living_cost")),
					"name": str(item.get("name", "Living expense")),
					"label": str(item.get("name", "Living expense")),
					"amount": int(item.get("amount", 0)),
					"due_in_days": days_until,
					"due_in": due_text,
				})
		for overdue in get_overdue_obligations(state):
			obligations.append({
				"id": "overdue_%s" % str(overdue.get("id", "bill")),
				"name": "Past due — %s" % str(overdue.get("reason", "bill")),
				"label": "Past due — %s" % str(overdue.get("reason", "bill")),
				"amount": int(overdue.get("amount", 0)),
				"due_in_days": 0,
				"due_in": "now",
			})
		if ResourceLoader.exists(VEHICLE_FINANCE_SYSTEM_PATH):
			var vehicle_script: Script = load(VEHICLE_FINANCE_SYSTEM_PATH)
			var vehicle_system: Variant = vehicle_script.new()
			if vehicle_system.has_method("get_upcoming_costs"):
				for vehicle_cost in vehicle_system.get_upcoming_costs(state):
					obligations.append(vehicle_cost)
	if state.debt > 0:
		var configured := int(state.flags.get("monthly_debt_payment", 0))
		var payment := configured if configured > 0 else maxi(50, ceili(float(state.debt) * 0.05))
		obligations.append({"id": "debt_payment", "name": "Debt payment", "label": "Debt payment", "amount": mini(state.debt, payment), "due_in_days": days_until, "due_in": due_text})
	return obligations


func get_next_paycheck(state: LifeGameState) -> Dictionary:
	return get_paycheck_preview(state)


func _process_vehicle_finance(state: LifeGameState) -> Array[String]:
	if not ResourceLoader.exists(VEHICLE_FINANCE_SYSTEM_PATH):
		return []
	var script: Script = load(VEHICLE_FINANCE_SYSTEM_PATH)
	var system: Variant = script.new()
	if not system.has_method("process_week"):
		return []
	var raw: Variant = system.process_week(state, self)
	var result: Array[String] = []
	if raw is Array:
		for line in raw:
			result.append(str(line))
	return result


func _find_housing(housing_id: String, content: Variant) -> Dictionary:
	if housing_id.is_empty():
		return {}
	for raw_option in _content_array(content, "housing"):
		if raw_option is Dictionary and str(raw_option.get("id", "")) == housing_id:
			return raw_option
	return {}


func _housing_mining_limit(state: LifeGameState, content: Variant) -> int:
	var housing := _find_housing(state.housing_id, content)
	if housing.is_empty():
		return maxi(0, int(state.flags.get("mining_max_rigs", 0)))
	var mining_rules: Variant = housing.get("mining", {})
	if not mining_rules is Dictionary or not bool(mining_rules.get("allowed", false)):
		return 0
	return maxi(0, int(mining_rules.get("max_rigs", 0)))


func _recurring_bills(state: LifeGameState, content: Variant) -> Array:
	var result: Array = []
	var state_bills: Variant = state.flags.get("recurring_bills", [])
	if state_bills is Array:
		result.append_array(state_bills)
	result.append_array(_content_array(content, "monthly_bills"))
	return result


func _content_array(content: Variant, key: String) -> Array:
	if not content is Dictionary:
		return []
	var catalog: Dictionary = content
	var value: Variant = catalog.get(key, [])
	if value is Array:
		return value
	# Combined content commonly stores each JSON document under its own key.
	if value is Dictionary:
		var nested: Dictionary = value
		var nested_value: Variant = nested.get(key, [])
		if nested_value is Array:
			return nested_value
	return []


func _month_boundaries_for_week(state: LifeGameState) -> Array[Dictionary]:
	var saved_boundary: Variant = state.flags.get("last_calendar_boundary", {})
	var current_week := int(state.calendar.get("week_index", 0))
	if saved_boundary is Dictionary and int(saved_boundary.get("to_week_index", -1)) == current_week:
		var saved_months: Variant = saved_boundary.get("month_boundaries", [])
		if saved_months is Array:
			var typed_months: Array[Dictionary] = []
			for value in saved_months:
				if value is Dictionary:
					typed_months.append(value.duplicate(true))
			return typed_months

	# Fallback supports imported saves or custom orchestrators that update the date
	# without retaining CalendarSystem's boundary dictionary.
	var current := _normalized_date(state.calendar)
	var previous := current.duplicate(true)
	for _day in range(7):
		previous = _subtract_one_day(previous)
	var result: Array[Dictionary] = []
	var cursor := previous
	for _day in range(7):
		cursor = _add_one_day(cursor)
		if int(cursor["day"]) == 1:
			result.append(cursor.duplicate(true))
	return result


func _normalized_date(value: Dictionary) -> Dictionary:
	var year := clampi(int(value.get("year", 2026)), 1900, 9999)
	var month := clampi(int(value.get("month", 1)), 1, 12)
	var day := clampi(int(value.get("day", 1)), 1, _days_in_month(year, month))
	return {"year": year, "month": month, "day": day}


func _add_one_day(date: Dictionary) -> Dictionary:
	var year := int(date["year"])
	var month := int(date["month"])
	var day := int(date["day"]) + 1
	if day > _days_in_month(year, month):
		day = 1
		month += 1
		if month > 12:
			month = 1
			year += 1
	return {"year": year, "month": month, "day": day}


func _subtract_one_day(date: Dictionary) -> Dictionary:
	var year := int(date["year"])
	var month := int(date["month"])
	var day := int(date["day"]) - 1
	if day < 1:
		month -= 1
		if month < 1:
			month = 12
			year -= 1
		day = _days_in_month(year, month)
	return {"year": year, "month": month, "day": day}


func _days_until_next_month(calendar: Dictionary) -> int:
	var date := _normalized_date(calendar)
	return _days_in_month(int(date["year"]), int(date["month"])) - int(date["day"]) + 1


func _date_key(value: Dictionary) -> String:
	var date := _normalized_date(value)
	return "%04d-%02d-%02d" % [int(date["year"]), int(date["month"]), int(date["day"])]


func _month_name(month: int) -> String:
	const NAMES: Array[String] = ["January", "February", "March", "April", "May", "June", "July", "August", "September", "October", "November", "December"]
	return NAMES[clampi(month, 1, 12) - 1]


func _days_in_month(year: int, month: int) -> int:
	match month:
		2:
			return 29 if year % 400 == 0 or (year % 4 == 0 and year % 100 != 0) else 28
		4, 6, 9, 11:
			return 30
		_:
			return 31


func _realistic_profile(state: LifeGameState) -> Dictionary:
	var raw: Variant = state.flags.get(REALISTIC_FINANCES_FLAG, {})
	return raw.duplicate(true) if raw is Dictionary else {}


func _merge_living_costs(target: Dictionary, source: Dictionary) -> void:
	for raw_key in source:
		var key := str(raw_key).strip_edges()
		if key.is_empty():
			continue
		var existing: Dictionary = target.get(key, {}) if target.get(key, {}) is Dictionary else {}
		var incoming: Variant = source[raw_key]
		if incoming is Dictionary:
			for field in incoming:
				existing[str(field)] = incoming[field]
		else:
			existing["amount"] = int(incoming)
		if not existing.has("name"):
			existing["name"] = key.replace("_", " ").capitalize()
		if not existing.has("category"):
			existing["category"] = key
		existing["amount"] = maxi(0, int(existing.get("amount", 0)))
		existing["active"] = bool(existing.get("active", true))
		target[key] = existing


func _basis_point_amount(amount: int, basis_points: int) -> int:
	if amount <= 0 or basis_points <= 0:
		return 0
	return maxi(0, roundi(float(amount) * float(basis_points) / 10000.0))
