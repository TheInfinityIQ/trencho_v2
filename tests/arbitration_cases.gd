extends RefCounted
const Demo = preload("res://debug/arbitration_demo.gd")
const Simulation = preload("res://kernel/simulation.gd")
const Policy = preload("res://kernel/ammunition_arbitration_policy.gd")
const NeedCases = preload("res://tests/resource_resolution_cases.gd")
const Exporter = preload("res://kernel/run_exporter.gd")

static func check(checks: Array, passed: bool, name: String) -> void:
	checks.append({"name": "106 / " + name, "passed": passed})

static func rows(sim: RefCounted, table: String) -> Array:
	return NeedCases.rows(sim, table)

static func events(sim: RefCounted, type: String) -> Array:
	return NeedCases.events(sim, type)

static func fresh(data: Dictionary = {}) -> RefCounted:
	var sim := Simulation.new()
	var result: Dictionary = sim.initialize(Demo.definition() if data.is_empty() else data, 106, "arbitration-tests")
	assert(result.success, JSON.stringify(result))
	return sim

static func funded(sim: RefCounted, command := "LOCAL_A") -> int:
	var total := 0
	for shipment in rows(sim, "shipments"):
		if shipment.has("arbitration_id") and shipment.destination_stockpile_id == ("A_STOCK" if command == "LOCAL_A" else "B_STOCK"): total += int(shipment.quantity)
	return total

static func report_at(sim: RefCounted) -> Dictionary:
	var reports: Array = sim.command_view("ARMY_COMMAND").superior_need_reports()
	return {} if reports.is_empty() else reports[0]

