class_name BusinessSystem
extends RefCounted

const BUSINESS_ID := "street_bowl_kitchen"
const STARTUP_COST := 3200
const STARTUP_HOURS := 12
const BASE_CAPACITY := 28
const EXPANSION_COST := 1800
const MAX_EXPANSIONS := 2


func get_definition() -> Dictionary:
	return {
		"id": BUSINESS_ID,
		"name": "Street Bowl Kitchen",
		"district_id": "commercial",
		"location_id": "street_market",
		"description": "A compact lunch stall whose profit depends on price, demand, upkeep, and staffing.",
		"startup_cost": STARTUP_COST,
		"startup_hours": STARTUP_HOURS,
		"default_price": 14,
		"default_staff": 0,
		"default_capacity": BASE_CAPACITY,
		"expansion_cost": EXPANSION_COST,
		"max_expansions": MAX_EXPANSIONS,
		"known_weekly_costs": {
			"pitch_rent": 120,
			"ingredients_per_customer": 5,
			"wage_per_staff_member": 90,
			"default_maintenance": 100
		}
	}


func start_eligibility_details(state) -> Dictionary:
	var reasons: Array[String] = []
	if bool(state.business.get("active", false)):
		reasons.append("You already operate a business.")
	if _is_jailed(state):
		reasons.append("You cannot open a market stall while jailed.")
	if int(state.cash) < STARTUP_COST:
		reasons.append("Startup costs $%s; you have $%s." % [_money(STARTUP_COST), _money(int(state.cash))])
	if int(state.weekly_time) < STARTUP_HOURS:
		reasons.append("Setup needs %d free hours this week." % STARTUP_HOURS)
	if int(state.reputation) < 20:
		reasons.append("The market requires at least 20 reputation for a vendor permit.")
	return {"eligible": reasons.is_empty(), "reasons": reasons}


func start(state, economy) -> String:
	var details := start_eligibility_details(state)
	if not bool(details.get("eligible", false)):
		return "You cannot start the business: %s" % _join_strings(details.get("reasons", []))
	if not _spend_time(state, STARTUP_HOURS, "Set up Street Bowl Kitchen"):
		return "You no longer have enough free time for the setup work."
	_record_money(state, economy, -STARTUP_COST, "Street Bowl Kitchen startup", "business_startup")
	state.business = {
		"id": BUSINESS_ID,
		"name": "Street Bowl Kitchen",
		"active": true,
		"weeks": 0,
		"price": 14,
		"staff": 0,
		"capacity": BASE_CAPACITY,
		"reputation": 45,
		"demand": 42,
		"marketing_budget": 40,
		"maintenance_budget": 100,
		"expansion_level": 0,
		"pending_expansion": false,
		"last_customers": 0,
		"last_revenue": 0,
		"last_expenses": 0,
		"last_profit": 0,
		"lifetime_profit": -STARTUP_COST,
		"loss_streak": 0,
		"last_processed_week": -1
	}
	state.skills["business"] = clampi(int(state.skills.get("business", 0)) + 3, 0, 100)
	state.happiness = clampi(int(state.happiness) + 5, 0, 100)
	state.add_history("Opened Street Bowl Kitchen at the street market.")
	return "Street Bowl Kitchen is open. You paid $%s and used %d hours. Weekly results now depend on demand, price, staffing, and upkeep." % [_money(STARTUP_COST), STARTUP_HOURS]


func set_decision(state, key: String, value) -> String:
	if not bool(state.business.get("active", false)):
		return "Start the business before making operating decisions."
	match key:
		"price":
			var price := int(value)
			if price < 8 or price > 26:
				return "Menu price must be between $8 and $26."
			state.business["price"] = price
			return "Menu price set to $%d. Higher prices earn more per sale but reduce demand." % price
		"staff":
			var staff := int(value)
			if staff < 0 or staff > 4:
				return "The stall can employ between 0 and 4 staff members."
			state.business["staff"] = staff
			_recalculate_capacity(state)
			return "Staffing set to %d. Each employee costs $90 weekly, adds capacity, and reduces your owner-hours." % staff
		"marketing_budget":
			var marketing := int(value)
			if marketing < 0 or marketing > 300:
				return "Weekly marketing must be between $0 and $300."
			state.business["marketing_budget"] = marketing
			return "Weekly marketing set to $%d. It can improve demand, but never guarantees sales." % marketing
		"maintenance_budget":
			var maintenance := int(value)
			if maintenance < 40 or maintenance > 300:
				return "Weekly maintenance must be between $40 and $300."
			state.business["maintenance_budget"] = maintenance
			return "Weekly maintenance set to $%d. Cutting it increases breakdown risk." % maintenance
		"expand_capacity":
			if not bool(value):
				state.business["pending_expansion"] = false
				return "The pending expansion was canceled before payment."
			if int(state.business.get("expansion_level", 0)) >= MAX_EXPANSIONS:
				return "The market pitch is already at maximum capacity."
			state.business["pending_expansion"] = true
			return "Expansion scheduled for next week. It will cost $%s only if funds are available." % _money(EXPANSION_COST)
		_:
			return "Unknown business decision: %s." % key


