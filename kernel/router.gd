extends RefCounted

const R = preload("res://kernel/result.gd")
const Clock = preload("res://kernel/clock.gd")

static func path_less(a: Array, b: Array) -> bool:
	for i in range(mini(a.size(), b.size())):
		if a[i] != b[i]:
			return str(a[i]) < str(b[i])
	return a.size() < b.size()

static func find(world: RefCounted, origin: String, destination: String, communication := false) -> Dictionary:
	var table := "communication_edges" if communication else "logistics_edges"
	var nodes := "commands" if communication else "locations"
	var dest_key := "to_command_id" if communication else "to_location_id"
	var time_key := "latency_seconds" if communication else "travel_time_seconds"
	var error := "NO_COMMUNICATION_ROUTE" if communication else "NO_LOGISTICS_ROUTE"
	for id in [origin, destination]:
		var node: Dictionary = world.get_entity(nodes, id)
		if node.is_empty() or not node.enabled:
			return R.fail(error)
	var queue: Array = [{"node": origin, "cost": 0, "edges": []}]
	var settled: Dictionary = {}
	while not queue.is_empty():
		queue.sort_custom(func(a, b): return a.cost < b.cost if a.cost != b.cost else path_less(a.edges, b.edges))
		var current: Dictionary = queue.pop_front()
		if settled.has(current.node):
			continue
		settled[current.node] = true
		if current.node == destination:
			return R.ok(null, {"origin_location_id": origin, "destination_location_id": destination, "edge_ids": current.edges, "total_travel_time": current.cost / 1000000.0})
		var edges: Array = world.get_communication_edges(current.node) if communication else world.get_outgoing_logistics_edges(current.node)
		for id in edges:
			var edge: Dictionary = world.get_entity(table, id)
			var target: Dictionary = world.get_entity(nodes, edge[dest_key])
			if not edge.enabled or target.is_empty() or not target.enabled or settled.has(edge[dest_key]):
				continue
			var path: Array = current.edges.duplicate()
			path.append(id)
			queue.append({"node": edge[dest_key], "cost": current.cost + Clock.units(edge[time_key]), "edges": path})
	return R.fail(error)
