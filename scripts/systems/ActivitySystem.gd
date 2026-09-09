class_name ActivitySystem
extends RefCounted

## Optional occupation activities that sit beside education and employment.
## Every paid action uses EconomySystem.record, while delayed freelance reviews
## and marketplace demand are resolved exactly once during weekly processing.

const CONTENT_PATH := "res://data/activities.json"
const PROCESS_FLAG := "activity_system_processed_week"
const ACTION_WEEK_FLAG := "activity_action_week"
const ACTION_COUNTS_FLAG := "activity_action_counts"
const INVENTORY_FLAG := "market_inventory"
const SEQUENCE_FLAG := "activity_sequence"
const STATS_FLAG := "occupation_stats"

const GLOBAL_GIG_WEEKLY_LIMIT := 2
const GLOBAL_LISTING_WEEKLY_LIMIT := 3
const MAX_ACTIVE_GIGS := 3
const MAX_ACTIVE_LISTINGS := 6

var _hobbies: Array[Dictionary] = []
var _gigs: Array[Dictionary] = []
var _marketplace_items: Array[Dictionary] = []


func _init() -> void:
	_reload_content()


func load_content() -> Dictionary:
	if _hobbies.is_empty() and _gigs.is_empty() and _marketplace_items.is_empty():
		_reload_content()
	return {
		"hobbies": _duplicate_entries(_hobbies),
		"gigs": _duplicate_entries(_gigs),
		"marketplace_items": _duplicate_entries(_marketplace_items),
	}


func get_hobbies() -> Array[Dictionary]:
	return _duplicate_entries(_hobbies)


func get_gigs() -> Array[Dictionary]:
	return _duplicate_entries(_gigs)


func get_marketplace_items() -> Array[Dictionary]:
	return _duplicate_entries(_marketplace_items)


func get_activity(activity_id: String) -> Dictionary:
	for entry in _hobbies:
		if str(entry.get("id", "")) == activity_id:
			var result := entry.duplicate(true)
			result["kind"] = "hobby"
			return result
	for entry in _gigs:
		if str(entry.get("id", "")) == activity_id:
			var result := entry.duplicate(true)
			result["kind"] = "gig"
			return result
	for entry in _marketplace_items:
		if str(entry.get("id", "")) == activity_id:
			var result := entry.duplicate(true)
			result["kind"] = "marketplace_item"
			return result
	return {}


## Returns actionable reasons plus known time and cash costs. Freelance client
## approval and marketplace demand deliberately remain unresolved until next week.
func eligibility_details(state, activity_id: String) -> Dictionary:
	var definition := get_activity(activity_id)
	if definition.is_empty():
		return {
			"eligible": false,
			"reasons": ["That activity is no longer available."],
			"reason": "That activity is no longer available.",
			"time_hours": 0,
			"cash_cost": 0,
		}
	var kind := str(definition.get("kind", ""))
	var time_hours := int(definition.get("craft_time_hours", definition.get("time_hours", 0)))
	var cash_cost := int(definition.get("material_cost", definition.get("cash_cost", 0)))
	var reasons := _requirement_reasons(state, definition.get("requirements", {}))
	if int(state.weekly_time) < time_hours:
		reasons.append("Needs %d free hours this week; you have %d." % [time_hours, int(state.weekly_time)])
	if int(state.cash) < cash_cost:
		reasons.append("Costs $%s; you have $%s." % [_money(cash_cost), _money(int(state.cash))])

	var action_key := "%s:%s" % [kind, activity_id]
	var weekly_limit := maxi(1, int(definition.get("weekly_limit", 1)))
	var used := _action_count(state, action_key)
	if used >= weekly_limit:
		reasons.append("Weekly limit reached (%d)." % weekly_limit)
	if kind == "gig":
		if _action_count(state, "gig:any") >= GLOBAL_GIG_WEEKLY_LIMIT:
			reasons.append("You can submit at most %d freelance gigs per week." % GLOBAL_GIG_WEEKLY_LIMIT)
		if get_active_gigs(state).size() >= MAX_ACTIVE_GIGS:
			reasons.append("Finish a pending client review before taking another gig.")

	return {
		"eligible": reasons.is_empty(),
		"reasons": reasons,
		"reason": _join_strings(reasons),
		"kind": kind,
		"time_hours": time_hours,
		"cash_cost": cash_cost,
		"weekly_limit": weekly_limit,
		"used_this_week": used,
		"remaining_this_week": maxi(0, weekly_limit - used),
	}


