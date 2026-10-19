extends "res://kernel/service.gd"
# Trusted application coordinator. Need/offer arithmetic consumes only scoped views.
const Policy = preload("res://kernel/resource_need_policy.gd")
const Clock = preload("res://kernel/clock.gd")
const Router = preload("res://kernel/router.gd")
const Logistics = preload("res://kernel/logistics_service.gd")
const Resources = preload("res://kernel/resource_service.gd")
const Communication = preload("res://kernel/communication_service.gd")
const Information = preload("res://kernel/information_service.gd")
const MATERIAL = ["urgency", "target_stock_quantity", "gross_need_quantity", "confirmed_incoming_quantity", "uncovered_need_quantity", "planning_rate_milli", "state", "condition"]

func scope(command: String, need: String, cause: Variant = null, coordination: Variant = null) -> void:
	sim.context = {"actor_entity_id": command, "source_system": "RESOURCE_RESOLUTION", "input_id": need, "causation_event_id": cause, "privileged": false, "coordination_id": coordination}

func active_need(command: String) -> Dictionary:
	for id in world.ids("resource_needs"):
		var need: Dictionary = world.get_entity("resource_needs", id)
		if need.command_id == command and need.state == "ACTIVE": return need
	return {}

func latest_batch(command: String) -> Dictionary:
	var best: Dictionary = {}
	for id in world.ids("observation_batches"):
		var batch: Dictionary = world.get_entity("observation_batches", id)
		if batch.command_id == command and batch.complete and (best.is_empty() or batch.observed_at_micro > best.observed_at_micro or (batch.observed_at_micro == best.observed_at_micro and batch.id > best.id)):
			best = batch
	return best

func incoming(command: String) -> int:
	var view: RefCounted = sim.command_view(command)
	var total := 0
	for transfer in view.known_incoming():
		if transfer.status == "IN_TRANSIT" and transfer.destination_stockpile_id == view.front_assignment().get("supply_stockpile_id"):
			total += int(transfer.quantity)
	return total

func save_need(need: Dictionary, event := "RESOURCE_NEED_UPDATED") -> void:
	var previous: Dictionary = world.get_entity("resource_needs", need.id)
	if not previous.is_empty():
		need.revision = previous.revision
		for key in MATERIAL:
			if need.get(key) != previous.get(key):
				need.revision += 1
				break
	sim.commit(event, [change("resource_needs", need)], {"need_id": need.id, "need_revision": need.revision}, need.id)

func coverage(need: Dictionary) -> void:
	need.confirmed_incoming_quantity = incoming(need.command_id)
	need.gross_need_quantity = maxi(0, int(need.target_stock_quantity) - int(need.available_quantity))
	need.uncovered_need_quantity = maxi(0, int(need.gross_need_quantity) - int(need.confirmed_incoming_quantity))
	need.condition = "SEEKING_SUPPLY"
	if need.get("awaiting_arrival_observation", false):
		need.condition = "AWAITING_OBSERVATION"
	elif need.uncovered_need_quantity == 0:
		need.condition = "COVERED_IN_TRANSIT" if need.confirmed_incoming_quantity > 0 else "AWAITING_CONFIRMATION"