static func run() -> Dictionary:
	var checks: Array = []
	var summaries: Dictionary = {}
	for scenario in ["A", "B", "C", "D", "E", "F", "G", "H"]:
		var result := Demo.run(scenario)
		check(checks, result.success, scenario + " runs")
		if not result.success: continue
		var sim: RefCounted = result.details.simulation
		var journal: Array = sim.decision_journal("ARMY_COMMAND")
		var shipments := rows(sim, "shipments")
		check(checks, NeedCases.conserved_prefixes(sim), scenario + " every event prefix stock/cargo/claims and entire event reconstruction")
		check(checks, sim.audit().AMMUNITION.valid, scenario + " ledger conservation")
		check(checks, Exporter.export_run(sim, "res://artifacts/run_step106_" + scenario).success and Exporter.replay_package("res://artifacts/run_step106_" + scenario).success, scenario + " strict full state and all event replay")
		check(checks, shipments.all(func(s): return s.origin_stockpile_id == "HQ_STOCK" and s.requested_by_command_id == "ARMY_COMMAND"), scenario + " superior own stock only")
		check(checks, sim.command_view("LOCAL_A").superior_need_reports().is_empty() and sim.command_view("LOCAL_B").superior_need_reports().is_empty(), scenario + " private superior report surface")
		check(checks, journal.all(func(d): return d.decision_type == "RESOURCE_ARBITRATION" and d.state == "COMPLETED" and d.started_at_micro % 1000000 == 0 and not d.input_reports.is_empty()), scenario + " stable typed decision journal on second boundaries")
		check(checks, rows(sim, "superior_revision_funding").all(func(f): return f.quantity <= (23 if scenario == "G" else (30 if scenario == "D" else 18000000))), scenario + " funding bounded by revision")
		if scenario == "A":
			var need: Dictionary = NeedCases.first_need(sim)
			check(checks, need.state == "RESOLVED" and funded(sim) == 80, "A real105 escalation allocation physical observation resolves")
			check(checks, report_at(sim).report_state == "RESOLVED" and events(sim, "RESOURCE_NEED_REPORT_UPDATE_SENT").size() > 0, "A material updates and resolution communicated")
			check(checks, rows(sim, "known_transfers").all(func(k): return k.status == "ARRIVED"), "A arrivals removed from incoming")
		if scenario == "B": check(checks, funded(sim) == 30 and funded(sim, "LOCAL_B") == 0, "B scarce30 critical receives30 constrained0 unequal")
		if scenario == "C":
			check(checks, funded(sim) == 60 and funded(sim, "LOCAL_B") == 40, "C coverage/rate staged allocation60/40")
			check(checks, journal[0].selected_allocations[0].need_id == "fixture:A" and journal[0].selected_allocations[1].need_id == "fixture:B" and journal[0].selected_allocations[0].stage_threshold_ms == 5000 and journal[0].selected_allocations[2].stage_threshold_ms == 15000, "C exact coverage order and5then15 stages")
		if scenario == "D":
			check(checks, report_at(sim).need_revision == 5 and funded(sim) == 30 and events(sim, "SUPERIOR_NEED_REPORT_STALE_IGNORED").size() == 1, "D newest5 wins late4 cannot overwrite allocation cap30")
		if scenario == "E":
			check(checks, report_at(sim).need_revision == 1 and funded(sim) == 80 and sim.world.get_stockpile("A_STOCK").quantities.AMMUNITION >= 190, "E stale delivered80 still allocates despite actual local refill")
			check(checks, journal[0].input_reports[0].need_revision == 1 and journal[0].input_reports[0].reported_uncovered_need_quantity == 80, "E journal pins stale delivered report revision/message")
		if scenario == "F":
			check(checks, funded(sim) == 0 and funded(sim, "LOCAL_B") == 40 and journal[0].candidate_evaluations.any(func(e): return e.need_id == "fixture:A" and e.reason_code == "NO_LOGISTICS_ROUTE"), "F unreachable A does not block B40")
		if scenario == "G": check(checks, funded(sim) == 23 and sim.world.get_stockpile("HQ_STOCK").quantities.AMMUNITION == 177 and journal.size() == 3, "G abundant stock three cycles sends23 total unchanged revision")
		if scenario == "H": check(checks, shipments.is_empty() and journal.is_empty() and report_at(sim).report_state == "RESOLVED", "H delivered resolution suppresses all allocation")
		summaries[scenario] = {"arbitrations": rows(sim, "resource_arbitrations"), "journal": journal, "need_ids": rows(sim, "resource_needs").map(func(n): return {"id": n.id, "revision": n.revision, "state": n.state}), "reports": sim.command_view("ARMY_COMMAND").superior_need_reports(), "shipments": shipments, "allocated_A": funded(sim), "allocated_B": funded(sim, "LOCAL_B"), "event_count": sim.events.count(), "end_tick": sim.world.clock().tick_index, "ledger": sim.audit()}
	_policy(checks)
	_timing(checks)
	_integrity(checks)
	_messages_and_lifecycle(checks)
	var failures: Array = []
	for item in checks:
		if not item.passed: failures.append(item.name)
	return {"success": failures.is_empty(), "checks": checks, "failures": failures, "scenarios": summaries}

static func _policy(checks: Array) -> void:
	for pair in [[4000, 5000, 20], [4000, 15000, 60], [4000, 20000, 80], [1001, 5000, 6], [1001, 15000, 16], [1001, 20000, 21], [900000000, 20000, 18000000], [0, 5000, 0]]:
		check(checks, Policy.required_stock(pair[0], pair[1]) == pair[2], "exact ceil threshold " + str(pair))
	for pair in [[0, 4, 1, 4, -1], [1, 3, 2, 6, 0], [9007199254740991, 899999999, 9007199254740990, 899999999, 1], [9007199254740991, 900000000, 9007199254740990, 899999999, -1], [1, 8, 1, 4, -1], [3, 2, 4, 3, 1]]:
		check(checks, Policy.ratio_compare(pair[0], pair[1], pair[2], pair[3]) == pair[4], "overflow-safe rational comparison " + str(pair))
	var a := Demo.report()
	var b := Demo.report("LOCAL_B", 1, 80, 0, 4000, "CRITICAL", "fixture:B")
	a.projected_stock = 0
	b.projected_stock = 0
	check(checks, Policy.before(a, b) and not Policy.before(b, a), "exact equal coverage ties by command ID")
	b.requesting_command_id = "LOCAL_A"
	check(checks, Policy.before(a, b), "equal command breaks tie by need ID")
	b.urgency = "CONSTRAINED"
	a.projected_stock = 80
	check(checks, Policy.before(a, b), "urgency precedence before coverage")

