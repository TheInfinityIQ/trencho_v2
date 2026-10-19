extends RefCounted
# A one-way presentation projection. No Simulation/WorldState reference is kept,
# no authoritative IDs are allocated, and no command service is called.
const Store = preload("res://kernel/event_store.gd")
const View = preload("res://kernel/player_observer_view.gd")
const TYPES = ["FRONT_BEHAVIOR", "FRIENDLY_PRESENCE", "ENEMY_ACTIVITY", "SUPPLY_DEPARTURE_VISIBLE", "SUPPLY_ARRIVAL_VISIBLE", "SUPPLY_LOSS_VISIBLE"]
const BEHAVIORS = {"HOLD": "HOLDING", "PRESS": "PRESSING", "REDUCE_ACTIVITY": "REDUCED_ACTIVITY", "WITHDRAW": "WITHDRAWING"}
var _configuration: Dictionary
var _events := Store.new()
var _records: Array = []
var _current: Dictionary = {}

func _init(configuration: Dictionary = {}) -> void:
	_configuration = configuration.duplicate(true)

static func band(centi: int) -> String:
	return "LOW" if centi <= 3333 else ("MEDIUM" if centi <= 6666 else "HIGH")

func configuration() -> Dictionary:
	return _configuration.duplicate(true)

func events() -> Array:
	return _events.all()

func snapshot() -> Dictionary:
	return {"sequence": _events.count(), "records": _records.duplicate(true), "current": _current.duplicate(true)}

func view() -> RefCounted:
	return View.new({"areas": configuration(), "records": _records})

func observe(event: Dictionary, world: RefCounted) -> void:
	if _configuration.is_empty(): return
	var ids: Array = _configuration.keys()
	ids.sort()
	var front_changed: bool = event.event_type == "RUN_STARTED" or event.payload.get("changes", []).any(func(c): return c.table == "fronts")
	for id in ids:
		var area: Dictionary = _configuration[id]
		if not area.enabled: continue
		if front_changed and area.front_id != null:
			var front: Dictionary = world.get_front(area.front_id)
			var values := {"FRONT_BEHAVIOR": BEHAVIORS[front.posture], "FRIENDLY_PRESENCE": band(int(front.friendly_strength_centi)), "ENEMY_ACTIVITY": band(int(front.enemy_pressure_centi))}
			for type in TYPES.slice(0, 3):
				var key: String = id + ":" + type
				if _current.get(key, {}).get("qualitative_value") != values[type]: _record(id, type, values[type], event, front.id)
		if event.event_type not in ["SHIPMENT_DISPATCHED", "SHIPMENT_ARRIVED", "SHIPMENT_DESTROYED"]: continue
		var shipment: Dictionary = world.get_shipment(event.subject_entity_id)
		var location: String = shipment.current_location_id
		var type := "SUPPLY_LOSS_VISIBLE"
		if event.event_type == "SHIPMENT_DISPATCHED":
			location = world.get_stockpile(shipment.origin_stockpile_id).location_id
			type = "SUPPLY_DEPARTURE_VISIBLE"
		elif event.event_type == "SHIPMENT_ARRIVED":
			location = world.get_stockpile(shipment.destination_stockpile_id).location_id
			type = "SUPPLY_ARRIVAL_VISIBLE"
		if location in area.location_ids: _record(id, type, "SUPPLY_MOVEMENT", event, shipment.id)

func _record(area: String, type: String, value: String, source: Dictionary, entity: Variant) -> void:
	if not View.valid_cue(type, value): return
	var index: int = _events.count() + 1
	var id := "player-observation:%010d" % index
	var event_id := "player-observation-event:%010d" % index
	var record := {"observation_id": id, "area_id": area, "observed_at": source.simulation_time, "observation_type": type, "qualitative_value": value, "source_event_id": source.event_id, "source_entity_id": entity, "metadata": {}}
	var previous: Variant = null if index == 1 else "player-observation-event:%010d" % (index - 1)
	var event := {"player_observation_event_id": event_id, "event_type": "PLAYER_OBSERVATION_RECORDED", "schema_version": "2C.1.player-observation.1", "player_observation_id": id, "area_id": area, "observed_at": source.simulation_time, "observation_type": type, "qualitative_value": value, "source_authoritative_event_id": source.event_id, "source_entity_id": entity, "previous_observation_event_id": previous, "metadata": {}}
	_events.append(event)
	_records.append(record)
	_current[area + ":" + type] = record.duplicate(true)
