extends SceneTree

const Simulation = preload("res://kernel/simulation.gd")
const Demo = preload("res://debug/demo.gd")
const Exporter = preload("res://kernel/run_exporter.gd")
const Router = preload("res://kernel/router.gd")
const Authority = preload("res://kernel/authority_service.gd")
const Information = preload("res://kernel/information_service.gd")
const World = preload("res://kernel/world_state.gd")
const Closeout = preload("res://tests/closeout_cases.gd")
const Definition = preload("res://kernel/world_definition.gd")
const FrontCases = preload("res://tests/front_cases.gd")
const DecisionCases = preload("res://tests/decision_cases.gd")
const NeedCases = preload("res://tests/resource_resolution_cases.gd")
const ArbitrationCases = preload("res://tests/arbitration_cases.gd")
const IntegratedCases = preload("res://tests/integrated_cases.gd")
const PlayerCases = preload("res://tests/player_observation_cases.gd")
var checks: Array = []
var failures: Array = []

func check(condition: bool, name: String) -> void:
	checks.append({"name": name, "passed": condition})
	if not condition:
		failures.append(name)
		print("FAIL: ", name)

func error(result: Dictionary, code: String, name: String) -> void:
	check(not result.success and result.error_code == code, name)

func fresh(stock := 1000, stockpile := "HQ_STOCK", data: Dictionary = {}) -> RefCounted:
	var sim := Simulation.new()
	var result: Dictionary = sim.initialize(Demo.definition() if data.is_empty() else data, 101, "acceptance")
	check(result.success, "fixture initializes")
	if stock > 0:
		check(do_input(sim, {"type": "CreateResource", "stockpile_id": stockpile, "resource_type_id": "AMMUNITION", "quantity": stock}).success, "scripted resource creation")
	return sim

func do_input(sim: RefCounted, command: Dictionary, privileged := true) -> Dictionary:
	return sim.execute(command, privileged)

func set_enabled(sim: RefCounted, table: String, id: String, enabled: bool) -> Dictionary:
	return do_input(sim, {"type": "SetEnabled", "table": table, "entity_id": id, "enabled": enabled})

func reserve(sim: RefCounted, quantity: Variant) -> Dictionary:
	return do_input(sim, {"type": "ReserveResource", "stockpile_id": "HQ_STOCK", "resource_type_id": "AMMUNITION", "quantity": quantity})

func ship(sim: RefCounted, quantity: Variant = 200, destination := "A_STOCK", origin := "HQ_STOCK") -> Dictionary:
	return Demo.create_shipment(sim, origin, destination, quantity)

func dispatch(sim: RefCounted, id: String) -> Dictionary:
	return do_input(sim, {"type": "DispatchShipment", "shipment_id": id})

func conserved(sim: RefCounted, name: String) -> void:
	for resource in sim.audit():
		check(sim.audit()[resource].valid, name + " / " + resource)
	# Validate every event prefix, including atomic transfers, independently of services.
	var projection := World.new(sim.initial_world)
	var valid := true
	for event in sim.events.all():
		projection.apply_event(event)
		var state: Dictionary = projection.snapshot()
		for resource in state.resource_types:
			var stock := 0.0
			var cargo := 0.0
			for s in state.stockpiles.values():
				stock += s.quantities.get(resource, 0)
				valid = valid and s.reserved.get(resource, 0) >= 0 and s.reserved.get(resource, 0) <= s.quantities.get(resource, 0)
			for s in state.shipments.values():
				if s.resource_type_id == resource and s.state in ["IN_TRANSIT", "BLOCKED"]:
					cargo += s.quantity
			var l: Dictionary = state.ledger[resource]
			valid = valid and absf(l.created - stock - cargo - l.consumed - l.destroyed) < 0.000001
	check(valid, name + " / every event prefix conserves resources")

func _initialize() -> void:
	_test_resources()
	_test_shipments()
	_test_routing()
	_test_hierarchy()
	_test_communication()
	_test_beliefs()
	_test_determinism()
	_test_validation()
	var closeout: Dictionary = Closeout.run()
	for item in closeout.checks:
		check(item.passed, item.name)
	var fronts: Dictionary = FrontCases.run()
	for item in fronts.checks:
		check(item.passed, item.name)
	var decisions: Dictionary = DecisionCases.run()
	for item in decisions.checks:
		check(item.passed, item.name)
	var needs: Dictionary = NeedCases.run()
	for item in needs.checks:
		check(item.passed, item.name)
	var arbitration: Dictionary = ArbitrationCases.run()
	for item in arbitration.checks:
		check(item.passed, item.name)
	var integrated: Dictionary = IntegratedCases.run()
	for item in integrated.checks:
		check(item.passed, item.name)
	var player: Dictionary = PlayerCases.run()
	for item in player.checks:
		check(item.passed, item.name)
	var report := {"schema_version": Definition.SCHEMA_VERSION, "project_version": Definition.PROJECT_VERSION, "engine_version": Engine.get_version_info().string, "checks": checks.size(), "passed": checks.size() - failures.size(), "failed": failures.size(), "failures": failures, "results": checks}
	Exporter.write_json("res://artifacts/acceptance_results.json", report)
	print("TRENCHO ACCEPTANCE: %d checks, %d failed" % [checks.size(), failures.size()])
	quit(0 if failures.is_empty() else 1)

