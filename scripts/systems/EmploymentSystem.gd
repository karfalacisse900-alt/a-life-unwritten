class_name EmploymentSystem
extends RefCounted

const JOBS_PATH := "res://data/jobs.json"
const COURSES_PATH := "res://data/courses.json"
const EMPLOYMENT_PROCESS_FLAG := "employment_system_processed_week"

var _jobs: Array[Dictionary] = []
var _courses: Array[Dictionary] = []


func _init() -> void:
	_jobs = _load_entries(JOBS_PATH, "jobs")
	_courses = _load_entries(COURSES_PATH, "courses")


func get_jobs() -> Array[Dictionary]:
	if _jobs.is_empty():
		_jobs = _load_entries(JOBS_PATH, "jobs")
	return _duplicate_entries(_jobs)


func get_courses() -> Array[Dictionary]:
	if _courses.is_empty():
		_courses = _load_entries(COURSES_PATH, "courses")
	return _duplicate_entries(_courses)


func get_job(job_id: String) -> Dictionary:
	for job in _jobs:
		if str(job.get("id", "")) == job_id:
			return job.duplicate(true)
	return {}


func get_course(course_id: String) -> Dictionary:
	for course in _courses:
		if str(course.get("id", "")) == course_id:
			return course.duplicate(true)
	return {}


func eligible(state, job: Dictionary) -> bool:
	return bool(eligibility_details(state, job).get("eligible", false))


func eligibility_details(state, job: Dictionary) -> Dictionary:
	var reasons: Array[String] = []
	if job.is_empty():
		reasons.append("That job listing no longer exists.")
		return {"eligible": false, "reasons": reasons}
	if _is_jailed(state):
		reasons.append("You cannot attend an interview while jailed.")

	var requirements: Dictionary = job.get("requirements", {})
	var min_health := int(requirements.get("min_health", 0))
	if int(state.health) < min_health:
		reasons.append("Requires at least %d health." % min_health)
	var min_reputation := int(requirements.get("min_reputation", -100))
	if int(state.reputation) < min_reputation:
		reasons.append("Requires at least %d reputation." % min_reputation)
	var max_convictions := int(requirements.get("max_convictions", 999))
	if _conviction_count(state) > max_convictions:
		reasons.append("Your criminal record does not meet the employer's policy.")

	var required_education: Array = requirements.get("education", [])
	for education_id_value in required_education:
		var education_id := str(education_id_value)
		if not state.education.has(education_id):
			reasons.append("Requires %s." % _humanize_id(education_id))

	var skill_requirements: Dictionary = requirements.get("skills", {})
	for skill_id_value in skill_requirements.keys():
		var skill_id := str(skill_id_value)
		var required_level := int(skill_requirements.get(skill_id_value, 0))
		var current_level := int(state.skills.get(skill_id, 0))
		if current_level < required_level:
			reasons.append("Requires %s %d (you have %d)." % [_humanize_id(skill_id), required_level, current_level])

	var application_hours := int(job.get("application_hours", 4))
	if int(state.weekly_time) < application_hours:
		reasons.append("The interview needs %d free hours this week." % application_hours)

	return {"eligible": reasons.is_empty(), "reasons": reasons, "reason": _join_strings(reasons)}


