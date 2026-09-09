class_name LifePage
extends RefCounted

const VIEWPORT := Rect2(0, 94, 540, 708)

func draw(ui: UiKit, state: LifeGameState, ctx: Dictionary) -> void:
	ui.host.draw_rect(Rect2(0, 0, 540, 960), UiKit.BG)
	var scroll := float(ctx.get("scroll", 0.0))
	var y := 110.0 - scroll
	y = _draw_identity(ui, state, ctx, y)
	y = _draw_obligations(ui, ctx, y)
	y = _draw_activities(ui, state, y)
	_draw_history(ui, state, y)
	_mask_content(ui)
	ui.header("Life", "AGE %d  /  %s" % [state.age, str(ctx.get("current_city", "Bellwether"))], state.cash, str(ctx.get("date_text", "")))

func _visible(y: float, height: float) -> bool:
	return y + height > VIEWPORT.position.y and y < VIEWPORT.end.y

func _draw_identity(ui: UiKit, state: LifeGameState, ctx: Dictionary, y: float) -> float:
	if _visible(y, 246):
		ui.panel(Rect2(18, y, 504, 246), UiKit.WHITE, UiKit.LINE, 6, 1)
		ui.avatar(Rect2(36, y + 20, 120, 140), state.player_name, state.appearance)
		ui.text("YOUR NEXT CHAPTER", Vector2(177, y + 32), 9, UiKit.MUTED)
		ui.heading(_fit_name(state.player_name, 321, 27), Vector2(177, y + 66), 27, UiKit.INK, 321)
		ui.text("%d years old  ·  %s" % [state.age, state.pronouns], Vector2(177, y + 88), 11, UiKit.MUTED)
		ui.paragraph(str(ctx.get("situation", "Finding a path in the city")), Rect2(177, y + 99, 318, 40), 12, UiKit.INK, 17, 2)
		ui.text(str(ctx.get("housing_name", "Choose a home")) + "  ›", Vector2(177, y + 153), 11, UiKit.BLUE, 318)
		ui.register(Rect2(170, y + 132, 334, 33), "open_housing")
		ui.divider(y + 179, 36, 468)
		var values := [state.health, state.happiness, state.stress, state.reputation]
		var names := ["HEALTH", "HAPPINESS", "STRESS", "REPUTATION"]
		for i in 4:
			var x := 36.0 + i * 120.0
			ui.text(str(names[i]), Vector2(x, y + 200), 8, UiKit.MUTED)
			ui.text(str(values[i]), Vector2(x, y + 227), 20, UiKit.INK)
			ui.text("/ 100", Vector2(x + 33, y + 226), 9, UiKit.MUTED)
			ui.host.draw_rect(Rect2(x, y + 235, 91, 3), UiKit.LINE)
			ui.host.draw_rect(Rect2(x, y + 235, float(values[i]) * 0.91, 3), UiKit.RED if i == 2 and int(values[i]) > 65 else UiKit.BLUE)
	return y + 266.0

func _draw_obligations(ui: UiKit, ctx: Dictionary, y: float) -> float:
	var items: Array = ctx.get("obligations", [])
	var shown := mini(items.size(), 3)
	var height := 68.0 + maxi(1, shown) * 31.0
	if _visible(y, height):
		ui.heading("Coming up", Vector2(22, y + 25), 23, UiKit.INK)
		ui.text("VIEW ACCOUNTS  ›", Vector2(357, y + 23), 10, UiKit.BLUE, 160, HORIZONTAL_ALIGNMENT_RIGHT)
		ui.register(Rect2(351, y, 169, 36), "nav_page", "assets")
		ui.divider(y + 39, 22, 496)
		if items.is_empty():
			ui.text("No scheduled payment is due next week.", Vector2(22, y + 65), 12, UiKit.MUTED)
		else:
			for i in shown:
				ui.text(str(items[i]), Vector2(22, y + 64 + i * 31), 11, UiKit.INK, 496)
			if items.size() > shown:
				ui.text("+ %d more scheduled costs in Assets" % (items.size() - shown), Vector2(22, y + height - 3), 9, UiKit.MUTED)
	return y + height + 15.0

func _draw_activities(ui: UiKit, state: LifeGameState, y: float) -> float:
	var activities: Array = state.active_activities
	var height := 126.0 if activities.is_empty() else 76.0 + mini(activities.size(), 3) * 48.0
	if _visible(y, height):
		ui.panel(Rect2(18, y, 504, height), UiKit.WHITE, UiKit.LINE, 6, 1)
		ui.heading("This week", Vector2(36, y + 32), 23, UiKit.INK)
		ui.text("%dh available" % state.weekly_time, Vector2(346, y + 29), 11, UiKit.BLUE, 155, HORIZONTAL_ALIGNMENT_RIGHT)
		if activities.is_empty():
			ui.paragraph("Make time for work, learning, or someone who matters.", Rect2(36, y + 46, 456, 40), 12, UiKit.MUTED, 17, 2)
			ui.text("EXPLORE OCCUPATIONS  ›", Vector2(36, y + 108), 10, UiKit.BLUE)
			ui.register(Rect2(30, y + 87, 253, 32), "nav_page", "occupation")
		else:
			for i in mini(activities.size(), 3):
				var activity: Dictionary = activities[i]
				ui.text(str(activity.get("name", activity.get("reason", "Planned activity"))), Vector2(36, y + 64 + i * 48), 13, UiKit.INK, 455)
				ui.text(str(activity.get("detail", "In progress")), Vector2(36, y + 83 + i * 48), 10, UiKit.MUTED, 455)
	return y + height + 22.0

func _draw_history(ui: UiKit, state: LifeGameState, y: float) -> float:
	var history: Array = state.event_history
	var height := 66.0 + mini(history.size(), 6) * 58.0
	if _visible(y, height):
		ui.heading("Life, lately", Vector2(22, y + 24), 23, UiKit.INK)
		ui.text("YOUR JOURNAL", Vector2(367, y + 22), 9, UiKit.MUTED, 150, HORIZONTAL_ALIGNMENT_RIGHT)
		ui.divider(y + 38, 22, 496)
		if history.is_empty():
			ui.text("The next chapter starts here.", Vector2(22, y + 68), 13, UiKit.MUTED)
		else:
			var first := maxi(0, history.size() - 6)
			var row := 0
			for i in range(history.size() - 1, first - 1, -1):
				ui.host.draw_circle(Vector2(28, y + 62 + row * 58), 3, UiKit.BLUE if row == 0 else UiKit.MUTED)
				ui.paragraph(str(history[i]), Rect2(43, y + 47 + row * 58, 462, 47), 12, UiKit.INK, 18, 2)
				row += 1
	return y + height + 14.0

func _mask_content(ui: UiKit) -> void:
	for i in range(ui.hits.size() - 1, -1, -1):
		var rect: Rect2 = ui.hits[i].get("rect", Rect2())
		if not rect.intersects(VIEWPORT): ui.hits.remove_at(i)
		else: ui.hits[i]["rect"] = rect.intersection(VIEWPORT)
	ui.host.draw_rect(Rect2(0, 0, 540, 94), UiKit.BG)
	ui.host.draw_rect(Rect2(0, 802, 540, 158), UiKit.BG)

func _fit_name(value: String, width: float, font_size: int) -> String:
	if UiKit.TITLE_FONT.get_string_size(value, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x <= width:
		return value
	var shortened := value
	while shortened.length() > 1 and UiKit.TITLE_FONT.get_string_size(shortened + "…", HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x > width:
		shortened = shortened.left(shortened.length() - 1)
	return shortened.strip_edges() + "…"
