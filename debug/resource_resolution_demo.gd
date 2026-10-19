extends RefCounted
const Simulation = preload("res://kernel/simulation.gd")
const Base = preload("res://debug/front_demo.gd")
const R = preload("res://kernel/result.gd")

static func definition(scenario := "B") -> Dictionary:
	var data: Dictionary = Base.definition()
	data.id = "trencho_step105_" + scenario
	data.commands[1].local_decision_front_id = "FRONT_A"
	data.commands[1].resource_resolution_enabled = true
	data.commands[2].local_decision_front_id = "FRONT_B"
	data.fronts.append({"id": "FRONT_B", "location_id": "DEPOT_B", "responsible_command_id": "LOCAL_B", "supply_stockpile_id": "B_STOCK", "friendly_strength": 60, "enemy_pressure": 50, "posture": "HOLD", "base_ammo_demand_per_second": 8})
	data.stockpiles[0].quantities = {"AMMUNITION": 1000}
	data.stockpiles[1].quantities.AMMUNITION = 2
	data.stockpiles[2].quantities = {"AMMUNITION": 84 if scenario == "C" else (160 if scenario == "E" else 200)}
	var latency := 0.5 if scenario in ["D", "E"] else 0.1
	data.communication_edges = [{"id": "a_b", "from_command_id": "LOCAL_A", "to_command_id": "LOCAL_B", "latency_seconds": latency}, {"id": "b_a", "from_command_id": "LOCAL_B", "to_command_id": "LOCAL_A", "latency_seconds": latency}, {"id": "a_army", "from_command_id": "LOCAL_A", "to_command_id": "ARMY_COMMAND", "latency_seconds": 0.2}, {"id": "army_a", "from_command_id": "ARMY_COMMAND", "to_command_id": "LOCAL_A", "latency_seconds": 0.2}]
	data.logistics_edges = [{"id": "b_to_a", "from_location_id": "DEPOT_B", "to_location_id": "DEPOT_A", "travel_time_seconds": 0.5}]
	if scenario == "A":
		data.locations.append({"id": "RESERVE_SITE"})
		data.commands[1].directly_controlled_location_ids.append("RESERVE_SITE")
		data.commands[1].directly_controlled_stockpile_ids.append("A_RESERVE")
		data.stockpiles.append({"id": "A_RESERVE", "owner_command_id": "LOCAL_A", "location_id": "RESERVE_SITE", "quantities": {"AMMUNITION": 100}})
		data.logistics_edges.append({"id": "reserve_a", "from_location_id": "RESERVE_SITE", "to_location_id": "DEPOT_A", "travel_time_seconds": 0.5})
	if scenario == "E":
		data.locations.append({"id": "DEPOT_C"})
		data.commands.append({"id": "LOCAL_C", "superior_command_id": "ARMY_COMMAND", "directly_controlled_location_ids": ["DEPOT_C"], "directly_controlled_stockpile_ids": ["C_STOCK"], "local_decision_front_id": "FRONT_C", "resource_resolution_enabled": true})
		data.stockpiles.append({"id": "C_STOCK", "owner_command_id": "LOCAL_C", "location_id": "DEPOT_C", "quantities": {"AMMUNITION": 2}})
		data.fronts.append({"id": "FRONT_C", "location_id": "DEPOT_C", "responsible_command_id": "LOCAL_C", "supply_stockpile_id": "C_STOCK", "friendly_strength": 60, "enemy_pressure": 50, "posture": "HOLD", "base_ammo_demand_per_second": 8})
		data.communication_edges.append_array([{"id": "c_a", "from_command_id": "LOCAL_C", "to_command_id": "LOCAL_A", "latency_seconds": 0.1}, {"id": "a_c", "from_command_id": "LOCAL_A", "to_command_id": "LOCAL_C", "latency_seconds": 0.1}, {"id": "c_b", "from_command_id": "LOCAL_C", "to_command_id": "LOCAL_B", "latency_seconds": 0.5}, {"id": "b_c", "from_command_id": "LOCAL_B", "to_command_id": "LOCAL_C", "latency_seconds": 0.5}])
		data.logistics_edges.append({"id": "b_to_c", "from_location_id": "DEPOT_B", "to_location_id": "DEPOT_C", "travel_time_seconds": 0.5})
	return data

static func run(scenario := "B") -> Dictionary:
	var sim := Simulation.new()
	var initialized: Dictionary = sim.initialize(definition(scenario), 105, "step105_" + scenario)
	if not initialized.success: return initialized
	if scenario == "D":
		sim.advance(13)
		var supply: Dictionary = sim.execute({"type": "CreateResource", "stockpile_id": "A_STOCK", "resource_type_id": "AMMUNITION", "quantity": 200}, true)
		if not supply.success: return supply
		sim.advance(27)
	else: sim.advance(18 if scenario == "E" else 40)
	sim.execute({"type": "EndRun"}, true)
	return R.ok(null, {"simulation": sim})