func apply(state, job_id: String) -> String:
	var job := get_job(job_id)
	if job.is_empty():
		return "That job listing is no longer available."
	var details := eligibility_details(state, job)
	if not bool(details.get("eligible", false)):
		var reasons: Array = details.get("reasons", [])
		return "You cannot apply for %s: %s" % [str(job.get("title", "this job")), " ".join(reasons)]

	var application_hours := int(job.get("application_hours", 4))
	if not _spend_time(state, application_hours, "Interview for %s" % str(job.get("title", "job"))):
		return "There is not enough free time left for that interview."

	var interview_score := _interview_score(state, job)
	var random_swing := int(state.randi_seeded(25)) - 12
	var final_score := interview_score + random_swing
	var hired := final_score >= 52
	var job_title := str(job.get("title", "Job"))
	if not hired:
		state.stress = clampi(int(state.stress) + 2, 0, 100)
		state.add_history("Interviewed for %s but was not selected." % job_title)
		return "The %s interview went reasonably, but another candidate was selected. Build relevant skills and try again." % job_title

	var had_previous_job := not str(state.employment.get("job_id", "")).is_empty()
	var previous_title := str(state.employment.get("title", ""))
	state.employment = {
		"job_id": job_id,
		"title": job_title,
		"weekly_pay": int(job.get("weekly_pay", 0)),
		"schedule_hours": int(job.get("schedule_hours", 0)),
		"hours_per_week": int(job.get("schedule_hours", 0)),
		"performance": clampi(55 + int((final_score - 52) / 3), 50, 70),
		"weeks": 0,
		"active": true,
		"promotion_level": 0,
		"last_reviewed_week": -1
	}
	state.happiness = clampi(int(state.happiness) + 4, 0, 100)
	state.stress = clampi(int(state.stress) + 1, 0, 100)
	state.add_history("Hired as %s." % job_title)
	if not had_previous_job:
		return "You handled the interview well and were hired as %s. Pay begins when the next week is processed." % job_title
	return "You were hired as %s, replacing your previous %s role." % [job_title, previous_title]


func resign(state) -> String:
	if str(state.employment.get("job_id", "")).is_empty():
		return "You do not currently have a job to resign from."
	var title := str(state.employment.get("title", "your job"))
	if not _spend_time(state, 1, "Resignation paperwork"):
		return "You need 1 free hour to finish the resignation paperwork."
	state.employment = {
		"job_id": "",
		"title": "Unemployed",
		"weekly_pay": 0,
		"performance": 50,
		"weeks": 0,
		"hours_per_week": 0,
		"active": false
	}
	state.stress = clampi(int(state.stress) - 4, 0, 100)
	state.reputation = clampi(int(state.reputation) - 1, -100, 100)
	state.add_history("Resigned from %s." % title)
	return "You resigned from %s. There will be no further weekly pay from that job." % title


func course_eligibility_details(state, course: Dictionary) -> Dictionary:
	var reasons: Array[String] = []
	if course.is_empty():
		reasons.append("That course is unavailable.")
		return {"eligible": false, "reasons": reasons}
	var course_id := str(course.get("id", ""))
	if state.education.has(course_id):
		reasons.append("You already completed this qualification.")
	for activity in state.active_activities:
		if str(activity.get("type", "")) == "course" and str(activity.get("id", "")) == course_id:
			reasons.append("You are already enrolled in this course.")
		break
	var requirements: Dictionary = course.get("requirements", {})
	var min_age := int(requirements.get("min_age", 0))
	if int(state.age) < min_age:
		reasons.append("You must be at least %d." % min_age)
	var max_stress := int(requirements.get("max_stress", 100))
	if int(state.stress) > max_stress:
		reasons.append("Your stress is too high to enroll right now.")
	var cost := int(course.get("cost", 0))
	if int(state.cash) < cost:
		reasons.append("Enrollment costs $%s, but you have $%s." % [_money(cost), _money(int(state.cash))])
	var enrollment_hours := int(course.get("enrollment_hours", 1))
	if int(state.weekly_time) < enrollment_hours:
		reasons.append("Enrollment needs %d free hours this week." % enrollment_hours)
	return {"eligible": reasons.is_empty(), "reasons": reasons, "reason": _join_strings(reasons)}


func start_course(state, course_id: String, economy = null) -> String:
	var course := get_course(course_id)
	var details := course_eligibility_details(state, course)
	if not bool(details.get("eligible", false)):
		return "You cannot enroll: %s" % " ".join(details.get("reasons", []))
	var hours := int(course.get("enrollment_hours", 1))
	if not _spend_time(state, hours, "Enroll in %s" % str(course.get("name", "course"))):
		return "There is not enough free time left to enroll."
	var cost := int(course.get("cost", 0))
	if cost > 0:
		_record_money(state, economy, -cost, "%s tuition" % str(course.get("name", "Course")), "education")
	state.active_activities.append({
		"type": "course",
		"id": course_id,
		"name": str(course.get("name", "Course")),
		"weeks_remaining": int(course.get("duration_weeks", 1)),
		"weekly_hours": int(course.get("weekly_hours", 1)),
		"progress": 0,
		"required_progress": int(course.get("duration_weeks", 1)),
		"started_week": int(state.calendar.get("week_index", 0))
	})
	state.add_history("Enrolled in %s." % str(course.get("name", "a course")))
	return "Enrollment confirmed. The course takes %d hours for %d weeks; missed weeks pause progress." % [int(course.get("weekly_hours", 1)), int(course.get("duration_weeks", 1))]


