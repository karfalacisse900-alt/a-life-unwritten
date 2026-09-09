extends SceneTree

const StateClass = preload("res://scripts/core/LifeGameState.gd")
const CalendarClass = preload("res://scripts/systems/CalendarSystem.gd")
const EconomyClass = preload("res://scripts/systems/EconomySystem.gd")
const MarketClass = preload("res://scripts/systems/MarketSystem.gd")

var failures: Array[String] = []


func _initialize() -> void:
	_test_catalog_and_ui_contract()
	_test_stock_buy_sell_lots_and_ledger()
	_test_crypto_milli_units_and_broker_change()
	_test_seeded_independent_weekly_prices()
	_test_distributions_and_idempotence()
	_test_order_limit_and_rejections()
	_test_portfolio_allocation_and_save_roundtrip()
	if failures.is_empty():
		print("MARKET_SYSTEM_TESTS_OK: simulated instruments, cent pricing, lots, trading, fees, P&L, independent weekly prices, news, distributions, limits, allocation, ledger, and saves")
		quit(0)
		return
	for failure in failures:
		push_error("MARKET_TEST_FAIL: %s" % failure)
	quit(1)


func _test_catalog_and_ui_contract() -> void:
	var state = StateClass.new(10101)
	var market = MarketClass.new()
	_check(market.load_errors.is_empty(), "Market JSON should load cleanly: %s" % " ".join(market.load_errors))
	_check(market.get_asset_classes().size() == 4, "Expected stock, crypto, ETF, and bond classes.")
	_check(market.get_market_list(state, "stock").size() == 8, "Expected eight fictional stocks.")
	_check(market.get_market_list(state, "crypto").size() >= 8, "Expected named coins plus four legacy fictional crypto assets.")
	_check(market.get_market_list(state, "etf").size() == 2, "Expected two fictional ETFs.")
	_check(market.get_market_list(state, "bond").size() == 1, "Expected one fictional bond.")
	var mcw := market.get_asset("MCW")
	_check(str(mcw.get("id", "")) == "meridian_cloudworks", "Symbols should resolve to stable IDs.")
	_check(int(mcw.get("initial_price_cents", 0)) == 8640, "Prices must be stored in integer cents.")
	_check(market.get_asset("TDB").get("unit_scale", 0) == 1000, "Crypto should use milli-unit quantities.")
	_check(market.search_market(state, "health").size() == 1, "Market search should match issuer, sector, and description.")
	var status := market.get_market_status(state)
	_check(str(status.get("mode", "")) == "simulated" and str(status.get("disclaimer", "")).contains("no live quotes"), "Status must clearly identify quotes as simulated.")


func _test_stock_buy_sell_lots_and_ledger() -> void:
	var state = StateClass.new(20202)
	var market = MarketClass.new()
	var economy = EconomyClass.new()
	state.cash = 1000
	var opening_cash: int = state.cash
	var buy_text := market.buy(state, "MCW", 1, economy)
	_check(bool(market.last_result.get("ok", false)), "A funded one-share stock order should execute: %s" % buy_text)
	var first_quote: Dictionary = market.last_result.get("quote", {})
	_check(int(first_quote.get("price_cents", 0)) == 8640 and int(first_quote.get("fee_cents", 0)) == 99, "Stock quote should preserve exact cent price and minimum fee.")
	_check(int(first_quote.get("total_cents", 0)) == 8739, "One MCW share should settle at 8,739 cents including fee.")
	_check(state.ledger.size() == 1 and int(state.ledger[0].get("amount", 0)) == -88, "Cent settlement should debit whole-dollar cash through EconomySystem.")
	_check(int(market.get_portfolio(state).get("cash_credit_cents", -1)) == 61, "Unused settlement cents should remain as brokerage cash, not disappear.")
	var holding := market.get_holdings(state)[0]
	_check(int(holding.get("quantity_units", 0)) == 1 and int(holding.get("cost_basis_cents", 0)) == 8739, "Purchase should create an exact-cost tax lot.")

	var sell_text := market.sell(state, "meridian_cloudworks", 1, economy)
	_check(bool(market.last_result.get("ok", false)), "Owned stock should be sellable by stable ID: %s" % sell_text)
	_check(market.get_holdings(state).is_empty(), "Selling the only share should leave no active holding.")
	_check(state.ledger.size() == 2 and str(state.ledger[1].get("category", "")) == "market_sale", "Sale cash must pass through EconomySystem.record.")
	var realized := int(market.get_portfolio_summary(state).get("realized_pnl_cents", 999999))
	_check(realized == -198, "FIFO realized P&L should include both 99-cent trade fees; got %d cents." % realized)
	var ledger_delta := 0
	for row in state.ledger:
		ledger_delta += int(row.get("amount", 0))
	_check(state.cash == opening_cash + ledger_delta, "Cash must reconcile exactly with market ledger records.")