func evaluate_batch(batch: Dictionary) -> Dictionary:
	var previous_context: Dictionary = sim.context
	if batch.is_empty(): return R.fail("INVALID_ENTITY")
	var command: Dictionary = world.get_command(batch.command_id)
	if command.is_empty() or not command.get("resource_resolution_enabled", false) or not command.enabled or command.local_decision_front_id != batch.front_id:
		return R.fail("INVALID_RESOURCE_RESOLUTION_CONFIGURATION")
	var sample := Policy.sample(sim.command_view(command.id), batch.front_id, batch, Clock.units(sim.time()))
	if not sample.success: return R.fail("INCOMPLETE_OR_STALE_NEED_INFORMATION", {"reasons": sample.reasons})
	var need := active_need(command.id)
	if need.is_empty() and sample.supply_state not in ["CRITICAL", "CONSTRAINED"]: return R.ok()
	var opening := need.is_empty()
	if opening:
		need = {"id": sim.entity_id("need"), "command_id": command.id, "front_id": batch.front_id, "resource_type_id": "AMMUNITION", "state": "ACTIVE", "condition": "SEEKING_SUPPLY", "revision": 1, "current_resolution_phase": "LOCAL", "active_coordination_id": null, "escalation_message_id": null, "escalation_status": "NOT_SENT", "attempted_peer_ids": [], "local_exhausted": false, "awaiting_arrival_observation": false}
	need.need_id = need.id
	scope(command.id, need.id, world.last_event(batch.id))
	need.urgency = sample.urgency
	need.target_stock_quantity = sample.target_stock_quantity
	need.available_quantity = sample.values.FRONT_AMMO_AVAILABLE
	need.planning_rate_milli = sample.planning_rate_milli
	need.last_shortage = sample.values.FRONT_LAST_SHORTAGE
	need.based_on_observation_batch_id = batch.id
	need.last_evaluated_at_micro = Clock.units(sim.time())
	need.based_on_observed_at_micro = batch.observed_at_micro
	need.belief_record_ids = sample.belief_record_ids
	need.awaiting_arrival_observation = false
	coverage(need)
	if not opening and need.available_quantity >= need.target_stock_quantity and need.confirmed_incoming_quantity == 0 and need.last_shortage == 0:
		need.state = "RESOLVED"
		need.condition = "PHYSICALLY_REFILLED"
	save_need(need, "RESOURCE_NEED_OPENED" if opening else ("RESOURCE_NEED_RESOLVED" if need.state == "RESOLVED" else "RESOURCE_NEED_UPDATED"))
	if need.state == "RESOLVED":
		cancel_request(need, "NEED_RESOLVED")
	else:
		progress(need.id)
	sim.context = previous_context
	return R.ok(need.id)

func on_complete(batch: Dictionary) -> void:
	if world.get_command(batch.command_id).get("resource_resolution_enabled", false):
		evaluate_batch(batch)

func register_transfer(need_id: String, command: String, shipment: String, quantity: int, destination: String, coordination: Variant, notice: Variant) -> void:
	var id := "known:" + command + ":" + shipment
	if not world.get_entity("known_transfers", id).is_empty(): return
	var record := {"id": id, "command_id": command, "need_id": need_id, "shipment_id": shipment, "quantity": quantity, "destination_stockpile_id": destination, "coordination_id": coordination, "source_message_id": notice, "known_at_micro": Clock.units(sim.time()), "status": "IN_TRANSIT"}
	var known_event: String = sim.commit("INCOMING_TRANSFER_CONFIRMED", [change("known_transfers", record)], {"need_id": need_id, "coordination_id": coordination}, id)
	sim.context.causation_event_id = known_event
	var need: Dictionary = world.get_entity("resource_needs", need_id)
	if not need.is_empty() and need.state == "ACTIVE":
		coverage(need)
		save_need(need)

# Infrastructure notifications only visit transfers already known to their recipient.
func sync_known_transfers() -> void:
	var previous_context: Dictionary = sim.context
	for id in world.ids("known_transfers"):
		var known: Dictionary = world.get_entity("known_transfers", id)
		var shipment: Dictionary = world.get_shipment(known.shipment_id)
		if shipment.is_empty() or shipment.state not in ["ARRIVED", "BLOCKED", "DESTROYED", "IN_TRANSIT"] or known.status == shipment.state: continue
		scope(known.command_id, known.need_id, world.last_event(shipment.id), known.coordination_id)
		known.status = shipment.state
		known.last_notification_at_micro = Clock.units(sim.time())
		var known_event: String = sim.commit("KNOWN_TRANSFER_STATUS_CHANGED", [change("known_transfers", known)], {"status": known.status, "recipient_command_id": known.command_id}, known.id)
		sim.context.causation_event_id = known_event
		var need: Dictionary = world.get_entity("resource_needs", known.need_id)
		if need.is_empty() or need.state != "ACTIVE": continue
		if known.status == "ARRIVED":
			need.awaiting_arrival_observation = Clock.units(shipment.arrived_at) > int(need.based_on_observed_at_micro)
		elif known.status in ["BLOCKED", "DESTROYED"]:
			need.attempted_peer_ids = []
			need.current_resolution_phase = "LOCAL"
			need.escalation_message_id = null
			need.escalation_status = "NOT_SENT"
		coverage(need)
		save_need(need)
	sim.context = previous_context

