extends RefCounted
const World = preload("res://kernel/world_state.gd")

# Deterministic read/write audit, not timestamp proximity: follow entity IDs,
# actual event-prefix stock writes, batch record IDs and need/journal references.
static func run(sim: RefCounted) -> Dictionary:
	var projection := World.new(sim.initial_world)
	var arrivals: Dictionary = {}
	var previous_batch: Dictionary = {}
	var impacts: Array = []
	var event_by_id: Dictionary = {}
	var need_events: Dictionary = {}
	var decisions_by_batch: Dictionary = {}
	var families: Dictionary = {}
	var types: Dictionary = {}
	var transitions: Array = []
	var need_timeline: Array = []
	var valid_causation := true
	var stock_last_write: Dictionary = {}
	for event in sim.events.all():
		if event.causation_event_id != null and not event_by_id.has(event.causation_event_id): valid_causation = false
		event_by_id[event.event_id] = event
		types[event.event_type] = types.get(event.event_type, 0) + 1
		var family: String = event.event_type.get_slice("_", 0)
		families[family] = families.get(family, 0) + 1
		projection.apply_event(event)
		for change in event.payload.get("changes", []):
			if change.table == "stockpiles": stock_last_write[change.id] = event.event_id
			if change.table == "decisions" and change.value.get("observation_batch_id") != null:
				decisions_by_batch[change.value.observation_batch_id] = change.value.id
			if change.table == "resource_needs":
				var need: Dictionary = change.value
				var batch_id: String = need.based_on_observation_batch_id
				if not need_events.has(batch_id): need_events[batch_id] = []
				need_events[batch_id].append(event.event_id)
				need_timeline.append({"event_id": event.event_id, "time": event.simulation_time, "need_id": need.id, "command_id": need.command_id, "revision": need.revision, "state": need.state, "condition": need.condition, "available": need.available_quantity, "target": need.target_stock_quantity, "incoming": need.confirmed_incoming_quantity, "uncovered": need.uncovered_need_quantity, "observation_batch_id": batch_id})
		if event.event_type == "FRONT_POSTURE_CHANGED": transitions.append({"event_id": event.event_id, "time": event.simulation_time, "front_id": event.subject_entity_id, "previous": event.payload.previous, "value": event.payload.value, "decision_id": event.payload.decision_id})
		if event.event_type == "SHIPMENT_ARRIVED":
			var shipment: Dictionary = projection.get_shipment(event.subject_entity_id)
			var stock: String = shipment.destination_stockpile_id
			if not arrivals.has(stock): arrivals[stock] = []
			arrivals[stock].append({"event_id": event.event_id, "shipment_id": shipment.id, "need_id": shipment.get("need_id"), "quantity": shipment.quantity})
		if event.event_type == "FRONT_OBSERVATION_COMPLETE":
			var batch: Dictionary = projection.get_entity("observation_batches", event.subject_entity_id)
			var front: Dictionary = projection.get_front(batch.front_id)
			var stock_id: String = front.supply_stockpile_id
			var available: Dictionary = projection.get_entity("information_records", batch.record_ids.FRONT_AMMO_AVAILABLE)
			var prior: Dictionary = previous_batch.get(batch.front_id, {})
			if arrivals.has(stock_id) and not arrivals[stock_id].is_empty():
				impacts.append({"front_id": batch.front_id, "destination_stockpile_id": stock_id, "arrivals": arrivals[stock_id].duplicate(true), "observed_stock_write_event_id": stock_last_write.get(stock_id), "observation_batch_id": batch.id, "observation_event_id": batch.id.trim_prefix("observation:"), "available_information_id": available.id, "before_batch_id": prior.get("batch_id"), "before_information_id": prior.get("information_id"), "before_available": prior.get("available"), "after_available": available.value})
				arrivals[stock_id] = []
			previous_batch[batch.front_id] = {"batch_id": batch.id, "information_id": available.id, "available": available.value}
	for impact in impacts:
		impact.need_event_ids = need_events.get(impact.observation_batch_id, [])
		impact.decision_id = decisions_by_batch.get(impact.observation_batch_id)
	var c_needs: Array = sim.world.ids("resource_needs").filter(func(id): return sim.world.get_entity("resource_needs", id).command_id == "LOCAL_C")
	var chain: Dictionary = {}
	if not c_needs.is_empty():
		var need: Dictionary = sim.world.get_entity("resource_needs", c_needs[0])
		var opening: Dictionary = {}
		for event in sim.events.all():
			if event.event_type == "RESOURCE_NEED_OPENED" and event.subject_entity_id == need.id: opening = event
		if not opening.is_empty():
			var first: Dictionary = opening.payload.changes[0].value
			var escalation: Dictionary = sim.world.get_entity("messages", need.escalation_message_id)
			chain = {"need_id": need.id, "opening_event_id": opening.event_id, "observation_batch_id": first.based_on_observation_batch_id, "local_decision_id": decisions_by_batch.get(first.based_on_observation_batch_id), "self_help_shipments": [], "peer_conversations": [], "escalation_message_id": escalation.id, "superior_report_id": "need-report:OPERATIONAL_COMMAND:" + need.id, "arbitration_outputs": [], "physical_observation_impacts": impacts.filter(func(i): return i.front_id == "FRONT_C")}
			for id in sim.world.ids("shipments"):
				var ship: Dictionary = sim.world.get_shipment(id)
				if ship.get("need_id") == need.id and ship.origin_stockpile_id == "C_LOCAL_RESERVE": chain.self_help_shipments.append(id)
			for id in sim.world.ids("peer_coordinations"):
				var c: Dictionary = sim.world.get_entity("peer_coordinations", id)
				if c.need_id == need.id: chain.peer_conversations.append({"coordination_id": c.id, "request_message_id": c.request_message_id, "offer_message_id": c.response_message_id, "acceptance_message_id": c.acceptance_message_id, "reservation_ids": c.reservation_ids, "shipment_ids": c.shipment_ids})
			for decision in sim.decision_journal("OPERATIONAL_COMMAND"):
				for selected in decision.selected_allocations:
					if selected.need_id != need.id: continue
					var ships: Array = []
					for id in decision.shipment_ids:
						var ship: Dictionary = sim.world.get_shipment(id)
						if ship.get("need_id") != need.id: continue
						var notice: Dictionary = {}
						for mid in sim.world.ids("messages"):
							var message: Dictionary = sim.world.get_entity("messages", mid)
							if message.payload.get("subtype") == "AMMO_ALLOCATION_DISPATCHED" and message.payload.get("shipment_id") == id: notice = message
						ships.append({"shipment_id": id, "quantity": ship.quantity, "notification_message_id": notice.get("id"), "known_transfer_id": "known:LOCAL_C:" + id, "arrival_impacts": impacts.filter(func(i): return i.arrivals.any(func(a): return a.shipment_id == id))})
					chain.arbitration_outputs.append({"arbitration_id": decision.arbitration_id, "decision_id": decision.id, "report_id": selected.report_id, "report_message_id": selected.report_message_id, "need_revision": selected.need_revision, "stage_ms": selected.stage_threshold_ms, "quantity": selected.quantity, "shipments": ships})
	return {"valid_causation": valid_causation, "event_type_counts": types, "event_family_counts": families, "posture_timeline": transitions, "need_timeline": need_timeline, "physical_impacts": impacts, "causal_chain_C": chain}