func _test_crypto_milli_units_and_broker_change() -> void:
	var state = StateClass.new(30303)
	var market = MarketClass.new()
	var economy = EconomyClass.new()
	state.cash = 100
	var text := market.buy(state, "TDB", 250, economy)
	_check(bool(market.last_result.get("ok", false)), "A quarter fictional coin should be purchasable: %s" % text)
	var quote: Dictionary = market.last_result.get("quote", {})
	_check(str(quote.get("quantity_label", "")) == "0.25 TDB", "Crypto quantity should display the exact fraction without redundant zeros.")
	_check(int(quote.get("notional_cents", 0)) == 107 and int(quote.get("fee_cents", 0)) == 25, "0.250 TDB should calculate exact cent notional and crypto fee.")
	_check(int(quote.get("cash_required_dollars", 0)) == 2 and int(market.get_portfolio(state).get("cash_credit_cents", 0)) == 68, "Broker change should preserve sub-dollar settlement value.")
	var sell_text := market.sell(state, "TDB", 250, economy)
	_check(bool(market.last_result.get("ok", false)), "Milli-unit crypto holding should sell: %s" % sell_text)
	_check(int(market.get_portfolio(state).get("cash_credit_cents", -1)) == 50, "Crypto round trip should retain the exact remaining 50 cents at broker.")
	_check(int(market.get_portfolio_summary(state).get("realized_pnl_cents", 0)) == -50, "Crypto FIFO P&L should include exact buy and sell fees.")


func _test_seeded_independent_weekly_prices() -> void:
	var investor = StateClass.new(40404)
	var observer = StateClass.new(40404)
	var investor_market = MarketClass.new()
	var observer_market = MarketClass.new()
	var calendar_a = CalendarClass.new()
	var calendar_b = CalendarClass.new()
	investor.cash = 5000
	observer.cash = 5000
	investor_market.buy(investor, "BWT", 4, EconomyClass.new())
	# Deliberately consume the player's general RNG. Market movement must still be
	# derived only from seed/week/symbol and therefore remain identical.
	investor.randf_seeded()
	investor.randf_seeded()
	calendar_a.advance_one_week(investor)
	calendar_b.advance_one_week(observer)
	investor_market.process_week(investor, EconomyClass.new())
	observer_market.process_week(observer, EconomyClass.new())
	var prices_a: Dictionary = investor_market.get_portfolio(investor).get("prices_cents", {})
	var prices_b: Dictionary = observer_market.get_portfolio(observer).get("prices_cents", {})
	_check(prices_a == prices_b, "Same seed and week must produce the same prices regardless of holdings or general RNG usage.")
	_check(investor_market.get_market_news(investor).size() == 4, "Each weekly close should provide one macro story and three market movers.")
	var history_before := investor_market.get_price_history(investor, "BWT").size()
	var second_summary := investor_market.process_week(investor, EconomyClass.new())
	_check(second_summary.is_empty(), "Repeated processing of one week must be a no-op.")
	_check(investor_market.get_price_history(investor, "BWT").size() == history_before, "Idempotent weekly processing must not append duplicate prices.")


