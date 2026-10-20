extends RefCounted
const Demo = preload("res://debug/prompt_evaluation_demo.gd")
const Simulation = preload("res://kernel/simulation.gd")
const Policy = preload("res://kernel/prompt_evaluation_policy.gd")
const Config = preload("res://kernel/prompt_evaluation_config.gd")
const Prompts = preload("res://kernel/player_prompt_service.gd")
const Exporter = preload("res://kernel/run_exporter.gd")
const Needs = preload("res://tests/resource_resolution_cases.gd")

static func check(checks: Array, valid: bool, name: String) -> void:
	checks.append({"name": "111 / " + name, "passed": valid})

static func exact(a: Variant, b: Variant) -> bool:
	return Exporter.observer_equivalent(a, b)

static func evaluations(sim: RefCounted) -> Array:
	return sim.player_prompts.snapshot().evaluations

static func record_case(checks: Array, summaries: Dictionary, sim: RefCounted, name: String) -> void:
	var directory := "res://artifacts/run_step111_" + name
	check(checks, Exporter.export_run(sim, directory).success, name + " exports world/observer/prompt/evaluation-config")
	var rebuilt := Prompts.new(sim.player_observer.configuration())
	var valid := true
	for event in sim.player_prompts.events():
		if not rebuilt.apply_event(event).success: valid = false
	check(checks, valid and exact(rebuilt.snapshot(), sim.player_prompts.snapshot()) and exact(rebuilt.view().snapshot(), sim.player_prompt_view().snapshot()), name + " exact event-only prompt/evaluation reconstruction")
	check(checks, Needs.conserved_prefixes(sim), name + " every authoritative prefix conserves stock/cargo/claims")
	check(checks, safe_view(sim.player_prompt_view().snapshot()), name + " no exact quantities/report/message/need IDs in player data")
	summaries[name] = {"world_events": sim.events.count(), "observer_events": sim.player_observer.events().size(), "prompt_events": sim.player_prompts.events().size(), "inputs": sim.inputs.size(), "end_tick": sim.world.clock().tick_index, "evaluations": evaluations(sim), "prompts": sim.player_prompts.snapshot().prompts, "ledger": sim.audit()}

static func safe_view(view: Dictionary) -> bool:
	for prompt in view.prompts:
		if prompt.keys().any(func(k): return k not in ["prompt_id", "prompt_type", "area_id", "recipient_command_id", "submitted_at", "received_at", "state", "result", "assessment_code", "evaluated_at"]): return false
	for event in view.history:
		if event.keys().any(func(k): return k not in ["prompt_id", "prompt_type", "area_id", "recipient_command_id", "at", "event_type", "result", "assessment_code", "evaluated_at"]): return false
	return true

