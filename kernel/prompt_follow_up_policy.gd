extends RefCounted
# Pure interpretation of a certified acquisition chain. No WorldState, observer,
# current knowledge lookup, Local private beliefs, or service reference enters.
const R = preload("res://kernel/result.gd")
const Report = preload("res://kernel/subordinate_report_policy.gd")
const Values = preload("res://kernel/local_command_planner.gd")
const Observer = preload("res://kernel/player_observer.gd")
const PUBLIC_FIELDS = ["result", "assessment_code", "friendly_presence", "enemy_activity", "front_behavior", "ammo_condition", "assessment_observed_at", "issued_at"]
const BASIS_FIELDS = ["requirement_id", "collection_id", "owner_command_id", "area_id", "issued_at", "assessment_observed_at", "source_response_message_id", "source_information_record_ids", "source_observation_batch_id", "source_local_information_record_ids", "result", "assessment_code", "friendly_presence", "enemy_activity", "front_behavior", "ammo_condition"]

static func exact(a: Variant, b: Variant) -> bool:
	return JSON.stringify(a, "", true, true) == JSON.stringify(b, "", true, true)

static func qualitative(values: Dictionary) -> Dictionary:
	var status: String = values.FRONT_AMMO_COVERAGE_STATUS
	var ammo := "SECURE"
	if values.FRONT_LAST_SHORTAGE > 0: ammo = "SHORTAGE_REPORTED"
	elif status == "ZERO_DEMAND": ammo = "NO_ACTIVE_DEMAND"
	elif status == "FINITE":
		if values.FRONT_AMMO_COVERAGE_MILLISECONDS < 5000: ammo = "CRITICAL"
		elif values.FRONT_AMMO_COVERAGE_MILLISECONDS < 15000: ammo = "CONSTRAINED"
	return {"result": "ASSESSMENT_AVAILABLE", "assessment_code": "COLLECTED_AREA_SITUATION_ASSESSMENT", "friendly_presence": Observer.band(int(values.FRONT_FRIENDLY_STRENGTH)), "enemy_activity": Observer.band(int(values.FRONT_ENEMY_PRESSURE)), "front_behavior": Observer.BEHAVIORS[values.FRONT_POSTURE], "ammo_condition": ammo}

