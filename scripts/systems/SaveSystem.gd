class_name SaveSystem
extends RefCounted

## Versioned JSON saves with a validated temporary write and one rolling backup.
## Loading is staged in a separate LifeGameState so failure never damages the
## currently running life.

const SAVE_VERSION: int = 2
const DEFAULT_SAVE_PATH := "user://a_life_unwritten_save_v2.json"

var save_path: String
var backup_path: String
var temp_path: String
var last_result: Dictionary = {}


func _init(custom_save_path: String = "") -> void:
	save_path = custom_save_path if not custom_save_path.is_empty() else DEFAULT_SAVE_PATH
	var extension := save_path.get_extension()
	var base := save_path.get_basename()
	if extension.is_empty():
		backup_path = "%s.backup" % save_path
		temp_path = "%s.tmp" % save_path
	else:
		backup_path = "%s.backup.%s" % [base, extension]
		temp_path = "%s.tmp.%s" % [base, extension]


func save_game(state: LifeGameState, autosave: bool = false) -> String:
	var save_kind := "autosave" if autosave else "manual"
	state.flags["last_save_kind"] = save_kind
	state.flags["last_saved_week_index"] = int(state.calendar.get("week_index", 0))
	var document := _build_document(state, save_kind)
	var encoded := JSON.stringify(document, "  ")

	var write_error := _write_text(temp_path, encoded)
	if write_error != OK:
		last_result = {"ok": false, "error": "Could not write temporary save", "code": write_error}
		return "The game could not be saved (error %d)." % write_error

	var verification := _decode_document(_read_text(temp_path))
	if not bool(verification.get("ok", false)):
		_remove_if_present(temp_path)
		last_result = {"ok": false, "error": "Temporary save failed validation", "detail": verification.get("error", "Unknown validation error")}
		return "The game could not be saved because its temporary file failed validation."

	# Only a valid primary is allowed to replace the known-good backup. A corrupt
	# primary therefore cannot destroy the player's recovery point.
	if FileAccess.file_exists(save_path):
		var prior_text := _read_text(save_path)
		if bool(_decode_document(prior_text).get("ok", false)):
			var backup_error := _replace_with_text(backup_path, prior_text)
			if backup_error != OK:
				_remove_if_present(temp_path)
				last_result = {"ok": false, "error": "Could not update backup", "code": backup_error}
				return "The game could not be saved because the backup could not be updated (error %d)." % backup_error

	var replace_error := _replace_file(temp_path, save_path)
	if replace_error != OK:
		last_result = {"ok": false, "error": "Could not replace primary save", "code": replace_error}
		return "The game could not be saved (error %d)." % replace_error

	var final_check := _decode_document(_read_text(save_path))
	if not bool(final_check.get("ok", false)):
		last_result = {"ok": false, "error": "Final save verification failed", "detail": final_check.get("error", "Unknown validation error")}
		return "The save was written but did not pass final verification. Your previous backup was kept."

	last_result = {
		"ok": true,
		"kind": save_kind,
		"path": save_path,
		"week_index": int(state.calendar.get("week_index", 0)),
	}
	state.state_changed.emit()
	return "Life saved successfully." if not autosave else "Life autosaved."


func autosave(state: LifeGameState) -> String:
	return save_game(state, true)


