class_name MarketSystem
extends RefCounted

## A self-contained fictional securities market. Prices and tax lots use integer
## cents and integer quantity units. Stocks/funds/bonds use one unit per share;
## crypto uses the precision declared by each coin's unit_scale.
##
## Runtime data lives in state.flags[MARKET_FLAG], preserving compatibility with
## the existing versioned save contract. Market movement is derived from the
## save seed, week, sector, and symbol—not from holdings or trade activity.

const DATA_PATH := "res://data/markets.json"
const MARKET_FLAG := "simulated_markets"
const MARKET_VERSION := 1
const DEFAULT_HISTORY_WEEKS := 156
const DEFAULT_ORDER_LIMIT := 8
const MAX_TRANSACTIONS := 240
const MAX_ORDER_UNITS := 1000000000000

var load_errors: Array[String] = []
var last_result: Dictionary = {}

var _settings: Dictionary = {}
var _classes: Array[Dictionary] = []
var _instruments: Array[Dictionary] = []
var _by_id: Dictionary = {}
var _by_symbol: Dictionary = {}
var _macro_headlines: Dictionary = {}


func _init() -> void:
	_load_content()


func get_asset_classes() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for definition in _classes:
		result.append(definition.duplicate(true))
	return result


func get_asset(symbol_or_id: String) -> Dictionary:
	var key := symbol_or_id.strip_edges()
	if _by_id.has(key):
		return (_by_id[key] as Dictionary).duplicate(true)
	var symbol := key.to_upper()
	if _by_symbol.has(symbol):
		return (_by_symbol[symbol] as Dictionary).duplicate(true)
	return {}


## All instruments enriched with the current quote, weekly change, history, and
## owned quantity. class_filter accepts stock, crypto, etf, or bond.
func get_market_list(state, class_filter: String = "") -> Array[Dictionary]:
	var market := _ensure_market(state)
	var result: Array[Dictionary] = []
	var holdings: Dictionary = market.get("holdings", {})
	var prices: Dictionary = market.get("prices_cents", {})
	var changes: Dictionary = market.get("weekly_changes", {})
	for definition in _instruments:
		var asset_class := str(definition.get("asset_class", ""))
		if not class_filter.is_empty() and asset_class != class_filter:
			continue
		var symbol := str(definition.get("symbol", ""))
		var item := definition.duplicate(true)
		var price := maxi(1, int(prices.get(symbol, definition.get("initial_price_cents", 1))))
		var change: Dictionary = changes.get(symbol, {}) if changes.get(symbol, {}) is Dictionary else {}
		var holding: Dictionary = holdings.get(symbol, {}) if holdings.get(symbol, {}) is Dictionary else {}
		var default_units := default_order_units(symbol)
		item["price_cents"] = price
		item["formatted_price"] = format_price(price)
		item["previous_price_cents"] = int(change.get("old_price_cents", price))
		item["change_basis_points"] = int(change.get("change_basis_points", 0))
		item["change_percent"] = float(int(item["change_basis_points"])) / 100.0
		item["price_history_cents"] = _price_history_from_market(market, symbol)
		item["owned_quantity_units"] = maxi(0, int(holding.get("quantity_units", 0)))
		item["owned_quantity_label"] = format_quantity(symbol, int(item["owned_quantity_units"]))
		item["owned_market_value_cents"] = _holding_market_value_cents(definition, holding, price)
		item["default_order_units"] = default_units
		item["buy_quote"] = quote_buy(state, symbol, default_units)
		result.append(item)
	return result


func search_market(state, query: String, class_filter: String = "") -> Array[Dictionary]:
	var clean_query := query.strip_edges().to_lower()
	if clean_query.is_empty():
		return get_market_list(state, class_filter)
	var result: Array[Dictionary] = []
	for item in get_market_list(state, class_filter):
		var haystack := "%s %s %s %s" % [str(item.get("symbol", "")), str(item.get("name", "")), str(item.get("sector", "")), str(item.get("description", ""))]
		if haystack.to_lower().contains(clean_query):
			result.append(item)
	return result


func get_holdings(state, class_filter: String = "") -> Array[Dictionary]:
	var market := _ensure_market(state)
	var result: Array[Dictionary] = []
	var holdings: Dictionary = market.get("holdings", {})
	var prices: Dictionary = market.get("prices_cents", {})
	for definition in _instruments:
		var asset_class := str(definition.get("asset_class", ""))
		if not class_filter.is_empty() and asset_class != class_filter:
			continue
		var symbol := str(definition.get("symbol", ""))
		if not holdings.has(symbol) or not holdings[symbol] is Dictionary:
			continue
		var holding: Dictionary = holdings[symbol]
		var quantity := maxi(0, int(holding.get("quantity_units", 0)))
		if quantity <= 0:
			continue
		var price := maxi(1, int(prices.get(symbol, definition.get("initial_price_cents", 1))))
		var market_value := _holding_market_value_cents(definition, holding, price)
		var cost_basis := _holding_cost_basis_cents(holding)
		var item := definition.duplicate(true)
		item.merge(holding.duplicate(true), true)
		item["price_cents"] = price
		item["formatted_price"] = format_price(price)
		item["quantity_units"] = quantity
		item["quantity_label"] = format_quantity(symbol, quantity)
		item["market_value_cents"] = market_value
		item["cost_basis_cents"] = cost_basis
		item["average_cost_cents"] = _average_unit_cost_cents(definition, holding)
		item["unrealized_pnl_cents"] = market_value - cost_basis
		item["price_history_cents"] = _price_history_from_market(market, symbol)
		result.append(item)
	return result


func get_portfolio(state) -> Dictionary:
	return _ensure_market(state).duplicate(true)


