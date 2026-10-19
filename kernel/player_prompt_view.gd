extends RefCounted
# This object holds only detached advisory intent, never a WorldState or beliefs.
var _prompts: Array = []
var _history: Array = []
const FIELDS = ["prompt_id", "prompt_type", "area_id", "recipient_command_id", "submitted_at", "received_at", "state"]

func _init(records: Array = [], history: Array = [], recipient: Variant = null) -> void:
	for record in records:
		if recipient != null and record.recipient_command_id != recipient: continue
		var safe: Dictionary = {}
		for key in FIELDS: safe[key] = record[key]
		_prompts.append(safe)
	for event in history:
		if recipient != null and event.recipient_command_id != recipient: continue
		var safe: Dictionary = {}
		for key in ["prompt_id", "prompt_type", "area_id", "recipient_command_id", "at", "event_type"]: safe[key] = event[key]
		_history.append(safe)

func current() -> Array:
	return _prompts.duplicate(true)

func status(prompt_id: String) -> Dictionary:
	for record in _prompts:
		if record.prompt_id == prompt_id: return record.duplicate(true)
	return {}

func recent_history(limit := 50) -> Array:
	return _history.slice(maxi(0, _history.size() - clampi(limit, 0, 1000))).duplicate(true)

func snapshot() -> Dictionary:
	return {"prompts": current(), "history": _history.duplicate(true)}