func listing_details(state, item_id: String, quantity: int = 1) -> Dictionary:
	var definition := get_activity(item_id)
	var reasons: Array[String] = []
	if definition.is_empty() or str(definition.get("kind", "")) != "marketplace_item":
		reasons.append("That item cannot be listed.")
		return {"eligible": false, "reasons": reasons, "reason": _join_strings(reasons)}
	var safe_quantity := maxi(0, quantity)
	if safe_quantity <= 0:
		reasons.append("Choose at least one item to list.")
	var available := inventory_quantity(state, item_id)
	if safe_quantity > available:
		reasons.append("Only %d finished item(s) are available." % available)
	if _is_jailed(state):
		reasons.append("Marketplace listings cannot be prepared while jailed.")
	var hours := maxi(1, int(definition.get("listing_time_hours", 1)))
	if int(state.weekly_time) < hours:
		reasons.append("Listing needs %d free hour(s) this week." % hours)
	var fee := maxi(0, int(definition.get("listing_fee", 0))) * safe_quantity
	if int(state.cash) < fee:
		reasons.append("Listing fees are $%s; you have $%s." % [_money(fee), _money(int(state.cash))])
	if _action_count(state, "listing:any") >= GLOBAL_LISTING_WEEKLY_LIMIT:
		reasons.append("You can prepare at most %d marketplace listings per week." % GLOBAL_LISTING_WEEKLY_LIMIT)
	if get_active_listings(state).size() >= MAX_ACTIVE_LISTINGS:
		reasons.append("The marketplace account already has too many active listings.")
	return {
		"eligible": reasons.is_empty(),
		"reasons": reasons,
		"reason": _join_strings(reasons),
		"time_hours": hours,
		"listing_fee": fee,
		"quantity": safe_quantity,
		"available_quantity": available,
		"duration_weeks": int(definition.get("listing_duration_weeks", 3)),
	}


func perform_hobby(state, hobby_id: String, economy = null) -> String:
	var definition := get_activity(hobby_id)
	if str(definition.get("kind", "")) != "hobby":
		return "That is not an available hobby."
	var details := eligibility_details(state, hobby_id)
	if not bool(details.get("eligible", false)):
		return "You cannot do that now: %s" % str(details.get("reason", "Unavailable."))
	var hours := int(details.get("time_hours", 0))
	if not _spend_time(state, hours, "Practice %s" % str(definition.get("name", "hobby"))):
		return "There is not enough free time left for that hobby."
	var cost := int(details.get("cash_cost", 0))
	if cost > 0:
		_record_money(state, economy, -cost, "%s supplies" % str(definition.get("name", "Hobby")), "hobby_expense")
	_apply_effects(state, definition.get("effects", {}))
	_increment_action(state, "hobby:%s" % hobby_id)
	_increment_stat(state, "hobby_sessions", 1)
	state.add_history("Spent time on %s." % str(definition.get("name", "a hobby")))
	state.state_changed.emit()
	return "%s used %d hours%s and gave you a genuine break from the usual routine." % [
		str(definition.get("name", "The hobby")),
		hours,
		(" and $%s" % _money(cost)) if cost > 0 else "",
	]


