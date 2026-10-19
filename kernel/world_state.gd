extends RefCounted

const TABLES = ["locations", "commands", "resource_types", "stockpiles", "logistics_edges", "communication_edges", "shipments", "resource_reservations", "messages", "information_records", "ledger", "fronts", "observation_batches", "decisions", "decision_candidates", "resource_needs", "peer_coordinations", "known_transfers", "resolution_receipts"]
var _state: Dictionary = {}
var _outgoing: Dictionary = {}
var _stock_location: Dictionary = {}
var _stock_owner: Dictionary = {}
var _beliefs: Dictionary = {}
var _information_owner: Dictionary = {}
var _inboxes: Dictionary = {}
var _reservation_shipment: Dictionary = {}
var _active: Dictionary = {"shipments": {}, "messages": {}, "fronts": {}}
var _last_events: Dictionary = {}
var _correlations: Dictionary = {}

func _init(snapshot: Dictionary = {}) -> void:
	_state = snapshot.duplicate(true)
	for table in TABLES:
		if not _state.has(table):
			_state[table] = {}
	_reindex()

func snapshot() -> Dictionary:
	return _state.duplicate(true)

func get_entity(table: String, id: String) -> Dictionary:
	return _state.get(table, {}).get(id, {}).duplicate(true)

func get_location(id: String) -> Dictionary:
	return get_entity("locations", id)

func get_command(id: String) -> Dictionary:
	return get_entity("commands", id)

func get_stockpile(id: String) -> Dictionary:
	return get_entity("stockpiles", id)

func get_shipment(id: String) -> Dictionary:
	return get_entity("shipments", id)

func get_front(id: String) -> Dictionary:
	return get_entity("fronts", id)

func has_id(id: String) -> bool:
	for table in TABLES:
		if _state[table].has(id):
			return true
	return false

func ids(table: String) -> Array:
	var result: Array = _state.get(table, {}).keys()
	result.sort()
	return result

func clock() -> Dictionary:
	return _state.clock.duplicate(true)

func sequence() -> int:
	return _state.event_sequence

func ended() -> bool:
	return _state.ended

func get_outgoing_logistics_edges(id: String) -> Array:
	return _outgoing.get("logistics_edges:" + id, []).duplicate()

func get_communication_edges(id: String) -> Array:
	return _outgoing.get("communication_edges:" + id, []).duplicate()

func stockpiles_at(id: String) -> Array:
	return _stock_location.get(id, []).duplicate()

func stockpiles_owned_by(id: String) -> Array:
	return _stock_owner.get(id, []).duplicate()

func belief_ids(owner: String, subject: String, key: String) -> Array:
	return _beliefs.get(JSON.stringify([owner, subject, key]), []).duplicate()

func information_for(owner: String) -> Array:
	return _information_owner.get(owner, []).duplicate()

func inbox_for(owner: String) -> Array:
	return _inboxes.get(owner, []).duplicate()

func shipment_for_reservation(id: String) -> Variant:
	return _reservation_shipment.get(id)

func active_ids(table: String) -> Array:
	var result: Array = _active[table].keys()
	result.sort()
	return result

func last_event(id: String) -> Variant:
	return _last_events.get(id)

func correlation(id: String) -> Variant:
	return _correlations.get(id)

# Only the event application boundary writes persistent projections.
func apply_event(event: Dictionary) -> void:
	for change in event.payload.get("changes", []):
		if change.table == "clock":
			_state.clock = change.value.duplicate(true)
		elif change.table == "run":
			for key in change.value:
				_state[key] = change.value[key]
		else:
			var old: Dictionary = _state[change.table].get(change.id, {})
			_index_entity(change.table, old, true)
			_state[change.table][change.id] = change.value.duplicate(true)
			_index_entity(change.table, change.value)
	_state.event_sequence = int(event.event_id.get_slice(":", 1))
	if event.subject_entity_id != null:
		_last_events[event.subject_entity_id] = event.event_id
		if event.correlation_id != null:
			_correlations[event.subject_entity_id] = event.correlation_id

func _index(map: Dictionary, key: String, id: String) -> void:
	if not map.has(key):
		map[key] = []
	map[key].append(id)

func _update_index(map: Dictionary, key: String, id: String, remove: bool) -> void:
	if remove:
		if map.has(key):
			map[key].erase(id)
			if map[key].is_empty():
				map.erase(key)
	else:
		_index(map, key, id)

func _index_entity(table: String, entity: Dictionary, remove := false) -> void:
	if entity.is_empty():
		return
	var id: String = entity.id
	match table:
		"logistics_edges", "communication_edges":
			_update_index(_outgoing, table + ":" + str(entity.get("from_location_id", entity.get("from_command_id", ""))), id, remove)
		"stockpiles":
			_update_index(_stock_location, entity.location_id, id, remove)
			_update_index(_stock_owner, str(entity.owner_command_id), id, remove)
		"information_records":
			_update_index(_beliefs, JSON.stringify([entity.owner_command_id, entity.subject_entity_id, entity.fact_key]), id, remove)
			_update_index(_information_owner, entity.owner_command_id, id, remove)
		"shipments":
			if remove:
				_reservation_shipment.erase(entity.reservation_id)
			else:
				_reservation_shipment[entity.reservation_id] = id
			_active.shipments.erase(id)
			if not remove and entity.state == "IN_TRANSIT":
				_active.shipments[id] = true
		"messages":
			if entity.state == "DELIVERED":
				_update_index(_inboxes, entity.recipient_command_id, id, remove)
			_active.messages.erase(id)
			if not remove and entity.state == "IN_TRANSIT":
				_active.messages[id] = true
		"fronts":
			_active.fronts.erase(id)
			if not remove and entity.enabled:
				_active.fronts[id] = true

func _reindex() -> void:
	_outgoing.clear()
	_stock_location.clear()
	_stock_owner.clear()
	_beliefs.clear()
	_information_owner.clear()
	_inboxes.clear()
	_reservation_shipment.clear()
	_active = {"shipments": {}, "messages": {}, "fronts": {}}
	for table in TABLES:
		for id in ids(table):
			_index_entity(table, _state[table][id])
