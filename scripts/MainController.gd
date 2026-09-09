extends Node2D

const OCCUPATION_PAGE = preload("res://scripts/ui/pages/OccupationPage.gd")
const ASSETS_PAGE = preload("res://scripts/ui/pages/AssetsPage.gd")
const TRADE_TICKET = preload("res://scripts/ui/TradeTicket.gd")

const NAV_ITEMS := [
	{"id":"life", "label":"LIFE", "icon":"res://assets/mobile_icons/life.svg"},
	{"id":"city", "label":"CITY", "icon":"res://assets/mobile_icons/real_estate.svg"},
	{"id":"occupation", "label":"OCCUPATION", "icon":"res://assets/mobile_icons/career.svg"},
	{"id":"assets", "label":"ASSETS", "icon":"res://assets/mobile_icons/assets.svg"},
	{"id":"people", "label":"PEOPLE", "icon":"res://assets/mobile_icons/more.svg"}
]

var state: LifeGameState
var calendar: CalendarSystem
var economy: EconomySystem
var saves: SaveSystem
var characters: CharacterSystem
var employment: EmploymentSystem
var housing: HousingSystem
var business: BusinessSystem
var relationships: RelationshipSystem
var events: EventSystem
var activity_system: ActivitySystem
var asset_system: AssetSystem
var market_system: MarketSystem
var travel_system: TravelSystem
var vehicle_system: VehicleFinanceSystem

var ui := UiKit.new()
var character_page := CharacterCreatePage.new()
var housing_page := HousingSetupPage.new()
var life_page := LifePage.new()
var city_page := CityPage.new()
var occupation_page = OCCUPATION_PAGE.new()
var assets_page = ASSETS_PAGE.new()
var people_page := PeoplePage.new()
var overlay_page := OverlayPage.new()

var hitboxes: Array[Dictionary] = []
var hover_key := ""
var screen_mode := "welcome"
var current_page := "life"
var occupation_tab := "career"
var asset_tab := "owned"
var asset_category := ""
var market_section := "portfolio"
var city_tab := "local"
var selected_district := ""
var selected_person := ""
var name_active := false
var character_form := {
	"name":"Alex Rivera",
	"pronouns":"they/them",
	"appearance":0,
	"background":"family_couch",
	"traits":["resilient"]
}
var overlay_mode := ""
var overlay_data: Dictionary = {}
var pending_event: Dictionary = {}
var scrolls := {"life":0.0, "city":0.0, "occupation":0.0, "assets":0.0, "people":0.0}
var districts: Array[Dictionary] = []
var advancing := false
var last_advance_msec := 0
var nav_textures: Dictionary = {}
var touch_dragged := false
var touch_start := Vector2.ZERO
var touch_index := -1
var persistence_enabled := true
var trade_ticket: Control
var name_input: LineEdit

func _ready() -> void:
	state = LifeGameState.new()
	calendar = CalendarSystem.new()
	economy = EconomySystem.new()
	saves = SaveSystem.new()
	characters = CharacterSystem.new()
	employment = EmploymentSystem.new()
	housing = HousingSystem.new()
	business = BusinessSystem.new()
	relationships = RelationshipSystem.new()
	events = EventSystem.new()
	activity_system = ActivitySystem.new()
	asset_system = AssetSystem.new()
	market_system = MarketSystem.new()
	travel_system = TravelSystem.new()
	vehicle_system = VehicleFinanceSystem.new()
	_setup_native_inputs()
	districts = _load_array("res://data/districts.json", "districts")
	for item in NAV_ITEMS:
		var texture := load(str(item.icon))
		if texture is Texture2D: nav_textures[str(item.id)] = texture
	_apply_qa_args()
	_sync_name_input()
	get_viewport().size_changed.connect(queue_redraw)
	queue_redraw()

func _draw() -> void:
	hitboxes.clear()
	ui.begin(self, hitboxes, hover_key)
	match screen_mode:
		"welcome":
			character_page.draw(ui, state, {"welcome":true, "has_save":saves.has_save()})
		"create":
			var create_ctx := character_form.duplicate(true)
			create_ctx["welcome"] = false
			create_ctx["backgrounds"] = characters.get_backgrounds()
			create_ctx["traits"] = characters.get_traits()
			create_ctx["selected_traits"] = character_form["traits"]
			create_ctx["name_active"] = name_active
			character_page.draw(ui, state, create_ctx)
		"housing":
			var housing_eligibility: Dictionary = {}
			for option in housing.get_options():
				housing_eligibility[str(option.get("id", ""))] = housing.eligibility_details(state, str(option.get("id", "")))
			housing_page.draw(ui, state, {
				"housing_options":housing.get_options(),
				"eligibility":housing_eligibility,
				"initial":not state.created,
				"back_action":"back_to_character" if not state.created else "close_housing"
			})
		_:
			_draw_game_page()
			_draw_next_week_dock()
			_draw_bottom_nav()
			if current_page == "life":
				ui.button(Rect2(300, 18, 70, 36), "Save", "manual_save", null, UiKit.BLUE_DARK)

	# A modal owns the whole canvas. Remove page hit targets so taps in its
	# translucent area cannot leak through to navigation or a card underneath.
	if not overlay_mode.is_empty():
		hitboxes.clear()
	if overlay_mode == "summary":
		overlay_page.draw_week_summary(ui, state, overlay_data)
	elif overlay_mode == "event":
		var display_event := pending_event.duplicate(true)
		if not display_event.is_empty():
			display_event["choices"] = events.get_available_choices(state, str(display_event.get("id", "")))
		overlay_page.draw_event(ui, state, {"event":display_event})
	elif overlay_mode == "message":
		overlay_page.draw_message(ui, overlay_data)

func _draw_game_page() -> void:
	var date := calendar.date_text(state.calendar)
	match current_page:
		"city":
			city_page.draw(ui, state, _city_context(date))
		"occupation":
			occupation_page.draw(ui, state, _occupation_context(date))
		"assets":
			assets_page.draw(ui, state, _assets_context(date))
		"people":
			people_page.draw(ui, state, _people_context(date))
		_:
			life_page.draw(ui, state, _life_context(date))

