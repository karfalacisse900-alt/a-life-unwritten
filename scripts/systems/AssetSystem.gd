class_name AssetSystem
extends RefCounted

## Data-driven possessions and investment portfolio. The complete runtime state is
## stored below state.flags[PORTFOLIO_FLAG], so existing versioned saves preserve
## it without coupling LifeGameState to this optional system.

const DATA_PATH := "res://data/assets.json"
const PORTFOLIO_FLAG := "assets"
const PORTFOLIO_VERSION := 1
const MAX_PRICE_HISTORY := 104
const MAX_TRANSACTION_HISTORY := 120

var _assets: Array[Dictionary] = []
var _categories: Array[Dictionary] = []
var _asset_by_id: Dictionary = {}
var _category_by_id: Dictionary = {}

var load_errors: Array[String] = []
var last_result: Dictionary = {}


func _init() -> void:
	_load_content()


func get_catalog(category_id: String = "") -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for asset in _assets:
		if category_id.is_empty() or str(asset.get("category_id", "")) == category_id:
			result.append(asset.duplicate(true))
	return result


func get_categories() -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for category in _categories:
		var copy := category.duplicate(true)
		copy["asset_count"] = get_catalog(str(category.get("id", ""))).size()
		result.append(copy)
	return result


func get_asset(asset_id: String) -> Dictionary:
	if not _asset_by_id.has(asset_id):
		return {}
	return (_asset_by_id[asset_id] as Dictionary).duplicate(true)


func get_category(category_id: String) -> Dictionary:
	if not _category_by_id.has(category_id):
		return {}
	return (_category_by_id[category_id] as Dictionary).duplicate(true)


func get_portfolio(state) -> Dictionary:
	return _ensure_portfolio(state).duplicate(true)


## Catalog entries enriched with live prices, ownership, and a purchase quote.
## This is the primary read API for an Assets shop or investment market screen.
func get_market_list(state, category_id: String = "") -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var portfolio := _ensure_portfolio(state)
	var holdings: Dictionary = portfolio.get("holdings", {})
	for definition in _assets:
		if not category_id.is_empty() and str(definition.get("category_id", "")) != category_id:
			continue
		var asset_id := str(definition.get("id", ""))
		var item := definition.duplicate(true)
		item["current_value"] = _current_unit_value(portfolio, definition)
		var holding: Dictionary = holdings.get(asset_id, {}) if holdings.get(asset_id, {}) is Dictionary else {}
		item["owned_quantity"] = maxi(0, int(holding.get("quantity", 0)))
		item["owned_market_value"] = _holding_market_value(definition, holding, portfolio)
		item["price_history"] = _price_history(portfolio, asset_id)
		item["purchase_quote"] = quote_buy(state, asset_id, 1)
		result.append(item)
	return result


## Owned entries combine immutable catalog metadata with the player's saved lot.
func get_owned(state, category_id: String = "") -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var portfolio := _ensure_portfolio(state)
	var holdings: Dictionary = portfolio.get("holdings", {})
	for definition in _assets:
		var asset_id := str(definition.get("id", ""))
		if not holdings.has(asset_id) or not holdings[asset_id] is Dictionary:
			continue
		if not category_id.is_empty() and str(definition.get("category_id", "")) != category_id:
			continue
		var holding: Dictionary = holdings[asset_id]
		if int(holding.get("quantity", 0)) <= 0:
			continue
		var item := definition.duplicate(true)
		var market_value := _holding_market_value(definition, holding, portfolio)
		var cost_basis := maxi(0, int(holding.get("cost_basis", 0)))
		item["quantity"] = int(holding.get("quantity", 0))
		item["current_value"] = _current_unit_value(portfolio, definition)
		item["market_value"] = market_value
		item["cost_basis"] = cost_basis
		item["unrealized_gain"] = market_value - cost_basis
		item["average_unit_cost"] = int(holding.get("average_unit_cost", 0))
		item["condition"] = clampi(int(holding.get("condition", 100)), 0, 100)
		item["acquired_week"] = int(holding.get("acquired_week", 0))
		item["income_earned"] = int(holding.get("income_earned", 0))
		item["upkeep_paid"] = int(holding.get("upkeep_paid", 0))
		item["realized_gain"] = int(holding.get("realized_gain", 0))
		item["price_history"] = _price_history(portfolio, asset_id)
		result.append(item)
	return result


func get_holdings(state, category_id: String = "") -> Array[Dictionary]:
	return get_owned(state, category_id)


func quote_buy(state, asset_id: String, quantity: int = 1) -> Dictionary:
	var definition := get_asset(asset_id)
	if definition.is_empty() or quantity <= 0:
		return {"valid": false, "asset_id": asset_id, "quantity": quantity, "subtotal": 0, "fee": 0, "total": 0}
	var portfolio := _ensure_portfolio(state)
	var unit_value := _current_unit_value(portfolio, definition)
	var subtotal := unit_value * quantity
	var fee := _basis_point_charge(subtotal, int(definition.get("buy_fee_basis_points", 0)))
	return {
		"valid": true,
		"asset_id": asset_id,
		"quantity": quantity,
		"unit_value": unit_value,
		"subtotal": subtotal,
		"fee": fee,
		"total": subtotal + fee,
		"action_hours": maxi(0, int(definition.get("action_hours", 1))),
		"cash_after": int(state.cash) - subtotal - fee,
	}


