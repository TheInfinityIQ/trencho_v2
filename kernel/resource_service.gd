extends "res://kernel/service.gd"

func create_stock(resource: String, stockpile_id: String, quantity: Variant) -> Dictionary:
	if not sim.privileged():
		return R.fail("UNAUTHORIZED")
	if not quantity_valid(resource, quantity):
		return R.fail("INVALID_QUANTITY")
	var s := enabled_stockpile(stockpile_id)
	if s.is_empty():
		return R.fail("INVALID_ENTITY")
	var l := ledger(resource)
	s.quantities[resource] = s.quantities.get(resource, 0) + quantity
	l.created += quantity
	sim.commit("RESOURCE_CREATED", [change("stockpiles", s), change("ledger", l)], {"resource_type_id": resource, "quantity": quantity}, stockpile_id)
	return R.ok(stockpile_id)

func reserve(stockpile_id: String, resource: String, quantity: Variant, claimant: Variant = null, purpose := "DEBUG") -> Dictionary:
	if not quantity_valid(resource, quantity):
		return R.fail("INVALID_QUANTITY")
	var s := enabled_stockpile(stockpile_id)
	if s.is_empty():
		return R.fail("INVALID_ENTITY")
	if not sim.authorized(claimant, stockpile_id):
		return R.fail("UNAUTHORIZED")
	if quantity > available(s, resource):
		return R.fail("INSUFFICIENT_AVAILABLE_STOCK")
	var id: String = sim.entity_id("reservation")
	var record := reservation(id, stockpile_id, resource, quantity, claimant, purpose)
	if sim.context.get("source_system") == "RESOURCE_RESOLUTION":
		record.need_id = sim.context.input_id
		record.coordination_id = sim.context.get("coordination_id")
	s.reserved[resource] = s.reserved.get(resource, 0) + quantity
	sim.commit("RESERVATION_CREATED", [change("stockpiles", s), change("resource_reservations", record)], {}, id)
	return R.ok(id)

func reservation(id: String, stockpile_id: String, resource: String, quantity: Variant, claimant: Variant, purpose: String) -> Dictionary:
	return {"id": id, "stockpile_id": stockpile_id, "resource_type_id": resource, "quantity": quantity, "claimant_command_id": claimant, "purpose_code": purpose, "created_at": sim.time(), "state": "ACTIVE"}

func retire(id: String, state: String) -> Dictionary:
	var r: Dictionary = world.get_entity("resource_reservations", id)
	if r.is_empty():
		return R.fail("INVALID_ENTITY")
	if not sim.authorized(r.claimant_command_id, r.stockpile_id):
		return R.fail("UNAUTHORIZED")
	if r.state != "ACTIVE":
		return R.fail("INVALID_STATE")
	if r.purpose_code == "PEER_AMMO_TRANSFER_OFFER" and r.get("coordination_id") != null:
		return R.fail("INVALID_STATE", {"reason": "OFFER_OWNS_RESERVATION"})
	# Shipment-linked claims are retired only by shipment lifecycle operations.
	if world.shipment_for_reservation(id) != null:
		return R.fail("INVALID_STATE", {"reason": "SHIPMENT_OWNS_RESERVATION"})
	var s: Dictionary = world.get_stockpile(r.stockpile_id)
	var changes: Array = []
	s.reserved[r.resource_type_id] -= r.quantity
	if state == "CONSUMED":
		s.quantities[r.resource_type_id] -= r.quantity
		var l := ledger(r.resource_type_id)
		l.consumed += r.quantity
		changes.append(change("ledger", l))
	r.state = state
	changes.append_array([change("stockpiles", s), change("resource_reservations", r)])
	var event_type := "RESERVATION_" + state
	var cause: String = sim.commit(event_type, changes, {}, id)
	if state == "CONSUMED":
		sim.commit("RESOURCE_CONSUMED", [], {"resource_type_id": r.resource_type_id, "quantity": r.quantity}, r.stockpile_id, cause)
	return R.ok(id)

func remove_stock(stockpile_id: String, resource: String, quantity: Variant, actor: Variant, reason: String, destroy := false) -> Dictionary:
	if not quantity_valid(resource, quantity):
		return R.fail("INVALID_QUANTITY")
	var s := enabled_stockpile(stockpile_id)
	if s.is_empty():
		return R.fail("INVALID_ENTITY")
	if not sim.authorized(actor, stockpile_id):
		return R.fail("UNAUTHORIZED")
	if quantity > available(s, resource):
		return R.fail("INSUFFICIENT_AVAILABLE_STOCK")
	return _remove_validated(s, resource, quantity, reason, destroy)