func _life_context(date: String) -> Dictionary:
	var home := housing.current(state)
	var city := travel_system.get_current_city(state)
	var contract := travel_system.get_current_housing_contract(state)
	var home_name := str(contract.get("housing_name", home.get("name", "Unhoused")))
	var obligations: Array[String] = []
	for bill in economy.get_upcoming_obligations(state, {"housing":housing.get_options()}):
		if bill is Dictionary:
			var days := int(bill.get("due_in_days", -1))
			var when := ("in %d days" % days) if days >= 0 else str(bill.get("due_in", bill.get("schedule", "scheduled")))
			obligations.append("%s: %s (%s)" % [str(bill.get("label", bill.get("reason", bill.get("name", "Bill")))), ui.money(int(bill.get("amount", 0))), when])
	for bill in travel_system.upcoming_obligations(state):
		if bill is Dictionary and not bool(bill.get("consolidated", false)):
			var days := int(bill.get("due_in_days", -1))
			var when := ("in %d days" % days) if days >= 0 else str(bill.get("schedule", "scheduled"))
			obligations.append("%s: %s (%s)" % [str(bill.get("name", "City cost")), ui.money(int(bill.get("amount", 0))), when])
	for cost in asset_system.upcoming_costs(state):
		var days := int(cost.get("due_in_days", -1))
		var when := ("in %d days" % days) if days >= 0 else str(cost.get("due_in", "scheduled"))
		obligations.append("%s: %s (%s)" % [str(cost.get("name", "Asset upkeep")), ui.money(int(cost.get("amount", 0))), when])
	for cost in vehicle_system.get_upcoming_costs(state):
		var days := int(cost.get("due_in_days", -1))
		var when := ("in %d days" % days) if days >= 0 else str(cost.get("due_in", "scheduled"))
		obligations.append("%s: %s (%s)" % [str(cost.get("name", "Vehicle cost")), ui.money(int(cost.get("amount", 0))), when])
	var title := str(state.employment.get("title", "Unemployed"))
	if str(state.employment.get("job_id", "")).is_empty(): title = "Unemployed — looking for an opening"
	return {
		"date_text":date,
		"housing_name":home_name,
		"current_city":str(city.get("name", "Bellwether")),
		"situation":title,
		"obligations":obligations,
		"paycheck_preview":_realistic_paycheck_preview(),
		"commute_profile":travel_system.commute_profile(state),
		"scroll":scrolls["life"],
		"can_advance":not advancing
	}

func _city_context(date: String) -> Dictionary:
	var display_districts: Array[Dictionary] = []
	var chosen: Dictionary = {}
	for raw in districts:
		var district := raw.duplicate(true)
		district["description"] = str(district.get("tagline", "City opportunities"))
		var locations: Array = district.get("locations", [])
		for i in locations.size():
			var location: Dictionary = locations[i]
			var status := str(location.get("status", "available"))
			location["available"] = status == "available" or (status == "contextual" and _contextual_location_available(str(location.get("availability_rule", ""))))
			location["expansion"] = status == "unavailable_expansion"
			location["reason"] = str(location.get("unavailable_reason", "Available only when this situation is active." if status == "contextual" else ""))
			location["time_cost"] = 2
			locations[i] = location
		district["locations"] = locations
		display_districts.append(district)
		if str(district.get("id", "")) == selected_district: chosen = district
	var cities := travel_system.get_cities(state)
	var travel_quotes: Dictionary = {}
	var move_quotes: Dictionary = {}
	for city in cities:
		var city_id := str(city.get("id", ""))
		if bool(city.get("is_current", false)):
			continue
		var city_trip_quotes: Array[Dictionary] = []
		for mode in travel_system.get_travel_modes():
			city_trip_quotes.append(travel_system.trip_quote(state, city_id, str(mode.get("id", "")), true))
		travel_quotes[city_id] = city_trip_quotes
		var city_move_quotes: Array[Dictionary] = []
		for option in travel_system.get_housing_options(city_id, state):
			city_move_quotes.append(travel_system.move_quote(state, city_id, str(option.get("id", "")), "coach"))
		move_quotes[city_id] = city_move_quotes
	return {
		"date_text":date,
		"city_tab":city_tab,
		"current_city":travel_system.get_current_city(state),
		"cities":cities,
		"travel_modes":travel_system.get_travel_modes(),
		"travel_quotes":travel_quotes,
		"move_quotes":move_quotes,
		"commute_profile":travel_system.commute_profile(state),
		"commute_options":travel_system.get_local_transport_options(state),
		"district":selected_district,
		"districts":display_districts,
		"selected_district":chosen,
		"scroll":scrolls["city"]
	}

func _occupation_context(date: String) -> Dictionary:
	var jobs := employment.get_jobs()
	var current_city_id := travel_system.get_current_city_id(state)
	var eligibility: Dictionary = {}
	for i in jobs.size():
		var job: Dictionary = jobs[i]
		var details := employment.eligibility_details(state, job)
		var reasons: Array = details.get("reasons", [])
		details["reason"] = " ".join(reasons)
		eligibility[str(job.get("id", ""))] = details
		job["district"] = str(job.get("district_id", "City")).capitalize()
		job["requirements_text"] = _job_requirements_text(job)
		job["base_weekly_pay"] = int(job.get("weekly_pay", 0))
		job["weekly_pay"] = travel_system.adjusted_salary(current_city_id, int(job.get("weekly_pay", 0)))
		jobs[i] = job
	var course_eligibility: Dictionary = {}
	var courses := employment.get_courses()
	for course in courses:
		course_eligibility[str(course.get("id", ""))] = employment.course_eligibility_details(state, course)
	var hobbies := activity_system.get_hobbies()
	var gigs := activity_system.get_gigs()
	var marketplace_items := activity_system.get_marketplace_items()
	var activity_eligibility: Dictionary = {}
	var listing_eligibility: Dictionary = {}
	for item in hobbies + gigs + marketplace_items:
		var item_id := str(item.get("id", ""))
		activity_eligibility[item_id] = activity_system.eligibility_details(state, item_id)
	for item in marketplace_items:
		var item_id := str(item.get("id", ""))
		listing_eligibility[item_id] = activity_system.listing_details(state, item_id, 1)
	return {
		"date_text":date,
		"occupation_tab":occupation_tab,
		"current_city":travel_system.get_current_city(state),
		"paycheck_preview":_realistic_paycheck_preview(),
		"financial_profile":economy.get_financial_profile(state),
		"jobs":jobs,
		"job_eligibility":eligibility,
		"courses":courses,
		"course_eligibility":course_eligibility,
		"business_definition":business.get_definition(),
		"hobbies":hobbies,
		"gigs":gigs,
		"marketplace_items":marketplace_items,
		"activity_eligibility":activity_eligibility,
		"listing_details":listing_eligibility,
		"inventory":activity_system.get_inventory(state),
		"active_gigs":activity_system.get_active_gigs(state),
		"active_listings":activity_system.get_active_listings(state),
		"scroll":scrolls["occupation"]
	}

