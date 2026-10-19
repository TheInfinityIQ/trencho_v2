extends RefCounted

const Simulation = preload("res://kernel/simulation.gd")
const Demo = preload("res://debug/demo.gd")
const Exporter = preload("res://kernel/run_exporter.gd")

static func run() -> Dictionary:
	var checks: Array = []
	_correlation(checks, false)
	_correlation(checks, true)
	_failure(checks, false)
	_failure(checks, true)
	var failures: Array = []
	for item in checks:
		if not item.passed:
			failures.append(item.name)
	return {"checks": checks, "failures": failures, "success": failures.is_empty()}

static func check(checks: Array, condition: bool, name: String) -> void:
	checks.append({"name": name, "passed": condition})

static func event_for(sim: RefCounted, type: String, subject: String) -> Dictionary:
	for event in sim.events.all():
		if event.event_type == type and event.subject_entity_id == subject:
			return event
	return {}

static func _correlation(checks: Array, zero_latency: bool) -> void:
	var label := "closeout correlation / zero latency" if zero_latency else "closeout correlation / delayed"
	var definition: Dictionary = Demo.definition()
	if zero_latency:
		definition.communication_edges[1].latency_seconds = 0
	var sim := Simulation.new()
	var initialized: Dictionary = sim.initialize(definition, 101, "correlation")
	check(checks, initialized.success, label + " initializes")
	if not initialized.success:
		return
	var messages: Array = []
	for index in range(2):
		var fact := {"subject_entity_id": "A_STOCK", "fact_key": "closeout_" + str(index), "value": 30 + index, "observed_at": sim.time(), "confidence": 0.8}
		var sent: Dictionary = sim.execute({"type": "SendMessage", "sender_command_id": "LOCAL_A", "recipient_command_id": "ARMY_COMMAND", "message_type": "REPORT", "payload": {"facts": [fact]}}, true)
		check(checks, sent.success, label + " send " + str(index))
		if not sent.success:
			return
		messages.append(sent.entity_id)
	if not zero_latency:
		check(checks, sim.command_view("ARMY_COMMAND").information().is_empty(), label + " no ingestion before delivery")
		sim.advance(3)
	var correlations: Array = []
	for index in range(messages.size()):
		var id: String = messages[index]
		var sent := event_for(sim, "MESSAGE_SENT", id)
		var delivered := event_for(sim, "MESSAGE_DELIVERED", id)
		var belief: Dictionary = sim.command_view("ARMY_COMMAND").current_belief("A_STOCK", "closeout_" + str(index), sim.time())
		var ingested: Dictionary = event_for(sim, "INFORMATION_INGESTED", belief.get("id", ""))
		var events_exist := not sent.is_empty() and not delivered.is_empty() and not ingested.is_empty()
		check(checks, events_exist, label + " complete chain " + str(index))
		if not events_exist:
			continue
		check(checks, sent.correlation_id != null and sent.correlation_id == delivered.correlation_id and delivered.correlation_id == ingested.correlation_id, label + " correlation retained " + str(index))
		check(checks, delivered.causation_event_id == sent.event_id and ingested.causation_event_id == delivered.event_id and belief.causation_event_id == delivered.event_id, label + " immediate causal parents " + str(index))
		check(checks, belief.value == 30 + index and belief.source_message_id == id and belief.source_command_id == "LOCAL_A", label + " belief semantics unchanged " + str(index))
		correlations.append(sent.correlation_id)
	check(checks, correlations.size() == 2 and correlations[0] != correlations[1], label + " simultaneous operations stay separate")
	var replayed: Dictionary = Exporter.replay(sim.initial_world, sim.inputs, sim.world.clock().tick_index)
	check(checks, replayed.success and Exporter.equivalent(replayed.details.simulation.events.all(), sim.events.all()), label + " ordered events replay")

static func _failure(checks: Array, multiple_edges: bool) -> void:
	var label := "closeout failure / multiple edges" if multiple_edges else "closeout failure / demo edge"
	var sim := Simulation.new()
	var initialized: Dictionary = sim.initialize(Demo.definition(), 101, "failure")
	check(checks, initialized.success, label + " initializes")
	if not initialized.success:
		return
	if multiple_edges:
		sim.execute({"type": "SetEnabled", "table": "communication_edges", "entity_id": "a_army", "enabled": false}, true)
	var fact := {"subject_entity_id": "A_STOCK", "fact_key": "closeout_failed", "value": 300, "observed_at": sim.time(), "confidence": 1.0}
	var sent: Dictionary = sim.execute({"type": "SendMessage", "sender_command_id": "LOCAL_A", "recipient_command_id": "ARMY_COMMAND", "message_type": "REPORT", "payload": {"facts": [fact]}}, true)
	check(checks, sent.success, label + " send succeeds")
	if not sent.success:
		return
	var id: String = sent.entity_id
	check(checks, sim.world.get_entity("messages", id).state == "IN_TRANSIT", label + " initially in transit")
	var disabled_edges: Array = ["a_b_radio", "b_army"] if multiple_edges else ["a_army"]
	var disabling_events: Dictionary = {}
	for edge_id in disabled_edges:
		var disabled: Dictionary = sim.execute({"type": "SetEnabled", "table": "communication_edges", "entity_id": edge_id, "enabled": false}, true)
		check(checks, disabled.success, label + " disabled " + edge_id)
		disabling_events[edge_id] = sim.events.all().back().event_id
	sim.advance(5 if multiple_edges else 3)
	var failure := event_for(sim, "MESSAGE_FAILED", id)
	check(checks, sim.world.get_entity("messages", id).state == "FAILED" and not failure.is_empty(), label + " fails at attempted delivery")
	if failure.is_empty():
		return
	check(checks, failure.payload.get("reason_code") == "ROUTE_DISABLED", label + " reason code")
	check(checks, failure.payload.get("failed_edge_ids") == disabled_edges, label + " exact failed required edges")
	check(checks, failure.payload.get("failed_edge_change_event_ids") == disabling_events, label + " identifies disabling events")
	var sent_event := event_for(sim, "MESSAGE_SENT", id)
	check(checks, failure.causation_event_id == sent_event.event_id and failure.correlation_id == sent_event.correlation_id, label + " original operation retained")
	check(checks, sim.command_view("ARMY_COMMAND").current_belief("A_STOCK", "closeout_failed", sim.time()).is_empty() and sim.command_view("ARMY_COMMAND").inbox().is_empty(), label + " no recipient knowledge")
	var replayed: Dictionary = Exporter.replay(sim.initial_world, sim.inputs, sim.world.clock().tick_index)
	check(checks, replayed.success and Exporter.equivalent(replayed.details.simulation.snapshot(), sim.snapshot()) and Exporter.equivalent(replayed.details.simulation.events.all(), sim.events.all()), label + " state and diagnostics replay")
