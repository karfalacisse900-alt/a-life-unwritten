extends SceneTree

const TEST_SAVE := "user://a_life_unwritten_core_contract_test.json"

var failures: Array[String] = []


func _initialize() -> void:
	_test_state_and_rng()
	_test_calendar_and_economy()
	_test_save_backup_recovery()
	_cleanup_save_files()
	if failures.is_empty():
		print("CORE_TEST_PASS: state, RNG, calendar, ledger, idempotence, monthly schedule, and save recovery")
		quit(0)
	else:
		for failure in failures:
			push_error("CORE_TEST_FAIL: %s" % failure)
		quit(1)


func _test_state_and_rng() -> void:
	var state := LifeGameState.new(123456)
	_check(state.cash is int, "cash must be integer currency")
	_check(state.calendar.get("week_index") == 0, "new state must begin at week index zero")
	state.relationships = [{"id": "person_test", "bond": 63, "memories": ["Met at the park"]}]
	state.delayed_effects = [{"id": "later", "due_week": 4, "effects": {"stress": 2}}]
	state.randf_seeded()
	var snapshot := state.to_dict()
	var expected_next := state.randf_seeded()
	var restored := LifeGameState.new()
	_check(restored.from_dict(snapshot), "serialized state should reload")
	_check(is_equal_approx(restored.randf_seeded(), expected_next), "RNG sequence must continue exactly after reload")
	_check(restored.relationships == snapshot["relationships"], "relationships must survive full serialization")
	_check(restored.delayed_effects == snapshot["delayed_effects"], "delayed effects must survive full serialization")


func _test_calendar_and_economy() -> void:
	var housing_content := _load_json("res://data/housing.json")
	var state := LifeGameState.new(77)
	state.cash = 1000
	state.housing_id = "family_home"
	state.calendar = {"year": 2026, "month": 1, "day": 26, "week": 4, "week_index": 0}
	state.employment = {"job_id": "retail_assistant", "title": "Retail Assistant", "weekly_pay": 500, "performance": 55, "weeks": 0}
	var calendar_system := CalendarSystem.new()
	var economy := EconomySystem.new()

	var boundary := calendar_system.advance_one_week(state)
	_check(state.calendar == {"year": 2026, "month": 2, "day": 2, "week": 5, "week_index": 1}, "one advance must add exactly seven days")
	_check(bool(boundary.get("new_month", false)), "Jan 26 to Feb 2 must report a monthly boundary")
	_check((boundary.get("month_boundaries", []) as Array).size() == 1, "exactly one first-of-month boundary expected")

	var cash_before := state.cash
	var first_summary := economy.process_week(state, housing_content)
	_check(not first_summary.is_empty(), "weekly economy should produce a readable summary")
	_check(state.cash == 1420, "one $500 wage and one $80 monthly utility bill should net $420")
	_check(state.ledger.size() == 2, "wage and utility bill should produce two ledger rows")
	var ledger_size := state.ledger.size()
	var cash_after := state.cash
	economy.process_week(state, housing_content)
	_check(state.cash == cash_after and state.ledger.size() == ledger_size, "same-week economy processing must be idempotent")
	var ledger_delta := 0
	for entry in state.ledger:
		ledger_delta += int(entry.get("amount", 0))
	_check(cash_before + ledger_delta == state.cash, "cash must reconcile exactly to integer ledger amounts")

	calendar_system.advance_one_week(state)
	economy.process_week(state, housing_content)
	_check(state.cash == 1920, "ordinary non-boundary week should pay once and not charge monthly bills")
	var utility_charges := 0
	for entry in state.ledger:
		if str(entry.get("category", "")) == "housing_utilities":
			utility_charges += 1
	_check(utility_charges == 1, "monthly utility bill must not be charged every week")


func _test_save_backup_recovery() -> void:
	_cleanup_save_files()
	var save_system := SaveSystem.new(TEST_SAVE)
	var state := LifeGameState.new(987)
	state.created = true
	state.player_name = "Backup Tester"
	state.cash = 3210
	state.relationships = [{"id": "maya_chen", "bond": 72}]
	state.randf_seeded()
	var expected_rng_state := LifeGameState.new()
	expected_rng_state.from_dict(state.to_dict())
	var expected_rng_value := expected_rng_state.randf_seeded()
	var first_result := save_system.save_game(state)
	_check(bool(save_system.last_result.get("ok", false)), "first save should succeed: %s" % first_result)
	state.cash = 4444
	state.event_history.append("Second snapshot")
	var second_result := save_system.autosave(state)
	_check(bool(save_system.last_result.get("ok", false)), "second save should succeed and create backup: %s" % second_result)
	_check(FileAccess.file_exists(save_system.backup_path), "second valid save must retain one backup")

	var damaged := FileAccess.open(save_system.save_path, FileAccess.WRITE)
	_check(damaged != null, "test must be able to damage its isolated primary save")
	if damaged != null:
		damaged.store_string("{ definitely-not-valid-json")
		damaged = null
	var loaded := LifeGameState.new(1)
	loaded.player_name = "Live state must not leak"
	var load_result := save_system.load_game(loaded)
	_check(bool(save_system.last_result.get("ok", false)), "backup should load after primary corruption: %s" % load_result)
	_check(str(save_system.last_result.get("source", "")) == "backup", "load result should identify backup recovery")
	_check(loaded.cash == 3210 and loaded.player_name == "Backup Tester", "backup must contain the previous complete snapshot")
	_check(is_equal_approx(loaded.randf_seeded(), expected_rng_value), "JSON save must preserve all 64 bits of RNG continuation state")
	_check(save_system.has_save(), "repaired save should validate")

	# With both files invalid, loading must preserve the live object unchanged.
	var primary := FileAccess.open(save_system.save_path, FileAccess.WRITE)
	if primary != null:
		primary.store_string("broken primary")
		primary = null
	var backup := FileAccess.open(save_system.backup_path, FileAccess.WRITE)
	if backup != null:
		backup.store_string("broken backup")
		backup = null
	loaded.cash = 777
	loaded.player_name = "Unchanged Live State"
	save_system.load_game(loaded)
	_check(not bool(save_system.last_result.get("ok", true)), "two damaged files must report failure")
	_check(loaded.cash == 777 and loaded.player_name == "Unchanged Live State", "failed load must not partially overwrite live state")


func _load_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		failures.append("Could not open test content %s" % path)
		return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if parsed is Dictionary:
		return parsed
	failures.append("Test content was invalid JSON: %s" % path)
	return {}


func _cleanup_save_files() -> void:
	var paths := [
		TEST_SAVE,
		TEST_SAVE.get_basename() + ".backup." + TEST_SAVE.get_extension(),
		TEST_SAVE.get_basename() + ".tmp." + TEST_SAVE.get_extension(),
		TEST_SAVE + ".staging",
		TEST_SAVE.get_basename() + ".backup." + TEST_SAVE.get_extension() + ".staging",
	]
	for path in paths:
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