func local_help(need: Dictionary) -> void:
	var view: RefCounted = sim.command_view(need.command_id)
	for source in Policy.sources(view, 0):
		need = world.get_entity("resource_needs", need.id)
		if need.uncovered_need_quantity <= 0: break
		var quantity := mini(int(need.uncovered_need_quantity), int(source.quantity))
		var created: Dictionary = Logistics.new(sim).create_shipment(source.stockpile_id, view.front_assignment().supply_stockpile_id, "AMMUNITION", quantity, need.command_id)
		if not created.success: continue
		sim.context.causation_event_id = world.last_event(created.entity_id)
		var dispatched: Dictionary = Logistics.new(sim).dispatch(created.entity_id)
		if not dispatched.success:
			Logistics.new(sim).cancel(created.entity_id)
			continue
		sim.context.causation_event_id = world.last_event(created.entity_id)
		var event: String = sim.commit("LOCAL_RESOURCE_TRANSFER_DISPATCHED", [], {"need_id": need.id, "shipment_id": created.entity_id, "quantity": quantity}, need.id)
		sim.context.causation_event_id = event
		register_transfer(need.id, need.command_id, created.entity_id, quantity, view.front_assignment().supply_stockpile_id, null, null)

func snapshot_payload(need: Dictionary) -> Dictionary:
	return {"need_id": need.id, "need_revision": need.revision, "requesting_command_id": need.command_id, "requester_command_id": need.command_id, "front_id": need.front_id, "resource_type_id": "AMMUNITION", "destination_stockpile_id": sim.command_view(need.command_id).front_assignment().supply_stockpile_id, "urgency": need.urgency, "available_quantity": need.available_quantity, "confirmed_incoming_quantity": need.confirmed_incoming_quantity, "uncovered_need_quantity": need.uncovered_need_quantity, "target_stock_quantity": need.target_stock_quantity, "planning_rate_milli": need.planning_rate_milli, "observation_batch_id": need.based_on_observation_batch_id, "observed_at_micro": need.based_on_observed_at_micro}

func send(sender: String, recipient: String, type: String, payload: Dictionary) -> Dictionary:
	scope(sender, payload.need_id, sim.context.get("causation_event_id"), payload.get("coordination_id"))
	return Communication.new(sim).send(sender, recipient, type, payload)

func progress(id: String) -> void:
	var need: Dictionary = world.get_entity("resource_needs", id)
	if need.is_empty() or need.state != "ACTIVE" or need.get("awaiting_arrival_observation", false): return
	var batch := latest_batch(need.command_id)
	if batch.is_empty() or not Policy.sample(sim.command_view(need.command_id), need.front_id, batch, Clock.units(sim.time())).success: return
	scope(need.command_id, need.id, world.last_event(need.id))
	if need.uncovered_need_quantity <= 0: return
	local_help(need)
	need = world.get_entity("resource_needs", id)
	if need.uncovered_need_quantity <= 0:
		cancel_request(need, "NEED_REVISED")
		return
	if need.active_coordination_id != null: return
	need.local_exhausted = true
	var view: RefCounted = sim.command_view(need.command_id)
	for peer in view.peers():
		if peer.id in need.attempted_peer_ids: continue
		start_coordination(need, peer.id, view)
		return
	escalate(need, view)

func start_coordination(need: Dictionary, peer: String, view: RefCounted) -> void:
	var id: String = sim.entity_id("coordination")
	scope(need.command_id, need.id, world.last_event(need.id), id)
	var route: Dictionary = view.communication_route(peer)
	var deadline: int = Clock.units(sim.time()) + int(route.outbound_micro) + int(route.inbound_micro) + 1000000
	var c := {"id": id, "coordination_id": id, "need_id": need.id, "need_revision": need.revision, "requester_command_id": need.command_id, "peer_command_id": peer, "front_id": need.front_id, "destination_stockpile_id": view.front_assignment().supply_stockpile_id, "requested_quantity": need.uncovered_need_quantity, "requester_status": "WAIT_RESPONSE", "donor_status": "NONE", "state": "REQUESTED", "deadline_micro": deadline, "offer_expiry_micro": null, "reservation_ids": [], "allocations": [], "offered_quantity": 0, "confirmed_quantity": 0, "shipment_ids": [], "request_message_id": null, "response_message_id": null, "acceptance_message_id": null}
	need.active_coordination_id = id
	need.attempted_peer_ids.append(peer)
	need.current_resolution_phase = "PEER_COORDINATION"
	save_need(need)
	var cause: String = sim.commit("PEER_COORDINATION_STARTED", [change("peer_coordinations", c)], {"need_id": need.id}, id)
	sim.context.causation_event_id = cause
	var payload := snapshot_payload(need)
	payload.subtype = "AMMO_TRANSFER_REQUEST"
	payload.coordination_id = id
	payload.requested_quantity = c.requested_quantity
	payload.response_deadline_micro = deadline
	var result := send(need.command_id, peer, "COORDINATION", payload)
	c.request_message_id = result.entity_id
	sim.commit("PEER_COORDINATION_REQUEST_SENT", [change("peer_coordinations", c)], {"success": result.success, "error_code": result.error_code}, c.id)
	if not result.success: finish_request(c, "FAILED", result.error_code)