func _test_resources() -> void:
	var sim := fresh(500)
	var first := reserve(sim, 300)
	check(first.success, "reserve 300 from 500")
	error(reserve(sim, 250), "INSUFFICIENT_AVAILABLE_STOCK", "double spending rejected")
	var second := reserve(sim, 200)
	check(second.success, "remaining 200 can be reserved")
	error(do_input(sim, {"type": "ConsumeResource", "stockpile_id": "HQ_STOCK", "resource_type_id": "AMMUNITION", "quantity": 1, "reason_code": "TEST"}), "INSUFFICIENT_AVAILABLE_STOCK", "consumption cannot take reserved stock")
	conserved(sim, "two reservations")
	check(do_input(sim, {"type": "ConsumeReservation", "reservation_id": first.entity_id}).success, "consume active claim")
	check(sim.world.get_stockpile("HQ_STOCK").quantities.AMMUNITION == 200 and sim.audit().AMMUNITION.consumed == 300, "reservation consumption removes physical stock and credits consumed")
	error(do_input(sim, {"type": "ConsumeReservation", "reservation_id": first.entity_id}), "INVALID_STATE", "reservation cannot be consumed twice")
	error(do_input(sim, {"type": "ReleaseReservation", "reservation_id": first.entity_id}), "INVALID_STATE", "consumed reservation cannot be released")
	check(do_input(sim, {"type": "ReleaseReservation", "reservation_id": second.entity_id}).success, "release restores availability")
	error(do_input(sim, {"type": "ReleaseReservation", "reservation_id": second.entity_id}), "INVALID_STATE", "release exactly once")
	var invalidated := reserve(sim, 10)
	check(do_input(sim, {"type": "InvalidateReservation", "reservation_id": invalidated.entity_id}).success, "explicit reservation invalidation")
	for q in [0, -1, 0.5, "ten", INF, NAN]:
		error(reserve(sim, q), "INVALID_QUANTITY", "invalid reservation quantity " + str(q))
	error(do_input(sim, {"type": "ConsumeResource", "stockpile_id": "HQ_STOCK", "resource_type_id": "AMMUNITION", "quantity": 201, "reason_code": "TEST"}), "INSUFFICIENT_AVAILABLE_STOCK", "consumption cannot overspend")
	check(do_input(sim, {"type": "ConsumeResource", "stockpile_id": "HQ_STOCK", "resource_type_id": "AMMUNITION", "quantity": 20, "reason_code": "TEST"}).success, "actual resource consumption")
	check(do_input(sim, {"type": "DestroyResource", "stockpile_id": "HQ_STOCK", "resource_type_id": "AMMUNITION", "quantity": 10, "reason_code": "TEST"}).success, "explicit stock destruction")
	conserved(sim, "consumption and destruction")
	var data: Dictionary = Demo.definition()
	data.resource_types.append({"id": "TEST_FRACTIONAL", "allow_fractional_quantity": true})
	data.stockpiles[1].quantities = {"TEST_FRACTIONAL": 2.5}
	sim = fresh(0, "HQ_STOCK", data)
	var fractional := do_input(sim, {"type": "CreateShipment", "origin_stockpile_id": "HQ_STOCK", "destination_stockpile_id": "A_STOCK", "resource_type_id": "TEST_FRACTIONAL", "quantity": 1.25})
	check(fractional.success and dispatch(sim, fractional.entity_id).success, "generic fractional resource works through shipment service")
	sim.advance(2)
	check(sim.world.get_stockpile("A_STOCK").quantities.TEST_FRACTIONAL == 1.25, "fractional resource arrives")
	conserved(sim, "data-defined second resource")

