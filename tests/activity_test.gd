extends SceneTree

const StateClass = preload("res://scripts/core/LifeGameState.gd")
const CalendarClass = preload("res://scripts/systems/CalendarSystem.gd")
const EconomyClass = preload("res://scripts/systems/EconomySystem.gd")
const ActivityClass = preload("res://scripts/systems/ActivitySystem.gd")

var failures: Array[String] = []


func _initialize() -> void:
	_test_content_and_requirements()
	_test_hobbies_are_time_limited()
	_test_freelance_review_and_idempotence()
	_test_global_gig_limit()
	_test_crafting_and_marketplace()
	_test_save_round_trip()
	if failures.is_empty():
		print("ACTIVITY_TEST_PASS: hobbies, freelance review, crafting, inventory, uncertain marketplace demand, ledger, limits, save state, and weekly idempotence")
		quit(0)
		return
	for failure in failures:
		push_error("ACTIVITY_TEST_FAIL: %s" % failure)
	quit(1)


func _test_content_and_requirements() -> void:
	var activities = ActivityClass.new()
	var state = StateClass.new(1101)
	_check(activities.get_hobbies().size() >= 5, "Expected at least five original hobbies.")
	_check(activities.get_gigs().size() >= 6, "Expected at least six freelance briefs.")
	_check(activities.get_marketplace_items().size() >= 5, "Expected at least five craftable marketplace products.")
	_check(str(activities.get_activity("poster_layout").get("kind", "")) == "gig", "Stable activity IDs must resolve to their kind.")
	var bedroom := activities.eligibility_details(state, "bedroom_music")
	_check(not bool(bedroom.get("eligible", true)) and str(bedroom.get("reason", "")).contains("housing"), "Workspace hobbies must explain their housing requirement.")
	var advanced_gig := activities.eligibility_details(state, "event_photography")
	_check(not bool(advanced_gig.get("eligible", true)) and not (advanced_gig.get("reasons", []) as Array).is_empty(), "Skill-gated freelance work must be unavailable with reasons.")
	state.crime["in_jail"] = true
	var jail_block := activities.eligibility_details(state, "neighborhood_running")
	_check(not bool(jail_block.get("eligible", true)), "Normal hobbies must be blocked while jailed when content requires it.")


func _test_hobbies_are_time_limited() -> void:
	var activities = ActivityClass.new()
	var economy = EconomyClass.new()
	var state = StateClass.new(2202)
	state.cash = 100
	state.weekly_time = 20
	state.stress = 30
	var opening_cash: int = state.cash
	var first := activities.perform_hobby(state, "urban_sketching", economy)
	_check(first.contains("4 hours") and state.weekly_time == 16, "A hobby must consume its stated weekly hours.")
	_check(state.cash == opening_cash - 12 and _category_count(state, "hobby_expense") == 1, "Hobby supplies must use the reasoned economy ledger.")
	_check(int(state.skills.get("creative", 0)) == 2 and state.stress == 25, "Hobby effects must update skills and wellbeing.")
	var time_before_repeat: int = state.weekly_time
	var repeat := activities.perform_hobby(state, "urban_sketching", economy)
	_check(repeat.contains("Weekly limit") and state.weekly_time == time_before_repeat, "A once-weekly hobby must not spend time again after its limit.")

	var poor_state = StateClass.new(2203)
	poor_state.cash = 0
	poor_state.weekly_time = 20
	var poor_time: int = poor_state.weekly_time
	activities.perform_hobby(poor_state, "urban_sketching", economy)
	_check(poor_state.weekly_time == poor_time and poor_state.ledger.is_empty(), "Failed affordability checks must be atomic.")

	var calendar = CalendarClass.new()
	calendar.advance_one_week(state)
	var refreshed := activities.eligibility_details(state, "urban_sketching")
	_check(bool(refreshed.get("eligible", false)), "Weekly activity limits must reset after the calendar advances.")


func _test_freelance_review_and_idempotence() -> void:
	var activities = ActivityClass.new()
	var economy = EconomyClass.new()
	var calendar = CalendarClass.new()
	var state = StateClass.new(3303)
	state.weekly_time = 60
	state.housing_id = "family_home"
	state.reputation = 100
	state.stress = 0
	for skill_id in state.skills.keys():
		state.skills[skill_id] = 100
	state.skills["creative"] = 100
	var opening_cash: int = state.cash
	var submission := activities.accept_gig(state, "poster_layout")
	_check(submission.contains("not guaranteed") and activities.get_active_gigs(state).size() == 1, "A gig must become a pending client review, not instant guaranteed income.")
	_check(state.cash == opening_cash and _category_count(state, "freelance_income") == 0, "Submitting work must not pay before client review.")
	var second_attempt := activities.accept_gig(state, "poster_layout")
	_check(second_attempt.contains("Weekly limit") and activities.get_active_gigs(state).size() == 1, "The same repeatable gig must respect its weekly limit.")

	calendar.advance_one_week(state)
	var summary := activities.process_week(state, economy)
	_check(not summary.is_empty() and activities.get_active_gigs(state).is_empty(), "The next week must resolve and remove a reviewed brief.")
	var ledger_after: int = state.ledger.size()
	var cash_after: int = state.cash
	activities.process_week(state, economy)
	_check(state.ledger.size() == ledger_after and state.cash == cash_after, "Same-week freelance processing must be idempotent.")
	_check(_category_count(state, "freelance_income") == 1 and state.cash > opening_cash, "The seeded qualified submission should produce one ledger-backed payment.")


