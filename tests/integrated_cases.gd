extends RefCounted
const Demo = preload("res://debug/integrated_demo.gd")
const Audit = preload("res://tests/integrated_audit.gd")
const Needs = preload("res://tests/resource_resolution_cases.gd")
const Exporter = preload("res://kernel/run_exporter.gd")
const Simulation = preload("res://kernel/simulation.gd")

static func check(checks: Array, valid: bool, label: String) -> void:
	checks.append({"name": "107 / " + label, "passed": valid})

static func rows(sim: RefCounted, table: String) -> Array:
	return Needs.rows(sim, table)

static func events(sim: RefCounted, type: String) -> Array:
	return Needs.events(sim, type)

static func run() -> Dictionary:
	var checks: Array = []
	var completed := Demo.run()
	check(checks, completed.success, "fixed fixture completes")
	if not completed.success: return {"success": false, "checks": checks, "failures": ["107 initialization"], "error": completed}
	var sim: RefCounted = completed.details.simulation
	var audit := Audit.run(sim)
	check(checks, sim.world.clock().tick_index == 250 and sim.time() == 25.0, "25seconds tick250 without early exit")
	check(checks, sim.inputs.is_empty() and events(sim, "INPUT_RECEIVED").is_empty(), "zero external inputs including no EndRun")
	check(checks, sim.initial_world.resource_reservations.is_empty() and sim.initial_world.shipments.size() == 1, "initial cargo with zero preexisting reservations")
	check(checks, sim.initial_world.ledger.AMMUNITION.created == 368 and sim.initial_world.shipments.STRATEGIC_RESUPPLY.quantity == 60, "initial308stock plus60cargo accounted once")
	for pair in [["LOCAL_A", "PRESS"], ["LOCAL_B", "HOLD"], ["LOCAL_C", "REDUCE_ACTIVITY"]]:
		var journal: Array = sim.decision_journal(pair[0])
		check(checks, journal.size() == 25 and journal[0].selected_action == pair[1] and journal[0].selected_at_micro == 1000000, pair[0] + " expected first decision and25localcycles")
	var c_need: Dictionary = rows(sim, "resource_needs").filter(func(n): return n.command_id == "LOCAL_C")[0]
	check(checks, c_need.state == "ACTIVE", "C evolving need remains legitimately active")
	var self_ships := rows(sim, "shipments").filter(func(s): return s.origin_stockpile_id == "C_LOCAL_RESERVE")
	var peer_ships := rows(sim, "shipments").filter(func(s): return s.origin_stockpile_id == "B_LOCAL_RESERVE" and s.destination_stockpile_id == "C_FRONT_STOCK")
	check(checks, self_ships.size() == 1 and self_ships[0].quantity == 8 and self_ships[0].state == "ARRIVED", "C real own8shipment arrives")
	check(checks, peer_ships.size() == 1 and peer_ships[0].quantity == 30 and peer_ships[0].state == "ARRIVED", "B real peer30shipment arrives")
	var coords := rows(sim, "peer_coordinations").filter(func(c): return c.need_id == c_need.id)
	check(checks, coords.size() == 2 and coords[0].peer_command_id == "LOCAL_A" and coords[0].offered_quantity == 0 and coords[1].peer_command_id == "LOCAL_B", "C deterministic peerAdecline thenBoffer")
	var self_dispatch: Dictionary = events(sim, "SHIPMENT_DISPATCHED").filter(func(e): return e.subject_entity_id == self_ships[0].id)[0]
	var peer_dispatch: Dictionary = events(sim, "SHIPMENT_DISPATCHED").filter(func(e): return e.subject_entity_id == peer_ships[0].id)[0]
	var first_request: Dictionary = events(sim, "MESSAGE_SENT").filter(func(e): return e.subject_entity_id == coords[0].request_message_id)[0]
	var escalation_sent: Dictionary = events(sim, "MESSAGE_SENT").filter(func(e): return e.subject_entity_id == c_need.escalation_message_id)[0]
	check(checks, self_dispatch.event_id < first_request.event_id and peer_dispatch.event_id < escalation_sent.event_id, "C selfhelp thenpeers thenescalation causal sequence")
	check(checks, rows(sim, "resource_needs").any(func(n): return n.command_id == "LOCAL_A") and rows(sim, "resource_needs").any(func(n): return n.command_id == "LOCAL_B"), "A andB needs emerge from normal burn")
	var arbitrations: Array = sim.decision_journal("OPERATIONAL_COMMAND")
	check(checks, not arbitrations.is_empty() and not events(sim, "SUPERIOR_RESOURCE_TRANSFER_DISPATCHED").is_empty(), "real superior allocations")
	var scarce: Array = []
	for decision in arbitrations:
		var active: Array = decision.input_reports.filter(func(r): return r.report_state == "ACTIVE")
		var actionable: Array = active.filter(func(r): return r.reported_planning_rate_milli > 0 and r.reported_uncovered_need_quantity > 0)
		var sum := 0
		for report in actionable: sum += int(report.reported_uncovered_need_quantity)
		if actionable.size() >= 2 and int(decision.usable_stock_before) > 0 and int(decision.usable_stock_before) < sum: scarce.append(decision)
	check(checks, arbitrations.any(func(d): return d.input_reports.filter(func(r): return r.report_state == "ACTIVE").size() >= 2), "simultaneous multiple active delivered reports")
	check(checks, not scarce.is_empty(), "positive but insufficient supply for2plus actionablereports")
	check(checks, scarce.any(func(d): return d.started_at_micro == 15000000 and d.usable_stock_before == 60 and d.selected_allocations.size() == 2 and d.selected_allocations[0].quantity == 51 and d.selected_allocations[1].quantity == 9), "t15 scarce60 stagedC51/B9 unequal")
	var strategic: Dictionary = sim.world.get_shipment("STRATEGIC_RESUPPLY")
	check(checks, strategic.state == "ARRIVED" and strategic.arrived_at == 15.0 and strategic.destination_stockpile_id == "OP_HQ_STOCK", "initial strategic60physically arrives15seconds")
	check(checks, audit.posture_timeline.any(func(t): return t.front_id == "FRONT_A" and t.previous == "PRESS" and t.value != "PRESS") and audit.posture_timeline.any(func(t): return t.front_id == "FRONT_C" and t.previous == "REDUCE_ACTIVITY" and t.value == "HOLD"), "autonomous AandC exit initial nonHOLD postures")
	var resolved := rows(sim, "resource_needs").filter(func(n): return n.state == "RESOLVED")
	check(checks, resolved.size() == 1 and resolved[0].command_id == "LOCAL_A" and resolved[0].available_quantity == 66 and resolved[0].target_stock_quantity == 64 and resolved[0].planning_rate_milli == 3200 and resolved[0].last_shortage == 0, "amendedA dynamic lifecycle closes at observed66 target64")
	check(checks, rows(sim, "shipments").all(func(s): return s.destination_stockpile_id != "A_FRONT_STOCK"), "Aclosure honestly identified as targetrecalculation without resupply")
	var c_impacts: Array = audit.physical_impacts.filter(func(i): return i.front_id == "FRONT_C")
	for origin in ["C_LOCAL_RESERVE", "B_LOCAL_RESERVE", "OP_HQ_STOCK"]:
		var impact_found := false
		for impact in c_impacts:
			if impact.before_available == null or impact.after_available <= impact.before_available or impact.need_event_ids.is_empty() or impact.decision_id == null: continue
			if impact.arrivals.any(func(a): return sim.world.get_shipment(a.shipment_id).origin_stockpile_id == origin): impact_found = true
		check(checks, impact_found, "physical " + origin + " aid increases C observedstock with linkedneed/decision reevaluation")
	check(checks, not audit.causal_chain_C.is_empty() and not audit.causal_chain_C.arbitration_outputs.is_empty() and audit.causal_chain_C.local_decision_id != null, "completeC structural causalchain from observation through arbitration")
	check(checks, audit.causal_chain_C.arbitration_outputs.all(func(o): return o.shipments.all(func(s): return not s.arrival_impacts.is_empty() and s.notification_message_id != null and not sim.world.get_entity("known_transfers", s.known_transfer_id).is_empty())), "Csuperior cargo linkednotification incoming arrival observation reevaluation")
	check(checks, audit.valid_causation, "all causal references point to earlier events")
	check(checks, Needs.conserved_prefixes(sim), "all3607authoritativeprefixes claims stock cargo ledger and complete reconstruction")
	check(checks, sim.audit().AMMUNITION.created == 368 and sim.audit().AMMUNITION.consumed == 322 and sim.audit().AMMUNITION.stockpiles == 46 and sim.audit().AMMUNITION.in_transit == 0, "finalexact368=322consumed+46stock")
	_privacy_and_stability(sim, checks)
	_initial_validation(sim, checks)
	check(checks, Exporter.export_run(sim, "res://artifacts/run_step107").success, "full unchanged integrated package exported")
	var bytes := FileAccess.get_file_as_bytes("res://artifacts/run_step107/events.jsonl").size()
	check(checks, events(sim, "RESOURCE_CREATED").is_empty() and events(sim, "FRONT_ENEMY_PRESSURE_CHANGED").is_empty() and events(sim, "FRONT_FRIENDLY_STRENGTH_CHANGED").is_empty(), "no resourcecreation/pressure/strengthscript")
	var failures: Array = []
	for item in checks:
		if not item.passed: failures.append(item.name)
	return {"success": failures.is_empty(), "checks": checks, "failures": failures, "end_tick": sim.world.clock().tick_index, "event_count": sim.events.count(), "events_jsonl_bytes": bytes, "input_count": sim.inputs.size(), "audit": audit, "scarce_arbitrations": scarce, "arbitration_journal": arbitrations, "needs": rows(sim, "resource_needs"), "coordinations": rows(sim, "peer_coordinations"), "shipments": rows(sim, "shipments"), "ledger": sim.audit()}