## Submits completed freelance work. The client reviews it on the next weekly
## advance, so the displayed pay range is an opportunity rather than guaranteed income.
func accept_gig(state, gig_id: String) -> String:
	var definition := get_activity(gig_id)
	if str(definition.get("kind", "")) != "gig":
		return "That freelance brief is unavailable."
	var details := eligibility_details(state, gig_id)
	if not bool(details.get("eligible", false)):
		return "You cannot take that gig: %s" % str(details.get("reason", "Unavailable."))
	var hours := int(details.get("time_hours", 0))
	if not _spend_time(state, hours, "Complete %s" % str(definition.get("name", "freelance gig"))):
		return "There is not enough free time left to complete that brief."
	var pay_min := maxi(0, int(definition.get("pay_min", 0)))
	var pay_max := maxi(pay_min, int(definition.get("pay_max", pay_min)))
	var proposed_pay := pay_min + int(state.randi_seeded(pay_max - pay_min + 1))
	var sequence := _next_sequence(state)
	state.active_activities.append({
		"type": "freelance_gig",
		"id": "freelance_%d" % sequence,
		"activity_id": gig_id,
		"name": str(definition.get("name", "Freelance gig")),
		"client": str(definition.get("client", "Client")),
		"submitted_week": int(state.calendar.get("week_index", 0)),
		"due_week": int(state.calendar.get("week_index", 0)) + 1,
		"potential_pay": proposed_pay,
		"status": "client_review",
	})
	_apply_effects(state, definition.get("submission_effects", {}))
	_increment_action(state, "gig:%s" % gig_id)
	_increment_action(state, "gig:any")
	_increment_stat(state, "gigs_submitted", 1)
	state.add_history("Submitted %s to %s for review." % [str(definition.get("name", "freelance work")), str(definition.get("client", "a client"))])
	state.state_changed.emit()
	return "Work submitted after %d hours. %s will decide next week; the possible payment is $%s, but approval is not guaranteed." % [hours, str(definition.get("client", "The client")), _money(proposed_pay)]


func start_gig(state, gig_id: String) -> String:
	return accept_gig(state, gig_id)


func craft_item(state, item_id: String, economy = null) -> String:
	var definition := get_activity(item_id)
	if str(definition.get("kind", "")) != "marketplace_item":
		return "That marketplace recipe is unavailable."
	var details := eligibility_details(state, item_id)
	if not bool(details.get("eligible", false)):
		return "You cannot make that item: %s" % str(details.get("reason", "Unavailable."))
	var hours := int(details.get("time_hours", 0))
	if not _spend_time(state, hours, "Make %s" % str(definition.get("name", "marketplace item"))):
		return "There is not enough free time left to make that item."
	var material_cost := int(details.get("cash_cost", 0))
	if material_cost > 0:
		_record_money(state, economy, -material_cost, "%s materials" % str(definition.get("name", "Marketplace item")), "craft_materials")
	var quantity := maxi(1, int(definition.get("quantity_yield", 1)))
	_add_inventory(state, definition, quantity, material_cost)
	_apply_effects(state, definition.get("craft_effects", {}))
	_increment_action(state, "marketplace_item:%s" % item_id)
	_increment_stat(state, "items_crafted", quantity)
	state.add_history("Made %d × %s for the marketplace." % [quantity, str(definition.get("name", "an item"))])
	state.state_changed.emit()
	return "You made %d × %s in %d hours for $%s. They are now in your workshop inventory, not sold yet." % [quantity, str(definition.get("name", "item")), hours, _money(material_cost)]


