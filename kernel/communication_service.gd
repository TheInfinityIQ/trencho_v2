extends "res://kernel/service.gd"

const Router = preload("res://kernel/router.gd")
const Clock = preload("res://kernel/clock.gd")
const Information = preload("res://kernel/information_service.gd")
const TYPES = ["REPORT", "PROPOSAL", "COORDINATION", "ESCALATION", "STRATEGIC_REQUEST", "ORDER", "ACKNOWLEDGEMENT", "GENERIC"]

func send(sender: String, recipient: String, type: String, payload: Dictionary) -> Dictionary:
	for id in [sender, recipient]:
		var command: Dictionary = world.get_command(id)
		if command.is_empty() or not command.enabled:
			return R.fail("INVALID_ENTITY")
	if not sim.privileged() and sim.actor() != sender:
		return R.fail("UNAUTHORIZED")
	if type not in TYPES:
		return R.fail("INVALID_MESSAGE_TYPE")
	if type == "REPORT":
		if not payload.get("facts", []) is Array:
			return R.fail("INVALID_INFORMATION")
		for fact in payload.get("facts", []):
			if not fact is Dictionary:
				return R.fail("INVALID_INFORMATION")
			var validation: Dictionary = Information.new(sim).validate_fact(fact)
			if not validation.success:
				return validation
	var route: Dictionary = Router.find(world, sender, recipient, true)
	if not route.success:
		return route
	var id: String = sim.entity_id("message")
	var duration_us: int = Clock.units(world.clock().tick_duration)
	var latency_us: int = Clock.units(route.details.total_travel_time)
	var due_tick: int = world.clock().tick_index + ceili(float(latency_us) / duration_us)
	var message := {"id": id, "sender_command_id": sender, "recipient_command_id": recipient, "message_type": type, "payload": payload.duplicate(true), "sent_at": sim.time(), "route_edge_ids": route.details.edge_ids, "delivery_time": Clock.seconds(due_tick, world.clock().tick_duration), "delivery_tick": due_tick, "state": "IN_TRANSIT", "correlation_id": sim.context.get("input_id"), "causation_event_id": sim.context.get("causation_event_id")}
	sim.commit("MESSAGE_SENT", [change("messages", message)], {}, id)
	if due_tick <= world.clock().tick_index:
		step()
	return R.ok(id)

func step() -> void:
	for id in world.active_ids("messages"):
		var message: Dictionary = world.get_entity("messages", id)
		if message.state != "IN_TRANSIT" or message.delivery_tick > world.clock().tick_index:
			continue
		var intact := true
		for edge_id in message.route_edge_ids:
			var edge: Dictionary = world.get_entity("communication_edges", edge_id)
			intact = intact and edge.enabled and world.get_command(edge.from_command_id).enabled and world.get_command(edge.to_command_id).enabled
		intact = intact and world.get_command(message.recipient_command_id).enabled
		message.state = "DELIVERED" if intact else "FAILED"
		var cause: String = sim.commit("MESSAGE_DELIVERED" if intact else "MESSAGE_FAILED", [change("messages", message)], {}, id)
		if intact and message.message_type == "REPORT":
			for fact in message.payload.get("facts", []):
				Information.new(sim).ingest(message.recipient_command_id, fact, message.sender_command_id, id, cause)
