extends RefCounted
# Pure Local reasoning: detached own records and a completed observation envelope.
# No WorldState, front truth, observer, stockpile, or Operational knowledge access.
const Clock = preload("res://kernel/clock.gd")
const Planner = preload("res://kernel/local_command_planner.gd")
const KEYS = ["FRONT_FRIENDLY_STRENGTH", "FRONT_ENEMY_PRESSURE", "FRONT_POSTURE", "FRONT_AMMO_COVERAGE_MILLISECONDS", "FRONT_AMMO_COVERAGE_STATUS", "FRONT_LAST_SHORTAGE"]
const FIELDS = ["friendly_strength_centi", "enemy_pressure_centi", "posture", "ammo_coverage_milliseconds", "ammo_coverage_status", "last_shortage"]

static func sample(owner: String, front: String, records: Array, batch: Dictionary, now_micro: int) -> Dictionary:
	if batch.get("complete") != true or batch.get("command_id") != owner or batch.get("front_id") != front or not batch.get("record_ids") is Dictionary or not batch.get("observed_at_micro") is int and not batch.get("observed_at_micro") is float: return {}
	var age: int = now_micro - int(batch.observed_at_micro)
	if age < 0 or age > Planner.FRESH_MICRO: return {}
	# Accepted completion means the entire eleven-fact autonomous observation completed.
	if batch.record_ids.size() != Planner.OBSERVATION_KEYS.size(): return {}
	var by_id: Dictionary = {}
	for record in records: by_id[record.id] = record
	var result := {"observation_batch_id": batch.id, "observed_at": int(batch.observed_at_micro) / 1000000.0, "source_information_record_ids": []}
	for key in Planner.OBSERVATION_KEYS:
		var record: Dictionary = by_id.get(batch.record_ids.get(key), {})
		if record.is_empty() or record.owner_command_id != owner or record.subject_entity_id != front or record.fact_key != key or record.source_system != "FRONT_OBSERVATION" or record.source_message_id != null or Clock.units(record.observed_at) != int(batch.observed_at_micro) or Clock.units(record.received_at) > now_micro or record.expires_at != null and Clock.units(record.expires_at) <= now_micro or not Planner.valid_value(key, record.value): return {}
		# Same current-belief ordering as CommandView; no convenient historical fallback.
		var best: Dictionary = {}
		for candidate in records:
			if candidate.owner_command_id != owner or candidate.subject_entity_id != front or candidate.fact_key != key or Clock.units(candidate.received_at) > now_micro or Clock.units(candidate.observed_at) > now_micro or candidate.expires_at != null and Clock.units(candidate.expires_at) <= now_micro: continue
			if best.is_empty() or candidate.observed_at > best.observed_at or candidate.observed_at == best.observed_at and candidate.received_at > best.received_at or candidate.observed_at == best.observed_at and candidate.received_at == best.received_at and candidate.id < best.id: best = candidate
		if best.get("id") != record.id: return {}
	for index in range(KEYS.size()):
		var record: Dictionary = by_id[batch.record_ids[KEYS[index]]]
		result[FIELDS[index]] = record.value
		result.source_information_record_ids.append(record.id)
	if (result.ammo_coverage_status == "FINITE") != (result.ammo_coverage_milliseconds != null): return {}
	return result

static func payload(record: Dictionary, sample_data: Dictionary) -> Dictionary:
	var result := {"subtype": "AREA_SITUATION_REPORT", "collection_id": record.collection_id, "requirement_id": record.requirement_id, "area_id": record.area_id, "front_id": record.front_id, "reporting_command_id": record.collector_command_id, "requesting_command_id": record.owner_command_id}
	result.merge(sample_data.duplicate(true))
	result.facts = facts(result)
	return result

static func facts(payload_data: Dictionary) -> Array:
	var result: Array = []
	for index in range(KEYS.size()):
		result.append({"subject_entity_id": payload_data.front_id, "fact_key": "REPORTED_" + KEYS[index], "value": payload_data[FIELDS[index]], "observed_at": payload_data.observed_at, "confidence": 1.0})
	return result