func enroll_course(state, course_id: String, economy = null) -> String:
	return start_course(state, course_id, economy)


func process_week(state) -> Array[String]:
	var summary: Array[String] = []
	var week_index := int(state.calendar.get("week_index", 0))
	if int(state.flags.get(EMPLOYMENT_PROCESS_FLAG, -1)) == week_index:
		return summary
	state.flags[EMPLOYMENT_PROCESS_FLAG] = week_index
	if bool(state.employment.get("dismissal_pending", false)):
		var ended_title := str(state.employment.get("title", "your job"))
		state.employment = _empty_employment()
		state.add_history("Employment as %s ended after notice." % ended_title)
		summary.append("Your dismissal notice took effect before this week's schedule, so no pay was earned.")
		return summary
	if _is_jailed(state):
		if not str(state.employment.get("job_id", "")).is_empty():
			state.employment["suspended"] = true
			state.employment["suspension_reason"] = "jail"
			summary.append("Jail prevented you from attending your normal work schedule; no work hours were spent.")
		if _has_active_course(state):
			summary.append("Your course progress paused while you were in jail.")
		return summary
	if str(state.employment.get("suspension_reason", "")) == "jail":
		state.employment["suspended"] = false
		state.employment.erase("suspension_reason")

	_process_job_week(state, summary)
	_process_course_weeks(state, summary)
	return summary


func _process_job_week(state, summary: Array[String]) -> void:
	var job_id := str(state.employment.get("job_id", ""))
	if job_id.is_empty():
		return
	var job := get_job(job_id)
	if job.is_empty():
		summary.append("Your former employer closed the listed role; employment records were cleared.")
		state.employment = {}
		return

	var title := str(state.employment.get("title", job.get("title", "Job")))
	var schedule_hours := int(state.employment.get("schedule_hours", job.get("schedule_hours", 0)))
	var attended := _spend_time(state, schedule_hours, "%s work schedule" % title)
	var performance := int(state.employment.get("performance", 55))
	var delta := 0
	if not attended:
		delta = -10
		state.stress = clampi(int(state.stress) + 5, 0, 100)
		summary.append("You could not cover the full %d-hour %s schedule; performance fell." % [schedule_hours, title])
	else:
		var condition_score := int(state.health) + int(state.happiness) - int(state.stress)
		delta += 2 if condition_score >= 80 else (-2 if condition_score < 35 else 0)
		var skill_id := str(job.get("performance_skill", ""))
		var skill_level := int(state.skills.get(skill_id, 0))
		delta += 2 if skill_level >= 30 else (-1 if skill_level < 10 else 0)
		delta += int(state.randi_seeded(5)) - 2
		if state.traits.has("focused"):
			delta += 1
		performance = clampi(performance + delta, 0, 100)
		state.stress = clampi(int(state.stress) + (2 if schedule_hours >= 38 else 1), 0, 100)
		summary.append("You completed %d scheduled hours at %s; performance is %d." % [schedule_hours, title, performance])

	state.employment["performance"] = clampi(performance + (delta if not attended else 0), 0, 100)
	state.employment["weeks"] = int(state.employment.get("weeks", 0)) + 1
	state.employment["last_reviewed_week"] = int(state.calendar.get("week_index", 0))

	if _try_promotion(state, job, summary):
		return
	var weeks_worked := int(state.employment.get("weeks", 0))
	var current_performance := int(state.employment.get("performance", 0))
	if weeks_worked >= 4 and current_performance < 20:
		var dismissal_risk := clampi(25 + (20 - current_performance) * 3, 25, 85)
		if int(state.randi_seeded(100)) < dismissal_risk:
			state.employment["dismissal_pending"] = true
			state.reputation = clampi(int(state.reputation) - 4, -100, 100)
			state.stress = clampi(int(state.stress) + 8, 0, 100)
			state.add_history("Received dismissal notice from %s after sustained poor performance." % title)
			summary.append("%s issued a dismissal notice after repeated performance problems. This final worked week will still be paid." % title)


