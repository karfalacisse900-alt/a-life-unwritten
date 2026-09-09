class_name PeoplePage
extends RefCounted

const PORTRAIT = preload("res://scripts/ui/PortraitRenderer.gd")

func draw(ui: UiKit, state: LifeGameState, ctx: Dictionary) -> void:
	ui.host.draw_rect(Rect2(0, 0, 540, 960), UiKit.BG)
	if str(ctx.get("person_id", "")).is_empty():
		_draw_list(ui, state, ctx)
	else:
		_draw_detail(ui, state, ctx)

func _draw_list(ui: UiKit, state: LifeGameState, ctx: Dictionary) -> void:
	var definitions: Dictionary = ctx.get("people_by_id", {})
	var scroll := float(ctx.get("scroll", 0.0))
	var y := 170.0 - scroll
	for rel: Dictionary in state.relationships:
		var pid := str(rel.get("person_id", rel.get("id", "")))
		var person: Dictionary = definitions.get(pid, rel)
		if y + 123 > 159 and y < 802:
			ui.avatar(Rect2(24, y + 9, 84, 100), str(person.get("name", "Someone")), PORTRAIT.npc_index(person))
			ui.heading(str(person.get("name", "Someone")), Vector2(125, y + 31), 23, UiKit.INK, 346)
			ui.text(str(rel.get("status", person.get("role", "contact"))).capitalize() + "  ·  " + str(person.get("occupation", "City resident")), Vector2(126, y + 51), 10, UiKit.MUTED, 369)
			var history: Array = rel.get("history", [])
			var memory := str((history.back() as Dictionary).get("text", "")) if not history.is_empty() else "You have a story together."
			ui.paragraph(memory, Rect2(126, y + 59, 355, 34), 11, UiKit.INK, 15, 2)
			ui.text("Closeness %d   /   Trust %d" % [int(rel.get("closeness", 0)), int(rel.get("trust", 0))], Vector2(126, y + 107), 9, UiKit.BLUE)
			ui.text("›", Vector2(491, y + 56), 26, UiKit.BLUE)
			ui.register(Rect2(18, y, 504, 121), "open_person", pid)
			ui.divider(y + 124, 24, 492)
		y += 139.0
	_mask_content(ui, 159)
	ui.header("People", "THE PEOPLE WHO SHAPE YOUR LIFE", state.cash, str(ctx.get("date_text", "")))
	ui.heading("Your circle", Vector2(22, 135), 24, UiKit.INK)
	ui.text("%d connections" % state.relationships.size(), Vector2(343, 134), 11, UiKit.MUTED, 173, HORIZONTAL_ALIGNMENT_RIGHT)
	ui.divider(151, 22, 496)

func _draw_detail(ui: UiKit, state: LifeGameState, ctx: Dictionary) -> void:
	var person: Dictionary = ctx.get("selected_person", {})
	var rel: Dictionary = ctx.get("selected_relationship", {})
	var scroll := float(ctx.get("scroll", 0.0))
	var y := 112.0 - scroll
	var person_name := str(person.get("name", "Someone"))
	if y + 258 > 94 and y < 802:
		ui.panel(Rect2(18, y, 504, 258), UiKit.WHITE, UiKit.LINE, 6, 1)
		ui.avatar(Rect2(35, y + 18, 130, 153), person_name, PORTRAIT.npc_index(person))
		ui.text(str(rel.get("status", person.get("role", "contact"))).to_upper(), Vector2(185, y + 32), 9, UiKit.BLUE)
		ui.heading(person_name, Vector2(185, y + 65), 26, UiKit.INK, 315)
		ui.text(str(person.get("pronouns", "")), Vector2(185, y + 86), 11, UiKit.MUTED)
		ui.paragraph(str(person.get("bio", "A person whose story is tied to yours.")), Rect2(185, y + 100, 309, 74), 12, UiKit.INK, 18, 4)
		ui.divider(y + 187, 35, 467)
		var values := [int(rel.get("closeness", 0)), int(rel.get("trust", 0)), int(rel.get("tension", 0))]
		var names := ["CLOSENESS", "TRUST", "TENSION"]
		for i in 3:
			var x := 35.0 + i * 162.0
			ui.text(str(names[i]), Vector2(x, y + 209), 9, UiKit.MUTED)
			ui.text(str(values[i]), Vector2(x, y + 235), 20, UiKit.INK)
			ui.host.draw_rect(Rect2(x + 41, y + 225, 103, 4), UiKit.LINE)
			ui.host.draw_rect(Rect2(x + 41, y + 225, float(values[i]) * 1.03, 4), UiKit.RED if i == 2 and values[i] > 40 else UiKit.BLUE)
	y += 281.0
	ui.heading("Make time", Vector2(22, y + 23), 24, UiKit.INK)
	ui.text("%dh available this week" % state.weekly_time, Vector2(325, y + 20), 10, UiKit.MUTED, 191, HORIZONTAL_ALIGNMENT_RIGHT)
	ui.divider(y + 37, 22, 496)
	y += 46.0
	var actions: Array = ctx.get("available_actions", [])
	for action: Dictionary in actions:
		if y + 62 > 94 and y < 802:
			var available := bool(action.get("available", true))
			ui.text(str(action.get("label", "Relationship action")), Vector2(25, y + 22), 14, UiKit.INK)
			var detail := "%d hours" % int(action.get("hours", 0))
			if int(action.get("cost", 0)) > 0: detail += "  ·  " + ui.money(int(action.get("cost", 0)))
			if not available: detail = str(action.get("blocked_reason", "Unavailable"))
			ui.text(detail, Vector2(25, y + 43), 10, UiKit.MUTED if available else UiKit.RED, 368)
			ui.button(Rect2(418, y + 6, 96, 43), "CHOOSE", "person_action", {"person_id":str(person.get("id", "")), "action_id":str(action.get("id", ""))}, UiKit.BLUE_DARK, available)
			ui.divider(y + 60, 24, 490)
		y += 68.0
	y += 16.0
	var rel_history: Array = rel.get("history", [])
	ui.heading("Shared history", Vector2(22, y + 24), 24, UiKit.INK)
	y += 45.0
	if rel_history.is_empty():
		ui.paragraph("No defining moment yet. Your choices will be remembered.", Rect2(24, y, 470, 48), 12, UiKit.MUTED)
	else:
		for i in range(rel_history.size() - 1, maxi(-1, rel_history.size() - 5), -1):
			var memory: Dictionary = rel_history[i]
			ui.text("WEEK %d" % (int(memory.get("week_index", 0)) + 1), Vector2(24, y + 13), 9, UiKit.MUTED)
			ui.paragraph(str(memory.get("text", "")), Rect2(104, y, 402, 50), 12, UiKit.INK, 18, 2)
			y += 60.0
	_mask_content(ui, 94)
	ui.sub_header(person_name, str(person.get("occupation", "City resident")), UiKit.BLUE, "close_person")

func _mask_content(ui: UiKit, top: float) -> void:
	var viewport := Rect2(0, top, 540, 802 - top)
	for i in range(ui.hits.size() - 1, -1, -1):
		var rect: Rect2 = ui.hits[i].get("rect", Rect2())
		if not rect.intersects(viewport): ui.hits.remove_at(i)
		else: ui.hits[i]["rect"] = rect.intersection(viewport)
	ui.host.draw_rect(Rect2(0, 0, 540, top), UiKit.BG)
	ui.host.draw_rect(Rect2(0, 802, 540, 158), UiKit.BG)
