extends RefCounted
signal evaluation_completed(source: Dictionary)
# Advisory intent is authoritative input history in its own namespace. This
# service reads scope at submission; it never writes world or information data.
const R = preload("res://kernel/result.gd")
const View = preload("res://kernel/player_prompt_view.gd")
const Policy = preload("res://kernel/prompt_evaluation_policy.gd")
const Clock = preload("res://kernel/clock.gd")
const FollowUp = preload("res://kernel/prompt_follow_up_policy.gd")
const TYPES = ["DIRECT_ATTENTION", "REQUEST_ASSESSMENT"]
const SCHEMA = "2C.6.player-prompt.1"
const EVENT_FIELDS = ["schema_version", "prompt_event_id", "event_type", "prompt_id", "prompt_type", "area_id", "recipient_command_id", "at", "source_input_id", "previous_prompt_event_id"]
const EVALUATION_FIELDS = ["evaluation_id", "evaluated_at", "result", "assessment_code", "primary_report_id", "knowledge_report_ids", "knowledge_message_ids", "knowledge_reports", "evaluation_state"]
var _events: Array = []
var _prompts: Array = []
var _evaluations: Array = []
var _areas: Dictionary = {}
var _follow_ups: Array = []
var _satisfactions: Dictionary = {}
var _follow_up_enabled: Dictionary = {}
const FOLLOW_UP_FIELDS = ["follow_up_id", "requirement_id", "collection_id", "issued_at", "assessment_observed_at", "result", "assessment_code", "friendly_presence", "enemy_activity", "front_behavior", "ammo_condition", "source_response_message_id", "source_information_record_ids", "source_observation_batch_id", "source_local_information_record_ids", "follow_up_state", "previous_follow_up_event_id", "source_prompt_id", "source_evaluation_event_id", "source_requirement_id", "source_collection_id", "stream_sequence"]

func _init(areas: Dictionary = {}, follow_up_configuration: Array = []) -> void:
	_areas = areas.duplicate(true)
	for entry in follow_up_configuration: _follow_up_enabled[entry.operational_command_id] = entry.enabled

static func descendant(world: RefCounted, command_id: String, recipient: String) -> bool:
	var cursor: Variant = command_id
	while cursor != null:
		if cursor == recipient: return true
		var command: Dictionary = world.get_command(cursor)
		if command.is_empty(): return false
		cursor = command.superior_command_id
	return false

static func validate(input: Dictionary, areas: Dictionary, world: RefCounted) -> Dictionary:
	if input.keys().size() != 4 or input.keys().any(func(k): return k not in ["type", "prompt_type", "area_id", "recipient_command_id"]): return R.fail("INVALID_INPUT")
	for key in ["prompt_type", "area_id", "recipient_command_id"]:
		if not input.get(key) is String or input[key].is_empty(): return R.fail("INVALID_INPUT", {"field": key})
	if input.prompt_type not in TYPES: return R.fail("UNKNOWN_PROMPT_TYPE")
	if not areas.has(input.area_id): return R.fail("UNKNOWN_STRATEGIC_AREA")
	var area: Dictionary = areas[input.area_id]
	if not area.enabled: return R.fail("DISABLED_STRATEGIC_AREA")
	var recipient: Dictionary = world.get_command(input.recipient_command_id)
	if recipient.is_empty(): return R.fail("UNKNOWN_RECIPIENT_COMMAND")
	if recipient.command_level != "OPERATIONAL": return R.fail("RECIPIENT_NOT_OPERATIONAL")
	if not recipient.enabled: return R.fail("RECIPIENT_DISABLED")
	if area.front_id != null:
		if not descendant(world, world.get_front(area.front_id).responsible_command_id, recipient.id): return R.fail("AREA_OUTSIDE_COMMAND_SCOPE")
	else:
		for location in area.location_ids:
			var scoped := false
			for command_id in world.ids("commands"):
				if not descendant(world, command_id, recipient.id): continue
				var command: Dictionary = world.get_command(command_id)
				if location in command.directly_controlled_location_ids: scoped = true
				for stock_id in world.ids("stockpiles"):
					var stock: Dictionary = world.get_stockpile(stock_id)
					if stock.location_id == location and (stock.owner_command_id == command_id or stock_id in command.directly_controlled_stockpile_ids): scoped = true
			if not scoped: return R.fail("AREA_OUTSIDE_COMMAND_SCOPE")
	return R.ok()

func events() -> Array:
	return _events.duplicate(true)

func snapshot() -> Dictionary:
	return {"sequence": _events.size(), "prompts": _prompts.duplicate(true), "evaluations": _evaluations.duplicate(true), "follow_ups": _follow_ups.duplicate(true)}

