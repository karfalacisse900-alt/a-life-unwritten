class_name AssetsPage
extends RefCounted

const TAB_TOP := 106.0
const CONTENT_TOP := 202.0
const CONTENT_BOTTOM := 802.0


func draw(ui: UiKit, state: LifeGameState, ctx: Dictionary) -> void:
	ui.host.draw_rect(Rect2(0, 0, 540, 960), UiKit.BG)
	var first_hit := ui.hits.size()
	var tab := str(ctx.get("asset_tab", "owned"))
	match tab:
		"market": _draw_market(ui, state, ctx)
		"ledger": _draw_ledger(ui, state, ctx)
		_: _draw_owned(ui, state, ctx)
	# Content cards can be partly visible while scrolling. Keep their hit targets
	# inside the viewport, and repaint the fixed chrome over any overflow.
	var content_hits: Array[Dictionary] = []
	for i in range(first_hit, ui.hits.size()):
		var hit: Dictionary = ui.hits[i]
		var hit_rect: Rect2 = hit.get("rect", Rect2())
		var clipped := hit_rect.intersection(Rect2(0, CONTENT_TOP, 540, CONTENT_BOTTOM-CONTENT_TOP))
		if clipped.has_area():
			hit["rect"] = clipped
			content_hits.append(hit)
	ui.hits.resize(first_hit)
	ui.hits.append_array(content_hits)
	ui.host.draw_rect(Rect2(0, 0, 540, CONTENT_TOP), UiKit.BG)
	ui.host.draw_rect(Rect2(0, CONTENT_BOTTOM, 540, 158), UiKit.BG)
	if tab == "market":
		_draw_market_section_tabs(ui, str(ctx.get("market_section", "portfolio")), str(ctx.get("asset_category", "")))
	if tab != "market":
		ui.chip(Rect2(18, TAB_TOP, 158, 40), "OWNED", tab == "owned", "asset_tab", "owned")
		ui.chip(Rect2(191, TAB_TOP, 158, 40), "MARKETS", tab == "market", "asset_tab", "market")
		ui.chip(Rect2(364, TAB_TOP, 158, 40), "BANKING", tab == "ledger", "asset_tab", "ledger")
	if tab == "owned":
		_draw_category_chips(ui, _selected_category(ctx,"all"))
	# Draw the fixed header last so a market card or clipped canvas operation can
	# never cover the title, cash, or date on a smaller mobile viewport.
	ui.header("ASSETS", "YOUR MONEY, COLLECTION & POSSIBILITIES", state.cash, str(ctx.get("date_text", "")))

func _draw_owned(ui: UiKit, state: LifeGameState, ctx: Dictionary) -> void:
	var category := _selected_category(ctx, "all")
	var y := 206.0 - float(ctx.get("scroll",0.0))
	var owned: Array = _filter_category(ctx.get("owned", []), category)
	y = _draw_portfolio_summary(ui, state, ctx, y)
	var security_holdings: Array = ctx.get("market_holdings", [])
	var owned_vehicle: Dictionary = ctx.get("owned_vehicle", {})
	var any_owned := not owned.is_empty()
	if category in ["all","investment"]:
		for holding in security_holdings:
			if holding is Dictionary:
				any_owned = true
				if _fully_visible(y,82): _draw_portfolio_holding(ui,holding,Rect2(18,y,504,82))
				y += 92
	if category in ["all","vehicle"] and not owned_vehicle.is_empty():
		any_owned = true
		if _fully_visible(y,270): _draw_owned_vehicle(ui,state,owned_vehicle,ctx.get("vehicle_summary",{}),Rect2(18,y,504,270))
		y += 282
	if not any_owned:
		_draw_empty_owned(ui, category, y)
	for item in owned:
		if item is Dictionary:
			if _fully_visible(y,220): _draw_owned_card(ui,item,ctx,Rect2(18,y,504,220))
			y += 232

func _draw_portfolio_summary(ui: UiKit, state: LifeGameState, ctx: Dictionary, y: float) -> float:
	var summary: Dictionary = ctx.get("market_summary",{})
	var vehicle: Dictionary = ctx.get("vehicle_summary",{})
	if _fully_visible(y,144):
		ui.panel(Rect2(18,y,504,144),UiKit.BLUE_DARK,UiKit.BLUE_DARK,12,0)
		ui.text("NET WORTH",Vector2(38,y+27),10,Color("c7d4ce"))
		ui.text(ui.money(int(ctx.get("net_worth",0))),Vector2(38,y+68),31,UiKit.WHITE)
		ui.text("What you own, less what you owe",Vector2(38,y+90),11,Color("c7d4ce"))
		ui.host.draw_line(Vector2(38,y+104),Vector2(502,y+104),Color(1,1,1,0.15),1)
		ui.text("SECURITIES  "+_format_cents(int(summary.get("market_value_cents",0))),Vector2(38,y+128),10,Color("e0e8e2"))
		ui.text("VEHICLE  "+ui.money(int(vehicle.get("vehicle_value",0))),Vector2(303,y+128),10,Color("e0e8e2"),199,HORIZONTAL_ALIGNMENT_RIGHT)
	return y+156

func _draw_empty_owned(ui: UiKit, category: String, y: float) -> void:
	if not _fully_visible(y,164): return
	ui.panel(Rect2(18,y,504,164),UiKit.WHITE,UiKit.LINE,12,1)
	ui.text("Start your collection",Vector2(38,y+37),21,UiKit.INK)
	ui.paragraph("Your investments, car, art and useful belongings live here. Browse the market to find a first piece.",Rect2(38,y+53,454,47),13,UiKit.MUTED,19,2)
	ui.button(Rect2(38,y+112,189,36),"Browse the market","asset_tab","market",UiKit.BLUE)