func _test_shipments() -> void:
	var sim := fresh()
	var planned := ship(sim)
	check(planned.success, "planned shipment created")
	check(sim.world.get_stockpile("HQ_STOCK").quantities.AMMUNITION == 1000 and sim.world.get_stockpile("HQ_STOCK").reserved.AMMUNITION == 200, "planning reserves without physical transfer")
	var rid: String = sim.world.get_shipment(planned.entity_id).reservation_id
	error(do_input(sim, {"type": "ConsumeReservation", "reservation_id": rid}), "INVALID_STATE", "shipment reservation cannot be consumed independently")
	check(do_input(sim, {"type": "CancelShipment", "shipment_id": planned.entity_id}).success, "planned cancellation succeeds")
	check(sim.world.get_stockpile("HQ_STOCK").quantities.AMMUNITION == 1000 and sim.world.get_stockpile("HQ_STOCK").reserved.AMMUNITION == 0, "cancellation preserves physical stock and releases claim")
	error(dispatch(sim, planned.entity_id), "INVALID_STATE", "cancelled shipment cannot dispatch")
	var active := ship(sim)
	check(dispatch(sim, active.entity_id).success, "dispatch succeeds")
	check(sim.audit().AMMUNITION.consumed == 0 and sim.audit().AMMUNITION.in_transit == 200, "dispatch is transfer rather than consumption")
	check(sim.world.get_entity("resource_reservations", sim.world.get_shipment(active.entity_id).reservation_id).state == "FULFILLED", "dispatch fulfils reservation")
	error(do_input(sim, {"type": "CancelShipment", "shipment_id": active.entity_id}), "INVALID_STATE", "in-transit cancellation cannot teleport cargo")
	error(dispatch(sim, active.entity_id), "INVALID_STATE", "dispatch exactly once")
	sim.advance()
	check(sim.world.get_shipment(active.entity_id).state == "IN_TRANSIT" and sim.world.get_stockpile("A_STOCK").quantities.get("AMMUNITION", 0) == 0, "travel takes logical time")
	sim.advance()
	check(sim.world.get_shipment(active.entity_id).state == "ARRIVED" and sim.world.get_stockpile("A_STOCK").quantities.AMMUNITION == 200, "arrival credits correct destination")
	sim.advance(5)
	check(sim.world.get_stockpile("A_STOCK").quantities.AMMUNITION == 200, "arrival exactly once")
	var destroyed := ship(sim, 50, "B_STOCK")
	dispatch(sim, destroyed.entity_id)
	check(do_input(sim, {"type": "DestroyShipment", "shipment_id": destroyed.entity_id, "reason_code": "TEST_INTERDICTION"}).success, "destroy in-transit cargo")
	error(do_input(sim, {"type": "DestroyShipment", "shipment_id": destroyed.entity_id, "reason_code": "TEST"}), "INVALID_STATE", "destroy exactly once")
	sim.advance(10)
	check(sim.world.get_stockpile("B_STOCK").quantities.get("AMMUNITION", 0) == 0 and sim.audit().AMMUNITION.destroyed == 50, "destroyed cargo cannot arrive")
	conserved(sim, "shipment lifecycles")
	sim = fresh()
	var blocked := ship(sim, 200, "B_STOCK")
	dispatch(sim, blocked.entity_id)
	sim.advance()
	set_enabled(sim, "logistics_edges", "hq_b", false)
	sim.advance()
	var state: Dictionary = sim.world.get_shipment(blocked.entity_id)
	check(state.state == "BLOCKED" and state.current_location_id == "ARMY_HQ" and state.edge_progress_seconds == 0.1, "blocked cargo preserves last location and partial progress")
	error(do_input(sim, {"type": "CancelShipment", "shipment_id": blocked.entity_id}), "INVALID_STATE", "blocked cancellation cannot teleport cargo")
	conserved(sim, "blocked shipment")
	check(do_input(sim, {"type": "RerouteShipment", "shipment_id": blocked.entity_id, "destination_stockpile_id": "B_STOCK"}).success, "explicit alternate reroute")
	state = sim.world.get_shipment(blocked.entity_id)
	check(state.route_edge_ids == ["hq_a", "a_b"] and state.edge_progress_seconds == 0, "reroute starts from last reached location and resets progress")
	var reroute_event: Dictionary = sim.events.all().back()
	check(reroute_event.payload.abandoned_edge_id == "hq_b" and reroute_event.payload.abandoned_edge_progress_seconds == 0.1, "reroute records abandoned edge progress")
	sim.advance(6)
	check(sim.world.get_shipment(blocked.entity_id).state == "ARRIVED", "rerouted cargo arrives")
	conserved(sim, "rerouted shipment")
	sim = fresh()
	set_enabled(sim, "logistics_edges", "hq_b", false)
	var second_leg := ship(sim, 100, "B_STOCK")
	dispatch(sim, second_leg.entity_id)
	sim.advance(3)
	set_enabled(sim, "logistics_edges", "a_b", false)
	sim.advance()
	check(sim.world.get_shipment(second_leg.entity_id).current_location_id == "DEPOT_A", "second leg blocks at reached intermediate location")
	error(do_input(sim, {"type": "RerouteShipment", "shipment_id": second_leg.entity_id, "destination_stockpile_id": "B_STOCK"}), "NO_LOGISTICS_ROUTE", "failed reroute remains blocked")
	check(sim.world.get_shipment(second_leg.entity_id).state == "BLOCKED", "failed reroute keeps cargo")
	set_enabled(sim, "logistics_edges", "a_b", true)
	check(do_input(sim, {"type": "RerouteShipment", "shipment_id": second_leg.entity_id, "destination_stockpile_id": "B_STOCK"}).success, "reroute after route repair")
	check(sim.world.get_shipment(second_leg.entity_id).route_edge_ids == ["a_b"], "reroute uses current location, never original origin")
	sim.advance(4)
	conserved(sim, "intermediate reroute")
	sim = fresh()
	var disabled := ship(sim)
	set_enabled(sim, "logistics_edges", "hq_a", false)
	error(dispatch(sim, disabled.entity_id), "ROUTE_DISABLED", "dispatch validates first edge again")
	check(sim.world.get_shipment(disabled.entity_id).state == "PLANNED", "failed dispatch leaves plan intact")
	set_enabled(sim, "logistics_edges", "hq_a", true)
	dispatch(sim, disabled.entity_id)
	set_enabled(sim, "locations", "DEPOT_A", false)
	sim.advance()
	check(sim.world.get_shipment(disabled.entity_id).state == "BLOCKED", "disabled destination blocks arrival")
	check(do_input(sim, {"type": "DestroyShipment", "shipment_id": disabled.entity_id, "reason_code": "TEST"}).success, "blocked cargo can be explicitly destroyed")
	conserved(sim, "disabled destination")

