class_name UiKit
extends RefCounted

const INK := Color("24333a")
const MUTED := Color("68726f")
const LINE := Color("dedfd7")
const BG := Color("f4f1eb")
const WHITE := Color("fffefb")
const BLUE := Color("355f70")
const BLUE_DARK := Color("203e47")
const TEAL := Color("147d73")
const GREEN := Color("237a57")
const RED := Color("c2414b")
const GOLD := Color("a96f16")
const PURPLE := Color("6956a8")
const ORANGE := Color("b85d22")
const BODY_FONT = preload("res://assets/fonts/DM-Sans.ttf")
const TITLE_FONT = preload("res://assets/fonts/LibreBaskerville.ttf")

var host: CanvasItem
var hits: Array[Dictionary]
var hover_key := ""

func begin(canvas: CanvasItem, target_hits: Array[Dictionary], current_hover: String) -> void:
	host = canvas
	hits = target_hits
	hover_key = current_hover

func panel(rect: Rect2, fill: Color, border: Color = LINE, radius: int = 12, border_width: int = 1) -> void:
	var style := StyleBoxFlat.new()
	style.bg_color = fill
	style.border_color = border
	style.set_border_width_all(border_width)
	style.set_corner_radius_all(radius)
	style.shadow_size = 0
	style.anti_aliasing = true
	host.draw_style_box(style, rect)

