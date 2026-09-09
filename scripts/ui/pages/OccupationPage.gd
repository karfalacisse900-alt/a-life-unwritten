class_name OccupationPage
extends RefCounted

const CONTENT_TOP := 234.0
const CONTENT_BOTTOM := 806.0
const PAGE_WIDTH := 540.0


func draw(ui: UiKit, state: LifeGameState, ctx: Dictionary) -> void:
	ui.host.draw_rect(Rect2(0, 0, PAGE_WIDTH, 960), UiKit.BG)
	var first_content_hit := ui.hits.size()
	var tab := str(ctx.get("occupation_tab", "career"))
	match tab:
		"education":
			_draw_education(ui, state, ctx)
		"pursuits":
			_draw_pursuits(ui, state, ctx)
		"market":
			_draw_market(ui, state, ctx)
		_:
			_draw_career(ui, state, ctx)

	var bounds := Rect2(0, CONTENT_TOP, PAGE_WIDTH, CONTENT_BOTTOM - CONTENT_TOP)
	for index in range(ui.hits.size() - 1, first_content_hit - 1, -1):
		var clipped: Rect2 = (ui.hits[index].rect as Rect2).intersection(bounds)
		if clipped.has_area(): ui.hits[index].rect = clipped
		else: ui.hits.remove_at(index)
	# The page content is drawn first and then physically masked. This keeps a
	# touch-scroll from painting beneath the fixed header or Next Week dock.
	ui.host.draw_rect(Rect2(0, 0, PAGE_WIDTH, CONTENT_TOP), UiKit.BG)
	ui.host.draw_rect(Rect2(0, CONTENT_BOTTOM, PAGE_WIDTH, 960 - CONTENT_BOTTOM), UiKit.BG)
	_draw_chrome(ui, state, ctx, tab)


func _draw_chrome(ui: UiKit, state: LifeGameState, ctx: Dictionary, tab: String) -> void:
	ui.header("OCCUPATION", "CAREER • EDUCATION • INDEPENDENT WORK", state.cash, str(ctx.get("date_text", "")))

	var tabs := [
		{"id": "career", "label": "CAREER"},
		{"id": "education", "label": "STUDY"},
		{"id": "pursuits", "label": "PURSUITS"},
		{"id": "market", "label": "MARKET"},
	]
	for index in tabs.size():
		var item: Dictionary = tabs[index]
		ui.chip(Rect2(18 + index * 128, 106, 120, 38), str(item.get("label", "")), tab == str(item.get("id", "")), "occupation_tab", item.get("id"))

	ui.panel(Rect2(18, 157, 504, 62), UiKit.WHITE, UiKit.LINE, 12, 1)
	ui.host.draw_rect(Rect2(18, 157, 4, 62), UiKit.BLUE)
	var employed := not str(state.employment.get("job_id", "")).is_empty()
	var role := str(state.employment.get("title", "Unemployed")) if employed else "Exploring what comes next"
	ui.text("CURRENT STATUS", Vector2(38, 178), 9, UiKit.MUTED)
	ui.text(role, Vector2(38, 203), 16, UiKit.INK, 290)
	ui.text("%d HOURS AVAILABLE" % int(state.weekly_time), Vector2(340, 182), 11, UiKit.TEAL, 160, HORIZONTAL_ALIGNMENT_RIGHT)
	var context_line := "%s / year • biweekly" % ui.money(int(state.employment.get("weekly_pay", 0)) * 52) if employed else "No scheduled paycheck"
	ui.text(context_line, Vector2(340, 204), 11, UiKit.MUTED, 160, HORIZONTAL_ALIGNMENT_RIGHT)


