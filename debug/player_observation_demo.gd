extends RefCounted
const Simulation = preload("res://kernel/simulation.gd")
const Base = preload("res://debug/front_demo.gd")
const Integrated = preload("res://debug/integrated_demo.gd")
const R = preload("res://kernel/result.gd")

static func areas() -> Array:
	return [{"id": "AREA_FRONT_A", "display_name": "Front A", "location_ids": ["DEPOT_A"], "front_id": "FRONT_A", "metadata": {"friendly_strength": 8000, "private_need_quantity": 777}}, {"id": "AREA_HQ", "display_name": "Headquarters", "location_ids": ["ARMY_HQ"]}]

static func definition(scenario := "A") -> Dictionary:
	if scenario == "D":
		var data: Dictionary = Integrated.definition()
		data.strategic_areas = [{"id": "AREA_HQ", "display_name": "Headquarters", "location_ids": ["OP_HQ"]}]
		for letter in ["A", "B", "C"]:
			data.strategic_areas.append({"id": "AREA_FRONT_" + letter, "display_name": "Front " + letter, "location_ids": [letter + "_FRONT_SITE"], "front_id": "FRONT_" + letter})
		return data
	var data: Dictionary = Base.definition()
	data.id = "step109_" + scenario
	data.strategic_areas = areas()
	data.stockpiles[0].quantities = {"AMMUNITION": 100}
	if scenario == "A":
		data.fronts[0].friendly_strength = 80
		data.fronts[0].enemy_pressure = 40
		data.fronts[0].posture = "PRESS"
	if scenario in ["B", "E"]: data.fronts[0].enemy_pressure = 32
	if scenario == "C":
		data.logistics_edges = [{"id": "hq_a", "from_location_id": "ARMY_HQ", "to_location_id": "DEPOT_A", "travel_time_seconds": 0.5}]
		data.communication_edges = [{"id": "a_b", "from_command_id": "LOCAL_A", "to_command_id": "LOCAL_B", "latency_seconds": 2.0}]
	if scenario == "E":
		data.commands[1].local_decision_front_id = "FRONT_A"
		data.stockpiles[1].quantities.AMMUNITION = 120
	return data

static func fresh(scenario := "A", enabled := true) -> RefCounted:
	var data := definition(scenario)
	if not enabled: data.erase("strategic_areas")
	var sim := Simulation.new()
	var result: Dictionary = sim.initialize(data, 109, "step109_" + scenario)
	assert(result.success, JSON.stringify(result))
	return sim

static func input(sim: RefCounted, type: String, value: Variant) -> Dictionary:
	return sim.execute({"type": type, "front_id": "FRONT_A", "value": value}, true)

static func shipment(sim: RefCounted, quantity := 7) -> Dictionary:
	var created: Dictionary = sim.execute({"type": "CreateShipment", "origin_stockpile_id": "HQ_STOCK", "destination_stockpile_id": "A_STOCK", "resource_type_id": "AMMUNITION", "quantity": quantity}, true)
	if created.success: sim.execute({"type": "DispatchShipment", "shipment_id": created.entity_id}, true)
	return created
