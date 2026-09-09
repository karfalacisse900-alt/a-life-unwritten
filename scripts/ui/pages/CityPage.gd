class_name CityPage
extends RefCounted

## A code-drawn, app-like city and mobility screen. All content beneath the fixed
## tab bar is scrollable; no generated imagery or decorative mockup assets are
## used here.

const PAGE_WIDTH := 540.0
const CONTENT_TOP := 158.0
const CONTENT_BOTTOM := 802.0

const DISTRICT_COLORS := {
	"downtown": Color("365f82"),
	"commercial": Color("9b6238"),
	"industrial": Color("65717a"),
	"residential": Color("39735e"),
	"government": Color("695c79"),
}

const CITY_PALETTE := [
	Color("466b75"), Color("4f6f9c"), Color("637a55"),
	Color("a36f4c"), Color("6b6670"), Color("79698a"),
]


func draw(ui: UiKit, state: LifeGameState, ctx: Dictionary) -> void:
	ui.host.draw_rect(Rect2(0, 0, PAGE_WIDTH, 960), UiKit.BG)
	var first_content_hit := ui.hits.size()
	var tab := str(ctx.get("city_tab", "local"))
	if not tab in ["local", "travel", "move"]:
		tab = "local"

	match tab:
		"travel":
			_draw_travel(ui, state, ctx)
		"move":
			_draw_move(ui, state, ctx)
		_:
			if str(ctx.get("district", "")).is_empty():
				_draw_local(ui, state, ctx)
			else:
				_draw_district(ui, state, ctx)

	# Scrolled rows cannot receive taps underneath the fixed navigation.
	var content_bounds := Rect2(0, CONTENT_TOP, PAGE_WIDTH, CONTENT_BOTTOM - CONTENT_TOP)
	for index in range(ui.hits.size() - 1, first_content_hit - 1, -1):
		var clipped: Rect2 = (ui.hits[index].rect as Rect2).intersection(content_bounds)
		if clipped.has_area(): ui.hits[index].rect = clipped
		else: ui.hits.remove_at(index)
	# Paint hard masks over scrolled content, then place the stable navigation on
	# top. This gives touch scrolling the same visual behavior as a clipped list.
	ui.host.draw_rect(Rect2(0, 0, PAGE_WIDTH, CONTENT_TOP), UiKit.BG)
	ui.host.draw_rect(Rect2(0, CONTENT_BOTTOM, PAGE_WIDTH, 960 - CONTENT_BOTTOM), UiKit.BG)
	_draw_chrome(ui, state, ctx, tab)


func _draw_chrome(ui: UiKit, state: LifeGameState, ctx: Dictionary, tab: String) -> void:
	var city := _current_city(ctx)
	var city_name := str(city.get("name", "Bellwether"))
	ui.header("CITY", "%s  •  COST OF LIVING & MOBILITY" % city_name.to_upper(), state.cash, str(ctx.get("date_text", "")))
	var tabs: Array[Dictionary] = [
		{"id": "local", "label": "LOCAL"},
		{"id": "travel", "label": "TRAVEL"},
		{"id": "move", "label": "MOVE"},
	]
	for index in tabs.size():
		var item: Dictionary = tabs[index]
		ui.chip(Rect2(18 + index * 173, 106, 158, 40), str(item.get("label", "")), tab == str(item.get("id", "")), "city_tab", item.get("id"))


