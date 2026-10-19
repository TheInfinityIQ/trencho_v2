extends RefCounted
const Demo = preload("res://debug/player_prompt_demo.gd")
const Observation = preload("res://debug/player_observation_demo.gd")
const Simulation = preload("res://kernel/simulation.gd")
const Prompts = preload("res://kernel/player_prompt_service.gd")
const Exporter = preload("res://kernel/run_exporter.gd")
const Needs = preload("res://tests/resource_resolution_cases.gd")

static func check(checks: Array, valid: bool, name: String) -> void:
	checks.append({"name": "110 / " + name, "passed": valid})

static func exact(a: Variant, b: Variant) -> bool:
	return Exporter.observer_equivalent(a, b)

static func record_case(checks: Array, summaries: Dictionary, sim: RefCounted, name: String) -> void:
	var directory := "res://artifacts/run_step110_" + name
	check(checks, Exporter.export_run(sim, directory).success, name + " exports authoritative intent package")
	var rebuilt := Prompts.new()
	var valid := true
	for event in sim.player_prompts.events():
		if not rebuilt.apply_event(event).success: valid = false
	check(checks, valid and exact(rebuilt.snapshot(), sim.player_prompts.snapshot()) and exact(rebuilt.view().snapshot(), sim.player_prompt_view().snapshot()), name + " event-only prompt reconstruction exact")
	check(checks, Needs.conserved_prefixes(sim), name + " all world prefixes conserve resources and claims")
	summaries[name] = {"world_events": sim.events.count(), "observation_events": sim.player_observer.events().size(), "prompt_events": sim.player_prompts.events().size(), "prompts": sim.player_prompts.snapshot().prompts, "input_count": sim.inputs.size(), "end_tick": sim.world.clock().tick_index, "ledger": sim.audit()}

