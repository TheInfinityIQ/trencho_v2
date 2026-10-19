extends "res://kernel/service.gd"

const Router = preload("res://kernel/router.gd")
const Clock = preload("res://kernel/clock.gd")
const Resources = preload("res://kernel/resource_service.gd")

func create_shipment(origin_id: String, destination_id: String, resource: String, quantity: Variant, actor: Variant) -> Dictionary:
	if not quantity_valid(resource, quantity):
		return R.fail("INVALID_QUANTITY")
	var origin: Dictionary = world.get_stockpile(origin_id)
	var destination: Dictionary = world.get_stockpile(destination_id)
	if origin.is_empty() or destination.is_empty():
		return R.fail("INVALID_ENTITY")
	if enabled_stockpile(origin_id).is_empty():
		return R.fail("ORIGIN_DISABLED")
	if enabled_stockpile(destination_id).is_empty():
		return R.fail("DESTINATION_DISABLED")
	if origin_id == destination_id:
		return R.fail("INVALID_ENTITY")
	if not sim.authorized(actor, origin_id):
		return R.fail("UNAUTHORIZED")
	if available(origin, resource) < quantity:
		return R.fail("INSUFFICIENT_AVAILABLE_STOCK")
	var route: Dictionary = Router.find(world, origin.location_id, destination.location_id)
	if not route.success:
		return route
	var id: String = sim.entity_id("shipment")
	var rid: String = sim.entity_id("reservation")
	var reservation: Dictionary = Resources.new(sim).reservation(rid, origin_id, resource, quantity, actor, "SHIPMENT")
	origin.reserved[resource] = origin.reserved.get(resource, 0) + quantity
	var shipment := {"id": id, "resource_type_id": resource, "quantity": quantity, "origin_stockpile_id": origin_id, "destination_stockpile_id": destination_id, "requested_by_command_id": actor, "reservation_id": rid, "route_edge_ids": route.details.edge_ids, "current_route_index": 0, "current_location_id": origin.location_id, "edge_progress_seconds": 0.0, "state": "PLANNED", "created_at": sim.time(), "departed_at": null, "arrived_at": null, "blocked_reason": null}
	if sim.context.get("source_system") == "RESOURCE_RESOLUTION":
		shipment.need_id = sim.context.input_id
		shipment.coordination_id = sim.context.get("coordination_id")
	var cause: String = sim.commit("RESERVATION_CREATED", [change("stockpiles", origin), change("resource_reservations", reservation), change("shipments", shipment)], {"shipment_id": id}, rid)
	sim.commit("SHIPMENT_CREATED", [], {"reservation_id": rid, "route": route.details}, id, cause)
	return R.ok(id)

func dispatch(id: String) -> Dictionary:
	var s: Dictionary = world.get_shipment(id)
	if s.is_empty():
		return R.fail("INVALID_ENTITY")
	if not sim.authorized(sim.actor(), s.origin_stockpile_id):
		return R.fail("UNAUTHORIZED")
	if s.state != "PLANNED":
		return R.fail("INVALID_STATE")
	var r: Dictionary = world.get_entity("resource_reservations", s.reservation_id)
	if r.is_empty() or r.state != "ACTIVE" or r.stockpile_id != s.origin_stockpile_id or r.quantity != s.quantity:
		return R.fail("RESERVATION_MISMATCH")
	if r.resource_type_id != s.resource_type_id:
		return R.fail("RESOURCE_TYPE_MISMATCH")
	var origin := enabled_stockpile(s.origin_stockpile_id)
	if origin.is_empty():
		return R.fail("ORIGIN_DISABLED")
	if enabled_stockpile(s.destination_stockpile_id).is_empty():
		return R.fail("DESTINATION_DISABLED")
	if not s.route_edge_ids.is_empty() and not world.get_entity("logistics_edges", s.route_edge_ids[0]).enabled:
		return R.fail("ROUTE_DISABLED")
	origin.quantities[s.resource_type_id] -= s.quantity
	origin.reserved[s.resource_type_id] -= s.quantity
	r.state = "FULFILLED"
	s.state = "IN_TRANSIT"
	s.departed_at = sim.time()
	var cause: String = sim.commit("RESERVATION_FULFILLED", [change("stockpiles", origin), change("resource_reservations", r), change("shipments", s)], {"shipment_id": id}, r.id)
	sim.commit("SHIPMENT_DISPATCHED", [], {}, id, cause)
	return R.ok(id)