static func certify(evidence: Dictionary) -> Dictionary:
	if evidence.size() != 4 or evidence.keys().any(func(k): return k not in ["requirement", "collection", "response", "information_records"]): return R.fail("INVALID_FOLLOW_UP_EVIDENCE")
	for key in ["requirement", "collection", "response"]:
		if not evidence.get(key) is Dictionary: return R.fail("INVALID_FOLLOW_UP_EVIDENCE")
	if not evidence.get("information_records") is Array or evidence.information_records.size() != 6: return R.fail("INVALID_FOLLOW_UP_EVIDENCE")
	var req: Dictionary = evidence.requirement
	var collection: Dictionary = evidence.collection
	var response: Dictionary = evidence.response
	for key in ["requirement_id", "owner_command_id", "area_id", "satisfaction_collection_id", "satisfaction_message_id", "satisfied_at", "satisfaction_information_record_ids", "source_prompt_ids", "source_evaluation_ids"]:
		if not req.has(key): return R.fail("INVALID_FOLLOW_UP_EVIDENCE")
	for key in ["collection_id", "requirement_id", "owner_command_id", "collector_command_id", "area_id", "front_id", "completed_at", "response_message_id", "source_observation_batch_id", "source_information_record_ids", "information_record_ids"]:
		if not collection.has(key): return R.fail("INVALID_FOLLOW_UP_EVIDENCE")
	for key in ["id", "sender_command_id", "recipient_command_id", "sent_at", "delivery_time", "payload"]:
		if not response.has(key): return R.fail("INVALID_FOLLOW_UP_EVIDENCE")
	if not req.satisfaction_information_record_ids is Array or req.satisfaction_information_record_ids.size() != 6 or not req.source_prompt_ids is Array or not req.source_evaluation_ids is Array or req.source_prompt_ids.size() != req.source_evaluation_ids.size() or req.source_prompt_ids.is_empty() or not collection.source_information_record_ids is Array or collection.source_information_record_ids.size() != 6 or not collection.source_observation_batch_id is String: return R.fail("INVALID_FOLLOW_UP_EVIDENCE")
	for value in [req.requirement_id, req.owner_command_id, req.area_id, req.satisfaction_collection_id, req.satisfaction_message_id, collection.collection_id, collection.collector_command_id, collection.front_id, collection.source_observation_batch_id, response.id] + req.satisfaction_information_record_ids + collection.source_information_record_ids + req.source_prompt_ids + req.source_evaluation_ids:
		if not value is String or value.is_empty(): return R.fail("INVALID_FOLLOW_UP_EVIDENCE")
	for value in [req.satisfied_at, response.sent_at, response.delivery_time]:
		if not (value is int or value is float) or not is_finite(float(value)) or value < 0: return R.fail("INVALID_FOLLOW_UP_EVIDENCE")
	if req.get("state") != "SATISFIED" or req.get("requirement_type") != "AREA_SITUATION_ASSESSMENT" or req.get("creation_reason") != "PLAYER_PROMPT_INFORMATION_GAP" or collection.get("state") != "COMPLETED" or collection.get("result_code") != "REPORT_DELIVERED" or collection.get("method") != "SUBORDINATE_SITUATION_REPORT" or response.get("state") != "DELIVERED" or response.get("message_type") != "REPORT": return R.fail("INVALID_FOLLOW_UP_EVIDENCE")
	if collection.get("requirement_id") != req.requirement_id or collection.get("collection_id") != req.satisfaction_collection_id or collection.get("response_message_id") != req.satisfaction_message_id or collection.get("owner_command_id") != req.owner_command_id or collection.get("area_id") != req.area_id or collection.get("information_record_ids") != req.satisfaction_information_record_ids or collection.get("completed_at") != req.satisfied_at or response.get("id") != req.satisfaction_message_id or response.get("recipient_command_id") != req.owner_command_id or response.get("sender_command_id") != collection.get("collector_command_id") or response.get("delivery_time") != req.satisfied_at or not response.get("payload") is Dictionary: return R.fail("INVALID_FOLLOW_UP_EVIDENCE")
	var payload: Dictionary = response.payload
	if payload.get("subtype") != "AREA_SITUATION_REPORT" or payload.get("collection_id") != collection.collection_id or payload.get("requirement_id") != req.requirement_id or payload.get("area_id") != req.area_id or payload.get("front_id") != collection.get("front_id") or payload.get("observation_batch_id") != collection.get("source_observation_batch_id") or payload.get("source_information_record_ids") != collection.get("source_information_record_ids") or payload.get("requesting_command_id") != req.owner_command_id or payload.get("reporting_command_id") != collection.collector_command_id: return R.fail("INVALID_FOLLOW_UP_EVIDENCE")
	var values: Dictionary = {}
	var seen: Array = []
	for index in range(Report.KEYS.size()):
		var record: Variant = evidence.information_records[index]
		if not record is Dictionary: return R.fail("INVALID_FOLLOW_UP_EVIDENCE")
		var key: String = Report.KEYS[index]
		if record.get("id") != req.satisfaction_information_record_ids[index] or record.get("id") in seen or record.get("owner_command_id") != req.owner_command_id or record.get("source_command_id") != collection.collector_command_id or record.get("source_message_id") != response.id or record.get("source_system") != null or record.get("subject_entity_id") != collection.front_id or record.get("fact_key") != "REPORTED_" + key or record.get("observed_at") != payload.get("observed_at") or record.get("received_at") != req.satisfied_at or record.get("confidence") != 1 or not record.has("value") or not Values.valid_value(key, record.value) or not payload.has(Report.FIELDS[index]) or not exact(record.value, payload[Report.FIELDS[index]]): return R.fail("INVALID_FOLLOW_UP_EVIDENCE")
		seen.append(record.id)
		values[key] = record.value
	if (values.FRONT_AMMO_COVERAGE_STATUS == "FINITE") != (values.FRONT_AMMO_COVERAGE_MILLISECONDS != null): return R.fail("INVALID_FOLLOW_UP_EVIDENCE")
	if not (payload.get("observed_at") is int or payload.get("observed_at") is float) or not is_finite(float(payload.observed_at)) or payload.observed_at < 0 or payload.observed_at > response.sent_at or not payload.get("facts") is Array or not exact(payload.facts, Report.facts(payload)): return R.fail("INVALID_FOLLOW_UP_EVIDENCE")
	var basis := {"requirement_id": req.requirement_id, "collection_id": collection.collection_id, "owner_command_id": req.owner_command_id, "area_id": req.area_id, "issued_at": req.satisfied_at, "assessment_observed_at": payload.observed_at, "source_response_message_id": response.id, "source_information_record_ids": seen, "source_observation_batch_id": collection.source_observation_batch_id, "source_local_information_record_ids": collection.source_information_record_ids.duplicate()}
	basis.merge(qualitative(values))
	return R.ok(null, {"basis": basis, "requirement": req.duplicate(true)})
