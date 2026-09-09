class_name LifeGameState
extends RefCounted

## Serializable source of truth for the simulation. Systems mutate this object;
## UI scenes only read it and call system APIs.

signal state_changed

const DEFAULT_SEED: int = 711_2026
const DEFAULT_WEEKLY_TIME: int = 40

var created: bool = false
var player_name: String = ""
var pronouns: String = "They/Them"
var appearance: int = 0
var background_id: String = ""
var traits: Array[String] = []

var birth_year: int = 2008
var age: int = 18
var calendar: Dictionary = {}

var cash: int = 0
var savings: int = 0
var debt: int = 0
var ledger: Array[Dictionary] = []

var health: int = 80
var happiness: int = 65
var stress: int = 20
var reputation: int = 50
var energy: int = 80
var weekly_time: int = DEFAULT_WEEKLY_TIME

var skills: Dictionary = {}
var education: Array[String] = []
var employment: Dictionary = {}

var housing_id: String = ""
var owned_properties: Array[String] = []
var relationships: Array[Dictionary] = []

var business: Dictionary = {}
var crypto: Dictionary = {}
var crime: Dictionary = {}

var active_activities: Array[Dictionary] = []
var delayed_effects: Array[Dictionary] = []
var event_history: Array[String] = []
var cooldowns: Dictionary = {}
var flags: Dictionary = {}
var last_week_summary: Array[String] = []

var seed: int = DEFAULT_SEED
var rng_state: int = 0


func _init(initial_seed: int = DEFAULT_SEED) -> void:
	seed = _normalized_seed(initial_seed)
	_reset_values(seed)


## Restores a clean age-18 starting state. Supplying a seed makes a run exactly
## reproducible; omitting it deliberately reuses this state's existing seed.
func reset_new_game(new_seed: int = 0) -> void:
	var chosen_seed := seed if new_seed == 0 else new_seed
	_reset_values(_normalized_seed(chosen_seed))
	state_changed.emit()


func _reset_values(new_seed: int) -> void:
	created = false
	player_name = ""
	pronouns = "They/Them"
	appearance = 0
	background_id = ""
	traits = []

	birth_year = 2008
	age = 18
	calendar = {
		"year": 2026,
		"month": 1,
		"day": 5,
		"week": 1,
		"week_index": 0,
	}

	# Character backgrounds apply their transparent trade-offs during creation.
	# These neutral values keep reset state modest and safe to preview.
	cash = 1200
	savings = 0
	debt = 0
	ledger = []

	health = 80
	happiness = 65
	stress = 20
	reputation = 50
	energy = 80
	weekly_time = DEFAULT_WEEKLY_TIME

	skills = {
		"people": 20,
		"grit": 20,
		"technical": 15,
		"education": 20,
		"communication": 15,
		"practical": 20,
		"driving": 10,
		"fitness": 20,
		"discipline": 15,
		"administration": 10,
		"digital": 15,
		"business": 10,
	}
	education = ["secondary_diploma"]
	employment = _default_employment()

	housing_id = ""
	owned_properties = []
	relationships = []

	business = _default_business()
	crypto = _default_crypto()
	crime = _default_crime()

	active_activities = []
	delayed_effects = []
	event_history = []
	cooldowns = {}
	flags = {
		"weekly_time_limit": DEFAULT_WEEKLY_TIME,
		"weekly_actions": [],
		"ledger_sequence": 0,
		# Week zero is the starting screen, not a payable work week.
		"last_economy_week_index": 0,
		"last_calendar_boundary": {},
		"missed_obligations": 0,
	}
	last_week_summary = []

	seed = new_seed
	var generator := RandomNumberGenerator.new()
	generator.seed = seed
	rng_state = generator.state


func _default_employment() -> Dictionary:
	return {
		"job_id": "",
		"title": "Unemployed",
		"weekly_pay": 0,
		"performance": 50,
		"weeks": 0,
		"hours_per_week": 0,
		"active": false,
	}


func _default_business() -> Dictionary:
	return {
		"id": "street_bowl_kitchen",
		"name": "Street Bowl Kitchen",
		"active": false,
		"weeks": 0,
		"price": 12,
		"staff": 0,
		"capacity": 45,
		"reputation": 50,
		"demand": 50,
		"marketing_budget": 0,
		"maintenance_budget": 0,
		"expansion_level": 0,
		"pending_expansion": false,
		"last_customers": 0,
		"last_revenue": 0,
		"last_expenses": 0,
		"lifetime_profit": 0,
		"last_processed_week": 0,
	}