func _draw_local(ui: UiKit, state: LifeGameState, ctx: Dictionary) -> void:
	var scroll := float(ctx.get("scroll", 0.0))
	var y := CONTENT_TOP + 12.0 - scroll
	var city := _current_city(ctx)
	y = _draw_city_overview(ui, city, ctx, y)
	y = _section(ui, y + 12.0, "CITY DISTRICTS", "Services and opportunities near home")
	var districts: Array = _dictionary_array(ctx.get("districts", []))
	if districts.is_empty():
		y = _empty_card(ui, y, "No districts available", "The local directory has not loaded yet.")
	else:
		for index in districts.size():
			y = _draw_district_row(ui, districts[index], index, y)

	y = _section(ui, y + 10.0, "YOUR COMMUTE", "Time and cost repeat while you work")
	y = _draw_current_commute(ui, state, ctx, y)
	var commute_options: Array = _dictionary_array(ctx.get("commute_options", ctx.get("local_transport", [])))
	if commute_options.is_empty():
		y = _empty_card(ui, y, "Commute data unavailable", "Choose a local transport option once the city service is connected.")
	else:
		for raw_option in commute_options:
			var option: Dictionary = raw_option
			y = _draw_commute_option(ui, option, y)



func _draw_city_overview(ui: UiKit, city: Dictionary, ctx: Dictionary, y: float) -> float:
	var height := 164.0
	if _intersects(y, height):
		var accent := _city_color(city, 0)
		ui.panel(Rect2(18, y, 504, height), UiKit.WHITE, Color("d8dee4"), 16, 1)
		ui.host.draw_rect(Rect2(18, y, 5, height), accent)
		ui.text("CURRENT CITY", Vector2(39, y + 27), 9, accent.darkened(0.08))
		ui.heading(str(city.get("name", "Bellwether")), Vector2(39, y + 56), 24, UiKit.INK, 275)
		ui.text(str(city.get("region", "Home region")).to_upper(), Vector2(332, y + 29), 9, UiKit.MUTED, 168, HORIZONTAL_ALIGNMENT_RIGHT)
		ui.paragraph(str(city.get("tagline", city.get("description", "Your local economy shapes everyday choices."))), Rect2(39, y + 65, 445, 34), 11, UiKit.MUTED, 15, 2)
		ui.divider(y + 100, 39, 461)

		var metric_width := 92.0
		_draw_metric(ui, Rect2(39, y + 110, metric_width, 42), "RENT", _index_text(city, "rent_index_basis_points", 10000))
		_draw_metric(ui, Rect2(131, y + 110, metric_width, 42), "UTILITIES", _index_text(city, "utility_index_basis_points", 10000))
		_draw_metric(ui, Rect2(223, y + 110, metric_width, 42), "LOCAL TAX", _tax_text(city))
		_draw_metric(ui, Rect2(315, y + 110, metric_width, 42), "JOB MARKET", _index_text(city, "job_market_basis_points", 10000))
		_draw_metric(ui, Rect2(407, y + 110, metric_width, 42), "PAY LEVEL", _index_text(city, "salary_index_basis_points", 10000))

		var contract: Dictionary = _dictionary(ctx.get("housing_contract", ctx.get("current_housing_contract", {})))
		if not contract.is_empty():
			var monthly := int(contract.get("monthly_rent", 0)) + int(contract.get("monthly_utilities", 0))
			ui.text("HOME  %s / MONTH" % ui.money(monthly), Vector2(312, y + 56), 10, UiKit.TEAL, 188, HORIZONTAL_ALIGNMENT_RIGHT)
	return y + height + 10.0