func _draw_owned_card(ui: UiKit, item: Dictionary, ctx: Dictionary, rect: Rect2) -> void:
	var category_id := str(item.get("category_id","equipment"))
	var accent := _accent_for(category_id,ctx)
	ui.panel(rect,UiKit.WHITE,UiKit.LINE,12,1)
	AssetIllustrations.draw(ui,item,Rect2(rect.position+Vector2(16,16),Vector2(134,128)))
	ui.text(str(item.get("name","Owned item")),rect.position+Vector2(168,33),17,UiKit.INK,318)
	ui.text(str(item.get("artist",_category_label(category_id))),rect.position+Vector2(168,55),11,UiKit.MUTED,318)
	ui.text(ui.money(int(item.get("market_value",0))),rect.position+Vector2(168,87),23,UiKit.INK)
	var gain := int(item.get("unrealized_gain",0))
	ui.text(("+" if gain>0 else "")+ui.money(gain)+" since purchase",rect.position+Vector2(168,109),11,_pnl_color(gain))
	ui.text("PAID "+ui.money(int(item.get("cost_basis",0))),rect.position+Vector2(168,135),9,UiKit.MUTED)
	ui.divider(rect.position.y+156,rect.position.x+16,rect.size.x-32)
	var condition := clampi(int(item.get("condition",100)),0,100)
	ui.text("Condition %d%% · Upkeep %s/mo" % [condition,ui.money(int(item.get("monthly_upkeep",0)))],rect.position+Vector2(18,179),10,UiKit.MUTED)
	_draw_sparkline(ui,item.get("price_history",[]),Rect2(rect.position+Vector2(18,191),Vector2(208,12)),accent)
	var maintain := condition<100 and _eligibility(ctx,"maintenance",str(item.get("id","")),true)
	ui.button(Rect2(rect.position+Vector2(298,173),Vector2(82,33)),"Care","maintain_asset",str(item.get("id","")),UiKit.TEAL,maintain)
	ui.button(Rect2(rect.position+Vector2(388,173),Vector2(98,33)),"Sell","sell_asset",str(item.get("id","")),UiKit.BLUE_DARK,_eligibility(ctx,"sell_eligibility",str(item.get("id","")),true))

func _draw_market(ui: UiKit, state: LifeGameState, ctx: Dictionary) -> void:
	var section := str(ctx.get("market_section", "portfolio"))
	if not section in ["portfolio", "stock", "etf", "crypto", "bond", "things"]:
		section = "portfolio"
	match section:
		"portfolio":
			_draw_market_portfolio(ui, ctx)
		"things":
			_draw_physical_market(ui, state, ctx)
		_:
			_draw_security_market(ui, state, ctx, section)


func _draw_market_section_tabs(ui: UiKit, selected: String, category: String = "") -> void:
	var mode := "portfolio" if selected == "portfolio" else ("shop" if selected == "things" else ("money" if selected == "ledger" else "trade"))
	var outer := Rect2(18, 106, 504, 38)
	var modes: Array[Dictionary] = [
		{"id":"portfolio", "label":"PORTFOLIO"},
		{"id":"trade", "label":"TRADE", "arg":"stock"},
		{"id":"shop", "label":"SHOP", "arg":"things"},
		{"id":"money", "label":"MONEY", "arg":"ledger", "action":"asset_tab"},
	]
	var width := outer.size.x / float(modes.size())
	for index in modes.size():
		var item: Dictionary = modes[index]
		var item_id := str(item.get("id", ""))
		var rect := Rect2(outer.position.x + width * index, outer.position.y, width, outer.size.y)
		if item_id == mode:
			ui.panel(rect.grow(-2), UiKit.BLUE_DARK, UiKit.BLUE_DARK, 7, 0)
		ui.text(str(item.get("label", "")), Vector2(rect.position.x, rect.position.y + 24), 10, UiKit.WHITE if item_id == mode else UiKit.MUTED, rect.size.x, HORIZONTAL_ALIGNMENT_CENTER)
		ui.register(rect, str(item.get("action", "market_section")), item.get("arg", item_id))

	if mode == "portfolio": return
	if mode == "money": return
	var choices: Array[Dictionary] = []
	if mode == "trade":
		choices = [{"id":"stock", "label":"Stocks"}, {"id":"crypto", "label":"Crypto"}, {"id":"etf", "label":"Funds"}, {"id":"bond", "label":"Bonds"}]
	else:
		choices = [{"id":"vehicle", "label":"Cars"}, {"id":"collectible", "label":"Art"}, {"id":"property", "label":"Homes"}, {"id":"equipment", "label":"Gear"}]
	for index in choices.size():
		var choice: Dictionary = choices[index]
		var choice_id := str(choice.get("id", ""))
		var selected_choice := choice_id == selected if mode == "trade" else choice_id == category
		var rect := Rect2(18 + index * 126, 157, 118, 32)
		ui.chip(rect, str(choice.get("label", "")), selected_choice, "market_section" if mode == "trade" else "asset_category", choice_id)


func _draw_security_market(ui: UiKit, state: LifeGameState, ctx: Dictionary, asset_class: String) -> void:
	var scroll := float(ctx.get("scroll", 0.0))
	var y := CONTENT_TOP + 6.0 - scroll
	var accent := _market_class_color(asset_class)
	var status: Dictionary = ctx.get("market_status", {}) if ctx.get("market_status", {}) is Dictionary else {}
	var class_status: Dictionary = status.get("crypto", {}) if asset_class == "crypto" and status.get("crypto", {}) is Dictionary else {}
	if class_status.is_empty() and status.get("equities", {}) is Dictionary:
		class_status = status.get("equities", {})
	var order_status: Dictionary = ctx.get("market_order_status", {}) if ctx.get("market_order_status", {}) is Dictionary else {}
	if _fully_visible(y, 46):
		ui.panel(Rect2(18, y, 504, 46), UiKit.WHITE, UiKit.LINE, 10, 1)
		ui.host.draw_circle(Vector2(35, y + 23), 4, UiKit.GREEN)
		ui.text(str(class_status.get("label", "ORDERS ACCEPTED")).to_upper(), Vector2(47, y + 27), 10, UiKit.INK)
		ui.text("%d OF %d ORDERS LEFT" % [int(order_status.get("remaining", 0)), int(order_status.get("limit", 0))], Vector2(313, y + 27), 9, UiKit.MUTED, 189, HORIZONTAL_ALIGNMENT_RIGHT)
	y += 58.0

	var instruments: Array = []
	var raw_instruments: Variant = ctx.get("market_instruments", [])
	if raw_instruments is Array:
		for raw_item in raw_instruments:
			if raw_item is Dictionary and str(raw_item.get("asset_class", "")) == asset_class:
				instruments.append(raw_item)
	if instruments.is_empty():
		if _fully_visible(y, 94):
			ui.panel(Rect2(18, y, 504, 94), UiKit.WHITE, UiKit.LINE, 12, 1)
			ui.text("No instruments available", Vector2(36, y + 39), 16, UiKit.INK)
			ui.text("This market category currently has no listings.", Vector2(36, y + 64), 11, UiKit.MUTED)
		return

	for raw_item in instruments:
		if not raw_item is Dictionary:
			continue
		var item: Dictionary = raw_item
		var card_height := 126.0
		if _fully_visible(y, card_height):
			_draw_security_row(ui, state, item, order_status, accent, Rect2(18, y, 504, card_height))
		y += card_height + 10.0