func _draw_career(ui: UiKit, state: LifeGameState, ctx: Dictionary) -> void:
	var y := CONTENT_TOP + 8.0 - float(ctx.get("scroll", 0.0))
	y = _section(ui, y, "CURRENT CHAPTER", "A job is one part of a life", UiKit.TEAL)
	var employed := not str(state.employment.get("job_id", "")).is_empty()
	var current_height := 188.0 if employed else 116.0
	if _intersects(y, current_height):
		ui.panel(Rect2(18, y, 504, current_height), UiKit.WHITE, UiKit.LINE, 8, 1)
		if employed:
			ui.host.draw_rect(Rect2(18, y + 15, 4, current_height - 30), UiKit.TEAL)
		ui.icon_badge(Vector2(54, y + 43), 23, "J", UiKit.TEAL if employed else UiKit.ORANGE)
		ui.text("EMPLOYED" if employed else "BETWEEN ROLES", Vector2(88, y + 29), 10, UiKit.TEAL if employed else UiKit.ORANGE)
		ui.text(str(state.employment.get("title", "Unemployed")) if employed else "Keep your week flexible", Vector2(88, y + 54), 19, UiKit.INK, 294)
		if employed:
			ui.text("%s/year • biweekly payroll • %dh schedule" % [ui.money(int(state.employment.get("weekly_pay", 0)) * 52), int(state.employment.get("schedule_hours", state.employment.get("hours_per_week", 0)))], Vector2(88, y + 79), 11, UiKit.MUTED, 302)
			_draw_button(ui, Rect2(402, y + 40, 98, 36), "RESIGN", "resign_job", null, UiKit.RED, true)
			var paycheck: Dictionary = ctx.get("paycheck_preview", {}) if ctx.get("paycheck_preview", {}) is Dictionary else {}
			ui.divider(y + 98, 38, 462)
			var gross := int(paycheck.get("gross", int(state.employment.get("weekly_pay", 0)) * 2))
			var withheld := int(paycheck.get("total_withheld", 0))
			var net := int(paycheck.get("estimated_net", gross - withheld))
			ui.text("BIWEEKLY GROSS", Vector2(38, y + 120), 8, UiKit.MUTED)
			ui.text(ui.money(gross), Vector2(38, y + 144), 17, UiKit.INK)
			ui.text("EST. TAXES", Vector2(199, y + 120), 8, UiKit.MUTED)
			ui.text("−%s" % ui.money(withheld), Vector2(199, y + 144), 17, UiKit.RED)
			ui.text("EST. TAKE-HOME", Vector2(351, y + 120), 8, UiKit.MUTED)
			ui.text(ui.money(net), Vector2(351, y + 144), 17, UiKit.GREEN, 131, HORIZONTAL_ALIGNMENT_RIGHT)
			var weeks_until := maxi(0, int(paycheck.get("next_pay_week", int(state.calendar.get("week_index", 0)) + 1)) - int(state.calendar.get("week_index", 0)))
			ui.text("Federal, state, payroll and %s local tax • next pay in %d week%s" % [str(paycheck.get("city_name", "city")), weeks_until, "" if weeks_until == 1 else "s"], Vector2(38, y + 174), 9, UiKit.MUTED, 444)
		else:
			ui.paragraph("Applications use time, and employers weigh skills, health, reputation, and your record.", Rect2(88, y + 65, 390, 40), 11, UiKit.MUTED, 15, 2)
	y += current_height + 18.0

	y = _section(ui, y, "OPEN ROLES", "Choose work that fits this season", UiKit.BLUE)
	var jobs: Array = ctx.get("jobs", [])
	var eligibility: Dictionary = ctx.get("job_eligibility", {})
	if jobs.is_empty():
		y = _empty_card(ui, y, "No listings today", "New openings arrive through the city job network.")
	for index in jobs.size():
		var job: Dictionary = jobs[index]
		var job_id := str(job.get("id", ""))
		var details := _details(eligibility, job_id, true)
		var allowed := bool(details.get("eligible", true))
		var card_height := 112.0
		if _intersects(y, card_height):
			var accent: Color = UiKit.BLUE
			ui.panel(Rect2(18, y, 504, card_height), UiKit.WHITE, UiKit.LINE, 8, 1)
			ui.icon_badge(Vector2(52, y + 38), 19, str(job.get("title", "J")).left(1), accent)
			ui.text(str(job.get("title", job.get("name", "Open role"))), Vector2(82, y + 31), 17, UiKit.INK, 282)
			var weekly_pay := int(job.get("weekly_pay", job.get("pay", 0)))
			ui.text("%s/year • %s" % [ui.money(weekly_pay * 52), str(job.get("district", job.get("district_id", "City"))).capitalize()], Vector2(82, y + 54), 11, accent)
			var note := _first_reason(details)
			if note.is_empty():
				note = str(job.get("description", job.get("requirements_text", "A practical city role.")))
			ui.paragraph(note, Rect2(38, y + 72, 346, 31), 10, UiKit.RED if not allowed else UiKit.MUTED, 14, 2)
			var same_job := employed and str(state.employment.get("job_id", "")) == job_id
			_draw_button(ui, Rect2(402, y + 35, 98, 40), "CURRENT" if same_job else "APPLY", "apply_job", job_id, accent, allowed and not same_job)
		y += card_height + 10.0

	y += 8.0
	y = _section(ui, y, "INDEPENDENT PATH", "Build something small before making it big", UiKit.ORANGE)
	_draw_business_card(ui, state, ctx, y)


