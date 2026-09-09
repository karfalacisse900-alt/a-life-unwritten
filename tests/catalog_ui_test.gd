extends SceneTree

var failures: Array[String] = []


func _initialize() -> void:
	call_deferred("_run")


func _run() -> void:
	var game = load("res://main.tscn").instantiate()
	game.persistence_enabled = false
	root.add_child(game)
	await process_frame
	game.screen_mode = "playing"
	game.current_page = "assets"
	game.asset_tab = "market"
	game.market_section = "things"
	game.asset_category = "collectible"
	game.state.cash = 9000000
	game.state.skills["driving"] = 100
	game.queue_redraw()
	await process_frame
	await process_frame
	_check(_has_hit(game,"buy_asset","mona_lisa_edition"),"Mona Lisa edition is available from the gallery.")
	if OS.get_cmdline_user_args().has("--capture"):
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://qa/collection-art.png")
	var ctx: Dictionary = game._assets_context("January 5, 2026")
	game.scrolls.assets = game.assets_page.get_scroll_limit(game.state,ctx)
	game.queue_redraw()
	await process_frame
	await process_frame
	_check(_has_hit(game,"buy_asset","after_rain_canvas"),"The final gallery listing is reachable at the end of scroll.")
	game.asset_category="vehicle"
	ctx=game._assets_context("January 5, 2026")
	game.scrolls.assets=game.assets_page.get_scroll_limit(game.state,ctx)
	game.queue_redraw()
	await process_frame
	await process_frame
	_check(_has_hit(game,"buy_vehicle_cash","bugatti_tourbillon"),"Bugatti Tourbillon can be reached and purchased at the end of the dealer list.")
	if OS.get_cmdline_user_args().has("--capture"):
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://qa/collection-hypercars.png")
	for hit in game.hitboxes:
		if str(hit.get("action","")).begins_with("buy_vehicle") or str(hit.get("action",""))=="finance_vehicle":
			var rect: Rect2=hit["rect"]
			_check(rect.position.y>=202 and rect.end.y<=802,"Scrolled purchase targets cannot cover fixed navigation.")
	game.asset_system.buy(game.state,"mona_lisa_edition",1,game.economy)
	game.vehicle_system.purchase_cash(game.state,"honda_civic_2020",game.economy)
	game.asset_tab="owned"
	game.asset_category=""
	game.scrolls.assets=0.0
	game.queue_redraw()
	await process_frame
	await process_frame
	_check(_has_hit(game,"sell_vehicle",null),"Financed-system vehicle is present on the owned assets page.")
	if OS.get_cmdline_user_args().has("--capture"):
		await RenderingServer.frame_post_draw
		root.get_texture().get_image().save_png("res://qa/collection-owned.png")
	game.free()
	if failures.is_empty():
		print("CATALOG_UI_TESTS_OK: gallery, last car reachability, viewport hit clipping and owned vehicle visibility")
		quit(0)
	else:
		for failure in failures: push_error(failure)
		quit(1)


func _has_hit(game, action: String, arg: Variant) -> bool:
	for hit in game.hitboxes:
		if str(hit.get("action",""))==action and hit.get("arg")==arg: return true
	return false


func _check(ok: bool, message: String) -> void:
	if not ok: failures.append(message)
