extends RefCounted
const Simulation = preload("res://kernel/simulation.gd")
const Demo = preload("res://debug/resource_resolution_demo.gd")
const Decisions = preload("res://tests/decision_cases.gd")
const Policy = preload("res://kernel/resource_need_policy.gd")
const Resolution = preload("res://kernel/resource_resolution_service.gd")
const Exporter = preload("res://kernel/run_exporter.gd")
const World = preload("res://kernel/world_state.gd")
const Resources = preload("res://kernel/resource_service.gd")
const Logistics = preload("res://kernel/logistics_service.gd")

static func check(checks: Array, condition: bool, name: String) -> void:
	checks.append({"name": "105 / " + name, "passed": condition})

static func fresh(data: Variant = "B") -> RefCounted:
	var sim := Simulation.new()
	var result: Dictionary = sim.initialize(Demo.definition(data) if data is String else data, 105, "need-tests")
	assert(result.success, JSON.stringify(result))
	return sim

static func rows(sim: RefCounted, table: String) -> Array:
	return sim.world.ids(table).map(func(id): return sim.world.get_entity(table, id))

static func events(sim: RefCounted, type: String) -> Array:
	return sim.events.all().filter(func(e): return e.event_type == type)

static func first_need(sim: RefCounted, command := "LOCAL_A") -> Dictionary:
	var needs := rows(sim, "resource_needs").filter(func(n): return n.command_id == command)
	return {} if needs.is_empty() else needs.back()

static func edge(sim: RefCounted, id: String, enabled: bool, table := "communication_edges") -> void:
	assert(sim.execute({"type": "SetEnabled", "table": table, "entity_id": id, "enabled": enabled}, true).success)

static func evaluate_need(sim: RefCounted, data: Dictionary, complete := true, observed := 0, expiry: Variant = null) -> Dictionary:
	var ids: Dictionary = Decisions.inject(sim, data, "LOCAL_A", observed, expiry)
	var evaluated: Dictionary = Decisions.evaluate(sim, ids, complete, observed)
	var decision: Dictionary = sim.world.get_entity("decisions", evaluated.entity_id)
	return sim.execute({"type": "EvaluateResourceNeed", "observation_batch_id": decision.observation_batch_id}, true)

static func scarce_values() -> Dictionary:
	var values := Decisions.values()
	values.FRONT_AMMO_AVAILABLE = 0
	values.FRONT_AMMO_ON_HAND = 0
	values.FRONT_AMMO_COVERAGE_MILLISECONDS = 0
	values.FRONT_LAST_SHORTAGE = 2
	values.FRONT_INTERVAL_CONSUMED = 2
	return values

static func conserved_prefixes(sim: RefCounted) -> bool:
	var projection := World.new(sim.initial_world)
	for event in sim.events.all():
		projection.apply_event(event)
		var state: Dictionary = projection.snapshot()
		var physical := 0
		for stock in state.stockpiles.values():
			var quantity := int(stock.quantities.get("AMMUNITION", 0))
			var reserved := int(stock.reserved.get("AMMUNITION", 0))
			if reserved < 0 or reserved > quantity: return false
			physical += quantity
			var active_claims := 0
			for claim in state.resource_reservations.values():
				if claim.stockpile_id == stock.id and claim.resource_type_id == "AMMUNITION" and claim.state == "ACTIVE": active_claims += int(claim.quantity)
			if active_claims != reserved: return false
		for shipment in state.shipments.values():
			if shipment.state in ["IN_TRANSIT", "BLOCKED"]: physical += int(shipment.quantity)
		if state.ledger.AMMUNITION.created != physical + state.ledger.AMMUNITION.consumed + state.ledger.AMMUNITION.destroyed: return false
	return Exporter.equivalent(projection.snapshot(), sim.snapshot())

static func run() -> Dictionary:
	var checks: Array = []
	var summaries: Dictionary = {}
	_scenarios(checks, summaries)
	_need_policy(checks)
	_local_and_lifecycle(checks)
	_peer_reservations(checks)
	_failures(checks)
	_privacy_and_protocol(checks)
	var failures: Array = []
	for item in checks:
		if not item.passed: failures.append(item.name)
	return {"success": failures.is_empty(), "checks": checks, "failures": failures, "scenarios": summaries}