func _draw_security_row(ui: UiKit, state: LifeGameState, item: Dictionary, order_status: Dictionary, accent: Color, rect: Rect2) -> void:
	var symbol := str(item.get("symbol", item.get("id", ""))).to_upper()
	var price_cents := int(item.get("price_cents", 0))
	var change_bp := int(item.get("change_basis_points", 0))
	var change_color := UiKit.GREEN if change_bp >= 0 else UiKit.RED
	var owned_units := maxi(0, int(item.get("owned_quantity_units", 0)))
	var owned_label := str(item.get("owned_quantity_label", "0"))
	var history: Variant = item.get("price_history_cents", [])
	var remaining_orders := int(order_status.get("remaining", 0))
	var buy_enabled := remaining_orders > 0 and int(state.cash) > 0
	var sell_enabled := remaining_orders > 0 and owned_units > 0

	ui.panel(rect, UiKit.WHITE, UiKit.LINE, 12, 1)
	ui.host.draw_rect(Rect2(rect.position + Vector2(0, 12), Vector2(3, rect.size.y - 24)), accent)
	AssetIllustrations.draw_security(ui, item, Rect2(rect.position + Vector2(18, 10), Vector2(55, 48)))
	ui.text(symbol, rect.position + Vector2(18, 56), 8, accent.darkened(0.18), 55, HORIZONTAL_ALIGNMENT_CENTER)
	ui.text(str(item.get("name", symbol)), rect.position + Vector2(84, 29), 14, UiKit.INK, 235)
	ui.text(str(item.get("sector", "")), rect.position + Vector2(84, 47), 9, UiKit.MUTED, 235)
	ui.text(_format_cents(price_cents), rect.position + Vector2(335, 29), 18, UiKit.INK, 145, HORIZONTAL_ALIGNMENT_RIGHT)
	ui.text(("+" if change_bp > 0 else "") + "%.2f%%" % (float(change_bp) / 100.0), rect.position + Vector2(365, 48), 10, change_color, 115, HORIZONTAL_ALIGNMENT_RIGHT)
	ui.divider(rect.position.y + 58, rect.position.x + 18, rect.size.x - 36)
	_draw_sparkline(ui, history, Rect2(rect.position + Vector2(19, 72), Vector2(152, 30)), change_color)
	ui.text("POSITION", rect.position + Vector2(190, 78), 8, UiKit.MUTED)
	ui.text(owned_label if owned_units > 0 else "None", rect.position + Vector2(190, 96), 11, UiKit.INK, 125)
	ui.text("Choose quantity to trade", rect.position + Vector2(190, 114), 9, UiKit.MUTED, 135)
	var order_action := "buy_market" if buy_enabled or not sell_enabled else "sell_market"
	ui.button(Rect2(rect.position + Vector2(332, 73), Vector2(148, 35)), "Trade", order_action, symbol, accent, buy_enabled or sell_enabled)


func _draw_market_portfolio(ui: UiKit, ctx: Dictionary) -> void:
	var scroll := float(ctx.get("scroll", 0.0))
	var y := CONTENT_TOP + 6.0 - scroll
	var summary: Dictionary = ctx.get("market_summary", {}) if ctx.get("market_summary", {}) is Dictionary else {}
	var holdings: Array = ctx.get("market_holdings", []) if ctx.get("market_holdings", []) is Array else []
	var market_value := int(summary.get("market_value_cents", 0))
	var unrealized := int(summary.get("unrealized_pnl_cents", 0))
	var realized := int(summary.get("realized_pnl_cents", 0))
	var broker_cash := int(summary.get("broker_cash_cents", 0))
	var cost_basis := int(summary.get("cost_basis_cents", 0))

	if _fully_visible(y, 126):
		ui.panel(Rect2(18, y, 504, 126), UiKit.WHITE, UiKit.LINE, 12, 1)
		ui.text("INVESTMENT PORTFOLIO", Vector2(36, y + 26), 9, UiKit.MUTED)
		ui.text(_format_cents(market_value), Vector2(36, y + 61), 28, UiKit.INK)
		ui.text("MARKET VALUE", Vector2(37, y + 80), 8, UiKit.MUTED)
		ui.text("UNREALIZED", Vector2(324, y + 25), 8, UiKit.MUTED)
		ui.text(_signed_cents(unrealized), Vector2(324, y + 47), 15, _pnl_color(unrealized), 160, HORIZONTAL_ALIGNMENT_RIGHT)
		ui.text("REALIZED", Vector2(324, y + 70), 8, UiKit.MUTED)
		ui.text(_signed_cents(realized), Vector2(324, y + 92), 15, _pnl_color(realized), 160, HORIZONTAL_ALIGNMENT_RIGHT)
		ui.divider(y + 99, 36, 448)
		ui.text("COST BASIS  %s" % _format_cents(cost_basis), Vector2(36, y + 118), 9, UiKit.MUTED)
		ui.text("BROKER CASH  %s" % _format_cents(broker_cash), Vector2(300, y + 118), 9, UiKit.MUTED, 184, HORIZONTAL_ALIGNMENT_RIGHT)
	y += 138.0

	y = _draw_market_allocation(ui, summary, y)
	if _fully_visible(y, 24):
		ui.text("HOLDINGS", Vector2(20, y + 16), 10, UiKit.MUTED)
		ui.text("%d POSITIONS" % holdings.size(), Vector2(350, y + 16), 9, UiKit.MUTED, 170, HORIZONTAL_ALIGNMENT_RIGHT)
	y += 32.0
	if holdings.is_empty():
		if _fully_visible(y, 88):
			ui.panel(Rect2(18, y, 504, 88), UiKit.WHITE, UiKit.LINE, 12, 1)
			ui.text("No securities held", Vector2(36, y + 36), 15, UiKit.INK)
			ui.text("Choose Stocks, Funds, Crypto, or Bonds to place an order.", Vector2(36, y + 61), 11, UiKit.MUTED)
		y += 100.0
	else:
		for raw_holding in holdings:
			if not raw_holding is Dictionary:
				continue
			var holding: Dictionary = raw_holding
			if _fully_visible(y, 82):
				_draw_portfolio_holding(ui, holding, Rect2(18, y, 504, 82))
			y += 92.0

	var news: Array = ctx.get("market_news", []) if ctx.get("market_news", []) is Array else []
	if _fully_visible(y, 24):
		ui.text("MARKET BRIEF", Vector2(20, y + 16), 10, UiKit.MUTED)
	y += 32.0
	for index in mini(4, news.size()):
		var raw_news: Variant = news[index]
		if not raw_news is Dictionary:
			continue
		var story: Dictionary = raw_news
		if _fully_visible(y, 72):
			_draw_market_news_row(ui, story, Rect2(18, y, 504, 72))
		y += 80.0


