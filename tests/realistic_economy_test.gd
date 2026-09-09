extends SceneTree

const StateClass = preload("res://scripts/core/LifeGameState.gd")
const CalendarClass = preload("res://scripts/systems/CalendarSystem.gd")
const EconomyClass = preload("res://scripts/systems/EconomySystem.gd")
const VehicleClass = preload("res://scripts/systems/VehicleFinanceSystem.gd")

var failures: Array[String] = []


func _initialize() -> void:
	_test_biweekly_itemized_payroll()
	_test_monthly_living_costs_and_overdue()
	_test_vehicle_finance_and_running_costs()
	_test_travel_managed_handoff()
	if failures.is_empty():
		print("REALISTIC_ECONOMY_PASS: biweekly net payroll, itemized taxes, living-cost arrears, vehicle loans, insurance, fuel, maintenance, sale, and idempotence")
		quit(0)
	else:
		for failure in failures:
			push_error("REALISTIC_ECONOMY_FAIL: %s" % failure)
		quit(1)


func _test_biweekly_itemized_payroll() -> void:
	var state = StateClass.new(9001)
	var calendar = CalendarClass.new()
	var economy = EconomyClass.new()
	state.cash = 5000
	state.employment = {"job_id": "test_job", "title": "Test Technician", "weekly_pay": 1000, "active": true}
	economy.enable_realistic_finances(state, {
		"first_paycheck_wait_weeks": 1,
		"living_costs": {
			"phone": {"active": false},
			"groceries": {"active": false},
			"household": {"active": false},
			"healthcare": {"active": false}
		},
		"transport_mode": "walk_cycle"
	})
	var opening_cash: int = state.cash
	calendar.advance_one_week(state)
	var first := economy.process_week(state, {})
	var first_cash: int = state.cash
	_check(_category_count(state, "employment_income") == 1, "The first migrated pay period should deposit one partial paycheck.")
	_check(_category_count(state, "paycheck_net") == 1, "Paycheck ledger should include a transparent net-pay memo.")
	_check(_tax_total(state) > 0 and first_cash > opening_cash and first_cash < opening_cash + 1000, "Gross wages should be reduced by itemized withholding.")
	_check(_contains_text(first, "paycheck"), "Weekly summary should explain gross, withholding, and net pay.")
	var ledger_after_first: int = state.ledger.size()
	economy.process_week(state, {})
	_check(state.ledger.size() == ledger_after_first, "Realistic payroll must be idempotent within the same week.")

	calendar.advance_one_week(state)
	economy.process_week(state, {})
	_check(_category_count(state, "employment_income") == 1, "The off-pay week must accrue wages without depositing another paycheck.")
	calendar.advance_one_week(state)
	economy.process_week(state, {})
	_check(_category_count(state, "employment_income") == 2, "The next paycheck must arrive exactly two processed weeks later.")
	var profile: Dictionary = economy.get_financial_profile(state)
	var paycheck: Dictionary = profile.get("paycheck", {})
	_check(int(paycheck.get("accrued_gross", -1)) == 0 and int(profile.get("payroll", {}).get("last_gross", 0)) == 2000, "A regular biweekly check should contain exactly two weekly gross rates.")


func _test_monthly_living_costs_and_overdue() -> void:
	var state = StateClass.new(9002)
	var calendar = CalendarClass.new()
	var economy = EconomyClass.new()
	state.cash = 100
	state.calendar = {"year": 2026, "month": 1, "day": 26, "week": 4, "week_index": 0}
	economy.enable_realistic_finances(state, {
		"living_costs": {
			"phone": {"amount": 70, "active": true},
			"groceries": {"amount": 300, "active": true},
			"household": {"active": false},
			"healthcare": {"active": false}
		},
		"transport_mode": "public_transit"
	})
	calendar.advance_one_week(state)
	economy.process_week(state, {})
	_check(state.cash == 0, "Scheduled realistic bills should use available cash without leaving a negative balance.")
	_check(economy.get_overdue_total(state) > 0, "Unpaid phone, groceries, or transport should persist as overdue obligations.")
	_check(_category_suffix_count(state, "_overdue") > 0, "Missed scheduled costs should create reasoned overdue ledger rows.")
	var saved: Dictionary = state.to_dict()
	var restored = StateClass.new()
	_check(restored.from_dict(saved) and economy.get_overdue_total(restored) == economy.get_overdue_total(state), "Overdue balances should survive save/load through flags.")