static func run() -> Dictionary:
	var checks: Array = []
	var summaries: Dictionary = {}
	var a: RefCounted = Demo.fresh()
	var sent: Dictionary = Demo.send(a, Demo.report())
	Demo.prompt(a)
	a.advance(9)
	check(checks, evaluations(a).is_empty() and a.player_prompt_view().current()[0].state == "PENDING_EVALUATION", "A no evaluation on100ms ticks before1s")
	var info: Array = a.command_view("OPERATIONAL_COMMAND").information()
	a.advance()
	var e: Dictionary = evaluations(a)[0]
	check(checks, e.result == "KNOWN_CONCERN_PRESENT" and e.assessment_code == "ACTIVE_AMMO_SUPPLY_CONCERN" and e.evaluated_at == 1 and e.state == "COMPLETED", "A active attention exact result at1s")
	check(checks, e.knowledge_reports[0].need_id == "fixture:C" and e.knowledge_reports[0].need_revision == 1 and e.knowledge_message_ids == [sent.entity_id] and e.primary_report_id == "need-report:OPERATIONAL_COMMAND:fixture:C", "A provenance delivered report/message/need/revision exact")
	check(checks, a.player_prompt_view().current()[0].state == "EVALUATED" and a.command_prompt_view("LOCAL_C").current().is_empty(), "A evaluated lifecycle and Local isolation")
	check(checks, exact(info, a.command_view("OPERATIONAL_COMMAND").information()) and a.world.ids("shipments").size() == 1, "A no evaluation information/message/military action")
	var count: int = a.world.ids("messages").size()
	a.advance(20)
	check(checks, evaluations(a).size() == 1 and a.world.ids("messages").size() == count, "A evaluates once no repeated response/subordinate message")
	record_case(checks, summaries, a, "A")
	var b: RefCounted = Demo.fresh()
	Demo.send(b, Demo.report())
	Demo.prompt(b, "REQUEST_ASSESSMENT")
	b.advance(10)
	check(checks, evaluations(b)[0].result == "ASSESSMENT_AVAILABLE" and evaluations(b)[0].assessment_code == "ACTIVE_AMMO_SUPPLY_PROBLEM", "B active assessment qualitative")
	check(checks, b.player_prompt_view().status("player-prompt:0000000001").keys().all(func(k): return k not in ["knowledge_reports", "primary_report_id", "knowledge_report_ids", "knowledge_message_ids", "metadata"]), "B provenance/exact amounts hidden even in backing view")
	record_case(checks, summaries, b, "B")
	var c: RefCounted = Demo.fresh()
	Demo.prompt(c, "REQUEST_ASSESSMENT")
	c.advance(10)
	check(checks, not c.player_view().current("AREA_FRONT_C").is_empty() and c.command_view("OPERATIONAL_COMMAND").superior_need_reports().is_empty(), "C player sees area but command has no delivered report")
	check(checks, evaluations(c)[0].result == "FURTHER_INFORMATION_REQUIRED" and evaluations(c)[0].assessment_code == "NO_SUPPORTED_AREA_INFORMATION" and evaluations(c)[0].knowledge_reports.is_empty(), "C no player-truth shortcut or invented concern")
	check(checks, c.world.ids("messages").is_empty() and c.world.ids("resource_needs").is_empty(), "C information-required is result only no recon/task/message")
	Demo.prompt(c, "REQUEST_ASSESSMENT", "AREA_HQ")
	c.advance(10)
	check(checks, evaluations(c).back().result == "FURTHER_INFORMATION_REQUIRED", "frontless HQ has no supported assessment domain")
	record_case(checks, summaries, c, "C")
	var d: RefCounted = Demo.fresh()
	Demo.send(d, Demo.report())
	d.advance()
	var resolution: Dictionary = Demo.send(d, Demo.resolved())
	d.advance()
	Demo.prompt(d)
	Demo.prompt(d, "REQUEST_ASSESSMENT")
	d.advance(8)
	check(checks, evaluations(d).map(func(v): return v.result) == ["NO_ACTIVE_KNOWN_CONCERN", "ASSESSMENT_AVAILABLE"] and evaluations(d).map(func(v): return v.assessment_code) == ["LAST_KNOWN_AMMO_NEED_RESOLVED", "KNOWN_AMMO_NEED_RESOLVED"], "D delivered resolution both prompt policies")
	check(checks, evaluations(d).all(func(v): return v.knowledge_reports[0].need_revision == 2 and v.knowledge_message_ids == [resolution.entity_id] and v.knowledge_reports[0].report_state == "RESOLVED"), "D current resolved projection replaces original active message/revision")
	record_case(checks, summaries, d, "D")
	var boundary: RefCounted = Demo.fresh(true, 1.0)
	sent = Demo.send(boundary, Demo.report())
	Demo.prompt(boundary)
	boundary.advance(9)
	check(checks, boundary.command_view("OPERATIONAL_COMMAND").superior_need_reports().is_empty() and evaluations(boundary).is_empty(), "E report unavailable before boundary")
	boundary.advance()
	check(checks, evaluations(boundary)[0].result == "KNOWN_CONCERN_PRESENT" and evaluations(boundary)[0].knowledge_reports[0].report_received_at_micro == 1000000 and evaluations(boundary)[0].evaluated_at == 1 and evaluations(boundary)[0].knowledge_message_ids == [sent.entity_id], "E delivery/projection at1.0 available to same-boundary evaluation")
	record_case(checks, summaries, boundary, "E")
	var delayed: RefCounted = Demo.fresh(true, 2.0)
	Demo.send(delayed, Demo.report())
	Demo.prompt(delayed, "REQUEST_ASSESSMENT")
	delayed.advance(10)
	check(checks, evaluations(delayed)[0].result == "FURTHER_INFORMATION_REQUIRED" and evaluations(b)[0].result == "ASSESSMENT_AVAILABLE" and exact(b.world.get_front("FRONT_C"), delayed.world.get_front("FRONT_C")), "F same objective front/different delivered knowledge gives different assessment")
	delayed.advance(20)
	check(checks, not delayed.command_view("OPERATIONAL_COMMAND").superior_need_reports().is_empty() and evaluations(delayed).size() == 1 and evaluations(delayed)[0].result == "FURTHER_INFORMATION_REQUIRED", "F later report does not reevaluate completed prompt")
	record_case(checks, summaries, delayed, "F")
	var stale: RefCounted = Demo.fresh()
	sent = Demo.send(stale, Demo.report())
	stale.advance(200)
	stale.execute({"type": "CreateResource", "stockpile_id": "C_FRONT_STOCK", "resource_type_id": "AMMUNITION", "quantity": 1000}, true)
	stale.execute({"type": "SetEnabled", "table": "communication_edges", "entity_id": "LOCAL_C_to_OPERATIONAL_COMMAND", "enabled": false}, true)
	check(checks, not Demo.send(stale, Demo.resolved()).success, "G resolution transport failed, delivered active report remains")
	Demo.prompt(stale)
	stale.advance(10)
	e = evaluations(stale)[0]
	check(checks, e.result == "KNOWN_CONCERN_PRESENT" and e.knowledge_reports[0].need_revision == 1 and e.knowledge_message_ids == [sent.entity_id] and e.knowledge_reports[0].source_observed_at_micro == 0 and e.knowledge_reports[0].report_received_at_micro == 100000 and e.evaluated_at == 21, "G stale20.9s delivered report used without freshness cutoff or hidden inventory")
	check(checks, stale.world.get_stockpile("C_FRONT_STOCK").quantities.AMMUNITION > 80, "G actual subordinate stock contradicts stale known shortage")
	record_case(checks, summaries, stale, "G")
	_inertness(checks, summaries)
	_multiple_reports(checks, summaries)
	_policy_and_configuration(checks)
	_integrity(b, checks)
	var failures: Array = checks.filter(func(item): return not item.passed).map(func(item): return item.name)
	return {"success": failures.is_empty(), "checks": checks, "failures": failures, "scenarios": summaries}