static func _scenarios(checks: Array, summaries: Dictionary) -> void:
	for scenario in ["A", "B", "C", "D", "E"]:
		var completed := Demo.run(scenario)
		check(checks, completed.success, "scenario " + scenario + " runs")
		if not completed.success: continue
		var sim: RefCounted = completed.details.simulation
		var needs := rows(sim, "resource_needs")
		var coords := rows(sim, "peer_coordinations")
		check(checks, not needs.is_empty(), "scenario " + scenario + " opens need")
		check(checks, conserved_prefixes(sim), "scenario " + scenario + " every event prefix and reconstruction conserve all claims/stock/cargo")
		check(checks, Exporter.export_run(sim, "res://artifacts/run_step105_" + scenario).success and Exporter.replay_package("res://artifacts/run_step105_" + scenario).success, "scenario " + scenario + " exact file replay")
		check(checks, sim.world.get_stockpile("HQ_STOCK").quantities.AMMUNITION == 1000, "scenario " + scenario + " superior stock never allocated")
		check(checks, events(sim, "RESOURCE_CREATED").size() == (1 if scenario == "D" else 0), "scenario " + scenario + " creates no automatic ammunition")
		if scenario in ["A", "B", "D"]:
			check(checks, first_need(sim).state == "RESOLVED" and first_need(sim).confirmed_incoming_quantity == 0, "scenario " + scenario + " physical observed refill resolves")
		if scenario == "A":
			check(checks, coords.is_empty() and events(sim, "RESOURCE_NEED_ESCALATED").is_empty() and events(sim, "LOCAL_RESOURCE_TRANSFER_DISPATCHED").size() == 1, "local self-help excludes peer and escalation")
		if scenario == "B":
			check(checks, coords.size() == 1 and coords[0].offered_quantity == 80 and coords[0].requester_status == "DONE" and coords[0].donor_status == "DISPATCHED", "peer request offer acceptance dispatch completes")
			check(checks, coords[0].reservation_ids.all(func(id): return sim.world.get_entity("resource_reservations", id).state == "FULFILLED") and events(sim, "RESOURCE_NEED_ESCALATED").is_empty(), "peer claim fulfilled into cargo without escalation")
		if scenario == "C":
			check(checks, events(sim, "PEER_TRANSFER_DECLINED")[0].payload.reason_code == "INSUFFICIENT_SPARE_STOCK" and events(sim, "RESOURCE_NEED_ESCALATED").size() == 1 and first_need(sim).state == "ACTIVE", "protected peer declines and unresolved need escalates once")
			var facts: Array = sim.command_view("ARMY_COMMAND").information()
			check(checks, facts.size() == 4 and facts.all(func(f): return f.source_command_id == "LOCAL_A" and f.source_message_id != null and f.confidence == 1 and f.subject_entity_id == first_need(sim).id), "superior knows only four reported need facts with sender/message provenance")
			check(checks, facts.filter(func(f): return f.fact_key == "SUBORDINATE_AMMO_NEED_QUANTITY")[0].value == 80 and first_need(sim).uncovered_need_quantity == 40, "escalation remains timestamped snapshot rather than live omniscience")
		if scenario == "D":
			check(checks, coords[0].state == "CANCELLED" and coords[0].shipment_ids.is_empty() and coords[0].reservation_ids.all(func(id): return sim.world.get_entity("resource_reservations", id).state == "RELEASED"), "changed need cancels offer and releases claim without double allocation")
		if scenario == "E":
			var offers := coords.filter(func(c): return c.offered_quantity > 0)
			check(checks, offers.size() == 1 and offers[0].offered_quantity == 74 and offers[0].reservation_ids.all(func(id): return sim.world.get_entity("resource_reservations", id).state == "ACTIVE"), "competing requests cannot reserve same donor ammunition")
			check(checks, coords.filter(func(c): return c.peer_command_id == "LOCAL_B" and c.requester_command_id == "LOCAL_C" and c.state == "DECLINED").size() == 1, "second requester cannot receive first offer's promised stock")
		summaries[scenario] = {"need_ids": needs.map(func(n): return n.id), "need_states": needs.map(func(n): return n.state), "coordination_ids": coords.map(func(c): return c.id), "offers": coords.map(func(c): return c.offered_quantity), "event_count": sim.events.count(), "end_tick": sim.world.clock().tick_index, "ledger": sim.audit()}
	var a: Dictionary = Demo.run("B")
	var b: Dictionary = Demo.run("B")
	check(checks, Exporter.equivalent(a.details.simulation.snapshot(), b.details.simulation.snapshot()) and Exporter.equivalent(a.details.simulation.events.all(), b.details.simulation.events.all()), "independent coordination runs reproduce exact event stream")

