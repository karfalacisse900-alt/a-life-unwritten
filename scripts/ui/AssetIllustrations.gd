class_name AssetIllustrations
extends RefCounted

## Real catalog photography is used where it improves recognition at a glance;
## code-drawn fallbacks keep the game lightweight for items without a matching
## photograph. All downloaded photo credits live in assets/photography/ATTRIBUTION.md.
static var _textures: Dictionary = {}

const PHOTO_DIR := "res://assets/photography/"

static func _texture(path: String) -> Texture2D:
	if path.is_empty() or not ResourceLoader.exists(path):
		return null
	if not _textures.has(path):
		_textures[path] = load(path)
	return _textures[path] as Texture2D

static func _draw_photo(ui: UiKit, path: String, rect: Rect2, cover: bool = true, background: Color = Color("e9ece8")) -> bool:
	var texture := _texture(path)
	if texture == null:
		return false
	ui.host.draw_rect(rect, background)
	var inset := rect.grow(-4.0)
	var source := Rect2(Vector2.ZERO, texture.get_size())
	var source_ratio := source.size.x / maxf(1.0, source.size.y)
	var target_ratio := inset.size.x / maxf(1.0, inset.size.y)
	if cover:
		if source_ratio > target_ratio:
			var cropped_width := source.size.y * target_ratio
			source.position.x = (source.size.x - cropped_width) * 0.5
			source.size.x = cropped_width
		else:
			var cropped_height := source.size.x / target_ratio
			source.position.y = (source.size.y - cropped_height) * 0.5
			source.size.y = cropped_height
		ui.host.draw_texture_rect_region(texture, inset, source)
	else:
		var scale := minf(inset.size.x / source.size.x, inset.size.y / source.size.y)
		var fitted := Rect2(inset.get_center() - source.size * scale * 0.5, source.size * scale)
		ui.host.draw_texture_rect_region(texture, fitted, source)
	return true


static func draw(ui: UiKit, item: Dictionary, rect: Rect2) -> void:
	var thumbnail := str(item.get("thumbnail", ""))
	if not thumbnail.is_empty() and ResourceLoader.exists(thumbnail):
		if not _textures.has(thumbnail):
			_textures[thumbnail] = load(thumbnail)
		var texture: Texture2D = _textures[thumbnail]
		ui.host.draw_rect(rect, Color("e8e1d5"))
		var mat := rect.grow(-8)
		var source := Rect2(Vector2.ZERO, texture.get_size())
		# The David source is a museum scan. Show the photographic area, retaining
		# the unaltered archival source on disk and its credit beside the catalog.
		if thumbnail.ends_with("david.jpg"):
			source = Rect2(texture.get_size()*Vector2(0.18,0.165),texture.get_size()*Vector2(0.60,0.67))
		var image_size := source.size
		var scale := minf(mat.size.x / image_size.x, mat.size.y / image_size.y)
		var fitted := Rect2(mat.get_center() - image_size * scale * 0.5, image_size * scale)
		ui.host.draw_rect(fitted.grow(4), Color("3e3831"))
		ui.host.draw_texture_rect_region(texture, fitted, source)
		return
	match str(item.get("category_id", "vehicle")):
		"vehicle": draw_car(ui, item, rect)
		"property": _draw_property(ui, item, rect)
		"equipment": _draw_equipment(ui, item, rect)
		_: _draw_studio_art(ui, item, rect)