func _test_routing() -> void:
	var data: Dictionary = Demo.definition()
	data.logistics_edges.append({"id": "aaa_equal", "from_location_id": "ARMY_HQ", "to_location_id": "DEPOT_B", "travel_time_seconds": 0.5})
	var sim := fresh(1000, "HQ_STOCK", data)
	var route: Dictionary = Router.find(sim.world, "ARMY_HQ", "DEPOT_B")
	check(route.success and route.details.edge_ids == ["aaa_equal"], "deterministic equal-cost logistics tie-break")
	set_enabled(sim, "logistics_edges", "aaa_equal", false)
	route = Router.find(sim.world, "ARMY_HQ", "DEPOT_B")
	check(route.details.edge_ids == ["hq_b"], "disabled edge excluded and shortest route chosen")
	error(Router.find(sim.world, "DEPOT_B", "ARMY_HQ"), "NO_LOGISTICS_ROUTE", "edges are directed")
	for q in [0, -1, 0.25]:
		error(ship(sim, q), "INVALID_QUANTITY", "invalid shipment quantity " + str(q))
	error(ship(sim, 1, "HQ_STOCK"), "INVALID_ENTITY", "same stockpile shipment rejected")
	var count: int = sim.world.ids("resource_reservations").size()
	error(ship(sim, 1001), "INSUFFICIENT_AVAILABLE_STOCK", "shipment stock validation")
	error(ship(sim, 1, "SOURCE_STOCK"), "NO_LOGISTICS_ROUTE", "shipment no-route failure")
	check(sim.world.ids("resource_reservations").size() == count and sim.world.ids("shipments").is_empty(), "failed creation leaves neither reservation nor shipment")
	set_enabled(sim, "locations", "DEPOT_A", false)
	error(ship(sim), "DESTINATION_DISABLED", "disabled location cannot receive new shipment")
	set_enabled(sim, "stockpiles", "HQ_STOCK", false)
	error(ship(sim, 1, "B_STOCK"), "ORIGIN_DISABLED", "disabled stockpile cannot dispatch")
	data = Demo.definition()
	for e in data.logistics_edges:
		e.travel_time_seconds = 0.02
	sim = fresh(1000, "SOURCE_STOCK", data)
	var short := ship(sim, 100, "B_STOCK", "SOURCE_STOCK")
	dispatch(sim, short.entity_id)
	sim.advance()
	check(sim.world.get_shipment(short.entity_id).state == "ARRIVED", "overshoot traverses multiple short edges in one tick")
	conserved(sim, "multi-edge single tick")
	data = Demo.definition()
	for e in data.logistics_edges:
		e.travel_time_seconds = 0.0
	data.logistics_edges.append({"id": "zero_cycle", "from_location_id": "DEPOT_A", "to_location_id": "ARMY_HQ", "travel_time_seconds": 0})
	sim = fresh(1000, "HQ_STOCK", data)
	short = ship(sim)
	dispatch(sim, short.entity_id)
	sim.advance()
	check(sim.world.get_shipment(short.entity_id).state == "ARRIVED", "zero-time edges and cycles terminate deterministically")

