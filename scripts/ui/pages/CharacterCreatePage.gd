class_name CharacterCreatePage
extends RefCounted

func draw(ui: UiKit, _state: LifeGameState, ctx: Dictionary) -> void:
	ui.host.draw_rect(Rect2(0, 0, 540, 960), UiKit.BG)
	ui.host.draw_rect(Rect2(0, 0, 540, 104), UiKit.WHITE)
	ui.host.draw_line(Vector2(0, 103), Vector2(540, 103), UiKit.LINE, 1.0)
	ui.text("AU", Vector2(24, 55), 26, UiKit.BLUE_DARK)
	ui.host.draw_line(Vector2(72, 26), Vector2(72, 76), UiKit.LINE, 1.0)
	ui.heading("A Life Unwritten", Vector2(91, 49), 26, UiKit.INK)
	ui.text("YOUR LIFE, ONE WEEK AT A TIME", Vector2(92, 72), 9, UiKit.MUTED)
	if ctx.get("welcome", false):
		_draw_welcome(ui, ctx)
	else:
		_draw_creator(ui, ctx)

func _draw_welcome(ui: UiKit, ctx: Dictionary) -> void:
	ui.text("MAKE SOMETHING OF IT", Vector2(28, 148), 10, UiKit.BLUE)
	ui.heading("A life of your own.", Vector2(26, 199), 39, UiKit.INK)
	ui.paragraph("Find your people. Build your career. Take a chance. The life ahead is shaped by the choices you make.", Rect2(28, 220, 472, 62), 15, UiKit.MUTED, 22, 3)
	ui.avatar(Rect2(29, 308, 147, 166), "Alex", 5)
	ui.avatar(Rect2(196, 292, 147, 184), "Maya", 2)
	ui.avatar(Rect2(363, 313, 147, 163), "Samira", 4)
	ui.text("Every face has a story. Yours starts at eighteen.", Vector2(28, 505), 12, UiKit.MUTED)
	var features := [
		{"mark":"01", "title":"Make a living", "body":"Study, work, build a business. Find your own way."},
		{"mark":"02", "title":"Make it yours", "body":"A first apartment, your own car, a growing collection."},
		{"mark":"03", "title":"Make connections", "body":"Show up for people. They remember the choices you make."}
	]
	for i in features.size():
		var feature: Dictionary = features[i]
		var y := 538.0 + i * 68.0
		ui.text(str(feature.mark), Vector2(28, y + 22), 11, UiKit.MUTED)
		ui.text(str(feature.title), Vector2(72, y + 20), 16, UiKit.INK)
		ui.text(str(feature.body), Vector2(72, y + 42), 11, UiKit.MUTED, 435)
		ui.divider(y + 57, 28, 482)
	var has_save: bool = ctx.get("has_save", false)
	ui.button(Rect2(28, 780, 234, 56), "CONTINUE YOUR LIFE", "continue_game", null, UiKit.BLUE_DARK, has_save)
	ui.button(Rect2(277, 780, 234, 56), "START A NEW LIFE", "new_game", null, UiKit.BLUE)
	ui.text("Everything begins with a choice.", Vector2(0, 896), 11, UiKit.MUTED, 540, HORIZONTAL_ALIGNMENT_CENTER)

func _draw_creator(ui: UiKit, ctx: Dictionary) -> void:
	ui.panel(Rect2(18, 122, 504, 789), UiKit.WHITE, UiKit.LINE, 6, 1)
	ui.heading("Who will you become?", Vector2(36, 164), 28, UiKit.INK)
	ui.text("YOUR NAME", Vector2(36, 201), 10, UiKit.MUTED)
	var name_value := str(ctx.get("name", "Alex Rivera"))
	var appearance := int(ctx.get("appearance", 0))
	ui.avatar(Rect2(401, 185, 93, 101), name_value, appearance)
	var active := bool(ctx.get("name_active", false))
	ui.panel(Rect2(36, 214, 332, 50), UiKit.WHITE, UiKit.BLUE if active else UiKit.LINE, 5, 1)
	ui.text(name_value + ("|" if active else ""), Vector2(51, 246), 17, UiKit.INK)
	ui.register(Rect2(36, 210, 336, 58), "edit_name")
	ui.text("CHOOSE YOUR PORTRAIT", Vector2(36, 294), 10, UiKit.MUTED)
	ui.text("%d / 8" % (appearance + 1), Vector2(334, 294), 10, UiKit.BLUE)
	for i in 8:
		var frame := Rect2(37 + i * 58, 309, 49, 58)
		ui.avatar(frame, name_value, i)
		if i == appearance:
			ui.host.draw_rect(frame.grow(4), UiKit.BLUE, false, 2)
			ui.host.draw_rect(Rect2(frame.position.x, frame.end.y + 7, frame.size.x, 3), UiKit.BLUE)
		ui.register(frame.grow(4), "set_appearance", i)

	ui.text("PRONOUNS", Vector2(36, 404), 10, UiKit.MUTED)
	var pronouns := str(ctx.get("pronouns", "they/them"))
	ui.chip(Rect2(36, 416, 145, 40), "they / them", pronouns == "they/them", "set_pronouns", "they/them")
	ui.chip(Rect2(191, 416, 145, 40), "she / her", pronouns == "she/her", "set_pronouns", "she/her")
	ui.chip(Rect2(346, 416, 145, 40), "he / him", pronouns == "he/him", "set_pronouns", "he/him")

	ui.text("WHERE YOU BEGIN", Vector2(36, 491), 10, UiKit.MUTED)
	ui.text("Each has a tradeoff", Vector2(340, 491), 10, UiKit.MUTED, 152, HORIZONTAL_ALIGNMENT_RIGHT)
	var backgrounds: Array = ctx.get("backgrounds", [])
	var selected_bg := str(ctx.get("background", "family_couch"))
	for i in mini(backgrounds.size(), 4):
		var bg: Dictionary = backgrounds[i]
		var rect := Rect2(36 + (i % 2) * 234, 505 + (i / 2) * 92, 222, 80)
		var selected := str(bg.get("id", "")) == selected_bg
		ui.panel(rect, Color("edf2f3") if selected else UiKit.WHITE, UiKit.BLUE if selected else UiKit.LINE, 5, 1)
		ui.text(str(bg.get("name", "Background")), rect.position + Vector2(12, 24), 14, UiKit.INK, 198)
		ui.paragraph(str(bg.get("description", "")), Rect2(rect.position + Vector2(12, 33), Vector2(198, 36)), 10, UiKit.MUTED, 14, 2)
		ui.register(rect, "set_background", bg.get("id"))

	ui.text("YOUR STARTING TRAIT", Vector2(36, 712), 10, UiKit.MUTED)
	var traits: Array = ctx.get("traits", [])
	var selected_traits: Array = ctx.get("selected_traits", [])
	for i in mini(traits.size(), 4):
		var trait_def: Dictionary = traits[i]
		var rect := Rect2(36 + (i % 2) * 234, 726 + (i / 2) * 46, 222, 38)
		var selected := selected_traits.has(str(trait_def.get("id", "")))
		ui.chip(rect, str(trait_def.get("name", "Trait")), selected, "toggle_trait", trait_def.get("id"))

	var valid := not name_value.strip_edges().is_empty() and selected_traits.size() == 1
	ui.button(Rect2(36, 837, 456, 56), "CHOOSE YOUR FIRST HOME  ›", "finish_character", null, UiKit.BLUE_DARK, valid)