func _draw_business_card(ui: UiKit, state: LifeGameState, ctx: Dictionary, y: float) -> void:
	var definition: Dictionary = ctx.get("business_definition", {})
	var active := bool(state.business.get("active", false))
	var height := 205.0 if active else 154.0
	if not _intersects(y, height):
		return
	ui.panel(Rect2(18, y, 504, height), UiKit.WHITE, UiKit.LINE, 8, 1)
	ui.icon_badge(Vector2(54, y + 42), 22, "B", UiKit.ORANGE)
	var name := str(state.business.get("name", definition.get("name", "Street Bowl Kitchen")))
	ui.text("YOUR VENTURE" if active else "START A VENTURE", Vector2(88, y + 28), 10, UiKit.ORANGE)
	ui.heading(name, Vector2(88, y + 55), 20, UiKit.INK, 390)
	if not active:
		ui.paragraph(str(definition.get("description", "A small city business with changing demand and real operating costs.")), Rect2(38, y + 74, 300, 45), 11, UiKit.MUTED, 15, 3)
		var startup_cost := int(definition.get("startup_cost", 3200))
		var startup_hours := int(definition.get("startup_hours", 12))
		ui.text("%s • %dh setup" % [ui.money(startup_cost), startup_hours], Vector2(357, y + 91), 12, UiKit.INK, 143, HORIZONTAL_ALIGNMENT_RIGHT)
		_draw_button(ui, Rect2(346, y + 105, 154, 37), "OPEN BUSINESS", "start_business", null, UiKit.ORANGE, state.cash >= startup_cost and state.weekly_time >= startup_hours and state.reputation >= 20)
		return

	var last_profit := int(state.business.get("last_profit", 0))
	ui.text("Last week %s%s • reputation %d" % ["+" if last_profit > 0 else "", ui.money(last_profit), int(state.business.get("reputation", 45))], Vector2(38, y + 86), 12, UiKit.GREEN if last_profit >= 0 else UiKit.RED)
	ui.text("PRICE", Vector2(38, y + 116), 9, UiKit.MUTED)
	var price := int(state.business.get("price", 14))
	for index in 3:
		var option: int = [11, 14, 18][index]
		_draw_chip(ui, Rect2(38 + index * 67, y + 126, 60, 31), "$%d" % option, price == option, "business_price", option)
	var staff := int(state.business.get("staff", 0))
	ui.text("%d STAFF • %d CAPACITY" % [staff, int(state.business.get("capacity", 28))], Vector2(252, y + 119), 10, UiKit.MUTED, 248, HORIZONTAL_ALIGNMENT_RIGHT)
	_draw_button(ui, Rect2(252, y + 127, 112, 34), "HIRE +1", "hire_staff", staff + 1, UiKit.TEAL, staff < 4)
	var maintenance := int(state.business.get("maintenance_budget", 100))
	var next_maintenance := 180 if maintenance < 180 else 60
	_draw_button(ui, Rect2(373, y + 127, 127, 34), "UPKEEP $%d" % maintenance, "business_maintenance", next_maintenance, UiKit.BLUE, true)
	ui.text("Price changes demand. Staff cost wages. Upkeep reduces breakdown risk.", Vector2(38, y + 185), 10, UiKit.MUTED, 462)