func _assets_context(date: String) -> Dictionary:
	var bills: Array = economy.get_upcoming_obligations(state, {"housing":housing.get_options()})
	bills.append_array(travel_system.upcoming_obligations(state))
	var market := asset_system.get_market_list(state, asset_category)
	var buy_eligibility: Dictionary = {}
	for item in market:
		buy_eligibility[str(item.get("id", ""))] = asset_system.can_buy(state, str(item.get("id", "")), 1)
	var owned := asset_system.get_owned(state, asset_category)
	var sell_eligibility: Dictionary = {}
	var maintenance: Dictionary = {}
	for item in owned:
		var item_id := str(item.get("id", ""))
		sell_eligibility[item_id] = asset_system.can_sell(state, item_id, 1)
		maintenance[item_id] = asset_system.maintenance_details(state, item_id)
	var physical_catalog: Array[Dictionary] = []
	for item in asset_system.get_market_list(state, ""):
		if str(item.get("category_id", "")) != "investment" and str(item.get("category_id", "")) != "vehicle":
			physical_catalog.append(item)
	var vehicle_catalog: Array[Dictionary] = []
	for definition in vehicle_system.get_catalog():
		var vehicle := definition.duplicate(true)
		var vehicle_id := str(vehicle.get("id", ""))
		vehicle["cash_quote"] = vehicle_system.quote_cash_purchase(state, vehicle_id)
		vehicle["finance_quote"] = vehicle_system.quote_finance(state, vehicle_id)
		vehicle["cash_eligibility"] = vehicle_system.eligibility_details(state, vehicle_id, "cash")
		vehicle["finance_eligibility"] = vehicle_system.eligibility_details(state, vehicle_id, "finance")
		vehicle_catalog.append(vehicle)
	var market_summary := market_system.get_portfolio_summary(state)
	var vehicle_summary := vehicle_system.get_summary(state)
	var combined_net_worth := asset_system.net_worth(state)
	combined_net_worth += int(market_summary.get("portfolio_value_cents", 0)) / 100
	combined_net_worth += int(vehicle_summary.get("equity", 0))
	var all_costs := asset_system.upcoming_costs(state)
	all_costs.append_array(vehicle_system.get_upcoming_costs(state))
	return {
		"date_text":date,
		"asset_tab":asset_tab,
		"asset_category":asset_category,
		"market_section":market_section,
		"categories":asset_system.get_categories(),
		"catalog":market,
		"physical_catalog":physical_catalog,
		"owned":owned,
		"buy_eligibility":buy_eligibility,
		"sell_eligibility":sell_eligibility,
		"maintenance":maintenance,
		"portfolio":asset_system.get_portfolio(state),
		"breakdown":asset_system.get_breakdown(state),
		"net_worth":combined_net_worth,
		"upcoming_costs":all_costs,
		"bills":bills,
		"market_instruments":market_system.get_market_list(state),
		"market_holdings":market_system.get_holdings(state),
		"market_summary":market_summary,
		"market_news":market_system.get_market_news(state),
		"market_status":market_system.get_market_status(state),
		"market_order_status":market_system.get_order_limit_status(state),
		"vehicle_catalog":vehicle_catalog,
		"owned_vehicle":vehicle_system.get_owned(state),
		"vehicle_summary":vehicle_summary,
		"scroll":scrolls["assets"]
	}

func _people_context(date: String) -> Dictionary:
	var defs := relationships.get_people()
	var by_id: Dictionary = {}
	for person in defs: by_id[str(person.get("id", ""))] = person
	var person: Dictionary = by_id.get(selected_person, {})
	var rel := relationships.get_relationship(state, selected_person) if not selected_person.is_empty() else {}
	var index := 0
	for i in state.relationships.size():
		if str(state.relationships[i].get("person_id", "")) == selected_person: index = i
	var available_actions: Array[Dictionary] = []
	if not selected_person.is_empty(): available_actions = relationships.available_actions(state, selected_person)
	return {"date_text":date, "person_id":selected_person, "people_by_id":by_id, "selected_person":person, "selected_relationship":rel, "person_index":index, "available_actions":available_actions, "scroll":scrolls["people"]}

func _draw_next_week_dock() -> void:
	draw_rect(Rect2(0, 802, 540, 78), UiKit.BG)
	draw_line(Vector2(18, 807), Vector2(522, 807), UiKit.LINE, 1.0)
	var hours := maxi(0, state.weekly_time)
	ui.text("TIME THIS WEEK", Vector2(22, 832), 9, UiKit.MUTED)
	ui.text("%d hours available" % hours, Vector2(22, 859), 17, UiKit.INK)
	ui.button(Rect2(285, 818, 237, 50), "Next week  →", "next_week", null, UiKit.BLUE_DARK, not advancing)

func _draw_bottom_nav() -> void:
	draw_rect(Rect2(0, 880, 540, 80), UiKit.WHITE)
	draw_line(Vector2(0, 880), Vector2(540, 880), UiKit.LINE, 1)
	for i in NAV_ITEMS.size():
		var item: Dictionary = NAV_ITEMS[i]
		var id := str(item["id"])
		var x := float(i * 108)
		var selected := current_page == id
		if selected:
			draw_rect(Rect2(x + 40, 880, 28, 2), UiKit.BLUE)
		ui.navigation_icon(id, Vector2(x + 54, 909), UiKit.BLUE_DARK if selected else UiKit.MUTED)
		ui.text(str(item["label"]).capitalize(), Vector2(x, 945), 11, UiKit.BLUE_DARK if selected else UiKit.MUTED, 108, HORIZONTAL_ALIGNMENT_CENTER)
		ui.register(Rect2(x, 880, 108, 80), "nav_page", id)

