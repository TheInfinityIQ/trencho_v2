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
const Fronts = preload("res://kernel/front_service.gd")
const Journal = preload("res://kernel/decision_journal.gd")
const Router = preload("res://kernel/router.gd")
const Resolution = preload("res://kernel/resource_resolution_service.gd")
const Arbitration = preload("res://kernel/superior_arbitration_service.gd")
const Areas = preload("res://kernel/strategic_area_definition.gd")
const Observer = preload("res://kernel/player_observer.gd")
const Prompts = preload("res://kernel/player_prompt_service.gd")
const PromptView = preload("res://kernel/player_prompt_view.gd")

var world: RefCounted
var events := Store.new()
var initial_world: Dictionary
var inputs: Array = []
var context: Dictionary = {}
var start_time_utc: String
var _input_sequence := 0
var _rng := RandomNumberGenerator.new()
var player_observer := Observer.new()
var player_prompts := Prompts.new()
var _prompt_input_sequence := 0

func initialize(definition: Dictionary, seed := 101, run_id := "demo") -> Dictionary:
	var version := Engine.get_version_info()
	if version.major != 4 or version.minor != 7 or version.patch != 2 or version.status != "stable":
		return R.fail("ENGINE_VERSION_MISMATCH")
	var loaded: Dictionary = Definition.load_definition(definition, seed, run_id)
	if not loaded.success:
		return loaded
	return initialize_snapshot(loaded.details.snapshot, definition.get("strategic_areas", []))

func initialize_snapshot(snapshot: Dictionary, strategic_areas: Variant = []) -> Dictionary:
	var validation: Dictionary = Definition.validate_initial_snapshot(snapshot)
	if not validation.success:
		return validation
	var configured := Areas.normalize(strategic_areas, snapshot.locations, snapshot.fronts, {})
	if not configured.success: return configured
	player_observer = Observer.new(configured.details.areas)
	player_prompts = Prompts.new()
	_prompt_input_sequence = 0
	initial_world = snapshot.duplicate(true)
	# Restore the new fixed-point front fields to integer types after JSON parsing.
	initial_world.fronts = validation.details.fronts.duplicate(true)
	world = World.new(initial_world)
	events = Store.new()
	inputs = []
	_input_sequence = 0
	context = {}
	start_time_utc = Time.get_datetime_string_from_system(true) + "Z"
	_rng.seed = int(snapshot.simulation_seed)
	_rng.state = int(snapshot.rng_state)
	var started: String = commit("RUN_STARTED", [], {"simulation_seed": snapshot.simulation_seed}, null)
	for pair in [["locations", "LOCATION_CREATED"], ["commands", "COMMAND_CREATED"], ["resource_types", "RESOURCE_TYPE_DEFINED"], ["stockpiles", "STOCKPILE_CREATED"], ["logistics_edges", "LOGISTICS_EDGE_CREATED"], ["communication_edges", "COMMUNICATION_EDGE_CREATED"]]:
		for id in world.ids(pair[0]):
			commit(pair[1], [{"table": pair[0], "id": id, "value": world.get_entity(pair[0], id)}], {"initial_definition": true}, id)
	for id in world.ids("fronts"):
		commit("FRONT_CREATED", [{"table": "fronts", "id": id, "value": world.get_front(id)}], {"initial_definition": true}, id)
	for id in world.ids("shipments"):
		commit("INITIAL_CARGO_RECORDED", [{"table": "shipments", "id": id, "value": world.get_shipment(id)}], {"initial_definition": true}, id, started, id)
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

func commit(type: String, changes: Array, payload: Dictionary = {}, subject: Variant = null, cause: Variant = null, operation_correlation: Variant = null) -> String:
	var body: Dictionary = payload.duplicate(true)
	body.changes = changes.duplicate(true)
	body.privileged = privileged()
	if context.get("source_system") == "RESOURCE_RESOLUTION":
		body.need_id = context.get("input_id")
		if context.get("coordination_id") != null: body.coordination_id = context.coordination_id
	var subject_location: Variant = null
	if subject is String:
		var location: Dictionary = world.get_location(subject)
		var stock: Dictionary = world.get_stockpile(subject)
		var shipment: Dictionary = world.get_shipment(subject)
		if shipment.has("need_id"):
			body.need_id = shipment.need_id
			if shipment.get("coordination_id") != null: body.coordination_id = shipment.coordination_id
		if not location.is_empty():
			subject_location = subject
		elif not stock.is_empty():
			subject_location = stock.location_id
		elif not shipment.is_empty():
			subject_location = shipment.current_location_id
	var id := "event:%010d" % (world.sequence() + 1)
	var event_clock: Dictionary = changes[0].value if type == "TICK_ADVANCED" else world.clock()
	var correlation: Variant = operation_correlation if operation_correlation != null else context.get("input_id", world.correlation(subject) if subject is String else null)
	if body.get("need_id") is String and not body.need_id.is_empty():
		correlation = body.need_id
	# Superior transfers retain their arbitration chain even alongside a need ID.
	if context.get("arbitration_id") != null and type not in ["MESSAGE_DELIVERED", "MESSAGE_FAILED"]:
		correlation = context.arbitration_id
		body.arbitration_id = context.arbitration_id
		body.decision_id = context.get("decision_id")
	elif operation_correlation is String and operation_correlation.begins_with("arbitration:"):
		correlation = operation_correlation
	elif subject is String and world.get_shipment(subject).has("arbitration_id"):
		correlation = world.get_shipment(subject).arbitration_id
	var causation: Variant = cause if cause != null else context.get("causation_event_id", world.last_event(subject) if subject is String else null)
	var event := {"event_id": id, "event_type": type, "schema_version": Definition.SCHEMA_VERSION, "run_id": initial_world.run_id, "tick_index": event_clock.tick_index, "simulation_time": event_clock.simulation_time_seconds, "actor_entity_id": actor(), "subject_entity_id": subject, "location_id": subject_location, "correlation_id": correlation, "causation_event_id": causation, "payload": body}
	world.apply_event(event)
	events.append(event)
	player_observer.observe(event, world)
	return id