func view(recipient: Variant = null) -> RefCounted:
	return View.new(_prompts, _events, recipient)

func _next_base_event_id() -> String:
	return "player-prompt-event:%010d" % (_events.size() - _follow_ups.size() + 1)

func _previous_base_event_id() -> Variant:
	var count := _events.size() - _follow_ups.size()
	return null if count == 0 else "player-prompt-event:%010d" % count

# Canonical event replay is also used for live writes: one projection writer.
func apply_event(event: Dictionary) -> Dictionary:
	var evaluated: bool = event.get("event_type") == "PLAYER_PROMPT_EVALUATED"
	var follow_up: bool = event.get("event_type") == "PLAYER_PROMPT_FOLLOW_UP_ISSUED"
	var fields: Array = EVENT_FIELDS.filter(func(k): return k != "previous_prompt_event_id") + FOLLOW_UP_FIELDS if follow_up else EVENT_FIELDS + (EVALUATION_FIELDS if evaluated else [])
	if event.keys().size() != fields.size() or event.keys().any(func(k): return k not in fields) or event.get("schema_version") != SCHEMA: return R.fail("INVALID_PROMPT_EVENT")
	if follow_up:
		if not event.stream_sequence is int or event.stream_sequence != _events.size() + 1 or event.prompt_event_id != "player-prompt-follow-up-event:%010d" % (_follow_ups.size() + 1) or event.previous_follow_up_event_id != (null if _follow_ups.is_empty() else "player-prompt-follow-up-event:%010d" % _follow_ups.size()): return R.fail("INVALID_PROMPT_EVENT")
	elif event.prompt_event_id != _next_base_event_id() or event.previous_prompt_event_id != _previous_base_event_id(): return R.fail("INVALID_PROMPT_EVENT")
	for key in ["prompt_id", "prompt_type", "area_id", "recipient_command_id", "source_input_id"]:
		if not event.get(key) is String or event[key].is_empty(): return R.fail("INVALID_PROMPT_EVENT")
	if event.prompt_type not in TYPES or not (event.get("at") is int or event.get("at") is float) or not is_finite(float(event.at)) or event.at < 0: return R.fail("INVALID_PROMPT_EVENT")
	if event.get("event_type") == "PLAYER_PROMPT_SUBMITTED":
		if event.prompt_id != "player-prompt:%010d" % (_prompts.size() + 1) or (not _prompts.is_empty() and _prompts.back().state == "SUBMITTED"): return R.fail("INVALID_PROMPT_EVENT")
		_prompts.append({"prompt_id": event.prompt_id, "prompt_type": event.prompt_type, "area_id": event.area_id, "recipient_command_id": event.recipient_command_id, "submitted_at": event.at, "received_at": null, "state": "SUBMITTED", "source_input_id": event.source_input_id, "submitted_event_id": event.prompt_event_id, "received_event_id": null, "metadata": {}})
	else:
		var prompt: Dictionary = {}
		for record in _prompts:
			if record.prompt_id == event.prompt_id: prompt = record
		if prompt.is_empty(): return R.fail("INVALID_PROMPT_EVENT")
		for key in ["prompt_id", "prompt_type", "area_id", "recipient_command_id", "source_input_id"]:
			if event[key] != prompt[key]: return R.fail("INVALID_PROMPT_EVENT")
		if follow_up:
			if not _validate_follow_up(event, prompt): return R.fail("INVALID_PROMPT_FOLLOW_UP")
			var record := {"follow_up_id": event.follow_up_id, "prompt_id": prompt.prompt_id, "owner_command_id": prompt.recipient_command_id, "area_id": prompt.area_id, "state": "ISSUED"}
			for key in FOLLOW_UP_FIELDS:
				if key != "follow_up_state": record[key] = event[key].duplicate(true) if event[key] is Array else event[key]
			_follow_ups.append(record)
			prompt.follow_up_status = "AVAILABLE"
			prompt.latest_follow_up = record.duplicate(true)
		elif evaluated:
			if not _validate_evaluation(event, prompt): return R.fail("INVALID_PROMPT_EVALUATION")
			var evaluation := {"evaluation_id": event.evaluation_id, "prompt_id": prompt.prompt_id, "recipient_command_id": prompt.recipient_command_id, "area_id": prompt.area_id, "prompt_type": prompt.prompt_type, "state": "COMPLETED", "evaluated_at": event.evaluated_at, "evaluated_event_id": event.prompt_event_id}
			for key in ["result", "assessment_code", "primary_report_id", "knowledge_report_ids", "knowledge_message_ids", "knowledge_reports"]: evaluation[key] = event[key].duplicate(true) if event[key] is Array else event[key]
			_evaluations.append(evaluation)
			prompt.state = "EVALUATED"
			for key in ["evaluation_id", "result", "assessment_code", "evaluated_at"]: prompt[key] = event[key]
			prompt.evaluated_event_id = event.prompt_event_id
		else:
			if event.get("event_type") != "PLAYER_PROMPT_RECEIVED" or prompt.state != "SUBMITTED" or event.at != prompt.submitted_at or event.previous_prompt_event_id != prompt.submitted_event_id: return R.fail("INVALID_PROMPT_EVENT")
			prompt.received_at = event.at
			prompt.received_event_id = event.prompt_event_id
			prompt.state = "PENDING_EVALUATION"
	_events.append(event.duplicate(true))
	return R.ok(event.prompt_id)