static func run() -> Dictionary:
	var checks: Array = []
	var summaries: Dictionary = {}
	var a: RefCounted = Demo.fresh()
	var before: Dictionary = a.snapshot()
	var observed: Dictionary = a.player_observer.snapshot()
	var result: Dictionary = a.execute(Demo.input())
	check(checks, result.success and result.entity_id == "player-prompt:0000000001", "A first accepted advisory ID")
	var prompt: Dictionary = a.player_prompt_view().status(result.entity_id)
	check(checks, prompt.state == "PENDING_EVALUATION" and prompt.submitted_at == 0 and prompt.received_at == 0, "A zero-latency receipt ends pending")
	check(checks, a.player_prompts.events().map(func(e): return e.event_type) == ["PLAYER_PROMPT_SUBMITTED", "PLAYER_PROMPT_RECEIVED"], "A two semantic events")
	check(checks, a.command_prompt_view("OPERATIONAL_COMMAND").current().size() == 1 and a.command_prompt_view("LOCAL_C").current().is_empty() and a.command_prompt_view("MISSING").current().is_empty(), "A recipient-only detached inbox no Local delivery")
	check(checks, exact(before, a.snapshot()) and exact(observed, a.player_observer.snapshot()), "A world and observation unchanged")
	var view: RefCounted = a.player_prompt_view()
	var mutable: Array = view.current()
	mutable[0].state = "CHEAT"
	check(checks, view.status(result.entity_id).state == "PENDING_EVALUATION" and a.player_prompt_view().status(result.entity_id).state == "PENDING_EVALUATION", "A public queries deep-copy backing state")
	check(checks, prompt.keys().all(func(k): return k in ["prompt_id", "prompt_type", "area_id", "recipient_command_id", "submitted_at", "received_at", "state"]), "A prompt view strict public allowlist")
	check(checks, not view.has_method("information") and not view.has_method("current_belief"), "A advisory view has no hidden knowledge interface")
	record_case(checks, summaries, a, "A")
	var b: RefCounted = Demo.fresh()
	before = b.snapshot()
	result = b.execute(Demo.input("REQUEST_ASSESSMENT"))
	check(checks, result.success and b.player_prompt_view().status(result.entity_id).state == "PENDING_EVALUATION", "B assessment request pending without answer")
	check(checks, exact(before, b.snapshot()) and b.world.ids("information_records").is_empty(), "B no information, recon, or gameplay mutation")
	record_case(checks, summaries, b, "B")
	# Local front observation at1s is private and delayed to Operational Command.
	var c: RefCounted = Demo.fresh()
	c.advance(10)
	var knowledge: Dictionary = c.command_view("OPERATIONAL_COMMAND")._data.duplicate(true)
	check(checks, not c.player_view().current("AREA_FRONT_C").is_empty() and c.command_view("OPERATIONAL_COMMAND").current_belief("FRONT_C", "FRONT_ENEMY_PRESSURE", c.time()).is_empty(), "C visible qualitative area absent from recipient beliefs")
	observed = c.player_observer.snapshot()
	before = c.snapshot()
	result = c.execute(Demo.input())
	check(checks, result.success and exact(before, c.snapshot()) and exact(knowledge, c.command_view("OPERATIONAL_COMMAND")._data.duplicate(true)) and exact(observed, c.player_observer.snapshot()), "C pointer grants neither player cues nor world truth to commander")
	check(checks, c.player_prompts.snapshot().prompts[0].metadata.is_empty() and c.inputs.back().command.size() == 4, "C no observer payload or arbitrary metadata copied")
	record_case(checks, summaries, c, "C")
	_invalid(checks, summaries)
	var e: RefCounted = Demo.fresh()
	for entry in [["DIRECT_ATTENTION", "AREA_FRONT_A"], ["REQUEST_ASSESSMENT", "AREA_FRONT_C"], ["DIRECT_ATTENTION", "AREA_FRONT_B"]]: e.execute(Demo.input(entry[0], entry[1]))
	check(checks, e.player_prompt_view().current().map(func(p): return p.area_id) == ["AREA_FRONT_A", "AREA_FRONT_C", "AREA_FRONT_B"], "E same-tick input order not sorted by area/type")
	check(checks, e.player_prompt_view().current().map(func(p): return p.prompt_id) == ["player-prompt:0000000001", "player-prompt:0000000002", "player-prompt:0000000003"], "E prompt IDs independent sequential")
	check(checks, e.command_prompt_view("OPERATIONAL_COMMAND").current() == e.player_prompt_view().current() and e.player_prompts.events().size() == 6, "E recipient order matches accepted execution order")
	check(checks, e.player_prompt_view().recent_history(0).is_empty() and e.player_prompt_view().recent_history(1).size() == 1 and e.player_prompt_view().recent_history(-1).is_empty(), "E history limits bounded")
	record_case(checks, summaries, e, "E")
	var f: RefCounted = Demo.fresh()
	var h: RefCounted = Demo.fresh()
	f.start_time_utc = h.start_time_utc
	for ticks in [0, 11, 39, 100, 150, 250]:
		f.advance(ticks - f.world.clock().tick_index)
		h.advance(ticks - h.world.clock().tick_index)
		f.execute(Demo.input("REQUEST_ASSESSMENT" if ticks % 2 else "DIRECT_ATTENTION", "AREA_FRONT_C"))
	check(checks, exact(f.snapshot(), h.snapshot()) and exact(f.events.all(), h.events.all()), "F entire authoritative state/events/IDs identical without normalization")
	check(checks, exact(f.player_observer.snapshot(), h.player_observer.snapshot()) and exact(f.player_observer.events(), h.player_observer.events()) and exact(f.player_view().snapshot(), h.player_view().snapshot()), "F complete observation stream/projection unaffected")
	for table in ["decisions", "decision_candidates", "resource_needs", "peer_coordinations", "superior_need_reports", "resource_arbitrations", "messages", "shipments", "information_records", "ledger"]:
		check(checks, exact(f.snapshot()[table], h.snapshot()[table]), "F exact AI inertness " + table)
	check(checks, f.events.count() == 3607 and h.events.count() == 3607 and h.inputs.is_empty() and h.player_prompts.events().is_empty(), "H accepted integrated3607 events no fabricated prompt/input")
	check(checks, view.current().size() == 1 and view.recent_history().size() == 2, "held older detached view never changes")
	record_case(checks, summaries, f, "F")
	record_case(checks, summaries, h, "H")
	check(checks, FileAccess.get_file_as_bytes("res://artifacts/run_step110_F/events.jsonl") == FileAccess.get_file_as_bytes("res://artifacts/run_step110_H/events.jsonl"), "F actual events.jsonl byte-identical")
	for file in ["initial_world.json", "final_world.json", "player_observer_config.json", "player_observation_events.jsonl", "final_player_observer.json"]:
		check(checks, FileAccess.get_file_as_bytes("res://artifacts/run_step110_F/" + file) == FileAccess.get_file_as_bytes("res://artifacts/run_step110_H/" + file), "F exact exported " + file)
	for file in ["inputs.jsonl", "player_prompt_events.jsonl", "final_player_prompts.json"]:
		check(checks, FileAccess.get_file_as_bytes("res://artifacts/run_step110_F/" + file) != FileAccess.get_file_as_bytes("res://artifacts/run_step110_H/" + file), "F expected prompt-specific difference " + file)
	var fm: Dictionary = Exporter.read_json("res://artifacts/run_step110_F/manifest.json").details.value
	var hm: Dictionary = Exporter.read_json("res://artifacts/run_step110_H/manifest.json").details.value
	fm.erase("player_prompt")
	hm.erase("player_prompt")
	check(checks, exact(fm, hm), "F manifest differs only prompt-specific stream/projection/input hashes")
	_integrity(a, checks)
	var failures: Array = checks.filter(func(item): return not item.passed).map(func(item): return item.name)
	return {"success": failures.is_empty(), "checks": checks, "failures": failures, "scenarios": summaries}