func _test_vehicle_finance_and_running_costs() -> void:
	var state = StateClass.new(9003)
	var calendar = CalendarClass.new()
	var economy = EconomyClass.new()
	var vehicles = VehicleClass.new()
	state.cash = 20000
	state.skills["driving"] = 100
	state.employment = {"job_id": "test_job", "title": "Route Coordinator", "weekly_pay": 1500, "active": true}
	state.calendar = {"year": 2026, "month": 1, "day": 26, "week": 4, "week_index": 0}
	economy.enable_realistic_finances(state, {"first_paycheck_wait_weeks": 1})
	_check(vehicles.get_catalog().size() >= 6, "The realistic vehicle catalog should provide multiple price and cost tiers.")
	var quote := vehicles.quote_finance(state, "parkside_compact_2014")
	_check(bool(quote.get("valid", false)) and int(quote.get("monthly_payment", 0)) > 0 and int(quote.get("due_today", 0)) > 0, "Finance quotes should expose down payment, fees, APR term, and monthly payment.")
	var purchase := vehicles.purchase_financed(state, "parkside_compact_2014", economy)
	_check(not vehicles.get_owned(state).is_empty() and purchase.contains("Financed"), "An eligible player should be able to finance a vehicle.")
	_check(_category_count(state, "vehicle_down_payment") == 1 and vehicles.get_loan_balance(state) > 0, "The down payment and secured loan balance should be tracked separately.")
	var before_process_entries: int = state.ledger.size()
	calendar.advance_one_week(state)
	var summary := economy.process_week(state, {})
	var after_process_entries: int = state.ledger.size()
	_check(_category_count(state, "vehicle_fuel") == 1, "Using a car for work should charge weekly fuel or electricity.")
	_check(_category_count(state, "vehicle_payment") == 1 and _category_count(state, "vehicle_insurance") == 1 and _category_count(state, "vehicle_maintenance") == 1, "A month boundary should itemize payment, insurance, and maintenance exactly once.")
	_check(after_process_entries > before_process_entries and _contains_text(summary, "insurance"), "Vehicle costs should appear in both the ledger and readable week summary.")
	economy.process_week(state, {})
	_check(state.ledger.size() == after_process_entries, "Repeated economy processing must not duplicate vehicle costs.")
	var balance_before_sale := vehicles.get_loan_balance(state)
	var sale := vehicles.sell(state, economy)
	_check(balance_before_sale > 0 and vehicles.get_owned(state).is_empty() and sale.contains("Sold"), "Selling should remove the vehicle and pay off the remaining secured loan.")
	_check(_category_count(state, "vehicle_sale") == 1 and _category_count(state, "vehicle_loan_payoff") == 1, "Vehicle sale proceeds and loan payoff should be separate ledger movements.")


func _test_travel_managed_handoff() -> void:
	var state = StateClass.new(9004)
	var economy = EconomyClass.new()
	state.employment = {"job_id": "test_job", "title": "Office Assistant", "weekly_pay": 800, "active": true}
	economy.enable_realistic_finances(state, {"transport_mode": "travel_managed"})
	var costs: Array[Dictionary] = economy.get_monthly_living_costs(state)
	var has_generic_transport := false
	for cost in costs:
		if str(cost.get("id", "")) == "transport":
			has_generic_transport = true
	var preview: Dictionary = economy.get_paycheck_preview(state)
	var deductions: Dictionary = preview.get("deductions", {})
	_check(not has_generic_transport, "travel_managed mode must suppress EconomySystem's generic transport bill.")
	_check(int(deductions.get("city_tax", -1)) == 0, "travel_managed mode must leave city-local payroll tax to TravelSystem.")


func _category_count(state, category: String) -> int:
	var count := 0
	for entry in state.ledger:
		if str(entry.get("category", "")) == category:
			count += 1
	return count


func _category_suffix_count(state, suffix: String) -> int:
	var count := 0
	for entry in state.ledger:
		if str(entry.get("category", "")).ends_with(suffix):
			count += 1
	return count


func _tax_total(state) -> int:
	var total := 0
	for entry in state.ledger:
		if str(entry.get("category", "")) in ["federal_tax", "state_tax", "city_tax", "payroll_tax"]:
			total += -int(entry.get("amount", 0))
	return total


func _contains_text(lines: Array, fragment: String) -> bool:
	for line in lines:
		if str(line).to_lower().contains(fragment.to_lower()):
			return true
	return false


func _check(condition: bool, message: String) -> void:
	if not condition:
		failures.append(message)
