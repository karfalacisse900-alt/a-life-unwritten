class_name CharacterSystem
extends RefCounted

const CONTENT_PATH := "res://data/character_options.json"

var backgrounds: Array[Dictionary] = []
var traits: Array[Dictionary] = []

func _init() -> void:
	_load_content()

func get_backgrounds() -> Array[Dictionary]:
	return backgrounds.duplicate(true)

func get_traits() -> Array[Dictionary]:
	return traits.duplicate(true)

func get_background(background_id: String) -> Dictionary:
	for background in backgrounds:
		if str(background.get("id", "")) == background_id:
			return background.duplicate(true)
	return {}

func create_character(state: LifeGameState, form: Dictionary, economy: EconomySystem) -> String:
	var clean_name := str(form.get("name", "")).strip_edges().left(28)
	if clean_name.is_empty():
		return "Enter a name before starting."
	var background := get_background(str(form.get("background", "family_couch")))
	if background.is_empty():
		return "Choose a valid background."
	var chosen_traits: Array = form.get("traits", [])
	if chosen_traits.size() != 1:
		return "Choose exactly one starting trait."

	var chosen_seed := int(Time.get_unix_time_from_system()) & 0x7fffffff
	state.reset_new_game(chosen_seed)
	state.player_name = clean_name
	state.pronouns = str(form.get("pronouns", "they/them"))
	state.appearance = posmod(int(form.get("appearance", 0)), 12)
	state.background_id = str(background.get("id"))
	state.traits.clear()
	state.traits.append(str(chosen_traits[0]))
	state.cash = 0
	state.savings = int(background.get("savings", 0))
	state.debt = int(background.get("debt", 0))
	state.health = int(background.get("health", 70))
	state.happiness = int(background.get("happiness", 60))
	state.stress = int(background.get("stress", 22))
	state.reputation = int(background.get("reputation", 45))
	state.flags["weekly_time_limit"] = 60
	state.weekly_time = 60
	state.skills = {
		"communication": 12,
		"practical": 12,
		"fitness": 12,
		"driving": 8,
		"administration": 8,
		"discipline": 10,
		"business": 5,
		"grit": 10
	}
	var bonuses: Dictionary = background.get("skill_bonus", {})
	for skill_key in bonuses:
		state.skills[str(skill_key)] = int(state.skills.get(str(skill_key), 0)) + int(bonuses[skill_key])
	_apply_trait_tradeoff(state, str(chosen_traits[0]))
	economy.record(state, int(background.get("cash", 0)), "%s starting cash" % str(background.get("name", "Background")), "starting_balance")
	if state.savings > 0:
		state.ledger.append({
			"id": state.ledger.size() + 1,
			"week_index": 0,
			"date": "%04d-%02d-%02d" % [int(state.calendar.year), int(state.calendar.month), int(state.calendar.day)],
			"amount": state.savings,
			"balance_after": state.savings,
			"reason": "Starting savings",
			"category": "starting_balance",
			"account": "savings"
		})
	state.add_history("At 18, %s arrived in Bellwether with a plan still unwritten." % state.player_name)
	return "Character created. Choose where this new chapter begins."

func _apply_trait_tradeoff(state: LifeGameState, trait_id: String) -> void:
	match trait_id:
		"focused":
			state.skills["administration"] += 5
			state.stress += 3
		"charming":
			state.skills["communication"] += 6
			state.skills["discipline"] -= 2
		"resilient":
			state.skills["grit"] += 7
			state.skills["communication"] -= 2
		"bold":
			state.reputation += 3
			state.stress += 2

func _load_content() -> void:
	backgrounds.clear()
	traits.clear()
	if not FileAccess.file_exists(CONTENT_PATH):
		push_error("Character content missing: %s" % CONTENT_PATH)
		return
	var file := FileAccess.open(CONTENT_PATH, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text()) if file != null else null
	if not parsed is Dictionary:
		push_error("Character content is invalid JSON.")
		return
	for item in (parsed as Dictionary).get("backgrounds", []):
		if item is Dictionary: backgrounds.append((item as Dictionary).duplicate(true))
	for item in (parsed as Dictionary).get("traits", []):
		if item is Dictionary: traits.append((item as Dictionary).duplicate(true))