static func draw_car(ui: UiKit, item: Dictionary, rect: Rect2) -> void:
	var car_class := str(item.get("class", item.get("kind", "sedan")))
	var identity := str(item.get("id", item.get("vehicle_id", "")))
	var photo_path := _vehicle_photo(identity, car_class)
	if _draw_photo(ui, photo_path, rect, false):
		return
	var sporty := car_class in ["hypercar", "supercar", "sports_car", "roadster"] or identity.contains("bugatti")
	var tall := car_class in ["suv", "van"]
	var paint := Color(str(item.get("paint_color", "74838b")))
	ui.host.draw_rect(rect, Color("edf0eb"))
	var stage := Rect2(rect.position + Vector2(8, 0), Vector2(rect.size.x - 16, rect.size.y))
	_line(ui, stage, [Vector2(9,91), Vector2(231,91)], Color("d2d7d1"), 1)
	_poly(ui, stage, [Vector2(17,84),Vector2(204,84),Vector2(225,92),Vector2(28,96)], Color(0.12,0.18,0.18,0.08))
	var roof_y := 43 if sporty else (23 if tall else 32)
	var roof_front := 143 if sporty else 148
	var roof_back := 101 if sporty else 91
	var body: Array = [Vector2(12,76),Vector2(20,62),Vector2(52,56),Vector2(roof_back,roof_y),Vector2(roof_front,roof_y),Vector2(178,58),Vector2(214,64),Vector2(228,73),Vector2(225,85),Vector2(14,85)]
	_poly(ui, stage, body, paint)
	_line(ui, stage, body + [body[0]], paint.darkened(0.35), 1.2)
	_poly(ui, stage, [Vector2(69,55),Vector2(roof_back+4,roof_y+5),Vector2(roof_front-5,roof_y+5),Vector2(164,56)], Color("253f48"))
	_line(ui, stage, [Vector2(118,roof_y+5),Vector2(116,56)], Color("9baeb0"), 1)
	_line(ui, stage, [Vector2(73,54),Vector2(104,roof_y+8),Vector2(134,roof_y+8)], Color("b4cccd"), 1)
	_poly(ui, stage, [Vector2(13,78),Vector2(229,78),Vector2(225,85),Vector2(14,85)], paint.darkened(0.25))
	_line(ui, stage, [Vector2(30,62),Vector2(78,59),Vector2(163,59),Vector2(210,66)], paint.lightened(0.4), 1.4)
	_line(ui, stage, [Vector2(117,58),Vector2(116,77)], paint.darkened(0.28), 1)
	_line(ui, stage, [Vector2(102,62),Vector2(112,62)], Color("d4ddd9"), 1.5)
	if sporty:
		_poly(ui, stage, [Vector2(145,60),Vector2(159,63),Vector2(154,77),Vector2(145,76)], Color("24393e"))
		_line(ui, stage, [Vector2(171,54),Vector2(188,54)], paint.darkened(0.25), 2)
	if identity.contains("bugatti"):
		var arc_points: Array = []
		for i in 18:
			var angle := -PI*0.5 + float(i)*PI/17.0
			arc_points.append(Vector2(132+cos(angle)*28,60+sin(angle)*18))
		_line(ui, stage, arc_points, Color("d8e3e5"), 2.3)
		_poly(ui, stage, [Vector2(13,64),Vector2(51,59),Vector2(57,78),Vector2(13,78)], paint.darkened(0.28))
	_line(ui, stage, [Vector2(204,66),Vector2(220,71)], Color("fff6d8"), 2.5)
	_line(ui, stage, [Vector2(15,68),Vector2(28,66)], Color("9a393d"), 2)
	for wheel_x in [54,184]:
		_circle(ui, stage, Vector2(wheel_x,82), 14, Color("20282c"))
		_circle(ui, stage, Vector2(wheel_x,82), 9.2, Color("a2aaac"))
		_circle(ui, stage, Vector2(wheel_x,82), 5.7, Color("4d5c65"))
		for i in 5:
			var a := float(i)*TAU/5.0
			_line(ui, stage, [Vector2(wheel_x,82),Vector2(wheel_x,82)+Vector2(cos(a),sin(a))*8.5], Color("d5dcdb"), 1)
		_circle(ui, stage, Vector2(wheel_x,82), 2, Color("e1e6e2"))


static func _draw_property(ui: UiKit, item: Dictionary, rect: Rect2) -> void:
	if _draw_photo(ui, PHOTO_DIR + "modern_house.jpg", rect, true):
		return
	ui.host.draw_rect(rect, Color("e7ebe2"))
	var stage := Rect2(rect.position + Vector2(8,8), rect.size - Vector2(16,16))
	_poly(ui, stage, [Vector2(34,88),Vector2(34,44),Vector2(118,15),Vector2(206,44),Vector2(206,88)], Color("d7c9b3"))
	_poly(ui, stage, [Vector2(27,46),Vector2(118,10),Vector2(213,46),Vector2(207,52),Vector2(118,22),Vector2(32,52)], Color("58645c"))
	for x in [55,91,155]:
		_poly(ui, stage, [Vector2(x,50),Vector2(x+21,50),Vector2(x+21,73),Vector2(x,73)], Color("46636b"))
		_line(ui, stage, [Vector2(x+10,50),Vector2(x+10,73)], Color("c2d0cb"), 1)
	_poly(ui, stage, [Vector2(123,53),Vector2(142,53),Vector2(142,88),Vector2(123,88)], Color("725847"))
	_line(ui, stage, [Vector2(20,90),Vector2(222,90)], Color("88937d"), 3)