static func _need_policy(checks: Array) -> void:
	var sim := fresh()
	var values := scarce_values()
	values.FRONT_AMMO_DEMAND_RATE = 1001
	values.FRONT_INTERVAL_DEMAND = 1
	values.FRONT_INTERVAL_CONSUMED = 1
	values.FRONT_LAST_SHORTAGE = 0
	evaluate_need(sim, values)
	check(checks, first_need(sim).target_stock_quantity == 21 and first_need(sim).planning_rate_milli == 1001, "exact ceil 20-second target without float")
	sim = fresh()
	values = scarce_values()
	values.FRONT_AMMO_DEMAND_RATE = 0
	values.FRONT_AMMO_COVERAGE_MILLISECONDS = null
	values.FRONT_AMMO_COVERAGE_STATUS = "ZERO_DEMAND"
	evaluate_need(sim, values)
	check(checks, first_need(sim).planning_rate_milli == 4000 and first_need(sim).target_stock_quantity == 80 and first_need(sim).urgency == "CRITICAL", "recent demand fallback survives zero instantaneous burn")
	for variant in ["secure", "zero", "partial", "missing", "bad-interval"]:
		sim = fresh()
		values = Decisions.values() if variant == "secure" else scarce_values()
		if variant == "zero":
			values.FRONT_AMMO_DEMAND_RATE = 0
			values.FRONT_INTERVAL_DEMAND = 0
			values.FRONT_INTERVAL_CONSUMED = 0
			values.FRONT_LAST_SHORTAGE = 0
			values.FRONT_AMMO_COVERAGE_STATUS = "ZERO_DEMAND"
			values.FRONT_AMMO_COVERAGE_MILLISECONDS = null
		if variant == "missing": values.erase("FRONT_AMMO_AVAILABLE")
		if variant == "bad-interval": values.FRONT_INTERVAL_CONSUMED = 99
		var result := evaluate_need(sim, values, variant != "partial")
		check(checks, rows(sim, "resource_needs").is_empty() and (result.success if variant in ["secure", "zero"] else not result.success), "need does not open from " + variant + " sample")
	for expired in [false, true]:
		sim = fresh()
		values = scarce_values()
		var ids: Dictionary = Decisions.inject(sim, values, "LOCAL_A", 0, 0.5 if expired else null)
		var evaluated: Dictionary = Decisions.evaluate(sim, ids)
		var batch_id: String = sim.world.get_entity("decisions", evaluated.entity_id).observation_batch_id
		sim.execute({"type": "SetFrontEnabled", "front_id": "FRONT_A", "value": false}, true)
		sim.advance(6 if expired else 16)
		check(checks, not sim.execute({"type": "EvaluateResourceNeed", "observation_batch_id": batch_id}, true).success and rows(sim, "resource_needs").is_empty(), "expired/stale need information has no world fallback " + str(expired))
	sim = fresh("C")
	sim.advance(10)
	var original: Dictionary = first_need(sim)
	sim.advance(10)
	var lower: Dictionary = first_need(sim)
	sim.execute({"type": "SetFrontEnemyPressure", "front_id": "FRONT_A", "value": 100}, true)
	sim.advance(10)
	check(checks, original.id == first_need(sim).id and original.target_stock_quantity == 80 and lower.target_stock_quantity == 40 and first_need(sim).target_stock_quantity == 80 and lower.revision > original.revision and first_need(sim).revision > lower.revision, "need quantity dynamically decreases/increases with monotonic material revisions")
	sim = fresh()
	sim.advance(10)
	var need: Dictionary = first_need(sim)
	sim.advance()
	var before := first_need(sim)
	sim.execute({"type": "EvaluateResourceNeed", "observation_batch_id": before.based_on_observation_batch_id}, true)
	check(checks, first_need(sim).revision == before.revision and first_need(sim).last_evaluated_at_micro > need.last_evaluated_at_micro, "time/provenance-only reevaluation does not increment revision")

