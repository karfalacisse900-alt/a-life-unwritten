class_name HousingSetupPage
extends RefCounted

func draw(ui: UiKit, state: LifeGameState, ctx: Dictionary) -> void:
	ui.host.draw_rect(Rect2(0, 0, 540, 960), UiKit.BG)
	var initial := bool(ctx.get("initial", true))
	ui.sub_header("Choose a first home" if initial else "Housing desk", "Housing changes bills, wellbeing, and opportunities", UiKit.PURPLE, str(ctx.get("back_action", "back_to_character")))
	ui.panel(Rect2(18, 112, 504, 90), UiKit.WHITE, UiKit.LINE, 8, 1)
	ui.icon_badge(Vector2(56, 157), 23, "$", UiKit.GOLD.darkened(0.13))
	ui.text("Starting cash", Vector2(93, 146), 12, UiKit.MUTED)
	ui.text(ui.money(state.cash), Vector2(93, 176), 25, UiKit.INK)
	ui.paragraph("Deposits are charged now. Rent follows the monthly calendar.", Rect2(244, 133, 252, 48), 12, UiKit.MUTED, 18, 2)

	var options: Array = ctx.get("housing_options", [])
	var eligibility: Dictionary = ctx.get("eligibility", {})
	var y := 222.0
	for i in mini(options.size(), 3):
		var home: Dictionary = options[i]
		var deposit := int(home.get("deposit", home.get("move_in_cost", 0)))
		var moving := int(home.get("moving_cost", 0))
		var move_total := deposit + moving
		var rent := int(home.get("monthly_rent", home.get("rent", 0)))
		var details: Dictionary = eligibility.get(str(home.get("id", "")), {})
		var enabled := bool(details.get("eligible", state.cash >= move_total))
		var rect := Rect2(18, y, 504, 174)
		var colors := [UiKit.TEAL, UiKit.BLUE, UiKit.PURPLE]
		ui.panel(rect, UiKit.WHITE, UiKit.LINE, 8, 1)
		ui.icon_badge(Vector2(60, y + 45), 25, ["F", "R", "A"][i], colors[i])
		ui.heading(str(home.get("name", home.get("title", "Home"))), Vector2(99, y + 40), 20, UiKit.INK)
		ui.text("%s move-in  •  %s / month" % [ui.money(move_total), ui.money(rent + int(home.get("monthly_utilities", 0)))], Vector2(99, y + 64), 12, UiKit.MUTED)
		ui.paragraph(str(home.get("description", home.get("summary", "A place to begin."))), Rect2(40, y + 81, 460, 42), 13, UiKit.MUTED, 18, 2)
		var benefit := str(home.get("tradeoff", home.get("benefit", home.get("effect", "Stable housing"))))
		if enabled:
			ui.paragraph(benefit, Rect2(40, y + 119, 300, 36), 10, colors[i], 14, 2)
		ui.button(Rect2(356, y + 121, 142, 38), "MOVE IN", "choose_housing", home.get("id"), colors[i], enabled)
		if not enabled:
			var reasons: Array = details.get("reasons", [])
			ui.paragraph(str(reasons[0]) if not reasons.is_empty() else "Not affordable", Rect2(40, y + 119, 300, 36), 9, UiKit.RED, 13, 2)
		y += 190.0

	ui.panel(Rect2(18, 805, 504, 86), UiKit.WHITE, UiKit.LINE, 8, 1)
	ui.text("NEXT: FIND YOUR FOOTING", Vector2(36, 838), 12, UiKit.BLUE)
	ui.text("After moving in, explore jobs and decide how to spend Week 1.", Vector2(36, 863), 13, UiKit.INK)
