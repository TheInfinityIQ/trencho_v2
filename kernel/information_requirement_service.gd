extends RefCounted
# A work-item projection, never an InformationRecord. Satisfaction uses certified
# typed references from the separate collection stream, without duplicating facts.
# Sources are typed references to completed111 evaluations, not same-stream causes.
const R = preload("res://kernel/result.gd")
const View = preload("res://kernel/information_requirement_view.gd")
const SCHEMA = "2C.5.information-requirement.1"
const TYPE = "AREA_SITUATION_ASSESSMENT"
const REASON = "PLAYER_PROMPT_INFORMATION_GAP"
const SOURCE_FIELDS = ["evaluation_id", "prompt_id", "recipient_command_id", "area_id", "prompt_type", "evaluated_at", "result", "assessment_code", "evaluated_event_id", "state"]
const EVENT_FIELDS = ["schema_version", "requirement_event_id", "event_type", "requirement_id", "requirement_type", "owner_command_id", "area_id", "state", "created_at", "last_updated_at", "at", "creation_reason", "source_prompt_id", "source_evaluation_id", "source_evaluation_event_id", "previous_requirement_event_id", "metadata"]
var _area_ids: Dictionary = {}
var _owner_ids: Array = []
var _enabled: Dictionary = {}
var _sources: Dictionary = {}
var _processed: Dictionary = {}
var _events: Array = []
var _requirements: Array = []
var _completions: Dictionary = {}

# Completion registry is certified by the collection coordinator / replay verifier.
# These are typed cross-stream references, never battlefield facts.
func register_completion(item: Dictionary) -> void:
	if item.get("state") == "COMPLETED" and item.get("result_code") == "REPORT_DELIVERED": _completions[item.collection_id] = item.duplicate(true)

func satisfy(item: Dictionary) -> Dictionary:
	var existing := _open(item.owner_command_id, item.area_id)
	if existing.is_empty() or existing.requirement_id != item.requirement_id: return R.fail("INVALID_REQUIREMENT_SATISFACTION")
	return apply_event({"schema_version": SCHEMA, "requirement_event_id": "information-requirement-event:%010d" % (_events.size() + 1), "previous_requirement_event_id": null if _events.is_empty() else _events.back().requirement_event_id, "event_type": "INFORMATION_REQUIREMENT_SATISFIED", "requirement_id": item.requirement_id, "owner_command_id": item.owner_command_id, "area_id": item.area_id, "collection_id": item.collection_id, "response_message_id": item.response_message_id, "information_record_ids": item.information_record_ids.duplicate(), "satisfied_at": item.completed_at})

func _apply_satisfied(event: Dictionary) -> Dictionary:
	var fields := ["schema_version", "requirement_event_id", "previous_requirement_event_id", "event_type", "requirement_id", "owner_command_id", "area_id", "collection_id", "response_message_id", "information_record_ids", "satisfied_at"]
	if event.size() != fields.size() or event.keys().any(func(k): return k not in fields) or event.get("schema_version") != SCHEMA or event.get("requirement_event_id") != "information-requirement-event:%010d" % (_events.size() + 1) or event.get("previous_requirement_event_id") != (null if _events.is_empty() else _events.back().requirement_event_id) or not _completions.has(event.get("collection_id")): return R.fail("INVALID_REQUIREMENT_SATISFACTION")
	var item: Dictionary = _completions[event.collection_id]
	var existing := _open(item.owner_command_id, item.area_id)
	if existing.is_empty() or existing.requirement_id != item.requirement_id or event.requirement_id != item.requirement_id or event.owner_command_id != item.owner_command_id or event.area_id != item.area_id or event.response_message_id != item.response_message_id or event.information_record_ids != item.information_record_ids or event.satisfied_at != item.completed_at or event.satisfied_at < existing.last_updated_at: return R.fail("INVALID_REQUIREMENT_SATISFACTION")
	existing.state = "SATISFIED"
	existing.satisfied_at = event.satisfied_at
	existing.last_updated_at = event.satisfied_at
	existing.satisfaction_collection_id = item.collection_id
	existing.satisfaction_message_id = item.response_message_id
	existing.satisfaction_information_record_ids = item.information_record_ids.duplicate()
	_events.append(event.duplicate(true))
	return R.ok(item.requirement_id)

func _init(areas: Dictionary = {}, owners: Array = [], configuration: Array = [], sources: Array = []) -> void:
	for id in areas: _area_ids[id] = areas[id].enabled
	_owner_ids = owners.duplicate()
	for entry in configuration: _enabled[entry.operational_command_id] = entry.enabled
	for source in sources: register_source(source)

func register_source(source: Dictionary) -> Dictionary:
	var safe: Dictionary = {}
	for field in SOURCE_FIELDS: safe[field] = source.get(field)
	for field in ["evaluation_id", "prompt_id", "recipient_command_id", "area_id", "evaluated_event_id"]:
		if not safe[field] is String or safe[field].is_empty(): return R.fail("INVALID_REQUIREMENT_SOURCE")
	if safe.state != "COMPLETED" or safe.prompt_type not in ["DIRECT_ATTENTION", "REQUEST_ASSESSMENT"] or safe.recipient_command_id not in _owner_ids or not _area_ids.get(safe.area_id, false) or not (safe.evaluated_at is int or safe.evaluated_at is float) or not is_finite(float(safe.evaluated_at)) or safe.evaluated_at < 0: return R.fail("INVALID_REQUIREMENT_SOURCE")
	if _sources.has(safe.evaluation_id) and JSON.stringify(_sources[safe.evaluation_id], "", true, true) != JSON.stringify(safe, "", true, true): return R.fail("INVALID_REQUIREMENT_SOURCE")
	_sources[safe.evaluation_id] = safe
	return R.ok()

