extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
	_run_acceptance_scenario()
	if failures.is_empty():
		print("MILESTONE_ACCEPTANCE_PASS: character → housing → occupation → income/bills → activities/assets → save-ready state")
		quit(0)
	else:
		for failure in failures: push_error("FAIL: " + failure)
		quit(1)

func _check(condition: bool, message: String) -> void:
	if not condition: failures.append(message)

func _run_acceptance_scenario() -> void:
	var state := LifeGameState.new(24680)
	var calendar := CalendarSystem.new()
	var economy := EconomySystem.new()
	var character := CharacterSystem.new()
	var employment := EmploymentSystem.new()
	var housing := HousingSystem.new()
	var business := BusinessSystem.new()
	var relationships := RelationshipSystem.new()
	var events := EventSystem.new()
	var activities := ActivitySystem.new()
	var assets := AssetSystem.new()

	var created := character.create_character(state, {
		"name":"Acceptance Player", "pronouns":"they/them", "appearance":7,
		"background":"fresh_start", "traits":["resilient"]
	}, economy)
	_check(not created.is_empty() and state.player_name == "Acceptance Player", "new character is created from a background")
	_check(state.age == 18 and state.cash == 1450 and state.debt == 350, "starting age and modest finances match the selected background")
	_check(character.get_backgrounds().size() == 4, "background tradeoffs are data-driven")

	var home_result := housing.move_to(state, "rented_room", economy)
	_check(state.housing_id == "rented_room" and not home_result.is_empty(), "rented-room move charges move-in costs and succeeds")
	_check(state.cash == 850, "rented-room deposit and moving cost are charged exactly")
	state.created = true
	relationships.seed_people(state)
	_check(state.relationships.size() == 7, "persistent starting relationships are seeded")

	_check(employment.get_jobs().size() == 5, "five job listings exist")
	_check(housing.get_options().size() == 3, "three housing choices exist")
	_check(employment.get_courses().size() >= 1, "the workplace training course exists")
	_check(events.load_content().size() >= 25, "at least 25 varied events load")
	_check(activities.get_hobbies().size() == 5, "five playable hobbies load")
	_check(activities.get_gigs().size() == 6, "six freelance gigs load")
	_check(activities.get_marketplace_items().size() == 5, "five craft-and-sell marketplace items load")
	_check(assets.get_catalog().size() >= 14, "the playable asset catalog includes the original milestone plus expansions")
	for base_asset_id in ["northstar_index_fund", "renewal_works_fund", "harbor_civic_bond", "metro_hatchback", "courier_van", "solace_electric_sedan", "riverside_micro_studio", "corner_shop_unit", "maple_duplex", "night_bus_print", "river_glass_sculpture", "after_rain_canvas", "creator_laptop", "market_stall_kit"]:
		_check(not assets.get_asset(base_asset_id).is_empty(), "original asset ID remains compatible with saves: " + base_asset_id)
	_check(assets.get_categories().size() == 5, "investment, vehicle, property, collectible, and equipment categories load")
	var district_data := _read_json("res://data/districts.json")
	_check((district_data.get("districts", []) as Array).size() == 5, "all five city districts load")

	var delivery := employment.get_job("delivery_worker")
	_check(not employment.eligible(state, delivery), "job requirements block an underqualified application")
	state.health = 92
	state.reputation = 80
	state.skills["practical"] = 75
	state.skills["fitness"] = 65
	var application := employment.apply(state, "warehouse_worker")
	_check(str(state.employment.get("job_id", "")) == "warehouse_worker", "a strongly qualified application can lead to employment: " + application)

	var cash_before_week := state.cash
	var advanced := calendar.advance_one_week(state)
	_check(bool(advanced.get("advanced", false)) and int(state.calendar.week_index) == 1, "Next Week advances exactly once")
	var summaries: Array[String] = []
	summaries.append_array(employment.process_week(state))
	summaries.append_array(housing.process_week(state))
	summaries.append_array(economy.process_week(state, {"housing":housing.get_options()}))
	summaries.append_array(relationships.process_week(state))
	var pay_count := _ledger_category_count(state, "employment_income")
	_check(pay_count == 1 and state.cash > cash_before_week, "weekly pay is posted once with a ledger reason")
	var cash_after_first_process := state.cash
	economy.process_week(state, {"housing":housing.get_options()})
	_check(state.cash == cash_after_first_process and _ledger_category_count(state, "employment_income") == 1, "reprocessing the same week cannot duplicate income")

	var time_before := state.weekly_time
	var impossible_spend := state.spend_time(time_before + 1, "Impossible repeat")
	_check(not impossible_spend and state.weekly_time == time_before, "the weekly time budget blocks actions that do not fit")

	var month_boundary_count := 0
	for _week in 4:
		var boundary := calendar.advance_one_week(state)
		if bool(boundary.get("new_month", false)): month_boundary_count += 1
		employment.process_week(state)
		housing.process_week(state)
		economy.process_week(state, {"housing":housing.get_options()})
	_check(month_boundary_count == 1, "the explicit calendar crosses one monthly boundary in the starting four-week span")
	_check(_ledger_category_count(state, "housing_rent") == 1 and _ledger_category_count(state, "housing_utilities") == 1, "rent and utilities charge on that monthly boundary only")

	state.cash = 5000
	state.weekly_time = 60
	var business_result := business.start(state, economy)
	_check(bool(state.business.get("active", false)) and not business_result.is_empty(), "the first small business can be started after progression")
	_check(business.set_decision(state, "price", 18).contains("$18"), "business pricing is a working decision")

	var before_social_time := state.weekly_time
	var social_result := relationships.act(state, "person_jordan_hale", "spend_time", economy)
	_check(not social_result.is_empty() and state.weekly_time < before_social_time, "a relationship action consumes time and persists")

	state.cash = 5000
	state.weekly_time = 60
	var activity_time_before := state.weekly_time
	var hobby_result := activities.perform_hobby(state, "neighborhood_running", economy)
	_check(hobby_result.contains("Neighborhood Run") and state.weekly_time < activity_time_before, "an occupation hobby is playable and consumes weekly time")
	var asset_result := assets.buy(state, "northstar_index_fund", 1, economy)
	_check(asset_result.begins_with("Bought") and assets.get_owned(state).size() == 1, "an asset can be purchased and appears in the owned portfolio")

	var serialized := state.to_dict()
	var restored := LifeGameState.new()
	_check(restored.from_dict(serialized), "full simulation state can be restored")
	_check(restored.housing_id == state.housing_id and restored.relationships.size() == state.relationships.size() and bool(restored.business.get("active", false)), "housing, relationships, and business survive serialization")
	_check(restored.flags == state.flags, "activity and asset flags survive the save-state round trip")
	var restored_asset_state: Dictionary = restored.flags.get("assets", {})
	var restored_holdings: Dictionary = restored_asset_state.get("holdings", {})
	var restored_occupation_stats: Dictionary = restored.flags.get("occupation_stats", {})
	_check(restored_holdings.has("northstar_index_fund"), "the purchased investment survives serialization")
	_check(int(restored_occupation_stats.get("hobby_sessions", 0)) == 1, "occupation activity history survives serialization")

	for page in ["CharacterCreatePage", "HousingSetupPage", "LifePage", "CityPage", "OccupationPage", "AssetsPage", "PeoplePage", "OverlayPage"]:
		_check(FileAccess.file_exists("res://scripts/ui/pages/%s.gd" % page), "%s renderer exists" % page)

func _ledger_category_count(state: LifeGameState, category: String) -> int:
	var count := 0
	for entry in state.ledger:
		if str(entry.get("category", "")) == category: count += 1
	return count

func _read_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return {}
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	return parsed if parsed is Dictionary else {}
