extends "res://kernel/service.gd"
const Policy = preload("res://kernel/ammunition_arbitration_policy.gd")
const Clock = preload("res://kernel/clock.gd")
const Logistics = preload("res://kernel/logistics_service.gd")
const Router = preload("res://kernel/router.gd")
const Communication = preload("res://kernel/communication_service.gd")
const Resolution = preload("res://kernel/resource_resolution_service.gd")

func enabled(command: String) -> bool:
	return world.get_command(command).get("ammunition_arbitration_enabled", false)

func scope(command: String, arbitration: String, cause: Variant, decision: Variant = null) -> void:
	sim.context = {"actor_entity_id": command, "source_system": "RESOURCE_ARBITRATION", "input_id": arbitration, "arbitration_id": arbitration, "decision_id": decision, "causation_event_id": cause, "privileged": false}

func integer(value: Variant, maximum := Policy.MAX_SAFE) -> bool:
	return (value is int or value is float) and value >= 0 and value <= maximum and value == floor(value)

# Uses actual delivered envelopes and hierarchy/assignment authority, never front metrics.
func receive_report(message: Dictionary) -> void:
	var p: Dictionary = message.payload
	var superior: String = message.recipient_command_id
	if not enabled(superior) or message.message_type != "ESCALATION" or message.state != "DELIVERED": return
	var sender: Dictionary = world.get_command(message.sender_command_id)
	if sender.get("command_level") != "LOCAL" or sender.get("superior_command_id") != superior or p.get("requesting_command_id") != sender.id or not p.get("need_id") is String or p.need_id.is_empty(): return
	var resolved: bool = p.get("subtype") == "AMMO_NEED_RESOLVED"
	if p.get("subtype") not in ["AMMO_NEED_ESCALATION", "AMMO_NEED_UPDATE", "AMMO_NEED_RESOLVED"]: return
	var revision: Variant = p.get("final_revision") if resolved else p.get("need_revision")
	if not integer(revision) or revision < 1: return
	var id: String = "need-report:" + superior + ":" + p.need_id
	var prior: Dictionary = world.get_entity("superior_need_reports", id)
	if not prior.is_empty() and prior.requesting_command_id != sender.id: return
	scope(superior, p.need_id, world.last_event(message.id))
	if not prior.is_empty() and revision <= prior.need_revision:
		sim.commit("SUPERIOR_NEED_REPORT_STALE_IGNORED", [], {"report_id": id, "source_message_id": message.id, "reported_revision": revision, "known_revision": prior.need_revision}, id)
		return
	var report: Dictionary = prior.duplicate(true)
	if not resolved:
		for key in ["available_quantity", "confirmed_incoming_quantity", "uncovered_need_quantity", "target_stock_quantity", "planning_rate_milli", "observed_at_micro"]:
			if not integer(p.get(key)): return
		if p.planning_rate_milli > 900000000 or p.uncovered_need_quantity > 18000000 or p.target_stock_quantity > 18000000 or p.confirmed_incoming_quantity > Policy.MAX_SAFE - int(p.available_quantity): return
		if p.observed_at_micro > Clock.units(sim.time()) or p.get("urgency") not in ["CRITICAL", "CONSTRAINED", "REFILL"] or not p.get("front_id") is String or not p.get("observation_batch_id") is String or not p.get("destination_stockpile_id") is String: return
		# Declared direct ownership validates the destination; no subordinate inventory read.
		if p.destination_stockpile_id not in sender.directly_controlled_stockpile_ids or not world.get_stockpile(p.destination_stockpile_id).get("enabled", false): return
		for key in ["available_quantity", "confirmed_incoming_quantity", "uncovered_need_quantity", "target_stock_quantity", "planning_rate_milli"]:
			report["reported_" + key] = int(p[key])
		report.front_id = p.front_id
		report.destination_stockpile_id = p.destination_stockpile_id
		report.resource_type_id = p.get("resource_type_id")
		if report.resource_type_id != "AMMUNITION": return
		report.urgency = p.urgency
		report.source_observation_batch_id = p.observation_batch_id
		report.source_observed_at_micro = int(p.observed_at_micro)
	report.id = id
	report.need_id = p.need_id
	report.superior_command_id = superior
	report.requesting_command_id = sender.id
	report.need_revision = int(revision)
	report.report_message_id = message.id
	report.report_received_at_micro = Clock.units(sim.time())
	report.report_state = "RESOLVED" if resolved else "ACTIVE"
	sim.commit("SUPERIOR_NEED_REPORT_RESOLVED" if resolved else "SUPERIOR_NEED_REPORT_RECEIVED", [change("superior_need_reports", report)], {"source_message_id": message.id, "need_revision": revision}, id)