func _draw_education(ui: UiKit, state: LifeGameState, ctx: Dictionary) -> void:
	var y := CONTENT_TOP + 8.0 - float(ctx.get("scroll", 0.0))
	y = _section(ui, y, "LEARNING RECORD", "Qualifications stay with you", UiKit.PURPLE)
	var record_height := 106.0
	if _intersects(y, record_height):
		ui.panel(Rect2(18, y, 504, record_height), UiKit.WHITE, UiKit.LINE, 8, 1)
		ui.icon_badge(Vector2(54, y + 41), 23, "✓", UiKit.PURPLE)
		ui.text("EDUCATION", Vector2(89, y + 28), 10, UiKit.PURPLE)
		var education_text := "Secondary diploma"
		if not state.education.is_empty():
			var labels := PackedStringArray()
			for qualification in state.education:
				labels.append(str(qualification).replace("_", " ").capitalize())
			education_text = ", ".join(labels)
		ui.paragraph(education_text, Rect2(89, y + 39, 390, 42), 14, UiKit.INK, 19, 2)
		var active_courses := _active_courses(state)
		ui.text("%d course%s currently in progress" % [active_courses.size(), "" if active_courses.size() == 1 else "s"], Vector2(89, y + 91), 11, UiKit.MUTED)
	y += record_height + 18.0

	y = _section(ui, y, "COURSES", "Time now can unlock better choices later", UiKit.PURPLE)
	var courses: Array = ctx.get("courses", [])
	var eligibility: Dictionary = ctx.get("course_eligibility", {})
	if courses.is_empty():
		y = _empty_card(ui, y, "No class is enrolling", "Check the civic learning board again later.")
	for course_value in courses:
		var course: Dictionary = course_value
		var course_id := str(course.get("id", ""))
		var details := _details(eligibility, course_id, true)
		var active_course := _find_active_course(state, course_id)
		var active := not active_course.is_empty()
		var height := 157.0
		if _intersects(y, height):
			ui.panel(Rect2(18, y, 504, height), UiKit.WHITE, UiKit.LINE, 8, 1)
			ui.text(str(course.get("provider", "CITY LEARNING")), Vector2(38, y + 27), 9, UiKit.PURPLE)
			ui.text(str(course.get("name", "Course")), Vector2(38, y + 52), 18, UiKit.INK, 330)
			ui.paragraph(str(course.get("description", "Build a useful qualification.")), Rect2(38, y + 65, 323, 46), 10, UiKit.MUTED, 14, 3)
			var cost := int(course.get("cost", 0))
			var enrollment_hours := int(course.get("enrollment_hours", 1))
			var weekly_hours := int(course.get("weekly_hours", 1))
			ui.panel(Rect2(372, y + 22, 128, 64), Color("f6f2fb"), Color("e0d5ec"), 13, 1)
			ui.text(ui.money(cost), Vector2(372, y + 50), 17, UiKit.INK, 128, HORIZONTAL_ALIGNMENT_CENTER)
			ui.text("%dh enroll • %dh/week" % [enrollment_hours, weekly_hours], Vector2(372, y + 72), 9, UiKit.MUTED, 128, HORIZONTAL_ALIGNMENT_CENTER)
			if active:
				ui.text("IN PROGRESS • %d WEEK(S) LEFT" % int(active_course.get("weeks_remaining", 0)), Vector2(38, y + 137), 11, UiKit.PURPLE)
				_draw_button(ui, Rect2(372, y + 102, 128, 37), "IN PROGRESS", "enroll_course", course_id, UiKit.PURPLE, false)
			else:
				var allowed := bool(details.get("eligible", true))
				var reason := _first_reason(details)
				ui.text(reason if not allowed else "A planned weekly commitment", Vector2(38, y + 137), 10, UiKit.RED if not allowed else UiKit.MUTED, 318)
				_draw_button(ui, Rect2(372, y + 102, 128, 37), "ENROLL", "enroll_course", course_id, UiKit.PURPLE, allowed)
		y += height + 12.0

	y += 8.0
	y = _section(ui, y, "SKILLS IN MOTION", "What practice is changing", UiKit.BLUE)
	var skills_height := 158.0
	if _intersects(y, skills_height):
		ui.panel(Rect2(18, y, 504, skills_height), Color("fbfaf6"), Color("d9d5ca"), 18, 1)
		var skills := ["communication", "practical", "digital", "business", "creative", "discipline"]
		for index in skills.size():
			var skill_id: String = skills[index]
			var column := index % 3
			var row := index / 3
			var rect := Rect2(38 + column * 154, y + 24 + row * 56, 142, 43)
			ui.panel(rect, Color("f0f3f2"), Color("d8dfdc"), 13, 1)
			ui.text(skill_id.capitalize(), Vector2(rect.position.x + 12, rect.position.y + 18), 9, UiKit.MUTED)
			ui.text(str(int(state.skills.get(skill_id, 0))), Vector2(rect.position.x + 12, rect.position.y + 37), 16, UiKit.INK)