func _test_distributions_and_idempotence() -> void:
	var state = StateClass.new(50505)
	var market = MarketClass.new()
	var economy = EconomyClass.new()
	var calendar = CalendarClass.new()
	state.cash = 10000
	var bought := market.buy(state, "NTN", 20, economy)
	_check(bool(market.last_result.get("ok", false)), "Twenty fictional treasury notes should be affordable: %s" % bought)
	for _week in range(4):
		calendar.advance_one_week(state)
		market.process_week(state, economy)
	var distribution_count := _ledger_category_count(state, "market_distribution")
	_check(distribution_count >= 1, "Four-week treasury note interest should settle through EconomySystem.")
	var distributions := int(market.get_portfolio_summary(state).get("distributions_cents", 0))
	_check(distributions > 0, "Portfolio summary should retain exact cent distributions.")
	var ledger_size: int = state.ledger.size()
	var credit := int(market.get_portfolio(state).get("cash_credit_cents", 0))
	market.process_week(state, economy)
	_check(state.ledger.size() == ledger_size and int(market.get_portfolio(state).get("cash_credit_cents", 0)) == credit, "Same-week processing must not duplicate distributions or settlement.")


func _test_order_limit_and_rejections() -> void:
	var state = StateClass.new(60606)
	var market = MarketClass.new()
	var economy = EconomyClass.new()
	state.cash = 100
	for _order in range(8):
		market.buy(state, "OBL", 1, economy)
		_check(bool(market.last_result.get("ok", false)), "Each of the first eight weekly orders should execute.")
	var before_cash: int = state.cash
	var before_units := int(market.get_holdings(state, "crypto")[0].get("quantity_units", 0))
	var blocked := market.buy(state, "OBL", 1, economy)
	_check(not bool(market.last_result.get("ok", true)) and blocked.contains("limit"), "Ninth same-week order should be rejected with a clear limit reason.")
	_check(state.cash == before_cash and int(market.get_holdings(state, "crypto")[0].get("quantity_units", 0)) == before_units, "Rejected order must not mutate cash or holdings.")
	_check(int(market.get_order_limit_status(state).get("remaining", -1)) == 0, "UI order-limit API should report no remaining orders.")


func _test_portfolio_allocation_and_save_roundtrip() -> void:
	var state = StateClass.new(70707)
	var market = MarketClass.new()
	var economy = EconomyClass.new()
	state.cash = 5000
	market.buy(state, "AHS", 3, economy)
	market.buy(state, "EMB", 2000, economy)
	market.buy(state, "GLI", 2, economy)
	var summary := market.get_portfolio_summary(state)
	_check(int(summary.get("holding_count", 0)) == 3, "Portfolio should report three distinct holdings.")
	var allocation: Dictionary = summary.get("allocation_by_class_cents", {})
	_check(allocation.has("stock") and allocation.has("crypto") and allocation.has("etf"), "Allocation should separate realistic asset classes.")
	_check(int(summary.get("market_value_cents", 0)) > 0 and int(summary.get("cost_basis_cents", 0)) > 0, "Summary should expose market value and fee-inclusive cost basis in cents.")
	var snapshot := state.to_dict()
	var restored = StateClass.new(1)
	_check(restored.from_dict(snapshot), "State with brokerage flags should deserialize.")
	var restored_market = MarketClass.new()
	_check(restored_market.get_holdings(restored).size() == 3, "Holdings and tax lots should survive the existing save contract.")
	_check(restored_market.get_portfolio(restored).get("prices_cents", {}) == market.get_portfolio(state).get("prices_cents", {}), "Prices should survive a save/load round trip.")
	_check(restored_market.net_worth_cents(restored) == market.net_worth_cents(state), "Net worth should remain identical after save/load.")


func _ledger_category_count(state, category: String) -> int:
	var count := 0
	for entry in state.ledger:
		if str(entry.get("category", "")) == category:
			count += 1
	return count


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