static func _local_and_lifecycle(checks: Array) -> void:
	var sim := fresh("A")
	sim.advance(10)
	var need: Dictionary = first_need(sim)
	check(checks, need.state == "ACTIVE" and need.condition == "COVERED_IN_TRANSIT" and need.confirmed_incoming_quantity == 80 and need.available_quantity == 0 and sim.front_metrics("FRONT_A").current_ammo_on_hand == 0, "known local incoming covers sourcing but is not physical stock or resolved")
	sim.advance(4)
	check(checks, rows(sim, "peer_coordinations").is_empty() and events(sim, "RESOURCE_NEED_ESCALATED").is_empty(), "covered transit suppresses peer and escalation")
	sim.advance()
	check(checks, first_need(sim).state == "ACTIVE" and first_need(sim).confirmed_incoming_quantity == 0 and sim.front_metrics("FRONT_A").current_ammo_on_hand > 0, "arrival removes incoming without prematurely resolving")
	sim.advance(5)
	check(checks, first_need(sim).state == "RESOLVED" and first_need(sim).available_quantity >= first_need(sim).target_stock_quantity, "next shortage-free complete physical observation resolves")
	var old_id: String = first_need(sim).id
	sim.execute({"type": "DestroyResource", "stockpile_id": "A_STOCK", "resource_type_id": "AMMUNITION", "quantity": sim.front_metrics("FRONT_A").current_available_ammo, "reason_code": "TEST_NEW_SHORTAGE"}, true)
	sim.advance(10)
	check(checks, rows(sim, "resource_needs").filter(func(n): return n.command_id == "LOCAL_A").size() == 2 and first_need(sim).id != old_id and sim.world.get_entity("resource_needs", old_id).state == "RESOLVED", "later shortage creates new ID and never resurrects resolved need")
	sim = fresh("B")
	sim.advance(20)
	check(checks, first_need(sim).state == "ACTIVE" and first_need(sim).available_quantity >= first_need(sim).target_stock_quantity and first_need(sim).last_shortage > 0, "recent shortage prevents closure despite observed physical refill")
	sim.advance(10)
	check(checks, first_need(sim).state == "RESOLVED", "later shortage-free interval closes same need")
	var data: Dictionary = Demo.definition("A")
	data.stockpiles.back().quantities.AMMUNITION = 8
	sim = fresh(data)
	sim.advance(10)
	check(checks, first_need(sim).confirmed_incoming_quantity == 8 and first_need(sim).uncovered_need_quantity == 72 and rows(sim, "peer_coordinations")[0].requested_quantity == 72, "partial self-help coordinates remainder without waiting for arrival")
	var local_event: Dictionary = events(sim, "LOCAL_RESOURCE_TRANSFER_DISPATCHED")[0]
	check(checks, local_event.event_id < events(sim, "PEER_COORDINATION_STARTED")[0].event_id, "local dispatch precedes peer conversation")
	data = Demo.definition("A")
	data.logistics_edges.erase(data.logistics_edges.back())
	data.stockpiles.append({"id": "A_RESERVE_Z", "location_id": "DEPOT_A", "owner_command_id": "LOCAL_A", "quantities": {"AMMUNITION": 100}})
	data.commands[1].directly_controlled_stockpile_ids.append("A_RESERVE_Z")
	sim = fresh(data)
	sim.advance(10)
	check(checks, events(sim, "LOCAL_RESOURCE_TRANSFER_DISPATCHED").size() == 1 and sim.world.get_shipment(events(sim, "LOCAL_RESOURCE_TRANSFER_DISPATCHED")[0].payload.shipment_id).origin_stockpile_id == "A_RESERVE_Z", "unroutable first local source is skipped for next deterministic source")
	check(checks, sim.world.get_stockpile("A_RESERVE").quantities.AMMUNITION == 100, "unroutable local stock is unchanged")

	data = Demo.definition("A")
	data.fronts.append({"id": "OTHER_ACTIVE_FRONT", "location_id": "RESERVE_SITE", "responsible_command_id": "LOCAL_A", "supply_stockpile_id": "A_RESERVE", "friendly_strength": 50, "enemy_pressure": 0, "posture": "HOLD", "base_ammo_demand_per_second": 0})
	sim = fresh(data)
	sim.advance(10)
	check(checks, events(sim, "LOCAL_RESOURCE_TRANSFER_DISPATCHED").is_empty() and sim.world.get_stockpile("A_RESERVE").quantities.AMMUNITION == 100, "self-help excludes stock serving another active front")
