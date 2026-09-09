extends SceneTree

var failures: Array[String] = []

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	var game := (load("res://main.tscn") as PackedScene).instantiate()
	game.set("persistence_enabled", false)
	root.add_child(game)
	await process_frame
	game.call("_action", "new_game", null)
	await process_frame
	var form: Dictionary = game.get("character_form")
	form["appearance"] = 0
	var targets: Array[Dictionary] = [{"rect":Rect2(100, 300, 100, 60), "action":"appearance_next", "arg":null}]
	game.set("hitboxes", targets)
	# iOS emits a native touch and, when enabled, a device -1 mouse stream.
	# An emulated mouse must not execute canvas gameplay before touch release.
	_send_touch(game, Vector2(150, 330), true)
	_send_mouse(game, Vector2(150, 330), true, InputEvent.DEVICE_ID_EMULATION)
	_check(int(form["appearance"]) == 0, "finger down must not activate a canvas action through an emulated mouse")
	_send_touch(game, Vector2(150, 330), false)
	_send_mouse(game, Vector2(150, 330), false, InputEvent.DEVICE_ID_EMULATION)
	_check(int(form["appearance"]) == 1, "one complete touch must activate once, not twice")
	form["appearance"] = 0
	_send_touch(game, Vector2(150, 330), true)
	_send_mouse(game, Vector2(150, 330), true, InputEvent.DEVICE_ID_EMULATION)
	var drag := InputEventScreenDrag.new()
	drag.position = Vector2(150, 370)
	drag.relative = Vector2(0, 40)
	game.call("_unhandled_input", drag)
	_send_touch(game, Vector2(150, 370), false)
	_check(int(form["appearance"]) == 0, "dragging from an actionable row must not activate it")
	form["appearance"] = 0
	_send_mouse(game, Vector2(150, 330), true, 0)
	_check(int(form["appearance"]) == 1, "physical desktop mouse input remains functional")
	game.set("screen_mode", "game")
	var scrolls: Dictionary = game.get("scrolls")
	scrolls["people"] = 420.0
	game.call("_action", "open_person", "person_nia_brooks")
	_check(float(scrolls["people"]) == 0.0, "opening a person from a scrolled list shows the profile first")
	scrolls["people"] = 300.0
	game.call("_action", "close_person", null)
	_check(float(scrolls["people"]) == 0.0, "closing a person resets the detail scroll before rendering the list")
	game.call("_action", "new_game", null)
	var name_field: LineEdit = game.get("name_input")
	_check(name_field.visible and name_field.virtual_keyboard_enabled, "creation exposes a native field with virtual keyboard enabled")
	name_field.text = "Tablet Player"
	name_field.text_changed.emit(name_field.text)
	_check(str((game.get("character_form") as Dictionary).get("name", "")) == "Tablet Player", "native name editing updates creation state")
	game.call("_action", "set_appearance", 7)
	_check(name_field.text == "Tablet Player", "selecting another portrait preserves native name input")
	game.free()
	if failures.is_empty():
		print("MOBILE_INPUT_PASS: touch emulation, swipe cancellation, mouse, portrait selection, native name, profile scroll")
		quit(0)
	else:
		for failure in failures: push_error("FAIL: " + failure)
		quit(1)

func _send_touch(game: Node, point: Vector2, pressed: bool) -> void:
	var event := InputEventScreenTouch.new()
	event.position = point
	event.pressed = pressed
	game.call("_unhandled_input", event)

func _send_mouse(game: Node, point: Vector2, pressed: bool, device_id: int) -> void:
	var event := InputEventMouseButton.new()
	event.position = point
	event.button_index = MOUSE_BUTTON_LEFT
	event.pressed = pressed
	event.device = device_id
	game.call("_unhandled_input", event)

func _check(condition: bool, description: String) -> void:
	if not condition: failures.append(description)
