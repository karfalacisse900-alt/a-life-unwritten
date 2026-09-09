extends SceneTree

const LifeStateScript = preload("res://scripts/core/LifeGameState.gd")
const EconomyScript = preload("res://scripts/systems/EconomySystem.gd")
const EventScript = preload("res://scripts/systems/EventSystem.gd")
const RelationshipScript = preload("res://scripts/systems/RelationshipSystem.gd")

var failures := 0


func _init() -> void:
	call_deferred("_run")


func _run() -> void:
	var events = EventScript.new()
	var relationships = RelationshipScript.new()
	var economy = EconomyScript.new()
	_check(events.events.size() >= 25, "catalog contains at least 25 events")
	_check(events.validation_errors.is_empty(), "catalog passes EventSystem validation")
	_check(_unique_event_ids(events.events), "event ids are unique")
	_check(_has_all_tones(events.events), "catalog includes positive, negative, ordinary, and difficult events")

	var state = LifeStateScript.new(12345)
	relationships.seed_people(state)
	_check(state.relationships.size() >= 5, "persistent people are seeded")
	_check(_has_person(state, "person_jordan_hale"), "stable family relationship id exists")
	_check(_has_person(state, "person_maya_chen"), "stable coworker relationship id exists")

	var promotion: Dictionary = events.get_event("earned_promotion_review")
	_check(not events.is_eligible(state, promotion), "promotion is ineligible while unemployed")
	state.employment = {"job_id": "office_assistant", "title": "Office Assistant", "weekly_pay": 510, "performance": 82, "weeks": 12, "active": true}
	_check(events.is_eligible(state, promotion), "promotion is eligible for a qualifying worker")

	var mining_repair: Dictionary = events.get_event("mining_fan_rattle")
	_check(not events.is_eligible(state, mining_repair), "mining repair is ineligible without equipment")
	state.crypto["mining"]["rigs"] = 1
	_check(events.is_eligible(state, mining_repair), "mining repair recognizes owned equipment")

	var relationship_state = LifeStateScript.new(24680)
	relationships.seed_people(relationship_state)
	var starting_cash: int = relationship_state.cash
	var starting_time: int = relationship_state.weekly_time
	var relationship_message: String = relationships.act(relationship_state, "person_nia_brooks", "spend_time", economy)
	_check(not relationship_message.is_empty(), "relationship action returns readable feedback")
	_check(relationship_state.cash == starting_cash - 18, "relationship action records its known cost")
	_check(relationship_state.weekly_time == starting_time - 3, "relationship action consumes weekly time once")
	var time_after_action: int = relationship_state.weekly_time
	relationships.act(relationship_state, "person_nia_brooks", "spend_time", economy)
	_check(relationship_state.weekly_time == time_after_action, "relationship cooldown blocks repeated time use")

	var delayed_state = LifeStateScript.new(777)
	delayed_state.health = 70
	var cash_before_clinic: int = delayed_state.cash
	var clinic_result: Dictionary = events.resolve(delayed_state, "community_clinic_screening", "book_screening", economy)
	_check(bool(clinic_result.get("ok", false)), "event choice resolves")
	_check(delayed_state.cash == cash_before_clinic - 30, "known event cost is charged exactly once")
	_check(delayed_state.delayed_effects.size() == 1, "delayed event effect is scheduled")
	delayed_state.calendar["week_index"] = 2
	var delayed_summary := events.process_delayed(delayed_state, economy)
	_check(delayed_summary.size() == 1, "due delayed effect triggers once")
	_check(delayed_state.health == 76, "delayed stat effect applies")
	_check(events.process_delayed(delayed_state, economy).is_empty(), "processed delayed effect cannot repeat")

	var legal_state = LifeStateScript.new(888)
	legal_state.crime["suspicion"] = 70
	var court_result: Dictionary = events.resolve(legal_state, "court_summons_arrives", "miss_hearing", economy)
	_check(bool(court_result.get("ok", false)), "court event resolves")
	_check((legal_state.crime["record"] as Array).size() == 1, "conviction appends a persistent record entry")
	legal_state.calendar["week_index"] = 1
	events.process_delayed(legal_state, economy)
	_check(bool(legal_state.crime.get("in_jail", false)), "delayed jail sentence starts")
	_check(int(legal_state.crime.get("jail_weeks", 0)) == 6, "jail sentence length is preserved")

	if failures == 0:
		print("EVENTS TEST PASS — %d events, %d persistent people" % [events.events.size(), relationships.people.size()])
	else:
		push_error("EVENTS TEST FAIL — %d check(s) failed" % failures)
	quit(failures)


func _check(condition: bool, label: String) -> void:
	if condition:
		print("PASS: %s" % label)
		return
	failures += 1
	push_error("FAIL: %s" % label)


func _unique_event_ids(all_events: Array[Dictionary]) -> bool:
	var seen: Dictionary = {}
	for event: Dictionary in all_events:
		var event_id := str(event.get("id", ""))
		if event_id.is_empty() or seen.has(event_id):
			return false
		seen[event_id] = true
	return true


func _has_all_tones(all_events: Array[Dictionary]) -> bool:
	var tones: Dictionary = {}
	for event: Dictionary in all_events:
		tones[str(event.get("tone", ""))] = true
	for required in ["positive", "negative", "ordinary", "difficult"]:
		if not tones.has(required):
			return false
	return true


func _has_person(state, person_id: String) -> bool:
	for relationship: Dictionary in state.relationships:
		if str(relationship.get("person_id", "")) == person_id:
			return true
	return false
