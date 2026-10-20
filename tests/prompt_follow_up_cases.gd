extends RefCounted
const Demo = preload("res://debug/prompt_follow_up_demo.gd")
const Evaluation = preload("res://debug/prompt_evaluation_demo.gd")
const Simulation = preload("res://kernel/simulation.gd")
const Prompts = preload("res://kernel/player_prompt_service.gd")
const Policy = preload("res://kernel/prompt_follow_up_policy.gd")
const Exporter = preload("res://kernel/run_exporter.gd")
const Needs = preload("res://tests/resource_resolution_cases.gd")

static func check(checks: Array, valid: bool, name: String) -> void:
	checks.append({"name": "114 / " + name, "passed": valid})

static func follow_ups(sim: RefCounted) -> Array:
	return sim.player_prompts.snapshot().follow_ups

static func requirements(sim: RefCounted) -> Array:
	return sim.information_requirements.snapshot().requirements

static func rebuild(sim: RefCounted) -> RefCounted:
	var result := Prompts.new(sim.player_observer.configuration(), sim.prompt_follow_up_configuration())
	for requirement in requirements(sim):
		if requirement.state == "SATISFIED":
			var registered: Dictionary = result.register_satisfaction(sim.follow_up_evidence(requirement))
			assert(registered.success, JSON.stringify(registered))
	return result

static func public_safe(value: Variant) -> bool:
	if value is Array: return value.all(func(item): return public_safe(item))
	if not value is Dictionary: return true
	var private_keys := ["friendly_strength_centi", "enemy_pressure_centi", "ammo_coverage_milliseconds", "last_shortage", "requirement_id", "collection_id", "source_information_record_ids", "source_local_information_record_ids", "source_response_message_id", "source_observation_batch_id", "follow_up_id", "metadata", "knowledge_reports", "source_prompt_id", "source_evaluation_event_id", "source_requirement_id", "source_collection_id", "previous_follow_up_event_id", "stream_sequence"]
	for key in value:
		if key in private_keys or not public_safe(value[key]): return false
	return true

static func basis_values(strength := 5000, pressure := 5000, posture := "HOLD", status := "FINITE", coverage: Variant = 10000, shortage := 0) -> Dictionary:
	return {"FRONT_FRIENDLY_STRENGTH": strength, "FRONT_ENEMY_PRESSURE": pressure, "FRONT_POSTURE": posture, "FRONT_AMMO_COVERAGE_STATUS": status, "FRONT_AMMO_COVERAGE_MILLISECONDS": coverage, "FRONT_LAST_SHORTAGE": shortage}

static func prefix_before_first_follow_up(sim: RefCounted) -> RefCounted:
	var result := rebuild(sim)
	for event in sim.player_prompts.events():
		if event.event_type == "PLAYER_PROMPT_FOLLOW_UP_ISSUED": break
		var applied: Dictionary = result.apply_event(event)
		assert(applied.success)
	return result

static func base_lines(events: Array) -> String:
	var text := ""
	for event in events:
		if event.event_type != "PLAYER_PROMPT_FOLLOW_UP_ISSUED": text += JSON.stringify(event, "", true, true) + "\n"
	return text

static func record_case(checks: Array, summaries: Dictionary, sim: RefCounted, name: String) -> void:
	check(checks, Exporter.export_run(sim, "res://artifacts/run_step114_" + name).success, name + " exports hashed followup config and additive prompt stream")
	var reconstructed := rebuild(sim)
	var valid := true
	for event in sim.player_prompts.events():
		if not reconstructed.apply_event(event).success: valid = false
	check(checks, valid and Exporter.observer_equivalent(reconstructed.snapshot(), sim.player_prompts.snapshot()) and Exporter.observer_equivalent(reconstructed.view().snapshot(), sim.player_prompt_view().snapshot()), name + " exact prompt event reconstruction with certified113 source registry")
	check(checks, public_safe(sim.player_prompt_view().snapshot()) and public_safe(sim.player_prompt_view()._prompts) and public_safe(sim.player_prompt_view()._history), name + " current/backing/history public projections contain no exact/private provenance")
	check(checks, Needs.conserved_prefixes(sim), name + " conservation at all authoritative prefixes")
	summaries[name] = {"world_events": sim.events.count(), "prompt_events": sim.player_prompts.events().size(), "follow_ups": follow_ups(sim), "evaluations": sim.player_prompts.snapshot().evaluations, "requirements": requirements(sim), "collections": sim.information_collections.records(), "view": sim.player_prompt_view().snapshot(), "end_tick": sim.world.clock().tick_index, "ledger": sim.audit()}

