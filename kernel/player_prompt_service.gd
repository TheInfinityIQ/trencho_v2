extends RefCounted
# Advisory intent is authoritative input history in its own namespace. This
# service reads scope at submission; it never writes world or information data.
const R = preload("res://kernel/result.gd")
const View = preload("res://kernel/player_prompt_view.gd")
const Policy = preload("res://kernel/prompt_evaluation_policy.gd")
const Clock = preload("res://kernel/clock.gd")
const TYPES = ["DIRECT_ATTENTION", "REQUEST_ASSESSMENT"]
const SCHEMA = "2C.3.player-prompt.1"
const EVENT_FIELDS = ["schema_version", "prompt_event_id", "event_type", "prompt_id", "prompt_type", "area_id", "recipient_command_id", "at", "source_input_id", "previous_prompt_event_id"]
const EVALUATION_FIELDS = ["evaluation_id", "evaluated_at", "result", "assessment_code", "primary_report_id", "knowledge_report_ids", "knowledge_message_ids", "knowledge_reports", "evaluation_state"]
var _events: Array = []
var _prompts: Array = []
var _evaluations: Array = []
var _areas: Dictionary = {}

func _init(areas: Dictionary = {}) -> void:
	_areas = areas.duplicate(true)

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
	return {"sequence": _events.size(), "prompts": _prompts.duplicate(true), "evaluations": _evaluations.duplicate(true)}

func view(recipient: Variant = null) -> RefCounted:
	return View.new(_prompts, _events, recipient)

# Canonical event replay is also used for live writes: one projection writer.
func apply_event(event: Dictionary) -> Dictionary:
	var n := _events.size() + 1
	var evaluated: bool = event.get("event_type") == "PLAYER_PROMPT_EVALUATED"
	var fields: Array = EVENT_FIELDS + EVALUATION_FIELDS if evaluated else EVENT_FIELDS
	if event.keys().size() != fields.size() or event.keys().any(func(k): return k not in fields) or event.get("schema_version") != SCHEMA or event.get("prompt_event_id") != "player-prompt-event:%010d" % n or event.get("previous_prompt_event_id") != (null if _events.is_empty() else _events.back().prompt_event_id): return R.fail("INVALID_PROMPT_EVENT")
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
		if evaluated:
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
		var event := {"schema_version": SCHEMA, "prompt_event_id": "player-prompt-event:%010d" % (_events.size() + 1), "event_type": "PLAYER_PROMPT_EVALUATED", "prompt_id": prompt.prompt_id, "prompt_type": prompt.prompt_type, "area_id": prompt.area_id, "recipient_command_id": prompt.recipient_command_id, "at": at, "source_input_id": prompt.source_input_id, "previous_prompt_event_id": _events.back().prompt_event_id, "evaluation_id": "prompt-evaluation:%010d" % (_evaluations.size() + 1), "evaluated_at": at, "evaluation_state": "COMPLETED"}
		event.merge(result)
		var applied := apply_event(event)
		assert(applied.success)

func submit(input: Dictionary, input_id: String, at: float) -> Dictionary:
	var id := "player-prompt:%010d" % (_prompts.size() + 1)
	for type in ["PLAYER_PROMPT_SUBMITTED", "PLAYER_PROMPT_RECEIVED"]:
		var event := {"schema_version": SCHEMA, "prompt_event_id": "player-prompt-event:%010d" % (_events.size() + 1), "event_type": type, "prompt_id": id, "prompt_type": input.prompt_type, "area_id": input.area_id, "recipient_command_id": input.recipient_command_id, "at": at, "source_input_id": input_id, "previous_prompt_event_id": null if _events.is_empty() else _events.back().prompt_event_id}
		var result := apply_event(event)
		assert(result.success)
	return R.ok(id)