static func _multiple_reports(checks: Array, summaries: Dictionary) -> void:
	var sim: RefCounted = Demo.fresh()
	for need in ["fixture:Z", "fixture:A", "fixture:R"]: Demo.send(sim, Demo.report(1, need))
	var resolved: Dictionary = Demo.send(sim, Demo.resolved(2, "fixture:R"))
	Demo.prompt(sim)
	Demo.prompt(sim, "REQUEST_ASSESSMENT")
	sim.advance(10)
	var first: Dictionary = evaluations(sim)[0]
	check(checks, first.primary_report_id == "need-report:OPERATIONAL_COMMAND:fixture:A" and first.knowledge_reports.size() == 3 and first.knowledge_reports.map(func(r): return r.need_id) == ["fixture:A", "fixture:R", "fixture:Z"], "multiple actual delivered needs samefront canonical provenance and active tie")
	check(checks, first.knowledge_reports[1].report_state == "RESOLVED" and first.knowledge_reports[1].need_revision == 2 and first.knowledge_reports[1].report_message_id == resolved.entity_id and evaluations(sim)[1].result == "ASSESSMENT_AVAILABLE", "current delivered projection uses resolution revision/message not raw historical report")
	record_case(checks, summaries, sim, "multi_reports")
	var data := Demo.definition()
	data.commands.append({"id": "A_OTHER_OPERATIONAL", "command_level": "OPERATIONAL", "strategic_prompt_evaluation_enabled": true})
	data.commands[3].superior_command_id = "A_OTHER_OPERATIONAL"
	var recipients := Simulation.new()
	check(checks, recipients.initialize(data, 111, "multi_recipients").success, "multiple enabled Operational command configuration valid")
	recipients.execute({"type": "SubmitPlayerPrompt", "prompt_type": "DIRECT_ATTENTION", "area_id": "AREA_FRONT_A", "recipient_command_id": "OPERATIONAL_COMMAND"})
	recipients.execute({"type": "SubmitPlayerPrompt", "prompt_type": "REQUEST_ASSESSMENT", "area_id": "AREA_FRONT_C", "recipient_command_id": "A_OTHER_OPERATIONAL"})
	recipients.advance(10)
	check(checks, evaluations(recipients).map(func(e): return e.prompt_id) == ["player-prompt:0000000002", "player-prompt:0000000001"] and evaluations(recipients).map(func(e): return e.evaluation_id) == ["prompt-evaluation:0000000001", "prompt-evaluation:0000000002"], "cross-recipient evaluation IDs deterministic commandID then accepted prompt order")
	check(checks, recipients.command_prompt_view("A_OTHER_OPERATIONAL").current().size() == 1 and recipients.command_prompt_view("OPERATIONAL_COMMAND").current().size() == 1 and recipients.command_prompt_view("LOCAL_C").current().is_empty(), "evaluated recipient inbox isolation preserved")
	record_case(checks, summaries, recipients, "multi_recipients")