func list_item(state, item_id: String, economy = null, quantity: int = 1) -> String:
	var definition := get_activity(item_id)
	var details := listing_details(state, item_id, quantity)
	if not bool(details.get("eligible", false)):
		return "You cannot list that item: %s" % str(details.get("reason", "Unavailable."))
	var hours := int(details.get("time_hours", 1))
	if not _spend_time(state, hours, "Photograph and list %s" % str(definition.get("name", "marketplace item"))):
		return "There is not enough free time left to prepare the listing."
	var reserved := _remove_inventory(state, item_id, quantity)
	if not bool(reserved.get("ok", false)):
		return "The finished inventory changed before the listing could be prepared."
	var fee := int(details.get("listing_fee", 0))
	if fee > 0:
		_record_money(state, economy, -fee, "%s marketplace listing fee" % str(definition.get("name", "Item")), "marketplace_fee")
	var sequence := _next_sequence(state)
	state.active_activities.append({
		"type": "market_listing",
		"id": "listing_%d" % sequence,
		"activity_id": item_id,
		"item_id": item_id,
		"name": str(definition.get("name", "Marketplace item")),
		"quantity": quantity,
		"cost_basis": int(reserved.get("cost_basis", 0)),
		"listing_fee": fee,
		"listed_week": int(state.calendar.get("week_index", 0)),
		"due_week": int(state.calendar.get("week_index", 0)) + 1,
		"weeks_listed": 0,
		"max_weeks": maxi(1, int(definition.get("listing_duration_weeks", 3))),
		"status": "listed",
	})
	_increment_action(state, "listing:any")
	_increment_stat(state, "listings_created", 1)
	state.state_changed.emit()
	return "%d × %s listed for %d week(s). Demand is uncertain; the market will respond after Next Week." % [quantity, str(definition.get("name", "item")), int(definition.get("listing_duration_weeks", 3))]


func cancel_listing(state, listing_id: String) -> String:
	var remaining: Array[Dictionary] = []
	var restored := false
	var restored_name := "item"
	for activity_value in state.active_activities:
		var activity: Dictionary = activity_value
		if not restored and str(activity.get("type", "")) == "market_listing" and str(activity.get("id", "")) == listing_id:
			var definition := get_activity(str(activity.get("item_id", "")))
			if not definition.is_empty():
				_add_inventory(state, definition, int(activity.get("quantity", 1)), int(activity.get("cost_basis", 0)))
			restored = true
			restored_name = str(activity.get("name", "item"))
			continue
		remaining.append(activity)
	if not restored:
		return "That listing is no longer active."
	state.active_activities = remaining
	state.state_changed.emit()
	return "%s returned to workshop inventory. The listing fee was not refundable." % restored_name


func get_inventory(state) -> Array[Dictionary]:
	var inventory := _inventory_copy(state)
	for index in range(inventory.size()):
		var entry: Dictionary = inventory[index]
		var quantity := maxi(1, int(entry.get("quantity", 1)))
		entry["unit_cost"] = int(round(float(int(entry.get("total_cost_basis", 0))) / float(quantity)))
		var definition := get_activity(str(entry.get("item_id", "")))
		entry["estimated_unit_value"] = int((int(definition.get("sale_price_min", 0)) + int(definition.get("sale_price_max", 0))) / 2.0)
		inventory[index] = entry
	return inventory


func inventory_quantity(state, item_id: String) -> int:
	for entry in _inventory_copy(state):
		if str(entry.get("item_id", "")) == item_id:
			return maxi(0, int(entry.get("quantity", 0)))
	return 0


func get_active_gigs(state) -> Array[Dictionary]:
	return _active_of_type(state, "freelance_gig")


func get_active_listings(state) -> Array[Dictionary]:
	return _active_of_type(state, "market_listing")


## Resolve submitted work and listing demand after CalendarSystem advances. The
## week-index guard prevents repeated Next Week input from duplicating payouts.
func process_week(state, economy = null) -> Array[String]:
	var summary: Array[String] = []
	var week_index := int(state.calendar.get("week_index", 0))
	if int(state.flags.get(PROCESS_FLAG, -1)) == week_index:
		return summary
	state.flags[PROCESS_FLAG] = week_index

	var remaining: Array[Dictionary] = []
	for activity_value in state.active_activities:
		var activity: Dictionary = activity_value
		var activity_type := str(activity.get("type", ""))
		if activity_type != "freelance_gig" and activity_type != "market_listing":
			remaining.append(activity)
			continue
		if int(activity.get("due_week", week_index)) > week_index:
			remaining.append(activity)
			continue
		if activity_type == "freelance_gig":
			_resolve_gig(state, activity, economy, summary)
		else:
			var keep_listing := _resolve_listing(state, activity, economy, summary)
			if keep_listing:
				remaining.append(activity)
	state.active_activities = remaining
	state.state_changed.emit()
	return summary