func _draw_current_commute(ui: UiKit, state: LifeGameState, ctx: Dictionary, y: float) -> float:
	var height := 108.0
	if _intersects(y, height):
		var profile := _dictionary(ctx.get("commute_profile", {}))
		var exists := not profile.is_empty()
		var employed := bool(profile.get("is_employed", not str(state.employment.get("job_id", "")).is_empty()))
		ui.panel(Rect2(18, y, 504, height), Color("f0f5f4"), Color("b9cec9"), 15, 1)
		ui.panel(Rect2(34, y + 18, 48, 48), Color("dceae7"), Color("c2d8d2"), 12, 1)
		ui.text(_transport_glyph(str(profile.get("id", ""))), Vector2(34, y + 50), 19, UiKit.TEAL, 48, HORIZONTAL_ALIGNMENT_CENTER)
		ui.text("SELECTED", Vector2(98, y + 25), 9, UiKit.TEAL)
		ui.text(str(profile.get("name", "No commute selected")), Vector2(98, y + 50), 17, UiKit.INK, 250)
		var status := "Active work commute" if employed else "Charges begin when employed"
		ui.text(status, Vector2(98, y + 70), 10, UiKit.MUTED, 250)
		var monthly := int(profile.get("estimated_monthly_total", profile.get("monthly_fixed_cost", 0)))
		ui.text(ui.money(monthly), Vector2(368, y + 43), 19, UiKit.INK, 132, HORIZONTAL_ALIGNMENT_RIGHT)
		var externally_managed := bool(profile.get("vehicle_costs_managed_externally", false))
		ui.text("CITY COST / MONTH" if externally_managed else "EST. / MONTH", Vector2(368, y + 62), 8, UiKit.MUTED, 132, HORIZONTAL_ALIGNMENT_RIGHT)
		ui.divider(y + 82, 38, 462)
		var weekly := int(profile.get("weekly_commute_cost", 0))
		var hours := int(profile.get("commute_hours_weekly", 0))
		var reliable := int(profile.get("reliability_percent", 0))
		var detail := ("Fuel & insurance shown with vehicle  •  %dh weekly" % hours) if externally_managed else "%s weekly  •  %dh weekly  •  %d%% reliable" % [ui.money(weekly), hours, reliable]
		ui.text(detail if exists else "Choose below to price your journey to work", Vector2(38, y + 100), 10, UiKit.MUTED)
	return y + height + 9.0


func _draw_commute_option(ui: UiKit, option: Dictionary, y: float) -> float:
	var height := 88.0
	if _intersects(y, height):
		var selected := bool(option.get("selected", false))
		var enabled := bool(option.get("eligible", true)) and not selected
		var accent := UiKit.TEAL if selected else UiKit.BLUE_DARK
		ui.panel(Rect2(18, y, 504, height), UiKit.WHITE, Color("dce1e6"), 13, 1)
		ui.panel(Rect2(33, y + 18, 42, 42), Color("eef2f4"), Color("d8dfe4"), 10, 1)
		ui.text(_transport_glyph(str(option.get("id", ""))), Vector2(33, y + 46), 16, accent, 42, HORIZONTAL_ALIGNMENT_CENTER)
		ui.text(str(option.get("name", "Local transport")), Vector2(88, y + 28), 15, UiKit.INK, 246)
		var monthly := int(option.get("estimated_monthly_total", int(option.get("monthly_fixed_cost", 0)) + int(option.get("weekly_commute_cost", 0)) * 4))
		var hours := int(option.get("commute_hours_weekly", 0))
		var reliable := int(option.get("reliability_percent", 0))
		var external_costs := bool(option.get("vehicle_costs_managed_externally", false))
		var cost_line := "%s/mo city cost  •  %dh/wk" % [ui.money(monthly), hours] if external_costs else "%s/mo est.  •  %dh/wk  •  %d%% reliable" % [ui.money(monthly), hours, reliable]
		ui.text(cost_line, Vector2(88, y + 49), 10, UiKit.MUTED, 278)
		var reason := _first_reason(option)
		if not reason.is_empty() and not bool(option.get("eligible", true)):
			ui.text(_short(reason, 54), Vector2(88, y + 69), 9, UiKit.RED, 300)
		elif external_costs:
			ui.text("Fuel, insurance, loan and maintenance are itemized with your car.", Vector2(88, y + 69), 9, UiKit.MUTED, 300)
		else:
			ui.text(_short(str(option.get("description", "Recurring transport costs are shown before selection.")), 58), Vector2(88, y + 69), 9, UiKit.MUTED, 300)
		ui.button(Rect2(403, y + 24, 98, 40), "CURRENT" if selected else "SELECT", "select_transport", str(option.get("id", "")), accent, enabled)
	return y + height + 9.0


