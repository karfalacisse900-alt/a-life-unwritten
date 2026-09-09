extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run_flow")

func _run_flow() -> void:
	var scene: PackedScene = load("res://main.tscn")
	var game := scene.instantiate()
	game.set("persistence_enabled", false)
	root.add_child(game)
	await process_frame
	_check(str(game.get("screen_mode")) == "welcome", "project opens at the welcome screen")

	game.call("_action", "new_game", null)
	_check(str(game.get("screen_mode")) == "create", "New Life opens character creation")
	game.set("character_form", {"name":"Flow Tester", "pronouns":"she/her", "appearance":3, "background":"fresh_start", "traits":["bold"]})
	game.call("_action", "finish_character", null)
	_check(str(game.get("screen_mode")) == "housing", "valid character continues to housing")
	game.call("_action", "choose_housing", "family_home")
	var state: LifeGameState = game.get("state")
	_check(bool(state.created) and state.housing_id == "family_home", "housing selection completes the playable setup")
	game.call("_action", "close_message", null)

	for page_id in ["life", "city", "occupation", "assets", "people"]:
		game.call("_action", "nav_page", page_id)
		_check(str(game.get("current_page")) == page_id, "%s navigation page opens" % page_id)

	state.health = 95
	state.reputation = 90
	state.skills["practical"] = 80
	state.skills["fitness"] = 80
	game.call("_action", "apply_job", "warehouse_worker")
	_check(str(state.employment.get("job_id", "")) == "warehouse_worker", "controller job application reaches EmploymentSystem")
	game.call("_action", "close_message", null)

	var before_week := int(state.calendar.get("week_index", 0))
	game.call("_action", "next_week", null)
	_check(int(state.calendar.get("week_index", 0)) == before_week + 1, "controller advances one week")
	_check(str(game.get("overlay_mode")) == "summary", "post-week explanation opens")
	game.call("_action", "next_week", null)
	_check(int(state.calendar.get("week_index", 0)) == before_week + 1, "repeated Next Week input is blocked while the summary is open")
	_check(_category_count(state, "employment_income") == 1, "controller posts the weekly wage once")

	game.free()
	if failures.is_empty():
		print("CONTROLLER_FLOW_PASS: welcome, creation, housing, LIFE/CITY/OCCUPATION/ASSETS/PEOPLE, job, week summary, duplicate-input guard")
		quit(0)
	else:
		for failure in failures: push_error("FAIL: " + failure)
		quit(1)

func _check(condition: bool, message: String) -> void:
	if not condition: failures.append(message)

func _category_count(state: LifeGameState, category: String) -> int:
	var count := 0
	for entry in state.ledger:
		if str(entry.get("category", "")) == category: count += 1
	return count
