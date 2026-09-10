extends SceneTree

# Real-renderer smoke test. Screenshots are optional and never include a user save.
var game: Node
var capture_dir := ""
var failed := false

func _initialize() -> void:
	for arg in OS.get_cmdline_user_args():
		if str(arg).begins_with("--captures="): capture_dir = str(arg).trim_prefix("--captures=")
	call_deferred("_run")

func _run() -> void:
	root.size = Vector2i(540, 960)
	var scene: PackedScene = load("res://main.tscn")
	game = scene.instantiate()
	game.set("persistence_enabled", false)
	root.add_child(game)
	await _capture("welcome")
	game.call("_action", "new_game", null)
	await _capture("create")
	game.set("character_form", {"name":"Morgan Vale", "pronouns":"they/them", "appearance":5, "background":"fresh_start", "traits":["focused"]})
	game.call("_action", "finish_character", null)
	await _capture("housing")
	game.call("_action", "choose_housing", "family_home")
	game.call("_action", "close_message", null)
	for page in ["life", "city", "occupation", "assets", "people"]:
		game.call("_action", "nav_page", page)
		await _capture(page)
	game.call("_action", "open_person", "person_nia_brooks")
	await _capture("person")
	game.call("_action", "nav_page", "assets")
	game.call("_action", "asset_tab", "market")
	game.call("_action", "market_section", "crypto")
	await _capture("crypto")
	game.call("_action", "buy_market", "BTC")
	var ticket: Control = game.get("trade_ticket")
	if not ticket.visible:
		failed = true
		push_error("Trade ticket failed to open")
	ticket.get("amount").text = "0.0025"
	ticket.call("_refresh")
	await _capture("trade")
	ticket.call("_cancel")
	game.call("_action", "market_section", "things")
	game.call("_action", "asset_category", "collectible")
	await _capture("art")
	game.set("scrolls", {"life":0.0, "city":0.0, "occupation":0.0, "assets":390.0, "people":0.0})
	await _capture("art_scrolled")
	game.call("_action", "asset_category", "vehicle")
	await _capture("vehicles")
	var context: Dictionary = game.call("_assets_context", "January 5, 2026")
	var last_scroll: float = game.get("assets_page").call("get_scroll_limit", game.get("state"), context)
	game.set("scrolls", {"life":0.0, "city":0.0, "occupation":0.0, "assets":last_scroll, "people":0.0})
	await _capture("hypercars")
	game.call("_action", "nav_page", "life")
	root.size = Vector2i(1000, 800)
	await _capture("desktop")
	root.size = Vector2i(390, 844)
	await _capture("phone")
	game.queue_free()
	await process_frame
	print("UI_RENDER_PASS: creation, five pages, people, crypto ticket, art, vehicles, 540x960, 1000x800, 390x844" if not failed else "UI_RENDER_FAIL")
	quit(1 if failed else 0)

func _capture(label: String) -> void:
	game.call("queue_redraw")
	await process_frame
	await process_frame
	if not capture_dir.is_empty() and DisplayServer.get_name() != "headless":
		await RenderingServer.frame_post_draw
		DirAccess.make_dir_recursive_absolute(capture_dir)
		var error := root.get_texture().get_image().save_png(capture_dir.path_join(label + ".png"))
		if error != OK:
			failed = true
			push_error("Could not save QA screenshot: " + label)
