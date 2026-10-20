extends RefCounted
const Demo = preload("res://debug/information_collection_demo.gd")
const Evaluation = preload("res://debug/prompt_evaluation_demo.gd")
const Simulation = preload("res://kernel/simulation.gd")
const Exporter = preload("res://kernel/run_exporter.gd")
const Policy = preload("res://kernel/subordinate_report_policy.gd")
const Audit = preload("res://kernel/information_collection_audit.gd")
const Requirements = preload("res://kernel/information_requirement_service.gd")
const State = preload("res://kernel/information_collection_state.gd")
const Needs = preload("res://tests/resource_resolution_cases.gd")

static func check(checks: Array, valid: bool, name: String) -> void:
	checks.append({"name": "113 / " + name, "passed": valid})

static func collections(sim: RefCounted) -> Array:
	return sim.information_collections.records()

static func requirements(sim: RefCounted) -> Array:
	return sim.information_requirements.snapshot().requirements

static func facts(sim: RefCounted) -> Array:
	return sim.command_view("OPERATIONAL_COMMAND").information().filter(func(v): return v.fact_key.begins_with("REPORTED_FRONT_"))

static func toggle(sim: RefCounted, id: String, enabled: bool) -> Dictionary:
	return sim.execute({"type": "SetEnabled", "table": "communication_edges", "entity_id": id, "enabled": enabled}, true)

static func partial_belief(sim: RefCounted) -> Dictionary:
	return sim.execute({"type": "IngestInformation", "owner_command_id": "LOCAL_C", "fact": {"subject_entity_id": "FRONT_C", "fact_key": "FRONT_ENEMY_PRESSURE", "value": 9900, "observed_at": sim.time(), "confidence": 1.0}}, true)

static func audit(sim: RefCounted, events: Array = []) -> Dictionary:
	return Audit.reconstruct(sim.initial_world, sim.information_collection_configuration(), sim.player_observer.configuration(), requirements(sim), sim.information_collections.events() if events.is_empty() else events, sim.events.all())

static func record_case(checks: Array, summaries: Dictionary, sim: RefCounted, name: String) -> void:
	check(checks, Exporter.export_run(sim, "res://artifacts/run_step113_" + name).success, name + " exports all authoritative and typed2C artifacts")
	var rebuilt := audit(sim)
	check(checks, rebuilt.success and Exporter.observer_equivalent(rebuilt.details.state.snapshot(), sim.information_collections.snapshot()), name + " independent historical-prefix collection reconstruction")
	var rebuilt_requirements := Requirements.new(sim.player_observer.configuration(), ["OPERATIONAL_COMMAND"], sim.information_requirement_configuration(), sim.player_prompts.snapshot().evaluations)
	for item in collections(sim): rebuilt_requirements.register_completion(item)
	var valid := true
	for event in sim.information_requirements.events():
		if not rebuilt_requirements.apply_event(event).success: valid = false
	check(checks, valid and Exporter.observer_equivalent(rebuilt_requirements.snapshot(), sim.information_requirements.snapshot()), name + " requirement lifecycle reconstruction from certified completions")
	check(checks, Needs.conserved_prefixes(sim), name + " conservation at every authoritative prefix")
	summaries[name] = {"world_events": sim.events.count(), "collections": collections(sim), "requirements": requirements(sim), "collection_events": sim.information_collections.events(), "operational_information": facts(sim), "evaluations": sim.player_prompts.snapshot().evaluations, "end_tick": sim.world.clock().tick_index, "ledger": sim.audit()}

# Test-only causal ID bijection. Remove exactly the two113 message subtypes and
# their six reported fact events. Every remaining event, value, order, time,
# policy score, quantity and physical mutation must match, with no tolerance.
# This does not change the production importer or authoritative comparer.
static func military_events(sim: RefCounted) -> Array:
	var messages: Array = []
	for id in sim.world.ids("messages"):
		var message: Dictionary = sim.world.get_entity("messages", id)
		if message.payload.get("subtype") in ["AREA_SITUATION_REPORT_REQUEST", "AREA_SITUATION_REPORT"]: messages.append(id)
	var result: Array = []
	for event in sim.events.all():
		if event.event_type in ["MESSAGE_SENT", "MESSAGE_DELIVERED", "MESSAGE_FAILED"] and event.subject_entity_id in messages: continue
		if event.event_type == "INFORMATION_INGESTED" and event.payload.changes[0].value.source_message_id in messages: continue
		result.append(event)
	return result

