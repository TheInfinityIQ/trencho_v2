extends RefCounted
const Demo = preload("res://debug/information_requirement_demo.gd")
const Evaluation = preload("res://debug/prompt_evaluation_demo.gd")
const Simulation = preload("res://kernel/simulation.gd")
const Requirements = preload("res://kernel/information_requirement_service.gd")
const Config = preload("res://kernel/information_requirement_config.gd")
const Exporter = preload("res://kernel/run_exporter.gd")
const Needs = preload("res://tests/resource_resolution_cases.gd")

static func check(checks: Array, valid: bool, name: String) -> void:
	checks.append({"name": "112 / " + name, "passed": valid})

static func exact(a: Variant, b: Variant) -> bool:
	return Exporter.observer_equivalent(a, b)

static func records(sim: RefCounted) -> Array:
	return sim.information_requirements.snapshot().requirements

static func owners(sim: RefCounted) -> Array:
	return sim.world.ids("commands").filter(func(id): return sim.world.get_command(id).command_level == "OPERATIONAL")

static func reconstruct(sim: RefCounted) -> RefCounted:
	return Requirements.new(sim.player_observer.configuration(), owners(sim), sim.information_requirement_configuration(), sim.player_prompts.snapshot().evaluations)

static func record_case(checks: Array, summaries: Dictionary, sim: RefCounted, name: String) -> void:
	check(checks, Exporter.export_run(sim, "res://artifacts/run_step112_" + name).success, name + " exports separate112 artifacts")
	var rebuilt := reconstruct(sim)
	var valid := true
	for event in sim.information_requirements.events():
		if not rebuilt.apply_event(event).success: valid = false
	check(checks, valid and exact(rebuilt.snapshot(), sim.information_requirements.snapshot()), name + " event-only reconstruction with validated111 evaluation registry")
	for owner in owners(sim):
		check(checks, exact(rebuilt.view(owner).snapshot(), sim.information_requirement_view(owner).snapshot()), name + " exact recipient-view reconstruction " + owner)
	check(checks, Needs.conserved_prefixes(sim), name + " authoritative prefix conservation and claims")
	check(checks, safe_records(sim.information_requirements.snapshot(), sim.information_requirements.events()), name + " no observer payload or battlefield fact in records/events")
	summaries[name] = {"world_events": sim.events.count(), "observer_events": sim.player_observer.events().size(), "prompt_events": sim.player_prompts.events().size(), "evaluations": sim.player_prompts.snapshot().evaluations, "requirement_events": sim.information_requirements.events(), "requirements": records(sim), "inputs": sim.inputs.size(), "end_tick": sim.world.clock().tick_index, "ledger": sim.audit()}

static func safe_records(state: Dictionary, events: Array) -> bool:
	for record in state.requirements:
		if record.keys().size() != 11 or record.keys().any(func(k): return k not in ["requirement_id", "requirement_type", "owner_command_id", "area_id", "state", "created_at", "last_updated_at", "source_prompt_ids", "source_evaluation_ids", "creation_reason", "metadata"]) or not record.metadata.is_empty(): return false
	for event in events:
		if event.size() != Requirements.EVENT_FIELDS.size() or event.keys().any(func(k): return k not in Requirements.EVENT_FIELDS) or not event.metadata.is_empty(): return false
	return true

