extends RefCounted
# Replaceable prototype policy: integers only; no world/service/view reference.
const ORDER = ["HOLD", "REDUCE_ACTIVITY", "PRESS"]
const CRITICAL_MS = 5000
const CONSTRAINED_MS = 15000
const ADVANTAGE = 2000
const LARGE_ADVANTAGE = 4000

static func factors(values: Dictionary) -> Dictionary:
	var shortage: int = values.FRONT_LAST_SHORTAGE
	var status: String = values.FRONT_AMMO_COVERAGE_STATUS
	var supply := "NO_ACTIVE_DEMAND"
	if shortage > 0 or (status == "FINITE" and values.FRONT_AMMO_COVERAGE_MILLISECONDS < CRITICAL_MS):
		supply = "CRITICAL"
	elif status == "FINITE":
		supply = "CONSTRAINED" if values.FRONT_AMMO_COVERAGE_MILLISECONDS < CONSTRAINED_MS else "SECURE"
	elif status == "OUT_OF_RANGE":
		supply = "SECURE"
	var margin: int = values.FRONT_FRIENDLY_STRENGTH - values.FRONT_ENEMY_PRESSURE
	var strength := "CONTESTED"
	if margin >= ADVANTAGE:
		strength = "STRONG_ADVANTAGE"
	elif margin <= -ADVANTAGE:
		strength = "STRONG_DISADVANTAGE"
	return {"supply_state": supply, "strength_state": strength, "strength_margin_centi": margin, "recent_shortage": shortage > 0}

static func evaluate(values: Dictionary) -> Dictionary:
	var state := factors(values)
	var candidates: Array = []
	for action in ORDER:
		var candidate := {"action": action, "eligible": true, "score": null, "factor_contributions": {}, "rejection_reasons": []}
		var f: Dictionary = candidate.factor_contributions
		match action:
			"HOLD":
				f.BASE = 50
				if state.strength_state == "CONTESTED": f.CONTESTED = 20
				if state.supply_state == "CONSTRAINED": f.CONSTRAINED_SUPPLY = 15
				if state.supply_state == "SECURE": f.SECURE_SUPPLY = 10
				if state.supply_state == "CRITICAL": f.CRITICAL_SUPPLY = -20
			"REDUCE_ACTIVITY":
				f.BASE = 20
				if state.recent_shortage: f.RECENT_AMMO_SHORTAGE = 100
				if state.supply_state == "CRITICAL": f.CRITICAL_SUPPLY = 60
				if state.supply_state == "CONSTRAINED": f.CONSTRAINED_SUPPLY = 25
				if state.strength_state == "STRONG_DISADVANTAGE": f.STRONG_DISADVANTAGE = 10
				if state.supply_state == "SECURE": f.SECURE_SUPPLY = -20
			"PRESS":
				if state.supply_state != "SECURE": candidate.rejection_reasons.append("SUPPLY_NOT_SECURE")
				if state.strength_margin_centi < ADVANTAGE: candidate.rejection_reasons.append("INSUFFICIENT_STRENGTH_MARGIN")
				if state.recent_shortage: candidate.rejection_reasons.append("RECENT_AMMO_SHORTAGE")
				candidate.eligible = candidate.rejection_reasons.is_empty()
				if candidate.eligible:
					f.BASE = 30
					f.STRENGTH_ADVANTAGE = 40
					if state.strength_margin_centi >= LARGE_ADVANTAGE: f.LARGE_STRENGTH_ADVANTAGE = 20
					f.SECURE_SUPPLY = 20
		if candidate.eligible:
			candidate.score = 0
			for contribution in f.values():
				candidate.score += contribution
		candidates.append(candidate)
	var selection := select(candidates)
	return {"classifications": state, "candidates": candidates, "selected_action": selection.action, "tie_break": selection.tie_break}

static func select(candidates: Array) -> Dictionary:
	var best: Dictionary = {}
	var tied := false
	for action in ORDER:
		for candidate in candidates:
			if candidate.action != action or not candidate.eligible:
				continue
			if best.is_empty() or candidate.score > best.score:
				best = candidate
				tied = false
			elif candidate.score == best.score:
				tied = true
	return {"action": best.get("action"), "tie_break": tied}