func _draw_market_allocation(ui: UiKit, summary: Dictionary, y: float) -> float:
	var allocation: Dictionary = summary.get("allocation_by_class_cents", {}) if summary.get("allocation_by_class_cents", {}) is Dictionary else {}
	var total := maxi(0, int(summary.get("market_value_cents", 0)))
	var height := 104.0
	if _fully_visible(y, height):
		ui.panel(Rect2(18, y, 504, height), UiKit.WHITE, UiKit.LINE, 12, 1)
		ui.text("ALLOCATION", Vector2(36, y + 24), 9, UiKit.MUTED)
		var bar := Rect2(36, y + 36, 468, 10)
		ui.panel(bar, Color("edf0f3"), Color("edf0f3"), 5, 0)
		var cursor := bar.position.x
		var classes := ["stock", "etf", "bond", "crypto"]
		for asset_class in classes:
			var value := maxi(0, int(allocation.get(asset_class, 0)))
			var width := 0.0 if total <= 0 else bar.size.x * float(value) / float(total)
			if width > 0.0:
				ui.host.draw_rect(Rect2(cursor, bar.position.y, width, bar.size.y), _market_class_color(asset_class))
			cursor += width
		for index in classes.size():
			var asset_class: String = classes[index]
			var value := maxi(0, int(allocation.get(asset_class, 0)))
			var percent := 0.0 if total <= 0 else float(value) * 100.0 / float(total)
			var col := index % 2
			var row := index / 2
			var x := 36.0 + col * 234.0
			var label_y := y + 66.0 + row * 20.0
			ui.host.draw_circle(Vector2(x + 4, label_y - 3), 4, _market_class_color(asset_class))
			ui.text("%s  %.1f%%" % [_market_class_label(asset_class), percent], Vector2(x + 15, label_y), 9, UiKit.INK)
	return y + height + 12.0


func _draw_portfolio_holding(ui: UiKit, holding: Dictionary, rect: Rect2) -> void:
	var symbol := str(holding.get("symbol", ""))
	var accent := _market_class_color(str(holding.get("asset_class", "stock")))
	var pnl := int(holding.get("unrealized_pnl_cents", 0))
	ui.panel(rect, UiKit.WHITE, UiKit.LINE, 11, 1)
	ui.panel(Rect2(rect.position + Vector2(17, 16), Vector2(54, 25)), Color("eef2f6"), Color("d7dee7"), 6, 1)
	ui.text(symbol, rect.position + Vector2(17, 33), 10, accent.darkened(0.18), 54, HORIZONTAL_ALIGNMENT_CENTER)
	ui.text(str(holding.get("name", symbol)), rect.position + Vector2(83, 30), 13, UiKit.INK, 230)
	ui.text(str(holding.get("quantity_label", "")), rect.position + Vector2(83, 53), 9, UiKit.MUTED, 230)
	ui.text(_format_cents(int(holding.get("market_value_cents", 0))), rect.position + Vector2(337, 30), 15, UiKit.INK, 147, HORIZONTAL_ALIGNMENT_RIGHT)
	ui.text(_signed_cents(pnl), rect.position + Vector2(337, 53), 10, _pnl_color(pnl), 147, HORIZONTAL_ALIGNMENT_RIGHT)
	_draw_sparkline(ui, holding.get("price_history_cents", []), Rect2(rect.position + Vector2(18, 59), Vector2(294, 10)), accent)


func _draw_market_news_row(ui: UiKit, story: Dictionary, rect: Rect2) -> void:
	var tone := str(story.get("tone", "neutral"))
	var accent := UiKit.GREEN if tone == "positive" else (UiKit.RED if tone == "negative" else UiKit.BLUE)
	ui.panel(rect, UiKit.WHITE, UiKit.LINE, 10, 1)
	ui.host.draw_circle(rect.position + Vector2(20, 23), 4, accent)
	ui.text(str(story.get("headline", "Market update")), rect.position + Vector2(34, 27), 12, UiKit.INK, 448)
	ui.text(str(story.get("body", "")), rect.position + Vector2(34, 51), 9, UiKit.MUTED, 448)


func _draw_physical_market(ui: UiKit, state: LifeGameState, ctx: Dictionary) -> void:
	var category := _selected_category(ctx, "vehicle")
	if not category in ["vehicle", "property", "collectible", "equipment"]:
		category = "vehicle"
	var scroll := float(ctx.get("scroll", 0.0))
	var y := CONTENT_TOP + 6.0 - scroll
	if category == "vehicle":
		_draw_vehicle_market(ui, state, ctx, y)
		return
	var source: Variant = ctx.get("physical_catalog", ctx.get("catalog", []))
	var catalog: Array = _filter_category(source, category)
	if catalog.is_empty():
		if _fully_visible(y, 88):
			ui.panel(Rect2(18, y, 504, 88), UiKit.WHITE, UiKit.LINE, 12, 1)
			ui.text("No items currently listed", Vector2(36, y + 36), 15, UiKit.INK)
			ui.text("Choose another category to continue browsing.", Vector2(36, y + 61), 11, UiKit.MUTED)
		return
	for raw_item in catalog:
		if not raw_item is Dictionary:
			continue
		var item: Dictionary = raw_item
		if _fully_visible(y, 218):
			_draw_market_card(ui, state, item, ctx, Rect2(18, y, 504, 218))
		y += 230.0