func _test_hierarchy() -> void:
	var sim := fresh()
	check(sim.world.get_command("LOCAL_A").superior_command_id == "ARMY_COMMAND", "parent child relationship")
	check(sim.world.get_command("ARMY_COMMAND").subordinate_command_ids == ["LOCAL_A", "LOCAL_B"], "multiple siblings are stable")
	error(do_input(sim, {"type": "ReparentCommand", "command_id": "ARMY_COMMAND", "superior_command_id": "LOCAL_A"}), "HIERARCHY_CYCLE", "descendant reparent rejected")
	error(do_input(sim, {"type": "ReparentCommand", "command_id": "LOCAL_A", "superior_command_id": "LOCAL_A"}), "HIERARCHY_CYCLE", "self parent rejected")
	check(do_input(sim, {"type": "ReparentCommand", "command_id": "LOCAL_A", "superior_command_id": "STRATEGIC_COMMAND"}).success, "valid reparent succeeds")
	check(sim.events.all().back().event_type == "COMMAND_REPARENTED", "reparent event recorded")
	check(not "LOCAL_A" in sim.world.get_command("ARMY_COMMAND").subordinate_command_ids and "LOCAL_A" in sim.world.get_command("STRATEGIC_COMMAND").subordinate_command_ids, "both adjacency directions updated")
	var auth := Authority.new(sim)
	check(auth.can_dispatch("ARMY_COMMAND", "HQ_STOCK"), "direct authority allowed")
	check(not auth.can_dispatch("STRATEGIC_COMMAND", "HQ_STOCK"), "superior inherits no write authority")
	error(do_input(sim, {"type": "CreateShipment", "origin_stockpile_id": "HQ_STOCK", "destination_stockpile_id": "A_STOCK", "resource_type_id": "AMMUNITION", "quantity": 10, "actor_entity_id": "STRATEGIC_COMMAND"}, false), "UNAUTHORIZED", "unauthorized dispatch request rejected")
	check(do_input(sim, {"type": "CreateShipment", "origin_stockpile_id": "HQ_STOCK", "destination_stockpile_id": "A_STOCK", "resource_type_id": "AMMUNITION", "quantity": 10, "actor_entity_id": "ARMY_COMMAND"}, false).success, "authorized command request accepted")
	error(do_input(sim, {"type": "CreateResource", "stockpile_id": "HQ_STOCK", "resource_type_id": "AMMUNITION", "quantity": 1}, false), "UNAUTHORIZED", "debug creation unavailable to normal input")
	error(do_input(sim, {"type": "SetEnabled", "table": "communication_edges", "entity_id": "army_a", "enabled": false}, false), "UNAUTHORIZED", "forced edge failure is privileged")
	set_enabled(sim, "commands", "ARMY_COMMAND", false)
	check(not auth.can_dispatch("ARMY_COMMAND", "HQ_STOCK"), "disabled command has no dispatch authority")
	check(not sim.world.get_command("ARMY_COMMAND").is_empty(), "disabled command retains identity and history")
	var view: RefCounted = sim.command_view("STRATEGIC_COMMAND")
	check(view.local_stockpile("HQ_STOCK").is_empty() and view.information().is_empty(), "hierarchy confers no stock knowledge or beliefs")
	view = sim.command_view("LOCAL_B")
	check(not view.local_stockpile("B_STOCK").is_empty() and view.local_stockpile("A_STOCK").is_empty(), "command view exposes own stock only")
	check(not view.local_location("DEPOT_B").is_empty() and view.local_location("ARMY_HQ").is_empty(), "command view exposes own locations only")
	check(not view.has_method("snapshot") and not view.has_method("get_entity") and not view.has_method("get_stockpile"), "command view has no unrestricted world API")
	var detached: Dictionary = sim.world.get_stockpile("HQ_STOCK")
	detached.quantities.AMMUNITION = -100
	check(sim.world.get_stockpile("HQ_STOCK").quantities.AMMUNITION == 1000, "world queries cannot mutate authoritative state")
	var local: Dictionary = view.local_stockpile("B_STOCK")
	local.enabled = false
	check(sim.world.get_stockpile("B_STOCK").enabled, "command view is detached from world")
	check(view.public_facts().has("scenario"), "explicitly public facts available")

func message(sim: RefCounted, sender := "LOCAL_A", recipient := "ARMY_COMMAND", payload: Dictionary = {}, type := "GENERIC") -> Dictionary:
	return do_input(sim, {"type": "SendMessage", "sender_command_id": sender, "recipient_command_id": recipient, "message_type": type, "payload": payload})

func fact(sim: RefCounted, value: Variant = 1, key := "test", observed: Variant = null, expiry: Variant = null) -> Dictionary:
	return {"subject_entity_id": "A_STOCK", "fact_key": key, "value": value, "observed_at": sim.time() if observed == null else observed, "confidence": 0.8, "expires_at": expiry}