func receive_notification(message: Dictionary) -> void:
	var p: Dictionary = message.payload
	if message.message_type != "ORDER" or p.get("subtype") != "AMMO_ALLOCATION_DISPATCHED": return
	var owner: String = message.recipient_command_id
	var parent: Variant = world.get_command(owner).get("superior_command_id")
	if parent != message.sender_command_id or p.get("superior_command_id") != parent: return
	for key in ["need_id", "shipment_id", "arbitration_id", "decision_id", "destination_stockpile_id", "source_stockpile_id"]:
		if not p.get(key) is String: return
	if not integer(p.get("quantity")) or p.quantity <= 0 or not integer(p.get("need_revision_used")): return
	var shipment: Dictionary = world.get_shipment(p.shipment_id)
	# Notification authenticity checks transport identity only. No hidden shipment scan.
	if shipment.get("arbitration_id") != p.arbitration_id or shipment.get("decision_id") != p.decision_id or shipment.get("need_id") != p.need_id or shipment.get("requested_by_command_id") != parent or shipment.get("destination_stockpile_id") != p.destination_stockpile_id or shipment.get("origin_stockpile_id") != p.source_stockpile_id or shipment.get("quantity") != p.quantity: return
	if p.destination_stockpile_id not in world.get_command(owner).directly_controlled_stockpile_ids: return
	var resolution := Resolution.new(sim)
	resolution.scope(owner, p.need_id, world.last_event(message.id))
	sim.commit("SUPERIOR_ALLOCATION_NOTICE_RECEIVED", [], {"source_message_id": message.id, "arbitration_id": p.arbitration_id, "decision_id": p.decision_id, "shipment_id": shipment.id, "shipment_state": shipment.state}, p.need_id)
	if shipment.state == "IN_TRANSIT":
		resolution.register_transfer(p.need_id, owner, shipment.id, int(p.quantity), p.destination_stockpile_id, null, message.id)

# Material revision tracking is separate from need arithmetic, so sending cannot
# create another revision. Failed transport never writes the superior projection.
func update_reports() -> void:
	for id in world.ids("resource_needs"):
		var need: Dictionary = world.get_entity("resource_needs", id)
		var parent: Variant = world.get_command(need.command_id).get("superior_command_id")
		if not parent is String or not enabled(parent) or need.get("escalation_message_id") == null: continue
		var sent_revision: int = need.get("last_superior_report_revision", 0)
		if sent_revision >= int(need.revision): continue
		var resolution := Resolution.new(sim)
		resolution.scope(need.command_id, need.id, world.last_event(need.id))
		var payload: Dictionary = resolution.snapshot_payload(need)
		payload.subtype = "AMMO_NEED_RESOLVED" if need.state == "RESOLVED" else "AMMO_NEED_UPDATE"
		if need.state == "RESOLVED": payload.final_revision = need.revision
		var result: Dictionary = resolution.send(need.command_id, parent, "ESCALATION", payload)
		need.last_superior_report_revision = need.revision
		need.last_superior_update_message_id = result.entity_id
		sim.commit("RESOURCE_NEED_REPORT_UPDATE_SENT", [change("resource_needs", need)], {"success": result.success, "error_code": result.error_code, "message_id": result.entity_id, "need_revision": need.revision}, need.id)

func sources(view: RefCounted) -> Array:
	return view.controlled_stockpiles().filter(func(s): return s.quantities.has("AMMUNITION"))

func usable(stockpiles: Array) -> int:
	# Saturated availability is used only for zero/exhaustion decisions. Each
	# dispatch uses its exact source quantity. Journals retain the exact total below.
	var total := 0
	for stock in stockpiles:
		if enabled_stockpile(stock.id).is_empty(): continue
		var s: Dictionary = world.get_stockpile(stock.id)
		total += mini(Policy.MAX_SAFE - total, int(s.quantities.get("AMMUNITION", 0)) - int(s.reserved.get("AMMUNITION", 0)))
	return total

func exact_usable(stockpiles: Array) -> Variant:
	var digits := "0"
	for stock in stockpiles:
		if enabled_stockpile(stock.id).is_empty(): continue
		var s: Dictionary = world.get_stockpile(stock.id)
		var addend := str(int(s.quantities.get("AMMUNITION", 0)) - int(s.reserved.get("AMMUNITION", 0)))
		var left := digits.length() - 1
		var right := addend.length() - 1
		var carry := 0
		var result := ""
		while left >= 0 or right >= 0 or carry > 0:
			var digit := carry + (int(digits[left]) if left >= 0 else 0) + (int(addend[right]) if right >= 0 else 0)
			result = str(digit % 10) + result
			carry = digit / 10
			left -= 1
			right -= 1
		digits = result
	if digits.length() < 16 or (digits.length() == 16 and digits <= str(Policy.MAX_SAFE)): return int(digits)
	# Decimal text preserves a total larger than the authoritative JSON safe range.
	return digits