func _try_promotion(state, job: Dictionary, summary: Array[String]) -> bool:
	if int(state.employment.get("promotion_level", 0)) > 0:
		return false
	var promotion: Dictionary = job.get("promotion", {})
	if promotion.is_empty():
		return false
	if int(state.employment.get("weeks", 0)) < int(promotion.get("min_weeks", 999999)):
		return false
	if int(state.employment.get("performance", 0)) < int(promotion.get("min_performance", 101)):
		return false
	var skill_requirements: Dictionary = promotion.get("skill_requirements", {})
	for skill_key in skill_requirements.keys():
		if int(state.skills.get(str(skill_key), 0)) < int(skill_requirements.get(skill_key, 0)):
			return false
	var old_title := str(state.employment.get("title", "your role"))
	var new_title := str(promotion.get("title", old_title))
	state.employment["title"] = new_title
	state.employment["weekly_pay"] = int(promotion.get("weekly_pay", state.employment.get("weekly_pay", 0)))
	state.employment["promotion_level"] = 1
	state.happiness = clampi(int(state.happiness) + 6, 0, 100)
	state.reputation = clampi(int(state.reputation) + 4, -100, 100)
	state.add_history("Promoted from %s to %s." % [old_title, new_title])
	summary.append("Strong results earned a promotion to %s at $%s per week." % [new_title, _money(int(state.employment.get("weekly_pay", 0)))])
	return true


func _process_course_weeks(state, summary: Array[String]) -> void:
	var remaining_activities: Array[Dictionary] = []
	for activity_value in state.active_activities:
		var activity: Dictionary = activity_value
		if str(activity.get("type", "")) != "course":
			remaining_activities.append(activity)
			continue
		var course_id := str(activity.get("id", ""))
		var course := get_course(course_id)
		if course.is_empty():
			summary.append("A discontinued course was removed from your activities.")
			continue
		var bonus_progress := maxi(0, int(activity.get("progress", 0)))
		if bonus_progress > 0:
			activity["weeks_remaining"] = maxi(0, int(activity.get("weeks_remaining", 1)) - bonus_progress)
			activity["progress"] = 0
			if int(activity["weeks_remaining"]) <= 0:
				_complete_course(state, course, summary)
				continue
		var weekly_hours := int(activity.get("weekly_hours", course.get("weekly_hours", 1)))
		if not _spend_time(state, weekly_hours, "%s classes" % str(course.get("name", "Course"))):
			remaining_activities.append(activity)
			state.stress = clampi(int(state.stress) + 2, 0, 100)
			summary.append("You lacked %d free hours for %s, so progress paused." % [weekly_hours, str(course.get("name", "your course"))])
			continue
		activity["weeks_remaining"] = int(activity.get("weeks_remaining", 1)) - 1
		if int(activity["weeks_remaining"]) > 0:
			remaining_activities.append(activity)
			summary.append("You attended %s; %d week(s) remain." % [str(course.get("name", "your course")), int(activity["weeks_remaining"])])
			continue
		_complete_course(state, course, summary)
	state.active_activities = remaining_activities


func _complete_course(state, course: Dictionary, summary: Array[String]) -> void:
	var award := str(course.get("education_award", course.get("id", "")))
	if not award.is_empty() and not state.education.has(award):
		state.education.append(award)
	var rewards: Dictionary = course.get("skill_rewards", {})
	for skill_key in rewards.keys():
		var skill_id := str(skill_key)
		state.skills[skill_id] = clampi(int(state.skills.get(skill_id, 0)) + int(rewards.get(skill_key, 0)), 0, 100)
	state.happiness = clampi(int(state.happiness) + int(course.get("completion_happiness", 0)), 0, 100)
	state.reputation = clampi(int(state.reputation) + int(course.get("completion_reputation", 0)), -100, 100)
	var course_name := str(course.get("name", "Course"))
	state.add_history("Completed %s." % course_name)
	summary.append("You completed %s and gained its qualification and skill rewards." % course_name)


