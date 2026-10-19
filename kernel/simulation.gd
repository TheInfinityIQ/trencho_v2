extends RefCounted

const R = preload("res://kernel/result.gd")
const Clock = preload("res://kernel/clock.gd")
const World = preload("res://kernel/world_state.gd")
const Store = preload("res://kernel/event_store.gd")
const Definition = preload("res://kernel/world_definition.gd")
const Resources = preload("res://kernel/resource_service.gd")
const Logistics = preload("res://kernel/logistics_service.gd")
const Authority = preload("res://kernel/authority_service.gd")
const Hierarchy = preload("res://kernel/hierarchy_service.gd")
const Communication = preload("res://kernel/communication_service.gd")
const Information = preload("res://kernel/information_service.gd")
const View = preload("res://kernel/command_view.gd")

var world: RefCounted
var events := Store.new()
var initial_world: Dictionary
var inputs: Array = []
var context: Dictionary = {}
var start_time_utc: String
var _input_sequence := 0
var _rng := RandomNumberGenerator.new()

func initialize(definition: Dictionary, seed := 101, run_id := "demo") -> Dictionary:
	var version := Engine.get_version_info()
	if version.major != 4 or version.minor != 7 or version.patch != 2 or version.status != "stable":
		return R.fail("ENGINE_VERSION_MISMATCH")
	var loaded: Dictionary = Definition.load_definition(definition, seed, run_id)
	if not loaded.success:
		return loaded
	return initialize_snapshot(loaded.details.snapshot)

func initialize_snapshot(snapshot: Dictionary) -> Dictionary:
	var validation: Dictionary = Definition.validate_initial_snapshot(snapshot)
	if not validation.success:
		return validation
	initial_world = snapshot.duplicate(true)
	world = World.new(snapshot)
	events = Store.new()
	inputs = []
	_input_sequence = 0
	context = {}
	start_time_utc = Time.get_datetime_string_from_system(true) + "Z"
	_rng.seed = int(snapshot.simulation_seed)
	_rng.state = int(snapshot.rng_state)
	commit("RUN_STARTED", [], {"simulation_seed": snapshot.simulation_seed}, null)
	for pair in [["locations", "LOCATION_CREATED"], ["commands", "COMMAND_CREATED"], ["resource_types", "RESOURCE_TYPE_DEFINED"], ["stockpiles", "STOCKPILE_CREATED"], ["logistics_edges", "LOGISTICS_EDGE_CREATED"], ["communication_edges", "COMMUNICATION_EDGE_CREATED"]]:
		for id in world.ids(pair[0]):
			commit(pair[1], [{"table": pair[0], "id": id, "value": world.get_entity(pair[0], id)}], {"initial_definition": true}, id)
	return R.ok()

func actor() -> Variant:
	return context.get("actor_entity_id")

func privileged() -> bool:
	return context.get("privileged", false)

func authorized(command: Variant, stockpile: String) -> bool:
	return privileged() or (command is String and actor() == command and Authority.new(self).can_dispatch(command, stockpile))

func entity_id(type: String) -> String:
	return "%s:%010d" % [type, world.sequence() + 1]

func time() -> float:
	return world.clock().simulation_time_seconds

func commit(type: String, changes: Array, payload: Dictionary = {}, subject: Variant = null, cause: Variant = null) -> String:
	var body: Dictionary = payload.duplicate(true)
	body.changes = changes.duplicate(true)
	body.privileged = privileged()
	var subject_location: Variant = null
	if subject is String:
		var location: Dictionary = world.get_location(subject)
		var stock: Dictionary = world.get_stockpile(subject)
		var shipment: Dictionary = world.get_shipment(subject)
		if not location.is_empty():
			subject_location = subject
		elif not stock.is_empty():
			subject_location = stock.location_id
		elif not shipment.is_empty():
			subject_location = shipment.current_location_id
	var id := "event:%010d" % (world.sequence() + 1)
	var event_clock: Dictionary = changes[0].value if type == "TICK_ADVANCED" else world.clock()
	var correlation: Variant = context.get("input_id", world.correlation(subject) if subject is String else null)
	var causation: Variant = cause if cause != null else context.get("causation_event_id", world.last_event(subject) if subject is String else null)
	var event := {"event_id": id, "event_type": type, "schema_version": "2A.1", "run_id": initial_world.run_id, "tick_index": event_clock.tick_index, "simulation_time": event_clock.simulation_time_seconds, "actor_entity_id": actor(), "subject_entity_id": subject, "location_id": subject_location, "correlation_id": correlation, "causation_event_id": causation, "payload": body}
	world.apply_event(event)
	events.append(event)
	return id