func spent(report: Dictionary) -> int:
	var id: String = "allocation-funding:" + report.id + ":" + str(report.need_revision)
	return int(world.get_entity("superior_revision_funding", id).get("quantity", 0))

func emit(type: String, decision: Dictionary, payload: Dictionary = {}, subject: Variant = null) -> String:
	var event: String = sim.commit(type, [change("decisions", decision)], payload, decision.id if subject == null else subject, null, decision.arbitration_id)
	sim.context.causation_event_id = event
	return event

func evaluate(command: String, cause: Variant) -> void:
	var view: RefCounted = sim.command_view(command)
	var reports: Array = view.superior_need_reports()
	var stockpiles := sources(view)
	if stockpiles.is_empty() or not reports.any(func(r): return r.report_state == "ACTIVE"): return
	var arbitration: String = sim.entity_id("arbitration")
	scope(command, arbitration, cause)
	# The first event allocates the arbitration ID before generating the decision ID.
	var started: String = sim.commit("RESOURCE_ARBITRATION_STARTED", [change("resource_arbitrations", {"id": arbitration, "superior_command_id": command, "started_at_micro": Clock.units(sim.time()), "state": "STARTED"})], {}, arbitration)
	var decision_id: String = sim.entity_id("decision")
	scope(command, arbitration, started, decision_id)
	var decision := {"id": decision_id, "decision_id": decision_id, "decision_type": "RESOURCE_ARBITRATION", "arbitration_id": arbitration, "command_id": command, "started_at_micro": Clock.units(sim.time()), "completed_at_micro": null, "state": "STARTED", "input_reports": reports.duplicate(true), "source_stockpile_ids": stockpiles.map(func(s): return s.id), "usable_stock_before": exact_usable(stockpiles), "candidate_evaluations": [], "selected_allocations": [], "shipment_ids": []}
	emit("DECISION_STARTED", decision)
	var projections: Dictionary = {}
	for report in reports:
		if report.report_state == "ACTIVE": projections[report.id] = int(report.reported_available_quantity) + int(report.reported_confirmed_incoming_quantity)
	for threshold in Policy.THRESHOLDS:
		var ordered: Array = reports.duplicate(true)
		for report in ordered: report.projected_stock = projections.get(report.id, 0)
		ordered.sort_custom(Policy.before)
		for report in ordered:
			var remaining := 0 if report.report_state != "ACTIVE" else maxi(0, int(report.reported_uncovered_need_quantity) - spent(report))
			var rate: int = report.get("reported_planning_rate_milli", 0)
			var projected: int = projections.get(report.id, 0)
			var required := Policy.required_stock(rate, threshold)
			var deficit := maxi(0, required - projected)
			var desired := mini(deficit, remaining)
			var evaluation := {"report_id": report.id, "report_message_id": report.report_message_id, "need_id": report.need_id, "need_revision": report.need_revision, "requesting_command_id": report.requesting_command_id, "stage_threshold_ms": threshold, "urgency": report.get("urgency", "REFILL"), "reported_projected_stock": projected, "planning_rate_milli": rate, "required_stock": required, "stage_deficit": deficit, "remaining_reported_need": remaining, "selected_quantity": 0, "dispatched_quantity": 0, "shipment_ids": [], "reason_code": "STAGE_ALREADY_MET", "dispatch_results": []}
			if report.report_state != "ACTIVE": evaluation.reason_code = "REPORT_RESOLVED"
			elif rate == 0: evaluation.reason_code = "ZERO_PLANNING_RATE"
			elif remaining == 0: evaluation.reason_code = "NO_REMAINING_REPORTED_NEED"
			elif desired > 0:
				if usable(stockpiles) == 0:
					evaluation.reason_code = "LOWER_PRIORITY_THAN_EXHAUSTED_STOCK" if decision.shipment_ids.size() > 0 else "NO_SUPERIOR_STOCK"
				else: allocate(report, desired, stockpiles, decision, evaluation)
			projections[report.id] = projected + int(evaluation.dispatched_quantity)
			evaluation.usable_stock_remaining = exact_usable(stockpiles)
			decision.candidate_evaluations.append(evaluation)
			emit("RESOURCE_ARBITRATION_NEED_EVALUATED", decision, evaluation, report.id)
	decision.completed_at_micro = Clock.units(sim.time())
	decision.state = "COMPLETED"
	decision.usable_stock_remaining = exact_usable(stockpiles)
	var completed: String = emit("DECISION_COMPLETED", decision)
	sim.commit("RESOURCE_ARBITRATION_COMPLETED", [change("resource_arbitrations", {"id": arbitration, "superior_command_id": command, "decision_id": decision_id, "started_at_micro": decision.started_at_micro, "completed_at_micro": decision.completed_at_micro, "state": "COMPLETED"})], {"decision_id": decision_id, "usable_stock_remaining": decision.usable_stock_remaining}, arbitration, completed, arbitration)

