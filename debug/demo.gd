extends RefCounted

const Simulation = preload("res://kernel/simulation.gd")
const Exporter = preload("res://kernel/run_exporter.gd")
const R = preload("res://kernel/result.gd")

static func definition() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/demo_world.json"))

static func input(sim: RefCounted, command: Dictionary) -> Dictionary:
	return sim.execute(command, true)

static func create_shipment(sim: RefCounted, origin: String, destination: String, quantity: int) -> Dictionary:
	return input(sim, {"type": "CreateShipment", "origin_stockpile_id": origin, "destination_stockpile_id": destination, "resource_type_id": "AMMUNITION", "quantity": quantity})

static func run(seed := 101, run_id := "demo") -> Dictionary:
	var sim := Simulation.new()
	var result := sim.initialize(definition(), seed, run_id)
	if not result.success:
		return result
	result = input(sim, {"type": "CreateResource", "stockpile_id": "SOURCE_STOCK", "resource_type_id": "AMMUNITION", "quantity": 1000})
	if not result.success:
		return result
	result = create_shipment(sim, "SOURCE_STOCK", "HQ_STOCK", 600)
	if not result.success:
		return result
	var source_shipment: String = result.entity_id
	result = input(sim, {"type": "DispatchShipment", "shipment_id": source_shipment})
	if not result.success:
		return result
	sim.advance(3)
	if sim.world.get_shipment(source_shipment).state != "ARRIVED":
		return R.fail("DEMO_SOURCE_ARRIVAL")
	var a := create_shipment(sim, "HQ_STOCK", "A_STOCK", 300)
	var b := create_shipment(sim, "HQ_STOCK", "B_STOCK", 200)
	if not a.success or not b.success:
		return R.fail("DEMO_SHIPMENT_CREATION")
	for id in [a.entity_id, b.entity_id]:
		result = input(sim, {"type": "DispatchShipment", "shipment_id": id})
		if not result.success:
			return result
	sim.advance()
	input(sim, {"type": "SetEnabled", "table": "logistics_edges", "entity_id": "hq_b", "enabled": false})
	sim.advance()
	if sim.world.get_shipment(a.entity_id).state != "ARRIVED" or sim.world.get_shipment(b.entity_id).state != "BLOCKED" or not sim.audit().AMMUNITION.valid:
		return R.fail("DEMO_BLOCKED_CONSERVATION")
	result = input(sim, {"type": "RerouteShipment", "shipment_id": b.entity_id, "destination_stockpile_id": "B_STOCK"})
	if not result.success:
		return result
	sim.advance(6)
	if sim.world.get_shipment(b.entity_id).state != "ARRIVED":
		return R.fail("DEMO_REROUTE_ARRIVAL")
	var fact := {"subject_entity_id": "A_STOCK", "fact_key": "reported_ammunition", "value": 300, "observed_at": sim.time(), "confidence": 1.0}
	result = input(sim, {"type": "SendMessage", "sender_command_id": "LOCAL_A", "recipient_command_id": "ARMY_COMMAND", "message_type": "REPORT", "payload": {"facts": [fact]}})
	if not result.success:
		return result
	if not sim.command_view("ARMY_COMMAND").current_belief("A_STOCK", "reported_ammunition", sim.time()).is_empty():
		return R.fail("DEMO_TELEPATHY")
	sim.advance(3)
	if sim.command_view("ARMY_COMMAND").current_belief("A_STOCK", "reported_ammunition", sim.time()).is_empty():
		return R.fail("DEMO_REPORT_DELIVERY")
	fact.fact_key = "failed_report"
	fact.observed_at = sim.time()
	result = input(sim, {"type": "SendMessage", "sender_command_id": "LOCAL_A", "recipient_command_id": "ARMY_COMMAND", "message_type": "REPORT", "payload": {"facts": [fact]}})
	if not result.success:
		return result
	var failed_id: String = result.entity_id
	input(sim, {"type": "SetEnabled", "table": "communication_edges", "entity_id": "a_army", "enabled": false})
	sim.advance(3)
	if sim.world.get_entity("messages", failed_id).state != "FAILED" or not sim.command_view("ARMY_COMMAND").current_belief("A_STOCK", "failed_report", sim.time()).is_empty():
		return R.fail("DEMO_FAILED_MESSAGE")
	input(sim, {"type": "EndRun"})
	return R.ok(null, {"simulation": sim})