func _unhandled_input(event: InputEvent) -> void:
	# Native text fields and the modal consume their own input first. This keeps
	# a keyboard tap from also activating canvas buttons behind the order sheet.
	if trade_ticket != null and trade_ticket.visible: return
	# Godot generates mouse events for touch so native Controls work on phones.
	# Canvas actions use raw touch release, after swipe detection, exactly once.
	if (event is InputEventMouseButton or event is InputEventMouseMotion) and event.device == InputEvent.DEVICE_ID_EMULATION:
		return
	if event is InputEventMouseMotion:
		var new_hover := ""
		for hit in hitboxes:
			if (hit.rect as Rect2).has_point(event.position): new_hover = ui.hit_key(str(hit.action), hit.arg)
		if new_hover != hover_key:
			hover_key = new_hover
			queue_redraw()
		return
	if event is InputEventMouseButton:
		if event.button_index == MOUSE_BUTTON_WHEEL_UP and event.pressed:
			_scroll_current(-54)
			return
		if event.button_index == MOUSE_BUTTON_WHEEL_DOWN and event.pressed:
			_scroll_current(54)
			return
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			_activate_at(event.position)
			return
	if event is InputEventScreenTouch:
		if event.pressed:
			if touch_index != -1: return
			touch_index = event.index
			touch_start = event.position
			touch_dragged = false
		elif event.index == touch_index:
			touch_index = -1
			if not touch_dragged: _activate_at(event.position)
		return
	if event is InputEventScreenDrag:
		if touch_index != -1 and event.index != touch_index: return
		if event.position.distance_to(touch_start) > 8.0: touch_dragged = true
		_scroll_current(-event.relative.y)
		return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.ctrl_pressed and event.keycode == KEY_S and screen_mode == "game":
			_action("manual_save", null)
			return
		if event.keycode == KEY_ESCAPE:
			if overlay_mode == "message": overlay_mode = ""
			elif not selected_person.is_empty(): selected_person = ""
			elif not selected_district.is_empty(): selected_district = ""
			queue_redraw()

func _activate_at(point: Vector2) -> void:
	for i in range(hitboxes.size() - 1, -1, -1):
		var hit: Dictionary = hitboxes[i]
		if (hit.rect as Rect2).has_point(point):
			_action(str(hit.action), hit.arg)
			get_viewport().set_input_as_handled()
			return

func _action(action: String, arg: Variant) -> void:
	match action:
		"new_game": _new_game()
		"continue_game": _continue_game()
		"edit_name":
			name_active = true
			name_input.grab_focus()
		"set_appearance": character_form["appearance"] = posmod(int(arg), 8)
		"appearance_prev": character_form["appearance"] = posmod(int(character_form["appearance"]) - 1, 8)
		"appearance_next": character_form["appearance"] = posmod(int(character_form["appearance"]) + 1, 8)
		"set_pronouns": character_form["pronouns"] = str(arg)
		"set_background": character_form["background"] = str(arg)
		"toggle_trait": character_form["traits"] = [str(arg)]
		"finish_character": _finish_character()
		"back_to_character": screen_mode = "create"
		"choose_start_housing", "choose_housing": _choose_housing(str(arg))
		"close_housing": screen_mode = "game"
		"open_housing": screen_mode = "housing"
		"nav_page": _navigate(str(arg))
		"open_district":
			selected_district = str(arg)
			scrolls["city"] = 0.0
		"close_district":
			selected_district = ""
			scrolls["city"] = 0.0
		"visit_location": _visit_location(str(arg))
		"city_tab":
			city_tab = str(arg)
			selected_district = ""
			scrolls["city"] = 0.0
		"select_transport": _change_transport(str(arg))
		"travel_city": _travel_to_city(arg as Dictionary)
		"relocate_city": _relocate_to_city(arg as Dictionary)
		"occupation_tab":
			occupation_tab = str(arg)
			scrolls["occupation"] = 0.0
		"asset_tab":
			asset_tab = str(arg)
			scrolls["assets"] = 0.0
		"asset_category":
			asset_category = str(arg)
			scrolls["assets"] = 0.0
		"market_section":
			market_section = str(arg)
			if market_section != "things": asset_category = ""
			scrolls["assets"] = 0.0
		"buy_market": _open_trade_ticket(str(arg), "buy")
		"sell_market": _open_trade_ticket(str(arg), "sell")
		"apply_job": _job_apply(str(arg))
		"resign_job": _show_result("Career update", employment.resign(state))
		"enroll_course": _show_result("Learning update", employment.enroll_course(state, str(arg), economy))
		"perform_hobby": _show_result("Time well spent", activity_system.perform_hobby(state, str(arg), economy))
		"accept_gig": _show_result("Freelance submission", activity_system.accept_gig(state, str(arg)))
		"craft_item": _show_result("Workshop update", activity_system.craft_item(state, str(arg), economy))
		"list_item": _show_result("Marketplace update", activity_system.list_item(state, str(arg), economy, 1))
		"cancel_listing": _show_result("Listing update", activity_system.cancel_listing(state, str(arg)))
		"buy_asset": _show_result("Asset purchased", asset_system.buy(state, str(arg), 1, economy))
		"sell_asset": _show_result("Asset sold", asset_system.sell(state, str(arg), 1, economy))
		"maintain_asset": _show_result("Care and maintenance", asset_system.maintain(state, str(arg), economy))
		"buy_vehicle_cash": _vehicle_purchase(str(arg), false)
		"finance_vehicle": _vehicle_purchase(str(arg), true)
		"sell_vehicle": _vehicle_sell()
		"repair_vehicle": _show_result("Vehicle service", vehicle_system.repair(state, economy))
		"start_business": _show_result("Business update", business.start(state, economy))
		"business_price": _show_result("Pricing changed", business.set_decision(state, "price", int(arg)))
		"business_staff", "hire_staff": _show_result("Staffing changed", business.set_decision(state, "staff", int(arg)))
		"business_marketing": _show_result("Marketing changed", business.set_decision(state, "marketing_budget", int(arg)))
		"business_maintenance": _show_result("Maintenance changed", business.set_decision(state, "maintenance_budget", int(arg)))
		"business_expand": _show_result("Expansion plan", business.set_decision(state, "expand_capacity", true))
		"open_person":
			selected_person = str(arg)
			scrolls["people"] = 0.0
		"close_person":
			selected_person = ""
			scrolls["people"] = 0.0
		"person_action": _person_action(arg as Dictionary)
		"save_money": _show_result("Savings", economy.transfer_to_savings(state, int(arg)))
		"withdraw_money": _show_result("Savings", economy.withdraw_from_savings(state, int(arg)))
		"repay_debt": _show_result("Debt", economy.repay_debt(state, int(arg)))
		"next_week": _next_week()
		"continue_after_summary": _continue_after_summary()
		"resolve_event": _resolve_event(arg as Dictionary)
		"close_message": overlay_mode = ""
		"manual_save": _manual_save()
	_sync_name_input()
	queue_redraw()