func allocate(report: Dictionary, desired: int, stockpiles: Array, decision: Dictionary, evaluation: Dictionary) -> void:
	evaluation.reason_code = "NO_LOGISTICS_ROUTE"
	for old_stock in stockpiles:
		if desired <= 0: break
		var stock: Dictionary = enabled_stockpile(old_stock.id)
		if stock.is_empty(): continue
		var quantity := mini(desired, int(stock.quantities.get("AMMUNITION", 0)) - int(stock.reserved.get("AMMUNITION", 0)))
		if quantity <= 0: continue
		if not sim.authorized(decision.command_id, stock.id):
			evaluation.reason_code = "UNAUTHORIZED_SOURCE"
			continue
		var destination: Dictionary = enabled_stockpile(report.destination_stockpile_id)
		if destination.is_empty() or not Router.find(world, stock.location_id, destination.location_id).success: continue
		var selection := {"arbitration_id": decision.arbitration_id, "decision_id": decision.id, "need_id": report.need_id, "need_revision": report.need_revision, "report_id": report.id, "report_message_id": report.report_message_id, "quantity": quantity, "source_stockpile_id": stock.id, "destination_stockpile_id": report.destination_stockpile_id, "stage_threshold_ms": evaluation.stage_threshold_ms}
		evaluation.selected_quantity += quantity
		decision.selected_allocations.append(selection)
		emit("RESOURCE_ALLOCATION_SELECTED", decision, selection, report.id)
		sim.context.allocation_need_id = report.need_id
		sim.context.need_revision = report.need_revision
		var created: Dictionary = Logistics.new(sim).create_shipment(stock.id, report.destination_stockpile_id, "AMMUNITION", quantity, decision.command_id)
		var dispatched: Dictionary = created
		if created.success:
			sim.context.causation_event_id = world.last_event(created.entity_id)
			dispatched = Logistics.new(sim).dispatch(created.entity_id)
			if not dispatched.success: Logistics.new(sim).cancel(created.entity_id)
		evaluation.dispatch_results.append({"success": dispatched.success, "error_code": dispatched.error_code, "shipment_id": created.entity_id})
		if not dispatched.success:
			evaluation.reason_code = "DISPATCH_FAILED"
			continue
		evaluation.reason_code = "DISPATCHED"
		evaluation.dispatched_quantity += quantity
		evaluation.shipment_ids.append(created.entity_id)
		decision.shipment_ids.append(created.entity_id)
		desired -= quantity
		var funding_id: String = "allocation-funding:" + report.id + ":" + str(report.need_revision)
		var funding := {"id": funding_id, "report_id": report.id, "need_id": report.need_id, "need_revision": report.need_revision, "quantity": spent(report) + quantity}
		var cause: String = sim.commit("SUPERIOR_RESOURCE_TRANSFER_DISPATCHED", [change("superior_revision_funding", funding)], {"decision_id": decision.id, "need_id": report.need_id, "need_revision": report.need_revision, "shipment_id": created.entity_id, "quantity": quantity}, created.entity_id, world.last_event(created.entity_id), decision.arbitration_id)
		sim.context.causation_event_id = cause
		var notification: Dictionary = Communication.new(sim).send(decision.command_id, report.requesting_command_id, "ORDER", {"subtype": "AMMO_ALLOCATION_DISPATCHED", "arbitration_id": decision.arbitration_id, "decision_id": decision.id, "need_id": report.need_id, "need_revision_used": report.need_revision, "shipment_id": created.entity_id, "quantity": quantity, "source_stockpile_id": stock.id, "destination_stockpile_id": report.destination_stockpile_id, "superior_command_id": decision.command_id})
		sim.context.causation_event_id = sim.commit("SUPERIOR_ALLOCATION_NOTIFICATION_SENT", [], {"shipment_id": created.entity_id, "message_id": notification.entity_id, "success": notification.success, "error_code": notification.error_code}, created.entity_id, cause, decision.arbitration_id)

func step(cause: Variant) -> void:
	var previous: Dictionary = sim.context
	if Clock.units(sim.time()) % 1000000 == 0:
		for id in world.ids("commands"):
			if enabled(id) and world.get_command(id).enabled: evaluate(id, cause)
	sim.context = previous