func _draw_pursuits(ui: UiKit, state: LifeGameState, ctx: Dictionary) -> void:
	var y := CONTENT_TOP + 8.0 - float(ctx.get("scroll", 0.0))
	var active_gigs: Array = ctx.get("active_gigs", [])
	if not active_gigs.is_empty():
		y = _section(ui, y, "ON THE CLIENT'S DESK", "Completed work awaiting a decision", UiKit.GOLD)
		for gig_value in active_gigs:
			var gig: Dictionary = gig_value
			var height := 76.0
			if _intersects(y, height):
				ui.panel(Rect2(18, y, 504, height), Color("fff8e8"), Color("e2c77e"), 17, 1)
				ui.icon_badge(Vector2(48, y + 38), 18, "…", UiKit.GOLD)
				ui.text(str(gig.get("name", "Freelance work")), Vector2(78, y + 29), 15, UiKit.INK, 290)
				ui.text(str(gig.get("client", "Client")) + " • review next week", Vector2(78, y + 53), 10, UiKit.MUTED)
				ui.text("up to %s" % ui.money(int(gig.get("potential_pay", 0))), Vector2(390, y + 42), 12, UiKit.GOLD, 110, HORIZONTAL_ALIGNMENT_RIGHT)
			y += height + 9.0
		y += 9.0

	y = _section(ui, y, "HOBBIES", "Useful is not the only reason to spend time", UiKit.TEAL)
	var hobbies: Array = ctx.get("hobbies", [])
	var eligibility: Dictionary = ctx.get("activity_eligibility", {})
	if hobbies.is_empty():
		y = _empty_card(ui, y, "Make room for something you enjoy", "Hobby opportunities appear as your life changes.")
	for index in hobbies.size():
		var hobby: Dictionary = hobbies[index]
		var hobby_id := str(hobby.get("id", ""))
		var details := _details(eligibility, hobby_id, true)
		var allowed := bool(details.get("eligible", true))
		var height := 108.0
		if _intersects(y, height):
			var accent: Color = UiKit.TEAL
			ui.panel(Rect2(18, y, 504, height), UiKit.WHITE, UiKit.LINE, 8, 1)
			ui.icon_badge(Vector2(51, y + 37), 19, str(hobby.get("name", "H")).left(1), accent)
			ui.text(str(hobby.get("name", "Hobby")), Vector2(82, y + 29), 16, UiKit.INK, 290)
			ui.text("%dh%s" % [int(hobby.get("time_hours", 0)), " • " + ui.money(int(hobby.get("cash_cost", 0))) if int(hobby.get("cash_cost", 0)) > 0 else ""], Vector2(82, y + 52), 11, accent)
			var note := _first_reason(details) if not allowed else _effects_text(hobby.get("effects", {}))
			ui.paragraph(note, Rect2(38, y + 72, 342, 29), 10, UiKit.RED if not allowed else UiKit.MUTED, 14, 2)
			_draw_button(ui, Rect2(398, y + 35, 102, 39), "MAKE TIME", "perform_hobby", hobby_id, accent, allowed)
		y += height + 10.0

	y += 9.0
	y = _section(ui, y, "FREELANCE BOARD", "Finish the work now; payment still depends on review", UiKit.BLUE)
	var gigs: Array = ctx.get("gigs", [])
	if gigs.is_empty():
		y = _empty_card(ui, y, "No briefs are open", "The local client board changes over time.")
	for index in gigs.size():
		var gig: Dictionary = gigs[index]
		var gig_id := str(gig.get("id", ""))
		var details := _details(eligibility, gig_id, true)
		var allowed := bool(details.get("eligible", true))
		var height := 126.0
		if _intersects(y, height):
			var accent := UiKit.BLUE if index % 2 == 0 else UiKit.PURPLE
			ui.panel(Rect2(18, y, 504, height), Color("fbfcfd"), accent.lightened(0.25), 18, 1)
			ui.text(str(gig.get("client", "LOCAL CLIENT")).to_upper(), Vector2(38, y + 25), 9, accent)
			ui.text(str(gig.get("name", "Freelance brief")), Vector2(38, y + 50), 17, UiKit.INK, 330)
			ui.paragraph(str(gig.get("description", "Complete a short client brief.")), Rect2(38, y + 61, 328, 35), 10, UiKit.MUTED, 14, 2)
			ui.text("%dh • possible %s–%s" % [int(gig.get("time_hours", 0)), ui.money(int(gig.get("pay_min", 0))), ui.money(int(gig.get("pay_max", 0)))], Vector2(38, y + 112), 11, UiKit.BLUE)
			_draw_button(ui, Rect2(389, y + 35, 111, 40), "SUBMIT WORK", "accept_gig", gig_id, accent, allowed)
			if not allowed:
				ui.paragraph(_first_reason(details), Rect2(377, y + 81, 123, 35), 9, UiKit.RED, 12, 3)
		y += height + 10.0