static func draw_security(ui: UiKit, item: Dictionary, rect: Rect2) -> void:
	var symbol := str(item.get("symbol", item.get("id", ""))).to_upper()
	var asset_class := str(item.get("asset_class", "stock"))
	var photo_path := PHOTO_DIR + "stock_exchange.jpg"
	match symbol:
		"BTC": photo_path = PHOTO_DIR + "bitcoin_coins.jpg"
		"SOL": photo_path = PHOTO_DIR + "solana_logo.png"
		"ETH": photo_path = PHOTO_DIR + "ethereum_logo.png"
		"DOGE": photo_path = PHOTO_DIR + "bitcoin_coins.jpg"
		_:
			if asset_class == "bond": photo_path = PHOTO_DIR + "bond_certificate.jpg"
	if _draw_photo(ui, photo_path, rect, not photo_path.ends_with(".png"), Color("eef2f4")):
		return
	ui.host.draw_rect(rect, Color("eef2f4"))
	ui.icon_badge(rect.get_center(), minf(rect.size.x, rect.size.y) * 0.28, symbol.left(1), UiKit.BLUE)


static func _vehicle_photo(identity: String, car_class: String) -> String:
	var id := identity.to_lower()
	if id.contains("bugatti") or car_class in ["hypercar", "supercar"]:
		return PHOTO_DIR + "bugatti_veyron.jpg"
	if id.contains("porsche") or car_class in ["sports_car", "sports_sedan", "roadster"]:
		return PHOTO_DIR + "porsche_911.jpg"
	if id.contains("tesla") or car_class == "electric":
		return PHOTO_DIR + "tesla_model3.jpg"
	if car_class in ["suv"]:
		return PHOTO_DIR + "rav4_suv.jpg"
	if car_class in ["van"]:
		return PHOTO_DIR + "ford_transit.jpg"
	if car_class in ["compact", "sedan", "hybrid"]:
		return PHOTO_DIR + "passat_sedan.jpg"
	return ""


static func _draw_equipment(ui: UiKit, item: Dictionary, rect: Rect2) -> void:
	ui.host.draw_rect(rect, Color("e8e9e3"))
	var stage := Rect2(rect.position + Vector2(8,8), rect.size - Vector2(16,16))
	if str(item.get("id", "")).contains("stall"):
		_poly(ui, stage, [Vector2(48,24),Vector2(192,24),Vector2(214,44),Vector2(27,44)], Color("5b8172"))
		_line(ui, stage, [Vector2(42,44),Vector2(42,100)], Color("6c6b61"), 3)
		_line(ui, stage, [Vector2(201,44),Vector2(201,100)], Color("6c6b61"), 3)
		_poly(ui, stage, [Vector2(47,69),Vector2(195,69),Vector2(195,96),Vector2(47,96)], Color("bca884"))
	else:
		_poly(ui, stage, [Vector2(50,18),Vector2(190,18),Vector2(190,83),Vector2(50,83)], Color("485862"))
		_poly(ui, stage, [Vector2(57,24),Vector2(184,24),Vector2(184,76),Vector2(57,76)], Color("9ab5b6"))
		_poly(ui, stage, [Vector2(50,83),Vector2(190,83),Vector2(212,96),Vector2(27,96)], Color("9da8aa"))
		_line(ui, stage, [Vector2(80,41),Vector2(147,41)], Color("dce5dc"), 3)
		_line(ui, stage, [Vector2(80,52),Vector2(166,52)], Color("dce5dc"), 2)


static func _draw_studio_art(ui: UiKit, item: Dictionary, rect: Rect2) -> void:
	ui.host.draw_rect(rect, Color("eae3d9"))
	var frame := rect.grow(-12)
	ui.host.draw_rect(frame, Color("4d453b"))
	var art := frame.grow(-5)
	ui.host.draw_rect(art, Color("9aa5a5"))
	var seed_value := absi(str(item.get("id", "")).hash())
	for i in 4:
		var x := art.position.x + art.size.x*(0.08+float(i)*0.23)
		ui.host.draw_rect(Rect2(x,art.position.y+art.size.y*(0.3+float((seed_value+i)%3)*0.12),art.size.x*0.17,art.size.y*0.35),Color("566d73").lightened(float(i)*0.1))
	ui.host.draw_line(art.position+Vector2(0,art.size.y*0.8),art.end-Vector2(0,art.size.y*0.2),Color("c7b18e"),3)


static func _point(rect: Rect2, p: Vector2) -> Vector2:
	return rect.position + Vector2(p.x*rect.size.x/240.0,p.y*rect.size.y/112.0)


static func _poly(ui: UiKit, rect: Rect2, raw: Array, color: Color) -> void:
	var points := PackedVector2Array()
	for p in raw: points.append(_point(rect,p))
	ui.host.draw_colored_polygon(points,color)


static func _line(ui: UiKit, rect: Rect2, raw: Array, color: Color, width: float) -> void:
	var points := PackedVector2Array()
	for p in raw: points.append(_point(rect,p))
	ui.host.draw_polyline(points,color,width,true)


static func _circle(ui: UiKit, rect: Rect2, p: Vector2, radius: float, color: Color) -> void:
	ui.host.draw_circle(_point(rect,p),radius*minf(rect.size.x/240.0,rect.size.y/112.0),color,true,-1,true)