func _resolve_gig(state, activity: Dictionary, economy, summary: Array[String]) -> void:
	var gig_id := str(activity.get("activity_id", ""))
	var definition := get_activity(gig_id)
	if definition.is_empty():
		summary.append("A discontinued freelance brief was removed without payment.")
		return
	var requirements: Dictionary = definition.get("requirements", {})
	var skill_requirements: Dictionary = requirements.get("skills", {})
	var primary_skill := str(definition.get("primary_skill", ""))
	var threshold := int(skill_requirements.get(primary_skill, 0))
	var skill_level := int(state.skills.get(primary_skill, 0))
	var chance := int(definition.get("base_acceptance", 60))
	chance += int((skill_level - threshold) / 2.0)
	chance += int((int(state.reputation) - 40) / 6.0)
	chance -= maxi(0, int(state.stress) - 55) / 5
	chance = clampi(chance, 15, 95)
	var accepted := int(state.randi_seeded(100)) < chance
	var name := str(definition.get("name", "Freelance work"))
	var client := str(definition.get("client", "The client"))
	if accepted:
		var payment := maxi(0, int(activity.get("potential_pay", definition.get("pay_min", 0))))
		_record_money(state, economy, payment, "%s — %s" % [name, client], "freelance_income")
		_apply_effects(state, definition.get("success_effects", {}))
		_increment_stat(state, "gigs_accepted", 1)
		_increment_stat(state, "freelance_revenue", payment)
		state.add_history("%s accepted %s and paid $%s." % [client, name, _money(payment)])
		summary.append("%s approved %s and paid $%s." % [client, name, _money(payment)])
	else:
		_apply_effects(state, definition.get("rejection_effects", {}))
		_increment_stat(state, "gigs_rejected", 1)
		state.add_history("%s declined %s after review." % [client, name])
		summary.append("%s declined %s after review, so the proposed payment did not arrive." % [client, name])


func _resolve_listing(state, activity: Dictionary, economy, summary: Array[String]) -> bool:
	var item_id := str(activity.get("item_id", activity.get("activity_id", "")))
	var definition := get_activity(item_id)
	if definition.is_empty():
		summary.append("A discontinued marketplace listing was removed.")
		return false
	var demand_chance := int(definition.get("base_demand", 50))
	demand_chance += int(state.skills.get("business", 0) / 4.0)
	demand_chance += int((int(state.reputation) - 40) / 8.0)
	demand_chance -= maxi(0, int(state.stress) - 65) / 6
	demand_chance = clampi(demand_chance, 12, 93)
	var sold := int(state.randi_seeded(100)) < demand_chance
	var quantity := maxi(1, int(activity.get("quantity", 1)))
	var name := str(definition.get("name", activity.get("name", "Marketplace item")))
	if sold:
		var price_min := maxi(0, int(definition.get("sale_price_min", 0)))
		var price_max := maxi(price_min, int(definition.get("sale_price_max", price_min)))
		var unit_price := price_min + int(state.randi_seeded(price_max - price_min + 1))
		var revenue := unit_price * quantity
		_record_money(state, economy, revenue, "%d × %s marketplace sale" % [quantity, name], "marketplace_sale")
		var cost_basis := int(activity.get("cost_basis", 0)) + int(activity.get("listing_fee", 0))
		var profit := revenue - cost_basis
		state.happiness = clampi(int(state.happiness) + (2 if profit >= 0 else -1), 0, 100)
		state.reputation = clampi(int(state.reputation) + 1, -100, 100)
		state.skills["business"] = clampi(int(state.skills.get("business", 0)) + 2, 0, 100)
		_increment_stat(state, "items_sold", quantity)
		_increment_stat(state, "marketplace_revenue", revenue)
		state.add_history("Sold %d × %s through the neighborhood marketplace." % [quantity, name])
		summary.append("Marketplace demand found a buyer for %d × %s at $%s each: $%s revenue and $%s %s after making and listing costs." % [quantity, name, _money(unit_price), _money(revenue), _money(absi(profit)), "profit" if profit >= 0 else "loss"])
		return false

	activity["weeks_listed"] = int(activity.get("weeks_listed", 0)) + 1
	if int(activity["weeks_listed"]) >= maxi(1, int(activity.get("max_weeks", 3))):
		_add_inventory(state, definition, quantity, int(activity.get("cost_basis", 0)))
		_increment_stat(state, "expired_listings", 1)
		summary.append("The %s listing expired after %d week(s) without a buyer. The item returned to workshop inventory." % [name, int(activity["weeks_listed"])])
		return false
	activity["due_week"] = int(state.calendar.get("week_index", 0)) + 1
	summary.append("No buyer chose %s this week. The listing remains active for %d more week(s)." % [name, maxi(0, int(activity.get("max_weeks", 3)) - int(activity["weeks_listed"]))])
	return true