func can_buy(state, asset_id: String, quantity: int = 1) -> Dictionary:
	var reasons: Array[String] = []
	var definition := get_asset(asset_id)
	var quote := quote_buy(state, asset_id, quantity)
	if definition.is_empty():
		reasons.append("That asset is no longer offered.")
		return {"eligible": false, "ok": false, "reasons": reasons, "reason": reasons[0], "quote": quote}
	if quantity <= 0:
		reasons.append("Choose at least one unit.")
	if not bool(definition.get("tradable", true)):
		reasons.append("This asset is not currently for sale.")

	var portfolio := _ensure_portfolio(state)
	var holdings: Dictionary = portfolio.get("holdings", {})
	var holding: Dictionary = holdings.get(asset_id, {}) if holdings.get(asset_id, {}) is Dictionary else {}
	var owned := maxi(0, int(holding.get("quantity", 0)))
	var maximum := maxi(1, int(definition.get("max_quantity", 1)))
	if quantity > 0 and owned + quantity > maximum:
		reasons.append("You can own at most %d unit%s of this asset." % [maximum, "" if maximum == 1 else "s"])

	var requirements: Dictionary = definition.get("requirements", {}) if definition.get("requirements", {}) is Dictionary else {}
	var minimum_reputation := int(requirements.get("min_reputation", -100))
	if int(state.reputation) < minimum_reputation:
		reasons.append("Requires reputation %d; yours is %d." % [minimum_reputation, int(state.reputation)])
	var required_skills: Dictionary = requirements.get("min_skill", {}) if requirements.get("min_skill", {}) is Dictionary else {}
	for raw_skill_id in required_skills:
		var skill_id := str(raw_skill_id)
		var required_level := int(required_skills[raw_skill_id])
		var current_level := int(state.skills.get(skill_id, 0))
		if current_level < required_level:
			reasons.append("Requires %s %d; yours is %d." % [_title_case(skill_id), required_level, current_level])
	var required_education: Array = requirements.get("education", []) if requirements.get("education", []) is Array else []
	for raw_qualification in required_education:
		var qualification := str(raw_qualification)
		if not state.education.has(qualification):
			reasons.append("Requires %s." % _title_case(qualification))

	var total := int(quote.get("total", 0))
	var reserve := maxi(0, int(requirements.get("min_cash_after_purchase", 0)))
	if int(state.cash) < total:
		reasons.append("Costs $%s including fees; you have $%s." % [_money(total), _money(int(state.cash))])
	elif int(state.cash) - total < reserve:
		reasons.append("This purchase requires $%s left as a cash reserve." % _money(reserve))
	var action_hours := int(quote.get("action_hours", 0))
	if int(state.weekly_time) < action_hours:
		reasons.append("Buying this needs %d free hour%s this week." % [action_hours, "" if action_hours == 1 else "s"])
	if _is_jailed(state) and not _available_in_jail(definition):
		reasons.append("You cannot arrange this purchase while jailed.")

	return {
		"eligible": reasons.is_empty(),
		"ok": reasons.is_empty(),
		"reasons": reasons,
		"reason": _join_strings(reasons),
		"quote": quote,
		"owned_quantity": owned,
		"maximum_quantity": maximum,
	}


func buy(state, asset_id: String, quantity: int, economy) -> String:
	if economy == null or not economy.has_method("record"):
		last_result = {"ok": false, "reason": "The accounting service is unavailable."}
		return str(last_result["reason"])
	var details := can_buy(state, asset_id, quantity)
	if not bool(details.get("eligible", false)):
		last_result = {"ok": false, "reason": str(details.get("reason", "This purchase is unavailable.")), "details": details}
		return "You cannot buy that: %s" % str(last_result["reason"])
	var definition := get_asset(asset_id)
	var quote: Dictionary = details.get("quote", {})
	var hours := int(quote.get("action_hours", 0))
	if hours > 0 and not _spend_time(state, hours, "Buy %s" % str(definition.get("name", "an asset"))):
		last_result = {"ok": false, "reason": "There is not enough free time left this week."}
		return str(last_result["reason"])

	var total := int(quote.get("total", 0))
	economy.record(state, -total, "Bought %s × %d" % [str(definition.get("name", asset_id)), quantity], "asset_purchase")
	var portfolio := _ensure_portfolio(state)
	var holdings: Dictionary = portfolio.get("holdings", {})
	var holding := _sanitized_holding(asset_id, holdings.get(asset_id, {}))
	var old_quantity := int(holding.get("quantity", 0))
	holding["quantity"] = old_quantity + quantity
	holding["cost_basis"] = int(holding.get("cost_basis", 0)) + total
	holding["average_unit_cost"] = roundi(float(int(holding["cost_basis"])) / float(maxi(1, int(holding["quantity"]))))
	if old_quantity <= 0:
		holding["acquired_week"] = int(state.calendar.get("week_index", 0))
		holding["condition"] = 100
	holding["last_transaction_week"] = int(state.calendar.get("week_index", 0))
	holdings[asset_id] = holding
	portfolio["holdings"] = holdings
	portfolio["cash_invested"] = int(portfolio.get("cash_invested", 0)) + total
	_append_transaction(portfolio, {
		"week_index": int(state.calendar.get("week_index", 0)),
		"action": "buy",
		"asset_id": asset_id,
		"quantity": quantity,
		"unit_value": int(quote.get("unit_value", 0)),
		"fee": int(quote.get("fee", 0)),
		"cash_total": -total,
	})
	state.flags[PORTFOLIO_FLAG] = portfolio
	_sync_owned_property(state, definition, true)
	state.add_history("Bought %s%s." % [str(definition.get("name", asset_id)), " × %d" % quantity if quantity > 1 else ""])
	last_result = {"ok": true, "action": "buy", "asset_id": asset_id, "quantity": quantity, "cash_total": -total, "quote": quote}
	return "Bought %s%s for $%s including $%s in fees." % [str(definition.get("name", asset_id)), " × %d" % quantity if quantity > 1 else "", _money(total), _money(int(quote.get("fee", 0)))]


