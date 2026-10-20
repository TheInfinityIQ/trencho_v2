extends RefCounted

const R = preload("res://kernel/result.gd")
const Clock = preload("res://kernel/clock.gd")
const Front = preload("res://kernel/front_definition.gd")
const InitialCargo = preload("res://kernel/initial_cargo.gd")
const PROJECT_VERSION = "0.3.4"
const SCHEMA_VERSION = "2C.5"

static func load_definition(data: Dictionary, seed: int, run_id: String) -> Dictionary:
	if not R.json_compatible(data) or not R.json_compatible(seed):
		return R.fail("INVALID_WORLD_DEFINITION", {"reason": "NON_JSON_VALUE"})
	if not data.get("id", "") is String or not data.get("public_facts", {}) is Dictionary:
		return R.fail("INVALID_WORLD_DEFINITION")
	var state := {"schema_version": SCHEMA_VERSION, "project_version": PROJECT_VERSION, "run_id": run_id, "simulation_seed": seed, "engine_version": Engine.get_version_info().string, "initial_world_definition_id": data.get("id", ""), "event_sequence": 0, "input_sequence": 0, "ended": false, "clock": {"tick_index": 0, "tick_duration": data.get("tick_duration", 0.1), "simulation_time_seconds": 0.0}, "public_facts": data.get("public_facts", {}).duplicate(true)}
	if state.initial_world_definition_id.is_empty() or not (state.clock.tick_duration is float or state.clock.tick_duration is int) or not is_finite(float(state.clock.tick_duration)) or Clock.units(state.clock.tick_duration) <= 0:
		return R.fail("INVALID_WORLD_DEFINITION")
	state.clock.tick_duration = Clock.units(state.clock.tick_duration) / 1000000.0
	var used: Dictionary = {}
	for table in ["locations", "commands", "resource_types", "stockpiles", "logistics_edges", "communication_edges"]:
		state[table] = {}
		if not data.get(table, []) is Array:
			return R.fail("INVALID_WORLD_DEFINITION")
		for source in data.get(table, []):
			if not source is Dictionary or not source.get("id") is String or source.id.is_empty() or used.has(source.id):
				return R.fail("INVALID_WORLD_DEFINITION", {"reason": "INVALID_OR_DUPLICATE_ID"})
			var record: Dictionary = source.duplicate(true)
			# Runtime IDs use typed ':' namespaces; definition IDs cannot collide with them.
			if ":" in record.id:
				return R.fail("INVALID_WORLD_DEFINITION", {"reason": "RESERVED_ID_NAMESPACE"})
			used[record.id] = true
			if table != "resource_types":
				record.enabled = record.get("enabled", true)
			if table != "stockpiles":
				record.metadata = record.get("metadata", {})
			if table in ["locations", "commands", "resource_types"]:
				record.display_name = record.get("display_name", record.id)
			match table:
				"locations":
					record.location_type = record.get("location_type", "GENERIC")
					record.position_2d = record.get("position_2d", [0, 0])
				"commands":
					record.command_level = record.get("command_level", "LOCAL")
					record.local_decision_front_id = record.get("local_decision_front_id")
					record.ammunition_arbitration_enabled = record.get("ammunition_arbitration_enabled", false)
					if not record.ammunition_arbitration_enabled is bool or (record.ammunition_arbitration_enabled and record.command_level != "OPERATIONAL"):
						return R.fail("INVALID_ARBITRATION_CONFIGURATION")
					record.resource_resolution_enabled = record.get("resource_resolution_enabled", false)
					if not record.resource_resolution_enabled is bool:
						return R.fail("INVALID_RESOURCE_RESOLUTION_CONFIGURATION")
					record.superior_command_id = record.get("superior_command_id")
					record.subordinate_command_ids = []
					record.directly_controlled_location_ids = record.get("directly_controlled_location_ids", [])
					record.directly_controlled_stockpile_ids = record.get("directly_controlled_stockpile_ids", [])
				"resource_types":
					record.unit_name = record.get("unit_name", record.id)
					record.allow_fractional_quantity = record.get("allow_fractional_quantity", false)
				"stockpiles":
					record.owner_command_id = record.get("owner_command_id")
					record.quantities = record.get("quantities", {})
					record.reserved = {}
				"logistics_edges":
					record.transport_mode = record.get("transport_mode", "ABSTRACT_ROUTE")
				"communication_edges":
					record.mode = record.get("mode", "RADIO")
			if table != "resource_types" and not record.enabled is bool:
				return R.fail("INVALID_WORLD_DEFINITION")
			if table != "stockpiles" and not record.metadata is Dictionary:
				return R.fail("INVALID_WORLD_DEFINITION")
			if table in ["locations", "commands", "resource_types"] and not record.display_name is String:
				return R.fail("INVALID_WORLD_DEFINITION")
			if table == "resource_types" and (not record.allow_fractional_quantity is bool or not record.unit_name is String):
				return R.fail("INVALID_WORLD_DEFINITION")
			if table == "locations":
				if not record.location_type is String or not record.position_2d is Array or record.position_2d.size() != 2:
					return R.fail("INVALID_WORLD_DEFINITION")
				for coordinate in record.position_2d:
					if not (coordinate is int or coordinate is float) or not is_finite(float(coordinate)):
						return R.fail("INVALID_WORLD_DEFINITION")
			state[table][record.id] = record
	for table in ["shipments", "messages", "resource_reservations", "information_records", "ledger"]:
		state[table] = {}
	for id in state.resource_types:
		state.ledger[id] = {"id": id, "created": 0, "consumed": 0, "destroyed": 0}
	for id in state.stockpiles:
		var s: Dictionary = state.stockpiles[id]
		if not state.locations.has(s.get("location_id", "")) or (s.owner_command_id != null and not state.commands.has(s.owner_command_id)) or not s.quantities is Dictionary:
			return R.fail("INVALID_WORLD_DEFINITION", {"stockpile": id})
		for resource in s.quantities:
			var q: Variant = s.quantities[resource]
			if not state.resource_types.has(resource) or not (q is int or q is float) or not is_finite(float(q)) or q < 0 or (not state.resource_types[resource].allow_fractional_quantity and q != floor(q)):
				return R.fail("INVALID_WORLD_DEFINITION", {"quantity": resource})
			state.ledger[resource].created += q
	for table in ["logistics_edges", "communication_edges"]:
		var communication: bool = table == "communication_edges"
		var nodes: Dictionary = state.commands if communication else state.locations
		for id in state[table]:
			var e: Dictionary = state[table][id]
			var timing: Variant = e.get("latency_seconds" if communication else "travel_time_seconds")
			if not nodes.has(e.get("from_command_id" if communication else "from_location_id", "")) or not nodes.has(e.get("to_command_id" if communication else "to_location_id", "")) or not (timing is int or timing is float) or not is_finite(float(timing)) or timing < 0:
				return R.fail("INVALID_WORLD_DEFINITION", {"edge": id})
			e["latency_seconds" if communication else "travel_time_seconds"] = Clock.units(timing) / 1000000.0
	var controlled_stock: Dictionary = {}
	var controlled_location: Dictionary = {}
	for id in state.commands:
		var c: Dictionary = state.commands[id]
		for pair in [[c.directly_controlled_stockpile_ids, state.stockpiles, controlled_stock], [c.directly_controlled_location_ids, state.locations, controlled_location]]:
			if not pair[0] is Array:
				return R.fail("INVALID_WORLD_DEFINITION")
			for controlled_id in pair[0]:
				if not pair[1].has(controlled_id) or pair[2].has(controlled_id):
					return R.fail("INVALID_WORLD_DEFINITION", {"authority": controlled_id})
				pair[2][controlled_id] = id
		var parent: Variant = c.superior_command_id
		var visited: Dictionary = {id: true}
		while parent != null:
			if visited.has(parent):
				return R.fail("HIERARCHY_CYCLE")
			if not state.commands.has(parent):
				return R.fail("INVALID_WORLD_DEFINITION")
			visited[parent] = true
			parent = state.commands[parent].superior_command_id
		if c.superior_command_id != null:
			state.commands[c.superior_command_id].subordinate_command_ids.append(id)
	for id in state.stockpiles:
		var owner: Variant = state.stockpiles[id].owner_command_id
		if owner != null and controlled_stock.get(id) != owner:
			return R.fail("INVALID_WORLD_DEFINITION", {"reason": "OWNER_AUTHORITY_MISMATCH", "stockpile_id": id})
	for id in state.commands:
		state.commands[id].subordinate_command_ids.sort()
	if not InitialCargo.load_into(state, data.get("initial_in_transit_shipments", []), used):
		return R.fail("INVALID_INITIAL_CARGO")
	state.fronts = {}
	if not data.get("fronts", []) is Array:
		return R.fail("INVALID_WORLD_DEFINITION")
	for data_front in data.get("fronts", []):
		if not Front.tick_compatible(state.clock.tick_duration):
			return R.fail("INVALID_FRONT", {"reason": "UNSUPPORTED_FRONT_TICK_DURATION"})
		if not data_front is Dictionary:
			return R.fail("INVALID_WORLD_DEFINITION")
		for key in ["id", "responsible_command_id", "location_id", "supply_stockpile_id"]:
			if not data_front.get(key) is String:
				return R.fail("INVALID_WORLD_DEFINITION")
		if used.has(data_front.id) or ":" in data_front.id or not state.resource_types.has("AMMUNITION") or state.resource_types.AMMUNITION.allow_fractional_quantity:
			return R.fail("INVALID_WORLD_DEFINITION")
		var result: Dictionary = Front.make(data_front, state.commands.get(data_front.responsible_command_id, {}), state.locations.get(data_front.location_id, {}), state.stockpiles.get(data_front.supply_stockpile_id, {}), 0.0)
		if not result.success:
			return result
		state.fronts[data_front.id] = result.details.front
		used[data_front.id] = true
	for command in state.commands.values():
		if command.ammunition_arbitration_enabled and 1000000 % Clock.units(state.clock.tick_duration) != 0:
			return R.fail("INVALID_ARBITRATION_TICK_PRECISION")
		var front_id: Variant = command.local_decision_front_id
		if front_id == null:
			if command.resource_resolution_enabled:
				return R.fail("INVALID_RESOURCE_RESOLUTION_CONFIGURATION")
			continue
		if not front_id is String or not state.fronts.has(front_id) or command.command_level != "LOCAL" or state.fronts[front_id].responsible_command_id != command.id:
			return R.fail("INVALID_LOCAL_PLANNER_CONFIGURATION")
	state.observation_batches = {}
	state.decisions = {}
	state.decision_candidates = {}
	state.superior_need_reports = {}
	state.superior_revision_funding = {}
	state.resource_arbitrations = {}
	state.resource_needs = {}
	state.peer_coordinations = {}
	state.known_transfers = {}
	state.resolution_receipts = {}
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	state.rng_state = str(rng.state)
	return R.ok(null, {"snapshot": state})