func process_week(state, economy) -> Array[String]:
	var summary: Array[String] = []
	if not bool(state.business.get("active", false)):
		return summary
	if str(state.business.get("id", "")) != BUSINESS_ID:
		summary.append("This business type is not supported by the current milestone.")
		return summary
	var week_index := int(state.calendar.get("week_index", 0))
	if int(state.business.get("last_processed_week", -1)) == week_index:
		return summary
	state.business["last_processed_week"] = week_index

	_process_expansion(state, economy, summary)
	_recalculate_capacity(state)
	var staff := int(state.business.get("staff", 0))
	var owner_hours := maxi(4, 16 - staff * 4)
	var jailed := _is_jailed(state)
	var owner_present := false if jailed else _spend_time(state, owner_hours, "Run Street Bowl Kitchen")
	if jailed:
		state.business["reputation"] = clampi(int(state.business.get("reputation", 45)) - 3, 0, 100)
		summary.append("You could not operate the stall personally from jail; unavoidable lease and staffing costs continued.")
	elif not owner_present:
		state.business["reputation"] = clampi(int(state.business.get("reputation", 45)) - 4, 0, 100)
		state.stress = clampi(int(state.stress) + 4, 0, 100)
		summary.append("You could not cover the stall's %d owner-hours; service and reputation suffered." % owner_hours)

	var capacity := int(state.business.get("capacity", BASE_CAPACITY))
	var price := int(state.business.get("price", 14))
	var marketing := int(state.business.get("marketing_budget", 0))
	var maintenance := int(state.business.get("maintenance_budget", 100))
	var business_reputation := int(state.business.get("reputation", 45))
	var city_demand := 40 + int(state.randi_seeded(25)) - 12
	var price_effect := (14 - price) * 4
	var marketing_effect := int(marketing / 15.0)
	var reputation_effect := int((business_reputation - 45) / 2.0)
	var skill_effect := int(state.skills.get("business", 0) / 5.0)
	var demand := maxi(0, city_demand + price_effect + marketing_effect + reputation_effect + skill_effect)
	if jailed:
		if staff <= 0:
			demand = 0
		else:
			demand = int(demand * minf(0.8, 0.35 + staff * 0.12))
	elif not owner_present:
		var unattended_factor := 0.25 if staff <= 0 else minf(0.85, 0.45 + staff * 0.12)
		demand = int(demand * unattended_factor)

	var breakdown := demand > 0 and _roll_breakdown(state, maintenance, capacity)
	var effective_capacity := capacity
	var repair_cost := 0
	if breakdown:
		effective_capacity = maxi(5, int(capacity * 0.55))
		repair_cost = 280
		state.business["reputation"] = clampi(int(state.business.get("reputation", 45)) - 3, 0, 100)
		summary.append("A cooking-unit breakdown reduced capacity and required a $%s repair." % _money(repair_cost))

	var customers := mini(demand, effective_capacity)
	var revenue := customers * price
	var ingredient_unit_cost := 3 if bool(state.flags.get("supplier_discount", false)) else (4 if bool(state.flags.get("supplier_contract", false)) else 5)
	var ingredient_cost := customers * ingredient_unit_cost
	var pitch_rent := 120
	var staff_wages := staff * 90
	var expenses := ingredient_cost + pitch_rent + staff_wages + marketing + maintenance + repair_cost
	if revenue > 0:
		_record_money(state, economy, revenue, "Street Bowl Kitchen sales", "business_revenue")
	_record_money(state, economy, -ingredient_cost, "Street Bowl Kitchen ingredients", "business_supplies")
	_record_money(state, economy, -pitch_rent, "Street market pitch rent", "business_rent")
	if staff_wages > 0:
		_record_money(state, economy, -staff_wages, "Street Bowl Kitchen staff wages", "business_payroll")
	if marketing > 0:
		_record_money(state, economy, -marketing, "Street Bowl Kitchen marketing", "business_marketing")
	_record_money(state, economy, -maintenance, "Street Bowl Kitchen maintenance", "business_maintenance")
	if repair_cost > 0:
		_record_money(state, economy, -repair_cost, "Street Bowl Kitchen equipment repair", "business_repair")

	var profit := revenue - expenses
	state.business["weeks"] = int(state.business.get("weeks", 0)) + 1
	state.business["demand"] = demand
	state.business["last_customers"] = customers
	state.business["last_revenue"] = revenue
	state.business["last_expenses"] = expenses
	state.business["last_profit"] = profit
	state.business["lifetime_profit"] = int(state.business.get("lifetime_profit", -STARTUP_COST)) + profit
	state.business["loss_streak"] = int(state.business.get("loss_streak", 0)) + 1 if profit < 0 else 0

	if customers >= int(effective_capacity * 0.85) and not breakdown:
		state.business["reputation"] = clampi(int(state.business.get("reputation", 45)) + 2, 0, 100)
	elif customers < int(capacity * 0.3):
		state.business["reputation"] = clampi(int(state.business.get("reputation", 45)) - 1, 0, 100)
	if owner_present:
		state.skills["business"] = clampi(int(state.skills.get("business", 0)) + 2, 0, 100)
	state.stress = clampi(int(state.stress) + (3 if profit < 0 else 1), 0, 100)

	var profit_word := "profit" if profit >= 0 else "loss"
	summary.append("Street Bowl Kitchen served %d of %d potential customers: $%s revenue, $%s expenses, $%s %s." % [customers, demand, _money(revenue), _money(expenses), _money(absi(profit)), profit_word])
	_maybe_fail(state, summary)
	return summary