func _setup_native_inputs() -> void:
	name_input = LineEdit.new()
	name_input.position = Vector2(36, 214)
	name_input.size = Vector2(332, 50)
	name_input.max_length = 28
	name_input.placeholder_text = "Your name"
	name_input.virtual_keyboard_enabled = true
	name_input.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_DEFAULT
	name_input.add_theme_font_size_override("font_size", 17)
	name_input.add_theme_font_override("font", load("res://assets/fonts/DM-Sans.ttf"))
	name_input.add_theme_color_override("font_color", UiKit.INK)
	var field := StyleBoxFlat.new()
	field.bg_color = Color("fffdf8")
	field.border_color = Color("b8c6ba")
	field.set_border_width_all(1)
	field.set_corner_radius_all(8)
	field.content_margin_left = 15
	name_input.add_theme_stylebox_override("normal", field)
	var focus := field.duplicate() as StyleBoxFlat
	focus.border_color = Color("267564")
	focus.set_border_width_all(2)
	name_input.add_theme_stylebox_override("focus", focus)
	name_input.text_changed.connect(func(value): character_form["name"] = value; queue_redraw())
	name_input.focus_entered.connect(func(): name_active = true; queue_redraw())
	name_input.focus_exited.connect(func(): name_active = false; queue_redraw())
	name_input.text_submitted.connect(func(_value): name_input.release_focus())
	add_child(name_input)
	trade_ticket = TRADE_TICKET.new()
	add_child(trade_ticket)
	trade_ticket.completed.connect(func(result, success): _show_result("Order filled" if success else "Order not placed", result, success); queue_redraw())
	trade_ticket.cancelled.connect(queue_redraw)

func _sync_name_input() -> void:
	if name_input == null: return
	name_input.visible = screen_mode == "create" and overlay_mode.is_empty()
	if not name_input.visible: name_input.release_focus()
	if name_input.text != str(character_form.get("name", "")):
		name_input.text = str(character_form.get("name", ""))

func _open_trade_ticket(symbol: String, side: String) -> void:
	if trade_ticket.visible or not overlay_mode.is_empty(): return
	trade_ticket.open_order(state, market_system, economy, symbol, side)

func _new_game() -> void:
	state.reset_new_game()
	character_form = {"name":"Alex Rivera", "pronouns":"they/them", "appearance":0, "background":"family_couch", "traits":["resilient"]}
	city_tab = "local"
	market_section = "portfolio"
	asset_category = ""
	name_active = false
	overlay_mode = ""
	screen_mode = "create"

func _continue_game() -> void:
	var result := saves.load_game(state)
	if bool(saves.last_result.get("ok", false)):
		relationships.seed_people(state)
		if state.created:
			_initialize_real_world_finances()
		screen_mode = "game" if state.created else ("housing" if not state.player_name.is_empty() else "create")
		current_page = "life"
	else:
		_show_result("Could not load", result, false)

func _finish_character() -> void:
	var result := characters.create_character(state, character_form, economy)
	if state.player_name == str(character_form["name"]).strip_edges():
		screen_mode = "housing"
	else:
		_show_result("Character setup", result, false)

func _choose_housing(housing_id: String) -> void:
	var result := housing.move_to(state, housing_id, economy)
	if state.housing_id == housing_id:
		state.created = true
		relationships.seed_people(state)
		_initialize_real_world_finances()
		_autosave()
		screen_mode = "game"
		current_page = "life"
		_show_result("Welcome home", result, true)
	else:
		_show_result("Housing update", result, false)

func _navigate(page: String) -> void:
	if page == "work": page = "occupation"
	if page == "money": page = "assets"
	if not ["life", "city", "occupation", "assets", "people"].has(page): return
	current_page = page
	selected_district = ""
	selected_person = ""
	overlay_mode = ""

func _job_apply(job_id: String) -> void:
	var old_id := str(state.employment.get("job_id", ""))
	var result := employment.apply(state, job_id)
	var success := str(state.employment.get("job_id", "")) == job_id and old_id != job_id
	if success:
		_apply_city_salary_to_current_job()
	_show_result("Application result", result, success)

func _change_transport(transport_id: String) -> void:
	var result := travel_system.select_local_transport(state, transport_id, economy)
	var success := bool(travel_system.last_result.get("ok", false))
	if success:
		_sync_finance_transport()
	_show_result("Commute updated", result, success)

func _travel_to_city(data: Dictionary) -> void:
	var city_id := str(data.get("city_id", ""))
	var mode_id := str(data.get("mode_id", "coach"))
	var result := travel_system.travel(state, city_id, mode_id, economy, true)
	_show_result("Trip update", result, bool(travel_system.last_result.get("ok", false)))

func _relocate_to_city(data: Dictionary) -> void:
	var city_id := str(data.get("city_id", ""))
	var housing_id := str(data.get("housing_id", ""))
	var mode_id := str(data.get("mode_id", "coach"))
	var result := travel_system.relocate(state, city_id, housing_id, mode_id, economy)
	var success := bool(travel_system.last_result.get("ok", false))
	if success:
		_initialize_real_world_finances()
		_apply_city_salary_to_current_job()
	_show_result("Relocation", result, success)