static func _privacy_and_stability(sim: RefCounted, checks: Array) -> void:
	for command in ["LOCAL_A", "LOCAL_B", "LOCAL_C"]:
		var view: RefCounted = sim.command_view(command)
		check(checks, view.information().all(func(i): return i.owner_command_id == command and i.subject_entity_id == "FRONT_" + command.right(1)) and view.inbox().all(func(m): return m.recipient_command_id == command and m.state == "DELIVERED") and view.superior_need_reports().is_empty(), command + " private observations inbox and no superior reports")
		check(checks, view.controlled_stockpiles().all(func(s): return s.owner_command_id == command) and view.local_stockpile("OP_HQ_STOCK").is_empty(), command + " own inventory only")
		var valid := true
		for decision in sim.decision_journal(command):
			var batch: Dictionary = sim.world.get_entity("observation_batches", decision.observation_batch_id)
			if decision.belief_record_ids.size() != 11 or not batch.complete: valid = false
			for id in decision.belief_record_ids:
				var belief: Dictionary = sim.world.get_entity("information_records", id)
				if belief.owner_command_id != command or belief.subject_entity_id != batch.front_id or id not in batch.record_ids.values(): valid = false
		check(checks, valid, command + " all25decisions exact private complete11beliefs")
	var op: RefCounted = sim.command_view("OPERATIONAL_COMMAND")
	check(checks, op.controlled_stockpiles().size() == 1 and op.controlled_stockpiles()[0].id == "OP_HQ_STOCK" and op.local_stockpile("C_FRONT_STOCK").is_empty(), "superior own exact inventory excludes foreign fronts")
	check(checks, op.superior_need_reports().all(func(r): return sim.world.get_entity("messages", r.report_message_id).state == "DELIVERED"), "superior current reports derived only from deliveredmessages")
	var valid_reports := true
	for decision in sim.decision_journal("OPERATIONAL_COMMAND"):
		for report in decision.input_reports:
			var message: Dictionary = sim.world.get_entity("messages", report.report_message_id)
			if message.state != "DELIVERED" or message.recipient_command_id != "OPERATIONAL_COMMAND" or message.delivery_time * 1000000 > decision.started_at_micro: valid_reports = false
	check(checks, valid_reports, "every arbitration snapshots alreadydelivered exactreportrevision")
	var valid_known := true
	for known in rows(sim, "known_transfers"):
		var ship: Dictionary = sim.world.get_shipment(known.shipment_id)
		if ship.requested_by_command_id != known.command_id:
			var message: Dictionary = sim.world.get_entity("messages", known.source_message_id)
			if message.state != "DELIVERED" or message.recipient_command_id != known.command_id or message.payload.shipment_id != ship.id: valid_known = false
	check(checks, valid_known, "every foreign incoming has delivered namednotification no telepathy")
	check(checks, rows(sim, "resource_reservations").all(func(r): return r.state != "ACTIVE"), "no active reservation leak at25s")
	check(checks, rows(sim, "peer_coordinations").all(func(c): return c.requester_status == "DONE" and c.donor_status != "RESERVED"), "all conversations completed no outstandingoffer leak")
	check(checks, rows(sim, "messages").all(func(m): return m.state in ["DELIVERED", "FAILED"] or m.delivery_tick > 250), "only legitimate posthorizon messages remain intransit")
	check(checks, rows(sim, "shipments").all(func(s): return s.state == "ARRIVED" and (s.reservation_id == null or not sim.world.get_entity("resource_reservations", s.reservation_id).is_empty())), "all cargo arrived no orphan reservationrefs")
	var unique := true
	for need in rows(sim, "resource_needs"):
		if need.state == "ACTIVE" and rows(sim, "resource_needs").filter(func(n): return n.state == "ACTIVE" and n.command_id == need.command_id).size() != 1: unique = false
	check(checks, unique and rows(sim, "resource_needs").size() == 4, "bounded4needs atmost1active percommand")
	var sent_revisions: Dictionary = {}
	var no_spam := true
	for message in rows(sim, "messages"):
		if message.message_type == "ESCALATION":
			var key: String = message.payload.need_id + ":" + str(message.payload.get("need_revision", message.payload.get("final_revision")))
			if sent_revisions.has(key): no_spam = false
			sent_revisions[key] = true
	check(checks, no_spam, "no duplicate escalation/update same needrevision")
	check(checks, rows(sim, "peer_coordinations").all(func(c): return events(sim, "MESSAGE_SENT").filter(func(e): return e.subject_entity_id == c.request_message_id).size() == 1), "one request per peerconversation no outstandingduplicate")
	var funded: Dictionary = {}
	var caps: Dictionary = {}
	for decision in sim.decision_journal("OPERATIONAL_COMMAND"):
		for r in decision.input_reports: caps[r.id + ":" + str(r.need_revision)] = r.get("reported_uncovered_need_quantity", 0)
	for ship in rows(sim, "shipments"):
		if not ship.has("arbitration_id"): continue
		var key: String = "need-report:OPERATIONAL_COMMAND:" + ship.need_id + ":" + str(ship.need_revision)
		funded[key] = funded.get(key, 0) + ship.quantity
	var capped := true
	for key in funded:
		if funded[key] > caps.get(key, -1): capped = false
	check(checks, capped, "every revision cumulative actualdispatch within deliveredcap")
	var closed: Dictionary = {}
	var quiet := true
	for event in sim.events.all():
		if event.event_type == "RESOURCE_NEED_RESOLVED": closed[event.subject_entity_id] = true
		if event.event_type == "MESSAGE_SENT":
			var message: Dictionary = sim.world.get_entity("messages", event.subject_entity_id)
			if message.payload.get("need_id") in closed and message.payload.get("subtype") in ["AMMO_TRANSFER_REQUEST", "AMMO_NEED_ESCALATION"]: quiet = false
	check(checks, quiet, "resolvedneed no new requests/escalations")
	check(checks, rows(sim, "decisions").all(func(d): return not d.has("reward") and not d.has("grade")), "descriptive decisions no reward or grades")

static func _initial_validation(sim: RefCounted, checks: Array) -> void:
	for bad in [{"quantity": -1}, {"quantity": 0}, {"quantity": 1.5}, {"resource_type_id": "FOOD"}, {"origin_stockpile_id": "MISSING"}, {"destination_stockpile_id": "MISSING"}, {"route_edge_ids": []}, {"route_edge_ids": ["hq_A"]}, {"id": "LOCAL_A"}, {"id": "runtime:fake"}]:
		var data := Demo.definition()
		data.initial_in_transit_shipments[0].merge(bad, true)
		check(checks, not Simulation.new().initialize(data).success, "invalid initialcargo rejected " + JSON.stringify(bad))
	for field in ["state", "reservation_id", "edge_progress_seconds"]:
		var initial: Dictionary = sim.initial_world.duplicate(true)
		initial.shipments.STRATEGIC_RESUPPLY[field] = {"state": "ARRIVED", "reservation_id": "fake", "edge_progress_seconds": 1.0}[field]
		check(checks, not Simulation.new().initialize_snapshot(initial).success, "noncanonical initialshipment snapshot rejected " + field)
