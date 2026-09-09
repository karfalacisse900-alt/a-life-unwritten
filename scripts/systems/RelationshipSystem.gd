class_name RelationshipSystem
extends RefCounted

const PEOPLE_PATH := "res://data/people.json"
const MAX_HISTORY_ENTRIES := 24

var people: Array[Dictionary] = []
var _people_by_id: Dictionary = {}


func _init() -> void:
	_load_people()


func _load_people() -> Array[Dictionary]:
	people.clear()
	_people_by_id.clear()
	if not FileAccess.file_exists(PEOPLE_PATH):
		push_error("Relationship content is missing: %s" % PEOPLE_PATH)
		return people
	var file := FileAccess.open(PEOPLE_PATH, FileAccess.READ)
	if file == null:
		push_error("Relationship content could not be opened: %s" % PEOPLE_PATH)
		return people
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not (parsed is Dictionary):
		push_error("Relationship content is not a JSON object.")
		return people
	var source: Variant = (parsed as Dictionary).get("people", [])
	if not (source is Array):
		push_error("Relationship content has no people array.")
		return people
	for value: Variant in source:
		if not (value is Dictionary):
			continue
		var person := (value as Dictionary).duplicate(true)
		var person_id := str(person.get("id", ""))
		if person_id.is_empty() or _people_by_id.has(person_id):
			continue
		people.append(person)
		_people_by_id[person_id] = person
	return people


func get_people() -> Array[Dictionary]:
	return people.duplicate(true)


func seed_people(state: Variant) -> void:
	if people.is_empty():
		_load_people()
	var current_week := _week_index(state)
	for definition: Dictionary in people:
		var person_id := str(definition.get("id", ""))
		if person_id.is_empty() or _find_index(state, person_id) >= 0:
			continue
		var initial: Dictionary = definition.get("initial", {})
		var relationship := {
			"person_id": person_id,
			"name": str(definition.get("name", "Unknown")),
			"pronouns": str(definition.get("pronouns", "they/them")),
			"role": str(definition.get("role", "acquaintance")),
			"occupation": str(definition.get("occupation", "")),
			"portrait": str(definition.get("portrait", "default")),
			"bio": str(definition.get("bio", "")),
			"traits": (definition.get("traits", []) as Array).duplicate(),
			"actions": (definition.get("actions", []) as Array).duplicate(),
			"closeness": clampi(int(initial.get("closeness", 20)), 0, 100),
			"trust": clampi(int(initial.get("trust", 20)), 0, 100),
			"chemistry": clampi(int(initial.get("chemistry", 0)), 0, 100),
			"tension": clampi(int(initial.get("tension", 0)), 0, 100),
			"status": str(initial.get("status", "acquaintance")),
			"met_week": current_week,
			"last_interaction_week": current_week - 1,
			"interacted_this_week": false,
			"cooldowns": {},
			"flags": {},
			"history": [{
				"week_index": current_week,
				"text": "You began this chapter knowing %s." % str(definition.get("name", "them"))
			}]
		}
		state.relationships.append(relationship)


func get_relationship(state: Variant, person_id: String) -> Dictionary:
	var index := _find_index(state, person_id)
	if index < 0:
		return {}
	return (state.relationships[index] as Dictionary).duplicate(true)


func available_actions(state: Variant, person_id: String) -> Array[Dictionary]:
	var relationship := get_relationship(state, person_id)
	if relationship.is_empty():
		return []
	var result: Array[Dictionary] = []
	var action_ids: Array = relationship.get("actions", [])
	for action_value: Variant in action_ids:
		var action_id := str(action_value)
		var details := _action_details(action_id)
		if details.is_empty():
			continue
		var block_reason := _action_block_reason(state, relationship, action_id)
		details["available"] = block_reason.is_empty()
		details["blocked_reason"] = block_reason
		result.append(details)
	return result