static func _peer_reservations(checks: Array) -> void:
	var sim := fresh("B")
	sim.advance(11)
	var c: Dictionary = rows(sim, "peer_coordinations")[0]
	check(checks, c.offered_quantity == 80 and c.peer_protected_stock == 80 and sim.world.get_stockpile("B_STOCK").reserved.AMMUNITION == 80, "offer reserves physical stock and protects exact donor target")
	check(checks, first_need(sim).confirmed_incoming_quantity == 0, "offer is not confirmed incoming")
	check(checks, not Logistics.new(sim).dispatch_reserved(c.reservation_ids[0], "A_STOCK", "LOCAL_B").success and sim.world.get_entity("resource_reservations", c.reservation_ids[0]).state == "ACTIVE", "unscoped caller cannot dispatch an owned donor claim")
	check(checks, not sim.execute({"type": "ReleaseReservation", "reservation_id": c.reservation_ids[0]}, true).success and not Resources.new(sim).release_peer_offer(c.reservation_ids[0], c.id).success, "offer claims cannot be stolen by generic retirement or unscoped maintenance")
	sim.advance()
	check(checks, first_need(sim).confirmed_incoming_quantity == 0 and rows(sim, "peer_coordinations")[0].requester_status == "WAIT_DISPATCH", "acceptance alone is not incoming")
	sim.advance()
	check(checks, first_need(sim).confirmed_incoming_quantity == 0 and rows(sim, "shipments").size() == 1, "actual dispatch remains unknown until notice delivery")
	var shipment: Dictionary = rows(sim, "shipments")[0]
	check(checks, shipment.reservation_id == c.reservation_ids[0] and sim.world.get_entity("resource_reservations", shipment.reservation_id).state == "FULFILLED" and events(sim, "RESERVATION_CREATED").size() == 1, "offer reservation becomes cargo without release/re-reserve window")
	check(checks, not Logistics.new(sim).dispatch_reserved(shipment.reservation_id, "A_STOCK", "LOCAL_B").success, "accepted claim cannot dispatch twice")
	sim.advance()
	check(checks, first_need(sim).confirmed_incoming_quantity == 80 and first_need(sim).condition == "COVERED_IN_TRANSIT" and rows(sim, "known_transfers")[0].source_message_id != null, "only delivered dispatch notice confirms peer incoming")
	var data: Dictionary = Demo.definition("B")
	data.stockpiles[2].quantities.AMMUNITION = 84
	for entry in [["B_FREE_A", 30], ["B_FREE_Z", 60]]:
		data.stockpiles.append({"id": entry[0], "location_id": "DEPOT_B", "owner_command_id": "LOCAL_B", "quantities": {"AMMUNITION": entry[1]}})
		data.commands[2].directly_controlled_stockpile_ids.append(entry[0])
	sim = fresh(data)
	sim.advance(14)
	c = rows(sim, "peer_coordinations")[0]
	check(checks, c.allocations.size() == 2 and c.allocations[0].stockpile_id == "B_FREE_A" and c.allocations[0].quantity == 30 and c.allocations[1].stockpile_id == "B_FREE_Z" and c.allocations[1].quantity == 50, "donor non-front sources precede protected front spare in sorted order")
	check(checks, c.shipment_ids.size() == 2 and first_need(sim).confirmed_incoming_quantity == 80 and first_need(sim).active_coordination_id == null and conserved_prefixes(sim), "multi-source offer dispatches all existing claims without partial-notice double sourcing")

