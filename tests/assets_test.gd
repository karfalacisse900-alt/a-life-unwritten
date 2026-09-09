extends SceneTree

const StateClass = preload("res://scripts/core/LifeGameState.gd")
const CalendarClass = preload("res://scripts/systems/CalendarSystem.gd")
const EconomyClass = preload("res://scripts/systems/EconomySystem.gd")
const AssetsClass = preload("res://scripts/systems/AssetSystem.gd")

var failures: Array[String] = []


func _initialize() -> void:
	_test_catalog_and_requirements()
	_test_buy_sell_and_ledger()
	_test_player_independent_values()
	_test_monthly_upkeep_and_idempotence()
	_test_property_sync_and_save_roundtrip()
	if failures.is_empty():
		print("ASSET_SYSTEM_TESTS_OK: catalog, trading, possessions, valuation, upkeep, benefits, ledger, and saving")
		quit(0)
		return
	for failure in failures:
		push_error("ASSET_TEST_FAIL: %s" % failure)
	quit(1)


func _test_catalog_and_requirements() -> void:
	var state = StateClass.new(1101)
	var assets = AssetsClass.new()
	_check(assets.load_errors.is_empty(), "Asset JSON should load and validate: %s" % " ".join(assets.load_errors))
	_check(assets.get_categories().size() == 5, "Expected five useful asset categories.")
	_check(assets.get_catalog("investment").size() >= 3, "Expected at least three fictional investments.")
	_check(assets.get_catalog("vehicle").size() >= 3, "Expected multiple vehicles.")
	_check(assets.get_catalog("property").size() >= 3, "Expected multiple properties.")
	_check(assets.get_catalog("collectible").size() >= 3, "Expected several art and collectible items.")
	state.cash = 20000
	var before_cash: int = state.cash
	var before_time: int = state.weekly_time
	var blocked := assets.buy(state, "courier_van", 1, EconomyClass.new())
	_check(not bool(assets.last_result.get("ok", true)), "Courier van should require driving skill: %s" % blocked)
	_check(state.cash == before_cash and state.weekly_time == before_time and state.ledger.is_empty(), "A blocked purchase must not consume cash, time, or create ledger rows.")


func _test_buy_sell_and_ledger() -> void:
	var state = StateClass.new(2202)
	var assets = AssetsClass.new()
	var economy = EconomyClass.new()
	state.cash = 2000
	var starting_cash: int = state.cash
	var buy_text := assets.buy(state, "northstar_index_fund", 5, economy)
	_check(bool(assets.last_result.get("ok", false)), "Five fund units should be purchasable: %s" % buy_text)
	var owned := assets.get_owned(state, "investment")
	_check(owned.size() == 1 and int(owned[0].get("quantity", 0)) == 5, "Fund purchase should create a five-unit holding.")
	_check(state.ledger.size() == 1 and str(state.ledger[0].get("category", "")) == "asset_purchase", "Purchase must be represented by one reasoned EconomySystem ledger row.")
	_check(state.weekly_time == 39, "One market order should consume one hour, regardless of unit count.")
	var purchase_outflow := -int(state.ledger[0].get("amount", 0))
	_check(purchase_outflow == 603, "$600 of fund units plus a 0.5% fee should cost $603 exactly.")

	var sell_text := assets.sell(state, "northstar_index_fund", 2, economy)
	_check(bool(assets.last_result.get("ok", false)), "A partial fund sale should work: %s" % sell_text)
	owned = assets.get_owned(state, "investment")
	_check(owned.size() == 1 and int(owned[0].get("quantity", 0)) == 3, "Partial sale should leave three fund units.")
	_check(state.ledger.size() == 2 and str(state.ledger[1].get("category", "")) == "asset_sale", "Sale proceeds must be recorded by EconomySystem.")
	var ledger_delta := 0
	for entry in state.ledger:
		ledger_delta += int(entry.get("amount", 0))
	_check(state.cash == starting_cash + ledger_delta, "Cash must reconcile exactly to asset ledger entries.")
	_check(int(assets.get_portfolio(state).get("realized_gain", 0)) == int(assets.last_result.get("realized_gain", 999)), "Portfolio should retain realized gain or loss from a partial sale.")