func _default_crypto() -> Dictionary:
	return {
		"coins": {
			"lumen": {
				"id": "lumen",
				"name": "Lumen Coin",
				"symbol": "LUM",
				"price": 24,
				"holdings_milli": 0,
				"average_cost": 0,
				"realized_gain": 0,
				"price_history": [24],
			},
			"forge": {
				"id": "forge",
				"name": "Forge Token",
				"symbol": "FRG",
				"price": 61,
				"holdings_milli": 0,
				"average_cost": 0,
				"realized_gain": 0,
				"price_history": [61],
			},
		},
		"market_news": [],
		"mining": {
			"rigs": 0,
			"capacity": 0,
			"coin_id": "lumen",
			"weekly_yield_milli": 0,
			"weekly_power_cost": 0,
			"maintenance": 100,
			"broken_rigs": 0,
			"auto_sell": false,
			"last_processed_week": 0,
		},
	}


func _default_crime() -> Dictionary:
	return {
		"suspicion": 0,
		"record": [],
		"investigations": [],
		"in_jail": false,
		"jail_weeks": 0,
		"sentence_remaining": 0,
		"fines_due": 0,
	}


## Returns a float in [0, 1) and advances the serializable RNG state once.
func randf_seeded() -> float:
	var generator := _generator_at_current_state()
	var value := generator.randf()
	rng_state = generator.state
	return value


## Returns an integer in [0, max_value). Non-positive bounds return zero and do
## not consume randomness, which keeps callers deterministic on empty lists.
func randi_seeded(max_value: int) -> int:
	if max_value <= 0:
		return 0
	var generator := _generator_at_current_state()
	var value := generator.randi_range(0, max_value - 1)
	rng_state = generator.state
	return value


func _generator_at_current_state() -> RandomNumberGenerator:
	var generator := RandomNumberGenerator.new()
	generator.seed = seed
	if rng_state != 0:
		generator.state = rng_state
	return generator


func add_history(text: String) -> void:
	var clean_text := text.strip_edges()
	if clean_text.is_empty():
		return
	event_history.append(clean_text)
	state_changed.emit()


## Spends this week's discretionary hours. Failed attempts leave all state intact.
func spend_time(hours: int, reason: String) -> bool:
	if hours <= 0 or hours > weekly_time:
		return false
	weekly_time -= hours
	var actions: Array = flags.get("weekly_actions", [])
	actions.append({
		"week_index": int(calendar.get("week_index", 0)),
		"hours": hours,
		"reason": reason.strip_edges(),
	})
	flags["weekly_actions"] = actions
	state_changed.emit()
	return true


## Complete, JSON-safe representation. Every mutable container is deep-copied so
## save code cannot accidentally mutate the running simulation.
func to_dict() -> Dictionary:
	return {
		"created": created,
		"player_name": player_name,
		"pronouns": pronouns,
		"appearance": appearance,
		"background_id": background_id,
		"traits": traits.duplicate(),
		"birth_year": birth_year,
		"age": age,
		"calendar": calendar.duplicate(true),
		"cash": cash,
		"savings": savings,
		"debt": debt,
		"ledger": ledger.duplicate(true),
		"health": health,
		"happiness": happiness,
		"stress": stress,
		"reputation": reputation,
		"energy": energy,
		"weekly_time": weekly_time,
		"skills": skills.duplicate(true),
		"education": education.duplicate(),
		"employment": employment.duplicate(true),
		"housing_id": housing_id,
		"owned_properties": owned_properties.duplicate(),
		"relationships": relationships.duplicate(true),
		"business": business.duplicate(true),
		"crypto": crypto.duplicate(true),
		"crime": crime.duplicate(true),
		"active_activities": active_activities.duplicate(true),
		"delayed_effects": delayed_effects.duplicate(true),
		"event_history": event_history.duplicate(),
		"cooldowns": cooldowns.duplicate(true),
		"flags": flags.duplicate(true),
		"last_week_summary": last_week_summary.duplicate(),
		"seed": seed,
		"rng_state": rng_state,
	}