func get_portfolio_summary(state) -> Dictionary:
	var market := _ensure_market(state)
	var holdings := get_holdings(state)
	var total_value := 0
	var total_basis := 0
	var allocation_by_class: Dictionary = {}
	var allocation_by_symbol: Dictionary = {}
	for holding in holdings:
		var value := int(holding.get("market_value_cents", 0))
		var basis := int(holding.get("cost_basis_cents", 0))
		var asset_class := str(holding.get("asset_class", "other"))
		var symbol := str(holding.get("symbol", ""))
		total_value += value
		total_basis += basis
		allocation_by_class[asset_class] = int(allocation_by_class.get(asset_class, 0)) + value
		allocation_by_symbol[symbol] = value
	var class_percentages: Dictionary = {}
	var symbol_percentages: Dictionary = {}
	for asset_class in allocation_by_class:
		class_percentages[asset_class] = _percent_basis_points(int(allocation_by_class[asset_class]), total_value)
	for symbol in allocation_by_symbol:
		symbol_percentages[symbol] = _percent_basis_points(int(allocation_by_symbol[symbol]), total_value)
	var broker_cash := maxi(0, int(market.get("cash_credit_cents", 0)))
	return {
		"holding_count": holdings.size(),
		"market_value_cents": total_value,
		"cost_basis_cents": total_basis,
		"unrealized_pnl_cents": total_value - total_basis,
		"realized_pnl_cents": int(market.get("realized_pnl_cents", 0)),
		"distributions_cents": int(market.get("distributions_cents", 0)),
		"broker_cash_cents": broker_cash,
		"portfolio_value_cents": total_value + broker_cash,
		"allocation_by_class_cents": allocation_by_class,
		"allocation_by_class_basis_points": class_percentages,
		"allocation_by_symbol_cents": allocation_by_symbol,
		"allocation_by_symbol_basis_points": symbol_percentages,
		"net_worth_cents": net_worth_cents(state),
		"orders": get_order_limit_status(state),
	}


func total_market_value_cents(state) -> int:
	return int(get_portfolio_summary(state).get("market_value_cents", 0))


func net_worth_cents(state) -> int:
	var market := _ensure_market(state)
	var value := 0
	var holdings: Dictionary = market.get("holdings", {})
	var prices: Dictionary = market.get("prices_cents", {})
	for definition in _instruments:
		var symbol := str(definition.get("symbol", ""))
		if holdings.has(symbol) and holdings[symbol] is Dictionary:
			var price := maxi(1, int(prices.get(symbol, definition.get("initial_price_cents", 1))))
			value += _holding_market_value_cents(definition, holdings[symbol], price)
	return (int(state.cash) + int(state.savings) - int(state.debt)) * 100 + value + maxi(0, int(market.get("cash_credit_cents", 0)))


func get_price_history(state, symbol_or_id: String) -> Array[int]:
	var definition := get_asset(symbol_or_id)
	if definition.is_empty():
		return []
	return _price_history_from_market(_ensure_market(state), str(definition.get("symbol", "")))


func get_market_news(state) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var raw: Variant = _ensure_market(state).get("news", [])
	if raw is Array:
		for item in raw:
			if item is Dictionary:
				result.append(item.duplicate(true))
	return result


func get_transactions(state, limit: int = 50) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var raw: Variant = _ensure_market(state).get("transactions", [])
	if not raw is Array:
		return result
	var start := maxi(0, raw.size() - maxi(0, limit))
	for index in range(raw.size() - 1, start - 1, -1):
		if raw[index] is Dictionary:
			result.append(raw[index].duplicate(true))
	return result


func get_market_status(state) -> Dictionary:
	var week_index := int(state.calendar.get("week_index", 0))
	return {
		"mode": "simulated",
		"currency": "USD",
		"as_of": _date_key(state.calendar),
		"week_index": week_index,
		"equities": {"status": "accepting_orders", "label": "Weekly market · orders accepted", "execution": "Current simulated quote"},
		"crypto": {"status": "always_open", "label": "Simulated 24/7 market", "execution": "Current simulated quote"},
		"disclaimer": "All prices are game prices. Named coins and fictional securities use simulated markets; no live quotes or real-money trading.",
	}


func get_order_limit_status(state) -> Dictionary:
	var market := _ensure_market(state)
	var week_index := int(state.calendar.get("week_index", 0))
	var orders: Dictionary = market.get("weekly_orders", {}) if market.get("weekly_orders", {}) is Dictionary else {}
	var used := int(orders.get("count", 0)) if int(orders.get("week_index", -1)) == week_index else 0
	var limit := maxi(1, int(_settings.get("orders_per_week", DEFAULT_ORDER_LIMIT)))
	return {"week_index": week_index, "used": used, "limit": limit, "remaining": maxi(0, limit - used)}


func default_order_units(symbol_or_id: String) -> int:
	var definition := get_asset(symbol_or_id)
	if definition.is_empty():
		return 1
	return maxi(1, int(definition.get("unit_scale", 1)))


## Converts whole shares or whole coins into the system's integer quantity units.
func units_for_whole_quantity(symbol_or_id: String, whole_quantity: int) -> int:
	if whole_quantity <= 0:
		return 0
	return whole_quantity * default_order_units(symbol_or_id)


## Parse decimal text directly into integer units: excess precision is rejected,
## never rounded or silently truncated. No scientific notation or separators.
func parse_quantity(symbol_or_id: String, amount_text: String) -> Dictionary:
	var definition := get_asset(symbol_or_id)
	if definition.is_empty(): return {"ok":false, "reason":"Choose an available asset."}
	var clean := amount_text.strip_edges()
	var decimals := quantity_decimals(symbol_or_id)
	if clean.is_empty(): return {"ok":false, "reason":"Enter an amount."}
	if clean.length() > 24: return {"ok":false, "reason":"That amount is too large."}
	var parts := clean.split(".", true)
	if parts.size() > 2: return {"ok":false, "reason":"Enter a number, for example 0.01."}
	var whole := str(parts[0])
	var fraction := str(parts[1]) if parts.size() == 2 else ""
	if whole.is_empty(): whole = "0"
	for digit in whole + fraction:
		if digit < "0" or digit > "9": return {"ok":false, "reason":"Use digits and a decimal point only."}
	if fraction.length() > decimals:
		return {"ok":false, "reason":"Use whole shares." if decimals == 0 else "This coin supports up to %d decimal places." % decimals}
	if whole.length() > 12: return {"ok":false, "reason":"That amount is too large."}
	var scale := default_order_units(symbol_or_id)
	if int(whole) > MAX_ORDER_UNITS / scale: return {"ok":false, "reason":"That amount exceeds the order limit."}
	var units := int(whole) * scale
	if not fraction.is_empty(): units += int(fraction.rpad(decimals, "0"))
	if units <= 0: return {"ok":false, "reason":"Enter an amount greater than zero."}
	if units > MAX_ORDER_UNITS: return {"ok":false, "reason":"That amount exceeds the order limit."}
	return {"ok":true, "quantity_units":units, "quantity_text":quantity_text(symbol_or_id, units)}