func text(value: String, pos: Vector2, size: int, color: Color = INK, width: float = -1.0, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> void:
	host.draw_string(BODY_FONT, pos, value, align, width, size, color)

func heading(value: String, pos: Vector2, size: int, color: Color = INK, width: float = -1.0, align: HorizontalAlignment = HORIZONTAL_ALIGNMENT_LEFT) -> void:
	host.draw_string(TITLE_FONT, pos, value, align, width, size, color)

func paragraph(value: String, rect: Rect2, size: int = 15, color: Color = MUTED, line_height: int = 21, max_lines: int = 3) -> void:
	var line := ""
	var y := rect.position.y + size
	var lines := 0
	for word in value.split(" "):
		var candidate := line + (" " if not line.is_empty() else "") + word
		if BODY_FONT.get_string_size(candidate, HORIZONTAL_ALIGNMENT_LEFT, -1, size).x > rect.size.x and not line.is_empty():
			text(line, Vector2(rect.position.x, y), size, color)
			lines += 1
			if lines >= max_lines: return
			y += line_height
			line = word
		else:
			line = candidate
	if not line.is_empty() and lines < max_lines:
		text(line, Vector2(rect.position.x, y), size, color)

func money(value: int) -> String:
	var absolute := absi(value)
	if absolute >= 1000000: return "$%.2fM" % (float(value) / 1000000.0)
	var digits := str(absolute)
	var grouped := ""
	for index in digits.length():
		if index > 0 and (digits.length() - index) % 3 == 0: grouped += ","
		grouped += digits[index]
	return ("−$" if value < 0 else "$") + grouped

func hit_key(action: String, arg: Variant = null) -> String:
	return action + ":" + JSON.stringify(arg)

func register(rect: Rect2, action: String, arg: Variant = null, enabled: bool = true) -> void:
	if enabled: hits.append({"rect":rect, "action":action, "arg":arg})

func button(rect: Rect2, label: String, action: String, arg: Variant = null, color: Color = BLUE, enabled: bool = true, icon: Texture2D = null) -> void:
	var fill := color
	if not enabled: fill = Color("c8cfd8")
	elif hover_key == hit_key(action, arg): fill = color.lightened(0.09)
	panel(rect, fill, fill.darkened(0.08), 7, 1)
	if icon:
		host.draw_texture_rect(icon, Rect2(rect.position + Vector2(7, 6), Vector2(rect.size.y - 12, rect.size.y - 12)), false)
		text(label, Vector2(rect.position.x + rect.size.y - 2, rect.position.y + rect.size.y * 0.63), 12, WHITE, rect.size.x - rect.size.y, HORIZONTAL_ALIGNMENT_CENTER)
	else:
		text(label, Vector2(rect.position.x, rect.position.y + rect.size.y * 0.63), 12, WHITE, rect.size.x, HORIZONTAL_ALIGNMENT_CENTER)
	register(rect, action, arg, enabled)

func chip(rect: Rect2, label: String, selected: bool, action: String, arg: Variant) -> void:
	if selected:
		host.draw_rect(Rect2(rect.position.x, rect.end.y - 2, rect.size.x, 2), BLUE_DARK)
	text(label.capitalize(), Vector2(rect.position.x, rect.position.y + rect.size.y * 0.64), 13, INK if selected else MUTED, rect.size.x, HORIZONTAL_ALIGNMENT_CENTER)
	register(rect, action, arg)

func header(title: String, subtitle: String, cash: int, date_text: String) -> void:
	host.draw_rect(Rect2(0, 0, 540, 92), BG)
	host.draw_line(Vector2(0, 91), Vector2(540, 91), LINE, 1.0)
	heading(title.capitalize(), Vector2(20, 39), 24, INK)
	text(subtitle.capitalize(), Vector2(20, 65), 10, MUTED, 340)
	text("AVAILABLE CASH", Vector2(382, 22), 8, MUTED, 138, HORIZONTAL_ALIGNMENT_RIGHT)
	text(money(cash), Vector2(382, 45), 17, INK, 138, HORIZONTAL_ALIGNMENT_RIGHT)
	text(date_text, Vector2(360, 73), 10, MUTED, 160, HORIZONTAL_ALIGNMENT_RIGHT)

func sub_header(title: String, subtitle: String, color: Color, back_action: String = "") -> void:
	host.draw_rect(Rect2(0, 0, 540, 94), WHITE)
	host.draw_line(Vector2(0, 93), Vector2(540, 93), LINE, 1.0)
	var x := 20.0
	if not back_action.is_empty():
		panel(Rect2(14, 22, 44, 44), Color("f1f4f7"), LINE, 10, 1)
		text("‹", Vector2(14, 56), 32, INK, 44, HORIZONTAL_ALIGNMENT_CENTER)
		register(Rect2(8, 15, 58, 62), back_action)
		x = 76.0
	heading(title.capitalize(), Vector2(x, 42), 23, INK)
	text(subtitle, Vector2(x, 66), 10, MUTED)
	host.draw_rect(Rect2(0, 90, 5, 4), color)

func section_title(title: String, y: float, subtitle: String = "") -> void:
	text(title.to_upper(), Vector2(20, y), 10, MUTED)
	if not subtitle.is_empty():
		text(subtitle, Vector2(265, y), 10, MUTED, 255, HORIZONTAL_ALIGNMENT_RIGHT)

func avatar(rect: Rect2, name: String, index: int = 0) -> void:
	PortraitRenderer.draw(self, rect, name, index)

func money_cents(value_cents: int) -> String:
	return "$%s" % String.num(float(value_cents) / 100.0, 2)

func stat_bar(rect: Rect2, label: String, value: int, color: Color) -> void:
	text(label, rect.position + Vector2(0, 11), 9, MUTED)
	panel(Rect2(rect.position + Vector2(0, 17), Vector2(rect.size.x, 8)), Color("e8edf1"), Color("e8edf1"), 4, 0)
	panel(Rect2(rect.position + Vector2(0, 17), Vector2(rect.size.x * clampf(float(value) / 100.0, 0.0, 1.0), 8)), color, color, 4, 0)
	text(str(value), rect.position + Vector2(0, 43), 12, INK)

func icon_badge(center: Vector2, radius: float, glyph: String, color: Color) -> void:
	host.draw_circle(center, radius, color)
	host.draw_circle(center, radius - 3.0, color.lightened(0.08))
	text(glyph, Vector2(center.x - radius, center.y + radius * 0.38), int(radius * 0.95), WHITE, radius * 2.0, HORIZONTAL_ALIGNMENT_CENTER)

func divider(y: float, x: float = 18.0, width: float = 504.0) -> void:
	host.draw_line(Vector2(x, y), Vector2(x + width, y), LINE, 1.0)

func navigation_icon(id: String, center: Vector2, color: Color) -> void:
	# One hand-drawn line vocabulary keeps navigation quiet beside character art.
	host.draw_set_transform(center)
	match id:
		"life":
			host.draw_rect(Rect2(-10, -12, 20, 25), color, false, 1.8)
			host.draw_line(Vector2(-5, -12), Vector2(-5, 13), color, 1.8)
			host.draw_line(Vector2(-1, -5), Vector2(6, -5), color, 1.8)
			host.draw_line(Vector2(-1, 1), Vector2(6, 1), color, 1.8)
		"city":
			host.draw_polyline(PackedVector2Array([Vector2(-14, -1), Vector2(0, -13), Vector2(14, -1)]), color, 1.8, true)
			host.draw_polyline(PackedVector2Array([Vector2(-10, -4), Vector2(-10, 12), Vector2(10, 12), Vector2(10, -4)]), color, 1.8, true)
			host.draw_rect(Rect2(-3, 3, 6, 9), color, false, 1.8)
		"occupation":
			host.draw_rect(Rect2(-13, -6, 26, 20), color, false, 1.8)
			host.draw_polyline(PackedVector2Array([Vector2(-5, -6), Vector2(-5, -12), Vector2(5, -12), Vector2(5, -6)]), color, 1.8, true)
			host.draw_line(Vector2(-13, 1), Vector2(13, 1), color, 1.8)
			host.draw_rect(Rect2(-2, -1, 4, 5), color)
		"assets":
			host.draw_rect(Rect2(-13, -9, 26, 22), color, false, 1.8)
			host.draw_rect(Rect2(3, -3, 12, 10), WHITE)
			host.draw_rect(Rect2(3, -3, 12, 10), color, false, 1.8)
			host.draw_circle(Vector2(7, 2), 1.5, color)
		"people":
			host.draw_circle(Vector2(-4, -6), 6, color, false, 1.8, true)
			host.draw_arc(Vector2(-4, 13), 10, PI, TAU, 24, color, 1.8, true)
			host.draw_arc(Vector2(5, -6), 6, -1.1, 1.1, 12, color, 1.8, true)
			host.draw_arc(Vector2(5, 13), 10, -1.4, 0, 12, color, 1.8, true)
	host.draw_set_transform(Vector2.ZERO)