func _test_communication() -> void:
	var sim := fresh()
	var sent := message(sim)
	check(sent.success and sim.world.get_entity("messages", sent.entity_id).route_edge_ids == ["a_army"], "one-edge message route")
	check(sim.command_view("ARMY_COMMAND").inbox().is_empty(), "in-transit message excluded from recipient inbox")
	sim.advance(2)
	check(sim.world.get_entity("messages", sent.entity_id).state == "IN_TRANSIT", "message waits for latency")
	sim.advance()
	check(sim.world.get_entity("messages", sent.entity_id).state == "DELIVERED" and sim.command_view("ARMY_COMMAND").inbox().size() == 1, "message delivered at due tick")
	sim.advance(5)
	check(sim.command_view("ARMY_COMMAND").inbox().size() == 1, "delivered message persists without duplicate delivery")
	set_enabled(sim, "communication_edges", "a_army", false)
	var route: Dictionary = Router.find(sim.world, "LOCAL_A", "ARMY_COMMAND", true)
	check(route.success and route.details.edge_ids == ["a_b_radio", "b_army"], "multi-edge communication route")
	sent = message(sim)
	sim.advance(5)
	check(sim.world.get_entity("messages", sent.entity_id).state == "DELIVERED", "multi-edge delivery")
	check(message(sim, "LOCAL_A", "LOCAL_B").success, "siblings communicate over explicit edge")
	error(message(sim, "STRATEGIC_COMMAND", "ARMY_COMMAND"), "NO_COMMUNICATION_ROUTE", "hierarchy is not a communication route")
	set_enabled(sim, "communication_edges", "a_b_radio", false)
	error(message(sim), "NO_COMMUNICATION_ROUTE", "no route rejected at send time")
	set_enabled(sim, "communication_edges", "a_army", true)
	var payload := {"facts": [fact(sim)]}
	sent = message(sim, "LOCAL_A", "ARMY_COMMAND", payload, "REPORT")
	check(sim.command_view("ARMY_COMMAND").current_belief("A_STOCK", "test", sim.time()).is_empty(), "report contents private while in transit")
	set_enabled(sim, "communication_edges", "a_army", false)
	sim.advance(3)
	check(sim.world.get_entity("messages", sent.entity_id).state == "FAILED", "required edge disabled before due delivery fails message")
	check(sim.command_view("ARMY_COMMAND").current_belief("A_STOCK", "test", sim.time()).is_empty(), "failed message produces no belief")
	set_enabled(sim, "communication_edges", "a_army", true)
	check(sim.command_view("ARMY_COMMAND").current_belief("A_STOCK", "test", sim.time()).is_empty(), "edge changes do not update beliefs")
	sent = message(sim, "LOCAL_A", "ARMY_COMMAND", {"facts": [fact(sim, 42)]}, "REPORT")
	sim.advance(3)
	var belief: Dictionary = sim.command_view("ARMY_COMMAND").current_belief("A_STOCK", "test", sim.time())
	check(belief.value == 42 and belief.source_message_id == sent.entity_id and belief.source_command_id == "LOCAL_A", "delivered report ingested with source provenance")
	check(belief.causation_event_id != null and belief.received_at == sim.time(), "belief includes receipt time and delivery cause")
	var before: int = sim.world.ids("information_records").size()
	var invalid: Dictionary = fact(sim)
	invalid.confidence = 1.1
	error(message(sim, "LOCAL_A", "ARMY_COMMAND", {"facts": [invalid]}, "REPORT"), "INVALID_INFORMATION", "malformed report rejected before sending")
	check(sim.world.ids("information_records").size() == before, "invalid report cannot partially ingest")
	var data: Dictionary = Demo.definition()
	data.communication_edges.append({"id": "a0_radio", "from_command_id": "LOCAL_A", "to_command_id": "ARMY_COMMAND", "latency_seconds": 0.3})
	sim = fresh(0, "HQ_STOCK", data)
	check(Router.find(sim.world, "LOCAL_A", "ARMY_COMMAND", true).details.edge_ids == ["a0_radio"], "communication equal-cost edge-ID tie-break")
	data = Demo.definition()
	data.communication_edges[1].latency_seconds = 0
	sim = fresh(0, "HQ_STOCK", data)
	sent = message(sim)
	check(sim.world.get_entity("messages", sent.entity_id).state == "DELIVERED" and sim.command_view("ARMY_COMMAND").inbox().size() == 1, "zero-latency message delivers at its due time without advancing clock")

func ingest(sim: RefCounted, owner: String, record: Dictionary) -> Dictionary:
	return do_input(sim, {"type": "IngestInformation", "owner_command_id": owner, "fact": record})