static func _timing(checks: Array) -> void:
	var data := Demo.definition()
	data.communication_edges[0].latency_seconds = 1.0
	var sim := fresh(data)
	Demo.send(sim, Demo.report())
	sim.advance(9)
	check(checks, report_at(sim).is_empty() and sim.decision_journal("ARMY_COMMAND").is_empty(), "undelivered report invisible before boundary")
	sim.advance()
	check(checks, funded(sim) == 80 and not report_at(sim).is_empty(), "report due exactly at1s eligible in same arbitration")
	check(checks, sim.command_view("LOCAL_A").known_incoming().is_empty(), "dispatch does not instantly reveal incoming")
	sim.advance(2)
	check(checks, sim.command_view("LOCAL_A").known_incoming().reduce(func(total, k): return total + k.quantity, 0) == 80, "notification delay then incoming80")
	sim.advance(3)
	check(checks, sim.command_view("LOCAL_A").known_incoming().all(func(k): return k.status == "ARRIVED"), "physical arrival removes all incoming")
	data = Demo.definition()
	data.communication_edges[2].latency_seconds = 1.0
	sim = fresh(data)
	Demo.send(sim, Demo.report())
	sim.advance(20)
	check(checks, funded(sim) == 80 and sim.command_view("LOCAL_A").known_incoming().is_empty() and events(sim, "SUPERIOR_ALLOCATION_NOTICE_RECEIVED").size() == 3, "notification after cargo is history without fake incoming")
	data = Demo.definition()
	data.communication_edges[0].latency_seconds = 0.5
	sim = fresh(data)
	Demo.send(sim, Demo.report())
	sim.advance(5)
	var update := Demo.report("LOCAL_A", 2, 30)
	update.subtype = "AMMO_NEED_UPDATE"
	Demo.send(sim, update)
	NeedCases.edge(sim, "a_army", false)
	sim.advance(5)
	check(checks, funded(sim) == 80 and report_at(sim).need_revision == 1 and events(sim, "MESSAGE_FAILED").size() == 1, "failed update leaves stale report actionable")
	update = {"subtype": "AMMO_NEED_RESOLVED", "need_id": "fixture:A", "requesting_command_id": "LOCAL_A", "final_revision": 3}
	check(checks, not Demo.send(sim, update).success and report_at(sim).report_state == "ACTIVE", "failed resolution cannot close superior report")