static func _invalid(checks: Array, summaries: Dictionary) -> void:
	var data := Demo.definition()
	data.commands.append({"id": "OTHER_OP", "command_level": "OPERATIONAL"})
	data.commands.append({"id": "DISABLED_OP", "command_level": "OPERATIONAL", "enabled": false})
	data.strategic_areas.append({"id": "DISABLED_AREA", "enabled": false, "location_ids": ["C_FRONT_SITE"], "front_id": "FRONT_C"})
	data.strategic_areas.append({"id": "UNOWNED_AREA", "location_ids": ["OFFSCREEN_SOURCE"]})
	data.strategic_areas.append({"id": "MIXED_AREA", "enabled": false, "location_ids": ["OP_HQ", "OFFSCREEN_SOURCE"]})
	var sim := Simulation.new()
	check(checks, sim.initialize(data, 110, "step110_D").success, "D scoped test definition valid")
	var before: Dictionary = sim.snapshot()
	var cases: Array = [[Demo.input("BAD_TYPE"), "UNKNOWN_PROMPT_TYPE"], [Demo.input("DIRECT_ATTENTION", "UNKNOWN"), "UNKNOWN_STRATEGIC_AREA"], [Demo.input("DIRECT_ATTENTION", "DISABLED_AREA"), "DISABLED_STRATEGIC_AREA"], [Demo.input("DIRECT_ATTENTION", "AREA_FRONT_C", "UNKNOWN"), "UNKNOWN_RECIPIENT_COMMAND"], [Demo.input("DIRECT_ATTENTION", "AREA_FRONT_C", "LOCAL_C"), "RECIPIENT_NOT_OPERATIONAL"], [Demo.input("DIRECT_ATTENTION", "AREA_FRONT_C", "OTHER_OP"), "AREA_OUTSIDE_COMMAND_SCOPE"], [Demo.input("DIRECT_ATTENTION", "UNOWNED_AREA"), "AREA_OUTSIDE_COMMAND_SCOPE"], [Demo.input("DIRECT_ATTENTION", "AREA_FRONT_C", "DISABLED_OP"), "RECIPIENT_DISABLED"]]
	for field in ["submitted_at", "received_at", "prompt_id", "metadata", "text", "enemy_pressure", "player_observation", "source_input_id"]:
		var forged := Demo.input()
		forged[field] = "FORGED"
		cases.append([forged, "INVALID_INPUT"])
	for field in ["prompt_type", "area_id", "recipient_command_id"]:
		var missing := Demo.input()
		missing.erase(field)
		cases.append([missing, "INVALID_INPUT"])
		var malformed := Demo.input()
		malformed[field] = 42
		cases.append([malformed, "INVALID_INPUT"])
	for entry in cases:
		var count: int = sim.inputs.size()
		var result: Dictionary = sim.execute(entry[0])
		check(checks, result.error_code == entry[1] and result.entity_id == null and sim.player_prompts.events().is_empty() and sim.player_prompts.snapshot().prompts.is_empty() and exact(before, sim.snapshot()) and sim.inputs.size() == count + 1, "D invalid attempt audit-only " + entry[1] + "/" + str(count))
	var valid: Dictionary = sim.execute(Demo.input())
	check(checks, valid.entity_id == "player-prompt:0000000001" and sim.player_prompts.events()[0].prompt_event_id == "player-prompt-event:0000000001", "D rejected attempts allocate no phantom prompt/event IDs")
	check(checks, sim.command_prompt_view("OTHER_OP").current().is_empty(), "D unrelated Operational inbox isolated")
	check(checks, sim.execute(Demo.input("DIRECT_ATTENTION", "AREA_HQ")).success, "D frontless HQ direct control in scope")
	record_case(checks, summaries, sim, "D")
	# Existing stockpile association is enough, without inventing location ownership.
	data = Demo.definition()
	data.commands[0].directly_controlled_location_ids = []
	var stock_only := Simulation.new()
	stock_only.initialize(data, 110, "scope_stock")
	check(checks, stock_only.execute(Demo.input("DIRECT_ATTENTION", "AREA_HQ")).success, "scope frontless owned/direct-stock location valid")
	data = Demo.definition()
	data.strategic_areas[0].location_ids.append("OFFSCREEN_SOURCE")
	var multi := Simulation.new()
	check(checks, multi.initialize(data, 110, "scope_multi").success and multi.execute(Demo.input("DIRECT_ATTENTION", "AREA_HQ")).error_code == "AREA_OUTSIDE_COMMAND_SCOPE", "scope every frontless location must resolve not just first")
	data = Demo.definition()
	data.commands.append({"id": "OTHER_OP", "command_level": "OPERATIONAL", "directly_controlled_stockpile_ids": ["OTHER_STOCK"]})
	data.stockpiles.append({"id": "OTHER_STOCK", "owner_command_id": "OTHER_OP", "location_id": "OP_HQ", "quantities": {"AMMUNITION": 0}})
	var shared := Simulation.new()
	check(checks, shared.initialize(data, 110, "scope_shared").success and shared.execute(Demo.input("DIRECT_ATTENTION", "AREA_HQ")).success and shared.execute(Demo.input("DIRECT_ATTENTION", "AREA_HQ", "OTHER_OP")).success, "scope legitimate shared infrastructure associations each valid")
	check(checks, shared.command_prompt_view("OTHER_OP").current().size() == 1 and shared.command_prompt_view("OPERATIONAL_COMMAND").current().size() == 1, "two Operational recipients receive only their own addressed prompt")
	var held := shared.command_prompt_view("OPERATIONAL_COMMAND")
	shared.execute({"type": "ReparentCommand", "command_id": "LOCAL_C", "superior_command_id": "OTHER_OP"}, true)
	check(checks, shared.execute(Demo.input()).error_code == "AREA_OUTSIDE_COMMAND_SCOPE" and shared.execute(Demo.input("DIRECT_ATTENTION", "AREA_FRONT_C", "OTHER_OP")).success, "front scope follows accepted current hierarchy after reparent")
	check(checks, held.current().size() == 1 and shared.command_prompt_view("OPERATIONAL_COMMAND").current().size() == 1, "old detached inbox and addressed prior prompts stable after hierarchy change")
	# Mixed legacy and prompt calls preserve all later core IDs/correlation/context.
	var mixed: RefCounted = Demo.fresh()
	var control: RefCounted = Demo.fresh()
	for value in [60, 65]:
		mixed.execute(Demo.input())
		var command := {"type": "SetFrontEnemyPressure", "front_id": "FRONT_C", "value": value}
		mixed.execute(command, true)
		control.execute(command, true)
	check(checks, exact(mixed.snapshot(), control.snapshot()) and exact(mixed.events.all(), control.events.all()), "mixed inputs leave later core input IDs/context/correlation identical")
	check(checks, mixed.inputs.map(func(i): return i.input_id) == ["player-prompt-input:0000000001", "input:0000000001", "player-prompt-input:0000000002", "input:0000000002"], "mixed input namespace counters independent original call order")
	record_case(checks, summaries, mixed, "G_mixed")