func _draw_district_row(ui: UiKit, district: Dictionary, index: int, y: float) -> float:
	var height := 78.0
	if _intersects(y, height):
		var district_id := str(district.get("id", ""))
		var accent: Color = DISTRICT_COLORS.get(district_id, UiKit.BLUE_DARK)
		ui.panel(Rect2(18, y, 504, height), UiKit.WHITE, Color("dce1e6"), 13, 1)
		ui.host.draw_rect(Rect2(18, y + 13, 4, height - 26), accent)
		ui.panel(Rect2(35, y + 19, 40, 40), accent.lightened(0.48), accent.lightened(0.31), 10, 1)
		ui.text(str(index + 1).pad_zeros(2), Vector2(35, y + 46), 13, accent.darkened(0.1), 40, HORIZONTAL_ALIGNMENT_CENTER)
		ui.text(str(district.get("name", district_id.capitalize())), Vector2(89, y + 30), 15, UiKit.INK, 274)
		ui.text(_short(str(district.get("description", district.get("summary", "Local services and opportunities"))), 59), Vector2(89, y + 53), 10, UiKit.MUTED, 296)
		ui.button(Rect2(411, y + 19, 90, 40), "EXPLORE", "open_district", district_id, accent)
	return y + height + 9.0


func _draw_district(ui: UiKit, state: LifeGameState, ctx: Dictionary) -> void:
	var y := CONTENT_TOP + 12.0 - float(ctx.get("scroll", 0.0))
	var selected := str(ctx.get("district", ""))
	var district := _dictionary(ctx.get("selected_district", {}))
	var accent: Color = DISTRICT_COLORS.get(selected, UiKit.BLUE_DARK)
	if _intersects(y, 52):
		ui.panel(Rect2(18, y, 504, 52), UiKit.WHITE, UiKit.LINE, 12, 1)
		ui.button(Rect2(30, y + 8, 88, 36), "BACK", "close_district", null, UiKit.BLUE_DARK)
		ui.text("LOCAL DIRECTORY", Vector2(331, y + 31), 9, UiKit.MUTED, 169, HORIZONTAL_ALIGNMENT_RIGHT)
	y += 63.0
	if _intersects(y, 116):
		ui.panel(Rect2(18, y, 504, 116), UiKit.WHITE, accent.lightened(0.28), 16, 1)
		ui.host.draw_rect(Rect2(18, y, 6, 116), accent)
		ui.text("DISTRICT", Vector2(40, y + 27), 9, accent.darkened(0.08))
		ui.text(str(district.get("name", selected.capitalize())), Vector2(40, y + 57), 23, UiKit.INK)
		ui.paragraph(str(district.get("description", "Nearby places and city services.")), Rect2(40, y + 69, 436, 34), 11, UiKit.MUTED, 15, 2)
		ui.text("%dH AVAILABLE THIS WEEK" % int(state.weekly_time), Vector2(327, y + 31), 10, UiKit.TEAL, 173, HORIZONTAL_ALIGNMENT_RIGHT)
	y += 128.0

	var locations: Array = _dictionary_array(district.get("locations", []))
	if locations.is_empty():
		_empty_card(ui, y, "Nothing open here", "Availability changes with work, money, and your circumstances.")
		return
	for index in locations.size():
		var location: Dictionary = locations[index]
		var enabled := bool(location.get("available", location.get("enabled", true))) and not bool(location.get("expansion", false))
		var time_cost := maxi(0, int(location.get("time_cost", 2)))
		var can_visit := enabled and int(state.weekly_time) >= time_cost
		var height := 96.0
		if _intersects(y, height):
			ui.panel(Rect2(18, y, 504, height), UiKit.WHITE, Color("dce1e6"), 13, 1)
			ui.panel(Rect2(34, y + 20, 42, 42), accent.lightened(0.48), accent.lightened(0.3), 10, 1)
			ui.text(str(location.get("icon", str(index + 1))), Vector2(34, y + 48), 14, accent, 42, HORIZONTAL_ALIGNMENT_CENTER)
			ui.text(str(location.get("name", "Location")), Vector2(89, y + 29), 15, UiKit.INK, 276)
			ui.paragraph(str(location.get("description", "Explore this part of the city.")), Rect2(89, y + 39, 286, 31), 9, UiKit.MUTED, 13, 2)
			var note := "%dh visit" % time_cost
			if bool(location.get("expansion", false)):
				note = "Not yet available"
			elif not enabled:
				note = _short(str(location.get("reason", "Requirements not met")), 50)
			ui.text(note, Vector2(89, y + 84), 9, UiKit.RED if not enabled else UiKit.TEAL, 290)
			ui.button(Rect2(410, y + 27, 91, 40), "VISIT", "visit_location", location.get("id"), accent, can_visit)
		y += height + 9.0