func _test_player_independent_values() -> void:
	var investor = StateClass.new(3303)
	var observer = StateClass.new(3303)
	var investor_assets = AssetsClass.new()
	var observer_assets = AssetsClass.new()
	var calendar_a = CalendarClass.new()
	var calendar_b = CalendarClass.new()
	investor.cash = 10000
	observer.cash = 10000
	investor_assets.buy(investor, "renewal_works_fund", 20, EconomyClass.new())
	calendar_a.advance_one_week(investor)
	calendar_b.advance_one_week(observer)
	investor_assets.process_week(investor, EconomyClass.new())
	observer_assets.process_week(observer, EconomyClass.new())
	var investor_prices: Dictionary = investor_assets.get_portfolio(investor).get("prices", {})
	var observer_prices: Dictionary = observer_assets.get_portfolio(observer).get("prices", {})
	_check(investor_prices == observer_prices, "Weekly values must be identical for the same seed whether or not the player bought an asset.")
	var history: Array = investor_assets.get_portfolio(investor).get("price_history", {}).get("renewal_works_fund", [])
	_check(history.size() == 2, "Weekly valuation should append exactly one price-history point.")
	var history_size := history.size()
	investor_assets.process_week(investor, EconomyClass.new())
	history = investor_assets.get_portfolio(investor).get("price_history", {}).get("renewal_works_fund", [])
	_check(history.size() == history_size, "Repeated processing of one week must not move prices twice.")


func _test_monthly_upkeep_and_idempotence() -> void:
	var state = StateClass.new(4404)
	var assets = AssetsClass.new()
	var economy = EconomyClass.new()
	var calendar = CalendarClass.new()
	state.cash = 20000
	state.skills["driving"] = 50
	state.calendar = {"year": 2026, "month": 1, "day": 26, "week": 4, "week_index": 0}
	var bought := assets.buy(state, "metro_hatchback", 1, economy)
	_check(bool(assets.last_result.get("ok", false)), "Qualified player should buy the hatchback: %s" % bought)
	var happiness_before: int = state.happiness
	var stress_before: int = state.stress
	calendar.advance_one_week(state)
	var first_summary := assets.process_week(state, economy)
	var ledger_after_first: int = state.ledger.size()
	var cash_after_first: int = state.cash
	_check(_ledger_category_count(state, "asset_upkeep") == 1, "Car upkeep should charge once at the monthly boundary.")
	_check(state.happiness == happiness_before + 1 and state.stress == stress_before - 1, "Owned car should apply its monthly wellbeing benefit.")
	_check(not first_summary.is_empty(), "Asset week should explain upkeep, benefits, or market movement.")
	assets.process_week(state, economy)
	_check(state.ledger.size() == ledger_after_first and state.cash == cash_after_first, "Same-week asset processing must not duplicate upkeep or benefits.")
	calendar.advance_one_week(state)
	assets.process_week(state, economy)
	_check(_ledger_category_count(state, "asset_upkeep") == 1, "Car upkeep must not be charged on ordinary non-boundary weeks.")
	_check(not assets.get_access_tags(state).has("cargo_vehicle") and assets.get_access_tags(state).has("delivery_access"), "Owned asset benefits should expose stable opportunity tags.")


func _test_property_sync_and_save_roundtrip() -> void:
	var state = StateClass.new(5505)
	var assets = AssetsClass.new()
	var economy = EconomyClass.new()
	state.cash = 100000
	state.reputation = 60
	var bought := assets.buy(state, "riverside_micro_studio", 1, economy)
	_check(bool(assets.last_result.get("ok", false)), "Affordable qualified property purchase should succeed: %s" % bought)
	_check(state.owned_properties.has("riverside_micro_studio"), "Property purchase should synchronize LifeGameState.owned_properties.")
	_check(assets.total_value(state) > 0 and assets.net_worth(state) == state.cash + state.savings + assets.total_value(state) - state.debt, "Asset total and net worth APIs should reconcile.")

	var snapshot := state.to_dict()
	var restored = StateClass.new(1)
	_check(restored.from_dict(snapshot), "State containing an asset portfolio should deserialize.")
	var restored_assets = AssetsClass.new()
	_check(restored_assets.get_owned(restored).size() == 1, "Portfolio holdings should survive the existing save contract through flags.")
	_check(restored_assets.get_portfolio(restored).get("prices", {}) == assets.get_portfolio(state).get("prices", {}), "Live asset values should survive saving and loading.")

	# Refresh weekly time before testing a sale, as the deed purchase uses six hours.
	state.weekly_time = 40
	var sold := assets.sell(state, "riverside_micro_studio", 1, economy)
	_check(bool(assets.last_result.get("ok", false)), "Owned property should be sellable: %s" % sold)
	_check(not state.owned_properties.has("riverside_micro_studio"), "Selling the final property unit should remove the stable property ID.")


func _ledger_category_count(state, category: String) -> int:
	var result := 0
	for entry in state.ledger:
		if str(entry.get("category", "")) == category:
			result += 1
	return result


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