static func mapped(value: Variant, ids: Dictionary) -> Variant:
	if value is String: return ids.get(value, value)
	if value is Array:
		var result: Array = []
		for item in value: result.append(mapped(item, ids))
		return result
	if value is Dictionary:
		var result: Dictionary = {}
		for key in value: result[ids.get(key, key)] = mapped(value[key], ids)
		return result
	return value

static func military_pair(a: RefCounted, b: RefCounted) -> Dictionary:
	var left := military_events(a)
	var right := military_events(b)
	if left.size() != right.size(): return {"success": false, "reason": "event count", "left": left.size(), "right": right.size()}
	var ids: Dictionary = {}
	var inverse: Dictionary = {}
	for index in range(left.size()):
		if left[index].event_type != right[index].event_type or left[index].simulation_time != right[index].simulation_time or left[index].payload.changes.size() != right[index].payload.changes.size(): return {"success": false, "reason": "event shape/order", "index": index}
		ids[left[index].event_id] = right[index].event_id
		for change_index in range(left[index].payload.changes.size()):
			var x: Dictionary = left[index].payload.changes[change_index]
			var y: Dictionary = right[index].payload.changes[change_index]
			if x.table != y.table or ids.has(x.id) and ids[x.id] != y.id or inverse.has(y.id) and inverse[y.id] != x.id: return {"success": false, "reason": "nonbijective entity/order", "index": index}
			ids[x.id] = y.id
			inverse[y.id] = x.id
	for index in range(left.size()):
		if not Exporter.observer_equivalent(mapped(left[index], ids), right[index]): return {"success": false, "reason": "military event value", "index": index, "left": mapped(left[index], ids), "right": right[index]}
	for table in ["fronts", "stockpiles", "shipments", "resource_reservations", "ledger", "resource_needs", "peer_coordinations", "resource_arbitrations", "superior_revision_funding", "decisions", "decision_candidates"]:
		if not Exporter.observer_equivalent(mapped(a.snapshot()[table], ids), b.snapshot()[table]): return {"success": false, "reason": "final projection " + table}
	return {"success": true, "matched_military_events": left.size(), "identity_pairs": ids.size(), "ledger": a.audit()}