static func _inertness(checks: Array, summaries: Dictionary) -> void:
	var enabled: RefCounted = Demo.fresh(true, 0.1, true)
	var disabled: RefCounted = Demo.fresh(false, 0.1, true)
	enabled.start_time_utc = disabled.start_time_utc
	check(checks, exact(enabled.initial_world, disabled.initial_world) and enabled.snapshot().commands.values().all(func(c): return not c.has(Config.FIELD)), "H flag stripped before canonicalWorldState/COMMAND_CREATED")
	for tick in [0, 11, 39, 100, 150, 240]:
		enabled.advance(tick - enabled.world.clock().tick_index)
		disabled.advance(tick - disabled.world.clock().tick_index)
		for sim in [enabled, disabled]: Demo.prompt(sim, "REQUEST_ASSESSMENT" if tick % 2 else "DIRECT_ATTENTION")
	enabled.advance(250 - enabled.world.clock().tick_index)
	disabled.advance(250 - disabled.world.clock().tick_index)
	check(checks, evaluations(enabled).size() == 6 and evaluations(disabled).is_empty() and disabled.player_prompt_view().current().all(func(p): return p.state == "PENDING_EVALUATION"), "H sixenabled evaluations vs110compatible pending-only disabled")
	check(checks, enabled.player_prompts.events().size() == 18 and disabled.player_prompts.events().size() == 12 and evaluations(enabled).map(func(e): return e.evaluation_id) == ["prompt-evaluation:0000000001", "prompt-evaluation:0000000002", "prompt-evaluation:0000000003", "prompt-evaluation:0000000004", "prompt-evaluation:0000000005", "prompt-evaluation:0000000006"], "H independent evaluation namespace and interleaved submission IDs")
	check(checks, evaluations(enabled).map(func(e): return e.evaluated_at) == [1.0, 2.0, 4.0, 11.0, 16.0, 25.0], "H eachprompt nextwhole-second boundary exactlyonce")
	check(checks, exact(enabled.events.all(), disabled.events.all()) and exact(enabled.snapshot(), disabled.snapshot()) and enabled.events.count() == 3607, "H full integrated3607 authoritative events/IDs/state exact without normalization")
	check(checks, exact(enabled.inputs, disabled.inputs) and exact(enabled.player_observer.snapshot(), disabled.player_observer.snapshot()) and exact(enabled.player_observer.events(), disabled.player_observer.events()), "H identical input history and absolute observer separation")
	for table in ["decisions", "decision_candidates", "resource_needs", "peer_coordinations", "superior_need_reports", "resource_arbitrations", "messages", "shipments", "information_records", "ledger"]:
		check(checks, exact(enabled.snapshot()[table], disabled.snapshot()[table]), "H exact military inertness " + table)
	record_case(checks, summaries, enabled, "H_enabled")
	record_case(checks, summaries, disabled, "H_disabled")
	for file in ["initial_world.json", "final_world.json", "events.jsonl", "inputs.jsonl", "player_observer_config.json", "player_observation_events.jsonl", "final_player_observer.json"]:
		check(checks, FileAccess.get_file_as_bytes("res://artifacts/run_step111_H_enabled/" + file) == FileAccess.get_file_as_bytes("res://artifacts/run_step111_H_disabled/" + file), "H actualbyteidentity " + file)
	for file in ["player_prompt_evaluation_config.json", "player_prompt_events.jsonl", "final_player_prompts.json"]:
		check(checks, FileAccess.get_file_as_bytes("res://artifacts/run_step111_H_enabled/" + file) != FileAccess.get_file_as_bytes("res://artifacts/run_step111_H_disabled/" + file), "H only prompt-specific difference " + file)
	var em: Dictionary = Exporter.read_json("res://artifacts/run_step111_H_enabled/manifest.json").details.value
	var dm: Dictionary = Exporter.read_json("res://artifacts/run_step111_H_disabled/manifest.json").details.value
	em.erase("player_prompt")
	dm.erase("player_prompt")
	check(checks, exact(em, dm), "H no unrelated manifest differences")
	var zero_on: RefCounted = Demo.fresh()
	var zero_off: RefCounted = Demo.fresh(false)
	zero_on.advance(30)
	zero_off.advance(30)
	check(checks, exact(zero_on.events.all(), zero_off.events.all()) and exact(zero_on.snapshot(), zero_off.snapshot()) and exact(zero_on.player_prompts.snapshot(), zero_off.player_prompts.snapshot()) and zero_on.player_prompts.events().is_empty() and evaluations(zero_on).is_empty(), "zero-prompt config toggle alone has zero evaluation/projection/world differences")
	record_case(checks, summaries, zero_on, "zero_enabled")
	record_case(checks, summaries, zero_off, "zero_disabled")