func quote_sell(state, asset_id: String, quantity: int = 1) -> Dictionary:
	var definition := get_asset(asset_id)
	if definition.is_empty() or quantity <= 0:
		return {"valid": false, "asset_id": asset_id, "quantity": quantity, "gross": 0, "fee": 0, "proceeds": 0}
	var portfolio := _ensure_portfolio(state)
	var holdings: Dictionary = portfolio.get("holdings", {})
	var holding: Dictionary = holdings.get(asset_id, {}) if holdings.get(asset_id, {}) is Dictionary else {}
	var owned := maxi(0, int(holding.get("quantity", 0)))
	var unit_value := _condition_adjusted_unit_value(definition, holding, portfolio)
	var gross := unit_value * mini(quantity, owned)
	var fee := _basis_point_charge(gross, int(definition.get("sell_fee_basis_points", 0)))
	var allocated_basis := roundi(float(int(holding.get("cost_basis", 0))) * float(mini(quantity, owned)) / float(maxi(1, owned)))
	return {
		"valid": owned > 0 and quantity <= owned,
		"asset_id": asset_id,
		"quantity": quantity,
		"owned_quantity": owned,
		"unit_value": unit_value,
		"gross": gross,
		"fee": fee,
		"proceeds": maxi(0, gross - fee),
		"allocated_cost_basis": allocated_basis,
		"estimated_gain": maxi(0, gross - fee) - allocated_basis,
		"action_hours": maxi(0, int(definition.get("sell_action_hours", definition.get("action_hours", 1)))),
		"condition": clampi(int(holding.get("condition", 100)), 0, 100),
	}


func can_sell(state, asset_id: String, quantity: int = 1) -> Dictionary:
	var reasons: Array[String] = []
	var definition := get_asset(asset_id)
	var quote := quote_sell(state, asset_id, quantity)
	if definition.is_empty():
		reasons.append("That asset is no longer recognized.")
		return {"eligible": false, "ok": false, "reasons": reasons, "reason": reasons[0], "quote": quote}
	var owned := int(quote.get("owned_quantity", 0))
	if quantity <= 0:
		reasons.append("Choose at least one unit.")
	elif owned <= 0:
		reasons.append("You do not own this asset.")
	elif quantity > owned:
		reasons.append("You own only %d unit%s." % [owned, "" if owned == 1 else "s"])
	var hours := int(quote.get("action_hours", 0))
	if int(state.weekly_time) < hours:
		reasons.append("Selling this needs %d free hour%s this week." % [hours, "" if hours == 1 else "s"])
	if _is_jailed(state) and not _available_in_jail(definition):
		reasons.append("You cannot arrange this sale while jailed.")
	return {"eligible": reasons.is_empty(), "ok": reasons.is_empty(), "reasons": reasons, "reason": _join_strings(reasons), "quote": quote}


func sell(state, asset_id: String, quantity: int, economy) -> String:
	if economy == null or not economy.has_method("record"):
		last_result = {"ok": false, "reason": "The accounting service is unavailable."}
		return str(last_result["reason"])
	var details := can_sell(state, asset_id, quantity)
	if not bool(details.get("eligible", false)):
		last_result = {"ok": false, "reason": str(details.get("reason", "This sale is unavailable.")), "details": details}
		return "You cannot sell that: %s" % str(last_result["reason"])
	var definition := get_asset(asset_id)
	var quote: Dictionary = details.get("quote", {})
	var hours := int(quote.get("action_hours", 0))
	if hours > 0 and not _spend_time(state, hours, "Sell %s" % str(definition.get("name", "an asset"))):
		last_result = {"ok": false, "reason": "There is not enough free time left this week."}
		return str(last_result["reason"])

	var proceeds := int(quote.get("proceeds", 0))
	economy.record(state, proceeds, "Sold %s × %d" % [str(definition.get("name", asset_id)), quantity], "asset_sale")
	var portfolio := _ensure_portfolio(state)
	var holdings: Dictionary = portfolio.get("holdings", {})
	var holding := _sanitized_holding(asset_id, holdings.get(asset_id, {}))
	var allocated_basis := int(quote.get("allocated_cost_basis", 0))
	var realized_gain := proceeds - allocated_basis
	holding["quantity"] = maxi(0, int(holding.get("quantity", 0)) - quantity)
	holding["cost_basis"] = maxi(0, int(holding.get("cost_basis", 0)) - allocated_basis)
	holding["realized_gain"] = int(holding.get("realized_gain", 0)) + realized_gain
	holding["last_transaction_week"] = int(state.calendar.get("week_index", 0))
	if int(holding["quantity"]) <= 0:
		holdings.erase(asset_id)
	else:
		holding["average_unit_cost"] = roundi(float(int(holding["cost_basis"])) / float(int(holding["quantity"])))
		holdings[asset_id] = holding
	portfolio["holdings"] = holdings
	portfolio["realized_gain"] = int(portfolio.get("realized_gain", 0)) + realized_gain
	portfolio["cash_recovered"] = int(portfolio.get("cash_recovered", 0)) + proceeds
	var realized_by_asset: Dictionary = portfolio.get("realized_by_asset", {})
	realized_by_asset[asset_id] = int(realized_by_asset.get(asset_id, 0)) + realized_gain
	portfolio["realized_by_asset"] = realized_by_asset
	_append_transaction(portfolio, {
		"week_index": int(state.calendar.get("week_index", 0)),
		"action": "sell",
		"asset_id": asset_id,
		"quantity": quantity,
		"unit_value": int(quote.get("unit_value", 0)),
		"fee": int(quote.get("fee", 0)),
		"cash_total": proceeds,
		"realized_gain": realized_gain,
	})
	state.flags[PORTFOLIO_FLAG] = portfolio
	if not holdings.has(asset_id):
		_sync_owned_property(state, definition, false)
	state.add_history("Sold %s%s for $%s." % [str(definition.get("name", asset_id)), " × %d" % quantity if quantity > 1 else "", _money(proceeds)])
	last_result = {"ok": true, "action": "sell", "asset_id": asset_id, "quantity": quantity, "cash_total": proceeds, "realized_gain": realized_gain, "quote": quote}
	return "Sold %s%s for $%s after fees — a %s of $%s against cost." % [str(definition.get("name", asset_id)), " × %d" % quantity if quantity > 1 else "", _money(proceeds), "gain" if realized_gain >= 0 else "loss", _money(absi(realized_gain))]


