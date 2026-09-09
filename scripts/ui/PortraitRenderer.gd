class_name PortraitRenderer
extends RefCounted

# Stable atlas coordinates preserve each character across saves and pages.
const PORTRAITS: Texture2D = preload("res://assets/editorial/people-portraits.png")
const NPC_PORTRAITS := {
	"person_jordan_hale": 0,
	"person_ellis_park": 5,
	"person_maya_chen": 2,
	"person_nia_brooks": 6,
	"person_theo_vance": 3,
	"person_samira_okafor": 4,
	"person_ren_ortiz": 7
}

static func draw(ui, rect: Rect2, _name: String, index: int = 0) -> void:
	var cell := PORTRAITS.get_size() / Vector2(4, 2)
	var chosen := posmod(index, 8)
	var source := Rect2(Vector2(chosen % 4, chosen / 4) * cell, cell).grow(-3.0)
	var ratio := rect.size.x / maxf(rect.size.y, 1.0)
	if source.size.x / source.size.y > ratio:
		var width := source.size.y * ratio
		source.position.x += (source.size.x - width) * 0.5
		source.size.x = width
	else:
		var height := source.size.x / ratio
		source.position.y += (source.size.y - height) * 0.24
		source.size.y = height
	ui.host.draw_rect(rect.grow(3.0), Color("fcfbf7"))
	ui.host.draw_texture_rect_region(PORTRAITS, rect, source)
	ui.host.draw_rect(rect, Color(0.16, 0.18, 0.20, 0.15), false, 1.0)

static func npc_index(person: Dictionary) -> int:
	var person_id := str(person.get("id", person.get("person_id", "")))
	if NPC_PORTRAITS.has(person_id): return int(NPC_PORTRAITS[person_id])
	return posmod(str(person.get("portrait", person.get("name", person_id))).hash(), 8)