func finish_request(c: Dictionary, state: String, reason: String, cause: Variant = null) -> void:
	if c.requester_status == "DONE": return
	scope(c.requester_command_id, c.need_id, cause if cause != null else world.last_event(c.id), c.id)
	c.requester_status = "DONE"
	c.state = state
	c.reason_code = reason
	sim.commit("PEER_COORDINATION_FINISHED", [change("peer_coordinations", c)], {"reason_code": reason}, c.id)
	var need: Dictionary = world.get_entity("resource_needs", c.need_id)
	if not need.is_empty() and need.active_coordination_id == c.id:
		need.active_coordination_id = null
		if reason == "NEED_REVISED": need.attempted_peer_ids = []
		save_need(need)

func cancel_request(need: Dictionary, reason: String) -> void:
	if need.active_coordination_id == null: return
	var c: Dictionary = world.get_entity("peer_coordinations", need.active_coordination_id)
	if c.is_empty() or c.requester_status == "DONE": return
	var payload := {"subtype": "AMMO_TRANSFER_CANCEL", "need_id": need.id, "need_revision": need.revision, "coordination_id": c.id, "reason_code": reason}
	send(need.command_id, c.peer_command_id, "COORDINATION", payload)
	finish_request(c, "TIMED_OUT" if reason == "RESPONSE_TIMEOUT" else "CANCELLED", reason)

func escalate(need: Dictionary, view: RefCounted) -> void:
	if need.escalation_message_id != null: return
	var parent: Dictionary = view.direct_superior()
	var status := "NO_SUPERIOR" if parent.is_empty() else ("NO_COMMUNICATION_ROUTE" if not view.communication_route(parent.id).get("outbound", false) else "SENT")
	if status != "SENT":
		if need.escalation_status != status:
			need.escalation_status = status
			sim.commit("RESOURCE_NEED_ESCALATION_FAILED", [], {"reason_code": status, "need_id": need.id}, need.id)
			save_need(need)
		return
	var payload := snapshot_payload(need)
	payload.subtype = "AMMO_NEED_ESCALATION"
	var result := send(need.command_id, parent.id, "ESCALATION", payload)
	need.escalation_status = "SENT" if result.success else result.error_code
	need.escalation_message_id = result.entity_id
	need.current_resolution_phase = "ESCALATED"
	sim.commit("RESOURCE_NEED_ESCALATED" if result.success else "RESOURCE_NEED_ESCALATION_FAILED", [], {"need_id": need.id, "message_id": result.entity_id, "reason_code": result.error_code}, need.id)
	save_need(need)

func save_coord(c: Dictionary, event: String, details: Dictionary = {}) -> String:
	details.need_id = c.need_id
	details.coordination_id = c.id
	return sim.commit(event, [change("peer_coordinations", c)], details, c.id)

func release_offer(c: Dictionary) -> void:
	scope(c.peer_command_id, c.need_id, sim.context.get("causation_event_id", world.last_event(c.id)), c.id)
	for id in c.reservation_ids:
		var reservation: Dictionary = world.get_entity("resource_reservations", id)
		if reservation.get("state") == "ACTIVE":
			Resources.new(sim).release_peer_offer(id, c.id)
			sim.context.causation_event_id = world.last_event(id)

func decline(c: Dictionary, reason: String) -> void:
	scope(c.peer_command_id, c.need_id, sim.context.get("causation_event_id", world.last_event(c.id)), c.id)
	release_offer(c)
	c.donor_status = "CLOSED"
	c.state = "DECLINED"
	var cause := save_coord(c, "PEER_TRANSFER_DECLINED", {"reason_code": reason})
	sim.context.causation_event_id = cause
	var result := send(c.peer_command_id, c.requester_command_id, "COORDINATION", {"subtype": "AMMO_TRANSFER_DECLINED", "need_id": c.need_id, "need_revision": c.need_revision, "coordination_id": c.id, "reason_code": reason})
	c.response_message_id = result.entity_id
	save_coord(c, "PEER_COORDINATION_RESPONSE_SENT", {"success": result.success, "error_code": result.error_code})
	if not result.success: finish_request(c, "FAILED", reason)