func player_view() -> RefCounted:
	return player_observer.view()

func player_prompt_view() -> RefCounted:
	return player_prompts.view()

func command_prompt_view(command_id: String) -> RefCounted:
	var command: Dictionary = world.get_command(command_id)
	if command.is_empty() or command.command_level != "OPERATIONAL": return PromptView.new()
	return player_prompts.view(command_id)

func _submit_player_prompt(input: Dictionary, is_privileged: bool) -> Dictionary:
	# Separate intent input sequence: legacy world IDs/context remain untouched.
	_prompt_input_sequence += 1
	var input_id := "player-prompt-input:%010d" % _prompt_input_sequence
	var result := Prompts.validate(input, player_observer.configuration(), world)
	if result.success: result = player_prompts.submit(input, input_id, time())
	inputs.append({"schema_version": Definition.SCHEMA_VERSION, "input_id": input_id, "tick_index": world.clock().tick_index, "privileged": is_privileged, "command": input.duplicate(true), "result": result.duplicate(true)})
	return result

# Input order within a tick is append order. Tick updates finish before external inputs at that tick.
func execute(input: Dictionary, is_privileged := false) -> Dictionary:
	if world == null or world.ended():
		return R.fail("INVALID_STATE")
	# Reject non-serializable calls before they can alter history or run identity.
	if not R.json_compatible(input):
		return R.fail("INVALID_QUANTITY" if input.has("quantity") and not R.json_compatible(input.quantity) else "INVALID_INPUT")
	if input.get("type") == "SubmitPlayerPrompt": return _submit_player_prompt(input, is_privileged)
	_input_sequence += 1
	context = {"input_id": "input:%010d" % _input_sequence, "actor_entity_id": input.get("actor_entity_id"), "privileged": is_privileged}
	var record := {"schema_version": Definition.SCHEMA_VERSION, "input_id": context.input_id, "tick_index": world.clock().tick_index, "privileged": is_privileged, "command": input.duplicate(true)}
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
		"SetEnabled": ["table", "entity_id", "enabled"], "ReparentCommand": ["command_id", "superior_command_id"], "SendMessage": ["sender_command_id", "recipient_command_id", "message_type", "payload"], "IngestInformation": ["owner_command_id", "fact"], "CreateFront": ["front"], "SetFrontEnemyPressure": ["front_id", "value"], "SetFrontFriendlyStrength": ["front_id", "value"], "SetFrontPosture": ["front_id", "value"], "SetFrontEnabled": ["front_id", "value"], "EvaluateResourceNeed": ["observation_batch_id"], "EvaluateLocalDecision": ["command_id", "front_id", "record_ids", "complete", "observed_at_micro"], "EndRun": []}
	if not input.get("type") is String or not required.has(input.type):
		return R.fail("INVALID_INPUT")
	for key in required[input.type]:
		if not input.has(key):
			return R.fail("INVALID_INPUT", {"missing": key})
		if key in ["quantity", "payload", "fact", "front", "value", "record_ids", "complete", "observed_at_micro", "enabled", "superior_command_id"]:
			continue
		if not input[key] is String or input[key].is_empty():
			return R.fail("INVALID_INPUT", {"field": key})
	if input.has("actor_entity_id") and input.actor_entity_id != null and not input.actor_entity_id is String:
		return R.fail("INVALID_INPUT")
	if input.has("purpose_code") and not input.purpose_code is String:
		return R.fail("INVALID_INPUT")
	for key in ["payload", "fact", "front"]:
		if input.has(key) and not input[key] is Dictionary:
			return R.fail("INVALID_INPUT")
	if input.has("enabled") and not input.enabled is bool:
		return R.fail("INVALID_INPUT")
	if input.has("superior_command_id") and input.superior_command_id != null and not input.superior_command_id is String:
		return R.fail("INVALID_INPUT")
	return R.ok()

