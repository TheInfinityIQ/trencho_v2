extends RefCounted
# Recipient-owned knowledge gaps only. No services/world/observer are retained.
var _requirements: Array = []
var _history: Array = []

func _init(records: Array = [], events: Array = [], owner := "") -> void:
	for record in records:
		if record.owner_command_id == owner: _requirements.append(record.duplicate(true))
	for event in events:
		if event.owner_command_id == owner: _history.append(event.duplicate(true))

func open_requirements() -> Array:
	return _requirements.duplicate(true)

func requirement(id: String) -> Dictionary:
	for record in _requirements:
		if record.requirement_id == id: return record.duplicate(true)
	return {}

func recent_history(limit := 50) -> Array:
	return _history.slice(maxi(0, _history.size() - clampi(limit, 0, 1000))).duplicate(true)

func snapshot() -> Dictionary:
	return {"requirements": open_requirements(), "history": _history.duplicate(true)}
