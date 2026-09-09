class_name HousingSystem
extends RefCounted

const HOUSING_PATH := "res://data/housing.json"
const HOUSING_PROCESS_FLAG := "housing_system_processed_week"
const DEPOSITS_FLAG := "housing_deposits"

var _options: Array[Dictionary] = []


func _init() -> void:
	_options = _load_options()


func get_options() -> Array[Dictionary]:
	if _options.is_empty():
		_options = _load_options()
	var result: Array[Dictionary] = []
	for option in _options:
		var copy := option.duplicate(true)
		copy["monthly_total"] = int(option.get("monthly_rent", 0)) + int(option.get("monthly_utilities", 0))
		copy["move_in_total"] = int(option.get("deposit", 0)) + int(option.get("moving_cost", 0))
		result.append(copy)
	return result


func current(state) -> Dictionary:
	return get_option(str(state.housing_id))


func get_option(housing_id: String) -> Dictionary:
	for option in _options:
		if str(option.get("id", "")) == housing_id:
			var copy := option.duplicate(true)
			copy["monthly_total"] = int(option.get("monthly_rent", 0)) + int(option.get("monthly_utilities", 0))
			copy["move_in_total"] = int(option.get("deposit", 0)) + int(option.get("moving_cost", 0))
			return copy
	return {}


func eligibility_details(state, housing_id: String) -> Dictionary:
	var option := get_option(housing_id)
	var reasons: Array[String] = []
	if option.is_empty():
		reasons.append("That housing option no longer exists.")
		return {"eligible": false, "reasons": reasons, "move_in_total": 0}
	if str(state.housing_id) == housing_id:
		reasons.append("You already live here.")
	if _is_jailed(state):
		reasons.append("You cannot move home while jailed.")

	var deposit := int(option.get("deposit", 0))
	var moving_cost := int(option.get("moving_cost", 0))
	var total := deposit + moving_cost
	var refundable := _current_refundable_deposit(state)
	var available_after_move := int(state.cash) + refundable - total
	var requirements: Dictionary = option.get("requirements", {})
	var min_after := int(requirements.get("min_cash_after_move", 0))
	if available_after_move < min_after:
		reasons.append("Move-in is $%s and the lease requires $%s left afterward." % [_money(total), _money(min_after)])
	var min_income := int(requirements.get("min_weekly_income", 0))
	var weekly_income := int(state.employment.get("weekly_pay", 0))
	if weekly_income < min_income:
		reasons.append("Requires documented income of $%s per week (you have $%s)." % [_money(min_income), _money(weekly_income)])
	if int(state.weekly_time) < 4:
		reasons.append("Moving needs 4 free hours this week.")
	return {
		"eligible": reasons.is_empty(),
		"reasons": reasons,
		"reason": _join_strings(reasons),
		"move_in_total": total,
		"refundable_deposit": refundable,
		"cash_after_move": available_after_move
	}


func move_to(state, housing_id: String, economy) -> String:
	var option := get_option(housing_id)
	var details := eligibility_details(state, housing_id)
	if not bool(details.get("eligible", false)):
		return "You cannot move there: %s" % _join_strings(details.get("reasons", []))
	if not _spend_time(state, 4, "Move to %s" % str(option.get("name", "new housing"))):
		return "There is not enough free time left to move this week."

	var old_option := current(state)
	var old_id := str(state.housing_id)
	var refundable := _current_refundable_deposit(state)
	if refundable > 0:
		_record_money(state, economy, refundable, "%s deposit returned" % str(old_option.get("name", "Housing")), "housing_deposit_refund")
		_set_held_deposit(state, old_id, 0)

	var deposit := int(option.get("deposit", 0))
	var moving_cost := int(option.get("moving_cost", 0))
	if deposit > 0:
		_record_money(state, economy, -deposit, "%s security deposit" % str(option.get("name", "Housing")), "housing_deposit")
		_set_held_deposit(state, housing_id, deposit)
	if moving_cost > 0:
		_record_money(state, economy, -moving_cost, "Move to %s" % str(option.get("name", "Housing")), "moving_cost")

	state.housing_id = housing_id
	state.happiness = clampi(int(state.happiness) + 2, 0, 100)
	state.add_history("Moved to %s." % str(option.get("name", "a new home")))
	var monthly_total := int(option.get("monthly_rent", 0)) + int(option.get("monthly_utilities", 0))
	return "You moved to %s. Move-in cost was $%s; the predictable monthly charge is $%s on the first monthly boundary." % [str(option.get("name", "your new home")), _money(deposit + moving_cost), _money(monthly_total)]