func _execute(i: Dictionary) -> Dictionary:
	match i.type:
		"EvaluateResourceNeed":
			if not privileged(): return R.fail("UNAUTHORIZED")
			return Resolution.new(self).evaluate_batch(world.get_entity("observation_batches", i.observation_batch_id))
		"EvaluateLocalDecision":
			return Journal.new(self).debug_evaluate(i)
		"CreateFront":
			return Fronts.new(self).create(i.front)
		"SetFrontEnemyPressure", "SetFrontFriendlyStrength", "SetFrontPosture", "SetFrontEnabled":
			var fields := {"SetFrontEnemyPressure": "enemy_pressure", "SetFrontFriendlyStrength": "friendly_strength", "SetFrontPosture": "posture", "SetFrontEnabled": "enabled"}
			return Fronts.new(self).set_field(i.front_id, fields[i.type], i.value)
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
		var prepared: Dictionary = Fronts.new(self).prepare_tick(clock.tick_duration)
		var tick_changes: Array = [{"table": "clock", "id": "clock", "value": clock}]
		tick_changes.append_array(prepared.changes)
		var tick_event := commit("TICK_ADVANCED", tick_changes, {"front_integer_demands": prepared.demands} if not prepared.demands.is_empty() else {})
		Logistics.new(self).step()
		Resolution.new(self).sync_known_transfers()
		Communication.new(self).step()
		Fronts.new(self).resolve_tick(prepared.demands, tick_event)
		Resolution.new(self).step(tick_event)
		var superior_enabled := false
		for command_id in world.ids("commands"):
			var command: Dictionary = world.get_command(command_id)
			if command.enabled and command.get("ammunition_arbitration_enabled", false): superior_enabled = true
		if superior_enabled:
			# Drain newly sent zero-latency material updates before this boundary's AI.
			Resolution.new(self).step(tick_event)
			Arbitration.new(self).step(tick_event)
			# Zero-latency orders are received after arbitration, before the next tick.
			Resolution.new(self).step(tick_event)
	return R.ok()

func receive_superior_message(message: Dictionary) -> void:
	if message.message_type == "ORDER": Arbitration.new(self).receive_notification(message)
	else: Arbitration.new(self).receive_report(message)

func update_superior_reports() -> void:
	Arbitration.new(self).update_reports()

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
	data.front_assignment = {}
	data.protected_front_stockpile_ids = []
	data.peers = []
	data.direct_superior = {}
	data.communication_routes = {}
	data.known_incoming = []
	data.superior_need_reports = []
	for report_id in world.ids("superior_need_reports"):
		var report: Dictionary = world.get_entity("superior_need_reports", report_id)
		if report.superior_command_id == id: data.superior_need_reports.append(report)
	var assigned: Dictionary = world.get_front(command.get("local_decision_front_id") if command.get("local_decision_front_id") is String else "")
	if not assigned.is_empty():
		data.front_assignment = {"front_id": assigned.id, "supply_stockpile_id": assigned.supply_stockpile_id}
	for front_id in world.ids("fronts"):
		var front: Dictionary = world.get_front(front_id)
		if front.responsible_command_id == id and front.enabled and front.supply_stockpile_id not in data.protected_front_stockpile_ids:
			data.protected_front_stockpile_ids.append(front.supply_stockpile_id)
	for other_id in world.ids("commands"):
		var other: Dictionary = world.get_command(other_id)
		var parent: Variant = command.superior_command_id
		var sibling: bool = other.id != id and parent != null and other.superior_command_id == parent and other.command_level == "LOCAL" and other.enabled
		if not sibling and other.id != parent:
			continue
		var outbound: Dictionary = Router.find(world, id, other.id, true)
		var inbound: Dictionary = Router.find(world, other.id, id, true)
		data.communication_routes[other.id] = {"outbound": outbound.success, "inbound": inbound.success, "outbound_micro": Clock.units(outbound.details.total_travel_time) if outbound.success else 0, "inbound_micro": Clock.units(inbound.details.total_travel_time) if inbound.success else 0}
		if sibling and outbound.success and inbound.success:
			data.peers.append({"id": other.id, "command_level": other.command_level, "superior_command_id": other.superior_command_id})
		if other.id == parent:
			data.direct_superior = {"id": other.id, "enabled": other.enabled}
	for transfer_id in world.ids("known_transfers"):
		var transfer: Dictionary = world.get_entity("known_transfers", transfer_id)
		if transfer.command_id == id: data.known_incoming.append(transfer)
	return View.new(data)

func snapshot() -> Dictionary:
	var result: Dictionary = world.snapshot()
	result.input_sequence = _input_sequence
	return result

func audit() -> Dictionary:
	return Resources.new(self).audit()

func front_metrics(id: String) -> Dictionary:
	return Fronts.new(self).metrics(id)

func decision_journal(command_id: String) -> Array:
	var result: Array = []
	for id in world.ids("decisions"):
		var decision: Dictionary = world.get_entity("decisions", id)
		if decision.command_id == command_id:
			result.append(decision)
	return result
