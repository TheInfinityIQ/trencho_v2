extends RefCounted
# This object holds sanitized presentation values only, never WorldState,
# CommandView, record metadata, private provenance or exact battlefield values.
var _data: Dictionary
const CUES = {"FRONT_BEHAVIOR": ["HOLDING", "PRESSING", "REDUCED_ACTIVITY", "WITHDRAWING"], "FRIENDLY_PRESENCE": ["LOW", "MEDIUM", "HIGH"], "ENEMY_ACTIVITY": ["LOW", "MEDIUM", "HIGH"], "SUPPLY_DEPARTURE_VISIBLE": ["SUPPLY_MOVEMENT"], "SUPPLY_ARRIVAL_VISIBLE": ["SUPPLY_MOVEMENT"], "SUPPLY_LOSS_VISIBLE": ["SUPPLY_MOVEMENT"]}

static func valid_cue(type: String, value: Variant) -> bool:
	return CUES.has(type) and value in CUES[type]

func _init(data: Dictionary) -> void:
	_data = {"areas": [], "current": {}, "history": []}
	var areas: Dictionary = data.get("areas", {})
	var ids: Array = areas.keys()
	ids.sort()
	for id in ids:
		if not areas[id].enabled: continue
		var area := {"area_id": id, "display_name": areas[id].display_name}
		_data.areas.append(area.duplicate())
		_data.current[id] = area
	var properties := {"FRONT_BEHAVIOR": "front_behavior", "FRIENDLY_PRESENCE": "friendly_presence", "ENEMY_ACTIVITY": "enemy_activity"}
	for record in data.get("records", []):
		if not _data.current.has(record.area_id): continue
		if not valid_cue(record.observation_type, record.qualitative_value): continue
		# Explicit allowlist: provenance, generic metadata and exact source data
		# are never copied into this object, including its private backing value.
		var public_record := {"area_id": record.area_id, "observed_at": record.observed_at, "observation_type": record.observation_type, "qualitative_value": record.qualitative_value}
		_data.history.append(public_record)
		if properties.has(record.observation_type):
			_data.current[record.area_id][properties[record.observation_type]] = record.qualitative_value
		else:
			_data.current[record.area_id].last_supply_movement = public_record.duplicate()

func areas() -> Array:
	return _data.get("areas", []).duplicate(true)

func snapshot() -> Dictionary:
	return _data.duplicate(true)

func current(area_id: String) -> Dictionary:
	return _data.get("current", {}).get(area_id, {}).duplicate(true)

func recent_history(limit := 50) -> Array:
	var history: Array = _data.get("history", [])
	return history.slice(maxi(0, history.size() - clampi(limit, 0, 1000))).duplicate(true)