static func run() -> Dictionary:
	var checks: Array = []
	var summaries: Dictionary = {}
	var a: RefCounted = Demo.fresh()
	Evaluation.prompt(a, "REQUEST_ASSESSMENT")
	a.advance(10)
	check(checks, follow_ups(a).is_empty() and a.player_prompt_view().current()[0].result == "FURTHER_INFORMATION_REQUIRED", "A initial unsupported result retained while acquiring")
	var held: RefCounted = a.player_prompt_view()
	a.advance(5)
	var answer: Dictionary = follow_ups(a)[0]
	check(checks, answer.follow_up_id == "prompt-follow-up:0000000001" and answer.prompt_id == "player-prompt:0000000001" and answer.requirement_id == "information-requirement:0000000001" and answer.collection_id == "information-collection:0000000001" and answer.state == "ISSUED", "A exact independent followup identity and acquisition links")
	check(checks, answer.issued_at == 1.5 and answer.assessment_observed_at == 1 and answer.result == "ASSESSMENT_AVAILABLE" and answer.assessment_code == "COLLECTED_AREA_SITUATION_ASSESSMENT", "A additive answer issued at exact satisfaction time with original observation timestamp")
	check(checks, answer.friendly_presence == "MEDIUM" and answer.enemy_activity == "HIGH" and answer.front_behavior == "HOLDING" and answer.ammo_condition == "CRITICAL", "A qualitative response derives from reported values")
	check(checks, a.player_prompts.snapshot().evaluations[0].result == "FURTHER_INFORMATION_REQUIRED" and a.player_prompt_view().current()[0].result == "FURTHER_INFORMATION_REQUIRED" and a.player_prompt_view().current()[0].latest_follow_up.result == "ASSESSMENT_AVAILABLE", "A original111 event/evaluation/projected result preserved with later additive answer")
	check(checks, held.current()[0].get("follow_up_status") == null and held.recent_history().size() == 3, "A held public view remains detached pre-answer snapshot")
	var copied: Dictionary = a.player_prompt_view().current()[0]
	copied.latest_follow_up.enemy_activity = "FORGED"
	check(checks, a.player_prompt_view().current()[0].latest_follow_up.enemy_activity == "HIGH" and a.command_prompt_view("LOCAL_C").current().is_empty(), "A detached queries and recipient scoping")
	var prior: Array = follow_ups(a)
	check(checks, a.player_prompts.issue_follow_ups(a.follow_up_evidence(requirements(a)[0])).success and Exporter.observer_equivalent(prior, follow_ups(a)), "A repeated satisfaction processing is idempotent")
	record_case(checks, summaries, a, "A")
	var b: RefCounted = Demo.fresh(true, false, 0.5, 2.0)
	Evaluation.prompt(b, "REQUEST_ASSESSMENT")
	b.advance(34)
	check(checks, follow_ups(b).is_empty() and requirements(b)[0].state == "OPEN", "B no followup before real return delivery")
	b.advance()
	check(checks, follow_ups(b).size() == 1 and follow_ups(b)[0].issued_at == 3.5 and follow_ups(b)[0].assessment_observed_at == 1, "B report transit may make acquired answer stale without new cutoff")
	record_case(checks, summaries, b, "B")
	var data := Demo.definition(true, false, 0.5, 0.3)
	data.fronts[2].enemy_pressure = 50
	var c: RefCounted = Demo.start(data)
	Evaluation.prompt(c, "REQUEST_ASSESSMENT")
	c.advance(11)
	c.execute({"type": "SetFrontEnemyPressure", "front_id": "FRONT_C", "value": 90}, true)
	c.advance(7)
	check(checks, follow_ups(c)[0].enemy_activity == "MEDIUM" and c.world.get_front("FRONT_C").enemy_pressure_centi == 9000 and JSON.stringify(c.player_view().snapshot()).contains("HIGH"), "C stale acquired MEDIUM wins over current objective/player HIGH")
	var evidence: Dictionary = c.follow_up_evidence(requirements(c)[0])
	check(checks, evidence.information_records.any(func(record): return record.fact_key == "REPORTED_FRONT_ENEMY_PRESSURE" and record.value == 5000) and public_safe(c.player_prompt_view().snapshot()), "D exact internal reported value present but absent from normal current/history projection")
	c.execute({"type": "IngestInformation", "owner_command_id": "OPERATIONAL_COMMAND", "fact": {"subject_entity_id": "FRONT_C", "fact_key": "REPORTED_FRONT_ENEMY_PRESSURE", "value": 10000, "observed_at": c.time(), "confidence": 1.0}}, true)
	check(checks, Policy.certify(c.follow_up_evidence(requirements(c)[0])).details.basis.enemy_activity == "MEDIUM" and follow_ups(c)[0].enemy_activity == "MEDIUM", "C later unrelated/newer Operational belief cannot replace exact satisfied source")
	record_case(checks, summaries, c, "C")
	var e: RefCounted = Demo.fresh()
	Evaluation.prompt(e)
	e.advance(15)
	check(checks, requirements(e)[0].state == "SATISFIED" and e.information_collections.records()[0].state == "COMPLETED" and follow_ups(e).is_empty(), "E DIRECT_ATTENTION acquires information without player answer")
	record_case(checks, summaries, e, "E")
	var f: RefCounted = Demo.fresh(true, false, 1.5, 0.5)
	Evaluation.prompt(f, "REQUEST_ASSESSMENT")
	f.advance(10)
	Evaluation.prompt(f, "REQUEST_ASSESSMENT")
	Evaluation.prompt(f)
	Evaluation.prompt(f, "REQUEST_ASSESSMENT")
	f.advance(20)
	check(checks, requirements(f).size() == 1 and f.information_collections.records().size() == 1 and follow_ups(f).size() == 3 and follow_ups(f).map(func(item): return item.prompt_id) == ["player-prompt:0000000001", "player-prompt:0000000002", "player-prompt:0000000004"], "F three inquiries share one acquisition; attention skipped; first-link answer order")
	check(checks, follow_ups(f).map(func(item): return item.follow_up_id) == ["prompt-follow-up:0000000001", "prompt-follow-up:0000000002", "prompt-follow-up:0000000003"], "F independent consecutive followup IDs")
	record_case(checks, summaries, f, "F")
	var g: RefCounted = Demo.fresh()
	g.execute({"type": "SetEnabled", "table": "communication_edges", "entity_id": "OPERATIONAL_COMMAND_to_LOCAL_C", "enabled": false}, true)
	Evaluation.prompt(g, "REQUEST_ASSESSMENT")
	g.advance(20)
	check(checks, requirements(g)[0].state == "OPEN" and follow_ups(g).is_empty(), "G unavailable collection yields no fabricated followup")
	record_case(checks, summaries, g, "G")
	var h: RefCounted = Demo.fresh()
	Evaluation.prompt(h, "REQUEST_ASSESSMENT")
	h.advance(15)
	var old: Dictionary = follow_ups(h)[0]
	Evaluation.prompt(h, "REQUEST_ASSESSMENT")
	h.advance(10)
	check(checks, follow_ups(h).size() == 2 and requirements(h).size() == 2 and h.information_collections.records().size() == 2 and follow_ups(h)[1].requirement_id != old.requirement_id and Exporter.observer_equivalent(old, follow_ups(h)[0]), "H new inquiry cycle gets new acquisition/answer without rewriting historical first answer")
	record_case(checks, summaries, h, "H")
	for item in [[0, "LOW"], [3333, "LOW"], [3334, "MEDIUM"], [6666, "MEDIUM"], [6667, "HIGH"], [10000, "HIGH"]]:
		var result := Policy.qualitative(basis_values(item[0], item[0]))
		check(checks, result.friendly_presence == item[1] and result.enemy_activity == item[1], "mapping exact strength/pressure centi boundary " + str(item[0]))
	for item in [["HOLD", "HOLDING"], ["PRESS", "PRESSING"], ["REDUCE_ACTIVITY", "REDUCED_ACTIVITY"], ["WITHDRAW", "WITHDRAWING"]]:
		check(checks, Policy.qualitative(basis_values(5000, 5000, item[0])).front_behavior == item[1], "mapping accepted posture " + item[0])
	for item in [["FINITE", 0, "CRITICAL"], ["FINITE", 4999, "CRITICAL"], ["FINITE", 5000, "CONSTRAINED"], ["FINITE", 14999, "CONSTRAINED"], ["FINITE", 15000, "SECURE"], ["ZERO_DEMAND", null, "NO_ACTIVE_DEMAND"], ["OUT_OF_RANGE", null, "SECURE"]]:
		check(checks, Policy.qualitative(basis_values(5000, 5000, "HOLD", item[0], item[1])).ammo_condition == item[2], "mapping qualitative ammo " + item[0] + "/" + str(item[1]))
		check(checks, Policy.qualitative(basis_values(5000, 5000, "HOLD", item[0], item[1], 1)).ammo_condition == "SHORTAGE_REPORTED", "mapping shortage precedence " + item[0] + "/" + str(item[1]))
	var zero: RefCounted = Demo.fresh()
	zero.advance(20)
	check(checks, follow_ups(zero).is_empty() and zero.player_prompts.events().is_empty() and zero.information_collections.records().is_empty(), "K enabling followup alone creates no records/messages/acquisition")
	record_case(checks, summaries, zero, "K_zero")
	var pending: RefCounted = Demo.fresh(true, false, 1.5, 0.5)
	Evaluation.prompt(pending, "REQUEST_ASSESSMENT")
	pending.advance(12)
	check(checks, follow_ups(pending).is_empty() and requirements(pending)[0].state == "OPEN", "K in-flight acquisition cannot produce followup")
	record_case(checks, summaries, pending, "K_pending")
	var zero_latency: RefCounted = Demo.fresh(true, false, 0.0, 0.0)
	Evaluation.prompt(zero_latency, "REQUEST_ASSESSMENT")
	zero_latency.advance(10)
	check(checks, follow_ups(zero_latency).size() == 1 and follow_ups(zero_latency)[0].issued_at == 1 and requirements(zero_latency)[0].satisfied_at == 1, "zero latency followup occurs synchronously after real ingestion and satisfaction")
	record_case(checks, summaries, zero_latency, "zero_latency")
	for field in ["follow_up_id", "prompt_id", "prompt_type", "area_id", "recipient_command_id", "requirement_id", "collection_id", "issued_at", "assessment_observed_at", "result", "assessment_code", "friendly_presence", "enemy_activity", "front_behavior", "ammo_condition", "source_response_message_id", "source_information_record_ids", "source_observation_batch_id", "source_local_information_record_ids", "follow_up_state", "previous_follow_up_event_id", "source_prompt_id", "source_evaluation_event_id", "source_requirement_id", "source_collection_id", "prompt_event_id", "schema_version", "stream_sequence"]:
		var service := prefix_before_first_follow_up(a)
		var event: Dictionary = a.player_prompts.events().back()
		var current: Variant = event[field]
		event[field] = ["FORGED"] if current is Array else (999 if current is int or current is float else "FORGED")
		check(checks, not service.apply_event(event).success, "integrity rejects forged followup " + field)
	var duplicated := rebuild(a)
	for event in a.player_prompts.events(): duplicated.apply_event(event)
	var duplicate: Dictionary = a.player_prompts.events().back()
	duplicate.prompt_event_id = "player-prompt-follow-up-event:0000000002"
	duplicate.follow_up_id = "prompt-follow-up:0000000002"
	duplicate.previous_follow_up_event_id = "player-prompt-follow-up-event:0000000001"
	duplicate.stream_sequence += 1
	check(checks, not duplicated.apply_event(duplicate).success, "integrity rejects second followup for already answered prompt/cycle even with next IDs")
	var uncertified := Prompts.new(a.player_observer.configuration(), a.prompt_follow_up_configuration())
	for event in a.player_prompts.events().slice(0, 3): uncertified.apply_event(event)
	check(checks, not uncertified.apply_event(a.player_prompts.events().back()).success, "integrity rejects followup without certified satisfaction evidence")
	var no_answer := rebuild(e)
	for event in e.player_prompts.events(): no_answer.apply_event(event)
	var attention: Dictionary = a.player_prompts.events().back()
	attention.prompt_type = "DIRECT_ATTENTION"
	check(checks, not no_answer.apply_event(attention).success, "integrity rejects DIRECT_ATTENTION claiming inquiry followup")
	for section in ["requirement", "collection", "response", "information_records"]:
		var forged: Dictionary = a.follow_up_evidence(requirements(a)[0])
		if section == "information_records": forged.information_records[0].source_message_id = "message:FORGED"
		elif section == "requirement": forged.requirement.state = "OPEN"
		elif section == "collection": forged.collection.collection_id = "information-collection:FORGED"
		else: forged.response.id = "message:FORGED"
		check(checks, not Policy.certify(forged).success, "evidence rejects mismatched/unsatisfied " + section)
	var mixed: Dictionary = a.follow_up_evidence(requirements(a)[0])
	mixed.information_records[0] = h.follow_up_evidence(requirements(h)[1]).information_records[0]
	check(checks, not Policy.certify(mixed).success, "evidence rejects mixing Operational records from another report/cycle")
	var source_values: Dictionary = a.follow_up_evidence(requirements(a)[0])
	source_values.information_records[0].value = 9999
	check(checks, not Policy.certify(source_values).success, "evidence rejects altered exact source fact despite valid reported field key")
	for invalid in ["yes", 1, null, {}]:
		var invalid_data := Demo.definition()
		invalid_data.commands[0].strategic_prompt_follow_up_enabled = invalid
		check(checks, not Simulation.new().initialize(invalid_data).success, "config rejects nonboolean " + str(invalid))
	var invalid_local := Demo.definition()
	invalid_local.commands[3].strategic_prompt_follow_up_enabled = true
	check(checks, not Simulation.new().initialize(invalid_local).success, "config rejects Local enabling Operational followup")
	var supported_data := Demo.definition()
	supported_data.commands[0].ammunition_arbitration_enabled = true
	var supported: RefCounted = Demo.start(supported_data)
	Evaluation.send(supported, Evaluation.report())
	Evaluation.prompt(supported, "REQUEST_ASSESSMENT")
	supported.advance(15)
	check(checks, supported.player_prompts.snapshot().evaluations[0].result == "ASSESSMENT_AVAILABLE" and requirements(supported).is_empty() and follow_ups(supported).is_empty(), "K already supported111 assessment creates no gap/acquisition/followup")
	var supported_service := rebuild(supported)
	for event in supported.player_prompts.events(): supported_service.apply_event(event)
	check(checks, supported_service.register_satisfaction(a.follow_up_evidence(requirements(a)[0])).success and not supported_service.apply_event(a.player_prompts.events().back()).success, "integrity source prompt with legitimate nonqualifying initial evaluation cannot claim followup")
	record_case(checks, summaries, supported, "K_supported")
	for field in ["satisfied_at", "satisfaction_collection_id"]:
		var malformed: Dictionary = a.follow_up_evidence(requirements(a)[0])
		malformed.requirement[field] = "MALFORMED" if field == "satisfied_at" else 123
		check(checks, not Policy.certify(malformed).success, "source validator rejects malformed typed " + field)
	var i_on: RefCounted = Demo.fresh(true, true)
	var i_off: RefCounted = Demo.fresh(false, true)
	for sim in [i_on, i_off]:
		Evaluation.prompt(sim, "REQUEST_ASSESSMENT")
		sim.advance(20)
		Evaluation.prompt(sim, "REQUEST_ASSESSMENT", "AREA_FRONT_A")
		sim.advance(230)
	check(checks, follow_ups(i_on).size() == 2 and follow_ups(i_off).is_empty() and requirements(i_on).size() == 2 and requirements(i_on).all(func(req): return req.state == "SATISFIED"), "I meaningful autonomous25s fixture has two acquisition/inquiry cycles with additive followups only enabled")
	record_case(checks, summaries, i_on, "I_enabled")
	record_case(checks, summaries, i_off, "I_disabled")
	var matching_files := ["initial_world.json", "events.jsonl", "final_world.json", "inputs.jsonl", "player_observer_config.json", "player_observation_events.jsonl", "final_player_observer.json", "player_prompt_evaluation_config.json", "player_prompt_information_requirement_config.json", "information_requirement_events.jsonl", "final_information_requirements.json", "information_collection_config.json", "information_collection_events.jsonl", "final_information_collections.json"]
	var hashes: Array = []
	for file in matching_files:
		var enabled_hash := FileAccess.get_sha256("res://artifacts/run_step114_I_enabled/" + file)
		var disabled_hash := FileAccess.get_sha256("res://artifacts/run_step114_I_disabled/" + file)
		check(checks, not enabled_hash.is_empty() and enabled_hash == disabled_hash, "I exact actual exported bytes preserved " + file)
		hashes.append({"file": file, "enabled_sha256": enabled_hash, "disabled_sha256": disabled_hash, "passed": enabled_hash == disabled_hash})
	summaries.inertness_files = hashes
	check(checks, base_lines(i_on.player_prompts.events()) == base_lines(i_off.player_prompts.events()), "I stripping only actual followup records leaves byte-identical110/111 base records across later cycles, no remap/rewrite")
	check(checks, Exporter.observer_equivalent(i_on.player_prompts.snapshot().evaluations, i_off.player_prompts.snapshot().evaluations) and Exporter.observer_equivalent(i_on.audit(), i_off.audit()), "I original111 evaluations and complete physical ledger exact on/off")
	check(checks, i_on.player_prompts.events().filter(func(event): return event.event_type == "PLAYER_PROMPT_FOLLOW_UP_ISSUED").all(func(event): return event.stream_sequence == i_on.player_prompts.events().find(event) + 1 and not event.has("previous_prompt_event_id")), "I followup explicit physical position and own lineage distinct from base lineage")
	var directory := "res://artifacts/run_step114_tampered"
	for field in ["follow_up_id", "requirement_id", "collection_id", "enemy_activity", "source_information_record_ids", "stream_sequence", "previous_follow_up_event_id", "source_evaluation_event_id"]:
		Exporter.export_run(a, directory)
		var events: Array = a.player_prompts.events()
		var value: Variant = events.back()[field]
		events.back()[field] = ["FORGED"] if value is Array else (999 if field == "stream_sequence" else "FORGED")
		Exporter.write_json(directory.path_join("player_prompt_events.jsonl"), events, true)
		var manifest: Dictionary = Exporter.read_json(directory.path_join("manifest.json")).details.value
		manifest.player_prompt.sha256 = FileAccess.get_sha256(directory.path_join("player_prompt_events.jsonl"))
		Exporter.write_json(directory.path_join("manifest.json"), manifest)
		check(checks, not Exporter.replay_package(directory).success, "import rejects rehashed forged followup " + field)
	Exporter.export_run(a, directory)
	var projection: Dictionary = Exporter.prompt_projection(a)
	projection.view.prompts[0].latest_follow_up.enemy_pressure_centi = 7000
	Exporter.write_json(directory.path_join("final_player_prompts.json"), projection)
	var manifest: Dictionary = Exporter.read_json(directory.path_join("manifest.json")).details.value
	manifest.player_prompt.projection_sha256 = FileAccess.get_sha256(directory.path_join("final_player_prompts.json"))
	Exporter.write_json(directory.path_join("manifest.json"), manifest)
	check(checks, not Exporter.replay_package(directory).success, "import rejects rehashed exact-value/private leakage in public current projection")
	Exporter.export_run(a, directory)
	projection = Exporter.prompt_projection(a)
	projection.view.history.back().source_information_record_ids = answer.source_information_record_ids
	Exporter.write_json(directory.path_join("final_player_prompts.json"), projection)
	manifest = Exporter.read_json(directory.path_join("manifest.json")).details.value
	manifest.player_prompt.projection_sha256 = FileAccess.get_sha256(directory.path_join("final_player_prompts.json"))
	Exporter.write_json(directory.path_join("manifest.json"), manifest)
	check(checks, not Exporter.replay_package(directory).success, "import rejects rehashed source-record leakage in public history")
	Exporter.export_run(a, directory)
	Exporter.write_json(directory.path_join("player_prompt_follow_up_config.json"), {})
	check(checks, Exporter.replay_package(directory).error_code == "FOLLOW_UP_PACKAGE_HASH_MISMATCH", "import rejects changed followup config hash")
	var failures: Array = []
	for item in checks:
		if not item.passed: failures.append(item.name)
	return {"success": failures.is_empty(), "checks": checks, "failures": failures, "scenarios": summaries}