func _draw_vehicle_market(ui: UiKit, state: LifeGameState, ctx: Dictionary, y: float) -> void:
	var owned: Dictionary = ctx.get("owned_vehicle", {}) if ctx.get("owned_vehicle", {}) is Dictionary else {}
	var summary: Dictionary = ctx.get("vehicle_summary", {}) if ctx.get("vehicle_summary", {}) is Dictionary else {}
	if not owned.is_empty():
		if _fully_visible(y, 270):
			_draw_owned_vehicle(ui, state, owned, summary, Rect2(18, y, 504, 270))
		y += 282.0

	var catalog: Array = ctx.get("vehicle_catalog", []) if ctx.get("vehicle_catalog", []) is Array else []
	if catalog.is_empty():
		if _fully_visible(y, 88):
			ui.panel(Rect2(18, y, 504, 88), UiKit.WHITE, UiKit.LINE, 12, 1)
			ui.text("No vehicles currently listed", Vector2(36, y + 36), 15, UiKit.INK)
			ui.text("Dealer inventory will appear here when available.", Vector2(36, y + 61), 11, UiKit.MUTED)
		return
	for raw_vehicle in catalog:
		if not raw_vehicle is Dictionary:
			continue
		var vehicle: Dictionary = raw_vehicle
		if _fully_visible(y, 242):
			_draw_vehicle_listing(ui, state, vehicle, not owned.is_empty(), Rect2(18, y, 504, 242))
		y += 254.0


func _draw_owned_vehicle(ui: UiKit, state: LifeGameState, owned: Dictionary, summary: Dictionary, rect: Rect2) -> void:
	var operational := bool(summary.get("operational",owned.get("operational",true)))
	var condition := int(summary.get("condition",owned.get("condition_score",100)))
	var arrears := int(summary.get("arrears",0))
	var repair_cost := maxi(350,roundi(float(owned.get("purchase_price",0))*0.035))
	ui.panel(rect,UiKit.WHITE,UiKit.LINE,12,1)
	AssetIllustrations.draw_car(ui,owned,Rect2(rect.position+Vector2(16,16),Vector2(188,94)))
	ui.text("YOUR VEHICLE",rect.position+Vector2(220,29),9,UiKit.MUTED)
	ui.paragraph(str(owned.get("name","Vehicle")),Rect2(rect.position+Vector2(220,39),Vector2(266,36)),16,UiKit.INK,19,2)
	ui.text(ui.money(int(summary.get("vehicle_value",owned.get("current_value",0)))),rect.position+Vector2(220,97),23,UiKit.INK)
	ui.divider(rect.position.y+123,rect.position.x+16,rect.size.x-32)
	_draw_vehicle_metric(ui,rect.position+Vector2(18,140),"LOAN BALANCE",ui.money(int(summary.get("loan_balance",0))),142)
	_draw_vehicle_metric(ui,rect.position+Vector2(180,140),"MONTHLY PAYMENT",ui.money(int(summary.get("monthly_payment",0))),142)
	_draw_vehicle_metric(ui,rect.position+Vector2(342,140),"EQUITY",ui.money(int(summary.get("equity",0))),142)
	_draw_vehicle_metric(ui,rect.position+Vector2(18,185),"INSURANCE / MO",ui.money(int(summary.get("insurance_monthly",owned.get("insurance_monthly",0)))),142)
	_draw_vehicle_metric(ui,rect.position+Vector2(180,185),"FUEL / WEEK",ui.money(int(summary.get("weekly_fuel",owned.get("fuel_weekly",0)))),142)
	_draw_vehicle_metric(ui,rect.position+Vector2(342,185),"MAINTENANCE / MO",ui.money(int(summary.get("maintenance_monthly",owned.get("maintenance_monthly",0)))),142)
	var status := "Condition %d%% · Ready to drive" % condition
	if not operational: status = "Repair needed · "+ui.money(repair_cost)
	elif bool(owned.get("insurance_lapsed",false)): status = "Insurance lapsed"
	elif arrears>0: status = "Overdue "+ui.money(arrears)
	ui.text(status,rect.position+Vector2(18,245),10,UiKit.MUTED if operational and arrears<=0 else UiKit.RED,260)
	ui.button(Rect2(rect.position+Vector2(294,228),Vector2(89,30)),"Repair","repair_vehicle",null,UiKit.TEAL,not operational and state.cash>=repair_cost)
	ui.button(Rect2(rect.position+Vector2(392,228),Vector2(94,30)),"Sell car","sell_vehicle",null,UiKit.BLUE_DARK,true)

func _draw_vehicle_metric(ui: UiKit, pos: Vector2, label: String, value: String, width: float, color: Color = UiKit.INK) -> void:
	ui.text(label, pos, 9, UiKit.MUTED, width)
	ui.text(value, pos + Vector2(0, 20), 13, color, width)