func _vehicle_purchase(vehicle_id: String, finance_purchase: bool) -> void:
	var result := vehicle_system.purchase_financed(state, vehicle_id, economy) if finance_purchase else vehicle_system.purchase_cash(state, vehicle_id, economy)
	var success := bool(vehicle_system.last_result.get("ok", false))
	if success:
		_sync_finance_transport()
	_show_result("Vehicle financing" if finance_purchase else "Vehicle purchase", result, success)

func _vehicle_sell() -> void:
	var result := vehicle_system.sell(state, economy)
	var success := bool(vehicle_system.last_result.get("ok", false))
	_sync_finance_transport()
	_show_result("Vehicle sale", result, success)

func _initialize_real_world_finances() -> void:
	var city := travel_system.get_current_city(state)
	var city_id := str(city.get("id", "bellwether"))
	var profile := travel_system.get_city_financial_profile(city_id)
	var cost_index := roundi((float(int(profile.get("rent_index_basis_points", 10000))) + float(int(profile.get("utility_index_basis_points", 10000)))) / 2.0)
	var finance_context := {
		"city_id":city_id,
		"city_name":str(city.get("name", "Bellwether")),
		"cost_index_basis_points":cost_index,
		"tax_rates":{"city_basis_points":0},
		"local_tax_managed_externally":true,
		"transport_mode":"travel_managed",
		"first_paycheck_wait_weeks":1
	}
	if economy.is_realistic_finances_enabled(state):
		economy.configure_city_context(state, finance_context)
	else:
		economy.enable_realistic_finances(state, finance_context)
	_sync_finance_transport()
	_apply_city_salary_to_current_job()

func _sync_finance_transport() -> void:
	if not economy.is_realistic_finances_enabled(state):
		return
	var commute := travel_system.commute_profile(state)
	var vehicle := vehicle_system.get_owned(state)
	var uses_owned_car := bool(commute.get("requires_owned_vehicle", false)) and not vehicle.is_empty() and bool(vehicle.get("operational", true))
	var city := travel_system.get_current_city(state)
	economy.configure_city_context(state, {
		"city_id":str(city.get("id", "bellwether")),
		"city_name":str(city.get("name", "Bellwether")),
		"transport_mode":"owned_vehicle" if uses_owned_car else "travel_managed",
		"tax_rates":{"city_basis_points":0},
		"local_tax_managed_externally":true
	})

func _apply_city_salary_to_current_job() -> void:
	var job_id := str(state.employment.get("job_id", ""))
	if job_id.is_empty():
		return
	var new_city_id := travel_system.get_current_city_id(state)
	var prior_city_id := str(state.employment.get("salary_city_id", ""))
	if prior_city_id == new_city_id and state.employment.has("base_weekly_pay"):
		return
	var base_pay := 0
	if not prior_city_id.is_empty() and int(state.employment.get("weekly_pay", 0)) > 0:
		var old_multiplier := maxf(0.01, travel_system.get_salary_multiplier(prior_city_id))
		base_pay = roundi(float(int(state.employment.get("weekly_pay", 0))) / old_multiplier)
	else:
		for job in employment.get_jobs():
			if str(job.get("id", "")) == job_id:
				base_pay = int(job.get("weekly_pay", 0))
				break
	if base_pay <= 0:
		base_pay = int(state.employment.get("base_weekly_pay", state.employment.get("weekly_pay", 0)))
	state.employment["base_weekly_pay"] = base_pay
	state.employment["weekly_pay"] = travel_system.adjusted_salary(new_city_id, base_pay)
	state.employment["salary_city_id"] = new_city_id

func _realistic_paycheck_preview() -> Dictionary:
	var preview := economy.get_paycheck_preview(state)
	var gross := maxi(0, int(preview.get("gross", 0)))
	var city := travel_system.get_current_city(state)
	var local_tax := roundi(float(gross) * float(int(city.get("income_tax_basis_points", 0))) / 10000.0)
	var deductions: Dictionary = preview.get("deductions", {}).duplicate(true) if preview.get("deductions", {}) is Dictionary else {}
	if local_tax > 0:
		deductions["local_income_tax"] = local_tax
	preview["deductions"] = deductions
	preview["local_income_tax"] = local_tax
	preview["total_withheld"] = int(preview.get("total_withheld", 0)) + local_tax
	preview["estimated_net"] = maxi(0, int(preview.get("estimated_net", 0)) - local_tax)
	preview["city_name"] = str(city.get("name", "City"))
	return preview

func _person_action(data: Dictionary) -> void:
	var result := relationships.act(state, str(data.get("person_id", "")), str(data.get("action_id", "")), economy)
	_show_result("Relationship moment", result, not _looks_failed(result))

func _next_week() -> void:
	var now := Time.get_ticks_msec()
	if advancing or now - last_advance_msec < 400 or not overlay_mode.is_empty(): return
	advancing = true
	last_advance_msec = now
	var cash_before := state.cash
	var boundary := calendar.advance_one_week(state)
	if not bool(boundary.get("advanced", false)):
		advancing = false
		_show_result("Week not advanced", str(boundary.get("reason", "Try again.")), false)
		return
	var summary: Array[String] = []
	summary.append_array(events.process_delayed(state, economy))
	summary.append_array(employment.process_week(state))
	summary.append_array(housing.process_week(state))
	summary.append_array(economy.process_week(state, {"housing":housing.get_options()}))
	summary.append_array(travel_system.process_week(state, economy))
	summary.append_array(relationships.process_week(state))
	summary.append_array(activity_system.process_week(state, economy))
	summary.append_array(asset_system.process_week(state, economy))
	summary.append_array(market_system.process_week(state, economy))
	_process_weekly_wellbeing(summary)
	state.last_week_summary = summary.duplicate()
	pending_event = {}
	if state.randi_seeded(100) < 76:
		pending_event = events.select_event(state)
	overlay_data = {"date_text":calendar.date_text(state.calendar), "cash_delta":state.cash - cash_before, "summary_lines":summary}
	overlay_mode = "summary"
	current_page = "life"
	_autosave()
	advancing = false