# Input order within a tick is append order. Tick updates finish before external inputs at that tick.
func execute(input: Dictionary, is_privileged := false) -> Dictionary:
	if world == null or world.ended():
		return R.fail("INVALID_STATE")
	# Reject non-serializable calls before they can alter history or run identity.
	if not R.json_compatible(input):
		return R.fail("INVALID_QUANTITY" if input.has("quantity") and not R.json_compatible(input.quantity) else "INVALID_INPUT")
	_input_sequence += 1
	context = {"input_id": "input:%010d" % _input_sequence, "actor_entity_id": input.get("actor_entity_id"), "privileged": is_privileged}
	var record := {"schema_version": "2A.1", "input_id": context.input_id, "tick_index": world.clock().tick_index, "privileged": is_privileged, "command": input.duplicate(true)}
	var received := commit("INPUT_RECEIVED", [{"table": "run", "id": "run", "value": {"input_sequence": _input_sequence}}], {"command": input})
	context.causation_event_id = received
	var validation := _validate_input(input)
	var result: Dictionary = _execute(input) if validation.success else validation
	record.result = result.duplicate(true)
	inputs.append(record)
	context = {}
	return result

func _validate_input(input: Dictionary) -> Dictionary:
	var required := {
		"CreateResource": ["stockpile_id", "resource_type_id", "quantity"], "ConsumeResource": ["stockpile_id", "resource_type_id", "quantity", "reason_code"], "DestroyResource": ["stockpile_id", "resource_type_id", "quantity", "reason_code"],
		"ReserveResource": ["stockpile_id", "resource_type_id", "quantity"], "ReleaseReservation": ["reservation_id"], "ConsumeReservation": ["reservation_id"], "InvalidateReservation": ["reservation_id"],
		"CreateShipment": ["origin_stockpile_id", "destination_stockpile_id", "resource_type_id", "quantity"], "DispatchShipment": ["shipment_id"], "CancelShipment": ["shipment_id"], "RerouteShipment": ["shipment_id", "destination_stockpile_id"], "DestroyShipment": ["shipment_id", "reason_code"],
		"SetEnabled": ["table", "entity_id", "enabled"], "ReparentCommand": ["command_id", "superior_command_id"], "SendMessage": ["sender_command_id", "recipient_command_id", "message_type", "payload"], "IngestInformation": ["owner_command_id", "fact"], "EndRun": []}
	if not input.get("type") is String or not required.has(input.type):
		return R.fail("INVALID_INPUT")
	for key in required[input.type]:
		if not input.has(key):
			return R.fail("INVALID_INPUT", {"missing": key})
		if key in ["quantity", "payload", "fact", "enabled", "superior_command_id"]:
			continue
		if not input[key] is String or input[key].is_empty():
			return R.fail("INVALID_INPUT", {"field": key})
	if input.has("actor_entity_id") and input.actor_entity_id != null and not input.actor_entity_id is String:
		return R.fail("INVALID_INPUT")
	if input.has("purpose_code") and not input.purpose_code is String:
		return R.fail("INVALID_INPUT")
	for key in ["payload", "fact"]:
		if input.has(key) and not input[key] is Dictionary:
			return R.fail("INVALID_INPUT")
	if input.has("enabled") and not input.enabled is bool:
		return R.fail("INVALID_INPUT")
	if input.has("superior_command_id") and input.superior_command_id != null and not input.superior_command_id is String:
		return R.fail("INVALID_INPUT")
	return R.ok()