static func _failures(checks: Array) -> void:
	for destroy in [false, true]:
		var sim := fresh("B")
		sim.advance(14)
		var id: String = first_need(sim).id
		var shipment: Dictionary = rows(sim, "shipments")[0]
		if destroy:
			sim.execute({"type": "DestroyShipment", "shipment_id": shipment.id, "reason_code": "TEST_FAILURE"}, true)
		else: edge(sim, "b_to_a", false, "logistics_edges")
		sim.advance()
		check(checks, first_need(sim).id == id and first_need(sim).condition == "SEEKING_SUPPLY" and first_need(sim).confirmed_incoming_quantity == 0 and first_need(sim).uncovered_need_quantity > 0, "known blocked/destroyed incoming resumes same need " + str(destroy))
		check(checks, events(sim, "KNOWN_TRANSFER_STATUS_CHANGED").size() == 1 and rows(sim, "known_transfers")[0].command_id == "LOCAL_A" and conserved_prefixes(sim), "scoped failure notification and conservation " + str(destroy))
		var package := "res://artifacts/run_step105_known_" + ("destroyed" if destroy else "blocked")
		check(checks, Exporter.export_run(sim, package).success and Exporter.replay_package(package).success, "known shipment failure replay " + str(destroy))
	for disable_donor in [false, true]:
		var sim := fresh("B")
		sim.advance(11)
		var c: Dictionary = rows(sim, "peer_coordinations")[0]
		if disable_donor:
			sim.execute({"type": "SetEnabled", "table": "commands", "entity_id": "LOCAL_B", "enabled": false}, true)
		else: edge(sim, "a_b", false)
		sim.advance(12)
		check(checks, c.reservation_ids.all(func(id): return sim.world.get_entity("resource_reservations", id).state == "RELEASED") and events(sim, "PEER_TRANSFER_OFFER_EXPIRED").size() == 1, "abandoned offer expiry releases stock even disabled donor " + str(disable_donor))
		check(checks, sim.world.get_stockpile("B_STOCK").reserved.AMMUNITION == 0 and conserved_prefixes(sim), "expiry preserves every resource prefix " + str(disable_donor))
		var package := "res://artifacts/run_step105_expiry_" + ("disabled" if disable_donor else "normal")
		check(checks, Exporter.export_run(sim, package).success and Exporter.replay_package(package).success, "offer expiry replay " + str(disable_donor))
	var sim := fresh("B")
	sim.advance(12)
	edge(sim, "b_to_a", false, "logistics_edges")
	sim.advance(3)
	check(checks, rows(sim, "shipments").is_empty() and events(sim, "PEER_TRANSFER_DECLINED").any(func(e): return e.payload.reason_code == "NO_LOGISTICS_ROUTE") and sim.world.get_stockpile("B_STOCK").reserved.AMMUNITION == 0, "acceptance revalidates route and releases failed offer")
	sim = fresh("B")
	sim.advance(10)
	edge(sim, "a_b", false)
	sim.advance()
	check(checks, rows(sim, "peer_coordinations")[0].requester_status == "DONE" and rows(sim, "peer_coordinations")[0].reason_code == "MESSAGE_FAILED" and sim.world.clock().simulation_time_seconds < 3, "explicit request-message failure advances before timeout")
	var data: Dictionary = Demo.definition("C")
	data.commands[1].superior_command_id = null
	sim = fresh(data)
	sim.advance(10)
	check(checks, first_need(sim).escalation_status == "NO_SUPERIOR" and rows(sim, "messages").is_empty(), "missing superior does not bypass hierarchy")
	data = Demo.definition("C")
	data.communication_edges = data.communication_edges.filter(func(e): return not e.id in ["a_army", "army_a"])
	sim = fresh(data)
	sim.advance(20)
	check(checks, first_need(sim).escalation_status == "NO_COMMUNICATION_ROUTE" and sim.command_view("ARMY_COMMAND").information().is_empty(), "unreachable superior receives no teleported knowledge")
	sim = fresh("C")
	sim.advance(13)
	check(checks, sim.command_view("ARMY_COMMAND").information().is_empty(), "superior does not learn before escalation delivery")
	edge(sim, "a_army", false)
	sim.advance()
	check(checks, sim.command_view("ARMY_COMMAND").information().is_empty() and events(sim, "RESOURCE_NEED_ESCALATION_FAILED").any(func(e): return e.payload.reason_code == "MESSAGE_FAILED"), "in-transit escalation failure is journaled without superior facts")
	data = Demo.definition("B")
	data.communication_edges[0].latency_seconds = 2.0
	data.communication_edges[1].latency_seconds = 2.0
	sim = fresh(data)
	sim.advance(25)
	var c: Dictionary = rows(sim, "peer_coordinations")[0]
	check(checks, rows(sim, "peer_coordinations").size() == 1 and c.deadline_micro == 6000000 and events(sim, "MESSAGE_SENT").filter(func(e): return e.payload.changes[0].value.payload.get("subtype") == "AMMO_TRANSFER_REQUEST").size() == 1, "outstanding request suppresses per-observation spam and uses exact RTT deadline")
	check(checks, not Resolution.response_timed_out(c, 5999999) and Resolution.response_timed_out(c, 6000000), "timeout uses simulation deadline boundary exactly")

	data = Demo.definition("B")
	data.communication_edges = data.communication_edges.filter(func(e): return e.id != "b_a")
	sim = fresh(data)
	sim.advance(10)
	check(checks, rows(sim, "peer_coordinations").is_empty() and events(sim, "RESOURCE_NEED_ESCALATED").size() == 1, "peer discovery requires both communication directions")
	sim = fresh("B")
	sim.advance(10)
	edge(sim, "b_a", false)
	sim.advance()
	check(checks, events(sim, "PEER_TRANSFER_DECLINED").any(func(e): return e.payload.reason_code == "NO_RETURN_COMMUNICATION_ROUTE") and rows(sim, "resource_reservations").is_empty(), "lost return route prevents offer reservation")
	data = Demo.definition("B")
	data.logistics_edges = []
	sim = fresh(data)
	sim.advance(15)
	check(checks, events(sim, "PEER_TRANSFER_DECLINED").any(func(e): return e.payload.reason_code == "NO_LOGISTICS_ROUTE") and rows(sim, "resource_reservations").is_empty(), "no donor logistics route produces structured decline")