func load_game(state: LifeGameState) -> String:
	if not FileAccess.file_exists(save_path) and not FileAccess.file_exists(backup_path):
		last_result = {"ok": false, "error": "No save found"}
		return "No saved life was found."

	var primary_error := "Primary save not found"
	if FileAccess.file_exists(save_path):
		var primary_text := _read_text(save_path)
		var primary := _decode_document(primary_text)
		if bool(primary.get("ok", false)):
			if _apply_staged(state, primary.get("data", {})):
				last_result = {"ok": true, "source": "primary", "version": int(primary.get("version", SAVE_VERSION)), "migrated": bool(primary.get("migrated", false))}
				return "Welcome back. Your saved life has been loaded."
			primary_error = "Primary save data could not initialize a game state"
		else:
			primary_error = str(primary.get("error", "Primary save is damaged"))

	if FileAccess.file_exists(backup_path):
		var backup_text := _read_text(backup_path)
		var backup := _decode_document(backup_text)
		if bool(backup.get("ok", false)) and _apply_staged(state, backup.get("data", {})):
			# Repair the primary from the exact validated backup document. The backup
			# remains in place as the single recovery copy.
			var repair_error := _replace_with_text(save_path, backup_text)
			last_result = {
				"ok": true,
				"source": "backup",
				"version": int(backup.get("version", SAVE_VERSION)),
				"migrated": bool(backup.get("migrated", false)),
				"primary_error": primary_error,
				"primary_repaired": repair_error == OK,
			}
			return "The main save was unavailable, so the previous backup was loaded%s." % (" and repaired" if repair_error == OK else "")

	last_result = {"ok": false, "error": "No valid save or backup", "primary_error": primary_error}
	return "The saved life is damaged and no valid backup could be loaded. Your current game was left unchanged."


func has_save() -> bool:
	if FileAccess.file_exists(save_path) and bool(_decode_document(_read_text(save_path)).get("ok", false)):
		return true
	return FileAccess.file_exists(backup_path) and bool(_decode_document(_read_text(backup_path)).get("ok", false))


func _build_document(state: LifeGameState, save_kind: String) -> Dictionary:
	var payload := state.to_dict()
	# JSON numbers cannot preserve every 64-bit integer. Store the deterministic
	# RNG pair as decimal strings; LifeGameState accepts both strings and ints.
	payload["seed"] = str(state.seed)
	payload["rng_state"] = str(state.rng_state)
	var payload_json := JSON.stringify(payload)
	return {
		"format": "a-life-unwritten",
		"version": SAVE_VERSION,
		"save_kind": save_kind,
		"saved_at_unix": int(Time.get_unix_time_from_system()),
		"checksum_sha256": _sha256(payload_json),
		"payload_json": payload_json,
	}


func _decode_document(text: String) -> Dictionary:
	if text.is_empty():
		return {"ok": false, "error": "Save file is empty"}
	var parser := JSON.new()
	var parse_error := parser.parse(text)
	if parse_error != OK:
		return {"ok": false, "error": "Invalid JSON at line %d: %s" % [parser.get_error_line(), parser.get_error_message()]}
	if not parser.data is Dictionary:
		return {"ok": false, "error": "Save root is not an object"}
	var document: Dictionary = parser.data
	var version := int(document.get("version", 0))

	if version == SAVE_VERSION:
		if str(document.get("format", "")) != "a-life-unwritten":
			return {"ok": false, "error": "Unrecognized save format"}
		var payload_json := str(document.get("payload_json", ""))
		if payload_json.is_empty():
			return {"ok": false, "error": "Save payload is missing"}
		var expected_checksum := str(document.get("checksum_sha256", ""))
		if expected_checksum.is_empty() or not expected_checksum.to_lower() == _sha256(payload_json):
			return {"ok": false, "error": "Save checksum does not match"}
		var payload_parser := JSON.new()
		var payload_error := payload_parser.parse(payload_json)
		if payload_error != OK or not payload_parser.data is Dictionary:
			return {"ok": false, "error": "Save payload is not valid JSON state data"}
		if not _valid_payload_shape(payload_parser.data):
			return {"ok": false, "error": "Save payload is missing required state fields"}
		return {"ok": true, "version": version, "data": payload_parser.data, "migrated": false}

	if version == 1:
		var migrated := _migrate_v1(document)
		if migrated.is_empty():
			return {"ok": false, "error": "Version 1 save could not be migrated"}
		return {"ok": true, "version": version, "data": migrated, "migrated": true}

	if version > SAVE_VERSION:
		return {"ok": false, "error": "Save version %d is newer than this game supports" % version}
	return {"ok": false, "error": "Unsupported or missing save version"}