func _test_global_gig_limit() -> void:
	var activities = ActivityClass.new()
	var state = StateClass.new(4404)
	state.weekly_time = 60
	state.housing_id = "family_home"
	state.reputation = 100
	state.health = 100
	state.stress = 0
	for skill_id in state.skills.keys():
		state.skills[skill_id] = 100
	state.skills["creative"] = 100
	activities.accept_gig(state, "poster_layout")
	activities.accept_gig(state, "furniture_assembly")
	var third := activities.accept_gig(state, "local_tutoring")
	_check(activities.get_active_gigs(state).size() == 2 and third.contains("at most 2"), "The occupation system must cap total freelance submissions each week.")


func _test_crafting_and_marketplace() -> void:
	var activities = ActivityClass.new()
	var economy = EconomyClass.new()
	var calendar = CalendarClass.new()
	var state = StateClass.new(5505)
	state.cash = 500
	state.weekly_time = 60
	state.housing_id = "family_home"
	state.skills["creative"] = 100
	state.skills["practical"] = 100
	state.skills["business"] = 100
	state.reputation = 100
	state.active_activities.append({"type": "course", "id": "keep_this_course", "weeks_remaining": 3})
	var opening_cash: int = state.cash
	var craft_result := activities.craft_item(state, "hand_poured_candle", economy)
	_check(craft_result.contains("not sold yet") and activities.inventory_quantity(state, "hand_poured_candle") == 2, "Crafting must create finished inventory without pretending it sold.")
	_check(state.cash == opening_cash - 36 and _category_count(state, "craft_materials") == 1, "Craft materials must create one exact ledger expense.")
	var list_result := activities.list_item(state, "hand_poured_candle", economy, 1)
	_check(list_result.contains("Demand is uncertain") and activities.inventory_quantity(state, "hand_poured_candle") == 1, "Listing must reserve only the chosen inventory quantity.")
	_check(_category_count(state, "marketplace_fee") == 1 and activities.get_active_listings(state).size() == 1, "Listing fees and active listings must persist separately.")

	calendar.advance_one_week(state)
	var first_summary := activities.process_week(state, economy)
	_check(not first_summary.is_empty(), "Weekly processing must explain the marketplace result.")
	var course_preserved := false
	for activity in state.active_activities:
		if str(activity.get("type", "")) == "course" and str(activity.get("id", "")) == "keep_this_course":
			course_preserved = true
	_check(course_preserved, "Activity processing must preserve courses and other systems' active entries.")
	var first_week_entries: int = state.ledger.size()
	var first_week_cash: int = state.cash
	activities.process_week(state, economy)
	_check(state.ledger.size() == first_week_entries and state.cash == first_week_cash, "Marketplace resolution must not duplicate in the same week.")

	for _remaining_week in range(4):
		if activities.get_active_listings(state).is_empty():
			break
		calendar.advance_one_week(state)
		activities.process_week(state, economy)
	_check(activities.get_active_listings(state).is_empty(), "A listing must sell or expire within its declared duration.")
	_check(_category_count(state, "marketplace_sale") <= 1, "One listing can produce at most one sale transaction.")
	var final_quantity := activities.inventory_quantity(state, "hand_poured_candle")
	_check(final_quantity == 1 or final_quantity == 2, "Sold inventory stays removed; expired inventory returns exactly once.")
	_check(opening_cash + _ledger_sum(state) == state.cash, "All marketplace cash movement must reconcile to the integer ledger.")


func _test_save_round_trip() -> void:
	var activities = ActivityClass.new()
	var economy = EconomyClass.new()
	var state = StateClass.new(6606)
	state.cash = 500
	state.weekly_time = 60
	state.housing_id = "rented_room"
	state.skills["creative"] = 100
	state.skills["practical"] = 100
	activities.craft_item(state, "custom_tote", economy)
	activities.list_item(state, "custom_tote", economy, 1)
	var restored = StateClass.new()
	_check(restored.from_dict(state.to_dict()), "Occupation state must survive standard save serialization.")
	_check(activities.inventory_quantity(restored, "custom_tote") == 1, "Unlisted workshop inventory must survive saving.")
	_check(activities.get_active_listings(restored).size() == 1, "Pending marketplace listings must survive saving.")
	_check(restored.flags.get("occupation_stats", {}) == state.flags.get("occupation_stats", {}), "Occupation totals must survive saving.")


func _category_count(state, category: String) -> int:
	var count := 0
	for entry in state.ledger:
		if str(entry.get("category", "")) == category:
			count += 1
	return count


func _ledger_sum(state) -> int:
	var total := 0
	for entry in state.ledger:
		total += int(entry.get("amount", 0))
	return total


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