func _execute(i: Dictionary) -> Dictionary:
	match i.type:
		"CreateResource":
			return Resources.new(self).create_stock(i.resource_type_id, i.stockpile_id, i.quantity)
		"ConsumeResource", "DestroyResource":
			return Resources.new(self).remove_stock(i.stockpile_id, i.resource_type_id, i.quantity, actor(), i.reason_code, i.type == "DestroyResource")
		"ReserveResource":
			return Resources.new(self).reserve(i.stockpile_id, i.resource_type_id, i.quantity, actor(), i.get("purpose_code", "SCRIPTED"))
		"ReleaseReservation", "ConsumeReservation", "InvalidateReservation":
			if i.type == "InvalidateReservation" and not privileged():
				return R.fail("UNAUTHORIZED")
			return Resources.new(self).retire(i.reservation_id, {"ReleaseReservation": "RELEASED", "ConsumeReservation": "CONSUMED", "InvalidateReservation": "INVALIDATED"}[i.type])
		"CreateShipment":
			return Logistics.new(self).create_shipment(i.origin_stockpile_id, i.destination_stockpile_id, i.resource_type_id, i.quantity, actor())
		"DispatchShipment":
			return Logistics.new(self).dispatch(i.shipment_id)
		"CancelShipment":
			return Logistics.new(self).cancel(i.shipment_id)
		"RerouteShipment":
			return Logistics.new(self).reroute(i.shipment_id, i.destination_stockpile_id)
		"DestroyShipment":
			return Logistics.new(self).destroy(i.shipment_id, i.reason_code)
		"ReparentCommand":
			return Hierarchy.new(self).reparent(i.command_id, i.superior_command_id)
		"SetEnabled":
			return _set_enabled(i)
		"SendMessage":
			return Communication.new(self).send(i.sender_command_id, i.recipient_command_id, i.message_type, i.payload)
		"IngestInformation":
			if not privileged():
				return R.fail("UNAUTHORIZED")
			return Information.new(self).ingest(i.owner_command_id, i.fact, "PRIVILEGED_INPUT")
		"EndRun":
			if not privileged():
				return R.fail("UNAUTHORIZED")
			commit("RUN_ENDED", [{"table": "run", "id": "run", "value": {"ended": true}}])
			return R.ok()
	return R.fail("INVALID_INPUT")

func _set_enabled(i: Dictionary) -> Dictionary:
	if not privileged():
		return R.fail("UNAUTHORIZED")
	var names := {"locations": "LOCATION", "commands": "COMMAND", "logistics_edges": "LOGISTICS_EDGE", "communication_edges": "COMMUNICATION_EDGE", "stockpiles": "STOCKPILE"}
	if not names.has(i.table):
		return R.fail("INVALID_ENTITY")
	var entity: Dictionary = world.get_entity(i.table, i.entity_id)
	if entity.is_empty():
		return R.fail("INVALID_ENTITY")
	entity.enabled = i.enabled
	commit(names[i.table] + "_ENABLED_CHANGED", [{"table": i.table, "id": i.entity_id, "value": entity}], {}, i.entity_id)
	return R.ok(i.entity_id)

func advance(ticks: int = 1) -> Dictionary:
	if ticks < 0 or world.ended():
		return R.fail("INVALID_STATE")
	for unused in range(ticks):
		context = {}
		var clock: Dictionary = world.clock()
		clock.tick_index += 1
		clock.simulation_time_seconds = Clock.seconds(clock.tick_index, clock.tick_duration)
		# The tick event is timestamped at its new time, matching all subsequent updates.
		commit("TICK_ADVANCED", [{"table": "clock", "id": "clock", "value": clock}])
		Logistics.new(self).step()
		Communication.new(self).step()
	return R.ok()

func command_view(id: String) -> RefCounted:
	var command: Dictionary = world.get_command(id)
	if command.is_empty():
		return null
	var data := {"identity": command, "stockpiles": {}, "locations": {}, "messages": [], "information_records": [], "public_facts": initial_world.get("public_facts", {})}
	for stockpile_id in command.directly_controlled_stockpile_ids:
		data.stockpiles[stockpile_id] = world.get_stockpile(stockpile_id)
	for location_id in command.directly_controlled_location_ids:
		data.locations[location_id] = world.get_location(location_id)
	for message_id in world.inbox_for(id):
		var message: Dictionary = world.get_entity("messages", message_id)
		if message.recipient_command_id == id and message.state == "DELIVERED":
			data.messages.append(message)
	for record_id in world.information_for(id):
		var record: Dictionary = world.get_entity("information_records", record_id)
		if record.owner_command_id == id:
			data.information_records.append(record)
	return View.new(data)

func snapshot() -> Dictionary:
	var result: Dictionary = world.snapshot()
	result.input_sequence = _input_sequence
	return result

func audit() -> Dictionary:
	return Resources.new(self).audit()