func quantity_decimals(symbol_or_id: String) -> int:
	var scale := default_order_units(symbol_or_id)
	var digits := 0
	while scale > 1:
		scale /= 10
		digits += 1
	return digits


func quantity_text(symbol_or_id: String, quantity_units: int) -> String:
	var scale := default_order_units(symbol_or_id)
	var whole := quantity_units / scale
	if scale == 1: return str(whole)
	var fraction := str(absi(quantity_units % scale)).lpad(quantity_decimals(symbol_or_id), "0")
	while fraction.ends_with("0"): fraction = fraction.left(-1)
	return str(whole) if fraction.is_empty() else "%d.%s" % [whole, fraction]


func maximum_order_units(state, symbol_or_id: String, side: String) -> int:
	if side == "sell":
		for holding in get_holdings(state):
			if str(holding.get("symbol", "")) == str(get_asset(symbol_or_id).get("symbol", "")):
				return mini(MAX_ORDER_UNITS, int(holding.get("quantity_units", 0)))
		return 0
	if not bool(eligibility_details(state, symbol_or_id, "buy").get("ok", false)): return 0
	var low := 0
	var high := MAX_ORDER_UNITS
	while low < high:
		var midpoint := low + (high - low + 1) / 2
		var quote := quote_buy(state, symbol_or_id, midpoint)
		if bool(quote.get("valid", false)) and int(quote.get("cash_required_dollars", 0)) <= int(state.cash):
			low = midpoint
		else:
			high = midpoint - 1
	return low


func quote_buy(state, symbol_or_id: String, quantity_units: int) -> Dictionary:
	var definition := get_asset(symbol_or_id)
	if definition.is_empty() or quantity_units <= 0 or quantity_units > MAX_ORDER_UNITS:
		return {"valid": false, "symbol": symbol_or_id.to_upper(), "quantity_units": quantity_units, "notional_cents": 0, "fee_cents": 0, "total_cents": 0}
	var symbol := str(definition.get("symbol", ""))
	var market := _ensure_market(state)
	var price := maxi(1, int((market.get("prices_cents", {}) as Dictionary).get(symbol, definition.get("initial_price_cents", 1))))
	var notional := _notional_cents(price, quantity_units, int(definition.get("unit_scale", 1)))
	var fee := _trade_fee_cents(notional, str(definition.get("asset_class", "stock")))
	var total := notional + fee
	var credit_before := maxi(0, int(market.get("cash_credit_cents", 0)))
	var credit_used := mini(credit_before, total)
	var uncovered := total - credit_used
	var cash_dollars := _ceil_div(uncovered, 100)
	var credit_after := credit_before - credit_used + cash_dollars * 100 - uncovered
	return {
		"valid": true,
		"side": "buy",
		"asset_id": str(definition.get("id", "")),
		"symbol": symbol,
		"asset_class": str(definition.get("asset_class", "")),
		"quantity_units": quantity_units,
		"quantity_label": format_quantity(symbol, quantity_units),
		"unit_scale": int(definition.get("unit_scale", 1)),
		"price_cents": price,
		"notional_cents": notional,
		"fee_cents": fee,
		"total_cents": total,
		"broker_cash_before_cents": credit_before,
		"broker_cash_used_cents": credit_used,
		"cash_required_dollars": cash_dollars,
		"broker_cash_after_cents": credit_after,
	}


func quote_sell(state, symbol_or_id: String, quantity_units: int) -> Dictionary:
	var definition := get_asset(symbol_or_id)
	if definition.is_empty() or quantity_units <= 0 or quantity_units > MAX_ORDER_UNITS:
		return {"valid": false, "symbol": symbol_or_id.to_upper(), "quantity_units": quantity_units, "gross_cents": 0, "fee_cents": 0, "net_proceeds_cents": 0}
	var symbol := str(definition.get("symbol", ""))
	var market := _ensure_market(state)
	var holdings: Dictionary = market.get("holdings", {})
	var holding: Dictionary = holdings.get(symbol, {}) if holdings.get(symbol, {}) is Dictionary else {}
	var owned := maxi(0, int(holding.get("quantity_units", 0)))
	var price := maxi(1, int((market.get("prices_cents", {}) as Dictionary).get(symbol, definition.get("initial_price_cents", 1))))
	var executable_quantity := mini(quantity_units, owned)
	var gross := _notional_cents(price, executable_quantity, int(definition.get("unit_scale", 1)))
	# Closing a tiny fractional holding never charges more than its proceeds.
	# The displayed fee must equal the actual deduction, even for one satoshi.
	var fee := mini(gross, _trade_fee_cents(gross, str(definition.get("asset_class", "stock")))) if gross > 0 else 0
	var net := maxi(0, gross - fee)
	var basis := _preview_fifo_cost_basis(holding, executable_quantity)
	var credit_before := maxi(0, int(market.get("cash_credit_cents", 0)))
	var settlement := credit_before + net
	var cash_dollars := settlement / 100
	var credit_after := settlement % 100
	return {
		"valid": owned >= quantity_units and quantity_units > 0,
		"side": "sell",
		"asset_id": str(definition.get("id", "")),
		"symbol": symbol,
		"asset_class": str(definition.get("asset_class", "")),
		"quantity_units": quantity_units,
		"quantity_label": format_quantity(symbol, quantity_units),
		"owned_quantity_units": owned,
		"unit_scale": int(definition.get("unit_scale", 1)),
		"price_cents": price,
		"gross_cents": gross,
		"fee_cents": fee,
		"net_proceeds_cents": net,
		"estimated_cost_basis_cents": basis,
		"estimated_realized_pnl_cents": net - basis,
		"broker_cash_before_cents": credit_before,
		"cash_payout_dollars": cash_dollars,
		"broker_cash_after_cents": credit_after,
	}