func _draw_travel(ui: UiKit, state: LifeGameState, ctx: Dictionary) -> void:
	var y := CONTENT_TOP + 12.0 - float(ctx.get("scroll", 0.0))
	if _intersects(y, 70):
		ui.panel(Rect2(18, y, 504, 70), Color("eef3f6"), Color("cfdae1"), 14, 1)
		ui.text("ROUND-TRIP TRAVEL", Vector2(38, y + 25), 10, UiKit.BLUE_DARK)
		ui.text("Visit without changing your home city", Vector2(38, y + 49), 15, UiKit.INK)
		ui.text("%s CASH  •  %dH FREE" % [ui.money(int(state.cash)), int(state.weekly_time)], Vector2(326, y + 42), 10, UiKit.MUTED, 174, HORIZONTAL_ALIGNMENT_RIGHT)
	y += 84.0

	var destinations := _destination_cities(ctx)
	if destinations.is_empty():
		_empty_card(ui, y, "No intercity routes", "Destination and fare data will appear here when available.")
		return
	for city_index in destinations.size():
		var city: Dictionary = destinations[city_index]
		var city_id := str(city.get("id", ""))
		var quotes := _quotes_for(ctx, "travel_quotes", city, ["travel_quotes", "trip_quotes", "quotes"])
		y = _draw_destination_heading(ui, city, city_index, y, "VISIT")
		if quotes.is_empty():
			y = _empty_card(ui, y, "No route quote available", "This connection cannot be priced from your current city.")
			continue
		for raw_quote in quotes:
			var quote: Dictionary = raw_quote
			y = _draw_travel_quote(ui, state, city_id, quote, y)
		y += 8.0


func _draw_destination_heading(ui: UiKit, city: Dictionary, index: int, y: float, label: String) -> float:
	var height := 86.0
	if _intersects(y, height):
		var accent := _city_color(city, index + 1)
		ui.panel(Rect2(18, y, 504, height), UiKit.WHITE, Color("d9dfe4"), 14, 1)
		ui.host.draw_rect(Rect2(18, y, 5, height), accent)
		ui.text(label, Vector2(39, y + 24), 9, accent.darkened(0.1))
		ui.heading(str(city.get("name", "Destination")), Vector2(39, y + 51), 20, UiKit.INK, 235)
		ui.text(_short(str(city.get("tagline", city.get("description", "A different place to build a life."))), 57), Vector2(39, y + 73), 9, UiKit.MUTED, 430)
		ui.text("RENT %s" % _index_text(city, "rent_index_basis_points", 10000), Vector2(315, y + 31), 10, UiKit.MUTED, 185, HORIZONTAL_ALIGNMENT_RIGHT)
		ui.text("PAY %s  •  TAX %s" % [_index_text(city, "salary_index_basis_points", 10000), _tax_text(city)], Vector2(295, y + 53), 10, UiKit.MUTED, 205, HORIZONTAL_ALIGNMENT_RIGHT)
	return y + height + 8.0