func _draw_vehicle_listing(ui: UiKit, state: LifeGameState, vehicle: Dictionary, already_owned: bool, rect: Rect2) -> void:
	var vehicle_id := str(vehicle.get("id",""))
	var cash_quote: Dictionary = vehicle.get("cash_quote",{})
	var finance_quote: Dictionary = vehicle.get("finance_quote",{})
	var cash_total := int(cash_quote.get("total",vehicle.get("purchase_price",0)))
	var driving_ok := int(state.skills.get("driving",0))>=int(vehicle.get("minimum_driving_skill",0))
	var cash_details: Dictionary = vehicle.get("cash_eligibility",{})
	var finance_details: Dictionary = vehicle.get("finance_eligibility",{})
	var cash_enabled := bool(cash_details.get("eligible",not already_owned and driving_ok and state.cash>=cash_total))
	var finance_enabled := bool(finance_details.get("eligible",_vehicle_finance_enabled(state,already_owned,driving_ok,finance_quote)))
	ui.panel(rect,UiKit.WHITE,UiKit.LINE,12,1)
	AssetIllustrations.draw_car(ui,vehicle,Rect2(rect.position+Vector2(16,14),Vector2(188,94)))
	ui.text(str(vehicle.get("condition","Used")).to_upper(),rect.position+Vector2(220,28),9,UiKit.MUTED)
	ui.paragraph(str(vehicle.get("name","Vehicle")),Rect2(rect.position+Vector2(220,39),Vector2(266,36)),16,UiKit.INK,19,2)
	ui.text(ui.money(int(vehicle.get("purchase_price",0))),rect.position+Vector2(220,99),23,UiKit.INK)
	ui.divider(rect.position.y+120,rect.position.x+16,rect.size.x-32)
	_draw_vehicle_metric(ui,rect.position+Vector2(18,136),"DOWN + FEES TODAY",ui.money(int(finance_quote.get("due_today",0))),148)
	_draw_vehicle_metric(ui,rect.position+Vector2(181,136),"PAYMENT / MONTH",ui.money(int(finance_quote.get("monthly_payment",0))),148)
	_draw_vehicle_metric(ui,rect.position+Vector2(344,136),"FINANCING","%.2f%% · %d mo" % [float(finance_quote.get("apr_basis_points",vehicle.get("apr_basis_points",0)))/100.0,int(finance_quote.get("term_months",vehicle.get("loan_term_months",0)))],140)
	ui.text("Insurance %s/mo · Fuel %s/wk · Care %s/mo" % [ui.money(int(vehicle.get("insurance_monthly",0))),ui.money(int(vehicle.get("fuel_weekly",0))),ui.money(int(vehicle.get("maintenance_monthly",0)))],rect.position+Vector2(18,183),10,UiKit.MUTED,468)
	var foot := "Game quote · Cash total "+ui.money(cash_total)
	if not driving_ok: foot = "Driving %d required" % int(vehicle.get("minimum_driving_skill",0))
	elif already_owned: foot = "Sell your current vehicle to change"
	ui.text(foot,rect.position+Vector2(18,221),9,UiKit.MUTED,270)
	ui.button(Rect2(rect.position+Vector2(298,202),Vector2(84,32)),"Cash","buy_vehicle_cash",vehicle_id,UiKit.TEAL,cash_enabled)
	ui.button(Rect2(rect.position+Vector2(391,202),Vector2(95,32)),"Finance","finance_vehicle",vehicle_id,UiKit.BLUE_DARK,finance_enabled)

func _vehicle_finance_enabled(state: LifeGameState, already_owned: bool, driving_ok: bool, quote: Dictionary) -> bool:
	if already_owned or not driving_ok or not bool(quote.get("valid", true)):
		return false
	if int(state.cash) < int(quote.get("due_today", 0)):
		return false
	var weekly_gross := maxi(0, int(state.employment.get("weekly_pay", 0)))
	if weekly_gross <= 0:
		return false
	var monthly_income := roundi(float(weekly_gross * 52) / 12.0)
	return int(quote.get("monthly_payment", 0)) <= roundi(float(monthly_income) * 0.22)


func _format_integer(value: int) -> String:
	var raw := str(absi(value))
	var formatted := ""
	while raw.length() > 3:
		formatted = "," + raw.right(3) + formatted
		raw = raw.left(raw.length() - 3)
	return ("-" if value < 0 else "") + raw + formatted


func _draw_physical_filters(ui: UiKit, selected: String, y: float) -> void:
	var items: Array[Dictionary] = [
		{"id":"vehicle", "label":"VEHICLES"},
		{"id":"property", "label":"PROPERTY"},
		{"id":"collectible", "label":"ART"},
		{"id":"equipment", "label":"EQUIPMENT"},
	]
	var outer := Rect2(18, y, 504, 36)
	ui.panel(outer, Color("eef1f4"), Color("dce1e7"), 8, 1)
	var width := outer.size.x / float(items.size())
	for index in items.size():
		var item: Dictionary = items[index]
		var item_id := str(item.get("id", ""))
		var rect := Rect2(outer.position.x + width * index, outer.position.y, width, outer.size.y)
		if item_id == selected:
			ui.panel(rect.grow(-3), UiKit.WHITE, Color("ccd4dd"), 6, 1)
		ui.text(str(item.get("label", "")), Vector2(rect.position.x, rect.position.y + 23), 9, UiKit.INK if item_id == selected else UiKit.MUTED, rect.size.x, HORIZONTAL_ALIGNMENT_CENTER)
		ui.register(rect, "asset_category", item_id)


func _draw_market_card(ui: UiKit, state: LifeGameState, item: Dictionary, ctx: Dictionary, rect: Rect2) -> void:
	var category_id := str(item.get("category_id","equipment"))
	ui.panel(rect,UiKit.WHITE,UiKit.LINE,12,1)
	AssetIllustrations.draw(ui,item,Rect2(rect.position+Vector2(16,16),Vector2(134,140)))
	ui.text(str(item.get("artist",_category_label(category_id))).to_upper(),rect.position+Vector2(168,29),9,UiKit.MUTED,316)
	ui.text(str(item.get("name","Asset")),rect.position+Vector2(168,54),18,UiKit.INK,316)
	ui.paragraph(str(item.get("edition",item.get("description",""))),Rect2(rect.position+Vector2(168,66),Vector2(314,40)),11,UiKit.MUTED,16,2)
	var value := int(item.get("current_value",item.get("initial_value",0)))
	ui.text(ui.money(value),rect.position+Vector2(168,123),24,UiKit.INK)
	ui.text("Current appraisal · changes weekly",rect.position+Vector2(168,144),9,UiKit.MUTED)
	ui.divider(rect.position.y+168,rect.position.x+16,rect.size.x-32)
	var quote: Dictionary = item.get("purchase_quote",{})
	var total := int(quote.get("total",value))
	var hours := int(quote.get("action_hours",item.get("action_hours",1)))
	var enabled := state.cash>=total and state.weekly_time>=hours and int(item.get("owned_quantity",0))<int(item.get("max_quantity",1)) and _eligibility(ctx,"buy_eligibility",str(item.get("id","")),true)
	ui.text("%s/mo care · %dh" % [ui.money(int(item.get("monthly_upkeep",0))),hours],rect.position+Vector2(18,191),10,UiKit.MUTED)
	ui.text("Edition, not museum original" if item.has("edition") else str(item.get("availability","")),rect.position+Vector2(18,206),9,UiKit.MUTED,280)
	ui.button(Rect2(rect.position+Vector2(310,178),Vector2(176,32)),"Buy · "+ui.money(total),"buy_asset",str(item.get("id","")),UiKit.BLUE_DARK,enabled)