func act(state: Variant, person_id: String, action_id: String, economy: Variant) -> String:
	seed_people(state)
	var index := _find_index(state, person_id)
	if index < 0:
		return "That person is not part of your life yet."
	var relationship: Dictionary = state.relationships[index]
	var allowed_actions: Array = relationship.get("actions", [])
	if not allowed_actions.has(action_id):
		return "%s is not comfortable with that kind of interaction." % str(relationship.get("name", "They"))
	var block_reason := _action_block_reason(state, relationship, action_id)
	if not block_reason.is_empty():
		return block_reason

	var details := _action_details(action_id)
	var hours := int(details.get("hours", 0))
	var cost := int(details.get("cost", 0))
	if state.cash < cost:
		return "You need $%d for that plan." % cost
	if not _spend_time(state, hours, "%s with %s" % [str(details.get("label", action_id)), str(relationship.get("name", "them"))]):
		return "You do not have %d free hours left this week." % hours
	if cost > 0:
		_record_money(economy, state, -cost, "%s with %s" % [str(details.get("label", "Relationship activity")), str(relationship.get("name", "friend"))], "relationships")

	var message := ""
	match action_id:
		"spend_time":
			_change(relationship, "closeness", 7)
			_change(relationship, "trust", 3)
			_change(relationship, "tension", -5)
			state.happiness = clampi(state.happiness + 3, 0, 100)
			message = "You made time for %s. The easy conversation brought you closer." % relationship["name"]
		"ask_help":
			var support := 75 if str(relationship.get("role", "")) == "family" else 50
			var roll := _roll(state, 100)
			if roll < int(relationship.get("trust", 0)):
				_record_money(economy, state, support, "%s helped with essentials" % relationship["name"], "relationships")
				_change(relationship, "trust", 2)
				message = "%s covered $%d of essentials and asked you to pay the kindness forward." % [relationship["name"], support]
			else:
				_change(relationship, "tension", 4)
				message = "%s could not help this time, but appreciated that you asked honestly." % relationship["name"]
		"gift":
			_change(relationship, "closeness", 5)
			_change(relationship, "trust", 2)
			_change(relationship, "tension", -3)
			message = "You chose a thoughtful gift for %s. It landed well." % relationship["name"]
		"argue":
			var constructive := int(relationship.get("trust", 0)) >= int(relationship.get("tension", 0))
			if constructive:
				_change(relationship, "trust", 2)
				_change(relationship, "tension", -4)
				message = "You and %s disagreed, listened, and cleared the air." % relationship["name"]
			else:
				_change(relationship, "closeness", -6)
				_change(relationship, "tension", 9)
				state.stress = clampi(state.stress + 4, 0, 100)
				message = "The argument with %s became personal. The tension lingers." % relationship["name"]
		"date":
			_change(relationship, "closeness", 6)
			_change(relationship, "chemistry", 5)
			_change(relationship, "tension", -2)
			if str(relationship.get("status", "")) not in ["dating", "partner"]:
				relationship["status"] = "dating"
				message = "You and %s agreed that this is officially a date, not just another hangout." % relationship["name"]
			else:
				message = "Your date with %s gave both of you a welcome change of pace." % relationship["name"]
			state.happiness = clampi(state.happiness + 4, 0, 100)
		"break_up":
			relationship["status"] = "former_partner"
			_change(relationship, "closeness", -18)
			_change(relationship, "trust", -8)
			_change(relationship, "tension", 16)
			state.happiness = clampi(state.happiness - 8, 0, 100)
			message = "You ended the relationship with %s. It was painful, but unambiguous." % relationship["name"]
		"business_proposal":
			var score := int(relationship.get("trust", 0)) + int(relationship.get("closeness", 0)) + int(state.business.get("reputation", 0))
			if score + _roll(state, 30) >= 125:
				state.business["partner_id"] = person_id
				state.business["staff"] = maxi(1, int(state.business.get("staff", 0)) + 1)
				state.business["capacity"] = maxi(1, int(state.business.get("capacity", 1)) + 4)
				relationship["status"] = "business_partner"
				_change(relationship, "trust", 5)
				message = "%s joined the business. Their help increased weekly capacity." % relationship["name"]
			else:
				_change(relationship, "tension", 3)
				message = "%s passed on the proposal. They want to see a stronger plan first." % relationship["name"]
		_:
			return "That relationship action is unavailable."

	relationship["last_interaction_week"] = _week_index(state)
	relationship["interacted_this_week"] = true
	var cooldowns: Dictionary = relationship.get("cooldowns", {})
	cooldowns[action_id] = _week_index(state) + int(details.get("cooldown_weeks", 1))
	relationship["cooldowns"] = cooldowns
	_add_relationship_history(relationship, message, _week_index(state))
	state.relationships[index] = relationship
	return message