func maintenance_details(state, asset_id: String) -> Dictionary:
	var reasons: Array[String] = []
	var definition := get_asset(asset_id)
	var portfolio := _ensure_portfolio(state)
	var holdings: Dictionary = portfolio.get("holdings", {})
	var holding: Dictionary = holdings.get(asset_id, {}) if holdings.get(asset_id, {}) is Dictionary else {}
	var condition := clampi(int(holding.get("condition", 100)), 0, 100)
	var cost := maxi(0, int(definition.get("maintenance_service_cost", 0)))
	var hours := 2
	if definition.is_empty() or int(holding.get("quantity", 0)) <= 0:
		reasons.append("You do not own this asset.")
	elif str(definition.get("category_id", "")) == "investment":
		reasons.append("Financial investments do not have physical maintenance.")
	elif condition >= 100:
		reasons.append("It is already in excellent condition.")
	if cost <= 0:
		reasons.append("No maintenance service is available for this item.")
	if int(state.cash) < cost:
		reasons.append("Maintenance costs $%s; you have $%s." % [_money(cost), _money(int(state.cash))])
	if int(state.weekly_time) < hours:
		reasons.append("Maintenance needs %d free hours this week." % hours)
	if _is_jailed(state):
		reasons.append("You cannot arrange maintenance while jailed.")
	return {"eligible": reasons.is_empty(), "ok": reasons.is_empty(), "reasons": reasons, "reason": _join_strings(reasons), "cost": cost, "hours": hours, "condition": condition, "restore": maxi(1, int(definition.get("maintenance_restore", 10)))}


func maintain(state, asset_id: String, economy) -> String:
	if economy == null or not economy.has_method("record"):
		last_result = {"ok": false, "reason": "The accounting service is unavailable."}
		return str(last_result["reason"])
	var details := maintenance_details(state, asset_id)
	if not bool(details.get("eligible", false)):
		last_result = {"ok": false, "reason": str(details.get("reason", "Maintenance is unavailable.")), "details": details}
		return "You cannot maintain that: %s" % str(last_result["reason"])
	var definition := get_asset(asset_id)
	if not _spend_time(state, int(details.get("hours", 2)), "Maintain %s" % str(definition.get("name", asset_id))):
		last_result = {"ok": false, "reason": "There is not enough free time left this week."}
		return str(last_result["reason"])
	var cost := int(details.get("cost", 0))
	economy.record(state, -cost, "%s maintenance service" % str(definition.get("name", asset_id)), "asset_maintenance")
	var portfolio := _ensure_portfolio(state)
	var holdings: Dictionary = portfolio.get("holdings", {})
	var holding := _sanitized_holding(asset_id, holdings.get(asset_id, {}))
	var before := clampi(int(holding.get("condition", 100)), 0, 100)
	holding["condition"] = mini(100, before + int(details.get("restore", 10)))
	holding["upkeep_paid"] = int(holding.get("upkeep_paid", 0)) + cost
	holdings[asset_id] = holding
	portfolio["holdings"] = holdings
	portfolio["upkeep_paid"] = int(portfolio.get("upkeep_paid", 0)) + cost
	state.flags[PORTFOLIO_FLAG] = portfolio
	last_result = {"ok": true, "action": "maintain", "asset_id": asset_id, "cost": cost, "condition_before": before, "condition_after": int(holding["condition"])}
	return "%s condition improved from %d%% to %d%% for $%s." % [str(definition.get("name", asset_id)), before, int(holding["condition"]), _money(cost)]


