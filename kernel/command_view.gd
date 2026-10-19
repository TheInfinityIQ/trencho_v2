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
