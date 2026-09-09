class_name EventSystem
extends RefCounted

const EVENTS_PATH := "res://data/events.json"

var events: Array[Dictionary] = []
var validation_errors: Array[String] = []
var _events_by_id: Dictionary = {}


func _init() -> void:
	load_content()


func load_content() -> Array[Dictionary]:
	events.clear()
	_events_by_id.clear()
	validation_errors.clear()
	if not FileAccess.file_exists(EVENTS_PATH):
		validation_errors.append("Missing event content: %s" % EVENTS_PATH)
		push_error(validation_errors[-1])
		return events
	var file := FileAccess.open(EVENTS_PATH, FileAccess.READ)
	if file == null:
		validation_errors.append("Could not open event content: %s" % EVENTS_PATH)
		push_error(validation_errors[-1])
		return events
	var json := JSON.new()
	var error := json.parse(file.get_as_text())
	if error != OK:
		validation_errors.append("Event JSON error on line %d: %s" % [json.get_error_line(), json.get_error_message()])
		push_error(validation_errors[-1])
		return events
	var parsed: Variant = json.data
	if not (parsed is Dictionary):
		validation_errors.append("Event content root must be an object.")
		return events
	var source: Variant = (parsed as Dictionary).get("events", [])
	if not (source is Array):
		validation_errors.append("Event content must contain an events array.")
		return events
	for index in range((source as Array).size()):
		var value: Variant = (source as Array)[index]
		if not (value is Dictionary):
			validation_errors.append("Event at index %d is not an object." % index)
			continue
		var event := (value as Dictionary).duplicate(true)
		var issue := _validate_event(event)
		if not issue.is_empty():
			validation_errors.append("Event %d: %s" % [index, issue])
			continue
		var event_id := str(event["id"])
		if _events_by_id.has(event_id):
			validation_errors.append("Duplicate event id: %s" % event_id)
			continue
		events.append(event)
		_events_by_id[event_id] = event
	for issue: String in validation_errors:
		push_warning(issue)
	return events


func get_event(event_id: String) -> Dictionary:
	if not _events_by_id.has(event_id):
		return {}
	return (_events_by_id[event_id] as Dictionary).duplicate(true)


func is_eligible(state: Variant, event: Dictionary) -> bool:
	return _event_block_reason(state, event).is_empty()