static func _integrity(checks: Array) -> void:
	var sim := fresh()
	Demo.send(sim, Demo.report("LOCAL_A", 1, 80, 0, 0))
	sim.advance(10)
	check(checks, funded(sim) == 0 and sim.decision_journal("ARMY_COMMAND")[0].candidate_evaluations.all(func(e): return e.reason_code == "ZERO_PLANNING_RATE"), "zero rate explicit reason no invented demand")
	sim = fresh()
	sim.execute({"type": "ReserveResource", "actor_entity_id": "ARMY_COMMAND", "stockpile_id": "HQ_STOCK", "resource_type_id": "AMMUNITION", "quantity": 180})
	Demo.send(sim, Demo.report())
	sim.advance(30)
	check(checks, funded(sim) == 20 and sim.world.get_stockpile("HQ_STOCK").reserved.AMMUNITION == 180, "existing reservations protect180 allowing20 only")
	check(checks, sim.decision_journal("ARMY_COMMAND")[0].usable_stock_before == 20, "journal source usability excludes reservations")
	var data := Demo.definition()
	data.stockpiles.append({"id": "HQ_SECOND", "location_id": "ARMY_HQ", "owner_command_id": "ARMY_COMMAND", "quantities": {"AMMUNITION": 50}})
	data.commands[0].directly_controlled_stockpile_ids.append("HQ_SECOND")
	data.stockpiles[0].quantities.AMMUNITION = 30
	sim = fresh(data)
	Demo.send(sim, Demo.report())
	sim.advance(10)
	check(checks, funded(sim) == 80 and rows(sim, "shipments").any(func(s): return s.origin_stockpile_id == "HQ_SECOND") and rows(sim, "shipments").any(func(s): return s.origin_stockpile_id == "HQ_STOCK"), "multi-source dispatch uses sorted own sources")
	var view: RefCounted = sim.command_view("ARMY_COMMAND")
	check(checks, view.local_stockpile("A_STOCK").is_empty() and view.local_stockpile("B_STOCK").is_empty(), "superior view cannot inspect subordinate inventories")
	var reports: Array = view.superior_need_reports()
	reports[0].reported_uncovered_need_quantity = 999
	check(checks, report_at(sim).reported_uncovered_need_quantity == 80, "detached report view cannot mutate authority")
	check(checks, not sim.execute({"type": "CreateShipment", "actor_entity_id": "ARMY_COMMAND", "origin_stockpile_id": "B_STOCK", "destination_stockpile_id": "A_STOCK", "resource_type_id": "AMMUNITION", "quantity": 1}).success, "superior cannot confiscate subordinate stock")
	var prior_ids: Dictionary = {}
	var causal := true
	var correlated := true
	for event in sim.events.all():
		if event.causation_event_id != null and not prior_ids.has(event.causation_event_id): causal = false
		prior_ids[event.event_id] = true
		if event.event_type in ["RESOURCE_ALLOCATION_SELECTED", "RESOURCE_ARBITRATION_NEED_EVALUATED", "SUPERIOR_RESOURCE_TRANSFER_DISPATCHED", "RESOURCE_ARBITRATION_COMPLETED"] and not str(event.correlation_id).begins_with("arbitration:"): correlated = false
	check(checks, causal and correlated, "arbitration events correlate with prior-event causation")
	check(checks, sim.decision_journal("ARMY_COMMAND")[0].selected_allocations.size() > 1 and not sim.decision_journal("ARMY_COMMAND")[0].shipment_ids.is_empty(), "single typed decision supports multiple selected outputs")
	data = Demo.definition()
	data.commands[1].ammunition_arbitration_enabled = true
	check(checks, not Simulation.new().initialize(data).success, "LOCAL superior arbitration flag rejected")
	data = Demo.definition()
	data.fronts = []
	data.commands[1].local_decision_front_id = null
	data.commands[2].local_decision_front_id = null
	data.tick_duration = 0.3
	check(checks, not Simulation.new().initialize(data).success, "arbitration requires exact reachable1s cadence")