func register_satisfaction(evidence: Dictionary) -> Dictionary:
	var certified := FollowUp.certify(evidence)
	if not certified.success: return certified
	var id: String = certified.details.basis.requirement_id
	if _satisfactions.has(id) and not FollowUp.exact(_satisfactions[id], certified.details): return R.fail("INVALID_FOLLOW_UP_EVIDENCE")
	_satisfactions[id] = certified.details.duplicate(true)
	return R.ok(id)

func _initial_evaluation(prompt: Dictionary, requirement: Dictionary) -> Dictionary:
	if prompt.prompt_type != "REQUEST_ASSESSMENT" or prompt.state != "EVALUATED" or prompt.prompt_id not in requirement.source_prompt_ids or prompt.recipient_command_id != requirement.owner_command_id or prompt.area_id != requirement.area_id: return {}
	var index: int = requirement.source_prompt_ids.find(prompt.prompt_id)
	for evaluation in _evaluations:
		if evaluation.prompt_id == prompt.prompt_id and evaluation.evaluation_id == requirement.source_evaluation_ids[index] and evaluation.result == "FURTHER_INFORMATION_REQUIRED" and evaluation.assessment_code == "NO_SUPPORTED_AREA_INFORMATION" and evaluation.evaluated_at <= requirement.satisfied_at: return evaluation
	return {}

func _already_followed(prompt_id: String, requirement_id: String) -> bool:
	return _follow_ups.any(func(record): return record.prompt_id == prompt_id and record.requirement_id == requirement_id)

func _eligible_order(requirement: Dictionary) -> Array:
	var result: Array = []
	for id in requirement.source_prompt_ids:
		for prompt in _prompts:
			if prompt.prompt_id == id and not _initial_evaluation(prompt, requirement).is_empty() and not _already_followed(id, requirement.requirement_id): result.append(id)
	return result

func _validate_follow_up(event: Dictionary, prompt: Dictionary) -> bool:
	if not _follow_up_enabled.get(prompt.recipient_command_id, false) or not _satisfactions.has(event.requirement_id) or event.follow_up_id != "prompt-follow-up:%010d" % (_follow_ups.size() + 1) or event.follow_up_state != "ISSUED": return false
	var source: Dictionary = _satisfactions[event.requirement_id]
	var eligible := _eligible_order(source.requirement)
	if eligible.is_empty() or eligible[0] != prompt.prompt_id or event.at != source.basis.issued_at or not _events.is_empty() and event.at < _events.back().at: return false
	if event.source_prompt_id != prompt.prompt_id or event.source_requirement_id != event.requirement_id or event.source_collection_id != event.collection_id or event.source_evaluation_event_id != _initial_evaluation(prompt, source.requirement).get("evaluated_event_id"): return false
	for key in FollowUp.BASIS_FIELDS:
		if key in ["owner_command_id", "area_id"]:
			if source.basis[key] != (prompt.recipient_command_id if key == "owner_command_id" else prompt.area_id): return false
		elif not FollowUp.exact(event[key], source.basis[key]): return false
	return true

func issue_follow_ups(evidence: Dictionary) -> Dictionary:
	var registered := register_satisfaction(evidence)
	if not registered.success: return registered
	var source: Dictionary = _satisfactions[registered.entity_id]
	if not _follow_up_enabled.get(source.requirement.owner_command_id, false): return R.ok()
	for id in _eligible_order(source.requirement):
		var prompt: Dictionary = _prompts.filter(func(item): return item.prompt_id == id)[0]
		var event := {"schema_version": SCHEMA, "prompt_event_id": "player-prompt-follow-up-event:%010d" % (_follow_ups.size() + 1), "event_type": "PLAYER_PROMPT_FOLLOW_UP_ISSUED", "prompt_id": prompt.prompt_id, "prompt_type": prompt.prompt_type, "area_id": prompt.area_id, "recipient_command_id": prompt.recipient_command_id, "at": source.basis.issued_at, "source_input_id": prompt.source_input_id, "previous_follow_up_event_id": null if _follow_ups.is_empty() else "player-prompt-follow-up-event:%010d" % _follow_ups.size(), "follow_up_id": "prompt-follow-up:%010d" % (_follow_ups.size() + 1), "follow_up_state": "ISSUED", "source_prompt_id": prompt.prompt_id, "source_evaluation_event_id": _initial_evaluation(prompt, source.requirement).evaluated_event_id, "source_requirement_id": source.requirement.requirement_id, "source_collection_id": source.basis.collection_id}
		event.stream_sequence = _events.size() + 1
		for key in FollowUp.BASIS_FIELDS:
			if key not in ["owner_command_id", "area_id"]: event[key] = source.basis[key].duplicate(true) if source.basis[key] is Array else source.basis[key]
		var applied := apply_event(event)
		if not applied.success: return applied
	return R.ok()