func offer(c: Dictionary, message: Dictionary) -> void:
	scope(c.peer_command_id, c.need_id, world.last_event(message.id), c.id)
	if c.donor_status != "NONE": return
	if Clock.units(sim.time()) >= c.deadline_micro:
		decline(c, "REQUEST_EXPIRED")
		return
	var view: RefCounted = sim.command_view(c.peer_command_id)
	var route: Dictionary = view.communication_route(c.requester_command_id)
	if not route.get("outbound", false) or not route.get("inbound", false):
		decline(c, "NO_RETURN_COMMUNICATION_ROUTE")
		return
	var batch := latest_batch(c.peer_command_id)
	if batch.is_empty():
		decline(c, "STALE_OR_INCOMPLETE_LOCAL_INFORMATION")
		return
	var own := Policy.sample(view, view.front_assignment().get("front_id", ""), batch, Clock.units(sim.time()))
	if not own.success:
		decline(c, "STALE_OR_INCOMPLETE_LOCAL_INFORMATION")
		return
	var remaining: int = c.requested_quantity
	var saw_spare := false
	var saw_route := false
	for source in Policy.sources(view, own.target_stock_quantity, true):
		saw_spare = true
		# Transport/authority validation is outside allocation policy; no foreign quantities are used.
		var origin: Dictionary = view.local_stockpile(source.stockpile_id)
		var destination: Dictionary = world.get_stockpile(c.destination_stockpile_id)
		if not sim.authorized(c.peer_command_id, source.stockpile_id):
			continue
		var planned := Router.find(world, origin.location_id, destination.location_id)
		if not planned.success: continue
		saw_route = true
		var quantity := mini(remaining, int(source.quantity))
		if quantity <= 0: break
		var reserved: Dictionary = Resources.new(sim).reserve(source.stockpile_id, "AMMUNITION", quantity, c.peer_command_id, "PEER_AMMO_TRANSFER_OFFER")
		if not reserved.success: continue
		sim.context.causation_event_id = world.last_event(reserved.entity_id)
		c.reservation_ids.append(reserved.entity_id)
		c.allocations.append({"stockpile_id": source.stockpile_id, "quantity": quantity, "reservation_id": reserved.entity_id})
		remaining -= quantity
		if remaining == 0: break
	c.offered_quantity = c.requested_quantity - remaining
	if c.offered_quantity <= 0:
		decline(c, "INSUFFICIENT_SPARE_STOCK" if not saw_spare else ("NO_LOGISTICS_ROUTE" if not saw_route else "UNAUTHORIZED_SOURCE"))
		return
	c.offer_expiry_micro = Clock.units(sim.time()) + int(route.outbound_micro) + int(route.inbound_micro) + 1000000
	c.donor_status = "RESERVED"
	c.state = "OFFERED"
	c.peer_protected_stock = own.target_stock_quantity
	c.peer_planning_rate_milli = own.planning_rate_milli
	c.peer_belief_record_ids = own.belief_record_ids
	var cause := save_coord(c, "PEER_TRANSFER_OFFERED", {"quantity": c.offered_quantity, "offer_expiry_micro": c.offer_expiry_micro})
	sim.context.causation_event_id = cause
	var result := send(c.peer_command_id, c.requester_command_id, "COORDINATION", {"subtype": "AMMO_TRANSFER_OFFER", "need_id": c.need_id, "need_revision": c.need_revision, "coordination_id": c.id, "quantity": c.offered_quantity, "offer_expiry_micro": c.offer_expiry_micro})
	c.response_message_id = result.entity_id
	save_coord(c, "PEER_COORDINATION_RESPONSE_SENT", {"success": result.success})
	if not result.success:
		release_offer(c)
		finish_request(c, "FAILED", result.error_code)

