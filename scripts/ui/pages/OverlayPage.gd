class_name OverlayPage
extends RefCounted

func draw_week_summary(ui: UiKit, state: LifeGameState, ctx: Dictionary) -> void:
	ui.host.draw_rect(Rect2(0, 0, 540, 960), Color(0.03, 0.08, 0.14, 0.72))
	ui.panel(Rect2(22, 72, 496, 802), UiKit.WHITE, Color("b9c9d8"), 24, 2)
	ui.host.draw_rect(Rect2(22, 72, 496, 94), UiKit.BLUE_DARK)
	ui.text("WEEK COMPLETE", Vector2(45, 116), 13, Color("8ed7ff"))
	ui.text(str(ctx.get("date_text", "")), Vector2(45, 146), 25, UiKit.WHITE)
	var delta := int(ctx.get("cash_delta", 0))
	ui.panel(Rect2(44, 188, 452, 100), Color("ecfaf5") if delta >= 0 else Color("fff0f2"), Color("b0dfcf") if delta >= 0 else Color("efbdc4"), 17, 2)
	ui.text("CASH CHANGE", Vector2(64, 220), 11, UiKit.MUTED)
	ui.text(("+" if delta > 0 else "") + ui.money(delta), Vector2(64, 259), 28, UiKit.GREEN if delta >= 0 else UiKit.RED)
	ui.text("Balance " + ui.money(state.cash), Vector2(280, 249), 14, UiKit.INK, 194, HORIZONTAL_ALIGNMENT_RIGHT)

	ui.text("WHAT HAPPENED", Vector2(46, 328), 13, UiKit.MUTED)
	var lines: Array = ctx.get("summary_lines", state.last_week_summary)
	var y := 345.0
	if lines.is_empty():
		lines = ["The week passed quietly.", "No scheduled money moved."]
	for i in mini(lines.size(), 7):
		var line := str(lines[i])
		var color := UiKit.RED if line.begins_with("-") else UiKit.GREEN if line.begins_with("+") else UiKit.BLUE
		ui.host.draw_circle(Vector2(57, y + 23), 6, color)
		ui.paragraph(line, Rect2(75, y + 8, 395, 40), 13, UiKit.INK, 17, 2)
		y += 52.0

	ui.panel(Rect2(44, 747, 452, 49), Color("f3f6f9"), UiKit.LINE, 12, 1)
	ui.text("Autosaved • each transaction remains in Assets → Banking", Vector2(44, 778), 11, UiKit.MUTED, 452, HORIZONTAL_ALIGNMENT_CENTER)
	ui.button(Rect2(44, 811, 452, 47), "CONTINUE", "continue_after_summary", null, UiKit.BLUE)

func draw_event(ui: UiKit, state: LifeGameState, ctx: Dictionary) -> void:
	ui.host.draw_rect(Rect2(0, 0, 540, 960), Color(0.03, 0.08, 0.14, 0.74))
	var event: Dictionary = ctx.get("event", {})
	var tone := str(event.get("tone", "ordinary"))
	var color := {"positive":UiKit.TEAL, "negative":UiKit.RED, "difficult":UiKit.PURPLE, "ordinary":UiKit.BLUE}.get(tone, UiKit.BLUE) as Color
	ui.panel(Rect2(20, 72, 500, 812), UiKit.WHITE, color.lightened(0.12), 24, 3)
	ui.host.draw_rect(Rect2(20, 72, 500, 129), color.darkened(0.12))
	ui.icon_badge(Vector2(72, 136), 30, str(event.get("icon", "?")), color)
	ui.text(str(event.get("title", "A choice appears")), Vector2(120, 130), 25, UiKit.WHITE)
	ui.text(tone.to_upper() + " EVENT", Vector2(120, 158), 11, Color(1,1,1,0.72))
	ui.paragraph(str(event.get("text", event.get("description", "Something unexpected changes the shape of your week."))), Rect2(48, 228, 444, 112), 17, UiKit.INK, 24, 5)
	ui.text("WHAT DO YOU DO?", Vector2(48, 371), 13, UiKit.MUTED)
	var choices: Array = event.get("choices", [])
	var y := 391.0
	for i in mini(choices.size(), 4):
		var choice: Dictionary = choices[i]
		var rect := Rect2(43, y, 454, 93)
		var cost := int(choice.get("cost", choice.get("known_cost", 0)))
		var requirements: Dictionary = choice.get("requirements", {})
		var hours := int(choice.get("time_cost", requirements.get("weekly_time_min", 0)))
		var enabled := bool(choice.get("available", true)) and state.cash >= cost and state.weekly_time >= hours
		ui.panel(rect, Color("f8fafc"), color.lightened(0.16) if enabled else UiKit.LINE, 16, 2)
		ui.text(str(choice.get("text", choice.get("label", "Choose"))), Vector2(61, y + 31), 15, UiKit.INK)
		var detail_parts: Array[String] = []
		if cost > 0: detail_parts.append("Known cost: " + ui.money(cost))
		if hours > 0: detail_parts.append("%d hours" % hours)
		if bool(choice.get("uncertain", false)): detail_parts.append("Outcome uncertain")
		if not enabled and not str(choice.get("blocked_reason", "")).is_empty(): detail_parts.append(str(choice.get("blocked_reason")))
		if detail_parts.is_empty(): detail_parts.append("No known cost")
		ui.text(" • ".join(detail_parts), Vector2(61, y + 57), 11, UiKit.MUTED)
		ui.button(Rect2(405, y + 27, 72, 39), "CHOOSE", "resolve_event", {"event_id":event.get("id"), "choice_id":choice.get("id")}, color, enabled)
		y += 105.0
	ui.text("Some consequences return in later weeks.", Vector2(0, 848), 11, UiKit.MUTED, 540, HORIZONTAL_ALIGNMENT_CENTER)

func draw_message(ui: UiKit, ctx: Dictionary) -> void:
	ui.host.draw_rect(Rect2(0, 0, 540, 960), Color(0.03, 0.08, 0.14, 0.64))
	var success := bool(ctx.get("success", true))
	var color := UiKit.TEAL if success else UiKit.RED
	ui.panel(Rect2(34, 262, 472, 322), UiKit.WHITE, color.lightened(0.14), 22, 3)
	ui.icon_badge(Vector2(270, 326), 34, "✓" if success else "!", color)
	ui.text(str(ctx.get("title", "Done")), Vector2(54, 393), 24, UiKit.INK, 432, HORIZONTAL_ALIGNMENT_CENTER)
	ui.paragraph(str(ctx.get("body", "Your choice has been recorded.")), Rect2(72, 420, 396, 75), 15, UiKit.MUTED, 22, 3)
	ui.button(Rect2(76, 516, 388, 48), "OK", "close_message", null, color)
