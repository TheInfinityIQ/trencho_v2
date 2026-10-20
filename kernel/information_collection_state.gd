extends RefCounted
const R = preload("res://kernel/result.gd")
const SCHEMA = "2C.5.information-collection.1"
const FIELDS = ["collection_id", "requirement_id", "owner_command_id", "collector_command_id", "area_id", "front_id", "method", "state", "created_at", "completed_at", "request_message_id", "response_message_id", "source_observation_batch_id", "source_information_record_ids", "information_record_ids", "result_code", "failure_event_id"]
const EVENT_FIELDS = ["schema_version", "collection_event_id", "previous_collection_event_id", "event_type", "at", "source_authoritative_event_id", "record"]
const TRANSITIONS = {"INFORMATION_COLLECTION_REQUEST_SENT": ["REQUEST_PENDING", "REQUEST_IN_TRANSIT"], "INFORMATION_COLLECTION_WAITING": ["REQUEST_IN_TRANSIT", "WAITING_FOR_LOCAL_OBSERVATION"], "INFORMATION_COLLECTION_REPORT_SENT": ["REQUEST_IN_TRANSIT", "REPORT_IN_TRANSIT"], "INFORMATION_COLLECTION_COMPLETED": ["REPORT_IN_TRANSIT", "COMPLETED"]}
var _records: Array = []
var _events: Array = []

func records() -> Array:
	return _records.duplicate(true)

func events() -> Array:
	return _events.duplicate(true)

func snapshot() -> Dictionary:
	return {"sequence": _events.size(), "collections": records()}

func record(id: String) -> Dictionary:
	for item in _records:
		if item.collection_id == id: return item.duplicate(true)
	return {}

func for_requirement(id: String) -> Dictionary:
	for item in _records:
		if item.requirement_id == id: return item.duplicate(true)
	return {}

func emit_record(type: String, item: Dictionary, at: float, cause: Variant = null) -> Dictionary:
	return apply_event({"schema_version": SCHEMA, "collection_event_id": "information-collection-event:%010d" % (_events.size() + 1), "previous_collection_event_id": null if _events.is_empty() else _events.back().collection_event_id, "event_type": type, "at": at, "source_authoritative_event_id": cause, "record": item.duplicate(true)})

func apply_event(event: Dictionary) -> Dictionary:
	if event.size() != EVENT_FIELDS.size() or event.keys().any(func(k): return k not in EVENT_FIELDS) or event.get("schema_version") != SCHEMA or event.get("collection_event_id") != "information-collection-event:%010d" % (_events.size() + 1) or event.get("previous_collection_event_id") != (null if _events.is_empty() else _events.back().collection_event_id) or not event.get("record") is Dictionary or not (event.get("at") is int or event.get("at") is float) or not is_finite(float(event.at)) or event.at < 0 or not _events.is_empty() and event.at < _events.back().at: return R.fail("INVALID_COLLECTION_EVENT")
	var item: Dictionary = event.record
	if item.size() != FIELDS.size() or item.keys().any(func(k): return k not in FIELDS) or item.method != "SUBORDINATE_SITUATION_REPORT" or not item.source_information_record_ids is Array or not item.information_record_ids is Array: return R.fail("INVALID_COLLECTION_EVENT")
	for key in ["collection_id", "requirement_id", "owner_command_id", "collector_command_id", "area_id", "front_id"]:
		if not item[key] is String or item[key].is_empty(): return R.fail("INVALID_COLLECTION_EVENT")
	var prior := record(item.collection_id)
	if event.event_type == "INFORMATION_COLLECTION_STARTED":
		if not prior.is_empty() or not for_requirement(item.requirement_id).is_empty() or item.collection_id != "information-collection:%010d" % (_records.size() + 1) or item.state != "REQUEST_PENDING" or item.created_at != event.at or item.completed_at != null or item.request_message_id != null or item.response_message_id != null or item.source_observation_batch_id != null or not item.source_information_record_ids.is_empty() or not item.information_record_ids.is_empty() or item.result_code != null or item.failure_event_id != null: return R.fail("INVALID_COLLECTION_EVENT")
		_records.append(item.duplicate(true))
	else:
		if prior.is_empty() or prior.state in ["COMPLETED", "UNAVAILABLE"]: return R.fail("INVALID_COLLECTION_EVENT")
		var mutable := ["state", "completed_at", "request_message_id", "response_message_id", "source_observation_batch_id", "source_information_record_ids", "information_record_ids", "result_code", "failure_event_id"]
		for key in FIELDS:
			if key not in mutable and prior[key] != item[key]: return R.fail("INVALID_COLLECTION_EVENT")
		for key in ["request_message_id", "response_message_id", "source_observation_batch_id"]:
			if prior[key] != null and prior[key] != item[key]: return R.fail("INVALID_COLLECTION_EVENT")
		if event.event_type == "INFORMATION_COLLECTION_UNAVAILABLE":
			if item.state != "UNAVAILABLE" or item.result_code not in ["NO_COMMUNICATION_ROUTE", "NO_RETURN_COMMUNICATION_ROUTE", "LOCAL_OBSERVATION_UNAVAILABLE", "REQUEST_MESSAGE_FAILED", "RESPONSE_MESSAGE_FAILED"] or item.completed_at != event.at: return R.fail("INVALID_COLLECTION_EVENT")
		else:
			if not TRANSITIONS.has(event.event_type): return R.fail("INVALID_COLLECTION_EVENT")
			var transition: Array = TRANSITIONS[event.event_type]
			if item.state != transition[1] or prior.state != transition[0] and not (event.event_type == "INFORMATION_COLLECTION_REPORT_SENT" and prior.state == "WAITING_FOR_LOCAL_OBSERVATION"): return R.fail("INVALID_COLLECTION_EVENT")
			if not item.request_message_id is String: return R.fail("INVALID_COLLECTION_EVENT")
			if item.state in ["REPORT_IN_TRANSIT", "COMPLETED"] and (not item.response_message_id is String or not item.source_observation_batch_id is String or item.source_information_record_ids.size() != 6): return R.fail("INVALID_COLLECTION_EVENT")
			if item.state == "COMPLETED":
				if item.completed_at != event.at or item.result_code != "REPORT_DELIVERED" or item.information_record_ids.size() != 6: return R.fail("INVALID_COLLECTION_EVENT")
			elif item.completed_at != null or item.result_code != null or not item.information_record_ids.is_empty(): return R.fail("INVALID_COLLECTION_EVENT")
		if item.state in ["REQUEST_IN_TRANSIT", "WAITING_FOR_LOCAL_OBSERVATION"] and (item.response_message_id != null or item.source_observation_batch_id != null or not item.source_information_record_ids.is_empty()): return R.fail("INVALID_COLLECTION_EVENT")
		if item.state != "UNAVAILABLE" and item.failure_event_id != null: return R.fail("INVALID_COLLECTION_EVENT")
		for index in range(_records.size()):
			if _records[index].collection_id == item.collection_id: _records[index] = item.duplicate(true)
	_events.append(event.duplicate(true))
	return R.ok(item.collection_id)
