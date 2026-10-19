extends RefCounted
# Narrow definition-time support for107's already-dispatched environmental cargo.
# No runtime dispatch/input or active reservation is fabricated.
static func load_into(state: Dictionary, definitions: Variant, used: Dictionary) -> bool:
	if not definitions is Array: return false
	for source in definitions:
		if not source is Dictionary or not source.get("id") is String or source.id.is_empty() or ":" in source.id or used.has(source.id): return false
		for key in ["origin_stockpile_id", "destination_stockpile_id", "resource_type_id"]:
			if not source.get(key) is String: return false
		var origin: Dictionary = state.stockpiles.get(source.origin_stockpile_id, {})
		var destination: Dictionary = state.stockpiles.get(source.destination_stockpile_id, {})
		var resource: Dictionary = state.resource_types.get(source.resource_type_id, {})
		var quantity: Variant = source.get("quantity")
		if origin.is_empty() or destination.is_empty() or origin.id == destination.id or resource.is_empty() or not origin.enabled or not destination.enabled: return false
		if not state.locations[origin.location_id].enabled: return false
		if not quantity is int and not quantity is float: return false
		if not is_finite(float(quantity)) or quantity <= 0 or quantity > 9007199254740991 or (not resource.allow_fractional_quantity and quantity != floor(quantity)): return false
		var route: Variant = source.get("route_edge_ids")
		if not route is Array or route.is_empty(): return false
		var location: String = origin.location_id
		var visited: Dictionary = {location: true}
		for edge_id in route:
			if not edge_id is String: return false
			var edge: Dictionary = state.logistics_edges.get(edge_id, {})
			if edge.is_empty() or not edge.enabled or edge.from_location_id != location or visited.has(edge.to_location_id): return false
			location = edge.to_location_id
			if not state.locations[location].enabled: return false
			visited[location] = true
		if location != destination.location_id: return false
		var requester: Variant = source.get("requested_by_command_id")
		if requester != null and not state.commands.has(requester): return false
		state.shipments[source.id] = {"id": source.id, "resource_type_id": resource.id, "quantity": quantity, "origin_stockpile_id": origin.id, "destination_stockpile_id": destination.id, "requested_by_command_id": requester, "reservation_id": null, "route_edge_ids": route.duplicate(), "current_route_index": 0, "current_location_id": origin.location_id, "edge_progress_seconds": 0.0, "state": "IN_TRANSIT", "created_at": 0.0, "departed_at": 0.0, "arrived_at": null, "blocked_reason": null, "initial_environmental_cargo": true}
		state.ledger[resource.id].created += quantity
		used[source.id] = true
	return true