func process_week(state) -> Array[String]:
	var summary: Array[String] = []
	var week_index := int(state.calendar.get("week_index", 0))
	if int(state.flags.get(HOUSING_PROCESS_FLAG, -1)) == week_index:
		return summary
	state.flags[HOUSING_PROCESS_FLAG] = week_index
	var option := current(state)
	if option.is_empty():
		state.stress = clampi(int(state.stress) + 4, 0, 100)
		state.health = clampi(int(state.health) - 1, 0, 100)
		summary.append("Without stable housing, stress rose and health slipped.")
		return summary
	var wellbeing: Dictionary = option.get("wellbeing", {})
	var happiness_delta := int(wellbeing.get("happiness", 0))
	var stress_delta := int(wellbeing.get("stress", 0))
	var health_delta := int(wellbeing.get("health", 0))
	state.happiness = clampi(int(state.happiness) + happiness_delta, 0, 100)
	state.stress = clampi(int(state.stress) + stress_delta, 0, 100)
	state.health = clampi(int(state.health) + health_delta, 0, 100)
	if happiness_delta != 0 or stress_delta != 0 or health_delta != 0:
		summary.append("%s affected wellbeing: happiness %+d, stress %+d, health %+d." % [str(option.get("name", "Housing")), happiness_delta, stress_delta, health_delta])
	return summary


func upcoming_monthly_obligation(state) -> Dictionary:
	var option := current(state)
	if option.is_empty():
		return {}
	var rent := int(option.get("monthly_rent", 0))
	var utilities := int(option.get("monthly_utilities", 0))
	return {
		"id": "housing_monthly",
		"name": "%s monthly housing" % str(option.get("name", "Housing")),
		"amount": rent + utilities,
		"rent": rent,
		"utilities": utilities,
		"schedule": "First weekly advance that crosses into a new month"
	}


func mining_capacity(state) -> Dictionary:
	var option := current(state)
	if option.is_empty():
		return {"allowed": false, "max_rigs": 0, "reason": "Secure housing is required."}
	var mining: Dictionary = option.get("mining", {})
	return mining.duplicate(true)


func _current_refundable_deposit(state) -> int:
	var current_id := str(state.housing_id)
	if current_id.is_empty():
		return 0
	var deposits: Dictionary = state.flags.get(DEPOSITS_FLAG, {})
	var held := int(deposits.get(current_id, 0))
	var option := current(state)
	var percent := int(option.get("deposit_refund_percent", 100))
	return maxi(0, int(held * percent / 100.0))


func _set_held_deposit(state, housing_id: String, amount: int) -> void:
	var deposits: Dictionary = state.flags.get(DEPOSITS_FLAG, {})
	if amount <= 0:
		deposits.erase(housing_id)
	else:
		deposits[housing_id] = amount
	state.flags[DEPOSITS_FLAG] = deposits


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


func _load_options() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	if not FileAccess.file_exists(HOUSING_PATH):
		push_error("Housing content missing: %s" % HOUSING_PATH)
		return entries
	var file := FileAccess.open(HOUSING_PATH, FileAccess.READ)
	if file == null:
		push_error("Could not open housing content: %s" % HOUSING_PATH)
		return entries
	var parsed = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		push_error("Housing content must be a JSON object.")
		return entries
	var raw_entries = parsed.get("housing", [])
	if not raw_entries is Array:
		push_error("Housing content requires a 'housing' array.")
		return entries
	for raw_entry in raw_entries:
		if raw_entry is Dictionary and not str(raw_entry.get("id", "")).is_empty():
			entries.append(raw_entry)
	return entries


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