func _draw_ledger(ui: UiKit, state: LifeGameState, ctx: Dictionary) -> void:
	var scroll := float(ctx.get("scroll", 0.0))
	var y := CONTENT_TOP + 12.0 - scroll
	var transactions: Array[Dictionary] = []
	for raw_entry in state.ledger:
		if raw_entry is Dictionary:
			transactions.append(raw_entry)

	if _fully_visible(y, 145):
		ui.panel(Rect2(18, y, 504, 145), Color("f7f2e8"), Color("d7c7a6"), 18, 2)
		ui.text("ACCOUNTS AT A GLANCE", Vector2(39, y + 27), 11, UiKit.ORANGE)
		ui.text(ui.money(state.cash), Vector2(39, y + 59), 20, UiKit.INK)
		ui.text("cash", Vector2(39, y + 77), 9, UiKit.MUTED)
		ui.text(ui.money(state.savings), Vector2(197, y + 59), 20, UiKit.GREEN)
		ui.text("savings", Vector2(197, y + 77), 9, UiKit.MUTED)
		ui.text(ui.money(state.debt), Vector2(355, y + 59), 20, UiKit.RED if state.debt > 0 else UiKit.MUTED)
		ui.text("debt", Vector2(355, y + 77), 9, UiKit.MUTED)
		ui.button(Rect2(39, y + 94, 135, 34), "SAVE $100", "save_money", 100, UiKit.TEAL, state.cash >= 100)
		ui.button(Rect2(202, y + 94, 135, 34), "WITHDRAW $100", "withdraw_money", 100, UiKit.BLUE, state.savings >= 100)
		ui.button(Rect2(365, y + 94, 135, 34), "PAY DEBT", "repay_debt", 100, UiKit.RED, state.debt > 0 and state.cash > 0)
	y += 158.0

	if _fully_visible(y, 26):
		ui.host.draw_circle(Vector2(25, y + 12), 4, UiKit.BLUE)
		ui.text("RECENT MONEY MOVES", Vector2(38, y + 16), 11, UiKit.BLUE)
		ui.text("Every dollar keeps its reason", Vector2(295, y + 16), 10, UiKit.MUTED, 205, HORIZONTAL_ALIGNMENT_RIGHT)
	y += 36.0

	if transactions.is_empty():
		if _fully_visible(y, 126):
			ui.panel(Rect2(18, y, 504, 126), UiKit.WHITE, UiKit.LINE, 18, 2)
			ui.text("No transactions yet", Vector2(39, y + 44), 18, UiKit.INK)
			ui.paragraph("Income, bills, transfers, purchases, sales, and upkeep will all appear here with a date and reason.", Rect2(39, y + 61, 445, 44), 12, UiKit.MUTED, 17, 3)
		return

	var newest := transactions.size() - 1
	for row in 8:
		var index := newest - row
		if index < 0:
			break
		var entry: Dictionary = transactions[index]
		if _fully_visible(y, 64):
			_draw_ledger_row(ui, entry, Rect2(18, y, 504, 64))
		y += 72.0


func _draw_ledger_row(ui: UiKit, entry: Dictionary, rect: Rect2) -> void:
	var amount := int(entry.get("amount", 0))
	var color := UiKit.GREEN if amount >= 0 else UiKit.RED
	ui.panel(rect, UiKit.WHITE, UiKit.LINE, 14, 1)
	ui.host.draw_circle(rect.position + Vector2(22, 32), 7, color)
	ui.text(str(entry.get("reason", "Asset transaction")), rect.position + Vector2(40, 27), 12, UiKit.INK)
	ui.text("%s • %s" % [str(entry.get("date", "")), str(entry.get("category", "asset")).replace("asset_", "").replace("_", " ").capitalize()], rect.position + Vector2(40, 47), 9, UiKit.MUTED)
	ui.text(("+" if amount > 0 else "") + ui.money(amount), rect.position + Vector2(367, 38), 14, color, 113, HORIZONTAL_ALIGNMENT_RIGHT)


func _draw_category_chips(ui: UiKit, selected: String, include_all: bool = true) -> void:
	var items: Array[Dictionary] = []
	if include_all:
		items.append({"id":"all", "label":"ALL", "width":48.0})
	items.append_array([
		{"id":"investment", "label":"FUNDS", "width":75.0},
		{"id":"vehicle", "label":"CARS", "width":62.0},
		{"id":"property", "label":"HOMES", "width":73.0},
		{"id":"collectible", "label":"ART", "width":52.0},
		{"id":"equipment", "label":"GEAR", "width":63.0},
	])
	var gap := 7.0
	var total_width := -gap
	for item in items:
		total_width += float(item.get("width", 60.0)) + gap
	var x := 18.0 + maxf(0.0, (504.0 - total_width) * 0.5)
	for item in items:
		var width := float(item.get("width", 60.0))
		var category_id := str(item.get("id", ""))
		var action_arg := "" if category_id == "all" else category_id
		ui.chip(Rect2(x, 157, width, 34), str(item.get("label", "")), selected == category_id, "asset_category", action_arg)
		x += width + gap


func _eligibility(ctx: Dictionary, bucket_name: String, asset_id: String, fallback: bool) -> bool:
	var raw_bucket: Variant = ctx.get(bucket_name, {})
	if not raw_bucket is Dictionary or not raw_bucket.has(asset_id):
		return fallback
	var details: Variant = raw_bucket.get(asset_id)
	if not details is Dictionary:
		return fallback
	return bool(details.get("eligible", details.get("ok", fallback)))