func process_week(state: Variant) -> Array[String]:
	seed_people(state)
	var summaries: Array[String] = []
	var current_week := _week_index(state)
	if int(state.flags.get("relationships_processed_week", -1)) == current_week:
		return summaries
	state.flags["relationships_processed_week"] = current_week
	var jailed := bool(state.crime.get("in_jail", false))
	var employed := not str(state.employment.get("job_id", "")).is_empty()
	for index in range(state.relationships.size()):
		var relationship: Dictionary = state.relationships[index]
		var interacted := bool(relationship.get("interacted_this_week", false))
		var last_interaction := int(relationship.get("last_interaction_week", current_week))
		var role := str(relationship.get("role", ""))
		var status := str(relationship.get("status", ""))
		if role == "coworker":
			relationship["context"] = "coworker" if employed else "former_coworker"
		if interacted:
			_change(relationship, "tension", -1)
		elif current_week - last_interaction >= 8 and current_week % 4 == 0:
			_change(relationship, "closeness", -1)
		if jailed and role in ["family", "friend"] and current_week % 4 == 0:
			_change(relationship, "tension", 1)
		if status in ["dating", "partner"]:
			if current_week - last_interaction >= 3:
				_change(relationship, "closeness", -2)
				_change(relationship, "tension", 3)
				if current_week % 4 == 0:
					summaries.append("%s feels distant after several quiet weeks." % relationship.get("name", "Your partner"))
			elif interacted:
				state.happiness = clampi(state.happiness + 1, 0, 100)
		if int(relationship.get("tension", 0)) >= 80 and status not in ["rival", "former_partner"]:
			relationship["status"] = "estranged"
			summaries.append("Your relationship with %s became estranged." % relationship.get("name", "someone close"))
			relationship["tension"] = 65
		relationship["interacted_this_week"] = false
		state.relationships[index] = relationship
	return summaries


func _action_details(action_id: String) -> Dictionary:
	match action_id:
		"spend_time":
			return {"id": action_id, "label": "Spend time", "hours": 3, "cost": 18, "cooldown_weeks": 1}
		"ask_help":
			return {"id": action_id, "label": "Ask for help", "hours": 2, "cost": 0, "cooldown_weeks": 6}
		"gift":
			return {"id": action_id, "label": "Give a gift", "hours": 1, "cost": 45, "cooldown_weeks": 2}
		"argue":
			return {"id": action_id, "label": "Talk through conflict", "hours": 1, "cost": 0, "cooldown_weeks": 2}
		"date":
			return {"id": action_id, "label": "Go on a date", "hours": 4, "cost": 35, "cooldown_weeks": 1}
		"break_up":
			return {"id": action_id, "label": "Break up", "hours": 1, "cost": 0, "cooldown_weeks": 1}
		"business_proposal":
			return {"id": action_id, "label": "Make a business proposal", "hours": 3, "cost": 0, "cooldown_weeks": 8}
	return {}