## Loads defensive, normalized data. SaveSystem calls this on a staging instance
## first, so malformed data never partially overwrites a live game.
func from_dict(data: Variant) -> bool:
	if not data is Dictionary:
		return false
	var source: Dictionary = data
	var loaded_seed := _normalized_seed(_safe_int(source.get("seed", DEFAULT_SEED), DEFAULT_SEED))
	_reset_values(loaded_seed)

	created = bool(source.get("created", created))
	player_name = str(source.get("player_name", player_name)).strip_edges().left(80)
	pronouns = str(source.get("pronouns", pronouns)).strip_edges().left(40)
	if pronouns.is_empty():
		pronouns = "They/Them"
	appearance = clampi(_safe_int(source.get("appearance", appearance), appearance), 0, 99)
	background_id = str(source.get("background_id", background_id)).strip_edges().left(80)
	traits = _string_array(source.get("traits", traits))

	birth_year = clampi(_safe_int(source.get("birth_year", birth_year), birth_year), 1900, 9999)
	age = clampi(_safe_int(source.get("age", age), age), 0, 150)
	calendar = _sanitized_calendar(source.get("calendar", calendar))

	cash = _safe_int(source.get("cash", cash), cash)
	savings = maxi(0, _safe_int(source.get("savings", savings), savings))
	debt = maxi(0, _safe_int(source.get("debt", debt), debt))
	ledger = _ledger_array(source.get("ledger", ledger))

	health = _stat(source.get("health", health), health)
	happiness = _stat(source.get("happiness", happiness), happiness)
	stress = _stat(source.get("stress", stress), stress)
	reputation = clampi(_safe_int(source.get("reputation", reputation), reputation), -100, 100)
	energy = _stat(source.get("energy", energy), energy)
	weekly_time = clampi(_safe_int(source.get("weekly_time", weekly_time), weekly_time), 0, 168)

	skills = _sanitized_skills(source.get("skills", skills))
	education = _string_array(source.get("education", education))
	employment = _merged_dictionary(_default_employment(), source.get("employment", {}))
	housing_id = str(source.get("housing_id", housing_id)).strip_edges().left(100)
	owned_properties = _string_array(source.get("owned_properties", owned_properties))
	relationships = _dictionary_array(source.get("relationships", relationships))

	business = _merged_dictionary(_default_business(), source.get("business", {}))
	crypto = _merged_dictionary(_default_crypto(), source.get("crypto", {}))
	crime = _merged_dictionary(_default_crime(), source.get("crime", {}))
	active_activities = _dictionary_array(source.get("active_activities", active_activities))
	delayed_effects = _dictionary_array(source.get("delayed_effects", delayed_effects))
	event_history = _string_array(source.get("event_history", event_history), false)
	cooldowns = _dictionary_or_copy(source.get("cooldowns", cooldowns), cooldowns)
	flags = _merged_dictionary(flags, source.get("flags", {}))
	last_week_summary = _string_array(source.get("last_week_summary", last_week_summary), false)

	rng_state = _safe_int(source.get("rng_state", rng_state), rng_state)
	if rng_state == 0:
		var generator := RandomNumberGenerator.new()
		generator.seed = seed
		rng_state = generator.state

	_normalize_loaded_state()
	state_changed.emit()
	return true


func _normalize_loaded_state() -> void:
	employment["weekly_pay"] = maxi(0, _safe_int(employment.get("weekly_pay", 0), 0))
	employment["performance"] = _stat(employment.get("performance", 50), 50)
	employment["weeks"] = maxi(0, _safe_int(employment.get("weeks", 0), 0))
	employment["hours_per_week"] = clampi(_safe_int(employment.get("hours_per_week", 0), 0), 0, 80)
	if str(employment.get("job_id", "")).is_empty():
		employment["active"] = false

	for key in ["price", "staff", "capacity", "reputation", "demand", "marketing_budget", "maintenance_budget", "expansion_level", "last_customers", "last_revenue", "last_expenses", "lifetime_profit", "last_processed_week"]:
		business[key] = _safe_int(business.get(key, 0), 0)
	business["staff"] = maxi(0, int(business["staff"]))
	business["capacity"] = maxi(1, int(business["capacity"]))
	business["reputation"] = clampi(int(business["reputation"]), 0, 100)
	business["demand"] = clampi(int(business["demand"]), 0, 100)

	var maximum_time := clampi(_safe_int(flags.get("weekly_time_limit", DEFAULT_WEEKLY_TIME), DEFAULT_WEEKLY_TIME), 1, 168)
	flags["weekly_time_limit"] = maximum_time
	weekly_time = mini(weekly_time, maximum_time)
	flags["last_economy_week_index"] = maxi(0, _safe_int(flags.get("last_economy_week_index", 0), 0))
	flags["ledger_sequence"] = maxi(ledger.size(), _safe_int(flags.get("ledger_sequence", ledger.size()), ledger.size()))