static func run() -> Dictionary:
	var checks: Array = []
	var summaries: Dictionary = {}
	var a: RefCounted = Demo.fresh()
	Evaluation.prompt(a, "REQUEST_ASSESSMENT")
	a.advance(9)
	check(checks, records(a).is_empty(), "A no requirement before actual111 evaluation")
	a.advance()
	var r: Dictionary = records(a)[0]
	check(checks, r.requirement_id == "information-requirement:0000000001" and r.requirement_type == "AREA_SITUATION_ASSESSMENT" and r.owner_command_id == "OPERATIONAL_COMMAND" and r.area_id == "AREA_FRONT_C" and r.state == "OPEN", "A assessment opens correct autonomous work item")
	check(checks, r.source_prompt_ids == ["player-prompt:0000000001"] and r.source_evaluation_ids == ["prompt-evaluation:0000000001"] and r.created_at == 1 and r.last_updated_at == 1 and r.creation_reason == "PLAYER_PROMPT_INFORMATION_GAP", "A exact prompt/evaluation/time/reason provenance")
	check(checks, a.information_requirements.events()[0].source_evaluation_event_id == a.player_prompts.events().back().prompt_event_id and a.information_requirements.events()[0].previous_requirement_event_id == null, "A explicitly typed cross-stream evaluation reference not same-stream cause")
	var held: RefCounted = a.information_requirement_view("OPERATIONAL_COMMAND")
	var copied: Array = held.open_requirements()
	copied[0].state = "SATISFIED"
	check(checks, held.requirement(r.requirement_id).state == "OPEN" and a.information_requirement_view("LOCAL_C").open_requirements().is_empty() and a.information_requirement_view("MISSING").requirement(r.requirement_id).is_empty(), "A detached queries and Local/unknown view isolation")
	check(checks, a.world.ids("information_records").filter(func(id): return a.world.get_entity("information_records", id).owner_command_id == "OPERATIONAL_COMMAND").is_empty() and a.world.ids("messages").is_empty(), "A work item creates no command fact or message")
	Evaluation.send(a, Evaluation.report())
	a.advance(20)
	check(checks, records(a)[0].state == "OPEN" and records(a)[0].last_updated_at == 1 and not a.command_view("OPERATIONAL_COMMAND").superior_need_reports().is_empty(), "A later real report/time does not fulfill or update OPEN work item")
	check(checks, held.open_requirements().size() == 1 and held.recent_history().size() == 1, "A held recipient view remains a snapshot")
	record_case(checks, summaries, a, "A")
	var b: RefCounted = Demo.fresh()
	Evaluation.prompt(b, "DIRECT_ATTENTION", "AREA_FRONT_A")
	Evaluation.prompt(b, "REQUEST_ASSESSMENT", "AREA_HQ")
	b.advance(10)
	check(checks, records(b).size() == 2 and records(b).map(func(v): return v.area_id) == ["AREA_FRONT_A", "AREA_HQ"], "B unsupported attention and frontless assessment each open requirement")
	record_case(checks, summaries, b, "B")
	var c: RefCounted = Demo.fresh()
	Evaluation.send(c, Evaluation.report())
	Evaluation.prompt(c)
	Evaluation.prompt(c, "REQUEST_ASSESSMENT")
	c.advance(10)
	check(checks, c.player_prompts.snapshot().evaluations.map(func(v): return v.result) == ["KNOWN_CONCERN_PRESENT", "ASSESSMENT_AVAILABLE"] and records(c).is_empty() and c.information_requirements.events().is_empty(), "C supported active knowledge produces no requirement")
	Evaluation.send(c, Evaluation.resolved())
	c.advance()
	Evaluation.prompt(c)
	Evaluation.prompt(c, "REQUEST_ASSESSMENT")
	c.advance(9)
	check(checks, c.player_prompts.snapshot().evaluations.back().assessment_code == "KNOWN_AMMO_NEED_RESOLVED" and records(c).is_empty(), "C resolved knowledge also produces none")
	record_case(checks, summaries, c, "C")
	var d: RefCounted = Demo.fresh()
	var immediate: Array = []
	var store: RefCounted = d.information_requirements
	d.player_prompts.evaluation_completed.connect(func(source): immediate.append({"evaluation_id": source.evaluation_id, "events": store.events().size(), "time": source.evaluated_at}))
	for type in ["REQUEST_ASSESSMENT", "DIRECT_ATTENTION", "REQUEST_ASSESSMENT"]: Evaluation.prompt(d, type)
	d.advance(10)
	check(checks, records(d).size() == 1 and d.information_requirements.events().map(func(v): return v.event_type) == ["INFORMATION_REQUIREMENT_OPENED", "INFORMATION_REQUIREMENT_LINKED", "INFORMATION_REQUIREMENT_LINKED"], "D one OPEN plus two LINKED no duplicate work items")
	check(checks, records(d)[0].source_prompt_ids == ["player-prompt:0000000001", "player-prompt:0000000002", "player-prompt:0000000003"] and records(d)[0].source_evaluation_ids == ["prompt-evaluation:0000000001", "prompt-evaluation:0000000002", "prompt-evaluation:0000000003"], "D provenance retains actual first-link chronology")
	check(checks, immediate.map(func(v): return v.events) == [1, 2, 3] and immediate.all(func(v): return v.time == 1), "D each evaluation immediately opens/links before next evaluation")
	var count: int = d.information_requirements.events().size()
	check(checks, d.information_requirements.consider(d.player_prompts.snapshot().evaluations[0]).success and d.information_requirements.events().size() == count and records(d)[0].source_prompt_ids.size() == 3, "D repeated same source is idempotent no duplicate link/ID")
	d.advance(10)
	Evaluation.prompt(d)
	d.advance(10)
	check(checks, records(d).size() == 1 and records(d)[0].created_at == 1 and records(d)[0].last_updated_at == 3 and records(d)[0].source_prompt_ids.size() == 4, "D later qualifying evaluation links and updates only last_updated")
	check(checks, d.information_requirement_view("OPERATIONAL_COMMAND").recent_history(0).is_empty() and d.information_requirement_view("OPERATIONAL_COMMAND").recent_history(1).size() == 1, "D recipient history is bounded")
	record_case(checks, summaries, d, "D")
	var e: RefCounted = Demo.fresh()
	for area in ["AREA_FRONT_A", "AREA_FRONT_B", "AREA_FRONT_C"]: Evaluation.prompt(e, "REQUEST_ASSESSMENT", area)
	e.advance(10)
	check(checks, records(e).map(func(v): return v.requirement_id) == ["information-requirement:0000000001", "information-requirement:0000000002", "information-requirement:0000000003"] and records(e).map(func(v): return v.area_id) == ["AREA_FRONT_A", "AREA_FRONT_B", "AREA_FRONT_C"], "E independent area gaps IDs in deterministic evaluation order")
	record_case(checks, summaries, e, "E")
	var f: RefCounted = Demo.fresh()
	check(checks, f.player_view().current("AREA_FRONT_C").enemy_activity == "HIGH", "F player already sees alarming area independently")
	Evaluation.prompt(f, "REQUEST_ASSESSMENT")
	f.advance(10)
	check(checks, records(f).size() == 1 and safe_records(f.information_requirements.snapshot(), f.information_requirements.events()) and f.information_requirements._area_ids.AREA_FRONT_C == true, "F requirement holds only gap identity/provenance no copied HIGH/strength/ammo/world metadata")
	check(checks, not f.player_prompt_view().snapshot().has("requirements") and not f.player_prompt_view().current()[0].has("requirement_id"), "F no new player requirement-ID exposure")
	record_case(checks, summaries, f, "F")
	_multiple_owners(checks, summaries)
	_inertness(checks, summaries)
	_configuration_and_inputs(checks, summaries)
	_integrity(d, c, checks)
	var failures: Array = checks.filter(func(item): return not item.passed).map(func(item): return item.name)
	return {"success": failures.is_empty(), "checks": checks, "failures": failures, "scenarios": summaries}

