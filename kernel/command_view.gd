extends RefCounted

# A detached, filtered value object: no raw WorldState or service reference escapes.
var _data: Dictionary

func _init(data: Dictionary) -> void:
	_data = data.duplicate(true)

func identity() -> Dictionary:
	return _data.identity.duplicate(true)

func local_stockpile(id: String) -> Dictionary:
	return _data.stockpiles.get(id, {}).duplicate(true)

func local_location(id: String) -> Dictionary:
	return _data.locations.get(id, {}).duplicate(true)

func inbox() -> Array:
	return _data.messages.duplicate(true)

func information() -> Array:
	return _data.information_records.duplicate(true)

func public_facts() -> Dictionary:
	return _data.public_facts.duplicate(true)

func current_belief(subject: String, key: String, at_time: float) -> Dictionary:
	var records: Array = []
	for record in _data.information_records:
		if record.subject_entity_id == subject and record.fact_key == key and record.received_at <= at_time and record.observed_at <= at_time and (record.expires_at == null or record.expires_at > at_time):
			records.append(record)
	records.sort_custom(func(a, b):
		if a.observed_at != b.observed_at:
			return a.observed_at > b.observed_at
		if a.received_at != b.received_at:
			return a.received_at > b.received_at
		return a.id < b.id)
	return {} if records.is_empty() else records[0].duplicate(true)

# Explicit own-authority/known-network surfaces, not foreign inventories/front truth.
func controlled_stockpiles() -> Array:
	var ids: Array = _data.stockpiles.keys()
	ids.sort()
	var result: Array = []
	for id in ids: result.append(_data.stockpiles[id].duplicate(true))
	return result

func front_assignment() -> Dictionary:
	return _data.get("front_assignment", {}).duplicate(true)

func protected_front_stockpile_ids() -> Array:
	return _data.get("protected_front_stockpile_ids", []).duplicate()

func peers() -> Array:
	return _data.get("peers", []).duplicate(true)

func direct_superior() -> Dictionary:
	return _data.get("direct_superior", {}).duplicate(true)

func communication_route(command_id: String) -> Dictionary:
	return _data.get("communication_routes", {}).get(command_id, {}).duplicate(true)

func known_incoming() -> Array:
	return _data.get("known_incoming", []).duplicate(true)

func superior_need_reports() -> Array:
	return _data.get("superior_need_reports", []).duplicate(true)