func eligibility_details(state, symbol_or_id: String, side: String = "buy", quantity_units: int = 0) -> Dictionary:
	var definition := get_asset(symbol_or_id)
	var reasons: Array[String] = []
	if definition.is_empty():
		reasons.append("That market symbol is unavailable.")
		return {"eligible": false, "ok": false, "reasons": reasons, "reason": reasons[0]}
	if int(state.age) < 18:
		reasons.append("A brokerage account requires the player to be 18.")
	if bool(state.flags.get("broker_account_suspended", false)):
		reasons.append("The brokerage account is temporarily restricted.")
	if bool(state.crime.get("in_jail", false)) or int(state.crime.get("jail_weeks", 0)) > 0:
		reasons.append("Market orders are unavailable while incarcerated.")
	var order_status := get_order_limit_status(state)
	if int(order_status.get("remaining", 0)) <= 0:
		reasons.append("This week's limit of %d market orders has been reached." % int(order_status.get("limit", DEFAULT_ORDER_LIMIT)))
	if quantity_units < 0:
		reasons.append("Quantity cannot be negative.")
	if quantity_units > MAX_ORDER_UNITS:
		reasons.append("That amount exceeds the order limit.")
	if not side in ["buy", "sell"]:
		reasons.append("Order side must be buy or sell.")
	return {
		"eligible": reasons.is_empty(),
		"ok": reasons.is_empty(),
		"reasons": reasons,
		"reason": _join_strings(reasons),
		"asset": definition,
		"orders": order_status,
	}


func can_buy(state, symbol_or_id: String, quantity_units: int) -> Dictionary:
	var eligibility := eligibility_details(state, symbol_or_id, "buy", quantity_units)
	var reasons: Array[String] = eligibility.get("reasons", []).duplicate()
	var quote := quote_buy(state, symbol_or_id, quantity_units)
	if quantity_units <= 0:
		reasons.append("Choose a positive quantity.")
	if not bool(quote.get("valid", false)):
		reasons.append("A valid purchase quote could not be created.")
	elif int(state.cash) < int(quote.get("cash_required_dollars", 0)):
		reasons.append("This order needs $%d cash after applying brokerage change; you have $%d." % [int(quote.get("cash_required_dollars", 0)), int(state.cash)])
	return {"eligible": reasons.is_empty(), "ok": reasons.is_empty(), "reasons": reasons, "reason": _join_strings(reasons), "quote": quote, "orders": get_order_limit_status(state)}


func can_sell(state, symbol_or_id: String, quantity_units: int) -> Dictionary:
	var eligibility := eligibility_details(state, symbol_or_id, "sell", quantity_units)
	var reasons: Array[String] = eligibility.get("reasons", []).duplicate()
	var quote := quote_sell(state, symbol_or_id, quantity_units)
	if quantity_units <= 0:
		reasons.append("Choose a positive quantity.")
	if not bool(quote.get("valid", false)):
		var owned := int(quote.get("owned_quantity_units", 0))
		reasons.append("You own %s and cannot sell %s." % [format_quantity(symbol_or_id, owned), format_quantity(symbol_or_id, quantity_units)])
	return {"eligible": reasons.is_empty(), "ok": reasons.is_empty(), "reasons": reasons, "reason": _join_strings(reasons), "quote": quote, "orders": get_order_limit_status(state)}


func buy(state, symbol_or_id: String, quantity_units: int, economy) -> String:
	if economy == null or not economy.has_method("record"):
		last_result = {"ok": false, "reason": "The accounting service is unavailable."}
		return str(last_result["reason"])
	var details := can_buy(state, symbol_or_id, quantity_units)
	if not bool(details.get("eligible", false)):
		last_result = {"ok": false, "reason": str(details.get("reason", "This order is unavailable.")), "details": details}
		return "Order rejected: %s" % str(last_result["reason"])
	var quote: Dictionary = details.get("quote", {})
	var definition := get_asset(symbol_or_id)
	var symbol := str(definition.get("symbol", ""))
	var cash_required := int(quote.get("cash_required_dollars", 0))
	if cash_required > 0:
		economy.record(state, -cash_required, "Brokerage purchase — %s %s" % [str(quote.get("quantity_label", "")), symbol], "market_purchase")
	var market := _ensure_market(state)
	market["cash_credit_cents"] = int(quote.get("broker_cash_after_cents", 0))
	var holdings: Dictionary = market.get("holdings", {})
	var holding := _sanitized_holding(holdings.get(symbol, {}))
	var lots: Array = holding.get("lots", [])
	lots.append({
		"quantity_units": quantity_units,
		"total_cost_cents": int(quote.get("total_cents", 0)),
		"price_cents": int(quote.get("price_cents", 0)),
		"fee_cents": int(quote.get("fee_cents", 0)),
		"acquired_week": int(state.calendar.get("week_index", 0)),
	})
	holding["lots"] = lots
	holding["quantity_units"] = int(holding.get("quantity_units", 0)) + quantity_units
	holding["last_trade_week"] = int(state.calendar.get("week_index", 0))
	holdings[symbol] = holding
	market["holdings"] = holdings
	_increment_order_count(market, int(state.calendar.get("week_index", 0)))
	_append_transaction(market, {
		"week_index": int(state.calendar.get("week_index", 0)), "date": _date_key(state.calendar), "side": "buy",
		"symbol": symbol, "quantity_units": quantity_units, "quantity_label": str(quote.get("quantity_label", "")),
		"price_cents": int(quote.get("price_cents", 0)), "notional_cents": int(quote.get("notional_cents", 0)),
		"fee_cents": int(quote.get("fee_cents", 0)), "settlement_cents": -int(quote.get("total_cents", 0)),
		"cash_ledger_dollars": -cash_required,
	})
	state.flags[MARKET_FLAG] = market
	state.add_history("Bought %s of %s (%s)." % [str(quote.get("quantity_label", "")), str(definition.get("name", symbol)), symbol])
	last_result = {"ok": true, "action": "buy", "symbol": symbol, "quantity_units": quantity_units, "quote": quote}
	return "Bought %s of %s at %s; fee %s." % [str(quote.get("quantity_label", "")), symbol, format_price(int(quote.get("price_cents", 0))), format_price(int(quote.get("fee_cents", 0)))]


