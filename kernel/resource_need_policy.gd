extends RefCounted
const Planner = preload("res://kernel/local_command_planner.gd")
const Policy104 = preload("res://kernel/decision_policy_104.gd")
const TARGET_MS = 20000

static func sample(view: RefCounted, front_id: String, batch: Dictionary, now_micro: int) -> Dictionary:
	var observed := Planner.sample(view, front_id, batch, now_micro)
	if not observed.success:
		return observed
	var values: Dictionary = observed.values
	if values.FRONT_INTERVAL_CONSUMED > values.FRONT_INTERVAL_DEMAND or values.FRONT_LAST_SHORTAGE != values.FRONT_INTERVAL_DEMAND - values.FRONT_INTERVAL_CONSUMED:
		observed.success = false
		observed.reasons.append("INVALID_INTERVAL_OBSERVATION")
		return observed
	# Bounds follow the accepted front maximum (900000 ammo/second under PRESS).
	if values.FRONT_AMMO_DEMAND_RATE > 900000000 or values.FRONT_INTERVAL_DEMAND > 900000:
		observed.success = false
		observed.reasons.append("UNSUPPORTED_PLANNING_RATE")
		return observed
	var rate := maxi(int(values.FRONT_AMMO_DEMAND_RATE), int(values.FRONT_INTERVAL_DEMAND) * 1000)
	@warning_ignore("integer_division")
	var target: int = (rate * TARGET_MS + 999999) / 1000000
	observed.planning_rate_milli = rate
	observed.target_stock_quantity = target
	observed.supply_state = Policy104.factors(values).supply_state
	observed.urgency = observed.supply_state if observed.supply_state in ["CRITICAL", "CONSTRAINED"] else "REFILL"
	return observed

static func available(stock: Dictionary) -> int:
	return maxi(0, int(stock.get("quantities", {}).get("AMMUNITION", 0)) - int(stock.get("reserved", {}).get("AMMUNITION", 0)))

static func sources(view: RefCounted, protected_stock: int, donor := false) -> Array:
	var assignment: Dictionary = view.front_assignment()
	var front_stock: String = assignment.get("supply_stockpile_id", "")
	var result: Array = []
	var active: Array = view.protected_front_stockpile_ids()
	for stock in view.controlled_stockpiles():
		if not stock.enabled or stock.id == front_stock or stock.id in active:
			continue
		if available(stock) > 0: result.append({"stockpile_id": stock.id, "quantity": available(stock)})
	if donor:
		var stock: Dictionary = view.local_stockpile(front_stock)
		if not stock.is_empty() and stock.enabled:
			var spare := maxi(0, available(stock) - protected_stock)
			if spare > 0: result.append({"stockpile_id": front_stock, "quantity": spare})
	return result