func _requirement_reasons(state, requirements_value) -> Array[String]:
	var reasons: Array[String] = []
	if not requirements_value is Dictionary:
		return reasons
	var requirements: Dictionary = requirements_value
	if bool(requirements.get("not_jailed", false)) and _is_jailed(state):
		reasons.append("Unavailable while jailed.")
	if int(state.age) < int(requirements.get("min_age", 0)):
		reasons.append("Requires age %d." % int(requirements.get("min_age", 0)))
	if int(state.health) < int(requirements.get("min_health", 0)):
		reasons.append("Requires health %d." % int(requirements.get("min_health", 0)))
	if int(state.happiness) < int(requirements.get("min_happiness", 0)):
		reasons.append("Requires happiness %d." % int(requirements.get("min_happiness", 0)))
	if int(state.stress) > int(requirements.get("max_stress", 100)):
		reasons.append("Stress must be %d or lower." % int(requirements.get("max_stress", 100)))
	if int(state.reputation) < int(requirements.get("min_reputation", -100)):
		reasons.append("Requires reputation %d." % int(requirements.get("min_reputation", -100)))
	if bool(requirements.get("housing_required", false)) and str(state.housing_id).is_empty():
		reasons.append("Stable housing and workspace are required.")
	var skill_requirements: Dictionary = requirements.get("skills", {})
	for skill_key in skill_requirements.keys():
		var required := int(skill_requirements.get(skill_key, 0))
		var actual := int(state.skills.get(str(skill_key), 0))
		if actual < required:
			reasons.append("%s %d required (you have %d)." % [str(skill_key).replace("_", " ").capitalize(), required, actual])
	var education_requirements = requirements.get("education", [])
	if education_requirements is Array:
		for qualification_value in education_requirements:
			var qualification := str(qualification_value)
			if not state.education.has(qualification):
				reasons.append("Requires %s." % qualification.replace("_", " ").capitalize())
	return reasons


func _apply_effects(state, effects_value) -> void:
	if not effects_value is Dictionary:
		return
	var effects: Dictionary = effects_value
	for stat in ["health", "happiness", "stress", "energy"]:
		if effects.has(stat):
			state.set(stat, clampi(int(state.get(stat)) + int(effects.get(stat, 0)), 0, 100))
	if effects.has("reputation"):
		state.reputation = clampi(int(state.reputation) + int(effects.get("reputation", 0)), -100, 100)
	var skill_effects: Dictionary = effects.get("skills", {})
	for skill_key in skill_effects.keys():
		var skill_id := str(skill_key)
		state.skills[skill_id] = clampi(int(state.skills.get(skill_id, 0)) + int(skill_effects.get(skill_key, 0)), 0, 100)


