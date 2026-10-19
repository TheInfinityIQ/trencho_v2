extends RefCounted
# Advisory intent is authoritative input history in its own namespace. This
# service reads scope at submission; it never writes world or information data.
const R = preload("res://kernel/result.gd")
const View = preload("res://kernel/player_prompt_view.gd")
const TYPES = ["DIRECT_ATTENTION", "REQUEST_ASSESSMENT"]
const SCHEMA = "2C.2.player-prompt.1"
const EVENT_FIELDS = ["schema_version", "prompt_event_id", "event_type", "prompt_id", "prompt_type", "area_id", "recipient_command_id", "at", "source_input_id", "previous_prompt_event_id"]
var _events: Array = []
var _prompts: Array = []

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
	return {"sequence": _events.size(), "prompts": _prompts.duplicate(true)}

func view(recipient: Variant = null) -> RefCounted:
	return View.new(_prompts, _events, recipient)

# Canonical event replay is also used for live writes: one projection writer.
func apply_event(event: Dictionary) -> Dictionary:
	var n := _events.size() + 1
	if event.keys().size() != EVENT_FIELDS.size() or event.keys().any(func(k): return k not in EVENT_FIELDS) or event.get("schema_version") != SCHEMA or event.get("prompt_event_id") != "player-prompt-event:%010d" % n or event.get("previous_prompt_event_id") != (null if _events.is_empty() else _events.back().prompt_event_id): return R.fail("INVALID_PROMPT_EVENT")
	for key in ["prompt_id", "prompt_type", "area_id", "recipient_command_id", "source_input_id"]:
		if not event.get(key) is String or event[key].is_empty(): return R.fail("INVALID_PROMPT_EVENT")
	if event.prompt_type not in TYPES or not (event.get("at") is int or event.get("at") is float) or not is_finite(float(event.at)) or event.at < 0: return R.fail("INVALID_PROMPT_EVENT")
	if n % 2 == 1:
		if event.get("event_type") != "PLAYER_PROMPT_SUBMITTED" or event.prompt_id != "player-prompt:%010d" % (_prompts.size() + 1): return R.fail("INVALID_PROMPT_EVENT")
		_prompts.append({"prompt_id": event.prompt_id, "prompt_type": event.prompt_type, "area_id": event.area_id, "recipient_command_id": event.recipient_command_id, "submitted_at": event.at, "received_at": null, "state": "SUBMITTED", "source_input_id": event.source_input_id, "submitted_event_id": event.prompt_event_id, "received_event_id": null, "metadata": {}})
	else:
		var prompt: Dictionary = _prompts.back()
		if event.get("event_type") != "PLAYER_PROMPT_RECEIVED" or event.at != prompt.submitted_at: return R.fail("INVALID_PROMPT_EVENT")
		for key in ["prompt_id", "prompt_type", "area_id", "recipient_command_id", "source_input_id"]:
			if event[key] != prompt[key]: return R.fail("INVALID_PROMPT_EVENT")
		prompt.received_at = event.at
		prompt.received_event_id = event.prompt_event_id
		prompt.state = "PENDING_EVALUATION"
	_events.append(event.duplicate(true))
	return R.ok(event.prompt_id)

func submit(input: Dictionary, input_id: String, at: float) -> Dictionary:
	var id := "player-prompt:%010d" % (_prompts.size() + 1)
	for type in ["PLAYER_PROMPT_SUBMITTED", "PLAYER_PROMPT_RECEIVED"]:
		var event := {"schema_version": SCHEMA, "prompt_event_id": "player-prompt-event:%010d" % (_events.size() + 1), "event_type": type, "prompt_id": id, "prompt_type": input.prompt_type, "area_id": input.area_id, "recipient_command_id": input.recipient_command_id, "at": at, "source_input_id": input_id, "previous_prompt_event_id": null if _events.is_empty() else _events.back().prompt_event_id}
		var result := apply_event(event)
		assert(result.success)
	return R.ok(id)
