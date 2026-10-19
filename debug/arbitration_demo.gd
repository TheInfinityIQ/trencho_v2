extends RefCounted
const Simulation = preload("res://kernel/simulation.gd")
const Base = preload("res://debug/resource_resolution_demo.gd")
const R = preload("res://kernel/result.gd")

static func definition(stock := 200) -> Dictionary:
	var data: Dictionary = Base.definition("C")
	data.id = "trencho_step106"
	data.commands[0].ammunition_arbitration_enabled = true
	data.commands[1].resource_resolution_enabled = false
	data.stockpiles[0].quantities.AMMUNITION = stock
	data.communication_edges = [
		{"id": "a_army", "from_command_id": "LOCAL_A", "to_command_id": "ARMY_COMMAND", "latency_seconds": 0.1},
		{"id": "b_army", "from_command_id": "LOCAL_B", "to_command_id": "ARMY_COMMAND", "latency_seconds": 0.1},
		{"id": "army_a", "from_command_id": "ARMY_COMMAND", "to_command_id": "LOCAL_A", "latency_seconds": 0.2},
		{"id": "army_b", "from_command_id": "ARMY_COMMAND", "to_command_id": "LOCAL_B", "latency_seconds": 0.2}]
	data.logistics_edges = [
		{"id": "hq_a", "from_location_id": "ARMY_HQ", "to_location_id": "DEPOT_A", "travel_time_seconds": 0.5},
		{"id": "hq_b", "from_location_id": "ARMY_HQ", "to_location_id": "DEPOT_B", "travel_time_seconds": 0.5}]
	return data

# Scripted delivered report fixtures isolate arbitration policy. A exercises the
# complete real105 need→escalation→allocation→local physical-resolution chain.
static func report(command := "LOCAL_A", revision := 1, quantity := 80, stock := 0, rate := 4000, urgency := "CRITICAL", need := "fixture:A") -> Dictionary:
	var a := command == "LOCAL_A"
	return {"subtype": "AMMO_NEED_ESCALATION", "need_id": need, "need_revision": revision, "requesting_command_id": command, "front_id": "FRONT_A" if a else "FRONT_B", "destination_stockpile_id": "A_STOCK" if a else "B_STOCK", "resource_type_id": "AMMUNITION", "urgency": urgency, "available_quantity": stock, "confirmed_incoming_quantity": 0, "uncovered_need_quantity": quantity, "target_stock_quantity": (rate * 20000 + 999999) / 1000000, "planning_rate_milli": rate, "observation_batch_id": "fixture-observation:" + command, "observed_at_micro": 0}

static func send(sim: RefCounted, payload: Dictionary) -> Dictionary:
	return sim.execute({"type": "SendMessage", "actor_entity_id": payload.requesting_command_id, "sender_command_id": payload.requesting_command_id, "recipient_command_id": "ARMY_COMMAND", "message_type": "ESCALATION", "payload": payload})

static func run(scenario := "A") -> Dictionary:
	var data := definition(30 if scenario == "B" else (100 if scenario == "C" else 200))
	if scenario == "A":
		data.commands[1].resource_resolution_enabled = true
		data.communication_edges[0].latency_seconds = 0.0
		data.communication_edges = data.communication_edges.filter(func(e): return e.from_command_id != "LOCAL_B" and e.to_command_id != "LOCAL_B")
	if scenario == "E": data.communication_edges[0].latency_seconds = 0.8
	if scenario == "F": data.logistics_edges.remove_at(0)
	var sim := Simulation.new()
	var initialized: Dictionary = sim.initialize(data, 106, "step106_" + scenario)
	if not initialized.success: return initialized
	if scenario == "A":
		sim.advance(40)
	else:
		var p := report()
		if scenario == "D": p.need_revision = 4
		if scenario == "G":
			p.uncovered_need_quantity = 23
			p.available_quantity = 57
		send(sim, p)
		if scenario in ["B", "C", "F"]:
			if scenario == "C":
				p = report("LOCAL_B", 1, 156, 4, 8000, "CRITICAL", "fixture:B")
			else: p = report("LOCAL_B", 1, 40, 40, 4000, "CONSTRAINED", "fixture:B")
			send(sim, p)
		if scenario == "D":
			p = report("LOCAL_A", 5, 30, 50)
			p.subtype = "AMMO_NEED_UPDATE"
			send(sim, p)
			p = report("LOCAL_A", 4, 80)
			p.subtype = "AMMO_NEED_UPDATE"
			send(sim, p)
		if scenario == "H":
			send(sim, {"subtype": "AMMO_NEED_RESOLVED", "need_id": "fixture:A", "final_revision": 2, "requesting_command_id": "LOCAL_A"})
		if scenario == "E":
			sim.advance(8)
			sim.execute({"type": "CreateResource", "stockpile_id": "A_STOCK", "resource_type_id": "AMMUNITION", "quantity": 200}, true)
			p = report("LOCAL_A", 2, 0, 200)
			p.subtype = "AMMO_NEED_UPDATE"
			send(sim, p)
			sim.advance(2)
		else: sim.advance(30)
		sim.execute({"type": "EndRun"}, true)
	return R.ok(null, {"simulation": sim})