static func _multiple_owners(checks: Array, summaries: Dictionary) -> void:
	var data := Demo.definition()
	data.commands.append({"id": "A_OTHER_OPERATIONAL", "command_level": "OPERATIONAL", "strategic_prompt_evaluation_enabled": true, "strategic_information_requirements_enabled": true})
	data.commands[3].superior_command_id = "A_OTHER_OPERATIONAL"
	var sim := Simulation.new()
	check(checks, sim.initialize(data, 112, "step112_G").success, "G two configured Operational owners initialize")
	sim.execute({"type": "SubmitPlayerPrompt", "prompt_type": "DIRECT_ATTENTION", "area_id": "AREA_FRONT_A", "recipient_command_id": "OPERATIONAL_COMMAND"})
	sim.execute({"type": "SubmitPlayerPrompt", "prompt_type": "REQUEST_ASSESSMENT", "area_id": "AREA_FRONT_C", "recipient_command_id": "A_OTHER_OPERATIONAL"})
	sim.advance(10)
	check(checks, records(sim).map(func(v): return v.owner_command_id) == ["A_OTHER_OPERATIONAL", "OPERATIONAL_COMMAND"] and records(sim).map(func(v): return v.requirement_id) == ["information-requirement:0000000001", "information-requirement:0000000002"], "G global requirement IDs follow deterministic evaluation order")
	check(checks, records(sim)[0].source_prompt_ids == ["player-prompt:0000000002"] and records(sim)[1].source_prompt_ids == ["player-prompt:0000000001"], "G cross-stream chronology not reordered by prompt ID")
	check(checks, sim.information_requirement_view("OPERATIONAL_COMMAND").open_requirements().size() == 1 and sim.information_requirement_view("OPERATIONAL_COMMAND").requirement("information-requirement:0000000001").is_empty() and sim.information_requirement_view("A_OTHER_OPERATIONAL").requirement("information-requirement:0000000002").is_empty() and sim.information_requirement_view("LOCAL_C").recent_history().is_empty(), "G owner-only records/history, no Local propagation")
	record_case(checks, summaries, sim, "G")