func _continue_after_summary() -> void:
	if pending_event.is_empty():
		overlay_mode = ""
	else:
		overlay_mode = "event"

func _resolve_event(data: Dictionary) -> void:
	var result := events.resolve(state, str(data.get("event_id", "")), str(data.get("choice_id", "")), economy)
	if not bool(result.get("ok", false)):
		_show_result("Choice unavailable", str(result.get("error", result.get("text", "That choice cannot be made now."))), false)
		return
	var body := str(result.get("text", "Your choice becomes part of the story."))
	var effects: Array = result.get("effect_summaries", [])
	if not effects.is_empty(): body += "\n\n" + " ".join(effects)
	pending_event = {}
	_autosave()
	_show_result(str(result.get("title", "Choice resolved")), body, true)

func _process_weekly_wellbeing(summary: Array[String]) -> void:
	var week := int(state.calendar.get("week_index", 0))
	if str(state.employment.get("job_id", "")).is_empty() and week % 2 == 0:
		state.stress = clampi(state.stress + 2, 0, 100)
		state.happiness = clampi(state.happiness - 1, 0, 100)
		summary.append("Another unemployed week raised stress slightly.")
	if state.stress >= 75:
		state.health = clampi(state.health - 2, 0, 100)
		summary.append("Sustained stress reduced health by 2.")
	elif state.stress <= 25 and week % 2 == 0:
		state.health = clampi(state.health + 1, 0, 100)
	if bool(state.crime.get("in_jail", false)):
		var remaining := maxi(0, int(state.crime.get("sentence_remaining", state.crime.get("jail_weeks", 0))) - 1)
		state.crime["sentence_remaining"] = remaining
		state.crime["jail_weeks"] = remaining
		if remaining == 0:
			state.crime["in_jail"] = false
			state.add_history("Released from city jail and returned to ordinary weekly life.")
			summary.append("Your sentence ended; normal city access returned.")
		else:
			summary.append("Jail routine continued; %d weeks remain." % remaining)

func _visit_location(location_id: String) -> void:
	var location := _find_location(location_id)
	if location.is_empty():
		_show_result("Location unavailable", "That location could not be found.", false)
		return
	if not state.spend_time(2, "Travel to %s" % str(location.get("name", "city location"))):
		_show_result("Not enough time", "Visiting this district needs 2 free hours this week.", false)
		return
	var actions: Array = location.get("actions", [])
	if actions.has("banking"):
		current_page = "assets"; asset_tab = "ledger"; selected_district = ""
	elif actions.has("browse_jobs"):
		current_page = "occupation"; occupation_tab = "career"; selected_district = ""
	elif actions.has("browse_courses"):
		current_page = "occupation"; occupation_tab = "education"; selected_district = ""
	elif actions.has("browse_housing"):
		screen_mode = "housing"
	elif actions.has("small_business"):
		current_page = "occupation"; occupation_tab = "pursuits"; selected_district = ""
	elif actions.has("vehicle_dealer"):
		current_page = "assets"; asset_tab = "market"; market_section = "things"; asset_category = "vehicle"; selected_district = ""
	elif actions.has("vehicle_service"):
		current_page = "assets"; asset_tab = "market"; market_section = "things"; asset_category = "vehicle"; selected_district = ""
	elif actions.has("crypto_market") or actions.has("mining"):
		current_page = "assets"; asset_tab = "market"; market_section = "crypto"; asset_category = ""; selected_district = ""
	elif actions.has("relationship_outing"):
		current_page = "people"; selected_district = ""
	elif actions.has("rest"):
		state.happiness = clampi(state.happiness + 4, 0, 100)
		state.stress = clampi(state.stress - 5, 0, 100)
		state.add_history("Took a quiet break at Riverside Park.")
		_show_result("A needed breather", "The park cost no money. Happiness rose and stress fell.", true)
	elif actions.has("community_events"):
		pending_event = events.select_event(state)
		if pending_event.is_empty(): _show_result("Community board", "Nothing relevant is posted for you this week.", true)
		else: overlay_mode = "event"
	elif actions.has("public_services"):
		_public_services()
	else:
		_show_result(str(location.get("name", "City location")), "This location opens only when your life creates a relevant situation.", false)

func _public_services() -> void:
	if str(state.employment.get("job_id", "")).is_empty() and state.cash < 180 and not bool(state.flags.get("starter_assistance_used", false)):
		economy.record(state, 120, "One-time public essentials grant", "public_assistance")
		state.flags["starter_assistance_used"] = true
		_show_result("Essentials grant", "You qualified for a one-time $120 city essentials grant.", true)
	else:
		_show_result("Public Services", "Your records are current. No assistance program matches your circumstances today.", true)

func _manual_save() -> void:
	if not persistence_enabled:
		_show_result("QA mode", "Saving is disabled in visual test mode.", true)
		return
	var result := saves.save_game(state, false)
	_show_result("Game saved" if bool(saves.last_result.get("ok", false)) else "Save failed", result, bool(saves.last_result.get("ok", false)))

func _show_result(title: String, body: String, success: Variant = null) -> void:
	var ok := not _looks_failed(body) if success == null else bool(success)
	overlay_data = {"title":title, "body":body, "success":ok}
	overlay_mode = "message"
	if ok and state.created: _autosave()

func _autosave() -> void:
	if persistence_enabled: saves.autosave(state)

func _looks_failed(text: String) -> bool:
	var lower := text.to_lower()
	return lower.contains("cannot") or lower.contains("not enough") or lower.contains("unavailable") or lower.contains("need $") or lower.contains("could not") or lower.contains("no longer")

func _scroll_current(delta: float) -> void:
	if screen_mode != "game" or not overlay_mode.is_empty(): return
	if trade_ticket != null and trade_ticket.visible: return
	scrolls[current_page] = clampf(float(scrolls.get(current_page, 0.0)) + delta, 0.0, _current_scroll_limit())
	queue_redraw()