func _draw_travel_quote(ui: UiKit, state: LifeGameState, city_id: String, quote: Dictionary, y: float) -> float:
	var enabled := bool(quote.get("eligible", quote.get("valid", false)))
	var reason := _first_reason(quote)
	var height := 82.0 if enabled or reason.is_empty() else 99.0
	if _intersects(y, height):
		ui.panel(Rect2(30, y, 492, height), UiKit.WHITE, Color("dfe3e7"), 11, 1)
		var mode_id := str(quote.get("mode_id", ""))
		ui.panel(Rect2(44, y + 18, 38, 38), Color("eef1f3"), Color("d8dee3"), 9, 1)
		ui.text(_transport_glyph(mode_id), Vector2(44, y + 44), 15, UiKit.BLUE_DARK, 38, HORIZONTAL_ALIGNMENT_CENTER)
		ui.text(str(quote.get("mode_name", mode_id.replace("_", " ").capitalize())), Vector2(94, y + 28), 14, UiKit.INK, 180)
		var distance := int(quote.get("total_distance_km", quote.get("distance_km", 0)))
		ui.text("%d km round trip  •  %dh" % [distance, int(quote.get("time_hours", 0))], Vector2(94, y + 50), 10, UiKit.MUTED, 215)
		var cost := int(quote.get("total_cost", quote.get("cost", 0)))
		ui.text(ui.money(cost), Vector2(315, y + 32), 17, UiKit.INK, 88, HORIZONTAL_ALIGNMENT_RIGHT)
		ui.text("TOTAL", Vector2(315, y + 50), 8, UiKit.MUTED, 88, HORIZONTAL_ALIGNMENT_RIGHT)
		ui.button(Rect2(413, y + 20, 90, 40), "BOOK", "travel_city", {"city_id": city_id, "mode_id": mode_id}, UiKit.BLUE_DARK, enabled and int(state.cash) >= cost)
		if not enabled and not reason.is_empty():
			ui.text(_short(reason, 75), Vector2(94, y + 80), 9, UiKit.RED, 397)
	return y + height + 7.0


func _draw_move(ui: UiKit, state: LifeGameState, ctx: Dictionary) -> void:
	var y := CONTENT_TOP + 12.0 - float(ctx.get("scroll", 0.0))
	if _intersects(y, 82):
		ui.panel(Rect2(18, y, 504, 82), Color("f4f1ec"), Color("d9d0c3"), 14, 1)
		ui.text("RELOCATION", Vector2(38, y + 25), 10, UiKit.ORANGE)
		ui.text("Price the whole move before committing", Vector2(38, y + 49), 16, UiKit.INK)
		ui.text("Trip + movers + deposit + first rent + transit", Vector2(38, y + 69), 10, UiKit.MUTED)
		ui.text("%s AVAILABLE" % ui.money(int(state.cash)), Vector2(340, y + 45), 10, UiKit.MUTED, 160, HORIZONTAL_ALIGNMENT_RIGHT)
	y += 96.0

	var destinations := _destination_cities(ctx)
	if destinations.is_empty():
		_empty_card(ui, y, "No homes to compare", "Destination leases will appear when relocation data is available.")
		return
	for city_index in destinations.size():
		var city: Dictionary = destinations[city_index]
		var city_id := str(city.get("id", ""))
		var quotes := _quotes_for(ctx, "move_quotes", city, ["move_quotes", "relocation_quotes", "housing_quotes"])
		y = _draw_destination_heading(ui, city, city_index, y, "MOVE TO")
		if quotes.is_empty():
			y = _empty_card(ui, y, "No lease quote available", "Housing or transport requirements prevent a complete quote.")
			continue
		for raw_quote in quotes:
			var quote: Dictionary = raw_quote
			y = _draw_move_quote(ui, state, city_id, quote, y)
		y += 10.0