func events() -> Array:
	return _events.duplicate(true)

func snapshot() -> Dictionary:
	return {"sequence": _events.size(), "requirements": _requirements.duplicate(true)}

func view(owner: String) -> RefCounted:
	return View.new(_requirements, _events, owner) if owner in _owner_ids else View.new()

func _open(owner: String, area: String) -> Dictionary:
	for record in _requirements:
		if record.owner_command_id == owner and record.area_id == area and record.requirement_type == TYPE and record.state == "OPEN": return record
	return {}

func consider(source: Dictionary) -> Dictionary:
	if not _enabled.get(source.get("recipient_command_id"), false): return R.ok()
	var registered := register_source(source)
	if not registered.success: return registered
	var safe: Dictionary = _sources[source.evaluation_id]
	if safe.result != "FURTHER_INFORMATION_REQUIRED" or safe.assessment_code != "NO_SUPPORTED_AREA_INFORMATION": return R.ok()
	if _processed.has(safe.evaluation_id): return R.ok(_processed[safe.evaluation_id])
	var existing := _open(safe.recipient_command_id, safe.area_id)
	var id: String = "information-requirement:%010d" % (_requirements.size() + 1) if existing.is_empty() else existing.requirement_id
	var event := {"schema_version": SCHEMA, "requirement_event_id": "information-requirement-event:%010d" % (_events.size() + 1), "event_type": "INFORMATION_REQUIREMENT_OPENED" if existing.is_empty() else "INFORMATION_REQUIREMENT_LINKED", "requirement_id": id, "requirement_type": TYPE, "owner_command_id": safe.recipient_command_id, "area_id": safe.area_id, "state": "OPEN", "created_at": safe.evaluated_at if existing.is_empty() else existing.created_at, "last_updated_at": safe.evaluated_at, "at": safe.evaluated_at, "creation_reason": REASON, "source_prompt_id": safe.prompt_id, "source_evaluation_id": safe.evaluation_id, "source_evaluation_event_id": safe.evaluated_event_id, "previous_requirement_event_id": null if _events.is_empty() else _events.back().requirement_event_id, "metadata": {}}
	return apply_event(event)

func on_evaluation(source: Dictionary) -> void:
	var result := consider(source)
	assert(result.success)

func apply_event(event: Dictionary) -> Dictionary:
	if event.get("event_type") == "INFORMATION_REQUIREMENT_SATISFIED": return _apply_satisfied(event)
	if event.size() != EVENT_FIELDS.size() or event.keys().any(func(k): return k not in EVENT_FIELDS) or event.get("schema_version") != SCHEMA or event.get("requirement_event_id") != "information-requirement-event:%010d" % (_events.size() + 1) or event.get("previous_requirement_event_id") != (null if _events.is_empty() else _events.back().requirement_event_id): return R.fail("INVALID_REQUIREMENT_EVENT")
	if event.requirement_type != TYPE or event.state != "OPEN" or event.creation_reason != REASON or not event.metadata is Dictionary or not event.metadata.is_empty() or not _enabled.get(event.owner_command_id, false) or event.owner_command_id not in _owner_ids or not _area_ids.get(event.area_id, false) or not _sources.has(event.source_evaluation_id): return R.fail("INVALID_REQUIREMENT_EVENT")
	var source: Dictionary = _sources[event.source_evaluation_id]
	if source.result != "FURTHER_INFORMATION_REQUIRED" or source.assessment_code != "NO_SUPPORTED_AREA_INFORMATION" or source.prompt_id != event.source_prompt_id or source.recipient_command_id != event.owner_command_id or source.area_id != event.area_id or source.evaluated_event_id != event.source_evaluation_event_id or source.evaluated_at != event.at or event.last_updated_at != event.at or _processed.has(source.evaluation_id): return R.fail("INVALID_REQUIREMENT_SOURCE")
	var existing := _open(event.owner_command_id, event.area_id)
	if event.event_type == "INFORMATION_REQUIREMENT_OPENED":
		if not existing.is_empty() or event.requirement_id != "information-requirement:%010d" % (_requirements.size() + 1) or event.created_at != event.at: return R.fail("INVALID_REQUIREMENT_EVENT")
		_requirements.append({"requirement_id": event.requirement_id, "requirement_type": TYPE, "owner_command_id": event.owner_command_id, "area_id": event.area_id, "state": "OPEN", "created_at": event.at, "last_updated_at": event.at, "source_prompt_ids": [event.source_prompt_id], "source_evaluation_ids": [event.source_evaluation_id], "creation_reason": REASON, "metadata": {}})
	elif event.event_type == "INFORMATION_REQUIREMENT_LINKED":
		if existing.is_empty() or event.requirement_id != existing.requirement_id or event.created_at != existing.created_at or event.at < existing.last_updated_at or event.source_prompt_id in existing.source_prompt_ids or event.source_evaluation_id in existing.source_evaluation_ids: return R.fail("INVALID_REQUIREMENT_EVENT")
		existing.source_prompt_ids.append(event.source_prompt_id)
		existing.source_evaluation_ids.append(event.source_evaluation_id)
		existing.last_updated_at = event.at
	else: return R.fail("INVALID_REQUIREMENT_EVENT")
	_processed[source.evaluation_id] = event.requirement_id
	_events.append(event.duplicate(true))
	return R.ok(event.requirement_id)