static func _integrity(sim: RefCounted, checks: Array) -> void:
	var directory := "res://artifacts/run_step110_tampered"
	for field in ["prompt_type", "area_id", "recipient_command_id", "previous_prompt_event_id", "source_input_id", "prompt_id", "run_id"]:
		Exporter.export_run(sim, directory)
		var events: Array = Exporter.read_lines(directory.path_join("player_prompt_events.jsonl")).details.value
		events[1][field] = "FORGED"
		Exporter.write_json(directory.path_join("player_prompt_events.jsonl"), events, true)
		var manifest: Dictionary = Exporter.read_json(directory.path_join("manifest.json")).details.value
		if field == "prompt_type": check(checks, Exporter.replay_package(directory).error_code == "PROMPT_PACKAGE_HASH_MISMATCH", "G changed stream hash rejected")
		manifest.player_prompt.sha256 = FileAccess.get_sha256(directory.path_join("player_prompt_events.jsonl"))
		Exporter.write_json(directory.path_join("manifest.json"), manifest)
		check(checks, Exporter.replay_package(directory).error_code == "PLAYER_PROMPT_REPLAY_MISMATCH", "G rehashed forged event rejected " + field)
	Exporter.export_run(sim, directory)
	var projection: Dictionary = Exporter.read_json(directory.path_join("final_player_prompts.json")).details.value
	projection.state.prompts[0].state = "ACCEPTED"
	Exporter.write_json(directory.path_join("final_player_prompts.json"), projection)
	var manifest: Dictionary = Exporter.read_json(directory.path_join("manifest.json")).details.value
	check(checks, Exporter.replay_package(directory).error_code == "PROMPT_PACKAGE_HASH_MISMATCH", "G changed projection hash rejected")
	manifest.player_prompt.projection_sha256 = FileAccess.get_sha256(directory.path_join("final_player_prompts.json"))
	Exporter.write_json(directory.path_join("manifest.json"), manifest)
	check(checks, Exporter.replay_package(directory).error_code == "PLAYER_PROMPT_REPLAY_MISMATCH", "G rehashed state inconsistent with events rejected")
	for field in ["input_id", "tick_index", "run_id"]:
		Exporter.export_run(sim, directory)
		var inputs: Array = Exporter.read_lines(directory.path_join("inputs.jsonl")).details.value
		inputs[0][field] = 1 if field == "tick_index" else "FORGED"
		Exporter.write_json(directory.path_join("inputs.jsonl"), inputs, true)
		manifest = Exporter.read_json(directory.path_join("manifest.json")).details.value
		check(checks, Exporter.replay_package(directory).error_code == "PROMPT_PACKAGE_HASH_MISMATCH", "G changed input hash rejected " + field)
		manifest.player_prompt.inputs_sha256 = FileAccess.get_sha256(directory.path_join("inputs.jsonl"))
		Exporter.write_json(directory.path_join("manifest.json"), manifest)
		check(checks, not Exporter.replay_package(directory).success, "G rehashed source input/order/tick integrity " + field)
	Exporter.export_run(sim, directory)
	check(checks, Exporter.replay_package(directory).success, "G untampered strict three-stream replay")
	var rebuilt := Prompts.new()
	var event: Dictionary = sim.player_prompts.events()[0]
	event.prompt_event_id = "player-prompt-event:0000000002"
	check(checks, not rebuilt.apply_event(event).success and rebuilt.events().is_empty(), "event-only reconstruction rejects broken sequence atomically")
	event = sim.player_prompts.events()[0]
	event.erase("previous_prompt_event_id")
	event.run_id = "UNEXPECTED"
	check(checks, not rebuilt.apply_event(event).success and rebuilt.events().is_empty(), "event-only reconstruction requires all fields including null root lineage and rejects extras")