func _test_beliefs() -> void:
	var sim := fresh()
	check(sim.command_view("LOCAL_A").information().is_empty(), "global truth creates no automatic belief")
	var stale := ingest(sim, "ARMY_COMMAND", fact(sim, 10))
	check(stale.success, "explicit information ingestion")
	sim.advance(2)
	var newer := ingest(sim, "ARMY_COMMAND", fact(sim, 20))
	ingest(sim, "ARMY_COMMAND", fact(sim, 99, "test", 0.1))
	var info := Information.new(sim)
	check(info.get_current_belief("ARMY_COMMAND", "A_STOCK", "test", sim.time()).id == newer.entity_id, "newest observation wins over later receipt")
	sim.advance()
	var received := ingest(sim, "ARMY_COMMAND", fact(sim, 30, "test", 0.2))
	check(info.get_current_belief("ARMY_COMMAND", "A_STOCK", "test", sim.time()).id == received.entity_id, "equal observation chooses newer receipt")
	var tied := ingest(sim, "ARMY_COMMAND", fact(sim, 40, "test", 0.2))
	check(info.get_current_belief("ARMY_COMMAND", "A_STOCK", "test", sim.time()).id == received.entity_id and tied.entity_id != received.entity_id, "equal times choose ascending stable record ID")
	check(sim.command_view("ARMY_COMMAND").information().size() == 5, "conflicting reports remain inspectable")
	ingest(sim, "ARMY_COMMAND", fact(sim, 50, "expiring", null, 0.4))
	check(not info.get_current_belief("ARMY_COMMAND", "A_STOCK", "expiring", sim.time()).is_empty(), "unexpired record visible")
	sim.advance()
	check(info.get_current_belief("ARMY_COMMAND", "A_STOCK", "expiring", sim.time()).is_empty(), "record expires at expiry boundary")
	ingest(sim, "LOCAL_A", fact(sim, 100))
	check(sim.command_view("ARMY_COMMAND").current_belief("A_STOCK", "test", sim.time()).value == 30 and sim.command_view("LOCAL_A").current_belief("A_STOCK", "test", sim.time()).value == 100, "superior can hold stale belief while subordinate has newer report")
	check(info.get_current_belief("ARMY_COMMAND", "A_STOCK", "test", 0).id == stale.entity_id, "historical query excludes future receipts")
	error(do_input(sim, {"type": "IngestInformation", "owner_command_id": "LOCAL_A", "fact": fact(sim)}, false), "UNAUTHORIZED", "direct information injection isolated from normal input")
	var record: Dictionary = sim.world.get_entity("information_records", stale.entity_id)
	check(record.source_system == "PRIVILEGED_INPUT" and record.source_message_id == null, "privileged ingestion provenance explicit")

func _test_determinism() -> void:
	var first: Dictionary = Demo.run(101, "first")
	var second: Dictionary = Demo.run(101, "second")
	check(first.success and second.success, "required demonstration sequence passes twice")
	if not first.success or not second.success:
		return
	var a: RefCounted = first.details.simulation
	var b: RefCounted = second.details.simulation
	check(Exporter.equivalent(a.snapshot(), b.snapshot()), "same seed and inputs yield same complete state")
	check(Exporter.equivalent(a.events.all(), b.events.all()), "same seed and inputs yield same ordered normalized event stream")
	check(Exporter.equivalent(a.audit(), b.audit()), "same seed resource ledger matches")
	var third: Dictionary = Demo.run(202, "third")
	check(third.success, "different-seed run succeeds")
	check(third.details.simulation.initial_world.simulation_seed == 202 and third.details.simulation.initial_world.rng_state != a.initial_world.rng_state, "simulation owns seeded RNG identity")
	var data_a: Dictionary = a.snapshot()
	var data_b: Dictionary = third.details.simulation.snapshot()
	for key in ["simulation_seed", "rng_state"]:
		data_a.erase(key)
		data_b.erase(key)
	check(Exporter.equivalent(data_a, data_b), "no stochastic policy: different seed preserves gameplay result")
	check(Exporter.export_run(a, "res://artifacts/run_demo").success, "complete diagnostic package exported")
	var replay: Dictionary = Exporter.replay_package("res://artifacts/run_demo")
	check(replay.success and replay.details.state_match and replay.details.events_match, "replay from JSON/JSONL files matches final state and all events")
	var projection := World.new(a.initial_world)
	var causal_valid := true
	var seen: Dictionary = {}
	for event in a.events.all():
		if event.causation_event_id != null:
			causal_valid = causal_valid and seen.has(event.causation_event_id)
		seen[event.event_id] = true
		projection.apply_event(event)
	check(Exporter.equivalent(projection.snapshot(), a.snapshot()), "event-only reconstruction matches complete final authoritative state")
	check(causal_valid, "causation references earlier events")
	var movement_linked := true
	for event in a.events.all():
		if event.event_type in ["SHIPMENT_PROGRESS_CHANGED", "SHIPMENT_ARRIVED", "MESSAGE_DELIVERED", "MESSAGE_FAILED"]:
			movement_linked = movement_linked and event.correlation_id != null and event.causation_event_id != null
	check(movement_linked, "autonomous delivery events retain input correlation and causal links")
	conserved(a, "required demonstration")
	check(a.world.get_stockpile("SOURCE_STOCK").quantities.AMMUNITION == 400 and a.world.get_stockpile("HQ_STOCK").quantities.AMMUNITION == 100 and a.world.get_stockpile("A_STOCK").quantities.AMMUNITION == 300 and a.world.get_stockpile("B_STOCK").quantities.AMMUNITION == 200, "demonstration ends with 400 / 100 / 300 / 200 ammunition")
	var end_clock: Dictionary = a.world.clock()
	check(end_clock.tick_index == 17 and end_clock.simulation_time_seconds == 1.7, "clock derives from integer logical ticks")
	error(a.advance(), "INVALID_STATE", "ended simulation cannot advance")
	error(do_input(a, {"type": "EndRun"}), "INVALID_STATE", "ended run cannot accept inputs")
	var copied: Array = a.events.all()
	copied[0].event_type = "TAMPERED"
	check(a.events.all()[0].event_type == "RUN_STARTED", "event store queries cannot mutate log")
	check(Exporter.equivalent({"b": 2.0, "a": 1}, {"a": 1.0, "b": 2}), "normalization ignores dictionary order and JSON number representation")
	# Future decision records have the same base envelope and JSON-compatible payload.
	var sample := {"event_type": "DECISION_CANDIDATE_RECORDED", "schema_version": "2A.1", "payload": {"candidate_id": "sample", "score": 1}}
	check(Exporter.equivalent(sample, JSON.parse_string(JSON.stringify(sample))), "reserved decision record shape serializes without fake production decisions")

