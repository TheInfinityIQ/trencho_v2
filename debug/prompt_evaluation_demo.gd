extends RefCounted
const Simulation = preload("res://kernel/simulation.gd")
const Base = preload("res://debug/player_prompt_demo.gd")

static func definition(enabled := true, latency := 0.1, integrated := false) -> Dictionary:
	var data := Base.definition()
	data.id = "step111"
	data.commands[0].strategic_prompt_evaluation_enabled = enabled
	if not integrated:
		data.stockpiles[0].quantities.AMMUNITION = 0
		for command in data.commands.slice(1):
			command.resource_resolution_enabled = false
			command.local_decision_front_id = null
		data.communication_edges = [{"id": "LOCAL_C_to_OPERATIONAL_COMMAND", "from_command_id": "LOCAL_C", "to_command_id": "OPERATIONAL_COMMAND", "latency_seconds": latency}, {"id": "OPERATIONAL_COMMAND_to_LOCAL_C", "from_command_id": "OPERATIONAL_COMMAND", "to_command_id": "LOCAL_C", "latency_seconds": 0.2}]
	return data

static func fresh(enabled := true, latency := 0.1, integrated := false) -> RefCounted:
	var sim := Simulation.new()
	var result: Dictionary = sim.initialize(definition(enabled, latency, integrated), 111, "step111")
	assert(result.success, JSON.stringify(result))
	return sim

static func prompt(sim: RefCounted, type := "DIRECT_ATTENTION", area := "AREA_FRONT_C") -> Dictionary:
	return sim.execute(Base.input(type, area))

static func report(revision := 1, need := "fixture:C") -> Dictionary:
	return {"subtype": "AMMO_NEED_ESCALATION", "need_id": need, "need_revision": revision, "requesting_command_id": "LOCAL_C", "front_id": "FRONT_C", "destination_stockpile_id": "C_FRONT_STOCK", "resource_type_id": "AMMUNITION", "urgency": "CRITICAL", "available_quantity": 0, "confirmed_incoming_quantity": 0, "uncovered_need_quantity": 80, "target_stock_quantity": 80, "planning_rate_milli": 4000, "observation_batch_id": "fixture-observation:C", "observed_at_micro": 0}

static func send(sim: RefCounted, payload: Dictionary) -> Dictionary:
	return sim.execute({"type": "SendMessage", "actor_entity_id": "LOCAL_C", "sender_command_id": "LOCAL_C", "recipient_command_id": "OPERATIONAL_COMMAND", "message_type": "ESCALATION", "payload": payload})

static func resolved(revision := 2, need := "fixture:C") -> Dictionary:
	return {"subtype": "AMMO_NEED_RESOLVED", "need_id": need, "requesting_command_id": "LOCAL_C", "final_revision": revision}
