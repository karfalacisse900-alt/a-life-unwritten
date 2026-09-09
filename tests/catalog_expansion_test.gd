extends SceneTree

const State = preload("res://scripts/core/LifeGameState.gd")
const Calendar = preload("res://scripts/systems/CalendarSystem.gd")
const Economy = preload("res://scripts/systems/EconomySystem.gd")
const Assets = preload("res://scripts/systems/AssetSystem.gd")
const Vehicles = preload("res://scripts/systems/VehicleFinanceSystem.gd")
const Page = preload("res://scripts/ui/pages/AssetsPage.gd")

var failures: Array[String] = []


func _initialize() -> void:
	var assets := Assets.new()
	var vehicles := Vehicles.new()
	_check(assets.load_errors.is_empty(), "Expanded asset content validates.")
	_check(vehicles.get_catalog().size() >= 16, "Sixteen vehicle options must be available.")
	for id in ["toyota_corolla_2017", "honda_civic_2020", "porsche_911_2025", "ferrari_roma_2024", "bugatti_veyron", "bugatti_chiron", "bugatti_tourbillon"]:
		var model := vehicles.get_vehicle(id)
		_check(not model.is_empty() and int(model.get("purchase_price",0))>0, "Expected real-model vehicle: "+id)
		_check(int(model.get("insurance_monthly",0))>0 and int(model.get("maintenance_monthly",0))>0,"Ownership costs apply: "+id)
	var state := State.new(7815)
	var observer := State.new(7815)
	state.cash = 200000
	observer.cash = 200000
	state.skills["driving"] = 100
	var economy := Economy.new()
	var starting_cash: int = state.cash
	assets.buy(state,"mona_lisa_edition",1,economy)
	_check(bool(assets.last_result.get("ok",false)),"A collectible edition can be bought.")
	var asset := assets.get_owned(state)[0]
	_check(str(asset.get("edition","")).length()>0 and str(asset.get("valuation_note","")).contains("not the museum original"),"Edition and valuation scope survive ownership metadata.")
	for item in assets.get_catalog("collectible"):
		if item.has("thumbnail"):
			_check(ResourceLoader.exists(str(item["thumbnail"])),"Thumbnail must ship: "+str(item["id"]))
	var calendar := Calendar.new()
	for week in 12:
		calendar.advance_one_week(state)
		calendar.advance_one_week(observer)
		assets.process_week(state,economy)
		assets.process_week(observer,economy)
	_check(assets.get_portfolio(state)["prices"] == assets.get_portfolio(observer)["prices"],"Buying art must not alter independent appraisal prices.")
	var values: Array = assets.get_portfolio(state)["price_history"]["mona_lisa_edition"]
	var changed := false
	for value in values:
		if int(value)!=int(values[0]): changed=true
	_check(changed and values.size()==13,"Collectible appraisals change through weekly simulation.")
	var cash_before_sale: int = state.cash
	state.weekly_time = 40
	assets.sell(state,"mona_lisa_edition",1,economy)
	_check(bool(assets.last_result.get("ok",false)) and state.cash>cash_before_sale,"Appraised art can be sold with a recorded payment.")
	var ledger_total := 0
	for entry in state.ledger: ledger_total += int(entry.get("amount",0))
	_check(state.cash==starting_cash+ledger_total,"Every art purchase, sale and upkeep dollar reconciles.")
	var page := Page.new()
	var ctx := {"asset_tab":"market","market_section":"things","asset_category":"vehicle","vehicle_catalog":vehicles.get_catalog(),"owned_vehicle":{}}
	var limit := page.get_scroll_limit(state,ctx)
	_check(limit>=16*254-600,"The last luxury car must be reachable by scrolling.")
	ctx["asset_category"]="collectible"
	ctx["physical_catalog"]=assets.get_catalog("collectible")
	_check(page.get_scroll_limit(state,ctx)>1000,"The expanded art catalog must be fully reachable.")
	if failures.is_empty():
		print("CATALOG_EXPANSION_TESTS_OK: real-model vehicles, attributed art, changing independent appraisals, ledger and catalog reachability")
		quit(0)
	else:
		for failure in failures: push_error(failure)
		quit(1)


func _check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)