## Called once after CalendarSystem advances. Prices are updated for every catalog
## asset in stable-ID order, whether or not the player owns it; player trades can
## therefore never cause favorable price movement.
func process_week(state, economy) -> Array[String]:
	var summary: Array[String] = []
	var portfolio := _ensure_portfolio(state)
	var week_index := int(state.calendar.get("week_index", 0))
	if week_index <= int(portfolio.get("last_processed_week", 0)):
		return summary
	portfolio["last_processed_week"] = week_index

	var largest_move := _update_all_values(state, portfolio)
	_process_condition_wear(portfolio)
	if _crossed_month_boundary(state):
		_process_monthly_income(state, economy, portfolio, summary)
		_process_monthly_upkeep(state, economy, portfolio, summary)
		_apply_monthly_benefits(state, portfolio, summary)

	if not largest_move.is_empty() and absf(float(largest_move.get("percent", 0.0))) >= 0.5:
		var direction := "rose" if float(largest_move.get("percent", 0.0)) >= 0.0 else "fell"
		summary.append("Asset market: %s %s %.1f%% to $%s." % [str(largest_move.get("name", "An asset")), direction, absf(float(largest_move.get("percent", 0.0))), _money(int(largest_move.get("new_value", 0)))])

	state.flags[PORTFOLIO_FLAG] = portfolio
	state.state_changed.emit()
	return summary


func total_value(state) -> int:
	var portfolio := _ensure_portfolio(state)
	var total := 0
	var holdings: Dictionary = portfolio.get("holdings", {})
	for definition in _assets:
		var asset_id := str(definition.get("id", ""))
		if holdings.has(asset_id) and holdings[asset_id] is Dictionary:
			total += _holding_market_value(definition, holdings[asset_id], portfolio)
	return total


func category_value(state, category_id: String) -> int:
	var portfolio := _ensure_portfolio(state)
	var total := 0
	var holdings: Dictionary = portfolio.get("holdings", {})
	for definition in _assets:
		if str(definition.get("category_id", "")) != category_id:
			continue
		var asset_id := str(definition.get("id", ""))
		if holdings.has(asset_id) and holdings[asset_id] is Dictionary:
			total += _holding_market_value(definition, holdings[asset_id], portfolio)
	return total


func net_worth(state) -> int:
	return int(state.cash) + int(state.savings) + total_value(state) - int(state.debt)


func get_breakdown(state) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for category in _categories:
		var category_id := str(category.get("id", ""))
		var owned := get_owned(state, category_id)
		result.append({
			"id": category_id,
			"name": str(category.get("name", category_id)),
			"accent": str(category.get("accent", "#777777")),
			"value": category_value(state, category_id),
			"holding_count": owned.size(),
		})
	return result


func get_access_tags(state) -> Array[String]:
	var result: Array[String] = []
	for item in get_owned(state):
		var benefits: Dictionary = item.get("benefits", {}) if item.get("benefits", {}) is Dictionary else {}
		var tags: Array = benefits.get("access_tags", []) if benefits.get("access_tags", []) is Array else []
		for raw_tag in tags:
			var tag := str(raw_tag)
			if not tag.is_empty() and not result.has(tag):
				result.append(tag)
	result.sort()
	return result


func upcoming_costs(state) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var days_until := _days_until_next_month(state.calendar)
	for item in get_owned(state):
		var amount := maxi(0, int(item.get("monthly_upkeep", 0))) * maxi(1, int(item.get("quantity", 1)))
		if amount <= 0:
			continue
		result.append({
			"id": "asset_upkeep_%s" % str(item.get("id", "")),
			"asset_id": str(item.get("id", "")),
			"name": "%s upkeep" % str(item.get("name", "Asset")),
			"amount": amount,
			"due_in_days": days_until,
			"due_in": "next week" if days_until <= 7 else "in %d days" % days_until,
		})
	return result


func _ensure_portfolio(state) -> Dictionary:
	var raw: Variant = state.flags.get(PORTFOLIO_FLAG, {})
	var portfolio: Dictionary = raw.duplicate(true) if raw is Dictionary else {}
	portfolio["version"] = PORTFOLIO_VERSION
	if not portfolio.has("holdings") or not (portfolio.get("holdings") is Dictionary):
		portfolio["holdings"] = {}
	if not portfolio.has("prices") or not (portfolio.get("prices") is Dictionary):
		portfolio["prices"] = {}
	if not portfolio.has("price_history") or not (portfolio.get("price_history") is Dictionary):
		portfolio["price_history"] = {}
	if not portfolio.has("transactions") or not (portfolio.get("transactions") is Array):
		portfolio["transactions"] = []
	if not portfolio.has("realized_by_asset") or not (portfolio.get("realized_by_asset") is Dictionary):
		portfolio["realized_by_asset"] = {}
	for key in ["realized_gain", "cash_invested", "cash_recovered", "income_earned", "upkeep_paid"]:
		portfolio[key] = int(portfolio.get(key, 0))
	if not portfolio.has("last_processed_week"):
		portfolio["last_processed_week"] = maxi(0, int(state.calendar.get("week_index", 0)) - 1)
	else:
		portfolio["last_processed_week"] = maxi(0, int(portfolio.get("last_processed_week", 0)))

	var prices: Dictionary = portfolio["prices"]
	var histories: Dictionary = portfolio["price_history"]
	for definition in _assets:
		var asset_id := str(definition.get("id", ""))
		var initial_value := maxi(1, int(definition.get("initial_value", 1)))
		prices[asset_id] = maxi(1, int(prices.get(asset_id, initial_value)))
		var history: Array = histories.get(asset_id, []) if histories.get(asset_id, []) is Array else []
		if history.is_empty():
			history.append(int(prices[asset_id]))
		histories[asset_id] = history
	portfolio["prices"] = prices
	portfolio["price_history"] = histories

	var holdings: Dictionary = portfolio["holdings"]
	for raw_asset_id in holdings.keys():
		var asset_id := str(raw_asset_id)
		var holding: Dictionary = _sanitized_holding(asset_id, holdings[raw_asset_id])
		if int(holding.get("quantity", 0)) <= 0:
			holdings.erase(raw_asset_id)
		else:
			holdings[raw_asset_id] = holding
	portfolio["holdings"] = holdings
	state.flags[PORTFOLIO_FLAG] = portfolio
	return portfolio