static func _inertness(checks: Array, summaries: Dictionary) -> void:
	var enabled: RefCounted = Demo.fresh(true, true, true)
	var disabled: RefCounted = Demo.fresh(false, true, true)
	enabled.start_time_utc = disabled.start_time_utc
	check(checks, exact(enabled.initial_world, disabled.initial_world) and enabled.initial_world.commands.values().all(func(c): return not c.has(Config.FIELD)), "H112 flag stripped before canonical projection")
	for tick in [0, 11, 39, 100, 150, 240]:
		for sim in [enabled, disabled]:
			sim.advance(tick - sim.world.clock().tick_index)
			Evaluation.prompt(sim, "REQUEST_ASSESSMENT" if tick % 2 else "DIRECT_ATTENTION")
	for sim in [enabled, disabled]: sim.advance(250 - sim.world.clock().tick_index)
	check(checks, enabled.events.count() == 3607 and exact(enabled.events.all(), disabled.events.all()) and exact(enabled.snapshot(), disabled.snapshot()), "H complete integrated military world/events/IDs identical without normalization")
	check(checks, exact(enabled.inputs, disabled.inputs) and exact(enabled.player_observer.events(), disabled.player_observer.events()) and exact(enabled.player_view().snapshot(), disabled.player_view().snapshot()) and exact(Exporter.prompt_projection(enabled), Exporter.prompt_projection(disabled)) and exact(enabled.player_prompts.events(), disabled.player_prompts.events()), "H111 evaluation/history and109observer remain absolutely identical")
	check(checks, records(enabled).size() == 1 and enabled.information_requirements.events().size() == 2 and records(disabled).is_empty() and disabled.information_requirements.events().is_empty(), "H first two unknown evaluations open/link one gap, disabled creates none")
	check(checks, records(enabled)[0].created_at == 1 and records(enabled)[0].last_updated_at == 2 and records(enabled)[0].state == "OPEN" and enabled.player_prompts.snapshot().evaluations.size() == 6, "H later supported evaluations leave prior requirement OPEN unchanged")
	for table in ["decisions", "decision_candidates", "resource_needs", "peer_coordinations", "superior_need_reports", "resource_arbitrations", "messages", "shipments", "resource_reservations", "information_records", "ledger"]:
		check(checks, exact(enabled.snapshot()[table], disabled.snapshot()[table]), "H no military or belief effect " + table)
	record_case(checks, summaries, enabled, "H_enabled")
	record_case(checks, summaries, disabled, "H_disabled")
	for file in ["initial_world.json", "events.jsonl", "final_world.json", "inputs.jsonl", "player_observer_config.json", "player_observation_events.jsonl", "final_player_observer.json", "player_prompt_evaluation_config.json", "player_prompt_events.jsonl", "final_player_prompts.json"]:
		check(checks, FileAccess.get_file_as_bytes("res://artifacts/run_step112_H_enabled/" + file) == FileAccess.get_file_as_bytes("res://artifacts/run_step112_H_disabled/" + file), "H actual file bytes identical " + file)
	for file in ["player_prompt_information_requirement_config.json", "information_requirement_events.jsonl", "final_information_requirements.json"]:
		check(checks, FileAccess.get_file_as_bytes("res://artifacts/run_step112_H_enabled/" + file) != FileAccess.get_file_as_bytes("res://artifacts/run_step112_H_disabled/" + file), "H only112 artifact differs " + file)
	var em: Dictionary = Exporter.read_json("res://artifacts/run_step112_H_enabled/manifest.json").details.value
	var dm: Dictionary = Exporter.read_json("res://artifacts/run_step112_H_disabled/manifest.json").details.value
	em.erase("information_requirement")
	dm.erase("information_requirement")
	check(checks, exact(em, dm), "H only112 manifest metadata differs")
	var zero_enabled: RefCounted = Demo.fresh()
	var zero_disabled: RefCounted = Demo.fresh(false)
	zero_enabled.advance(30)
	zero_disabled.advance(30)
	check(checks, exact(zero_enabled.snapshot(), zero_disabled.snapshot()) and exact(zero_enabled.events.all(), zero_disabled.events.all()) and exact(zero_enabled.information_requirements.snapshot(), zero_disabled.information_requirements.snapshot()) and zero_enabled.information_requirements.events().is_empty(), "J no prompts config toggle alone inert")
	record_case(checks, summaries, zero_enabled, "J_zero_enabled")
	record_case(checks, summaries, zero_disabled, "J_zero_disabled")

