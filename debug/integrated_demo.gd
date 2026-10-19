extends RefCounted
const Simulation = preload("res://kernel/simulation.gd")
const R = preload("res://kernel/result.gd")

static func definition() -> Dictionary:
	var data := {"id": "trencho_step107", "tick_duration": 0.1, "resource_types": [{"id": "AMMUNITION", "allow_fractional_quantity": false}], "locations": [{"id": "OP_HQ"}, {"id": "OFFSCREEN_SOURCE"}], "commands": [{"id": "OPERATIONAL_COMMAND", "command_level": "OPERATIONAL", "ammunition_arbitration_enabled": true, "directly_controlled_location_ids": ["OP_HQ"], "directly_controlled_stockpile_ids": ["OP_HQ_STOCK"]}], "stockpiles": [{"id": "OP_HQ_STOCK", "owner_command_id": "OPERATIONAL_COMMAND", "location_id": "OP_HQ", "quantities": {"AMMUNITION": 50}}, {"id": "OFFSCREEN_STOCK", "location_id": "OFFSCREEN_SOURCE", "quantities": {"AMMUNITION": 0}}], "fronts": [], "communication_edges": [], "logistics_edges": [{"id": "strategic_route", "from_location_id": "OFFSCREEN_SOURCE", "to_location_id": "OP_HQ", "travel_time_seconds": 15.0}], "initial_in_transit_shipments": [{"id": "STRATEGIC_RESUPPLY", "origin_stockpile_id": "OFFSCREEN_STOCK", "destination_stockpile_id": "OP_HQ_STOCK", "resource_type_id": "AMMUNITION", "quantity": 60, "route_edge_ids": ["strategic_route"]}]}
	var starting := {"A": [120, 80, 40], "B": [80, 60, 50], "C": [20, 50, 70]}
	for letter in ["A", "B", "C"]:
		var command: String = "LOCAL_" + letter
		var site: String = letter + "_FRONT_SITE"
		var stock: String = letter + "_FRONT_STOCK"
		data.locations.append({"id": site})
		data.stockpiles.append({"id": stock, "owner_command_id": command, "location_id": site, "quantities": {"AMMUNITION": starting[letter][0]}})
		data.commands.append({"id": command, "command_level": "LOCAL", "superior_command_id": "OPERATIONAL_COMMAND", "directly_controlled_location_ids": [site], "directly_controlled_stockpile_ids": [stock], "local_decision_front_id": "FRONT_" + letter, "resource_resolution_enabled": true})
		data.fronts.append({"id": "FRONT_" + letter, "location_id": site, "responsible_command_id": command, "supply_stockpile_id": stock, "friendly_strength": starting[letter][1], "enemy_pressure": starting[letter][2], "base_ammo_demand_per_second": 8, "posture": "HOLD"})
		data.logistics_edges.append({"id": "hq_" + letter, "from_location_id": "OP_HQ", "to_location_id": site, "travel_time_seconds": 2.0})
		for pair in [[command, "OPERATIONAL_COMMAND"], ["OPERATIONAL_COMMAND", command]]:
			data.communication_edges.append({"id": pair[0] + "_to_" + pair[1], "from_command_id": pair[0], "to_command_id": pair[1], "latency_seconds": 0.3})
		for peer in ["LOCAL_A", "LOCAL_B", "LOCAL_C"]:
			if peer != command: data.communication_edges.append({"id": command + "_to_" + peer, "from_command_id": command, "to_command_id": peer, "latency_seconds": 0.2})
	for entry in [["B", 30, 1.0], ["C", 8, 0.5]]:
		var letter: String = entry[0]
		var site: String = letter + "_RESERVE_SITE"
		var stock: String = letter + "_LOCAL_RESERVE"
		data.locations.append({"id": site})
		data.stockpiles.append({"id": stock, "owner_command_id": "LOCAL_" + letter, "location_id": site, "quantities": {"AMMUNITION": entry[1]}})
		data.commands[2 if letter == "B" else 3].directly_controlled_location_ids.append(site)
		data.commands[2 if letter == "B" else 3].directly_controlled_stockpile_ids.append(stock)
		data.logistics_edges.append({"id": letter + "_reserve_to_C", "from_location_id": site, "to_location_id": "C_FRONT_SITE", "travel_time_seconds": entry[2]})
	return data

static func run() -> Dictionary:
	var sim := Simulation.new()
	var initialized: Dictionary = sim.initialize(definition(), 107, "step107")
	if not initialized.success: return initialized
	# Inspection/assertions may observe; no execute/bootstrap/EndRun inputs occur.
	var advanced: Dictionary = sim.advance(250)
	if not advanced.success: return advanced
	return R.ok(null, {"simulation": sim})