func _current_scroll_limit() -> float:
	if current_page == "assets":
		if assets_page.has_method("get_scroll_limit"):
			return float(assets_page.get_scroll_limit(state, _assets_context(calendar.date_text(state.calendar))))
		if asset_tab == "market":
			if market_section == "things":
				var item_count := asset_system.get_market_list(state, asset_category).size()
				if asset_category == "vehicle": item_count = vehicle_system.get_catalog().size()
				return maxf(0.0, 200.0 + item_count * 250.0 - 600.0)
			return maxf(0.0, 230.0 + market_system.get_market_list(state, market_section if market_section != "portfolio" else "").size() * 206.0 - 600.0)
		if asset_tab == "owned": return maxf(0.0, 150.0 + asset_system.get_owned(state, asset_category).size() * 177.0 - 590.0)
		return 2400.0
	return float({"life":620.0, "city":3200.0, "occupation":1800.0, "people":700.0}.get(current_page, 0.0))

func _contextual_location_available(rule: String) -> bool:
	match rule:
		"crime_case_active": return not (state.crime.get("investigations", []) as Array).is_empty()
		"court_case_active": return bool(state.crime.get("court_case_active", false))
		"jailed": return bool(state.crime.get("in_jail", false))
		_: return false

func _find_location(location_id: String) -> Dictionary:
	for district in districts:
		for location in district.get("locations", []):
			if str(location.get("id", "")) == location_id: return (location as Dictionary).duplicate(true)
	return {}

func _job_requirements_text(job: Dictionary) -> String:
	var req: Dictionary = job.get("requirements", {})
	var parts: Array[String] = []
	for edu in req.get("education", []): parts.append(str(edu).replace("_", " ").capitalize())
	var required_skills: Dictionary = req.get("skills", {})
	for skill in required_skills: parts.append("%s %d" % [str(skill).capitalize(), int(required_skills[skill])])
	if int(req.get("max_convictions", 99)) == 0: parts.append("clean record")
	return "Entry level" if parts.is_empty() else ", ".join(parts)

func _load_array(path: String, key: String) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if not FileAccess.file_exists(path): return result
	var file := FileAccess.open(path, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(file.get_as_text()) if file != null else null
	if parsed is Dictionary:
		for item in (parsed as Dictionary).get(key, []):
			if item is Dictionary: result.append((item as Dictionary).duplicate(true))
	return result

func _apply_qa_args() -> void:
	# Screenshot-only states used by the project's visual QA command. Normal play
	# never supplies this argument and always opens the welcome screen.
	var qa := ""
	for value in OS.get_cmdline_user_args():
		if str(value).begins_with("--qa="): qa = str(value).trim_prefix("--qa=")
	if qa.is_empty(): return
	persistence_enabled = false
	if qa == "create":
		screen_mode = "create"
		return
	character_form = {"name":"Morgan Vale", "pronouns":"they/them", "appearance":5, "background":"fresh_start", "traits":["focused"]}
	characters.create_character(state, character_form, economy)
	if qa == "housing":
		screen_mode = "housing"
		return
	housing.move_to(state, "family_home", economy)
	state.created = true
	relationships.seed_people(state)
	_initialize_real_world_finances()
	screen_mode = "game"
	current_page = qa if ["life", "city", "occupation", "assets", "people"].has(qa) else "life"
	if qa == "learning" or qa == "education": current_page = "occupation"; occupation_tab = "education"
	if qa == "pursuits": current_page = "occupation"; occupation_tab = "pursuits"
	if qa == "marketplace": current_page = "occupation"; occupation_tab = "market"
	if qa == "business": current_page = "occupation"; occupation_tab = "pursuits"
	if qa == "business_active":
		current_page = "occupation"; occupation_tab = "pursuits"; state.cash = 6000; business.start(state, economy)
	if qa == "employed":
		current_page = "occupation"; occupation_tab = "career"; state.health = 90; state.reputation = 80; state.skills["practical"] = 70; employment.apply(state, "warehouse_worker")
	if qa == "ledger": current_page = "assets"; asset_tab = "ledger"
	if qa == "markets" or qa == "asset_market": current_page = "assets"; asset_tab = "market"; market_section = "portfolio"; asset_category = ""
	if qa == "market_stock": current_page = "assets"; asset_tab = "market"; market_section = "stock"; asset_category = ""
	if qa == "market_crypto": current_page = "assets"; asset_tab = "market"; market_section = "crypto"; asset_category = ""
	if qa == "trade":
		current_page = "assets"; asset_tab = "market"; market_section = "crypto"; state.cash = 2500
		_open_trade_ticket("BTC", "buy")
	if qa == "vehicle": current_page = "assets"; asset_tab = "market"; market_section = "things"; asset_category = "vehicle"; state.cash = 42000; state.skills["driving"] = 45
	if qa == "vehicle_owned":
		current_page = "assets"; asset_tab = "market"; market_section = "things"; asset_category = "vehicle"; state.cash = 10000; state.skills["driving"] = 45; state.health = 95; employment.apply(state, "warehouse_worker"); _apply_city_salary_to_current_job(); vehicle_system.purchase_financed(state, "parkside_compact_2014", economy); _sync_finance_transport()
	if qa == "asset_owned":
		current_page = "assets"; asset_tab = "owned"; state.cash = 12000
		asset_system.buy(state, "northstar_index_fund", 4, economy)
		asset_system.buy(state, "night_bus_print", 1, economy)
	if qa == "district": current_page = "city"; selected_district = "downtown"
	if qa == "travel": current_page = "city"; city_tab = "travel"
	if qa == "move" or qa == "relocation": current_page = "city"; city_tab = "move"; state.cash = 12000; state.skills["driving"] = 40
	if qa == "person": current_page = "people"; selected_person = "person_nia_brooks"
	if qa == "summary":
		current_page = "life"
		overlay_data = {"date_text":"January 12, 2026", "cash_delta":430, "summary_lines":["Work paid $560 from Warehouse Worker.", "Family Home utilities cost $80.", "You completed 38 scheduled hours; performance is 58.", "Jordan checked in after a busy week."]}
		overlay_mode = "summary"
	if qa == "event":
		current_page = "life"
		pending_event = events.select_event(state)
		overlay_mode = "event"