func receive_offer(c: Dictionary, message: Dictionary) -> void:
	if c.requester_status != "WAIT_RESPONSE": return
	var need: Dictionary = world.get_entity("resource_needs", c.need_id)
	if need.state != "ACTIVE":
		cancel_request(need, "NEED_RESOLVED")
		return
	# Reevaluate from the latest complete/fresh owned information, never requester truth.
	var batch := latest_batch(need.command_id)
	if batch.is_empty() or not Policy.sample(sim.command_view(need.command_id), need.front_id, batch, Clock.units(sim.time())).success:
		cancel_request(need, "STALE_OR_INCOMPLETE_LOCAL_INFORMATION")
		return
	coverage(need)
	save_need(need)
	if c.offered_quantity > need.uncovered_need_quantity:
		cancel_request(need, "NEED_REVISED")
		return
	if c.offered_quantity <= 0 or Clock.units(sim.time()) >= c.offer_expiry_micro:
		cancel_request(need, "OFFER_EXPIRED")
		return
	c.requester_status = "WAIT_DISPATCH"
	c.state = "ACCEPTED"
	c.accepted_quantity = c.offered_quantity
	var route: Dictionary = sim.command_view(need.command_id).communication_route(c.peer_command_id)
	c.deadline_micro = Clock.units(sim.time()) + int(route.get("outbound_micro", 0)) + int(route.get("inbound_micro", 0)) + 1000000
	var cause := save_coord(c, "PEER_TRANSFER_ACCEPTED", {"quantity": c.offered_quantity, "current_need_revision": need.revision})
	sim.context.causation_event_id = cause
	var result := send(need.command_id, c.peer_command_id, "COORDINATION", {"subtype": "AMMO_TRANSFER_ACCEPT", "need_id": need.id, "need_revision": need.revision, "coordination_id": c.id, "quantity": c.offered_quantity})
	c.acceptance_message_id = result.entity_id
	save_coord(c, "PEER_COORDINATION_ACCEPTANCE_SENT", {"success": result.success})
	if not result.success:
		cancel_request(need, result.error_code)

func receive_accept(c: Dictionary, message: Dictionary) -> void:
	if c.donor_status != "RESERVED": return
	scope(c.peer_command_id, c.need_id, world.last_event(message.id), c.id)
	if Clock.units(sim.time()) >= c.offer_expiry_micro or message.payload.get("quantity") != c.offered_quantity:
		decline(c, "OFFER_EXPIRED")
		return
	# Revalidate every claim/source/route before converting any offer claim.
	for allocation in c.allocations:
		var r: Dictionary = world.get_entity("resource_reservations", allocation.reservation_id)
		var origin := enabled_stockpile(allocation.stockpile_id)
		var destination := enabled_stockpile(c.destination_stockpile_id)
		if r.get("state") != "ACTIVE" or not sim.authorized(c.peer_command_id, allocation.stockpile_id):
			decline(c, "UNAUTHORIZED_SOURCE")
			return
		if origin.is_empty() or destination.is_empty() or not Router.find(world, origin.location_id, destination.location_id).success:
			decline(c, "NO_LOGISTICS_ROUTE")
			return
	for allocation in c.allocations:
		var dispatched: Dictionary = Logistics.new(sim).dispatch_reserved(allocation.reservation_id, c.destination_stockpile_id, c.peer_command_id)
		if not dispatched.success:
			decline(c, dispatched.error_code)
			return
		sim.context.causation_event_id = world.last_event(dispatched.entity_id)
		c.shipment_ids.append(dispatched.entity_id)
		var cause := save_coord(c, "PEER_TRANSFER_DISPATCHED", {"shipment_id": dispatched.entity_id, "quantity": allocation.quantity, "reservation_id": allocation.reservation_id})
		sim.context.causation_event_id = cause
		send(c.peer_command_id, c.requester_command_id, "COORDINATION", {"subtype": "AMMO_TRANSFER_DISPATCHED", "need_id": c.need_id, "need_revision": message.payload.need_revision, "coordination_id": c.id, "shipment_id": dispatched.entity_id, "quantity": allocation.quantity, "source_stockpile_id": allocation.stockpile_id, "destination_stockpile_id": c.destination_stockpile_id})
	c.donor_status = "DISPATCHED"
	c.state = "DISPATCHED"
	save_coord(c, "PEER_TRANSFER_DISPATCH_COMPLETED")