# Internal simulation capability: assignment permits consumption, never dispatch or allocation.
func consume_for_front(front_id: String, quantity: int) -> Dictionary:
	var front: Dictionary = world.get_front(front_id)
	if front.is_empty() or not front.enabled:
		return R.fail("INVALID_ENTITY")
	if sim.context.get("source_system") != "FRONT_SIMULATION" or sim.actor() != front_id:
		return R.fail("UNAUTHORIZED")
	if not quantity_valid("AMMUNITION", quantity):
		return R.fail("INVALID_QUANTITY")
	var s := enabled_stockpile(front.supply_stockpile_id)
	if s.is_empty():
		return R.fail("INVALID_ENTITY")
	if quantity > available(s, "AMMUNITION"):
		return R.fail("INSUFFICIENT_AVAILABLE_STOCK")
	return _remove_validated(s, "AMMUNITION", quantity, "FRONT_COMBAT_CONSUMPTION", false)

func _remove_validated(s: Dictionary, resource: String, quantity: Variant, reason: String, destroy: bool) -> Dictionary:
	s.quantities[resource] -= quantity
	var l := ledger(resource)
	var field := "destroyed" if destroy else "consumed"
	l[field] += quantity
	sim.commit("RESOURCE_DESTROYED" if destroy else "RESOURCE_CONSUMED", [change("stockpiles", s), change("ledger", l)], {"reason_code": reason, "quantity": quantity, "resource_type_id": resource}, s.id)
	return R.ok(s.id)

func audit() -> Dictionary:
	var result: Dictionary = {}
	for resource in world.ids("resource_types"):
		var l := ledger(resource)
		var stock := 0.0
		var cargo := 0.0
		var valid := true
		for id in world.ids("stockpiles"):
			var s: Dictionary = world.get_stockpile(id)
			var on_hand: float = s.quantities.get(resource, 0)
			var reserved: float = s.reserved.get(resource, 0)
			stock += on_hand
			valid = valid and reserved >= 0 and reserved <= on_hand and on_hand >= 0
		for id in world.ids("shipments"):
			var s: Dictionary = world.get_shipment(id)
			if s.resource_type_id == resource and s.state in ["IN_TRANSIT", "BLOCKED"]:
				cargo += s.quantity
		var balance: float = l.created - stock - cargo - l.consumed - l.destroyed
		result[resource] = {"created": l.created, "stockpiles": stock, "in_transit": cargo, "consumed": l.consumed, "destroyed": l.destroyed, "balance": balance, "valid": valid and absf(balance) < 0.000001}
	return result
# Expiry/cancellation maintenance for claims owned by a 105 offer, even if donor disabled.
# No public input exposes this capability; validate the coordination binding and source.
func release_peer_offer(reservation_id: String, coordination_id: String) -> Dictionary:
	var c: Dictionary = world.get_entity("peer_coordinations", coordination_id)
	var r: Dictionary = world.get_entity("resource_reservations", reservation_id)
	if sim.context.get("source_system") != "RESOURCE_RESOLUTION" or c.is_empty() or reservation_id not in c.get("reservation_ids", []) or r.is_empty() or r.purpose_code != "PEER_AMMO_TRANSFER_OFFER" or r.claimant_command_id != c.peer_command_id or sim.actor() != c.peer_command_id or r.get("coordination_id") != c.id or sim.context.get("input_id") != c.need_id:
		return R.fail("UNAUTHORIZED")
	if r.state != "ACTIVE":
		return R.fail("INVALID_STATE")
	if world.shipment_for_reservation(reservation_id) != null:
		return R.fail("INVALID_STATE")
	var stock: Dictionary = world.get_stockpile(r.stockpile_id)
	stock.reserved[r.resource_type_id] -= r.quantity
	r.state = "RELEASED"
	sim.commit("RESERVATION_RELEASED", [change("stockpiles", stock), change("resource_reservations", r)], {"coordination_id": coordination_id, "offer_maintenance": true}, r.id)
	return R.ok(r.id)