func _validate_evaluation(event: Dictionary, prompt: Dictionary) -> bool:
	if prompt.state != "PENDING_EVALUATION" or not _areas.has(prompt.area_id) or event.evaluation_id != "prompt-evaluation:%010d" % (_evaluations.size() + 1) or event.evaluation_state != "COMPLETED" or event.evaluated_at != event.at or event.at <= prompt.received_at or Clock.units(event.at) % 1000000 != 0: return false
	if not event.knowledge_reports is Array or not event.knowledge_report_ids is Array or not event.knowledge_message_ids is Array: return false
	var ids: Array = []
	for report in event.knowledge_reports:
		if not report is Dictionary or report.size() != Policy.REPORT_FIELDS.size() or report.keys().any(func(k): return k not in Policy.REPORT_FIELDS): return false
		for key in ["id", "superior_command_id", "front_id", "need_id", "report_message_id"]:
			if not report.get(key) is String or report[key].is_empty(): return false
		for key in ["need_revision", "source_observed_at_micro", "report_received_at_micro"]:
			if not (report.get(key) is int or report.get(key) is float) or report[key] < 0 or report[key] != floor(report[key]): return false
		if report.need_revision < 1 or report.source_observed_at_micro > report.report_received_at_micro or report.report_received_at_micro > Clock.units(event.at) or report.id in ids: return false
		ids.append(report.id)
	var expected := Policy.evaluate(prompt, {"front_id": _areas[prompt.area_id].front_id}, event.knowledge_reports)
	for key in expected:
		if JSON.stringify(expected[key], "", true, true) != JSON.stringify(event[key], "", true, true): return false
	return true

func evaluate_pending(identity: Dictionary, reports: Array, at: float) -> void:
	if identity.get("command_level") != "OPERATIONAL" or not identity.get("enabled", false) or Clock.units(at) % 1000000 != 0: return
	for prompt in _prompts.duplicate(true):
		if prompt.state != "PENDING_EVALUATION" or prompt.recipient_command_id != identity.id or prompt.received_at >= at: continue
		var result := Policy.evaluate(prompt, {"front_id": _areas[prompt.area_id].front_id}, reports)
		var event := {"schema_version": SCHEMA, "prompt_event_id": _next_base_event_id(), "event_type": "PLAYER_PROMPT_EVALUATED", "prompt_id": prompt.prompt_id, "prompt_type": prompt.prompt_type, "area_id": prompt.area_id, "recipient_command_id": prompt.recipient_command_id, "at": at, "source_input_id": prompt.source_input_id, "previous_prompt_event_id": _previous_base_event_id(), "evaluation_id": "prompt-evaluation:%010d" % (_evaluations.size() + 1), "evaluated_at": at, "evaluation_state": "COMPLETED"}
		event.merge(result)
		var applied := apply_event(event)
		assert(applied.success)
		var source: Dictionary = {}
		for key in ["evaluation_id", "prompt_id", "recipient_command_id", "area_id", "prompt_type", "evaluated_at", "result", "assessment_code"]: source[key] = event[key]
		source.evaluated_event_id = event.prompt_event_id
		source.state = "COMPLETED"
		evaluation_completed.emit(source)

func submit(input: Dictionary, input_id: String, at: float) -> Dictionary:
	var id := "player-prompt:%010d" % (_prompts.size() + 1)
	for type in ["PLAYER_PROMPT_SUBMITTED", "PLAYER_PROMPT_RECEIVED"]:
		var event := {"schema_version": SCHEMA, "prompt_event_id": _next_base_event_id(), "event_type": type, "prompt_id": id, "prompt_type": input.prompt_type, "area_id": input.area_id, "recipient_command_id": input.recipient_command_id, "at": at, "source_input_id": input_id, "previous_prompt_event_id": _previous_base_event_id()}
		var result := apply_event(event)
		assert(result.success)
	return R.ok(id)