func _test_validation() -> void:
	var data: Dictionary = Demo.definition()
	data.commands[0].superior_command_id = "LOCAL_A"
	var sim := Simulation.new()
	error(sim.initialize(data), "HIERARCHY_CYCLE", "cyclic initial hierarchy rejected")
	data = Demo.definition()
	data.locations.append(data.locations[0].duplicate(true))
	error(sim.initialize(data), "INVALID_WORLD_DEFINITION", "duplicate IDs rejected")
	data = Demo.definition()
	data.logistics_edges[0].travel_time_seconds = -1
	error(sim.initialize(data), "INVALID_WORLD_DEFINITION", "negative edge duration rejected")
	data = Demo.definition()
	data.stockpiles[0].quantities = {"AMMUNITION": -1}
	error(sim.initialize(data), "INVALID_WORLD_DEFINITION", "negative initial stock rejected")
	sim = fresh()
	error(do_input(sim, {"type": "Unknown"}), "INVALID_INPUT", "unknown input returns structured error")
	error(do_input(sim, {"type": "CreateShipment"}), "INVALID_INPUT", "missing fields rejected cleanly")
	error(do_input(sim, {"type": "SetEnabled", "table": "locations", "entity_id": "DEPOT_A", "enabled": "yes"}), "INVALID_INPUT", "wrong parameter types rejected cleanly")
	check(sim.inputs.back().result.error_code == "INVALID_INPUT", "failed input attempts retained in diagnostic history")
	var snapshot: Dictionary = sim.initial_world.duplicate(true)
	snapshot.schema_version = "future"
	error(Exporter.replay(snapshot, [], 0), "UNSUPPORTED_SNAPSHOT", "unknown schema never silently reinterpreted")
	snapshot = sim.initial_world.duplicate(true)
	snapshot.project_version = "0.1.0"
	error(Exporter.replay(snapshot, [], 0), "UNSUPPORTED_SNAPSHOT", "prior simulation version cannot silently reuse corrected event semantics")
	var replayed: Dictionary = Exporter.replay(sim.initial_world, sim.inputs, sim.world.clock().tick_index)
	check(replayed.success and Exporter.equivalent(replayed.details.simulation.snapshot(), sim.snapshot()), "failed input attempts replay consistently")
	var previous: Dictionary = sim.snapshot()
	error(reserve(sim, NAN), "INVALID_QUANTITY", "nonfinite quantity rejected before logging")
	check(Exporter.equivalent(previous, sim.snapshot()), "nonserializable input cannot alter authoritative history")
	check(Exporter.export_run(sim, "res://artifacts/run_invalid_inputs").success and Exporter.replay_package("res://artifacts/run_invalid_inputs").success, "run remains exportable and replayable after invalid input calls")
	error(Simulation.new().initialize_snapshot({"schema_version": "2A.1"}), "INVALID_SNAPSHOT", "incomplete snapshot returns structured error")
	snapshot = sim.initial_world.duplicate(true)
	snapshot.stockpiles.HQ_STOCK.reserved.AMMUNITION = 10
	error(Simulation.new().initialize_snapshot(snapshot), "INVALID_SNAPSHOT", "inconsistent initial snapshot is rejected")
