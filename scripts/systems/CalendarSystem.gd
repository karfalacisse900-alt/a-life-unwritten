class_name CalendarSystem
extends RefCounted

## Advances the simulation in indivisible seven-day turns. Date arithmetic is
## deliberately timezone-free so a saved seed behaves identically everywhere.

const MONTH_NAMES: Array[String] = [
	"January", "February", "March", "April", "May", "June",
	"July", "August", "September", "October", "November", "December",
]


func advance_one_week(state: LifeGameState) -> Dictionary:
	# This guard protects against a signal callback re-entering this synchronous
	# method. It is removed before returning and is not a long-lived game lock.
	if bool(state.flags.get("calendar_advancing", false)):
		return {
			"advanced": false,
			"reason": "A weekly advance is already being processed.",
			"new_month": false,
			"new_year": false,
			"month_boundaries": [],
		}
	state.flags["calendar_advancing"] = true

	var previous := _normalized_date(state.calendar)
	var previous_week_index := maxi(0, int(state.calendar.get("week_index", 0)))
	var current := {
		"year": int(previous["year"]),
		"month": int(previous["month"]),
		"day": int(previous["day"]),
	}
	var month_boundaries: Array[Dictionary] = []
	var year_boundaries: Array[int] = []

	for _day in range(7):
		var prior_year := int(current["year"])
		current = _add_one_day(current)
		if int(current["day"]) == 1:
			month_boundaries.append(current.duplicate(true))
		if int(current["year"]) != prior_year:
			year_boundaries.append(int(current["year"]))

	var new_week_index := previous_week_index + 1
	var completed_calendar := {
		"year": int(current["year"]),
		"month": int(current["month"]),
		"day": int(current["day"]),
		"week": _week_of_year(current),
		"week_index": new_week_index,
	}
	state.calendar = completed_calendar

	if not year_boundaries.is_empty():
		# Birth month/day is intentionally abstract in the first milestone, so age
		# changes on the first simulation week that crosses New Year's Day.
		state.age = clampi(int(current["year"]) - state.birth_year, 0, 150)

	state.weekly_time = clampi(int(state.flags.get("weekly_time_limit", LifeGameState.DEFAULT_WEEKLY_TIME)), 1, 168)
	state.energy = clampi(state.energy + int(state.flags.get("weekly_energy_recovery", 10)), 0, 100)
	state.flags["weekly_actions"] = []
	state.last_week_summary = []

	var boundary := {
		"advanced": true,
		"days": 7,
		"from": {
			"year": int(previous["year"]),
			"month": int(previous["month"]),
			"day": int(previous["day"]),
			"week": int(previous.get("week", _week_of_year(previous))),
			"week_index": previous_week_index,
		},
		"to": completed_calendar.duplicate(true),
		"from_week_index": previous_week_index,
		"to_week_index": new_week_index,
		"new_month": not month_boundaries.is_empty(),
		"new_year": not year_boundaries.is_empty(),
		"month_boundaries": month_boundaries,
		"year_boundaries": year_boundaries,
	}
	# Aliases make content/UI code readable without coupling it to implementation.
	boundary["previous_calendar"] = boundary["from"]
	boundary["current_calendar"] = boundary["to"]
	boundary["crossed_months"] = month_boundaries

	state.flags["last_calendar_boundary"] = boundary.duplicate(true)
	state.flags["calendar_advancing"] = false
	state.state_changed.emit()
	return boundary


func date_text(calendar: Dictionary) -> String:
	var date := _normalized_date(calendar)
	return "%s %d, %d" % [
		MONTH_NAMES[int(date["month"]) - 1],
		int(date["day"]),
		int(date["year"]),
	]


## Number of whole days from the displayed date to the next monthly billing day.
func days_until_next_month(calendar: Dictionary) -> int:
	var date := _normalized_date(calendar)
	return _days_in_month(int(date["year"]), int(date["month"])) - int(date["day"]) + 1


func will_cross_month_next_week(calendar: Dictionary) -> bool:
	return days_until_next_month(calendar) <= 7


func _normalized_date(value: Dictionary) -> Dictionary:
	var year := clampi(int(value.get("year", 2026)), 1900, 9999)
	var month := clampi(int(value.get("month", 1)), 1, 12)
	var day := clampi(int(value.get("day", 1)), 1, _days_in_month(year, month))
	return {
		"year": year,
		"month": month,
		"day": day,
		"week": clampi(int(value.get("week", 1)), 1, 53),
	}


func _add_one_day(date: Dictionary) -> Dictionary:
	var year := int(date["year"])
	var month := int(date["month"])
	var day := int(date["day"]) + 1
	if day > _days_in_month(year, month):
		day = 1
		month += 1
		if month > 12:
			month = 1
			year += 1
	return {"year": year, "month": month, "day": day}


func _week_of_year(date: Dictionary) -> int:
	var year := int(date["year"])
	var month := int(date["month"])
	var day_of_year := int(date["day"])
	for previous_month in range(1, month):
		day_of_year += _days_in_month(year, previous_month)
	return clampi(((day_of_year - 1) / 7) + 1, 1, 53)


func _days_in_month(year: int, month: int) -> int:
	match month:
		2:
			return 29 if _is_leap_year(year) else 28
		4, 6, 9, 11:
			return 30
		_:
			return 31


func _is_leap_year(year: int) -> bool:
	return year % 400 == 0 or (year % 4 == 0 and year % 100 != 0)