func _draw_sparkline(ui: UiKit, raw_history: Variant, rect: Rect2, color: Color) -> void:
	if not raw_history is Array or raw_history.size() < 2:
		ui.host.draw_line(Vector2(rect.position.x, rect.get_center().y), Vector2(rect.end.x, rect.get_center().y), Color("d8d9d4"), 2)
		return
	var history: Array = raw_history
	var start := maxi(0, history.size() - 14)
	var minimum := INF
	var maximum := -INF
	for i in range(start, history.size()):
		minimum = minf(minimum, float(history[i]))
		maximum = maxf(maximum, float(history[i]))
	var spread := maxf(1.0, maximum - minimum)
	var count := history.size() - start
	var points := PackedVector2Array()
	for i in count:
		var value := float(history[start + i])
		var px := rect.position.x + float(i) * rect.size.x / float(maxi(1, count - 1))
		var py := rect.end.y - ((value - minimum) / spread) * rect.size.y
		points.append(Vector2(px, py))
	ui.host.draw_polyline(points, color, 2.4, true)
	ui.host.draw_circle(points[-1], 3.5, color)


func _filter_category(raw_items: Variant, category: String) -> Array:
	var result: Array = []
	if not raw_items is Array:
		return result
	for raw_item in raw_items:
		if raw_item is Dictionary and (category == "all" or str(raw_item.get("category_id", "")) == category):
			result.append(raw_item)
	return result


func _selected_category(ctx: Dictionary, fallback: String) -> String:
	var selected := str(ctx.get("asset_category", fallback))
	return fallback if selected.is_empty() else selected


func _accent_for(category_id: String, ctx: Dictionary) -> Color:
	for raw_category in ctx.get("categories", []):
		if raw_category is Dictionary and str(raw_category.get("id", "")) == category_id:
			return Color(str(raw_category.get("accent", _category_color(category_id).to_html())))
	return _category_color(category_id)


func _category_color(category_id: String) -> Color:
	match category_id:
		"investment": return Color("5976e6")
		"vehicle": return Color("2fa881")
		"property": return Color("c88642")
		"collectible": return Color("a966b7")
		"equipment": return Color("d26363")
		_: return UiKit.BLUE


func _category_glyph(category_id: String) -> String:
	match category_id:
		"investment": return "↗"
		"vehicle": return "V"
		"property": return "H"
		"collectible": return "✦"
		"equipment": return "T"
		_: return "•"


func _category_label(category_id: String) -> String:
	match category_id:
		"investment": return "Investments"
		"vehicle": return "Vehicles"
		"property": return "Property"
		"collectible": return "Art & Collectibles"
		"equipment": return "Useful Belongings"
		_: return "Everything"


func _category_intro(category_id: String) -> String:
	match category_id:
		"investment": return "Fictional prices move each week on their own. Returns are never guaranteed."
		"vehicle": return "Transport opens routes and gigs, while fuel, insurance, and wear remain yours."
		"property": return "Long-term equity, monthly care, and an address with consequences."
		"collectible": return "Buy what means something; collector prices can still surprise you."
		"equipment": return "Practical tools connect directly to freelance work and the city marketplace."
		_: return "Build a life from choices that remain visible and useful."


func _condition_color(condition: int) -> Color:
	if condition >= 72: return UiKit.GREEN
	if condition >= 42: return UiKit.GOLD
	return UiKit.RED


func _market_class_color(asset_class: String) -> Color:
	match asset_class:
		"stock": return Color("315ee7")
		"etf": return Color("147d73")
		"crypto": return Color("6956a8")
		"bond": return Color("a96f16")
		_: return UiKit.BLUE


func _market_class_label(asset_class: String) -> String:
	match asset_class:
		"stock": return "Stocks"
		"etf": return "Funds"
		"crypto": return "Crypto"
		"bond": return "Bonds"
		_: return asset_class.capitalize()


func _format_cents(value_cents: int) -> String:
	var sign := "-" if value_cents < 0 else ""
	var absolute := absi(value_cents)
	var dollars := str(absolute / 100)
	var formatted := ""
	while dollars.length() > 3:
		formatted = "," + dollars.right(3) + formatted
		dollars = dollars.left(dollars.length() - 3)
	return "%s$%s%s.%02d" % [sign, dollars, formatted, absolute % 100]


func _signed_cents(value_cents: int) -> String:
	return ("+" if value_cents > 0 else "") + _format_cents(value_cents)


func _pnl_color(value_cents: int) -> Color:
	if value_cents > 0: return UiKit.GREEN
	if value_cents < 0: return UiKit.RED
	return UiKit.MUTED


func _fully_visible(y: float, height: float) -> bool:
	return y < CONTENT_BOTTOM and y + height > CONTENT_TOP


func get_scroll_limit(_state: LifeGameState, ctx: Dictionary) -> float:
	var total := 0.0
	var tab := str(ctx.get("asset_tab","owned"))
	var category := _selected_category(ctx,"all")
	if tab == "owned":
		total = 160
		var count := _filter_category(ctx.get("owned",[]),category).size()
		total += count*232
		if category in ["all","investment"]:
			total += (ctx.get("market_holdings",[]) as Array).size()*92
		if category in ["all","vehicle"] and not (ctx.get("owned_vehicle",{}) as Dictionary).is_empty():
			total += 282
		if total==160: total+=176
	elif tab == "ledger":
		total = 206+mini(8,_state.ledger.size())*72
	else:
		var section := str(ctx.get("market_section","portfolio"))
		if section == "things":
			if category not in ["vehicle","property","collectible","equipment"]: category="vehicle"
			if category == "vehicle":
				total = 8+(ctx.get("vehicle_catalog",[]) as Array).size()*254
				if not (ctx.get("owned_vehicle",{}) as Dictionary).is_empty(): total += 282
			else:
				total = 8+_filter_category(ctx.get("physical_catalog",ctx.get("catalog",[])),category).size()*230
		elif section == "portfolio":
			var holding_count := (ctx.get("market_holdings",[]) as Array).size()
			total = 8+138+116+32+maxi(1,holding_count)*92+32+mini(4,(ctx.get("market_news",[]) as Array).size())*80
		else:
			total = 66
			for item in ctx.get("market_instruments",[]):
				if item is Dictionary and str(item.get("asset_class",""))==section: total += 136
	return maxf(0,total-(CONTENT_BOTTOM-CONTENT_TOP))