func sell(state, symbol_or_id: String, quantity_units: int, economy) -> String:
	if economy == null or not economy.has_method("record"):
		last_result = {"ok": false, "reason": "The accounting service is unavailable."}
		return str(last_result["reason"])
	var details := can_sell(state, symbol_or_id, quantity_units)
	if not bool(details.get("eligible", false)):
		last_result = {"ok": false, "reason": str(details.get("reason", "This order is unavailable.")), "details": details}
		return "Order rejected: %s" % str(last_result["reason"])
	var quote: Dictionary = details.get("quote", {})
	var definition := get_asset(symbol_or_id)
	var symbol := str(definition.get("symbol", ""))
	var market := _ensure_market(state)
	var holdings: Dictionary = market.get("holdings", {})
	var holding := _sanitized_holding(holdings.get(symbol, {}))
	var consumed := _consume_fifo_lots(holding, quantity_units)
	var basis := int(consumed.get("cost_basis_cents", 0))
	holding = consumed.get("holding", holding)
	var realized := int(quote.get("net_proceeds_cents", 0)) - basis
	holding["realized_pnl_cents"] = int(holding.get("realized_pnl_cents", 0)) + realized
	holding["last_trade_week"] = int(state.calendar.get("week_index", 0))
	holdings[symbol] = holding
	market["holdings"] = holdings
	market["realized_pnl_cents"] = int(market.get("realized_pnl_cents", 0)) + realized
	market["cash_credit_cents"] = int(quote.get("broker_cash_after_cents", 0))
	var payout := int(quote.get("cash_payout_dollars", 0))
	if payout > 0:
		economy.record(state, payout, "Brokerage sale — %s %s" % [str(quote.get("quantity_label", "")), symbol], "market_sale")
	_increment_order_count(market, int(state.calendar.get("week_index", 0)))
	_append_transaction(market, {
		"week_index": int(state.calendar.get("week_index", 0)), "date": _date_key(state.calendar), "side": "sell",
		"symbol": symbol, "quantity_units": quantity_units, "quantity_label": str(quote.get("quantity_label", "")),
		"price_cents": int(quote.get("price_cents", 0)), "notional_cents": int(quote.get("gross_cents", 0)),
		"fee_cents": int(quote.get("fee_cents", 0)), "settlement_cents": int(quote.get("net_proceeds_cents", 0)),
		"cost_basis_cents": basis, "realized_pnl_cents": realized, "cash_ledger_dollars": payout,
	})
	state.flags[MARKET_FLAG] = market
	state.add_history("Sold %s of %s (%s)." % [str(quote.get("quantity_label", "")), str(definition.get("name", symbol)), symbol])
	last_result = {"ok": true, "action": "sell", "symbol": symbol, "quantity_units": quantity_units, "realized_pnl_cents": realized, "quote": quote}
	return "Sold %s of %s at %s; realized %s." % [str(quote.get("quantity_label", "")), symbol, format_price(int(quote.get("price_cents", 0))), _signed_money(realized)]


## Advances every quote exactly once per calendar week. Price generation uses a
## private deterministic weekly seed, so player holdings and order history cannot
## influence future prices. Distributions settle through EconomySystem.record.
func process_week(state, economy = null) -> Array[String]:
	var summary: Array[String] = []
	var market := _ensure_market(state)
	var week_index := int(state.calendar.get("week_index", 0))
	if week_index <= int(market.get("last_processed_week", 0)):
		return summary
	market["last_processed_week"] = week_index
	var macro_bp := _macro_change_basis_points(int(state.seed), week_index)
	market["macro_basis_points"] = macro_bp
	var prices: Dictionary = market.get("prices_cents", {})
	var histories: Dictionary = market.get("price_history_cents", {})
	var changes: Dictionary = {}
	var movers: Array[Dictionary] = []
	var history_limit := maxi(12, int(_settings.get("history_weeks", DEFAULT_HISTORY_WEEKS)))
	for definition in _instruments:
		var symbol := str(definition.get("symbol", ""))
		var old_price := maxi(1, int(prices.get(symbol, definition.get("initial_price_cents", 1))))
		var change_bp := _instrument_change_basis_points(definition, int(state.seed), week_index, macro_bp)
		var new_price := maxi(int(definition.get("minimum_price_cents", 1)), _apply_basis_points(old_price, change_bp))
		prices[symbol] = new_price
		var history: Array = histories.get(symbol, []) if histories.get(symbol, []) is Array else []
		history.append(new_price)
		while history.size() > history_limit:
			history.pop_front()
		histories[symbol] = history
		var actual_change_bp := _change_basis_points(old_price, new_price)
		changes[symbol] = {"old_price_cents": old_price, "new_price_cents": new_price, "change_basis_points": actual_change_bp}
		movers.append({"symbol": symbol, "name": str(definition.get("name", symbol)), "asset_class": str(definition.get("asset_class", "")), "change_basis_points": actual_change_bp, "price_cents": new_price})
	market["prices_cents"] = prices
	market["price_history_cents"] = histories
	market["weekly_changes"] = changes
	market["news"] = _build_weekly_news(int(state.seed), week_index, macro_bp, movers)
	_process_distributions(state, economy, market, summary)
	state.flags[MARKET_FLAG] = market
	var direction := "gained" if macro_bp > 25 else ("fell" if macro_bp < -25 else "was nearly flat")
	var stock_mover := _largest_mover(movers, "stock")
	if stock_mover.is_empty():
		summary.append("The fictional market %s this week." % direction)
	else:
		summary.append("Markets %s; %s moved %+.2f%%." % [direction, str(stock_mover.get("symbol", "")), float(int(stock_mover.get("change_basis_points", 0))) / 100.0])
	return summary


func format_price(cents: int) -> String:
	var sign := "-" if cents < 0 else ""
	var absolute := absi(cents)
	return "%s$%s.%02d" % [sign, _commas(absolute / 100), absolute % 100]


func format_quantity(symbol_or_id: String, quantity_units: int) -> String:
	var definition := get_asset(symbol_or_id)
	if definition.is_empty():
		return str(quantity_units)
	var scale := maxi(1, int(definition.get("unit_scale", 1)))
	if scale == 1:
		return "%d share%s" % [quantity_units, "" if quantity_units == 1 else "s"]
	return "%s %s" % [quantity_text(symbol_or_id, quantity_units), str(definition.get("symbol", ""))]