static func _messages_and_lifecycle(checks: Array) -> void:
	for bad in [{"need_id": ""}, {"need_revision": 1.5}, {"planning_rate_milli": 900000001}, {"resource_type_id": "FOOD"}, {"destination_stockpile_id": "B_STOCK"}, {"observed_at_micro": 10000000}, {"requesting_command_id": "LOCAL_B"}, {"uncovered_need_quantity": -1}, {"available_quantity": Policy.MAX_SAFE, "confirmed_incoming_quantity": 1}]:
		var sim := fresh()
		var p := Demo.report()
		p.merge(bad, true)
		# Sender identity remains LOCAL_A even when testing a spoofed payload author.
		sim.execute({"type": "SendMessage", "actor_entity_id": "LOCAL_A", "sender_command_id": "LOCAL_A", "recipient_command_id": "ARMY_COMMAND", "message_type": "ESCALATION", "payload": p})
		sim.advance(10)
		check(checks, report_at(sim).is_empty() and funded(sim) == 0, "invalid delivered report rejected " + JSON.stringify(bad))
	var data := Demo.definition()
	data.commands[1].resource_resolution_enabled = true
	data.communication_edges = data.communication_edges.filter(func(e): return e.from_command_id != "LOCAL_B" and e.to_command_id != "LOCAL_B")
	data.communication_edges[0].latency_seconds = 0.0
	var sim := fresh(data)
	sim.advance(10)
	check(checks, funded(sim) == 80 and report_at(sim).need_revision == 1, "real same-boundary zero-latency escalation processed before arbitration")
	var update_count := events(sim, "RESOURCE_NEED_REPORT_UPDATE_SENT").size()
	sim.advance()
	check(checks, events(sim, "RESOURCE_NEED_REPORT_UPDATE_SENT").size() == update_count, "time-only tick sends no material update")
	NeedCases.edge(sim, "army_a", false)
	sim.advance()
	check(checks, sim.command_view("LOCAL_A").known_incoming().is_empty() and events(sim, "MESSAGE_FAILED").size() == 3, "failed allocation notices reveal no incoming despite real cargo")
	sim.advance(3)
	check(checks, rows(sim, "shipments").all(func(s): return s.state == "ARRIVED") and sim.command_view("LOCAL_A").known_incoming().is_empty(), "unnotified cargo arrives physically without phantom incoming")
	# An old report can legitimately fund real cargo after the local need resolved.
	data = Demo.definition()
	data.commands[1].resource_resolution_enabled = true
	data.communication_edges = data.communication_edges.filter(func(e): return e.from_command_id != "LOCAL_B" and e.to_command_id != "LOCAL_B")
	data.communication_edges[0].latency_seconds = 0.1
	data.logistics_edges[0].travel_time_seconds = 2.0
	sim = fresh(data)
	sim.advance(12)
	var need: Dictionary = NeedCases.first_need(sim)
	sim.execute({"type": "CreateResource", "stockpile_id": "A_STOCK", "resource_type_id": "AMMUNITION", "quantity": 200}, true)
	NeedCases.edge(sim, "a_army", false)
	sim.advance(8)
	check(checks, funded(sim) == 80 and NeedCases.first_need(sim).state == "RESOLVED" and report_at(sim).report_state == "ACTIVE", "resolved local reality with failed resolution still permits stale superior allocation")
	sim.advance(2)
	check(checks, NeedCases.first_need(sim).id == need.id and NeedCases.first_need(sim).state == "RESOLVED" and sim.command_view("LOCAL_A").known_incoming().size() == 3, "late allocation notification cannot resurrect resolved need")
	sim.advance(18)
	check(checks, NeedCases.first_need(sim).state == "RESOLVED" and rows(sim, "shipments").all(func(s): return s.state == "ARRIVED"), "resolved need does not erase real cargo eventual extra arrival")
	check(checks, NeedCases.conserved_prefixes(sim), "resolved-before-arrival failure every prefix conserved")
	check(checks, Exporter.export_run(sim, "res://artifacts/run_step106_resolved_in_transit").success and Exporter.replay_package("res://artifacts/run_step106_resolved_in_transit").success, "resolved-in-transit exact replay")
	data = Demo.definition(0)
	sim = fresh(data)
	Demo.send(sim, Demo.report())
	sim.advance(10)
	check(checks, sim.decision_journal("ARMY_COMMAND")[0].candidate_evaluations.all(func(e): return e.reason_code == "NO_SUPERIOR_STOCK"), "zero source stock journals explicit reason")
	data = Demo.definition()
	data.commands[0].directly_controlled_stockpile_ids = []
	data.stockpiles[0].owner_command_id = null
	sim = fresh(data)
	Demo.send(sim, Demo.report())
	sim.advance(10)
	check(checks, sim.decision_journal("ARMY_COMMAND").is_empty() and funded(sim) == 0, "no directly controlled source yields no arbitration")
	data = Demo.definition()
	sim = fresh(data)
	Demo.send(sim, Demo.report("LOCAL_B", 1, 40, 40, 4000, "CONSTRAINED", "fixture:B"))
	Demo.send(sim, Demo.report())
	sim.advance(10)
	var first_order: Array = sim.decision_journal("ARMY_COMMAND")[0].selected_allocations.map(func(a): return [a.need_id, a.stage_threshold_ms, a.quantity])
	var other := fresh(data)
	Demo.send(other, Demo.report())
	Demo.send(other, Demo.report("LOCAL_B", 1, 40, 40, 4000, "CONSTRAINED", "fixture:B"))
	other.advance(10)
	check(checks, Exporter.equivalent(first_order, other.decision_journal("ARMY_COMMAND")[0].selected_allocations.map(func(a): return [a.need_id, a.stage_threshold_ms, a.quantity])), "candidate allocation order independent of report send order")
	data = Demo.definition()
	data.communication_edges = data.communication_edges.filter(func(e): return e.id != "army_a")
	sim = fresh(data)
	Demo.send(sim, Demo.report())
	sim.advance(10)
	check(checks, funded(sim) == 80 and sim.command_view("LOCAL_A").known_incoming().is_empty() and events(sim, "SUPERIOR_ALLOCATION_NOTIFICATION_SENT").all(func(e): return not e.payload.success), "unroutable notification failure journaled while physical dispatch retained")