func _draw_market(ui: UiKit, state: LifeGameState, ctx: Dictionary) -> void:
	var y := CONTENT_TOP + 8.0 - float(ctx.get("scroll", 0.0))
	var active_listings: Array = ctx.get("active_listings", [])
	if not active_listings.is_empty():
		y = _section(ui, y, "IN THE WINDOW", "Listings waiting for organic demand", UiKit.GOLD)
		for listing_value in active_listings:
			var listing: Dictionary = listing_value
			var height := 82.0
			if _intersects(y, height):
				ui.panel(Rect2(18, y, 504, height), Color("fff9ec"), Color("e5cb88"), 17, 1)
				ui.icon_badge(Vector2(49, y + 41), 18, "M", UiKit.GOLD)
				ui.text("%d × %s" % [int(listing.get("quantity", 1)), str(listing.get("name", "Marketplace item"))], Vector2(78, y + 31), 15, UiKit.INK, 280)
				ui.text("Week %d of %d • no sale is guaranteed" % [int(listing.get("weeks_listed", 0)) + 1, int(listing.get("max_weeks", 3))], Vector2(78, y + 56), 10, UiKit.MUTED)
				_draw_button(ui, Rect2(399, y + 23, 101, 37), "CANCEL", "cancel_listing", listing.get("id"), UiKit.RED, true)
			y += height + 9.0
		y += 8.0

	y = _section(ui, y, "WORKSHOP SHELF", "Finished things you own and can choose to sell", UiKit.TEAL)
	var inventory: Array = ctx.get("inventory", [])
	var listing_details: Dictionary = ctx.get("listing_details", {})
	if inventory.is_empty():
		y = _empty_card(ui, y, "Your shelf is empty", "Make something below; crafting costs time and materials before any possible sale.")
	for inventory_value in inventory:
		var item: Dictionary = inventory_value
		var item_id := str(item.get("item_id", item.get("id", "")))
		var details := _details(listing_details, item_id, true)
		var allowed := bool(details.get("eligible", true)) and int(item.get("quantity", 0)) > 0
		var height := 91.0
		if _intersects(y, height):
			ui.panel(Rect2(18, y, 504, height), Color("edf7f2"), Color("b8d7c8"), 17, 1)
			ui.icon_badge(Vector2(50, y + 45), 19, str(item.get("name", "I")).left(1), UiKit.TEAL)
			ui.text(str(item.get("name", "Finished item")), Vector2(81, y + 34), 16, UiKit.INK, 280)
			ui.text("%d ready • about %s each • cost basis %s" % [int(item.get("quantity", 0)), ui.money(int(item.get("estimated_unit_value", 0))), ui.money(int(item.get("unit_cost", 0)))], Vector2(81, y + 59), 10, UiKit.MUTED)
			_draw_button(ui, Rect2(399, y + 26, 101, 39), "LIST ONE", "list_item", item_id, UiKit.TEAL, allowed)
		y += height + 9.0

	y += 8.0
	y = _section(ui, y, "MAKE FOR MARKET", "Materials are certain; buyers are not", UiKit.ORANGE)
	var products: Array = ctx.get("marketplace_items", [])
	var eligibility: Dictionary = ctx.get("activity_eligibility", {})
	if products.is_empty():
		y = _empty_card(ui, y, "No workshop ideas available", "New recipes unlock through skills and city opportunities.")
	for index in products.size():
		var product: Dictionary = products[index]
		var product_id := str(product.get("id", ""))
		var details := _details(eligibility, product_id, true)
		var allowed := bool(details.get("eligible", true))
		var height := 130.0
		if _intersects(y, height):
			var accent := UiKit.ORANGE if index % 2 == 0 else UiKit.GOLD
			ui.panel(Rect2(18, y, 504, height), UiKit.WHITE, accent.lightened(0.24), 18, 1)
			ui.text("SMALL-BATCH IDEA", Vector2(38, y + 25), 9, accent)
			ui.text(str(product.get("name", "Marketplace item")), Vector2(38, y + 49), 17, UiKit.INK, 330)
			ui.paragraph(str(product.get("description", "Make an original item for the local marketplace.")), Rect2(38, y + 60, 326, 36), 10, UiKit.MUTED, 14, 2)
			ui.text("Make %d • %dh • %s materials" % [int(product.get("quantity_yield", 1)), int(product.get("craft_time_hours", 0)), ui.money(int(product.get("material_cost", 0)))], Vector2(38, y + 115), 11, accent)
			_draw_button(ui, Rect2(389, y + 34, 111, 40), "MAKE", "craft_item", product_id, accent, allowed)
			if not allowed:
				ui.paragraph(_first_reason(details), Rect2(377, y + 80, 123, 38), 9, UiKit.RED, 12, 3)
		y += height + 10.0