func _add_inventory(state, definition: Dictionary, quantity: int, cost_basis: int) -> void:
	var inventory := _inventory_copy(state)
	var item_id := str(definition.get("id", ""))
	for index in range(inventory.size()):
		var entry: Dictionary = inventory[index]
		if str(entry.get("item_id", "")) != item_id:
			continue
		entry["quantity"] = maxi(0, int(entry.get("quantity", 0))) + maxi(0, quantity)
		entry["total_cost_basis"] = maxi(0, int(entry.get("total_cost_basis", 0))) + maxi(0, cost_basis)
		entry["last_crafted_week"] = int(state.calendar.get("week_index", 0))
		inventory[index] = entry
		state.flags[INVENTORY_FLAG] = inventory
		return
	inventory.append({
		"id": item_id,
		"item_id": item_id,
		"name": str(definition.get("name", "Marketplace item")),
		"quantity": maxi(0, quantity),
		"total_cost_basis": maxi(0, cost_basis),
		"last_crafted_week": int(state.calendar.get("week_index", 0)),
	})
	state.flags[INVENTORY_FLAG] = inventory


func _remove_inventory(state, item_id: String, quantity: int) -> Dictionary:
	var inventory := _inventory_copy(state)
	for index in range(inventory.size()):
		var entry: Dictionary = inventory[index]
		if str(entry.get("item_id", "")) != item_id:
			continue
		var existing_quantity := maxi(0, int(entry.get("quantity", 0)))
		if quantity <= 0 or quantity > existing_quantity:
			return {"ok": false, "cost_basis": 0}
		var existing_basis := maxi(0, int(entry.get("total_cost_basis", 0)))
		var allocated_basis := int(round(float(existing_basis) * float(quantity) / float(existing_quantity)))
		if quantity == existing_quantity:
			inventory.remove_at(index)
		else:
			entry["quantity"] = existing_quantity - quantity
			entry["total_cost_basis"] = existing_basis - allocated_basis
			inventory[index] = entry
		state.flags[INVENTORY_FLAG] = inventory
		return {"ok": true, "cost_basis": allocated_basis}
	return {"ok": false, "cost_basis": 0}


func _inventory_copy(state) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	var raw_inventory = state.flags.get(INVENTORY_FLAG, [])
	if not raw_inventory is Array:
		return result
	for raw_entry in raw_inventory:
		if not raw_entry is Dictionary:
			continue
		var entry: Dictionary = raw_entry.duplicate(true)
		entry["item_id"] = str(entry.get("item_id", entry.get("id", "")))
		entry["quantity"] = maxi(0, int(entry.get("quantity", 0)))
		entry["total_cost_basis"] = maxi(0, int(entry.get("total_cost_basis", 0)))
		if not str(entry.get("item_id", "")).is_empty() and int(entry.get("quantity", 0)) > 0:
			result.append(entry)
	return result