func _draw_move_quote(ui: UiKit, state: LifeGameState, city_id: String, quote: Dictionary, y: float) -> float:
	var enabled := bool(quote.get("eligible", quote.get("valid", false)))
	var reason := _first_reason(quote)
	var height := 146.0 if enabled or reason.is_empty() else 162.0
	if _intersects(y, height):
		ui.panel(Rect2(30, y, 492, height), UiKit.WHITE, Color("dcdfe2"), 13, 1)
		ui.text("LEASE OPTION", Vector2(48, y + 24), 9, UiKit.MUTED)
		ui.text(str(quote.get("housing_name", "Destination home")), Vector2(48, y + 49), 17, UiKit.INK, 270)
		var monthly := int(quote.get("monthly_housing_total", int(quote.get("first_month_rent", 0)) + int(quote.get("monthly_utilities", 0))))
		ui.text("%s / MONTH" % ui.money(monthly), Vector2(325, y + 31), 11, UiKit.MUTED, 177, HORIZONTAL_ALIGNMENT_RIGHT)
		var net_cost := int(quote.get("net_cash_needed", quote.get("gross_move_in_total", 0)))
		ui.text(ui.money(net_cost), Vector2(325, y + 56), 19, UiKit.INK, 177, HORIZONTAL_ALIGNMENT_RIGHT)
		ui.text("NET DUE TO MOVE", Vector2(325, y + 73), 8, UiKit.MUTED, 177, HORIZONTAL_ALIGNMENT_RIGHT)
		ui.divider(y + 80, 48, 454)
		var deposit := int(quote.get("deposit", 0))
		var first_rent := int(quote.get("first_month_rent", 0))
		var movers := int(quote.get("moving_service", 0))
		var local_transport := int(quote.get("local_transport_setup", 0))
		ui.text("Deposit %s  •  first rent %s  •  movers %s  •  transit %s" % [ui.money(deposit), ui.money(first_rent), ui.money(movers), ui.money(local_transport)], Vector2(48, y + 101), 9, UiKit.MUTED, 432)
		var mode_id := str(quote.get("mode_id", ""))
		var route := "%s  •  %d km  •  %dh" % [str(quote.get("mode_name", mode_id.replace("_", " ").capitalize())), int(quote.get("distance_km", 0)), int(quote.get("time_hours", 0))]
		ui.text(route, Vector2(48, y + 125), 10, UiKit.BLUE_DARK, 285)
		ui.button(Rect2(382, y + 105, 120, 38), "RELOCATE", "relocate_city", {"city_id": city_id, "housing_id": str(quote.get("housing_id", "")), "mode_id": mode_id}, UiKit.ORANGE, enabled and int(state.cash) >= net_cost)
		if not enabled and not reason.is_empty():
			ui.text(_short(reason, 78), Vector2(48, y + 149), 9, UiKit.RED, 435)
	return y + height + 8.0


func _section(ui: UiKit, y: float, title: String, subtitle: String) -> float:
	if _intersects(y, 32):
		ui.text(title, Vector2(20, y + 14), 10, UiKit.MUTED)
		ui.text(subtitle, Vector2(246, y + 14), 9, UiKit.MUTED, 274, HORIZONTAL_ALIGNMENT_RIGHT)
	return y + 30.0


func _empty_card(ui: UiKit, y: float, title: String, body: String) -> float:
	var height := 104.0
	if _intersects(y, height):
		ui.panel(Rect2(18, y, 504, height), UiKit.WHITE, UiKit.LINE, 14, 1)
		ui.text(title, Vector2(38, y + 39), 16, UiKit.INK)
		ui.paragraph(body, Rect2(38, y + 52, 442, 35), 10, UiKit.MUTED, 14, 2)
	return y + height + 9.0


func _draw_metric(ui: UiKit, rect: Rect2, label: String, value: String) -> void:
	ui.text(label, rect.position + Vector2(0, 10), 8, UiKit.MUTED, rect.size.x, HORIZONTAL_ALIGNMENT_LEFT)
	ui.text(value, rect.position + Vector2(0, 32), 14, UiKit.INK, rect.size.x, HORIZONTAL_ALIGNMENT_LEFT)