func _sanitized_holding(asset_id: String, raw: Variant) -> Dictionary:
	var holding: Dictionary = raw.duplicate(true) if raw is Dictionary else {}
	holding["asset_id"] = asset_id
	holding["quantity"] = maxi(0, int(holding.get("quantity", 0)))
	holding["cost_basis"] = maxi(0, int(holding.get("cost_basis", 0)))
	holding["average_unit_cost"] = maxi(0, int(holding.get("average_unit_cost", 0)))
	holding["condition"] = clampi(int(holding.get("condition", 100)), 0, 100)
	holding["wear_remainder_basis_points"] = maxi(0, int(holding.get("wear_remainder_basis_points", 0)))
	for key in ["acquired_week", "last_transaction_week", "income_earned", "upkeep_paid", "realized_gain"]:
		holding[key] = int(holding.get(key, 0))
	return holding


func _update_all_values(state, portfolio: Dictionary) -> Dictionary:
	var largest_move: Dictionary = {}
	var prices: Dictionary = portfolio.get("prices", {})
	var histories: Dictionary = portfolio.get("price_history", {})
	var asset_ids: Array = _asset_by_id.keys()
	asset_ids.sort()
	for raw_asset_id in asset_ids:
		var asset_id := str(raw_asset_id)
		var definition: Dictionary = _asset_by_id[asset_id]
		var old_value := maxi(1, int(prices.get(asset_id, definition.get("initial_value", 1))))
		var drift := int(definition.get("weekly_drift_basis_points", 0))
		var volatility := maxi(0, int(definition.get("weekly_volatility_basis_points", 0)))
		# Randomness is consumed once per stable asset ID. Holdings and trades never
		# enter this equation, which keeps market outcomes exogenous to the player.
		var random_component := roundi((state.randf_seeded() * 2.0 - 1.0) * float(volatility))
		var change_basis_points := drift + random_component
		var calculated := roundi(float(old_value) * (1.0 + float(change_basis_points) / 10000.0))
		var minimum_value := maxi(1, roundi(float(int(definition.get("initial_value", 1))) * float(int(definition.get("minimum_value_percent", 10))) / 100.0))
		var new_value := maxi(minimum_value, calculated)
		var maximum_percent := int(definition.get("maximum_value_percent", 0))
		if maximum_percent > 0:
			new_value = mini(new_value, roundi(float(int(definition.get("initial_value", 1))) * float(maximum_percent) / 100.0))
		prices[asset_id] = new_value
		var history: Array = histories.get(asset_id, []) if histories.get(asset_id, []) is Array else []
		history.append(new_value)
		while history.size() > MAX_PRICE_HISTORY:
			history.pop_front()
		histories[asset_id] = history
		var percent := (float(new_value - old_value) / float(old_value)) * 100.0
		if largest_move.is_empty() or absf(percent) > absf(float(largest_move.get("percent", 0.0))):
			largest_move = {"asset_id": asset_id, "name": str(definition.get("name", asset_id)), "old_value": old_value, "new_value": new_value, "percent": percent}
	portfolio["prices"] = prices
	portfolio["price_history"] = histories
	return largest_move


func _process_condition_wear(portfolio: Dictionary) -> void:
	var holdings: Dictionary = portfolio.get("holdings", {})
	for raw_asset_id in holdings.keys():
		var asset_id := str(raw_asset_id)
		if not _asset_by_id.has(asset_id) or not holdings[raw_asset_id] is Dictionary:
			continue
		var definition: Dictionary = _asset_by_id[asset_id]
		var wear := maxi(0, int(definition.get("condition_wear_basis_points", 0)))
		if wear <= 0:
			continue
		var holding: Dictionary = holdings[raw_asset_id]
		var accumulated := int(holding.get("wear_remainder_basis_points", 0)) + wear
		var points_lost := int(accumulated / 100)
		holding["wear_remainder_basis_points"] = accumulated % 100
		if points_lost > 0:
			holding["condition"] = maxi(10, int(holding.get("condition", 100)) - points_lost)
		holdings[raw_asset_id] = holding
	portfolio["holdings"] = holdings


func _process_monthly_income(state, economy, portfolio: Dictionary, summary: Array[String]) -> void:
	if economy == null or not economy.has_method("record"):
		return
	var holdings: Dictionary = portfolio.get("holdings", {})
	for definition in _assets:
		var asset_id := str(definition.get("id", ""))
		if not holdings.has(asset_id) or not holdings[asset_id] is Dictionary:
			continue
		var holding: Dictionary = holdings[asset_id]
		var quantity := maxi(0, int(holding.get("quantity", 0)))
		var income := maxi(0, int(definition.get("monthly_income", 0))) * quantity
		if income <= 0:
			continue
		economy.record(state, income, "%s monthly income" % str(definition.get("name", asset_id)), "asset_income")
		holding["income_earned"] = int(holding.get("income_earned", 0)) + income
		holdings[asset_id] = holding
		portfolio["income_earned"] = int(portfolio.get("income_earned", 0)) + income
		summary.append("%s produced $%s in monthly income." % [str(definition.get("name", asset_id)), _money(income)])
	portfolio["holdings"] = holdings


