extends SceneTree

const StateClass = preload("res://scripts/core/LifeGameState.gd")
const CalendarClass = preload("res://scripts/systems/CalendarSystem.gd")
const EconomyClass = preload("res://scripts/systems/EconomySystem.gd")
const EmploymentClass = preload("res://scripts/systems/EmploymentSystem.gd")
const HousingClass = preload("res://scripts/systems/HousingSystem.gd")
const BusinessClass = preload("res://scripts/systems/BusinessSystem.gd")

var failures: Array[String] = []


func _init() -> void:
	_test_content_and_housing()
	_test_job_pay_idempotency()
	_test_course_completion()
	_test_business_week()
	_test_jail_suspends_normal_work()
	if failures.is_empty():
		print("WORK_MILESTONE_TESTS_OK")
		quit(0)
		return
	for failure in failures:
		push_error(failure)
	quit(1)


func _test_content_and_housing() -> void:
	var state = StateClass.new(101)
	var economy = EconomyClass.new()
	var housing = HousingClass.new()
	_check(housing.get_options().size() == 3, "Expected exactly three milestone housing choices.")
	var result := housing.move_to(state, "family_home", economy)
	_check(state.housing_id == "family_home", "Family home move should succeed: %s" % result)
	_check(int(housing.current(state).get("monthly_utilities", -1)) == 80, "Family-home monthly utilities should load from content.")


func _test_job_pay_idempotency() -> void:
	var state = StateClass.new(202)
	var employment = EmploymentClass.new()
	var economy = EconomyClass.new()
	var calendar = CalendarClass.new()
	_check(employment.get_jobs().size() >= 5, "Expected at least five job listings.")
	for skill_id in state.skills.keys():
		state.skills[skill_id] = 100
	state.health = 100
	state.reputation = 100
	state.stress = 0
	var apply_result := employment.apply(state, "office_assistant")
	_check(str(state.employment.get("job_id", "")) == "office_assistant", "High-scoring office application should succeed: %s" % apply_result)
	_check(not apply_result.contains("previous Unemployed"), "A first job must not be described as replacing unemployment.")
	var pay := int(state.employment.get("weekly_pay", 0))
	var before: int = int(state.cash)
	calendar.advance_one_week(state)
	economy.process_week(state, {})
	economy.process_week(state, {})
	_check(state.cash == before + pay, "Weekly employment income must be paid exactly once.")


func _test_course_completion() -> void:
	var state = StateClass.new(303)
	var employment = EmploymentClass.new()
	var economy = EconomyClass.new()
	var calendar = CalendarClass.new()
	state.cash = 1000
	var result := employment.start_course(state, "workplace_readiness_certificate", economy)
	_check(state.active_activities.size() == 1, "Course enrollment should create an active activity: %s" % result)
	for _week in range(3):
		calendar.advance_one_week(state)
		employment.process_week(state)
	_check(state.education.has("workplace_readiness_certificate"), "Three attended weeks should award the workplace certificate.")
	_check(state.active_activities.is_empty(), "Completed course should leave active activities.")


func _test_business_week() -> void:
	var state = StateClass.new(404)
	var business = BusinessClass.new()
	var economy = EconomyClass.new()
	var calendar = CalendarClass.new()
	state.cash = 10000
	state.reputation = 60
	var start_result := business.start(state, economy)
	_check(bool(state.business.get("active", false)), "Business should start with funds and time: %s" % start_result)
	calendar.advance_one_week(state)
	var before_entries: int = state.ledger.size()
	var first_summary := economy.process_week(state, {})
	var after_first: int = state.ledger.size()
	economy.process_week(state, {})
	_check(not first_summary.is_empty(), "Active business should produce a weekly summary.")
	_check(after_first > before_entries, "Business week should create reasoned ledger entries.")
	_check(state.ledger.size() == after_first, "Repeated weekly processing must not duplicate business transactions.")
	_check(int(state.business.get("last_processed_week", -1)) == int(state.calendar.get("week_index", -2)), "Business should record its processed week.")


func _test_jail_suspends_normal_work() -> void:
	var state = StateClass.new(505)
	var employment = EmploymentClass.new()
	var business = BusinessClass.new()
	var economy = EconomyClass.new()
	var calendar = CalendarClass.new()
	state.cash = 10000
	state.reputation = 100
	state.health = 100
	state.stress = 0
	for skill_id in state.skills.keys():
		state.skills[skill_id] = 100
	employment.apply(state, "office_assistant")
	business.start(state, economy)
	employment.start_course(state, "workplace_readiness_certificate", economy)
	calendar.advance_one_week(state)
	state.crime["in_jail"] = true
	state.crime["jail_weeks"] = 2
	var free_hours: int = state.weekly_time
	var work_summary := employment.process_week(state)
	var business_summary := economy.process_week(state, {})
	_check(state.weekly_time == free_hours, "Jail must not spend ordinary job or owner-operation hours.")
	_check(bool(state.employment.get("suspended", false)), "Employment should be marked suspended while jailed.")
	_check(int(state.active_activities[0].get("weeks_remaining", -1)) == 3, "Jail must pause course progress instead of treating it as normal attendance.")
	_check(int(state.business.get("last_customers", -1)) == 0, "An unstaffed business must not make ghost sales while its owner is jailed.")
	_check(not work_summary.is_empty() and not business_summary.is_empty(), "Jail-related work and business consequences should be explained.")


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