func _current_city(ctx: Dictionary) -> Dictionary:
	var raw: Variant = ctx.get("current_city", ctx.get("current_city_data", {}))
	var city: Dictionary = raw.duplicate(true) if raw is Dictionary else {"name": str(raw) if not str(raw).is_empty() else "Bellwether"}
	var profile := _dictionary(ctx.get("city_profile", ctx.get("current_city_profile", {})))
	for key in profile:
		if not city.has(key):
			city[key] = profile[key]
	return city


func _destination_cities(ctx: Dictionary) -> Array[Dictionary]:
	var current := _current_city(ctx)
	var current_id := str(current.get("id", ctx.get("current_city_id", "")))
	var source: Variant = ctx.get("cities", ctx.get("destinations", []))
	var result: Array[Dictionary] = []
	if source is Array:
		for raw_city in source:
			if not raw_city is Dictionary:
				continue
			var city: Dictionary = raw_city
			if bool(city.get("is_current", false)) or (not current_id.is_empty() and str(city.get("id", "")) == current_id):
				continue
			result.append(city)
	return result


func _quotes_for(ctx: Dictionary, context_key: String, city: Dictionary, embedded_keys: Array[String]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for embedded_key in embedded_keys:
		if city.has(embedded_key):
			_flatten_quotes(city.get(embedded_key), result)
			if not result.is_empty():
				return result
	var raw: Variant = ctx.get(context_key, {})
	var city_id := str(city.get("id", ""))
	if raw is Dictionary:
		_flatten_quotes((raw as Dictionary).get(city_id, {}), result)
	elif raw is Array:
		for candidate in raw:
			if candidate is Dictionary and str(candidate.get("destination_city_id", candidate.get("city_id", ""))) == city_id:
				_flatten_quotes(candidate, result)
	return result


func _flatten_quotes(value: Variant, result: Array[Dictionary]) -> void:
	if value is Array:
		for item in value:
			_flatten_quotes(item, result)
		return
	if not value is Dictionary:
		return
	var candidate: Dictionary = value
	if candidate.has("mode_id") and (candidate.has("total_cost") or candidate.has("net_cash_needed") or candidate.has("gross_move_in_total") or candidate.has("travel_cost")):
		result.append(candidate)
		return
	for nested in candidate.values():
		_flatten_quotes(nested, result)


func _dictionary(value: Variant) -> Dictionary:
	return value if value is Dictionary else {}


func _dictionary_array(value: Variant) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if value is Array:
		for item in value:
			if item is Dictionary:
				result.append(item)
	return result


func _index_text(city: Dictionary, key: String, fallback: int) -> String:
	return "%d%%" % roundi(float(int(city.get(key, fallback))) / 100.0)


func _tax_text(city: Dictionary) -> String:
	return "%.2f%%" % (float(int(city.get("income_tax_basis_points", 0))) / 100.0)


func _first_reason(data: Dictionary) -> String:
	var raw: Variant = data.get("reasons", [])
	if raw is Array and not raw.is_empty():
		return str(raw[0])
	return str(data.get("reason", ""))


func _transport_glyph(mode_id: String) -> String:
	if mode_id.contains("flight"):
		return "A"
	if mode_id.contains("rail") or mode_id.contains("metro"):
		return "R"
	if mode_id.contains("coach") or mode_id.contains("bus"):
		return "B"
	if mode_id.contains("car") or mode_id.contains("vehicle"):
		return "C"
	if mode_id.contains("walk") or mode_id.contains("cycle"):
		return "W"
	return "T"


func _city_color(city: Dictionary, index: int) -> Color:
	var raw := str(city.get("accent", ""))
	if not raw.is_empty():
		return Color(raw)
	return CITY_PALETTE[posmod(index, CITY_PALETTE.size())]


func _short(value: String, limit: int) -> String:
	var clean := value.strip_edges().replace("\n", " ")
	return clean if clean.length() <= limit else clean.left(maxi(1, limit - 1)).strip_edges() + "…"


func _intersects(y: float, height: float) -> bool:
	return y + height > CONTENT_TOP and y < CONTENT_BOTTOM