func _process_monthly_upkeep(state, economy, portfolio: Dictionary, summary: Array[String]) -> void:
	if economy == null or not economy.has_method("record"):
		return
	var holdings: Dictionary = portfolio.get("holdings", {})
	for definition in _assets:
		var asset_id := str(definition.get("id", ""))
		if not holdings.has(asset_id) or not holdings[asset_id] is Dictionary:
			continue
		var holding: Dictionary = holdings[asset_id]
		var quantity := maxi(0, int(holding.get("quantity", 0)))
		var upkeep := maxi(0, int(definition.get("monthly_upkeep", 0))) * quantity
		if upkeep <= 0:
			continue
		var shortfall := _charge_with_credit(state, economy, upkeep, "%s monthly upkeep" % str(definition.get("name", asset_id)), "asset_upkeep")
		holding["upkeep_paid"] = int(holding.get("upkeep_paid", 0)) + upkeep
		if shortfall > 0:
			holding["condition"] = maxi(10, int(holding.get("condition", 100)) - 5)
			summary.append("%s upkeep cost $%s; $%s became debt and condition suffered." % [str(definition.get("name", asset_id)), _money(upkeep), _money(shortfall)])
		else:
			summary.append("Paid $%s upkeep for %s." % [_money(upkeep), str(definition.get("name", asset_id))])
		holdings[asset_id] = holding
		portfolio["upkeep_paid"] = int(portfolio.get("upkeep_paid", 0)) + upkeep
	portfolio["holdings"] = holdings


func _apply_monthly_benefits(state, portfolio: Dictionary, summary: Array[String]) -> void:
	var happiness_delta := 0
	var stress_delta := 0
	var health_delta := 0
	var reputation_delta := 0
	var holdings: Dictionary = portfolio.get("holdings", {})
	for definition in _assets:
		var asset_id := str(definition.get("id", ""))
		if not holdings.has(asset_id) or not holdings[asset_id] is Dictionary or int(holdings[asset_id].get("quantity", 0)) <= 0:
			continue
		var benefits: Dictionary = definition.get("benefits", {}) if definition.get("benefits", {}) is Dictionary else {}
		happiness_delta += int(benefits.get("monthly_happiness", 0))
		stress_delta += int(benefits.get("monthly_stress", 0))
		health_delta += int(benefits.get("monthly_health", 0))
		reputation_delta += int(benefits.get("monthly_reputation", 0))
	state.happiness = clampi(int(state.happiness) + happiness_delta, 0, 100)
	state.stress = clampi(int(state.stress) + stress_delta, 0, 100)
	state.health = clampi(int(state.health) + health_delta, 0, 100)
	state.reputation = clampi(int(state.reputation) + reputation_delta, -100, 100)
	if happiness_delta != 0 or stress_delta != 0 or health_delta != 0 or reputation_delta != 0:
		summary.append("Your possessions affected life this month: happiness %+d, stress %+d, health %+d, reputation %+d." % [happiness_delta, stress_delta, health_delta, reputation_delta])


func _charge_with_credit(state, economy, amount: int, reason: String, category: String) -> int:
	if amount <= 0:
		return 0
	economy.record(state, -amount, reason, category)
	var shortfall := maxi(0, -int(state.cash))
	if shortfall > 0:
		state.debt = int(state.debt) + shortfall
		economy.record(state, shortfall, "Emergency credit for %s" % reason, "debt_draw")
		state.stress = clampi(int(state.stress) + 3, 0, 100)
		state.reputation = clampi(int(state.reputation) - 1, -100, 100)
		state.flags["missed_obligations"] = int(state.flags.get("missed_obligations", 0)) + 1
	return shortfall


func _holding_market_value(definition: Dictionary, holding: Dictionary, portfolio: Dictionary) -> int:
	var quantity := maxi(0, int(holding.get("quantity", 0)))
	return _condition_adjusted_unit_value(definition, holding, portfolio) * quantity


func _condition_adjusted_unit_value(definition: Dictionary, holding: Dictionary, portfolio: Dictionary) -> int:
	var current_value := _current_unit_value(portfolio, definition)
	if str(definition.get("category_id", "")) == "investment":
		return current_value
	var condition := clampi(int(holding.get("condition", 100)), 0, 100)
	var floor_percent := clampi(int(definition.get("condition_value_floor_percent", 60)), 0, 100)
	var effective_percent := floor_percent + roundi(float(100 - floor_percent) * float(condition) / 100.0)
	return maxi(1, roundi(float(current_value) * float(effective_percent) / 100.0))


func _current_unit_value(portfolio: Dictionary, definition: Dictionary) -> int:
	var prices: Dictionary = portfolio.get("prices", {})
	return maxi(1, int(prices.get(str(definition.get("id", "")), definition.get("initial_value", 1))))


func _price_history(portfolio: Dictionary, asset_id: String) -> Array[int]:
	var result: Array[int] = []
	var histories: Dictionary = portfolio.get("price_history", {})
	var raw: Variant = histories.get(asset_id, [])
	if raw is Array:
		for value in raw:
			result.append(maxi(1, int(value)))
	return result


func _append_transaction(portfolio: Dictionary, entry: Dictionary) -> void:
	var transactions: Array = portfolio.get("transactions", [])
	transactions.append(entry.duplicate(true))
	while transactions.size() > MAX_TRANSACTION_HISTORY:
		transactions.pop_front()
	portfolio["transactions"] = transactions