func _action_block_reason(state: Variant, relationship: Dictionary, action_id: String) -> String:
	var details := _action_details(action_id)
	if details.is_empty():
		return "That relationship action is unavailable."
	var current_week := _week_index(state)
	var cooldowns: Dictionary = relationship.get("cooldowns", {})
	if current_week < int(cooldowns.get(action_id, -1)):
		return "Give this relationship a little time before doing that again."
	if bool(state.crime.get("in_jail", false)) and str(relationship.get("role", "")) not in ["family", "public_defender"]:
		return "You cannot arrange that interaction while in jail."
	if int(state.weekly_time) < int(details.get("hours", 0)):
		return "You do not have enough free time left this week."
	if int(state.cash) < int(details.get("cost", 0)):
		return "You cannot afford that plan right now."
	match action_id:
		"ask_help":
			if int(relationship.get("closeness", 0)) < 35 or int(relationship.get("trust", 0)) < 35:
				return "Build more trust before asking for material help."
		"date":
			if str(relationship.get("role", "")) in ["family", "public_defender", "rival"]:
				return "Dating is not available in this relationship."
			if int(relationship.get("closeness", 0)) < 42 or int(relationship.get("chemistry", 0)) < 35:
				return "The connection is not ready for a date."
			if str(relationship.get("status", "")) == "former_partner":
				return "That relationship has ended."
		"break_up":
			if str(relationship.get("status", "")) not in ["dating", "partner"]:
				return "You are not currently dating this person."
		"business_proposal":
			if not bool(state.business.get("active", false)):
				return "Start a business before inviting a partner."
			if not str(state.business.get("partner_id", "")).is_empty():
				return "Your business already has a partner."
			if int(relationship.get("trust", 0)) < 40 or int(relationship.get("closeness", 0)) < 30:
				return "A business partnership needs more trust first."
	return ""


func _find_index(state: Variant, person_id: String) -> int:
	for index in range(state.relationships.size()):
		var relationship: Dictionary = state.relationships[index]
		if str(relationship.get("person_id", relationship.get("id", ""))) == person_id:
			return index
	return -1


func _change(relationship: Dictionary, field: String, amount: int) -> void:
	relationship[field] = clampi(int(relationship.get(field, 0)) + amount, 0, 100)


func _add_relationship_history(relationship: Dictionary, text: String, week_index: int) -> void:
	var history: Array = relationship.get("history", [])
	history.append({"week_index": week_index, "text": text})
	while history.size() > MAX_HISTORY_ENTRIES:
		history.pop_front()
	relationship["history"] = history


func _spend_time(state: Variant, hours: int, reason: String) -> bool:
	if hours <= 0:
		return true
	if state.has_method("spend_time"):
		return bool(state.spend_time(hours, reason))
	if int(state.weekly_time) < hours:
		return false
	state.weekly_time -= hours
	return true


func _record_money(economy: Variant, state: Variant, amount: int, reason: String, category: String) -> void:
	if economy != null and economy.has_method("record"):
		economy.record(state, amount, reason, category)
		return
	state.cash += amount
	var sequence := maxi(int(state.flags.get("ledger_sequence", state.ledger.size())), state.ledger.size()) + 1
	state.flags["ledger_sequence"] = sequence
	state.ledger.append({
		"id": sequence,
		"week_index": _week_index(state),
		"date": _date_label(state),
		"amount": amount,
		"balance_after": state.cash,
		"reason": reason,
		"category": category
	})


func _week_index(state: Variant) -> int:
	return int(state.calendar.get("week_index", 0))


func _date_label(state: Variant) -> String:
	return "%04d-%02d-%02d" % [
		int(state.calendar.get("year", 2026)),
		int(state.calendar.get("month", 1)),
		int(state.calendar.get("day", 1))
	]


func _roll(state: Variant, maximum: int) -> int:
	if maximum <= 1:
		return 0
	if state.has_method("randi_seeded"):
		return absi(int(state.randi_seeded(maximum))) % maximum
	return 0