func get_eligible_events(state: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for event: Dictionary in events:
		if is_eligible(state, event):
			result.append(event.duplicate(true))
	return result


func select_event(state: Variant) -> Dictionary:
	var candidates := get_eligible_events(state)
	if candidates.is_empty():
		return {}
	var total_weight := 0
	for event: Dictionary in candidates:
		total_weight += maxi(1, int(event.get("weight", 1)))
	var roll := _roll(state, total_weight)
	for event: Dictionary in candidates:
		roll -= maxi(1, int(event.get("weight", 1)))
		if roll < 0:
			return event
	return candidates[-1]


func get_available_choices(state: Variant, event_id: String) -> Array[Dictionary]:
	var event := get_event(event_id)
	if event.is_empty():
		return []
	var result: Array[Dictionary] = []
	for value: Variant in event.get("choices", []):
		if not (value is Dictionary):
			continue
		var choice := (value as Dictionary).duplicate(true)
		var reason := _condition_failure(state, choice.get("requirements", {}))
		var known_cost := int(choice.get("known_cost", 0))
		if reason.is_empty() and known_cost > int(state.cash):
			reason = "You need $%d in cash." % known_cost
		choice["available"] = reason.is_empty()
		choice["blocked_reason"] = reason
		result.append(choice)
	return result


func resolve(state: Variant, event_id: String, choice_id: String, economy: Variant) -> Dictionary:
	if not _events_by_id.has(event_id):
		return {"ok": false, "error": "That event is no longer available."}
	var event: Dictionary = _events_by_id[event_id]
	var event_block := _event_block_reason(state, event)
	if not event_block.is_empty():
		return {"ok": false, "error": event_block}
	var choice := _find_choice(event, choice_id)
	if choice.is_empty():
		return {"ok": false, "error": "That choice is not available."}
	var requirement_failure := _condition_failure(state, choice.get("requirements", {}))
	if not requirement_failure.is_empty():
		return {"ok": false, "error": requirement_failure}
	var known_cost := maxi(0, int(choice.get("known_cost", 0)))
	if int(state.cash) < known_cost:
		return {"ok": false, "error": "You need $%d in cash for that choice." % known_cost}
	if known_cost > 0:
		_record_money(economy, state, -known_cost, str(choice.get("cost_reason", "%s — %s" % [event.get("title", "Event"), choice.get("text", "Choice")])), "event_choice")

	var outcomes: Array = choice.get("outcomes", [])
	var outcome := _select_outcome(state, outcomes)
	if outcome.is_empty():
		return {"ok": false, "error": "That choice has no valid outcome."}
	var effect_summaries: Array[String] = []
	for effect_value: Variant in outcome.get("effects", []):
		if not (effect_value is Dictionary):
			continue
		var effect_summary := _apply_effect(state, effect_value, economy)
		if not effect_summary.is_empty():
			effect_summaries.append(effect_summary)
	var scheduled := 0
	for delayed_value: Variant in outcome.get("delayed", []):
		if not (delayed_value is Dictionary):
			continue
		_schedule_delayed(state, event_id, choice_id, delayed_value)
		scheduled += 1

	var current_week := _week_index(state)
	state.flags["event_seen:%s" % event_id] = true
	state.cooldowns[event_id] = current_week + maxi(0, int(event.get("cooldown_weeks", 0)))
	var outcome_text := str(outcome.get("text", "Your decision has consequences."))
	if state.has_method("add_history"):
		state.add_history("%s — %s" % [str(event.get("title", "Life event")), outcome_text])
	else:
		state.event_history.append("%s — %s" % [str(event.get("title", "Life event")), outcome_text])
	return {
		"ok": true,
		"event_id": event_id,
		"choice_id": choice_id,
		"title": str(event.get("title", "Life event")),
		"event_text": str(event.get("text", "")),
		"text": outcome_text,
		"effect_summaries": effect_summaries,
		"scheduled": scheduled
	}


func process_delayed(state: Variant, economy: Variant) -> Array[String]:
	var summaries: Array[String] = []
	var remaining: Array[Dictionary] = []
	var current_week := _week_index(state)
	for value: Variant in state.delayed_effects:
		if not (value is Dictionary):
			continue
		var delayed: Dictionary = value
		if int(delayed.get("due_week_index", current_week + 1)) > current_week:
			remaining.append(delayed)
			continue
		var text := str(delayed.get("text", "A past decision has caught up with you."))
		var details: Array[String] = []
		for effect_value: Variant in delayed.get("effects", []):
			if not (effect_value is Dictionary):
				continue
			var effect_summary := _apply_effect(state, effect_value, economy)
			if not effect_summary.is_empty():
				details.append(effect_summary)
		var summary := text
		if not details.is_empty():
			summary += " " + " ".join(details)
		summaries.append(summary)
		if state.has_method("add_history"):
			state.add_history(summary)
		else:
			state.event_history.append(summary)
	state.delayed_effects.assign(remaining)
	return summaries


func _validate_event(event: Dictionary) -> String:
	var event_id := str(event.get("id", ""))
	if event_id.is_empty():
		return "missing id"
	if str(event.get("title", "")).is_empty() or str(event.get("text", "")).is_empty():
		return "%s is missing title or text" % event_id
	if str(event.get("repeat", "")) not in ["once", "repeatable"]:
		return "%s has invalid repeat rule" % event_id
	var choices: Variant = event.get("choices", [])
	if not (choices is Array) or (choices as Array).is_empty():
		return "%s has no choices" % event_id
	var choice_ids: Dictionary = {}
	for choice_value: Variant in choices:
		if not (choice_value is Dictionary):
			return "%s contains a non-object choice" % event_id
		var choice: Dictionary = choice_value
		var choice_id := str(choice.get("id", ""))
		if choice_id.is_empty() or choice_ids.has(choice_id):
			return "%s has a missing or duplicate choice id" % event_id
		choice_ids[choice_id] = true
		if not choice.has("known_cost") or int(choice.get("known_cost", -1)) < 0:
			return "%s/%s has no valid known_cost" % [event_id, choice_id]
		var outcomes: Variant = choice.get("outcomes", [])
		if not (outcomes is Array) or (outcomes as Array).is_empty():
			return "%s/%s has no outcomes" % [event_id, choice_id]
	return ""


func _event_block_reason(state: Variant, event: Dictionary) -> String:
	var event_id := str(event.get("id", ""))
	if str(event.get("repeat", "repeatable")) == "once" and bool(state.flags.get("event_seen:%s" % event_id, false)):
		return "That event has already happened."
	var current_week := _week_index(state)
	if current_week < int(state.cooldowns.get(event_id, -1)):
		return "That event is still on cooldown."
	return _condition_failure(state, event.get("eligibility", {}))


func _condition_failure(state: Variant, raw_conditions: Variant) -> String:
	if not (raw_conditions is Dictionary):
		return ""
	var conditions: Dictionary = raw_conditions
	var jailed := bool(state.crime.get("in_jail", false))
	if conditions.has("in_jail") and jailed != bool(conditions["in_jail"]):
		return "This is not available in your current legal situation."
	var employed := not str(state.employment.get("job_id", "")).is_empty()
	var employment_status := str(conditions.get("employment_status", ""))
	if employment_status == "employed" and not employed:
		return "You need a job for this event."
	if employment_status == "unemployed" and employed:
		return "This event is only for an unemployed character."
	if conditions.has("employment_performance_min") and int(state.employment.get("performance", 0)) < int(conditions["employment_performance_min"]):
		return "Your work performance is not high enough."
	if conditions.has("employment_performance_max") and int(state.employment.get("performance", 0)) > int(conditions["employment_performance_max"]):
		return "Your work performance is outside this event's range."
	if conditions.has("employment_weeks_min") and int(state.employment.get("weeks", 0)) < int(conditions["employment_weeks_min"]):
		return "You have not held this job long enough."
	if conditions.has("job_ids") and not (state.employment.get("job_id", "") in conditions["job_ids"]):
		return "Your current job does not qualify."
	if conditions.has("housing_ids") and not (state.housing_id in conditions["housing_ids"]):
		return "Your current housing does not qualify."
	if conditions.has("debt_min") and int(state.debt) < int(conditions["debt_min"]):
		return "Your debt is below this event's threshold."
	if conditions.has("debt_max") and int(state.debt) > int(conditions["debt_max"]):
		return "Your debt is above this event's threshold."
	if conditions.has("cash_min") and int(state.cash) < int(conditions["cash_min"]):
		return "You do not have enough cash."
	if conditions.has("cash_max") and int(state.cash) > int(conditions["cash_max"]):
		return "This event only occurs during a cash shortage."
	for field in ["health", "happiness", "stress", "reputation", "energy"]:
		if conditions.has("%s_min" % field) and int(state.get(field)) < int(conditions["%s_min" % field]):
			return "%s is below the required level." % field.capitalize()
		if conditions.has("%s_max" % field) and int(state.get(field)) > int(conditions["%s_max" % field]):
			return "%s is above this event's range." % field.capitalize()
	if conditions.has("weekly_time_min") and int(state.weekly_time) < int(conditions["weekly_time_min"]):
		return "You do not have enough free time this week."
	if conditions.has("week_index_min") and _week_index(state) < int(conditions["week_index_min"]):
		return "This event cannot occur yet."
	if conditions.has("business_active") and bool(state.business.get("active", false)) != bool(conditions["business_active"]):
		return "Your business status does not qualify."
	if conditions.has("business_reputation_min") and int(state.business.get("reputation", 0)) < int(conditions["business_reputation_min"]):
		return "Your business reputation is not high enough."
	if conditions.has("business_staff_min") and int(state.business.get("staff", 0)) < int(conditions["business_staff_min"]):
		return "Your business does not have enough staff."
	if conditions.has("mining_equipment") and _has_mining_equipment(state) != bool(conditions["mining_equipment"]):
		return "This event requires active mining equipment."
	if conditions.has("suspicion_min") and int(state.crime.get("suspicion", 0)) < int(conditions["suspicion_min"]):
		return "Suspicion is below this event's threshold."
	if conditions.has("suspicion_max") and int(state.crime.get("suspicion", 0)) > int(conditions["suspicion_max"]):
		return "Suspicion is above this event's range."
	if conditions.has("criminal_record_min") and _criminal_record_count(state) < int(conditions["criminal_record_min"]):
		return "This event requires a criminal record."
	if conditions.has("skills_min"):
		var minimum_skills: Dictionary = conditions["skills_min"]
		for skill_value: Variant in minimum_skills.keys():
			var skill_id := str(skill_value)
			if int(state.skills.get(skill_id, 0)) < int(minimum_skills[skill_value]):
				return "Your %s skill is not high enough." % skill_id
	if conditions.has("education_has") and not state.education.has(str(conditions["education_has"])):
		return "You do not have the required qualification."
	if conditions.has("relationship_min"):
		var relation_failure := _relationship_min_failure(state, conditions["relationship_min"])
		if not relation_failure.is_empty():
			return relation_failure
	if conditions.has("relationship_status"):
		var status_condition: Dictionary = conditions["relationship_status"]
		var relationship := _relationship(state, str(status_condition.get("person_id", "")))
		if relationship.is_empty() or not (str(relationship.get("status", "")) in status_condition.get("values", [])):
			return "That relationship is not at the required stage."
	if conditions.has("active_activity_ids"):
		var found_activity := false
		for activity_value: Variant in state.active_activities:
			if not (activity_value is Dictionary):
				continue
			var activity: Dictionary = activity_value
			var activity_id := str(activity.get("id", activity.get("activity_id", activity.get("course_id", ""))))
			if activity_id in conditions["active_activity_ids"]:
				found_activity = true
				break
		if not found_activity:
			return "You do not have the relevant activity in progress."
	if conditions.has("flags_equals"):
		var expected_flags: Dictionary = conditions["flags_equals"]
		for flag_value: Variant in expected_flags.keys():
			if state.flags.get(str(flag_value)) != expected_flags[flag_value]:
				return "A required prior decision has not occurred."
	return ""


func _relationship_min_failure(state: Variant, raw_condition: Variant) -> String:
	if not (raw_condition is Dictionary):
		return ""
	var condition: Dictionary = raw_condition
	var relationship := _relationship(state, str(condition.get("person_id", "")))
	if relationship.is_empty():
		return "The required person is not in your life yet."
	var field := str(condition.get("field", "closeness"))
	if int(relationship.get(field, 0)) < int(condition.get("value", 0)):
		return "That relationship is not strong enough yet."
	return ""


func _find_choice(event: Dictionary, choice_id: String) -> Dictionary:
	for value: Variant in event.get("choices", []):
		if value is Dictionary and str((value as Dictionary).get("id", "")) == choice_id:
			return value as Dictionary
	return {}


func _select_outcome(state: Variant, outcomes: Array) -> Dictionary:
	if outcomes.is_empty():
		return {}
	var total_weight := 0
	for value: Variant in outcomes:
		if value is Dictionary:
			total_weight += maxi(1, int((value as Dictionary).get("weight", 1)))
	if total_weight <= 0:
		return {}
	var roll := _roll(state, total_weight)
	for value: Variant in outcomes:
		if not (value is Dictionary):
			continue
		var outcome: Dictionary = value
		roll -= maxi(1, int(outcome.get("weight", 1)))
		if roll < 0:
			return outcome
	return outcomes[-1] as Dictionary


func _schedule_delayed(state: Variant, event_id: String, choice_id: String, raw_delayed: Variant) -> void:
	var delayed: Dictionary = raw_delayed
	var due_week := _week_index(state) + maxi(1, int(delayed.get("after_weeks", 1)))
	state.delayed_effects.append({
		"id": "%s:%s:%d:%d" % [event_id, choice_id, due_week, state.delayed_effects.size()],
		"source_event_id": event_id,
		"choice_id": choice_id,
		"due_week_index": due_week,
		"text": str(delayed.get("text", "A past choice has consequences.")),
		"effects": (delayed.get("effects", []) as Array).duplicate(true)
	})


func _apply_effect(state: Variant, raw_effect: Variant, economy: Variant) -> String:
	var effect: Dictionary = raw_effect
	var effect_type := str(effect.get("type", ""))
	var amount := int(effect.get("amount", 0))
	if effect_type in ["health", "happiness", "stress", "reputation", "energy"]:
		var stat_minimum := -100 if effect_type == "reputation" else 0
		state.set(effect_type, clampi(int(state.get(effect_type)) + amount, stat_minimum, 100))
		return "%s %s%d." % [effect_type.capitalize(), "+" if amount >= 0 else "", amount]
	match effect_type:
		"stat":
			var stat := str(effect.get("field", ""))
			if stat in ["health", "happiness", "stress", "reputation", "energy"]:
				var stat_minimum := -100 if stat == "reputation" else 0
				state.set(stat, clampi(int(state.get(stat)) + amount, stat_minimum, 100))
				return "%s %s%d." % [stat.capitalize(), "+" if amount >= 0 else "", amount]
		"money":
			return _apply_money_effect(economy, state, amount, str(effect.get("reason", "Event transaction")), str(effect.get("category", "event")))
		"debt":
			var previous_debt := int(state.debt)
			state.debt = maxi(0, previous_debt + amount)
			var actual_change := int(state.debt) - previous_debt
			return "Debt %s$%d." % ["+" if actual_change >= 0 else "-", absi(actual_change)]
		"skill":
			var skill_id := str(effect.get("field", "general"))
			state.skills[skill_id] = clampi(int(state.skills.get(skill_id, 0)) + amount, 0, 100)
			return "%s skill %s%d." % [skill_id.capitalize(), "+" if amount >= 0 else "", amount]
		"time":
			if amount > 0 and _spend_time(state, amount, str(effect.get("reason", "Event choice"))):
				return "%d free hours used." % amount
		"employment_performance":
			state.employment["performance"] = clampi(int(state.employment.get("performance", 50)) + amount, 0, 100)
			return "Work performance %s%d." % ["+" if amount >= 0 else "", amount]
		"employment_promotion":
			var raise_amount := maxi(0, int(effect.get("pay_raise", 0)))
			state.employment["weekly_pay"] = maxi(0, int(state.employment.get("weekly_pay", 0)) + raise_amount)
			var title := str(state.employment.get("title", "Employee"))
			if not title.begins_with("Senior "):
				state.employment["title"] = "Senior %s" % title
			return "Promoted with a $%d weekly raise." % raise_amount
		"employment_lost":
			if not str(state.employment.get("job_id", "")).is_empty():
				state.employment = {"job_id": "", "title": "Unemployed", "weekly_pay": 0, "performance": 50, "weeks": 0}
				return "Employment ended: %s." % str(effect.get("reason", "circumstances changed"))
		"relationship":
			var person_id := str(effect.get("person_id", ""))
			var relationship_index := _relationship_index(state, person_id)
			if relationship_index >= 0:
				var relationship: Dictionary = state.relationships[relationship_index]
				var relation_field := str(effect.get("field", "closeness"))
				relationship[relation_field] = clampi(int(relationship.get(relation_field, 0)) + amount, 0, 100)
				state.relationships[relationship_index] = relationship
				return "%s: %s %s%d." % [relationship.get("name", "Relationship"), relation_field, "+" if amount >= 0 else "", amount]
		"relationship_status":
			var relationship_index := _relationship_index(state, str(effect.get("person_id", "")))
			if relationship_index >= 0:
				var relationship: Dictionary = state.relationships[relationship_index]
				relationship["status"] = str(effect.get("value", relationship.get("status", "friend")))
				state.relationships[relationship_index] = relationship
				return "Your relationship with %s changed." % relationship.get("name", "someone")
		"business":
			var business_field := str(effect.get("field", ""))
			var updated := int(state.business.get(business_field, 0)) + amount
			if business_field in ["reputation", "demand"]:
				updated = clampi(updated, 0, 100)
			else:
				updated = maxi(0, updated)
			state.business[business_field] = updated
			return "Business %s %s%d." % [business_field, "+" if amount >= 0 else "", amount]
		"mining":
			var mining: Dictionary = state.crypto.get("mining", {})
			var mining_field := str(effect.get("field", ""))
			var updated := int(mining.get(mining_field, 0)) + amount
			if mining_field in ["condition", "efficiency"]:
				updated = clampi(updated, 0, 100)
			else:
				updated = maxi(0, updated)
			mining[mining_field] = updated
			state.crypto["mining"] = mining
			return "Mining %s %s%d." % [mining_field, "+" if amount >= 0 else "", amount]
		"crime":
			var crime_field := str(effect.get("field", ""))
			if effect.has("value"):
				state.crime[crime_field] = effect["value"]
				return "%s changed." % crime_field.capitalize()
			if crime_field == "record" and state.crime.get("record", []) is Array:
				var record: Array = state.crime.get("record", [])
				for _entry in range(maxi(0, amount)):
					record.append({
						"id": "event_conviction_%d_%d" % [_week_index(state), record.size()],
						"week_index": _week_index(state),
						"label": "Court conviction",
						"source": "life_event"
					})
				state.crime["record"] = record
				return "Criminal record gained %d entry." % maxi(0, amount)
			var updated := int(state.crime.get(crime_field, 0)) + amount
			if crime_field == "suspicion":
				updated = clampi(updated, 0, 100)
			else:
				updated = maxi(0, updated)
			state.crime[crime_field] = updated
			return "%s %s%d." % [crime_field.capitalize(), "+" if amount >= 0 else "", amount]
		"flag":
			state.flags[str(effect.get("field", "event_flag"))] = effect.get("value", true)
		"activity_progress":
			var activity_id := str(effect.get("activity_id", ""))
			for index in range(state.active_activities.size()):
				var activity: Dictionary = state.active_activities[index]
				var current_id := str(activity.get("id", activity.get("activity_id", activity.get("course_id", ""))))
				if current_id == activity_id:
					activity["progress"] = maxi(0, int(activity.get("progress", 0)) + amount)
					state.active_activities[index] = activity
					return "%s progress +%d." % [activity.get("name", "Course"), amount]
		"education":
			var qualification := str(effect.get("value", effect.get("field", "")))
			if not qualification.is_empty() and not state.education.has(qualification):
				state.education.append(qualification)
				return "Earned %s." % qualification
	return ""


func _apply_money_effect(economy: Variant, state: Variant, amount: int, reason: String, category: String) -> String:
	if amount < 0 and int(state.cash) < -amount:
		var cash_paid := maxi(0, int(state.cash))
		if cash_paid > 0:
			_record_money(economy, state, -cash_paid, reason, category)
		var unpaid := -amount - cash_paid
		state.debt += unpaid
		return "$%d paid; $%d added to debt for %s." % [cash_paid, unpaid, reason]
	_record_money(economy, state, amount, reason, category)
	return "%s$%d: %s." % ["+" if amount >= 0 else "-", absi(amount), reason]


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


func _spend_time(state: Variant, hours: int, reason: String) -> bool:
	if hours <= 0:
		return true
	if state.has_method("spend_time"):
		return bool(state.spend_time(hours, reason))
	if int(state.weekly_time) < hours:
		return false
	state.weekly_time -= hours
	return true


func _has_mining_equipment(state: Variant) -> bool:
	var mining_value: Variant = state.crypto.get("mining", {})
	if not (mining_value is Dictionary):
		return false
	var mining: Dictionary = mining_value
	var equipment: Variant = mining.get("equipment", mining.get("rigs", []))
	if equipment is Array:
		return not (equipment as Array).is_empty()
	if equipment is Dictionary:
		return not (equipment as Dictionary).is_empty()
	if equipment is int or equipment is float:
		return int(equipment) > 0
	return int(mining.get("equipment_count", mining.get("rig_count", 0))) > 0 or bool(mining.get("active", false))


func _criminal_record_count(state: Variant) -> int:
	var record: Variant = state.crime.get("record", 0)
	if record is Array:
		return (record as Array).size()
	if record is Dictionary:
		return (record as Dictionary).size()
	return int(record)


func _relationship(state: Variant, person_id: String) -> Dictionary:
	var index := _relationship_index(state, person_id)
	if index < 0:
		return {}
	return state.relationships[index]


func _relationship_index(state: Variant, person_id: String) -> int:
	for index in range(state.relationships.size()):
		var relationship: Dictionary = state.relationships[index]
		if str(relationship.get("person_id", relationship.get("id", ""))) == person_id:
			return index
	return -1


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
