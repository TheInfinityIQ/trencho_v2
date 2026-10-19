extends RefCounted
# Reasoning boundary: only a detached CommandView and the observation envelope enter.
const Clock = preload("res://kernel/clock.gd")
const Policy = preload("res://kernel/decision_policy_104.gd")
const REQUIRED = ["FRONT_FRIENDLY_STRENGTH", "FRONT_ENEMY_PRESSURE", "FRONT_POSTURE", "FRONT_AMMO_AVAILABLE", "FRONT_AMMO_DEMAND_RATE", "FRONT_AMMO_COVERAGE_MILLISECONDS", "FRONT_AMMO_COVERAGE_STATUS", "FRONT_LAST_SHORTAGE"]
const OBSERVATION_KEYS = REQUIRED + ["FRONT_AMMO_ON_HAND", "FRONT_INTERVAL_DEMAND", "FRONT_INTERVAL_CONSUMED"]
const FRESH_MICRO = 1500000

static func sample(view: RefCounted, front_id: String, batch: Dictionary, now_micro: int) -> Dictionary:
	var result := {"success": true, "reasons": [], "missing_keys": [], "stale_keys": [], "inconsistent_keys": [], "invalid_keys": [], "values": {}, "belief_record_ids": [], "records": {}, "outcome_values": {}, "outcome_record_ids": []}
	if not batch.complete:
		result.reasons.append("INCOMPLETE_OBSERVATION_BATCH")
	if view == null:
		result.reasons.append("MISSING_REQUIRED_BELIEF")
		result.success = false
		return result
	for key in OBSERVATION_KEYS:
		var record: Dictionary = view.current_belief(front_id, key, now_micro / 1000000.0)
		if record.is_empty():
			result.missing_keys.append(key)
			continue
		result.belief_record_ids.append(record.id)
		result.records[key] = record
		result.values[key] = int(record.value) if (record.value is int or record.value is float) and is_finite(float(record.value)) else record.value
		if now_micro - Clock.units(record.observed_at) > FRESH_MICRO:
			result.stale_keys.append(key)
		if batch.record_ids.get(key) != record.id or Clock.units(record.observed_at) != batch.observed_at_micro:
			result.inconsistent_keys.append(key)
		if not valid_value(key, record.value):
			result.invalid_keys.append(key)
	if not result.missing_keys.is_empty():
		result.reasons.append("MISSING_REQUIRED_BELIEF")
		if not result.reasons.has("INCOMPLETE_OBSERVATION_BATCH"): result.reasons.append("INCOMPLETE_OBSERVATION_BATCH")
	if not result.stale_keys.is_empty(): result.reasons.append("STALE_REQUIRED_BELIEF")
	if not result.inconsistent_keys.is_empty() and not result.reasons.has("INCOMPLETE_OBSERVATION_BATCH"): result.reasons.append("INCOMPLETE_OBSERVATION_BATCH")
	if not result.invalid_keys.is_empty(): result.reasons.append("INVALID_REQUIRED_BELIEF")
	# Coverage value/status form one canonical pair.
	if result.reasons.is_empty():
		var value: Variant = result.values.FRONT_AMMO_COVERAGE_MILLISECONDS
		var status: String = result.values.FRONT_AMMO_COVERAGE_STATUS
		if (status == "FINITE") != (value != null):
			result.reasons.append("INVALID_REQUIRED_BELIEF")
	for key in ["FRONT_INTERVAL_DEMAND", "FRONT_INTERVAL_CONSUMED"]:
		var record: Dictionary = view.current_belief(front_id, key, now_micro / 1000000.0)
		if not record.is_empty() and batch.record_ids.get(key) == record.id and Clock.units(record.observed_at) == batch.observed_at_micro and now_micro - Clock.units(record.observed_at) <= FRESH_MICRO and valid_value(key, record.value):
			result.outcome_values[key] = int(record.value)
			result.outcome_record_ids.append(record.id)
	result.success = result.reasons.is_empty()
	return result

static func valid_value(key: String, value: Variant) -> bool:
	if key == "FRONT_POSTURE":
		return value is String and value in ["HOLD", "PRESS", "REDUCE_ACTIVITY", "WITHDRAW"]
	if key == "FRONT_AMMO_COVERAGE_STATUS":
		return value is String and value in ["FINITE", "ZERO_DEMAND", "OUT_OF_RANGE"]
	if key == "FRONT_AMMO_COVERAGE_MILLISECONDS" and value == null:
		return true
	if not (value is int or value is float) or not is_finite(float(value)) or value != floor(value) or value < 0 or value > 9007199254740991:
		return false
	if key in ["FRONT_FRIENDLY_STRENGTH", "FRONT_ENEMY_PRESSURE"]:
		return value <= 10000
	return true

static func evaluate(view: RefCounted, front_id: String, batch: Dictionary, now_micro: int) -> Dictionary:
	var observed := sample(view, front_id, batch, now_micro)
	if observed.success:
		observed.policy = Policy.evaluate(observed.values)
	return observed

static func outcome(start: Dictionary, finish: Dictionary, interval: Dictionary, decision: Dictionary, end_micro: int) -> Dictionary:
	return {"decision_id": decision.id, "evaluation_start_time_micro": decision.selected_at_micro, "evaluation_end_time_micro": end_micro, "selected_action": decision.selected_action, "starting_ammo_available": start.FRONT_AMMO_AVAILABLE, "ending_ammo_available": finish.FRONT_AMMO_AVAILABLE, "starting_coverage_status": start.FRONT_AMMO_COVERAGE_STATUS, "starting_coverage_ms": start.FRONT_AMMO_COVERAGE_MILLISECONDS, "ending_coverage_status": finish.FRONT_AMMO_COVERAGE_STATUS, "ending_coverage_ms": finish.FRONT_AMMO_COVERAGE_MILLISECONDS, "interval_demand": interval.FRONT_INTERVAL_DEMAND, "interval_consumed": interval.FRONT_INTERVAL_CONSUMED, "interval_shortage": finish.FRONT_LAST_SHORTAGE, "starting_enemy_pressure": start.FRONT_ENEMY_PRESSURE, "ending_enemy_pressure": finish.FRONT_ENEMY_PRESSURE, "starting_friendly_strength": start.FRONT_FRIENDLY_STRENGTH, "ending_friendly_strength": finish.FRONT_FRIENDLY_STRENGTH}