func _migrate_v1(document: Dictionary) -> Dictionary:
	var payload_value: Variant = document.get("payload", document.get("state", document))
	if payload_value is String:
		var parsed: Variant = JSON.parse_string(payload_value)
		if parsed is Dictionary:
			payload_value = parsed
	if not payload_value is Dictionary:
		return {}
	var old: Dictionary = payload_value
	var migrated_state := LifeGameState.new()
	var data := migrated_state.to_dict()
	data["created"] = true
	data["age"] = maxi(18, int(old.get("age", 18)))
	data["birth_year"] = int(data["calendar"]["year"]) - int(data["age"])
	data["cash"] = roundi(float(old.get("cash", data["cash"])))
	data["savings"] = maxi(0, roundi(float(old.get("savings", data["savings"]))))
	data["health"] = clampi(int(old.get("health", data["health"])), 0, 100)
	data["happiness"] = clampi(int(old.get("happiness", data["happiness"])), 0, 100)
	if old.has("player_name"):
		data["player_name"] = str(old["player_name"])
	if old.has("employment") and old["employment"] is Dictionary:
		data["employment"] = old["employment"].duplicate(true)
	return data


func _valid_payload_shape(data: Dictionary) -> bool:
	if not data.has("calendar") or not data["calendar"] is Dictionary:
		return false
	var saved_calendar: Dictionary = data["calendar"]
	for key in ["year", "month", "day", "week_index"]:
		if not saved_calendar.has(key):
			return false
	for required_key in ["cash", "savings", "debt", "employment", "housing_id", "relationships", "business", "crypto", "crime", "seed", "rng_state"]:
		if not data.has(required_key):
			return false
	return data["employment"] is Dictionary and data["relationships"] is Array and data["business"] is Dictionary and data["crypto"] is Dictionary and data["crime"] is Dictionary


func _apply_staged(target: LifeGameState, data: Variant) -> bool:
	if not data is Dictionary:
		return false
	var staging := LifeGameState.new()
	if not staging.from_dict(data):
		return false
	return target.from_dict(staging.to_dict())


func _sha256(text: String) -> String:
	var context := HashingContext.new()
	if context.start(HashingContext.HASH_SHA256) != OK:
		return ""
	if context.update(text.to_utf8_buffer()) != OK:
		return ""
	return context.finish().hex_encode()


func _read_text(path: String) -> String:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return ""
	return file.get_as_text()


func _write_text(path: String, text: String) -> Error:
	var absolute_path := ProjectSettings.globalize_path(path)
	var directory_error := DirAccess.make_dir_recursive_absolute(absolute_path.get_base_dir())
	if directory_error != OK and directory_error != ERR_ALREADY_EXISTS:
		return directory_error
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return FileAccess.get_open_error()
	file.store_string(text)
	file.flush()
	var result := file.get_error()
	file = null
	return result


func _replace_with_text(path: String, text: String) -> Error:
	var staging_path := "%s.staging" % path
	var write_error := _write_text(staging_path, text)
	if write_error != OK:
		return write_error
	return _replace_file(staging_path, path)


func _replace_file(source: String, destination: String) -> Error:
	var source_absolute := ProjectSettings.globalize_path(source)
	var destination_absolute := ProjectSettings.globalize_path(destination)
	if FileAccess.file_exists(destination):
		var remove_error := DirAccess.remove_absolute(destination_absolute)
		if remove_error != OK:
			return remove_error
	var rename_error := DirAccess.rename_absolute(source_absolute, destination_absolute)
	if rename_error == OK:
		return OK
	# Some filesystems cannot atomically rename across their backing volume.
	var copy_error := DirAccess.copy_absolute(source_absolute, destination_absolute)
	if copy_error == OK:
		DirAccess.remove_absolute(source_absolute)
	return copy_error


func _remove_if_present(path: String) -> void:
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