static func _privacy_and_protocol(checks: Array) -> void:
	var data: Dictionary = Demo.definition("B")
	data.stockpiles[1].quantities.AMMUNITION = 2000
	var sim := fresh(data)
	evaluate_need(sim, scarce_values())
	check(checks, first_need(sim).available_quantity == 0 and first_need(sim).gross_need_quantity == 80 and sim.front_metrics("FRONT_A").current_available_ammo == 2000, "need arithmetic follows private belief rather than conflicting raw front stock")
	data = Demo.definition("B")
	data.fronts[1].enabled = false
	sim = fresh(data)
	sim.advance(15)
	check(checks, events(sim, "PEER_TRANSFER_DECLINED").any(func(e): return e.payload.reason_code == "STALE_OR_INCOMPLETE_LOCAL_INFORMATION") and rows(sim, "resource_reservations").is_empty(), "peer abstains with missing own front information despite abundant raw stock")
	data = Demo.definition("B")
	data.logistics_edges.append({"id": "hidden_hq_a", "from_location_id": "ARMY_HQ", "to_location_id": "DEPOT_A", "travel_time_seconds": 2})
	sim = fresh(data)
	var shipment: Dictionary = sim.execute({"type": "CreateShipment", "origin_stockpile_id": "HQ_STOCK", "destination_stockpile_id": "A_STOCK", "resource_type_id": "AMMUNITION", "quantity": 100}, true)
	sim.execute({"type": "DispatchShipment", "shipment_id": shipment.entity_id}, true)
	sim.advance(10)
	check(checks, first_need(sim).confirmed_incoming_quantity == 0 and rows(sim, "known_transfers").is_empty(), "unreported global shipment is not speculative incoming")
	check(checks, sim.command_view("LOCAL_A").local_stockpile("HQ_STOCK").is_empty() and sim.command_view("LOCAL_A").local_stockpile("B_STOCK").is_empty(), "resolution view exposes no foreign resource inventory")
	var completed: Dictionary = Demo.run("B")
	sim = completed.details.simulation
	var c: Dictionary = rows(sim, "peer_coordinations")[0]
	var related: Array = sim.events.all().filter(func(e): return e.payload.get("coordination_id") == c.id)
	check(checks, not related.is_empty() and related.all(func(e): return e.correlation_id == c.need_id), "negotiation reservation/message/shipment events retain coordination and high-level need correlation")
	check(checks, events(sim, "PEER_TRANSFER_OFFERED")[0].payload.changes[0].value.peer_belief_record_ids.size() == 11, "donor protected target cites its own complete beliefs")
	check(checks, sim.events.all().filter(func(e): return e.event_type.begins_with("RESOURCE_NEED_") or e.event_type.begins_with("PEER_") or e.event_type == "LOCAL_RESOURCE_TRANSFER_DISPATCHED").all(func(e): return e.payload.changes.all(func(p): return p.table not in ["stockpiles", "ledger", "shipments"])), "need/coordination semantics never duplicate physical resource mutation")
	sim = fresh("B")
	var malformed := {"subtype": "AMMO_NEED_ESCALATION", "need_id": "need:invalid", "need_revision": 1.5, "requesting_command_id": "LOCAL_A", "resource_type_id": "AMMUNITION", "uncovered_need_quantity": "bad", "urgency": "CRITICAL", "front_id": "FRONT_A", "observed_at_micro": 0}
	sim.execute({"type": "SendMessage", "sender_command_id": "LOCAL_A", "recipient_command_id": "ARMY_COMMAND", "message_type": "ESCALATION", "payload": malformed}, true)
	sim.advance(3)
	check(checks, sim.command_view("ARMY_COMMAND").information().is_empty(), "malformed escalation cannot create superior need beliefs")
	malformed.need_revision = 1
	malformed.uncovered_need_quantity = 80
	malformed.observed_at_micro = 300000
	sim.execute({"type": "SendMessage", "sender_command_id": "LOCAL_A", "recipient_command_id": "LOCAL_B", "message_type": "ESCALATION", "payload": malformed}, true)
	sim.advance()
	check(checks, sim.command_view("LOCAL_B").information().is_empty(), "escalation cannot inject need beliefs into a non-superior")
	var result: Dictionary = Demo.run("E")
	sim = result.details.simulation
	var attempted: Array = rows(sim, "peer_coordinations").filter(func(coord): return coord.requester_command_id == "LOCAL_C").map(func(coord): return coord.peer_command_id)
	check(checks, attempted == ["LOCAL_A", "LOCAL_B"], "peer attempts are sequential sorted IDs without repeats")
	check(checks, sim.command_view("LOCAL_A").information().all(func(record): return record.subject_entity_id != "FRONT_B") and sim.command_view("LOCAL_B").information().all(func(record): return record.subject_entity_id != "FRONT_A"), "coordination never leaks another command's front observations")
	check(checks, not sim.execute({"type": "EvaluateResourceNeed", "observation_batch_id": first_need(sim).based_on_observation_batch_id}, false).success, "explicit need evaluation diagnostic is privileged")
	sim = fresh("B")
	sim.execute({"type": "SendMessage", "sender_command_id": "LOCAL_A", "recipient_command_id": "ARMY_COMMAND", "message_type": "REPORT", "payload": {"need_id": "coincidental-metadata", "facts": [{"subject_entity_id": "FRONT_A", "fact_key": "MARKER", "value": 1, "observed_at": 0, "confidence": 1}]}}, true)
	sim.advance(2)
	var sent: Dictionary = events(sim, "MESSAGE_SENT")[0]
	var delivered: Dictionary = events(sim, "MESSAGE_DELIVERED")[0]
	check(checks, sent.correlation_id == delivered.correlation_id and delivered.correlation_id == events(sim, "INFORMATION_INGESTED")[0].correlation_id and delivered.correlation_id != "coincidental-metadata", "generic REPORT correlation is unchanged by coincidental need metadata")
	sim = fresh("B")
	var report := {"subtype": "AMMO_NEED_ESCALATION", "need_id": "need:revision-test", "need_revision": 2, "requesting_command_id": "LOCAL_A", "resource_type_id": "AMMUNITION", "uncovered_need_quantity": 20, "urgency": "CRITICAL", "front_id": "FRONT_A", "observed_at_micro": 0}
	sim.execute({"type": "SendMessage", "sender_command_id": "LOCAL_A", "recipient_command_id": "ARMY_COMMAND", "message_type": "ESCALATION", "payload": report}, true)
	sim.advance(3)
	report.need_revision = 1
	report.uncovered_need_quantity = 80
	sim.execute({"type": "SendMessage", "sender_command_id": "LOCAL_A", "recipient_command_id": "ARMY_COMMAND", "message_type": "ESCALATION", "payload": report}, true)
	sim.advance(2)
	check(checks, sim.command_view("ARMY_COMMAND").current_belief("need:revision-test", "SUBORDINATE_AMMO_NEED_QUANTITY", sim.time()).value == 20 and events(sim, "RESOURCE_NEED_STALE_ESCALATION_IGNORED").size() == 1, "late stale escalation revision cannot overwrite newer reported need")
	var first_run: Dictionary = Demo.run("B")
	data = Demo.definition("B")
	data.commands.reverse()
	data.stockpiles.reverse()
	data.fronts.reverse()
	sim = fresh(data)
	sim.advance(40)
	sim.execute({"type": "EndRun"}, true)
	check(checks, Exporter.equivalent(first_run.details.simulation.events.all(), sim.events.all()), "declaration order cannot change deterministic peer/resource resolution")
	sim = fresh("B")
	var unbound: Dictionary = sim.execute({"type": "ReserveResource", "stockpile_id": "HQ_STOCK", "resource_type_id": "AMMUNITION", "quantity": 1, "purpose_code": "PEER_AMMO_TRANSFER_OFFER"}, true)
	check(checks, unbound.success and sim.execute({"type": "ReleaseReservation", "reservation_id": unbound.entity_id}, true).success, "generic purpose text alone never locks an unbound 2A reservation")
	var causal_run: Dictionary = Demo.run("D")
	sim = causal_run.details.simulation
	var by_id: Dictionary = {}
	for event in sim.events.all(): by_id[event.event_id] = event
	check(checks, events(sim, "RESERVATION_RELEASED").all(func(e): return by_id[e.causation_event_id].event_type == "MESSAGE_DELIVERED"), "offer cancellation release is caused by delivered cancellation")
	causal_run = Demo.run("B")
	sim = causal_run.details.simulation
	by_id = {}
	for event in sim.events.all(): by_id[event.event_id] = event
	check(checks, events(sim, "RESERVATION_FULFILLED").all(func(e): return by_id[e.causation_event_id].event_type == "SHIPMENT_CREATED") and events(sim, "PEER_TRANSFER_DISPATCHED").all(func(e): return by_id[e.causation_event_id].event_type == "SHIPMENT_DISPATCHED"), "reservation conversion and peer dispatch retain immediate physical causation")