func cancel(id: String) -> Dictionary:
	var s: Dictionary = world.get_shipment(id)
	if s.is_empty():
		return R.fail("INVALID_ENTITY")
	if not sim.authorized(sim.actor(), s.origin_stockpile_id):
		return R.fail("UNAUTHORIZED")
	if s.state != "PLANNED":
		return R.fail("INVALID_STATE")
	var r: Dictionary = world.get_entity("resource_reservations", s.reservation_id)
	if r.state != "ACTIVE":
		return R.fail("RESERVATION_MISMATCH")
	var stock: Dictionary = world.get_stockpile(s.origin_stockpile_id)
	stock.reserved[s.resource_type_id] -= s.quantity
	r.state = "RELEASED"
	s.state = "CANCELLED"
	var cause: String = sim.commit("RESERVATION_RELEASED", [change("stockpiles", stock), change("resource_reservations", r), change("shipments", s)], {}, r.id)
	sim.commit("SHIPMENT_CANCELLED", [], {}, id, cause)
	return R.ok(id)

func controls(s: Dictionary) -> bool:
	return sim.privileged() or (sim.actor() != null and sim.actor() == s.requested_by_command_id and world.get_command(sim.actor()).get("enabled", false))

func reroute(id: String, destination_id: String) -> Dictionary:
	var s: Dictionary = world.get_shipment(id)
	if s.is_empty():
		return R.fail("INVALID_ENTITY")
	if not controls(s):
		return R.fail("UNAUTHORIZED")
	if s.state not in ["IN_TRANSIT", "BLOCKED"]:
		return R.fail("INVALID_STATE")
	var destination := enabled_stockpile(destination_id)
	if destination.is_empty():
		return R.fail("DESTINATION_DISABLED")
	var route: Dictionary = Router.find(world, s.current_location_id, destination.location_id)
	if not route.success:
		block(s, "NO_LOGISTICS_ROUTE")
		return route
	var abandoned: Variant = s.route_edge_ids[s.current_route_index] if s.current_route_index < s.route_edge_ids.size() else null
	var progress: float = s.edge_progress_seconds
	s.route_edge_ids = route.details.edge_ids
	s.destination_stockpile_id = destination_id
	s.current_route_index = 0
	s.edge_progress_seconds = 0.0
	s.state = "IN_TRANSIT"
	s.blocked_reason = null
	sim.commit("SHIPMENT_REROUTED", [change("shipments", s)], {"abandoned_edge_id": abandoned, "abandoned_edge_progress_seconds": progress, "route": route.details}, id)
	return R.ok(id)

func destroy(id: String, reason: String) -> Dictionary:
	if not sim.privileged():
		return R.fail("UNAUTHORIZED")
	var s: Dictionary = world.get_shipment(id)
	if s.is_empty():
		return R.fail("INVALID_ENTITY")
	if s.state not in ["IN_TRANSIT", "BLOCKED"]:
		return R.fail("INVALID_STATE")
	s.state = "DESTROYED"
	var l := ledger(s.resource_type_id)
	l.destroyed += s.quantity
	var cause: String = sim.commit("SHIPMENT_DESTROYED", [change("shipments", s), change("ledger", l)], {"reason_code": reason, "quantity": s.quantity}, id)
	sim.commit("RESOURCE_DESTROYED", [], {"resource_type_id": s.resource_type_id, "quantity": s.quantity, "reason_code": reason}, id, cause)
	return R.ok(id)

func block(s: Dictionary, reason: String) -> void:
	s.state = "BLOCKED"
	s.blocked_reason = reason
	sim.commit("SHIPMENT_BLOCKED", [change("shipments", s)], {"reason_code": reason}, s.id)