func _interview_score(state, job: Dictionary) -> int:
	var score := 42
	var preferred: Dictionary = job.get("preferred_skills", {})
	for skill_key in preferred.keys():
		var target := maxi(1, int(preferred.get(skill_key, 1)))
		var level := int(state.skills.get(str(skill_key), 0))
		score += mini(9, int(level * 9.0 / target))
	score += int((int(state.health) - 50) / 10)
	score += int((int(state.reputation) - 40) / 8)
	score -= maxi(0, int(state.stress) - 50) / 7
	score -= _conviction_count(state) * 10
	if state.traits.has("charming"):
		score += 5
	if state.traits.has("focused"):
		score += 3
	return score


func _is_jailed(state) -> bool:
	return bool(state.crime.get("in_jail", state.crime.get("jailed", false))) or int(state.crime.get("jail_weeks", state.crime.get("jail_weeks_remaining", 0))) > 0


func _conviction_count(state) -> int:
	if state.crime.has("convictions"):
		var convictions_value = state.crime.get("convictions")
		if convictions_value is Array:
			return convictions_value.size()
		return int(convictions_value)
	if state.crime.has("criminal_record"):
		var record_value = state.crime.get("criminal_record")
		if record_value is Array:
			return record_value.size()
		return int(record_value)
	if state.crime.has("record") and state.crime.get("record") is Array:
		return state.crime.get("record").size()
	return 0


func _has_active_course(state) -> bool:
	for activity in state.active_activities:
		if str(activity.get("type", "")) == "course":
			return true
	return false


func _empty_employment() -> Dictionary:
	return {
		"job_id": "",
		"title": "Unemployed",
		"weekly_pay": 0,
		"performance": 50,
		"weeks": 0,
		"hours_per_week": 0,
		"active": false
	}


func _spend_time(state, hours: int, reason: String) -> bool:
	if hours <= 0:
		return true
	if state.has_method("spend_time"):
		return bool(state.spend_time(hours, reason))
	if int(state.weekly_time) < hours:
		return false
	state.weekly_time = int(state.weekly_time) - hours
	return true


func _record_money(state, economy, amount: int, reason: String, category: String) -> void:
	if economy != null and economy.has_method("record"):
		economy.record(state, amount, reason, category)
		return
	state.cash = int(state.cash) + amount
	var sequence := maxi(int(state.flags.get("ledger_sequence", state.ledger.size())), state.ledger.size()) + 1
	state.flags["ledger_sequence"] = sequence
	state.ledger.append({
		"id": sequence,
		"week_index": int(state.calendar.get("week_index", 0)),
		"date": "%04d-%02d-%02d" % [int(state.calendar.get("year", 0)), int(state.calendar.get("month", 1)), int(state.calendar.get("day", 1))],
		"amount": amount,
		"reason": reason,
		"category": category,
		"balance_after": int(state.cash),
		"account": "cash"
	})


func _load_entries(path: String, key: String) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	if not FileAccess.file_exists(path):
		push_error("EmploymentSystem content missing: %s" % path)
		return entries
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		push_error("EmploymentSystem could not open: %s" % path)
		return entries
	var parsed = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary:
		push_error("EmploymentSystem expected a JSON object in %s" % path)
		return entries
	var raw_entries = parsed.get(key, [])
	if not raw_entries is Array:
		push_error("EmploymentSystem expected '%s' to be an array in %s" % [key, path])
		return entries
	for raw_entry in raw_entries:
		if raw_entry is Dictionary and not str(raw_entry.get("id", "")).is_empty():
			entries.append(raw_entry)
	return entries


func _duplicate_entries(entries: Array[Dictionary]) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	for entry in entries:
		result.append(entry.duplicate(true))
	return result


func _join_strings(values: Array) -> String:
	var parts := PackedStringArray()
	for value in values:
		parts.append(str(value))
	return " ".join(parts)


func _humanize_id(value: String) -> String:
	return value.replace("_", " ").capitalize()


func _money(value: int) -> String:
	var raw := str(absi(value))
	var formatted := ""
	while raw.length() > 3:
		formatted = "," + raw.right(3) + formatted
		raw = raw.left(raw.length() - 3)
	formatted = raw + formatted
	return ("-" if value < 0 else "") + formatted