func _sync_owned_property(state, definition: Dictionary, owned: bool) -> void:
	if str(definition.get("category_id", "")) != "property":
		return
	var asset_id := str(definition.get("id", ""))
	if owned and not state.owned_properties.has(asset_id):
		state.owned_properties.append(asset_id)
	elif not owned:
		state.owned_properties.erase(asset_id)


func _available_in_jail(definition: Dictionary) -> bool:
	return bool(definition.get("available_in_jail", str(definition.get("category_id", "")) == "investment"))


func _is_jailed(state) -> bool:
	return bool(state.crime.get("in_jail", state.crime.get("jailed", false))) or int(state.crime.get("jail_weeks", state.crime.get("jail_weeks_remaining", 0))) > 0


func _crossed_month_boundary(state) -> bool:
	var boundary: Variant = state.flags.get("last_calendar_boundary", {})
	var week_index := int(state.calendar.get("week_index", 0))
	if boundary is Dictionary and int(boundary.get("to_week_index", -1)) == week_index:
		var months: Variant = boundary.get("month_boundaries", [])
		return months is Array and not months.is_empty()
	# Imported/custom states may lack CalendarSystem's boundary metadata. Because a
	# turn is exactly seven days, landing in the first seven days crossed day one.
	return week_index > 0 and int(state.calendar.get("day", 8)) <= 7


func _days_until_next_month(calendar: Dictionary) -> int:
	var year := clampi(int(calendar.get("year", 2026)), 1900, 9999)
	var month := clampi(int(calendar.get("month", 1)), 1, 12)
	var day := clampi(int(calendar.get("day", 1)), 1, _days_in_month(year, month))
	return _days_in_month(year, month) - day + 1


func _days_in_month(year: int, month: int) -> int:
	match month:
		2:
			return 29 if year % 400 == 0 or (year % 4 == 0 and year % 100 != 0) else 28
		4, 6, 9, 11:
			return 30
		_:
			return 31


func _basis_point_charge(amount: int, basis_points: int) -> int:
	if amount <= 0 or basis_points <= 0:
		return 0
	return ceili(float(amount) * float(basis_points) / 10000.0)


func _spend_time(state, hours: int, reason: String) -> bool:
	if hours <= 0:
		return true
	if state.has_method("spend_time"):
		return bool(state.spend_time(hours, reason))
	if int(state.weekly_time) < hours:
		return false
	state.weekly_time = int(state.weekly_time) - hours
	return true


func _join_strings(values: Array) -> String:
	var parts := PackedStringArray()
	for value in values:
		parts.append(str(value))
	return " ".join(parts)


func _title_case(value: String) -> String:
	var words := value.replace("_", " ").split(" ", false)
	var result := PackedStringArray()
	for word in words:
		result.append(str(word).capitalize())
	return " ".join(result)


func _money(value: int) -> String:
	var raw := str(absi(value))
	var formatted := ""
	while raw.length() > 3:
		formatted = "," + raw.right(3) + formatted
		raw = raw.left(raw.length() - 3)
	formatted = raw + formatted
	return ("-" if value < 0 else "") + formatted


func _load_content() -> void:
	_assets.clear()
	_categories.clear()
	_asset_by_id.clear()
	_category_by_id.clear()
	load_errors.clear()
	if not FileAccess.file_exists(DATA_PATH):
		load_errors.append("Asset content is missing: %s" % DATA_PATH)
		push_error(load_errors[-1])
		return
	var file := FileAccess.open(DATA_PATH, FileAccess.READ)
	if file == null:
		load_errors.append("Asset content could not be opened: %s" % DATA_PATH)
		push_error(load_errors[-1])
		return
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		load_errors.append("Asset content must be a JSON object.")
		push_error(load_errors[-1])
		return
	var raw_categories: Variant = parsed.get("categories", [])
	if raw_categories is Array:
		for raw_category in raw_categories:
			if not raw_category is Dictionary:
				continue
			var category_id := str(raw_category.get("id", "")).strip_edges()
			if category_id.is_empty() or _category_by_id.has(category_id):
				load_errors.append("Asset category has a missing or duplicate ID: %s" % category_id)
				continue
			var category: Dictionary = raw_category.duplicate(true)
			_category_by_id[category_id] = category
			_categories.append(category)
	var raw_assets: Variant = parsed.get("assets", [])
	if not raw_assets is Array:
		load_errors.append("Asset content requires an assets array.")
	else:
		for raw_asset in raw_assets:
			if not raw_asset is Dictionary:
				continue
			var asset_id := str(raw_asset.get("id", "")).strip_edges()
			var category_id := str(raw_asset.get("category_id", "")).strip_edges()
			if asset_id.is_empty() or _asset_by_id.has(asset_id):
				load_errors.append("Asset has a missing or duplicate ID: %s" % asset_id)
				continue
			if not _category_by_id.has(category_id):
				load_errors.append("Asset %s uses unknown category %s." % [asset_id, category_id])
				continue
			if int(raw_asset.get("initial_value", 0)) <= 0 or int(raw_asset.get("max_quantity", 0)) <= 0:
				load_errors.append("Asset %s needs positive value and quantity limits." % asset_id)
				continue
			var asset: Dictionary = raw_asset.duplicate(true)
			_asset_by_id[asset_id] = asset
			_assets.append(asset)
	for error_text in load_errors:
		push_error(error_text)