func _sanitized_calendar(value: Variant) -> Dictionary:
	var result := calendar.duplicate(true)
	if value is Dictionary:
		var source: Dictionary = value
		var year := clampi(_safe_int(source.get("year", result["year"]), int(result["year"])), 1900, 9999)
		var month := clampi(_safe_int(source.get("month", result["month"]), int(result["month"])), 1, 12)
		var day_limit := _days_in_month(year, month)
		result["year"] = year
		result["month"] = month
		result["day"] = clampi(_safe_int(source.get("day", result["day"]), int(result["day"])), 1, day_limit)
		result["week"] = clampi(_safe_int(source.get("week", result["week"]), int(result["week"])), 1, 53)
		result["week_index"] = maxi(0, _safe_int(source.get("week_index", result["week_index"]), int(result["week_index"])))
	return result


func _sanitized_skills(value: Variant) -> Dictionary:
	var result := skills.duplicate(true)
	if not value is Dictionary:
		return result
	result.clear()
	var source: Dictionary = value
	for raw_key in source:
		var key := str(raw_key).strip_edges()
		if not key.is_empty():
			result[key] = _stat(source[raw_key], 0)
	for required_key in ["people", "grit", "technical", "education", "communication", "practical", "driving", "fitness", "discipline", "administration", "digital", "business"]:
		if not result.has(required_key):
			result[required_key] = 0
	return result


func _ledger_array(value: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not value is Array:
		return result
	for raw_entry in value:
		if not raw_entry is Dictionary:
			continue
		var entry: Dictionary = raw_entry.duplicate(true)
		entry["id"] = maxi(0, _safe_int(entry.get("id", result.size() + 1), result.size() + 1))
		entry["week_index"] = maxi(0, _safe_int(entry.get("week_index", 0), 0))
		entry["amount"] = _safe_int(entry.get("amount", 0), 0)
		entry["balance_after"] = _safe_int(entry.get("balance_after", 0), 0)
		entry["reason"] = str(entry.get("reason", "Transaction")).left(160)
		entry["category"] = str(entry.get("category", "other")).left(80)
		result.append(entry)
	return result


func _dictionary_array(value: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if value is Array:
		for raw_value in value:
			if raw_value is Dictionary:
				result.append(raw_value.duplicate(true))
	return result


func _string_array(value: Variant, unique: bool = true) -> Array[String]:
	var result: Array[String] = []
	if value is Array:
		for raw_value in value:
			var clean := str(raw_value).strip_edges()
			if not clean.is_empty() and (not unique or not result.has(clean)):
				result.append(clean.left(160))
	return result


func _merged_dictionary(base: Dictionary, incoming: Variant) -> Dictionary:
	var result := base.duplicate(true)
	if not incoming is Dictionary:
		return result
	var additions: Dictionary = incoming
	for key in additions:
		if result.get(key) is Dictionary and additions[key] is Dictionary:
			result[key] = _merged_dictionary(result[key], additions[key])
		else:
			var incoming_value: Variant = additions[key]
			result[key] = incoming_value.duplicate(true) if incoming_value is Array or incoming_value is Dictionary else incoming_value
	return result


func _dictionary_or_copy(value: Variant, fallback: Dictionary) -> Dictionary:
	return value.duplicate(true) if value is Dictionary else fallback.duplicate(true)


func _stat(value: Variant, fallback: int) -> int:
	return clampi(_safe_int(value, fallback), 0, 100)


func _safe_int(value: Variant, fallback: int) -> int:
	if value is int or value is float or value is bool:
		return int(value)
	if value is String and str(value).is_valid_int():
		return int(value)
	return fallback


func _normalized_seed(value: int) -> int:
	return DEFAULT_SEED if value == 0 else value


func _days_in_month(year: int, month: int) -> int:
	match month:
		2:
			return 29 if _is_leap_year(year) else 28
		4, 6, 9, 11:
			return 30
		_:
			return 31


func _is_leap_year(year: int) -> bool:
	return year % 400 == 0 or (year % 4 == 0 and year % 100 != 0)