func _section(ui: UiKit, y: float, title: String, subtitle: String, color: Color) -> float:
	if _intersects(y, 30.0):
		ui.host.draw_circle(Vector2(25, y + 13), 4, color)
		ui.text(title, Vector2(38, y + 17), 11, color)
		ui.text(subtitle, Vector2(210, y + 17), 10, UiKit.MUTED, 292, HORIZONTAL_ALIGNMENT_RIGHT)
	return y + 31.0


func _empty_card(ui: UiKit, y: float, title: String, body: String) -> float:
	var height := 91.0
	if _intersects(y, height):
		ui.panel(Rect2(18, y, 504, height), UiKit.WHITE, UiKit.LINE, 17, 1)
		ui.text(title, Vector2(38, y + 34), 16, UiKit.INK)
		ui.paragraph(body, Rect2(38, y + 45, 450, 35), 10, UiKit.MUTED, 14, 2)
	return y + height + 10.0


func _draw_button(ui: UiKit, rect: Rect2, label: String, action: String, arg, color: Color, enabled: bool) -> void:
	if _intersects(rect.position.y, rect.size.y):
		ui.button(rect, label, action, arg, color, enabled)


func _draw_chip(ui: UiKit, rect: Rect2, label: String, selected: bool, action: String, arg) -> void:
	if _intersects(rect.position.y, rect.size.y):
		ui.chip(rect, label, selected, action, arg)


func _intersects(y: float, height: float) -> bool:
	return y + height > CONTENT_TOP and y < CONTENT_BOTTOM


func _details(source: Dictionary, content_id: String, fallback: bool) -> Dictionary:
	var value = source.get(content_id, fallback)
	if value is Dictionary:
		return value
	return {"eligible": bool(value)}


func _first_reason(details: Dictionary) -> String:
	var reasons = details.get("reasons", [])
	if reasons is Array and not reasons.is_empty():
		return str(reasons[0])
	return str(details.get("reason", ""))


func _effects_text(effects_value) -> String:
	if not effects_value is Dictionary:
		return "A little time set aside for yourself."
	var effects: Dictionary = effects_value
	var parts := PackedStringArray()
	for key in ["happiness", "stress", "health", "energy", "reputation"]:
		var amount := int(effects.get(key, 0))
		if amount != 0:
			parts.append("%s %s%d" % [str(key).capitalize(), "+" if amount > 0 else "", amount])
	var skill_effects: Dictionary = effects.get("skills", {})
	for skill_key in skill_effects.keys():
		var amount := int(skill_effects.get(skill_key, 0))
		parts.append("%s +%d" % [str(skill_key).capitalize(), amount])
		if parts.size() >= 3:
			break
	return " • ".join(parts) if not parts.is_empty() else "A little time set aside for yourself."


func _active_courses(state: LifeGameState) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for activity_value in state.active_activities:
		var activity: Dictionary = activity_value
		if str(activity.get("type", "")) == "course":
			result.append(activity)
	return result


func _find_active_course(state: LifeGameState, course_id: String) -> Dictionary:
	for activity_value in state.active_activities:
		var activity: Dictionary = activity_value
		if str(activity.get("type", "")) == "course" and str(activity.get("id", activity.get("course_id", ""))) == course_id:
			return activity
	return {}