static func _policy_and_configuration(checks: Array) -> void:
	var data := Demo.definition()
	var sim := Simulation.new()
	check(checks, sim.initialize(data, 111, "configuration").success, "valid separate config initializes")
	for entry in [[[{"operational_command_id": "MISSING", "enabled": true}], "UNKNOWN_COMMAND"], [[{"operational_command_id": "LOCAL_C", "enabled": true}], "COMMAND_NOT_OPERATIONAL"], [[{"operational_command_id": "OPERATIONAL_COMMAND", "enabled": 1}], "INVALID_ENABLED_VALUE"], [[{"operational_command_id": "OPERATIONAL_COMMAND", "enabled": true}, {"operational_command_id": "OPERATIONAL_COMMAND", "enabled": false}], "DUPLICATE_COMMAND_CONFIG"], [{}, "INVALID_PROMPT_EVALUATION_CONFIGURATION"], [[{"operational_command_id": "OPERATIONAL_COMMAND", "enabled": true, "text": "EXTRA"}], "INVALID_PROMPT_EVALUATION_CONFIGURATION"]]:
		var fresh := Simulation.new()
		check(checks, fresh.initialize_snapshot(sim.initial_world, sim.player_observer.configuration().values(), entry[0]).error_code == entry[1] and fresh.world == null and fresh.events.count() == 0, "invalid config fails before any world event " + entry[1])
	data.commands[0].strategic_prompt_evaluation_enabled = "YES"
	check(checks, Simulation.new().initialize(data).error_code == "INVALID_ENABLED_VALUE", "raw source flag type validated not silently ignored")
	data = Demo.definition()
	data.commands[1].strategic_prompt_evaluation_enabled = false
	check(checks, Simulation.new().initialize(data).error_code == "COMMAND_NOT_OPERATIONAL", "Local command cannot configure even explicitfalse flag")
	check(checks, Config.normalize([{"operational_command_id": "OPERATIONAL_COMMAND", "enabled": true}], sim.initial_world.commands, 0.3).error_code == "INVALID_PROMPT_EVALUATION_TICK_PRECISION", "opt-in cadence requires exactwhole-second compatible ticks")
	var copy: Array = sim.prompt_evaluation_configuration()
	copy[0].enabled = false
	check(checks, sim.prompt_evaluation_configuration()[0].enabled, "detached config query cannot change enabled state")
	var prompt := {"recipient_command_id": "OPERATIONAL_COMMAND", "prompt_type": "DIRECT_ATTENTION"}
	var area := {"front_id": "FRONT_C"}
	var r1 := {"id": "report:Z", "superior_command_id": "OPERATIONAL_COMMAND", "front_id": "FRONT_C", "report_state": "ACTIVE", "need_id": "need:Z", "need_revision": 2, "report_message_id": "message:Z", "source_observed_at_micro": 0, "report_received_at_micro": 100000}
	var r2: Dictionary = r1.duplicate(true)
	r2.id = "report:A"
	r2.need_id = "need:A"
	r2.report_message_id = "message:A"
	var r3: Dictionary = r1.duplicate(true)
	r3.id = "report:R"
	r3.need_id = "need:R"
	r3.report_message_id = "message:R"
	r3.report_state = "RESOLVED"
	r3.report_received_at_micro = 900000
	var evaluated := Policy.evaluate(prompt, area, [r3, r1, r2])
	check(checks, evaluated.primary_report_id == "report:A" and evaluated.result == "KNOWN_CONCERN_PRESENT", "active wins newer resolved then equal-time needIDascending tie")
	check(checks, evaluated.knowledge_report_ids == ["report:A", "report:R", "report:Z"] and evaluated.knowledge_message_ids == ["message:A", "message:R", "message:Z"], "all material current reports/messages in canonical order")
	check(checks, exact(evaluated, Policy.evaluate(prompt, area, [r2, r1, r3])), "policy input report order cannot affect selection/provenance")
	r1.report_received_at_micro = 200000
	check(checks, Policy.evaluate(prompt, area, [r2, r1, r3]).primary_report_id == "report:Z", "latestreceived active before needIDtie")
	r1.superior_command_id = "OTHER_OPERATIONAL"
	check(checks, Policy.evaluate(prompt, area, [r1]).result == "FURTHER_INFORMATION_REQUIRED", "foreign recipient report never used")
	r1.superior_command_id = "OPERATIONAL_COMMAND"
	r1.front_id = "OTHER_FRONT"
	check(checks, Policy.evaluate(prompt, area, [r1]).result == "FURTHER_INFORMATION_REQUIRED", "other front report never used")
	r2.exact_quantity = 987654
	r2.player_observation = "HIGH"
	check(checks, not JSON.stringify(Policy.evaluate(prompt, area, [r2])).contains("987654") and not JSON.stringify(Policy.evaluate(prompt, area, [r2])).contains("player_observation"), "policy whitelists only supported delivered report provenance no unrelated payload")
	# A prompt submitted exactly on a completed boundary waits until the next one.
	var timing: RefCounted = Demo.fresh()
	timing.advance(10)
	Demo.prompt(timing, "REQUEST_ASSESSMENT")
	var held: RefCounted = timing.player_prompt_view()
	timing.advance(9)
	check(checks, evaluations(timing).is_empty(), "boundary-time external prompt not evaluated retroactively")
	timing.advance()
	check(checks, evaluations(timing).size() == 1 and evaluations(timing)[0].evaluated_at == 2 and held.current()[0].state == "PENDING_EVALUATION", "next boundary at2 and held publicview detached")