func _ensure_market(state) -> Dictionary:
	var raw: Variant = state.flags.get(MARKET_FLAG, {})
	var market: Dictionary = raw.duplicate(true) if raw is Dictionary else {}
	if int(market.get("version", 0)) != MARKET_VERSION:
		market = {
			"version": MARKET_VERSION,
			"prices_cents": {},
			"price_history_cents": {},
			"weekly_changes": {},
			"holdings": {},
			"transactions": [],
			"news": [{"kind": "notice", "headline": "Fictional market", "body": "Prices are simulated and are not connected to real markets."}],
			"cash_credit_cents": 0,
			"realized_pnl_cents": 0,
			"distributions_cents": 0,
			"last_processed_week": 0,
			"weekly_orders": {"week_index": int(state.calendar.get("week_index", 0)), "count": 0},
		}
	var prices: Dictionary = market.get("prices_cents", {}) if market.get("prices_cents", {}) is Dictionary else {}
	var histories: Dictionary = market.get("price_history_cents", {}) if market.get("price_history_cents", {}) is Dictionary else {}
	for definition in _instruments:
		var symbol := str(definition.get("symbol", ""))
		var initial := maxi(1, int(definition.get("initial_price_cents", 1)))
		prices[symbol] = maxi(1, int(prices.get(symbol, initial)))
		if not histories.get(symbol, []) is Array or (histories.get(symbol, []) as Array).is_empty():
			histories[symbol] = [int(prices[symbol])]
	market["prices_cents"] = prices
	market["price_history_cents"] = histories
	market["cash_credit_cents"] = clampi(int(market.get("cash_credit_cents", 0)), 0, 99)
	state.flags[MARKET_FLAG] = market
	return market


func _process_distributions(state, economy, market: Dictionary, summary: Array[String]) -> void:
	if economy == null or not economy.has_method("record"):
		return
	var week_index := int(state.calendar.get("week_index", 0))
	var holdings: Dictionary = market.get("holdings", {})
	var prices: Dictionary = market.get("prices_cents", {})
	for definition in _instruments:
		var interval := maxi(0, int(definition.get("distribution_interval_weeks", 0)))
		var yield_bp := maxi(0, int(definition.get("annual_yield_basis_points", 0)))
		if interval <= 0 or yield_bp <= 0 or week_index % interval != 0:
			continue
		var symbol := str(definition.get("symbol", ""))
		if not holdings.has(symbol) or not holdings[symbol] is Dictionary:
			continue
		var holding: Dictionary = holdings[symbol]
		if int(holding.get("quantity_units", 0)) <= 0:
			continue
		var value := _holding_market_value_cents(definition, holding, int(prices.get(symbol, 1)))
		var distribution := _rounded_ratio(value * yield_bp * interval, 10000 * 52)
		if distribution <= 0:
			continue
		var settlement := int(market.get("cash_credit_cents", 0)) + distribution
		var payout_dollars := settlement / 100
		market["cash_credit_cents"] = settlement % 100
		if payout_dollars > 0:
			economy.record(state, payout_dollars, "%s distribution" % symbol, "market_distribution")
		holding["distributions_cents"] = int(holding.get("distributions_cents", 0)) + distribution
		holdings[symbol] = holding
		market["distributions_cents"] = int(market.get("distributions_cents", 0)) + distribution
		_append_transaction(market, {
			"week_index": week_index, "date": _date_key(state.calendar), "side": "distribution", "symbol": symbol,
			"quantity_units": int(holding.get("quantity_units", 0)), "settlement_cents": distribution,
			"cash_ledger_dollars": payout_dollars,
		})
		summary.append("%s paid a %s distribution." % [symbol, format_price(distribution)])
	market["holdings"] = holdings


func _instrument_change_basis_points(definition: Dictionary, save_seed: int, week_index: int, macro_bp: int) -> int:
	var symbol := str(definition.get("symbol", ""))
	var sector := str(definition.get("sector", ""))
	var volatility := maxi(0, int(definition.get("volatility_basis_points", 0)))
	var drift := int(definition.get("drift_basis_points", 0))
	var beta := int(definition.get("market_beta_basis_points", 10000))
	var market_component := _rounded_ratio(macro_bp * beta, 10000)
	var sector_noise := _seeded_centered(save_seed, week_index, "sector:%s" % sector, 140)
	var idiosyncratic := _seeded_bell(save_seed, week_index, "symbol:%s" % symbol, volatility)
	var asset_class := str(definition.get("asset_class", "stock"))
	var class_limit := 1600
	match asset_class:
		"crypto":
			class_limit = 3400
			sector_noise = _seeded_centered(save_seed, week_index, "digital-assets", 420)
		"etf":
			class_limit = 850
			sector_noise = _rounded_ratio(sector_noise, 3)
		"bond":
			class_limit = 300
			sector_noise = _rounded_ratio(sector_noise, 5)
	return clampi(drift + market_component + sector_noise + idiosyncratic, -class_limit, class_limit)


func _macro_change_basis_points(save_seed: int, week_index: int) -> int:
	return _seeded_bell(save_seed, week_index, "macro", 310)


func _seeded_centered(save_seed: int, week_index: int, channel: String, amplitude: int) -> int:
	var rng := RandomNumberGenerator.new()
	rng.seed = _derived_seed(save_seed, week_index, channel)
	return roundi((rng.randf() * 2.0 - 1.0) * float(amplitude))


func _seeded_bell(save_seed: int, week_index: int, channel: String, amplitude: int) -> int:
	var rng := RandomNumberGenerator.new()
	rng.seed = _derived_seed(save_seed, week_index, channel)
	var sample := (rng.randf() + rng.randf() + rng.randf() + rng.randf() - 2.0) / 2.0
	return roundi(sample * float(amplitude))


func _derived_seed(save_seed: int, week_index: int, channel: String) -> int:
	var hash_value := 2166136261
	for index in channel.length():
		hash_value = int((hash_value ^ channel.unicode_at(index)) * 16777619) & 0x7fffffff
	return (absi(save_seed) * 1000003 + week_index * 9176 + hash_value * 37 + 97) & 0x7fffffffffffffff


func _build_weekly_news(save_seed: int, week_index: int, macro_bp: int, movers: Array[Dictionary]) -> Array[Dictionary]:
	var news: Array[Dictionary] = []
	var tone := "positive" if macro_bp > 80 else ("negative" if macro_bp < -80 else "neutral")
	var options: Array = _macro_headlines.get(tone, []) if _macro_headlines.get(tone, []) is Array else []
	var headline := "Markets completed another simulated week."
	if not options.is_empty():
		var choice := absi(_derived_seed(save_seed, week_index, "headline:%s" % tone)) % options.size()
		headline = str(options[choice])
	news.append({"kind": "macro", "tone": tone, "headline": headline, "body": "Broad market impulse: %+.2f%%." % (float(macro_bp) / 100.0), "week_index": week_index})
	var sorted := movers.duplicate(true)
	sorted.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return absi(int(a.get("change_basis_points", 0))) > absi(int(b.get("change_basis_points", 0))))
	for mover in sorted.slice(0, mini(3, sorted.size())):
		var change_bp := int(mover.get("change_basis_points", 0))
		var direction := "advanced" if change_bp >= 0 else "declined"
		news.append({
			"kind": "mover", "tone": "positive" if change_bp >= 0 else "negative", "symbol": str(mover.get("symbol", "")),
			"headline": "%s %s %s%%" % [str(mover.get("symbol", "")), direction, _absolute_percent(change_bp)],
			"body": "%s closed at %s in the fictional weekly market." % [str(mover.get("name", "")), format_price(int(mover.get("price_cents", 0)))],
			"week_index": week_index,
		})
	return news