static func _configuration_and_inputs(checks: Array, summaries: Dictionary) -> void:
	var sim: RefCounted = Demo.fresh()
	for entry in [[[{"operational_command_id": "UNKNOWN", "enabled": true}], "UNKNOWN_COMMAND"], [[{"operational_command_id": "LOCAL_C", "enabled": true}], "COMMAND_NOT_OPERATIONAL"], [[{"operational_command_id": "OPERATIONAL_COMMAND", "enabled": "YES"}], "INVALID_ENABLED_VALUE"], [[{"operational_command_id": "OPERATIONAL_COMMAND", "enabled": true}, {"operational_command_id": "OPERATIONAL_COMMAND", "enabled": false}], "DUPLICATE_COMMAND_CONFIG"], [{}, "INVALID_PROMPT_EVALUATION_CONFIGURATION"], [[{"operational_command_id": "OPERATIONAL_COMMAND", "enabled": true, "payload": "EXTRA"}], "INVALID_PROMPT_EVALUATION_CONFIGURATION"]]:
		var fresh := Simulation.new()
		check(checks, fresh.initialize_snapshot(sim.initial_world, sim.player_observer.configuration().values(), sim.prompt_evaluation_configuration(), entry[0]).error_code == entry[1] and fresh.world == null and fresh.events.count() == 0, "configuration invalid before world start " + entry[1])
	var definition := Demo.definition()
	definition.commands[0].strategic_information_requirements_enabled = 1
	check(checks, Simulation.new().initialize(definition).error_code == "INVALID_ENABLED_VALUE", "source flag malformed value not ignored")
	var configuration: Array = sim.information_requirement_configuration()
	configuration[0].enabled = false
	check(checks, sim.information_requirement_configuration()[0].enabled, "config query detached")
	for type in ["CreateInformationRequirement", "LaunchRecon", "InvestigateArea"]:
		check(checks, sim.execute({"type": type}).error_code == "INVALID_INPUT" and records(sim).is_empty() and sim.information_requirements.events().is_empty(), "no new player input " + type)
	var evaluation_off: RefCounted = Demo.fresh(true, false)
	Evaluation.prompt(evaluation_off, "REQUEST_ASSESSMENT")
	evaluation_off.advance(30)
	check(checks, evaluation_off.player_prompt_view().current()[0].state == "PENDING_EVALUATION" and records(evaluation_off).is_empty(), "112 enabled without111 evaluation cannot create work item")
	record_case(checks, summaries, evaluation_off, "evaluation_disabled")
	var requirements_off: RefCounted = Demo.fresh(false)
	Evaluation.prompt(requirements_off, "REQUEST_ASSESSMENT")
	requirements_off.advance(10)
	check(checks, requirements_off.player_prompt_view().current()[0].result == "FURTHER_INFORMATION_REQUIRED" and records(requirements_off).is_empty(), "112 defaultfalse preserves accepted111 result only")
	record_case(checks, summaries, requirements_off, "requirements_disabled")
	var counter: RefCounted = Demo.fresh()
	Evaluation.send(counter, Evaluation.report())
	Evaluation.prompt(counter, "REQUEST_ASSESSMENT")
	Evaluation.prompt(counter, "REQUEST_ASSESSMENT", "AREA_HQ")
	counter.advance(10)
	check(checks, records(counter).size() == 1 and records(counter)[0].requirement_id == "information-requirement:0000000001" and records(counter)[0].source_evaluation_ids == ["prompt-evaluation:0000000002"], "requirement counter independent from evaluation/prompt/world counters")