func _active_of_type(state, activity_type: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for raw_activity in state.active_activities:
		if str(raw_activity.get("type", "")) == activity_type:
			result.append(raw_activity.duplicate(true))
	return result


func _action_count(state, action_key: String) -> int:
	_prepare_action_counts(state)
	var counts: Dictionary = state.flags.get(ACTION_COUNTS_FLAG, {})
	return maxi(0, int(counts.get(action_key, 0)))


func _increment_action(state, action_key: String) -> void:
	_prepare_action_counts(state)
	var counts: Dictionary = state.flags.get(ACTION_COUNTS_FLAG, {})
	counts[action_key] = maxi(0, int(counts.get(action_key, 0))) + 1
	state.flags[ACTION_COUNTS_FLAG] = counts


func _prepare_action_counts(state) -> void:
	var week_index := int(state.calendar.get("week_index", 0))
	if int(state.flags.get(ACTION_WEEK_FLAG, -1)) == week_index and state.flags.get(ACTION_COUNTS_FLAG, {}) is Dictionary:
		return
	state.flags[ACTION_WEEK_FLAG] = week_index
	state.flags[ACTION_COUNTS_FLAG] = {}


func _increment_stat(state, key: String, amount: int) -> void:
	var stats_value = state.flags.get(STATS_FLAG, {})
	var stats: Dictionary = stats_value if stats_value is Dictionary else {}
	stats[key] = int(stats.get(key, 0)) + amount
	state.flags[STATS_FLAG] = stats


func _next_sequence(state) -> int:
	var sequence := maxi(0, int(state.flags.get(SEQUENCE_FLAG, 0))) + 1
	state.flags[SEQUENCE_FLAG] = sequence
	return sequence


func _spend_time(state, hours: int, reason: String) -> bool:
	if hours <= 0:
		return true
	if state.has_method("spend_time"):
		return bool(state.spend_time(hours, reason))
	if int(state.weekly_time) < hours:
		return false
	state.weekly_time = int(state.weekly_time) - hours
	return true


func _record_money(state, economy, amount: int, reason: String, category: String) -> void:
	if amount == 0:
		return
	if economy != null and economy.has_method("record"):
		economy.record(state, amount, reason, category)
		return
	state.cash = int(state.cash) + amount
	var sequence := maxi(int(state.flags.get("ledger_sequence", state.ledger.size())), state.ledger.size()) + 1
	state.flags["ledger_sequence"] = sequence
	state.ledger.append({
		"id": sequence,
		"week_index": int(state.calendar.get("week_index", 0)),
		"date": "%04d-%02d-%02d" % [int(state.calendar.get("year", 0)), int(state.calendar.get("month", 1)), int(state.calendar.get("day", 1))],
		"amount": amount,
		"reason": reason,
		"category": category,
		"balance_after": int(state.cash),
		"account": "cash",
	})


func _is_jailed(state) -> bool:
	return bool(state.crime.get("in_jail", state.crime.get("jailed", false))) or int(state.crime.get("jail_weeks", state.crime.get("jail_weeks_remaining", 0))) > 0


func _reload_content() -> void:
	_hobbies.clear()
	_gigs.clear()
	_marketplace_items.clear()
	if not FileAccess.file_exists(CONTENT_PATH):
		push_error("ActivitySystem content missing: %s" % CONTENT_PATH)
		return
	var file := FileAccess.open(CONTENT_PATH, FileAccess.READ)
	if file == null:
		push_error("ActivitySystem could not open: %s" % CONTENT_PATH)
		return
	var parsed = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		push_error("ActivitySystem expected a JSON object in %s" % CONTENT_PATH)
		return
	_hobbies = _validated_entries(parsed.get("hobbies", []), "hobbies")
	_gigs = _validated_entries(parsed.get("gigs", []), "gigs")
	_marketplace_items = _validated_entries(parsed.get("marketplace_items", []), "marketplace_items")


func _validated_entries(value, label: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not value is Array:
		push_error("ActivitySystem expected '%s' to be an array." % label)
		return result
	var seen: Dictionary = {}
	for raw_entry in value:
		if not raw_entry is Dictionary:
			continue
		var entry: Dictionary = raw_entry.duplicate(true)
		var entry_id := str(entry.get("id", "")).strip_edges()
		if entry_id.is_empty() or seen.has(entry_id):
			push_error("ActivitySystem ignored a missing or duplicate %s id: %s" % [label, entry_id])
			continue
		seen[entry_id] = true
		result.append(entry)
	return result


func _duplicate_entries(entries: Array[Dictionary]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry in entries:
		result.append(entry.duplicate(true))
	return result


func _join_strings(values: Array) -> String:
	var parts := PackedStringArray()
	for value in values:
		parts.append(str(value))
	return " ".join(parts)


func _money(value: int) -> String:
	var raw := str(absi(value))
	var formatted := ""
	while raw.length() > 3:
		formatted = "," + raw.right(3) + formatted
		raw = raw.left(raw.length() - 3)
	formatted = raw + formatted
	return ("-" if value < 0 else "") + formatted