static func _integrity(sim: RefCounted, checks: Array) -> void:
	var directory := "res://artifacts/run_step111_tampered"
	for field in ["result", "assessment_code", "evaluation_id", "primary_report_id", "knowledge_report_ids", "knowledge_message_ids", "knowledge_reports", "evaluated_at", "previous_prompt_event_id", "prompt_id", "run_id"]:
		Exporter.export_run(sim, directory)
		var events: Array = Exporter.read_lines(directory.path_join("player_prompt_events.jsonl")).details.value
		var row: Dictionary = events.back()
		if field in ["knowledge_report_ids", "knowledge_message_ids"]: row[field] = ["FORGED"]
		elif field == "knowledge_reports": row.knowledge_reports[0].need_revision = 999
		elif field == "evaluated_at": row[field] = 2
		else: row[field] = "FORGED"
		Exporter.write_json(directory.path_join("player_prompt_events.jsonl"), events, true)
		var manifest: Dictionary = Exporter.read_json(directory.path_join("manifest.json")).details.value
		if field == "result": check(checks, Exporter.replay_package(directory).error_code == "PROMPT_PACKAGE_HASH_MISMATCH", "I evaluationstream changedhash rejected")
		manifest.player_prompt.sha256 = FileAccess.get_sha256(directory.path_join("player_prompt_events.jsonl"))
		Exporter.write_json(directory.path_join("manifest.json"), manifest)
		check(checks, Exporter.replay_package(directory).error_code == "PLAYER_PROMPT_REPLAY_MISMATCH", "I rehashed forged evaluation rejected " + field)
	Exporter.export_run(sim, directory)
	var projection: Dictionary = Exporter.read_json(directory.path_join("final_player_prompts.json")).details.value
	projection.view.prompts[0].uncovered_quantity = 777
	Exporter.write_json(directory.path_join("final_player_prompts.json"), projection)
	var manifest: Dictionary = Exporter.read_json(directory.path_join("manifest.json")).details.value
	manifest.player_prompt.projection_sha256 = FileAccess.get_sha256(directory.path_join("final_player_prompts.json"))
	Exporter.write_json(directory.path_join("manifest.json"), manifest)
	check(checks, Exporter.replay_package(directory).error_code == "PLAYER_PROMPT_REPLAY_MISMATCH", "I rehashed exact-number player-field injection rejected")
	Exporter.export_run(sim, directory)
	var config: Dictionary = Exporter.read_json(directory.path_join("player_prompt_evaluation_config.json")).details.value
	config.commands[0].enabled = false
	Exporter.write_json(directory.path_join("player_prompt_evaluation_config.json"), config)
	check(checks, Exporter.replay_package(directory).error_code == "PROMPT_PACKAGE_HASH_MISMATCH", "I config changedhash rejected")
	manifest = Exporter.read_json(directory.path_join("manifest.json")).details.value
	manifest.player_prompt.evaluation_config.sha256 = FileAccess.get_sha256(directory.path_join("player_prompt_evaluation_config.json"))
	Exporter.write_json(directory.path_join("manifest.json"), manifest)
	check(checks, Exporter.replay_package(directory).error_code == "PLAYER_PROMPT_REPLAY_MISMATCH", "I rehashed disabledconfig cannot explain recorded evaluation")
	Exporter.export_run(sim, directory)
	check(checks, Exporter.replay_package(directory).success, "I original strict replay all streams/projections passes")
	var reconstructed := Prompts.new(sim.player_observer.configuration())
	for event in sim.player_prompts.events(): reconstructed.apply_event(event)
	var duplicated: Dictionary = sim.player_prompts.events().back()
	duplicated.prompt_event_id = "player-prompt-event:0000000004"
	duplicated.previous_prompt_event_id = "player-prompt-event:0000000003"
	check(checks, not reconstructed.apply_event(duplicated).success and reconstructed.snapshot().evaluations.size() == 1, "I event reconstruction rejects second evaluation of same prompt")