static func validate_initial_snapshot(snapshot: Dictionary) -> Dictionary:
	for key in ["schema_version", "project_version", "engine_version", "run_id", "simulation_seed", "initial_world_definition_id", "event_sequence", "input_sequence", "clock", "rng_state", "ended", "public_facts", "locations", "commands", "resource_types", "stockpiles", "logistics_edges", "communication_edges", "shipments", "messages", "resource_reservations", "information_records", "ledger", "fronts", "observation_batches", "decisions", "decision_candidates", "resource_needs", "peer_coordinations", "known_transfers", "resolution_receipts", "superior_need_reports", "superior_revision_funding", "resource_arbitrations"]:
		if not snapshot.has(key):
			return R.fail("INVALID_SNAPSHOT", {"missing": key})
	if snapshot.schema_version != SCHEMA_VERSION or snapshot.project_version != PROJECT_VERSION:
		return R.fail("UNSUPPORTED_SNAPSHOT")
	if snapshot.engine_version != Engine.get_version_info().string:
		return R.fail("ENGINE_VERSION_MISMATCH")
	if not snapshot.clock is Dictionary or snapshot.clock.get("tick_index", -1) != 0 or snapshot.clock.get("simulation_time_seconds", -1) != 0 or snapshot.event_sequence != 0 or snapshot.input_sequence != 0 or snapshot.ended != false:
		return R.fail("UNSUPPORTED_SNAPSHOT")
	if not snapshot.rng_state is String or not snapshot.rng_state.is_valid_int() or not snapshot.run_id is String or not (snapshot.simulation_seed is int or snapshot.simulation_seed is float):
		return R.fail("INVALID_SNAPSHOT", {"reason": "INVALID_RUN_IDENTITY", "rng_state": snapshot.rng_state})
	var definition := {"id": snapshot.initial_world_definition_id, "tick_duration": snapshot.clock.get("tick_duration", 0), "public_facts": snapshot.public_facts}
	if not snapshot.shipments is Dictionary: return R.fail("INVALID_SNAPSHOT")
	definition.initial_in_transit_shipments = snapshot.shipments.values()
	for table in ["locations", "commands", "resource_types", "stockpiles", "logistics_edges", "communication_edges", "fronts"]:
		if not snapshot[table] is Dictionary:
			return R.fail("INVALID_SNAPSHOT")
		definition[table] = snapshot[table].values()
		for id in snapshot[table]:
			if not snapshot[table][id] is Dictionary or snapshot[table][id].get("id") != id:
				return R.fail("INVALID_SNAPSHOT")
	for table in ["messages", "resource_reservations", "information_records", "observation_batches", "decisions", "decision_candidates", "resource_needs", "peer_coordinations", "known_transfers", "resolution_receipts", "superior_need_reports", "superior_revision_funding", "resource_arbitrations"]:
		if not snapshot[table] is Dictionary or not snapshot[table].is_empty():
			return R.fail("UNSUPPORTED_SNAPSHOT")
	var result := load_definition(definition, int(snapshot.simulation_seed), snapshot.run_id)
	if not result.success:
		return R.fail("INVALID_SNAPSHOT", result.details)
	# Compare canonical semantic data; JSON parses integral numbers as floats.
	if not _same(result.details.snapshot, snapshot):
		return R.fail("INVALID_SNAPSHOT", {"reason": "INCONSISTENT_INITIAL_PROJECTION"})
	return R.ok(null, {"fronts": result.details.snapshot.fronts})

static func _same(a: Variant, b: Variant) -> bool:
	if a is Dictionary and b is Dictionary:
		if a.size() != b.size():
			return false
		for key in a:
			if not b.has(key) or not _same(a[key], b[key]):
				return false
		return true
	if a is Array and b is Array:
		if a.size() != b.size():
			return false
		for i in range(a.size()):
			if not _same(a[i], b[i]):
				return false
		return true
	return a == b