func step() -> void:
	for id in world.active_ids("shipments"):
		var s: Dictionary = world.get_shipment(id)
		if s.state != "IN_TRANSIT":
			continue
		if enabled_stockpile(s.destination_stockpile_id).is_empty():
			block(s, "DESTINATION_DISABLED")
			continue
		var remaining: int = Clock.units(world.clock().tick_duration)
		while s.current_route_index < s.route_edge_ids.size():
			var edge: Dictionary = world.get_entity("logistics_edges", s.route_edge_ids[s.current_route_index])
			if not edge.enabled or not world.get_location(edge.from_location_id).enabled or not world.get_location(edge.to_location_id).enabled:
				block(s, "ROUTE_DISABLED")
				break
			var needed: int = Clock.units(edge.travel_time_seconds) - Clock.units(s.edge_progress_seconds)
			if remaining < needed:
				s.edge_progress_seconds = (Clock.units(s.edge_progress_seconds) + remaining) / 1000000.0
				sim.commit("SHIPMENT_PROGRESS_CHANGED", [change("shipments", s)], {}, id)
				break
			remaining -= needed
			s.current_location_id = edge.to_location_id
			s.current_route_index += 1
			s.edge_progress_seconds = 0.0
			sim.commit("SHIPMENT_REACHED_LOCATION", [change("shipments", s)], {"edge_id": edge.id}, id)
			# Check the next edge even with zero remaining time: zero-cost edges finish now.
		if s.state == "IN_TRANSIT" and s.current_route_index == s.route_edge_ids.size():
			var destination: Dictionary = world.get_stockpile(s.destination_stockpile_id)
			destination.quantities[s.resource_type_id] = destination.quantities.get(s.resource_type_id, 0) + s.quantity
			s.state = "ARRIVED"
			s.arrived_at = sim.time()
			sim.commit("SHIPMENT_ARRIVED", [change("stockpiles", destination), change("shipments", s)], {"quantity": s.quantity}, id)
# 105: bind a live offer claim to cargo without releasing/re-reserving it.
# The existing dispatch path retains sole physical mutation ownership.
func dispatch_reserved(reservation_id: String, destination_id: String, actor: String) -> Dictionary:
	var r: Dictionary = world.get_entity("resource_reservations", reservation_id)
	if r.is_empty() or r.state != "ACTIVE" or r.purpose_code != "PEER_AMMO_TRANSFER_OFFER" or r.claimant_command_id != actor or world.shipment_for_reservation(reservation_id) != null:
		return R.fail("RESERVATION_MISMATCH")
	var coordination: Dictionary = world.get_entity("peer_coordinations", r.get("coordination_id", ""))
	if coordination.is_empty() or r.id not in coordination.reservation_ids or coordination.peer_command_id != actor or coordination.destination_stockpile_id != destination_id or r.resource_type_id != "AMMUNITION":
		return R.fail("RESERVATION_MISMATCH")
	if sim.context.get("source_system") != "RESOURCE_RESOLUTION":
		return R.fail("UNAUTHORIZED")
	if coordination.donor_status != "RESERVED" or not coordination.get("acceptance_message_id") is String or Clock.units(sim.time()) >= coordination.offer_expiry_micro:
		return R.fail("INVALID_STATE")
	var accepted: Dictionary = world.get_entity("messages", coordination.acceptance_message_id)
	if accepted.get("state") != "DELIVERED" or accepted.sender_command_id != coordination.requester_command_id or accepted.recipient_command_id != actor or accepted.payload.get("subtype") != "AMMO_TRANSFER_ACCEPT" or accepted.payload.get("coordination_id") != coordination.id or accepted.payload.get("quantity") != coordination.offered_quantity:
		return R.fail("INVALID_STATE")
	if not sim.authorized(actor, r.stockpile_id):
		return R.fail("UNAUTHORIZED")
	var origin := enabled_stockpile(r.stockpile_id)
	var destination := enabled_stockpile(destination_id)
	if origin.is_empty() or destination.is_empty() or origin.id == destination.id:
		return R.fail("INVALID_ENTITY")
	var route := Router.find(world, origin.location_id, destination.location_id)
	if not route.success: return route
	var id: String = sim.entity_id("shipment")
	var shipment := {"id": id, "resource_type_id": r.resource_type_id, "quantity": r.quantity, "origin_stockpile_id": origin.id, "destination_stockpile_id": destination.id, "requested_by_command_id": actor, "reservation_id": r.id, "route_edge_ids": route.details.edge_ids, "current_route_index": 0, "current_location_id": origin.location_id, "edge_progress_seconds": 0.0, "state": "PLANNED", "created_at": sim.time(), "departed_at": null, "arrived_at": null, "blocked_reason": null}
	shipment.need_id = sim.context.get("input_id")
	shipment.coordination_id = sim.context.get("coordination_id")
	var cause: String = sim.commit("SHIPMENT_CREATED", [change("shipments", shipment)], {"reservation_id": r.id, "existing_offer_reservation": true, "route": route.details}, id)
	sim.context.causation_event_id = cause
	return dispatch(id)