static func _integrity(gaps: RefCounted, supported: RefCounted, checks: Array) -> void:
	var directory := "res://artifacts/run_step112_tampered"
	for field in ["requirement_id", "owner_command_id", "area_id", "requirement_type", "state", "previous_requirement_event_id", "source_prompt_id", "source_evaluation_id", "source_evaluation_event_id", "metadata", "created_at", "run_id"]:
		Exporter.export_run(gaps, directory)
		var events: Array = Exporter.read_lines(directory.path_join("information_requirement_events.jsonl")).details.value
		if field == "metadata": events[0][field] = {"enemy_activity": "HIGH", "available_ammo": 777}
		elif field == "created_at": events[0][field] = 0
		else: events[0][field] = "FORGED"
		Exporter.write_json(directory.path_join("information_requirement_events.jsonl"), events, true)
		var manifest: Dictionary = Exporter.read_json(directory.path_join("manifest.json")).details.value
		if field == "requirement_id": check(checks, Exporter.replay_package(directory).error_code == "REQUIREMENT_PACKAGE_HASH_MISMATCH", "I changed requirement-event hash rejected")
		manifest.information_requirement.sha256 = FileAccess.get_sha256(directory.path_join("information_requirement_events.jsonl"))
		Exporter.write_json(directory.path_join("manifest.json"), manifest)
		check(checks, Exporter.replay_package(directory).error_code == "INFORMATION_REQUIREMENT_REPLAY_MISMATCH", "I rehashed forged event rejected " + field)
		var rebuilt := reconstruct(gaps)
		check(checks, not rebuilt.apply_event(events[0]).success and rebuilt.events().is_empty(), "I event-only validation rejects forged " + field)
	var rebuilt := reconstruct(gaps)
	var original: Array = gaps.information_requirements.events()
	rebuilt.apply_event(original[0])
	var duplicate: Dictionary = original[1].duplicate(true)
	duplicate.event_type = "INFORMATION_REQUIREMENT_OPENED"
	duplicate.requirement_id = "information-requirement:0000000002"
	check(checks, not rebuilt.apply_event(duplicate).success and rebuilt.snapshot().requirements.size() == 1, "I duplicate OPEN for samekey rejected")
	var nonqualifying := reconstruct(supported)
	var forged: Dictionary = original[0].duplicate(true)
	var source: Dictionary = supported.player_prompts.snapshot().evaluations[0]
	forged.source_prompt_id = source.prompt_id
	forged.source_evaluation_id = source.evaluation_id
	forged.source_evaluation_event_id = source.evaluated_event_id
	check(checks, not nonqualifying.apply_event(forged).success and nonqualifying.events().is_empty(), "I known-source evaluation without information gap cannot open requirement")
	Exporter.export_run(gaps, directory)
	var projection: Dictionary = Exporter.read_json(directory.path_join("final_information_requirements.json")).details.value
	projection.state.requirements[0].state = "SATISFIED"
	Exporter.write_json(directory.path_join("final_information_requirements.json"), projection)
	var manifest: Dictionary = Exporter.read_json(directory.path_join("manifest.json")).details.value
	manifest.information_requirement.projection_sha256 = FileAccess.get_sha256(directory.path_join("final_information_requirements.json"))
	Exporter.write_json(directory.path_join("manifest.json"), manifest)
	check(checks, Exporter.replay_package(directory).error_code == "INFORMATION_REQUIREMENT_REPLAY_MISMATCH", "I rehashed projection inconsistent with event stream rejected")
	Exporter.export_run(gaps, directory)
	var config: Dictionary = Exporter.read_json(directory.path_join("player_prompt_information_requirement_config.json")).details.value
	config.commands[0].enabled = false
	Exporter.write_json(directory.path_join("player_prompt_information_requirement_config.json"), config)
	check(checks, Exporter.replay_package(directory).error_code == "REQUIREMENT_PACKAGE_HASH_MISMATCH", "I altered config hash rejected")
	manifest = Exporter.read_json(directory.path_join("manifest.json")).details.value
	manifest.information_requirement.config_sha256 = FileAccess.get_sha256(directory.path_join("player_prompt_information_requirement_config.json"))
	Exporter.write_json(directory.path_join("manifest.json"), manifest)
	check(checks, Exporter.replay_package(directory).error_code == "INFORMATION_REQUIREMENT_REPLAY_MISMATCH", "I rehashed disabledconfig cannot produce recorded requirements")
	Exporter.export_run(gaps, directory)
	check(checks, Exporter.replay_package(directory).success, "I valid strict replay allstreams/projections")