func _process_expansion(state, economy, summary: Array[String]) -> void:
	if not bool(state.business.get("pending_expansion", false)):
		return
	if int(state.business.get("expansion_level", 0)) >= MAX_EXPANSIONS:
		state.business["pending_expansion"] = false
		return
	if int(state.cash) < EXPANSION_COST:
		summary.append("The $%s stall expansion was postponed because cash was insufficient." % _money(EXPANSION_COST))
		return
	_record_money(state, economy, -EXPANSION_COST, "Street Bowl Kitchen capacity expansion", "business_expansion")
	state.business["expansion_level"] = int(state.business.get("expansion_level", 0)) + 1
	state.business["pending_expansion"] = false
	_recalculate_capacity(state)
	state.add_history("Expanded Street Bowl Kitchen to capacity %d." % int(state.business.get("capacity", BASE_CAPACITY)))
	summary.append("The stall expansion finished for $%s; base service capacity increased." % _money(EXPANSION_COST))


func _recalculate_capacity(state) -> void:
	var staff := clampi(int(state.business.get("staff", 0)), 0, 4)
	var expansion_level := clampi(int(state.business.get("expansion_level", 0)), 0, MAX_EXPANSIONS)
	state.business["capacity"] = BASE_CAPACITY + staff * 12 + expansion_level * 18


func _roll_breakdown(state, maintenance: int, capacity: int) -> bool:
	var recommended := 80 + int(capacity * 1.5)
	var shortage := maxi(0, recommended - maintenance)
	var risk_percent := clampi(3 + int(shortage / 3.0), 3, 48)
	return int(state.randi_seeded(100)) < risk_percent


func _maybe_fail(state, summary: Array[String]) -> void:
	var loss_streak := int(state.business.get("loss_streak", 0))
	var business_reputation := int(state.business.get("reputation", 0))
	if loss_streak < 6 or business_reputation >= 18:
		return
	state.business["active"] = false
	state.happiness = clampi(int(state.happiness) - 8, 0, 100)
	state.stress = clampi(int(state.stress) + 10, 0, 100)
	state.add_history("Street Bowl Kitchen closed after a sustained losing run.")
	summary.append("After six losing weeks and declining reputation, Street Bowl Kitchen closed. Its debts and lessons remain part of your life.")


func _is_jailed(state) -> bool:
	return bool(state.crime.get("in_jail", state.crime.get("jailed", false))) or int(state.crime.get("jail_weeks", state.crime.get("jail_weeks_remaining", 0))) > 0


func _spend_time(state, hours: int, reason: String) -> bool:
	if state.has_method("spend_time"):
		return bool(state.spend_time(hours, reason))
	if int(state.weekly_time) < hours:
		return false
	state.weekly_time = int(state.weekly_time) - hours
	return true


func _record_money(state, economy, amount: int, reason: String, category: String) -> void:
	if amount == 0:
		return
	if economy != null and economy.has_method("record"):
		economy.record(state, amount, reason, category)
		return
	state.cash = int(state.cash) + amount
	var sequence := maxi(int(state.flags.get("ledger_sequence", state.ledger.size())), state.ledger.size()) + 1
	state.flags["ledger_sequence"] = sequence
	state.ledger.append({
		"id": sequence,
		"week_index": int(state.calendar.get("week_index", 0)),
		"date": "%04d-%02d-%02d" % [int(state.calendar.get("year", 0)), int(state.calendar.get("month", 1)), int(state.calendar.get("day", 1))],
		"amount": amount,
		"reason": reason,
		"category": category,
		"balance_after": int(state.cash),
		"account": "cash"
	})


func _join_strings(values: Array) -> String:
	var parts := PackedStringArray()
	for value in values:
		parts.append(str(value))
	return " ".join(parts)


func _money(value: int) -> String:
	var raw := str(absi(value))
	var formatted := ""
	while raw.length() > 3:
		formatted = "," + raw.right(3) + formatted
		raw = raw.left(raw.length() - 3)
	formatted = raw + formatted
	return ("-" if value < 0 else "") + formatted