func _largest_mover(movers: Array[Dictionary], class_filter: String = "") -> Dictionary:
	var result: Dictionary = {}
	for mover in movers:
		if not class_filter.is_empty() and str(mover.get("asset_class", "")) != class_filter:
			continue
		if result.is_empty() or absi(int(mover.get("change_basis_points", 0))) > absi(int(result.get("change_basis_points", 0))):
			result = mover
	return result


func _sanitized_holding(raw: Variant) -> Dictionary:
	var holding: Dictionary = raw.duplicate(true) if raw is Dictionary else {}
	var clean_lots: Array = []
	var total_quantity := 0
	var raw_lots: Variant = holding.get("lots", [])
	if raw_lots is Array:
		for raw_lot in raw_lots:
			if not raw_lot is Dictionary:
				continue
			var quantity := maxi(0, int(raw_lot.get("quantity_units", 0)))
			if quantity <= 0:
				continue
			var lot: Dictionary = raw_lot.duplicate(true)
			lot["quantity_units"] = quantity
			lot["total_cost_cents"] = maxi(0, int(lot.get("total_cost_cents", 0)))
			clean_lots.append(lot)
			total_quantity += quantity
	holding["lots"] = clean_lots
	holding["quantity_units"] = total_quantity
	holding["realized_pnl_cents"] = int(holding.get("realized_pnl_cents", 0))
	holding["distributions_cents"] = maxi(0, int(holding.get("distributions_cents", 0)))
	return holding


func _preview_fifo_cost_basis(holding: Dictionary, quantity_units: int) -> int:
	var remaining := maxi(0, quantity_units)
	var basis := 0
	var raw_lots: Variant = holding.get("lots", [])
	if not raw_lots is Array:
		return basis
	for raw_lot in raw_lots:
		if remaining <= 0:
			break
		if not raw_lot is Dictionary:
			continue
		var lot_quantity := maxi(0, int(raw_lot.get("quantity_units", 0)))
		var take := mini(remaining, lot_quantity)
		basis += _multiply_divide_rounded(int(raw_lot.get("total_cost_cents", 0)), take, maxi(1, lot_quantity))
		remaining -= take
	return basis


func _consume_fifo_lots(holding: Dictionary, quantity_units: int) -> Dictionary:
	var remaining := maxi(0, quantity_units)
	var basis := 0
	var updated_lots: Array = []
	var raw_lots: Variant = holding.get("lots", [])
	if raw_lots is Array:
		for raw_lot in raw_lots:
			if not raw_lot is Dictionary:
				continue
			var lot: Dictionary = raw_lot.duplicate(true)
			var lot_quantity := maxi(0, int(lot.get("quantity_units", 0)))
			var lot_cost := maxi(0, int(lot.get("total_cost_cents", 0)))
			if remaining > 0 and lot_quantity > 0:
				var take := mini(remaining, lot_quantity)
				var allocated := _multiply_divide_rounded(lot_cost, take, lot_quantity)
				basis += allocated
				lot_quantity -= take
				lot_cost -= allocated
				remaining -= take
			lot["quantity_units"] = lot_quantity
			lot["total_cost_cents"] = lot_cost
			if lot_quantity > 0:
				updated_lots.append(lot)
	holding["lots"] = updated_lots
	holding["quantity_units"] = maxi(0, int(holding.get("quantity_units", 0)) - quantity_units)
	return {"holding": holding, "cost_basis_cents": basis}


func _holding_cost_basis_cents(holding: Dictionary) -> int:
	var result := 0
	var raw_lots: Variant = holding.get("lots", [])
	if raw_lots is Array:
		for lot in raw_lots:
			if lot is Dictionary:
				result += maxi(0, int(lot.get("total_cost_cents", 0)))
	return result


func _average_unit_cost_cents(definition: Dictionary, holding: Dictionary) -> int:
	var quantity := maxi(0, int(holding.get("quantity_units", 0)))
	if quantity <= 0:
		return 0
	return _multiply_divide_rounded(_holding_cost_basis_cents(holding), maxi(1, int(definition.get("unit_scale", 1))), quantity)


func _holding_market_value_cents(definition: Dictionary, holding: Dictionary, price_cents: int) -> int:
	return _notional_cents(price_cents, maxi(0, int(holding.get("quantity_units", 0))), maxi(1, int(definition.get("unit_scale", 1))))


func _price_history_from_market(market: Dictionary, symbol: String) -> Array[int]:
	var result: Array[int] = []
	var histories: Dictionary = market.get("price_history_cents", {}) if market.get("price_history_cents", {}) is Dictionary else {}
	var raw: Variant = histories.get(symbol, [])
	if raw is Array:
		for value in raw:
			result.append(maxi(1, int(value)))
	return result


func _increment_order_count(market: Dictionary, week_index: int) -> void:
	var orders: Dictionary = market.get("weekly_orders", {}) if market.get("weekly_orders", {}) is Dictionary else {}
	if int(orders.get("week_index", -1)) != week_index:
		orders = {"week_index": week_index, "count": 0}
	orders["count"] = int(orders.get("count", 0)) + 1
	market["weekly_orders"] = orders


func _append_transaction(market: Dictionary, transaction: Dictionary) -> void:
	var transactions: Array = market.get("transactions", []) if market.get("transactions", []) is Array else []
	transactions.append(transaction.duplicate(true))
	while transactions.size() > MAX_TRANSACTIONS:
		transactions.pop_front()
	market["transactions"] = transactions