static func run() -> Dictionary:
	var checks: Array = []
	var summaries: Dictionary = {}
	var a: RefCounted = Demo.fresh()
	Evaluation.prompt(a, "REQUEST_ASSESSMENT")
	a.advance(10)
	check(checks, collections(a).size() == 1 and collections(a)[0].state == "REQUEST_IN_TRANSIT" and requirements(a)[0].state == "OPEN" and facts(a).is_empty(), "A boundary opens one requirement and actual request without OP facts")
	a.advance(2)
	check(checks, collections(a)[0].state == "REPORT_IN_TRANSIT" and facts(a).is_empty() and requirements(a)[0].state == "OPEN", "A Local fresh response sent only after request receipt")
	a.advance(3)
	check(checks, collections(a)[0].state == "COMPLETED" and collections(a)[0].result_code == "REPORT_DELIVERED" and facts(a).size() == 6 and requirements(a)[0].state == "SATISFIED", "A delivery ingests six reported facts then satisfies requirement")
	check(checks, requirements(a)[0].satisfied_at == 1.5 and requirements(a)[0].satisfaction_information_record_ids == collections(a)[0].information_record_ids and requirements(a)[0].satisfaction_collection_id == collections(a)[0].collection_id, "A typed exact satisfaction time and provenance")
	check(checks, a.player_prompt_view().current()[0].result == "FURTHER_INFORMATION_REQUIRED", "A original historical player evaluation unchanged")
	record_case(checks, summaries, a, "A")
	var b: RefCounted = Demo.fresh(true, false, 0.5, 0.7)
	Evaluation.prompt(b)
	b.advance(14)
	check(checks, b.world.inbox_for("LOCAL_C").is_empty() and facts(b).is_empty() and collections(b)[0].state == "REQUEST_IN_TRANSIT", "B no local delivered request before actual latency")
	b.advance()
	check(checks, collections(b)[0].state == "REPORT_IN_TRANSIT" and facts(b).is_empty(), "B report in transit gives no OP knowledge")
	b.advance(6)
	check(checks, facts(b).is_empty() and requirements(b)[0].state == "OPEN", "B requirement open through last predelivery tick")
	b.advance()
	check(checks, facts(b).size() == 6 and requirements(b)[0].satisfied_at == 2.2, "B exact return delivery boundary governs knowledge")
	record_case(checks, summaries, b, "B")
	var c: RefCounted = Demo.fresh()
	Evaluation.prompt(c)
	c.advance(11)
	check(checks, partial_belief(c).success, "C accepted partial current knowledge invalidates older batch consistency")
	c.advance()
	check(checks, collections(c)[0].state == "WAITING_FOR_LOCAL_OBSERVATION" and facts(c).is_empty() and collections(c)[0].response_message_id == null, "C delivered request waits for absent completed observation")
	check(checks, c.events.all().filter(func(v): return v.event_type == "FRONT_OBSERVATION_COMPLETE" and v.simulation_time == 1.1).is_empty(), "C controlled privileged partial ingestion is not batch completion")
	var original_batch: Dictionary = c.world.get_entity("observation_batches", c.world.ids("observation_batches")[0])
	check(checks, Policy.sample("LOCAL_C", "FRONT_C", c.command_view("LOCAL_C").information(), original_batch, 1200000).is_empty(), "C newer partial current belief prevents opportunistic old-batch/hybrid/raw-truth fallback")
	c.advance(8)
	check(checks, collections(c)[0].state == "REPORT_IN_TRANSIT" and c.world.get_entity("messages", collections(c)[0].response_message_id).payload.observed_at == 2, "C next legitimate completed batch generates response immediately")
	c.advance(3)
	check(checks, requirements(c)[0].state == "SATISFIED" and facts(c).all(func(v): return v.observed_at == 2 and v.received_at == 2.3), "C exact original observation and receipt timestamps")
	var eventual: Dictionary = c.world.get_entity("observation_batches", collections(c)[0].source_observation_batch_id)
	check(checks, eventual.id != original_batch.id and eventual.observed_at_micro == 2000000 and collections(c)[0].source_information_record_ids == Policy.KEYS.map(func(key): return eventual.record_ids[key]), "C response cites actual replacement batch and actual six source records")
	record_case(checks, summaries, c, "C")
	var batch: Dictionary = a.world.get_entity("observation_batches", collections(a)[0].source_observation_batch_id)
	var own: Array = a.command_view("LOCAL_C").information()
	check(checks, not Policy.sample("LOCAL_C", "FRONT_C", own, batch, 2500000).is_empty(), "D exact1.5s observation age remains fresh")
	check(checks, not Policy.sample("LOCAL_C", "FRONT_C", own, batch, 2499999).is_empty(), "D below1.5s observation age remains fresh")
	check(checks, Policy.sample("LOCAL_C", "FRONT_C", own, batch, 2500001).is_empty(), "D one microsecond beyond freshness rejects stale source")
	var broken := batch.duplicate(true)
	broken.complete = false
	check(checks, Policy.sample("LOCAL_C", "FRONT_C", own, broken, 1200000).is_empty(), "D incomplete batch rejected")
	broken = batch.duplicate(true)
	broken.record_ids.FRONT_ENEMY_PRESSURE = broken.record_ids.FRONT_FRIENDLY_STRENGTH
	check(checks, Policy.sample("LOCAL_C", "FRONT_C", own, broken, 1200000).is_empty(), "D mixed/corrupt batch record rejected")
	check(checks, Policy.sample("LOCAL_A", "FRONT_C", own, batch, 1200000).is_empty(), "D other Local cannot use C observations")
	var e: RefCounted = Demo.fresh()
	toggle(e, "OPERATIONAL_COMMAND_to_LOCAL_C", false)
	Evaluation.prompt(e)
	e.advance(30)
	check(checks, collections(e).size() == 1 and collections(e)[0].result_code == "NO_COMMUNICATION_ROUTE" and collections(e)[0].request_message_id == null and requirements(e)[0].state == "OPEN" and facts(e).is_empty(), "E no outbound route records unavailable without fake message/retry")
	record_case(checks, summaries, e, "E")
	var f: RefCounted = Demo.fresh()
	toggle(f, "LOCAL_C_to_OPERATIONAL_COMMAND", false)
	Evaluation.prompt(f)
	f.advance(30)
	check(checks, collections(f).size() == 1 and collections(f)[0].result_code == "NO_RETURN_COMMUNICATION_ROUTE" and collections(f)[0].response_message_id == null and requirements(f)[0].state == "OPEN" and facts(f).is_empty(), "F no return route leaves gap open without OP injection/retry")
	record_case(checks, summaries, f, "F")
	var g: RefCounted = Demo.fresh(true, false, 1.5, 1.2)
	Evaluation.prompt(g)
	g.advance(10)
	Evaluation.prompt(g, "REQUEST_ASSESSMENT")
	g.advance(10)
	g.advance(4)
	partial_belief(g)
	g.advance()
	Evaluation.prompt(g)
	g.advance(5)
	g.advance()
	Evaluation.prompt(g)
	g.advance(9)
	check(checks, collections(g).size() == 1 and requirements(g).size() == 1 and requirements(g)[0].source_prompt_ids.size() == 4 and g.world.ids("messages").size() == 2, "G prompts during request/wait/report link once without additional collection/request")
	g.advance(2)
	check(checks, collections(g)[0].state == "COMPLETED", "G original in-flight collection completes normally")
	record_case(checks, summaries, g, "G")
	var h: RefCounted = Demo.fresh()
	Evaluation.prompt(h, "REQUEST_ASSESSMENT", "AREA_HQ")
	h.advance(20)
	check(checks, requirements(h)[0].state == "OPEN" and collections(h).is_empty() and h.world.ids("messages").is_empty(), "H frontless gap has no fabricated collector/request")
	record_case(checks, summaries, h, "H")
	var j: RefCounted = Demo.fresh(true, false, 0.5, 0.3)
	Evaluation.prompt(j)
	j.advance(11)
	var prior_pressure: int = j.world.get_front("FRONT_C").enemy_pressure_centi
	j.execute({"type": "SetFrontEnemyPressure", "front_id": "FRONT_C", "value": 10}, true)
	j.advance(7)
	var received: Dictionary = j.world.get_entity("messages", collections(j)[0].response_message_id)
	check(checks, received.payload.enemy_pressure_centi == prior_pressure and received.payload.enemy_pressure_centi != j.world.get_front("FRONT_C").enemy_pressure_centi and facts(j).filter(func(v): return v.fact_key == "REPORTED_FRONT_ENEMY_PRESSURE")[0].value == prior_pressure, "I/J report uses legitimate previous local belief despite different objective/player state")
	check(checks, received.payload.keys().all(func(k): return k not in ["enemy_activity_band", "friendly_presence_band", "observer", "metadata"]) and not JSON.stringify(j.player_prompt_view().snapshot()).contains("reported_front"), "I/J no observer cues copied and no exact player followup")
	record_case(checks, summaries, j, "J")
	Evaluation.prompt(a, "REQUEST_ASSESSMENT")
	a.advance(5)
	check(checks, requirements(a).size() == 2 and requirements(a)[0].state == "SATISFIED" and requirements(a)[1].state == "OPEN" and requirements(a)[0].source_prompt_ids.size() == 1 and collections(a).size() == 2, "M later unsupported question creates new OPEN lifecycle and new collection")
	a.advance(5)
	check(checks, requirements(a).all(func(v): return v.state == "SATISFIED") and collections(a).all(func(v): return v.state == "COMPLETED"), "M completed history retained through second cycle")
	record_case(checks, summaries, a, "M")
	var zero: RefCounted = Demo.fresh(true, false, 0.0, 0.0)
	Evaluation.prompt(zero)
	zero.advance(10)
	check(checks, collections(zero)[0].state == "COMPLETED" and requirements(zero)[0].satisfied_at == 1 and facts(zero).all(func(v): return v.received_at == 1), "zero latency uses actual send/delivery/ingestion before completion same boundary")
	record_case(checks, summaries, zero, "zero_latency")
	var failed: RefCounted = Demo.fresh(true, false, 0.5, 0.5)
	Evaluation.prompt(failed)
	failed.advance(11)
	toggle(failed, "OPERATIONAL_COMMAND_to_LOCAL_C", false)
	failed.advance(19)
	check(checks, collections(failed)[0].result_code == "REQUEST_MESSAGE_FAILED" and collections(failed)[0].failure_event_id != null and facts(failed).is_empty() and requirements(failed)[0].state == "OPEN", "request delivery failure preserves structured failure and open gap without retry")
	record_case(checks, summaries, failed, "request_failed")
	var failed_response: RefCounted = Demo.fresh(true, false, 0.2, 0.5)
	Evaluation.prompt(failed_response)
	failed_response.advance(13)
	toggle(failed_response, "LOCAL_C_to_OPERATIONAL_COMMAND", false)
	failed_response.advance(17)
	check(checks, collections(failed_response)[0].result_code == "RESPONSE_MESSAGE_FAILED" and facts(failed_response).is_empty() and requirements(failed_response)[0].state == "OPEN", "response delivery failure never creates facts or satisfaction")
	record_case(checks, summaries, failed_response, "response_failed")
	var no_observation: RefCounted = Demo.fresh()
	Evaluation.prompt(no_observation, "REQUEST_ASSESSMENT", "AREA_FRONT_A")
	no_observation.advance(20)
	check(checks, collections(no_observation)[0].result_code == "LOCAL_OBSERVATION_UNAVAILABLE" and collections(no_observation)[0].request_message_id == null and requirements(no_observation)[0].state == "OPEN", "nonassigned Local is known unavailable rather than permanent waiter")
	record_case(checks, summaries, no_observation, "nonobserving")
	var k_on: RefCounted = Demo.fresh(true, true)
	var k_off: RefCounted = Demo.fresh(false, true)
	for sim in [k_on, k_off]:
		Evaluation.prompt(sim)
		Evaluation.prompt(sim, "REQUEST_ASSESSMENT")
		sim.advance(250)
	var paired := military_pair(k_on, k_off)
	summaries.military_comparison = paired
	check(checks, paired.success, "K every non113 authoritative event and all military/physical final projections match by causal ID bijection")
	check(checks, k_on.events.count() > k_off.events.count() and not collections(k_on).is_empty() and collections(k_off).is_empty(), "K real information communication legitimately diverges authoritative IDs/events only enabled")
	check(checks, Exporter.observer_equivalent(k_on.audit(), k_off.audit()), "K exact final physical conservation/ledger equality")
	record_case(checks, summaries, k_on, "K_enabled")
	record_case(checks, summaries, k_off, "K_disabled")
	for field in ["collection_id", "requirement_id", "owner_command_id", "collector_command_id", "area_id", "front_id", "method", "state", "created_at", "request_message_id", "response_message_id", "source_observation_batch_id", "source_information_record_ids", "information_record_ids", "result_code", "failure_event_id"]:
		var events: Array = zero.information_collections.events()
		var index: int = events.size() - 1
		var value: Variant = events[index].record[field]
		if value is Array: events[index].record[field] = ["forged"]
		elif value is int or value is float: events[index].record[field] = 999
		else: events[index].record[field] = "FORGED"
		check(checks, not audit(zero, events).success, "integrity rejects forged collection " + field)
	for field in ["collection_event_id", "previous_collection_event_id", "event_type", "schema_version", "source_authoritative_event_id", "at"]:
		var events: Array = zero.information_collections.events()
		events.back()[field] = 999 if field == "at" else "FORGED"
		check(checks, not audit(zero, events).success, "integrity rejects forged collection envelope " + field)
	var malformed: Array = zero.information_collections.events()
	malformed.back().record.observer_cue = "HIGH"
	check(checks, not audit(zero, malformed).success, "integrity rejects unknown observer/metadata payload")
	malformed = zero.information_collections.events()
	malformed.append(malformed.back().duplicate(true))
	check(checks, not audit(zero, malformed).success, "integrity rejects duplicate terminal event")
	for field in ["collection_id", "response_message_id", "information_record_ids", "satisfied_at", "requirement_id", "owner_command_id", "area_id", "previous_requirement_event_id"]:
		var rebuilt := Requirements.new(zero.player_observer.configuration(), ["OPERATIONAL_COMMAND"], zero.information_requirement_configuration(), zero.player_prompts.snapshot().evaluations)
		rebuilt.register_completion(collections(zero)[0])
		rebuilt.apply_event(zero.information_requirements.events()[0])
		var event: Dictionary = zero.information_requirements.events().back()
		event[field] = ["FORGED"] if field == "information_record_ids" else (999 if field == "satisfied_at" else "FORGED")
		check(checks, not rebuilt.apply_event(event).success, "integrity rejects forged satisfaction " + field)
	var early := Requirements.new(zero.player_observer.configuration(), ["OPERATIONAL_COMMAND"], zero.information_requirement_configuration(), zero.player_prompts.snapshot().evaluations)
	early.apply_event(zero.information_requirements.events()[0])
	check(checks, not early.apply_event(zero.information_requirements.events().back()).success, "integrity rejects satisfaction without certified complete collection")
	for invalid in ["yes", 1, {}, null]:
		var data := Demo.definition()
		data.commands[0].strategic_subordinate_reporting_enabled = invalid
		check(checks, not Simulation.new().initialize(data).success, "config rejects nonboolean enable " + str(invalid))
	var invalid_local := Demo.definition()
	invalid_local.commands[3].strategic_subordinate_reporting_enabled = true
	check(checks, not Simulation.new().initialize(invalid_local).success, "config rejects Local enabling Operational collection")
	var no_prompts: RefCounted = Demo.fresh()
	no_prompts.advance(20)
	check(checks, collections(no_prompts).is_empty() and no_prompts.world.ids("messages").is_empty() and facts(no_prompts).is_empty(), "enabled config alone creates no collection/message/fact")
	record_case(checks, summaries, no_prompts, "no_prompts")
	# Fresh-process replay is invoked independently for every exported package.
	# This same-process integrity probe additionally rehashes altered data, proving
	# validation is not merely a checksum comparison.
	var directory := "res://artifacts/run_step113_tampered"
	Exporter.export_run(zero, directory)
	var changed: Array = zero.information_collections.events()
	changed.back().record.information_record_ids[0] = "information:FORGED"
	Exporter.write_json(directory.path_join("information_collection_events.jsonl"), changed, true)
	var manifest: Dictionary = Exporter.read_json(directory.path_join("manifest.json")).details.value
	manifest.information_collection.sha256 = FileAccess.get_sha256(directory.path_join("information_collection_events.jsonl"))
	Exporter.write_json(directory.path_join("manifest.json"), manifest)
	check(checks, not Exporter.replay_package(directory).success, "strict importer rejects rehashed forged Operational information provenance")
	Exporter.export_run(zero, directory)
	var projection: Dictionary = zero.information_collections.snapshot()
	projection.collections[0].state = "UNAVAILABLE"
	Exporter.write_json(directory.path_join("final_information_collections.json"), projection)
	manifest = Exporter.read_json(directory.path_join("manifest.json")).details.value
	manifest.information_collection.projection_sha256 = FileAccess.get_sha256(directory.path_join("final_information_collections.json"))
	Exporter.write_json(directory.path_join("manifest.json"), manifest)
	check(checks, not Exporter.replay_package(directory).success, "strict importer rejects rehashed projection inconsistent with collection stream")
	Exporter.export_run(zero, directory)
	Exporter.write_json(directory.path_join("information_collection_events.jsonl"), [], true)
	check(checks, Exporter.replay_package(directory).error_code == "COLLECTION_PACKAGE_HASH_MISMATCH", "strict importer rejects altered hash before replay")
	var failures: Array = []
	for item in checks:
		if not item.passed: failures.append(item.name)
	return {"success": failures.is_empty(), "checks": checks, "failures": failures, "scenarios": summaries}