func process_message(message: Dictionary) -> void:
	var payload: Dictionary = message.payload
	var subtype: String = payload.get("subtype", "")
	var need_id: Variant = payload.get("need_id")
	if not need_id is String or not canonical_quantity(payload.get("need_revision"), 9007199254740991) or payload.need_revision < 1: return
	scope(message.recipient_command_id, need_id, world.last_event(message.id), payload.get("coordination_id"))
	if message.message_type == "ESCALATION" and subtype == "AMMO_NEED_ESCALATION":
		var sender: Dictionary = world.get_command(message.sender_command_id)
		if sender.command_level != "LOCAL" or sender.superior_command_id != message.recipient_command_id or payload.get("requesting_command_id") != sender.id: return
		for key in ["uncovered_need_quantity", "urgency", "front_id", "observed_at_micro"]:
			if not payload.has(key): return
		if not payload.observed_at_micro is int and not payload.observed_at_micro is float: return
		if payload.observed_at_micro < 0 or payload.observed_at_micro > Clock.units(sim.time()) or payload.observed_at_micro != floor(payload.observed_at_micro): return
		if not canonical_quantity(payload.uncovered_need_quantity, 18000000) or not canonical_quantity(payload.need_revision, 9007199254740991) or payload.need_revision < 1 or payload.get("resource_type_id") != "AMMUNITION" or payload.urgency not in ["CRITICAL", "CONSTRAINED", "REFILL"] or not payload.front_id is String: return
		var highest_revision := 0
		for record in sim.command_view(message.recipient_command_id).information():
			if record.subject_entity_id == need_id and record.fact_key == "SUBORDINATE_AMMO_NEED_REVISION":
				if record.source_command_id != sender.id: return
				highest_revision = maxi(highest_revision, int(record.value))
		if payload.need_revision <= highest_revision:
			sim.commit("RESOURCE_NEED_STALE_ESCALATION_IGNORED", [], {"need_id": need_id, "reported_revision": payload.need_revision, "known_revision": highest_revision, "source_message_id": message.id}, need_id)
			return
		var facts := {"SUBORDINATE_AMMO_NEED_QUANTITY": payload.uncovered_need_quantity, "SUBORDINATE_AMMO_NEED_URGENCY": payload.urgency, "SUBORDINATE_AMMO_NEED_REVISION": payload.need_revision, "SUBORDINATE_AMMO_NEED_FRONT": payload.front_id}
		for key in facts:
			Information.new(sim).ingest(message.recipient_command_id, {"subject_entity_id": need_id, "fact_key": key, "value": facts[key], "observed_at": payload.observed_at_micro / 1000000.0, "confidence": 1.0}, sender.id, message.id, world.last_event(message.id))
		return
	if message.message_type != "COORDINATION" or not payload.get("coordination_id") is String: return
	var c: Dictionary = world.get_entity("peer_coordinations", payload.coordination_id)
	if c.is_empty() or c.need_id != need_id: return
	var from_requester: bool = message.sender_command_id == c.requester_command_id and message.recipient_command_id == c.peer_command_id
	var from_peer: bool = message.sender_command_id == c.peer_command_id and message.recipient_command_id == c.requester_command_id
	if not from_requester and not from_peer: return
	match subtype:
		"AMMO_TRANSFER_REQUEST":
			if from_requester and c.request_message_id == message.id:
				var requester: Dictionary = world.get_command(c.requester_command_id)
				var peer: Dictionary = world.get_command(c.peer_command_id)
				if requester.superior_command_id == null or requester.superior_command_id != peer.superior_command_id or peer.command_level != "LOCAL" or c.destination_stockpile_id not in requester.directly_controlled_stockpile_ids:
					decline(c, "UNAUTHORIZED_SOURCE")
				else: offer(c, message)
		"AMMO_TRANSFER_OFFER":
			if from_peer and c.response_message_id == message.id: receive_offer(c, message)
		"AMMO_TRANSFER_ACCEPT":
			if from_requester and c.acceptance_message_id == message.id: receive_accept(c, message)
		"AMMO_TRANSFER_CANCEL":
			if from_requester:
				release_offer(c)
				c.donor_status = "CLOSED"
				save_coord(c, "PEER_TRANSFER_DECLINED", {"reason_code": payload.get("reason_code", "CANCELLED")})
		"AMMO_TRANSFER_DECLINED", "AMMO_TRANSFER_EXPIRED":
			if from_peer: finish_request(c, "DECLINED", payload.get("reason_code", "OFFER_EXPIRED"))
		"AMMO_TRANSFER_DISPATCHED":
			if not from_peer or not payload.get("shipment_id") is String or payload.shipment_id not in c.shipment_ids: return
			var shipment: Dictionary = world.get_shipment(payload.shipment_id)
			if payload.get("quantity") != shipment.quantity or payload.get("destination_stockpile_id") != c.destination_stockpile_id: return
			var known_id: String = "known:" + c.requester_command_id + ":" + payload.shipment_id
			if world.get_entity("known_transfers", known_id).is_empty():
				register_transfer(c.need_id, c.requester_command_id, payload.shipment_id, int(payload.quantity), c.destination_stockpile_id, c.id, message.id)
				c.confirmed_quantity += int(payload.quantity)
			save_coord(c, "PEER_TRANSFER_NOTICE_RECEIVED", {"shipment_id": payload.shipment_id})
			if c.confirmed_quantity >= c.get("accepted_quantity", c.offered_quantity):
				finish_request(c, "DISPATCHED", "DISPATCH_CONFIRMED")