func _trade_fee_cents(notional_cents: int, asset_class: String) -> int:
	if notional_cents <= 0:
		return 0
	var bps_key := "equity_fee_basis_points"
	var minimum_key := "equity_minimum_fee_cents"
	if asset_class == "crypto":
		bps_key = "crypto_fee_basis_points"
		minimum_key = "crypto_minimum_fee_cents"
	elif asset_class == "bond":
		bps_key = "bond_fee_basis_points"
		minimum_key = "bond_minimum_fee_cents"
	var variable_fee := _ceil_div(notional_cents * maxi(0, int(_settings.get(bps_key, 0))), 10000)
	return maxi(maxi(0, int(_settings.get(minimum_key, 0))), variable_fee)


func _notional_cents(price_cents: int, quantity_units: int, unit_scale: int) -> int:
	if price_cents <= 0 or quantity_units <= 0:
		return 0
	var scale := maxi(1, unit_scale)
	# Split before multiplication so high-precision coin quantities do not
	# overflow when multiplied by a quote such as Bitcoin's price in cents.
	return maxi(1, (quantity_units / scale) * price_cents + _rounded_ratio(price_cents * (quantity_units % scale), scale))


func _apply_basis_points(value: int, basis_points: int) -> int:
	return maxi(1, _rounded_ratio(value * (10000 + basis_points), 10000))


func _change_basis_points(old_value: int, new_value: int) -> int:
	if old_value <= 0:
		return 0
	return _rounded_ratio((new_value - old_value) * 10000, old_value)


func _percent_basis_points(part: int, total: int) -> int:
	if total <= 0:
		return 0
	return _rounded_ratio(part * 10000, total)


func _rounded_ratio(numerator: int, denominator: int) -> int:
	if denominator <= 0:
		return 0
	if numerator < 0:
		return -_rounded_ratio(-numerator, denominator)
	return (numerator + denominator / 2) / denominator


## Exact nonnegative (a * b) / denominator without an overflowing intermediate.
## Useful for tax lots: high-precision quantities can exceed a trillion units.
func _multiply_divide_rounded(a: int, b: int, denominator: int) -> int:
	if a <= 0 or b <= 0 or denominator <= 0: return 0
	var quotient := 0
	var remainder := 0
	var term_whole := a / denominator
	var term_remainder := a % denominator
	var multiplier := b
	while multiplier > 0:
		if multiplier % 2 == 1:
			quotient += term_whole
			remainder += term_remainder
			quotient += remainder / denominator
			remainder %= denominator
		multiplier /= 2
		if multiplier > 0:
			term_whole *= 2
			term_remainder *= 2
			term_whole += term_remainder / denominator
			term_remainder %= denominator
	return quotient + (1 if remainder >= (denominator + 1) / 2 else 0)


func _ceil_div(numerator: int, denominator: int) -> int:
	if numerator <= 0 or denominator <= 0:
		return 0
	return (numerator + denominator - 1) / denominator


func _absolute_percent(basis_points: int) -> String:
	return "%.2f" % (float(absi(basis_points)) / 100.0)


func _signed_money(cents: int) -> String:
	return ("+" if cents >= 0 else "-") + format_price(absi(cents))


func _commas(value: int) -> String:
	var raw := str(absi(value))
	var result := ""
	while raw.length() > 3:
		result = "," + raw.right(3) + result
		raw = raw.left(raw.length() - 3)
	return raw + result


func _join_strings(values: Array) -> String:
	var parts := PackedStringArray()
	for value in values:
		var text := str(value).strip_edges()
		if not text.is_empty():
			parts.append(text)
	return " ".join(parts)


func _date_key(calendar: Dictionary) -> String:
	return "%04d-%02d-%02d" % [int(calendar.get("year", 2026)), int(calendar.get("month", 1)), int(calendar.get("day", 1))]


func _load_content() -> void:
	load_errors.clear()
	_settings.clear()
	_classes.clear()
	_instruments.clear()
	_by_id.clear()
	_by_symbol.clear()
	_macro_headlines.clear()
	if not FileAccess.file_exists(DATA_PATH):
		load_errors.append("Market content is missing: %s" % DATA_PATH)
		push_error(load_errors[-1])
		return
	var file := FileAccess.open(DATA_PATH, FileAccess.READ)
	if file == null:
		load_errors.append("Market content could not be opened: %s" % DATA_PATH)
		push_error(load_errors[-1])
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		load_errors.append("Market content must be a JSON object.")
		push_error(load_errors[-1])
		return
	_settings = parsed.get("settings", {}).duplicate(true) if parsed.get("settings", {}) is Dictionary else {}
	_macro_headlines = parsed.get("macro_headlines", {}).duplicate(true) if parsed.get("macro_headlines", {}) is Dictionary else {}
	var raw_classes: Variant = parsed.get("asset_classes", [])
	if raw_classes is Array:
		for raw_class in raw_classes:
			if raw_class is Dictionary and not str(raw_class.get("id", "")).strip_edges().is_empty():
				_classes.append(raw_class.duplicate(true))
	var class_ids: Array[String] = []
	for definition in _classes:
		class_ids.append(str(definition.get("id", "")))
	var raw_instruments: Variant = parsed.get("instruments", [])
	if not raw_instruments is Array:
		load_errors.append("Market content requires an instruments array.")
	else:
		for raw_instrument in raw_instruments:
			if not raw_instrument is Dictionary:
				continue
			var instrument: Dictionary = raw_instrument.duplicate(true)
			var asset_id := str(instrument.get("id", "")).strip_edges()
			var symbol := str(instrument.get("symbol", "")).strip_edges().to_upper()
			var asset_class := str(instrument.get("asset_class", "")).strip_edges()
			if asset_id.is_empty() or symbol.is_empty() or _by_id.has(asset_id) or _by_symbol.has(symbol):
				load_errors.append("Market instrument has a missing or duplicate ID/symbol: %s / %s" % [asset_id, symbol])
				continue
			if not class_ids.has(asset_class):
				load_errors.append("Market instrument %s uses unknown class %s." % [symbol, asset_class])
				continue
			if int(instrument.get("initial_price_cents", 0)) <= 0 or int(instrument.get("unit_scale", 0)) <= 0:
				load_errors.append("Market instrument %s requires positive price cents and unit scale." % symbol)
				continue
			instrument["symbol"] = symbol
			_by_id[asset_id] = instrument
			_by_symbol[symbol] = instrument
			_instruments.append(instrument)
	for error_text in load_errors:
		push_error(error_text)