func step(tick_event: Variant = null) -> void:
	var previous_context: Dictionary = sim.context
	# Timeouts and offer expiry use simulation time. Local transport failure is scoped
	# to each registered conversation, not a global knowledge surface for planners.
	for id in world.ids("peer_coordinations"):
		var c: Dictionary = world.get_entity("peer_coordinations", id)
		if c.donor_status == "RESERVED" and Clock.units(sim.time()) >= c.offer_expiry_micro:
			scope(c.peer_command_id, c.need_id, tick_event, c.id)
			release_offer(c)
			c.donor_status = "EXPIRED"
			c.state = "EXPIRED"
			var cause := save_coord(c, "PEER_TRANSFER_OFFER_EXPIRED")
			sim.context.causation_event_id = cause
			send(c.peer_command_id, c.requester_command_id, "COORDINATION", {"subtype": "AMMO_TRANSFER_EXPIRED", "need_id": c.need_id, "need_revision": c.need_revision, "coordination_id": c.id, "reason_code": "OFFER_EXPIRED"})
		c = world.get_entity("peer_coordinations", id)
		if c.requester_status != "DONE":
			var failed := false
			for message_id in [c.request_message_id, c.response_message_id, c.acceptance_message_id]:
				if message_id != null and world.get_entity("messages", message_id).get("state") == "FAILED":
					failed = true
					c.failure_message_id = message_id
			if failed: finish_request(c, "FAILED", "MESSAGE_FAILED", world.last_event(c.failure_message_id))

	# Bounded deterministic drain handles zero-latency chains without recursive app calls.
	for unused in range(64):
		var handled := false
		for command_id in world.ids("commands"):
			var view: RefCounted = sim.command_view(command_id)
			for message in view.inbox():
				var subtype: Variant = message.payload.get("subtype")
				if not subtype is String or not (subtype.begins_with("AMMO_TRANSFER_") or subtype == "AMMO_NEED_ESCALATION"): continue
				var rid: String = "receipt:" + message.id
				if not world.get_entity("resolution_receipts", rid).is_empty(): continue
				scope(command_id, str(message.payload.get("need_id", "")), world.last_event(message.id), message.payload.get("coordination_id"))
				sim.commit("RESOURCE_RESOLUTION_MESSAGE_PROCESSED", [change("resolution_receipts", {"id": rid, "command_id": command_id, "message_id": message.id, "subtype": subtype, "processed_at_micro": Clock.units(sim.time())})], {}, rid)
				process_message(message)
				handled = true
		if not handled: break
	# Delivered responses at the deadline are processed before deciding that none arrived.
	for id in world.ids("peer_coordinations"):
		var c: Dictionary = world.get_entity("peer_coordinations", id)
		if response_timed_out(c, Clock.units(sim.time())):
			cancel_request(world.get_entity("resource_needs", c.need_id), "RESPONSE_TIMEOUT")
	sync_known_transfers()
	for id in world.ids("resource_needs"):
		var need: Dictionary = world.get_entity("resource_needs", id)
		if need.state == "ACTIVE":
			if need.escalation_message_id != null:
				var message: Dictionary = world.get_entity("messages", need.escalation_message_id)
				if message.get("state") == "FAILED":
					scope(need.command_id, need.id, world.last_event(message.id))
					need.last_failed_escalation_message_id = message.id
					need.escalation_message_id = null
					need.escalation_status = "DELIVERY_FAILED"
					sim.commit("RESOURCE_NEED_ESCALATION_FAILED", [], {"reason_code": "MESSAGE_FAILED", "message_id": message.id}, need.id)
					save_need(need)
			progress(id)
	sim.context = previous_context



func canonical_quantity(value: Variant, maximum: int) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value >= 0 and value <= maximum and value == floor(value)

static func response_timed_out(coordination: Dictionary, now_micro: int) -> bool:
	return coordination.requester_status != "DONE" and now_micro >= int(coordination.deadline_micro)
