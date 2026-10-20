extends RefCounted

const R = preload("res://kernel/result.gd")
const Simulation = preload("res://kernel/simulation.gd")
const Definition = preload("res://kernel/world_definition.gd")
const ExactJSON = preload("res://kernel/authoritative_json.gd")
const Areas = preload("res://kernel/strategic_area_definition.gd")
const Observer = preload("res://kernel/player_observer.gd")
const World = preload("res://kernel/world_state.gd")
const Prompts = preload("res://kernel/player_prompt_service.gd")
const PromptConfig = preload("res://kernel/prompt_evaluation_config.gd")
const Requirements = preload("res://kernel/information_requirement_service.gd")
const RequirementConfig = preload("res://kernel/information_requirement_config.gd")

static func normalize(value: Variant) -> Variant:
	if value is float and is_finite(value) and value == floor(value) and absf(value) < 9007199254740992.0:
		return int(value)
	if value is Dictionary:
		var result: Dictionary = {}
		var keys: Array = value.keys()
		keys.sort()
		for key in keys:
			# Run identity is diagnostic metadata, never simulation content.
			if key != "run_id":
				result[key] = normalize(value[key])
		return result
	if value is Array:
		var result: Array = []
		for item in value:
			result.append(normalize(item))
		return result
	return value

static func equivalent(a: Variant, b: Variant) -> bool:
	return JSON.stringify(normalize(a), "", true, true) == JSON.stringify(normalize(b), "", true, true)

# Observer records have no run_id exception or numeric representation rewrite.
# Keep the accepted authoritative comparer untouched while checking the new
# presentation contract exactly, including every field and both ID namespaces.
static func observer_equivalent(a: Variant, b: Variant) -> bool:
	return JSON.stringify(a, "", true, true) == JSON.stringify(b, "", true, true)

static func write_json(path: String, value: Variant, lines := false) -> bool:
	var file := FileAccess.open(path, FileAccess.WRITE)
	if file == null:
		return false
	if lines:
		for item in value:
			file.store_line(JSON.stringify(item, "", true, true))
	else:
		file.store_string(JSON.stringify(value, "\t", true, true) + "\n")
	file.flush()
	return file.get_error() == OK

static func export_run(sim: RefCounted, directory: String) -> Dictionary:
	var error := DirAccess.make_dir_recursive_absolute(ProjectSettings.globalize_path(directory))
	if error != OK:
		return R.fail("EXPORT_FAILED", {"path": directory, "error": error})
	var state: Dictionary = sim.snapshot()
	var manifest := {"run_id": state.run_id, "project_version": state.project_version, "schema_version": state.schema_version, "engine_version": state.engine_version, "simulation_seed": state.simulation_seed, "tick_duration": state.clock.tick_duration, "start_time_utc": sim.start_time_utc, "end_tick": state.clock.tick_index, "initial_world_definition_id": state.initial_world_definition_id}
	for pair in [["initial_world.json", sim.initial_world, false], ["final_world.json", state, false], ["events.jsonl", sim.events.all(), true], ["inputs.jsonl", sim.inputs, true]]:
		if not write_json(directory.path_join(pair[0]), pair[1], pair[2]):
			return R.fail("EXPORT_FAILED", {"file": pair[0]})
	manifest.player_observation_enabled = not sim.player_observer.configuration().is_empty()
	if manifest.player_observation_enabled:
		for pair in [["player_observer_config.json", {"strategic_areas": sim.player_observer.configuration()}, false], ["player_observation_events.jsonl", sim.player_observer.events(), true], ["final_player_observer.json", {"state": sim.player_observer.snapshot(), "view": sim.player_view().snapshot()}, false]]:
			if not write_json(directory.path_join(pair[0]), pair[1], pair[2]): return R.fail("EXPORT_FAILED", {"file": pair[0]})
		manifest.streams = {"authoritative": {"file": "events.jsonl", "schema_version": Definition.SCHEMA_VERSION, "sha256": FileAccess.get_sha256(directory.path_join("events.jsonl"))}, "player_observation": {"file": "player_observation_events.jsonl", "schema_version": "2C.1.player-observation.1", "sha256": FileAccess.get_sha256(directory.path_join("player_observation_events.jsonl"))}}
		manifest.observer_configuration_sha256 = FileAccess.get_sha256(directory.path_join("player_observer_config.json"))
		manifest.observer_projection_sha256 = FileAccess.get_sha256(directory.path_join("final_player_observer.json"))
	# Empty intent streams are explicit too; no synthetic prompt is generated.
	for pair in [["player_prompt_events.jsonl", sim.player_prompts.events(), true], ["final_player_prompts.json", prompt_projection(sim), false], ["player_prompt_evaluation_config.json", {"schema_version": PromptConfig.SCHEMA, "commands": sim.prompt_evaluation_configuration()}, false]]:
		if not write_json(directory.path_join(pair[0]), pair[1], pair[2]): return R.fail("EXPORT_FAILED", {"file": pair[0]})
	manifest.player_prompts_enabled = true
	manifest.player_prompt = {"schema_version": Prompts.SCHEMA, "file": "player_prompt_events.jsonl", "sha256": FileAccess.get_sha256(directory.path_join("player_prompt_events.jsonl")), "projection_file": "final_player_prompts.json", "projection_sha256": FileAccess.get_sha256(directory.path_join("final_player_prompts.json")), "inputs_sha256": FileAccess.get_sha256(directory.path_join("inputs.jsonl"))}
	manifest.player_prompt.evaluation_config = {"schema_version": PromptConfig.SCHEMA, "file": "player_prompt_evaluation_config.json", "sha256": FileAccess.get_sha256(directory.path_join("player_prompt_evaluation_config.json"))}
	for pair in [["information_requirement_events.jsonl", sim.information_requirements.events(), true], ["final_information_requirements.json", requirement_projection(sim), false], ["player_prompt_information_requirement_config.json", {"schema_version": RequirementConfig.SCHEMA, "commands": sim.information_requirement_configuration()}, false]]:
		if not write_json(directory.path_join(pair[0]), pair[1], pair[2]): return R.fail("EXPORT_FAILED", {"file": pair[0]})
	manifest.information_requirement = {"schema_version": Requirements.SCHEMA, "file": "information_requirement_events.jsonl", "sha256": FileAccess.get_sha256(directory.path_join("information_requirement_events.jsonl")), "projection_file": "final_information_requirements.json", "projection_sha256": FileAccess.get_sha256(directory.path_join("final_information_requirements.json")), "config_file": "player_prompt_information_requirement_config.json", "config_schema_version": RequirementConfig.SCHEMA, "config_sha256": FileAccess.get_sha256(directory.path_join("player_prompt_information_requirement_config.json"))}
	if not write_json(directory.path_join("manifest.json"), manifest): return R.fail("EXPORT_FAILED", {"file": "manifest.json"})
	return R.ok(null, {"directory": directory})

static func prompt_projection(sim: RefCounted) -> Dictionary:
	var recipients: Dictionary = {}
	for id in sim.world.ids("commands"):
		if sim.world.get_command(id).command_level == "OPERATIONAL": recipients[id] = sim.command_prompt_view(id).snapshot()
	return {"state": sim.player_prompts.snapshot(), "view": sim.player_prompt_view().snapshot(), "recipients": recipients}

static func requirement_projection(sim: RefCounted) -> Dictionary:
	var recipients: Dictionary = {}
	for id in sim.world.ids("commands"):
		if sim.world.get_command(id).command_level == "OPERATIONAL": recipients[id] = sim.information_requirement_view(id).snapshot()
	return {"state": sim.information_requirements.snapshot(), "recipients": recipients}

static func read_json(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return R.fail("IMPORT_FAILED", {"path": path})
	var parsed := ExactJSON.parse(file.get_as_text())
	if not parsed.success:
		return R.fail(parsed.error_code, {"path": path, "offset": parsed.details.offset})
	if not parsed.details.value is Dictionary:
		return R.fail("IMPORT_FAILED", {"path": path})
	return parsed

static func read_lines(path: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null:
		return R.fail("IMPORT_FAILED", {"path": path})
	var result: Array = []
	while not file.eof_reached():
		var line := file.get_line()
		if line.strip_edges().is_empty():
			continue
		var parsed := ExactJSON.parse(line)
		if not parsed.success:
			return R.fail(parsed.error_code, {"path": path, "offset": parsed.details.offset})
		if not parsed.details.value is Dictionary:
			return R.fail("IMPORT_FAILED", {"path": path})
		result.append(parsed.details.value)
	return R.ok(null, {"value": result})

static func replay(initial: Dictionary, recorded_inputs: Array, end_tick: int, strategic_areas: Variant = [], prompt_configuration: Variant = [], requirement_configuration: Variant = []) -> Dictionary:
	var sim := Simulation.new()
	var initialized := sim.initialize_snapshot(initial, strategic_areas, prompt_configuration, requirement_configuration)
	if not initialized.success:
		return initialized
	for record in recorded_inputs:
		if record.get("schema_version") != Definition.SCHEMA_VERSION or not record.get("command") is Dictionary or not record.get("privileged") is bool or record.get("tick_index", -1) < sim.world.clock().tick_index or record.tick_index > end_tick:
			return R.fail("INVALID_REPLAY_INPUT")
		var advance: Dictionary = sim.advance(record.tick_index - sim.world.clock().tick_index)
		if not advance.success:
			return advance
		var result: Dictionary = sim.execute(record.command, record.privileged)
		if not equivalent(result, record.get("result", {})):
			return R.fail("REPLAY_INPUT_MISMATCH", {"input_id": record.input_id})
	if sim.world.clock().tick_index < end_tick:
		var advance: Dictionary = sim.advance(end_tick - sim.world.clock().tick_index)
		if not advance.success:
			return advance
	return R.ok(null, {"simulation": sim})

static func replay_package(directory: String) -> Dictionary:
	var loaded: Dictionary = {}
	for filename in ["manifest.json", "initial_world.json", "final_world.json", "events.jsonl", "inputs.jsonl"]:
		var result := read_lines(directory.path_join(filename)) if filename.ends_with("jsonl") else read_json(directory.path_join(filename))
		if not result.success:
			return result
		loaded[filename] = result.details.value
	var manifest: Dictionary = loaded["manifest.json"]
	if manifest.get("schema_version") != Definition.SCHEMA_VERSION or manifest.get("project_version") != Definition.PROJECT_VERSION:
		return R.fail("UNSUPPORTED_SNAPSHOT")
	if not manifest.get("player_observation_enabled") is bool: return R.fail("INVALID_OBSERVER_PACKAGE")
	if manifest.get("player_prompts_enabled") != true or not manifest.get("player_prompt") is Dictionary: return R.fail("INVALID_PROMPT_PACKAGE")
	var prompt_manifest: Dictionary = manifest.player_prompt
	if not prompt_manifest.get("evaluation_config") is Dictionary or prompt_manifest.evaluation_config.get("schema_version") != PromptConfig.SCHEMA or prompt_manifest.evaluation_config.get("file") != "player_prompt_evaluation_config.json": return R.fail("INVALID_PROMPT_PACKAGE")
	if prompt_manifest.evaluation_config.get("sha256") != FileAccess.get_sha256(directory.path_join("player_prompt_evaluation_config.json")): return R.fail("PROMPT_PACKAGE_HASH_MISMATCH")
	var evaluation_configuration := read_json(directory.path_join("player_prompt_evaluation_config.json"))
	if not evaluation_configuration.success: return evaluation_configuration
	if evaluation_configuration.details.value.size() != 2 or evaluation_configuration.details.value.get("schema_version") != PromptConfig.SCHEMA or not evaluation_configuration.details.value.get("commands") is Array: return R.fail("INVALID_PROMPT_EVALUATION_CONFIGURATION")
	var requirement_manifest: Variant = manifest.get("information_requirement")
	if not requirement_manifest is Dictionary or requirement_manifest.get("schema_version") != Requirements.SCHEMA or requirement_manifest.get("file") != "information_requirement_events.jsonl" or requirement_manifest.get("projection_file") != "final_information_requirements.json" or requirement_manifest.get("config_file") != "player_prompt_information_requirement_config.json" or requirement_manifest.get("config_schema_version") != RequirementConfig.SCHEMA: return R.fail("INVALID_REQUIREMENT_PACKAGE")
	for pair in [["information_requirement_events.jsonl", "sha256"], ["final_information_requirements.json", "projection_sha256"], ["player_prompt_information_requirement_config.json", "config_sha256"]]:
		if requirement_manifest.get(pair[1]) != FileAccess.get_sha256(directory.path_join(pair[0])): return R.fail("REQUIREMENT_PACKAGE_HASH_MISMATCH")
		var read := read_lines(directory.path_join(pair[0])) if pair[0].ends_with("jsonl") else read_json(directory.path_join(pair[0]))
		if not read.success: return read
		loaded[pair[0]] = read.details.value
	var requirement_configuration: Dictionary = loaded["player_prompt_information_requirement_config.json"]
	if requirement_configuration.size() != 2 or requirement_configuration.get("schema_version") != RequirementConfig.SCHEMA or not requirement_configuration.get("commands") is Array: return R.fail("INVALID_REQUIREMENT_CONFIGURATION")
	if prompt_manifest.get("schema_version") != Prompts.SCHEMA or prompt_manifest.get("file") != "player_prompt_events.jsonl" or prompt_manifest.get("projection_file") != "final_player_prompts.json": return R.fail("INVALID_PROMPT_PACKAGE")
	for pair in [["player_prompt_events.jsonl", "sha256"], ["final_player_prompts.json", "projection_sha256"], ["inputs.jsonl", "inputs_sha256"]]:
		if prompt_manifest.get(pair[1]) != FileAccess.get_sha256(directory.path_join(pair[0])): return R.fail("PROMPT_PACKAGE_HASH_MISMATCH")
	for filename in ["player_prompt_events.jsonl", "final_player_prompts.json"]:
		var result := read_lines(directory.path_join(filename)) if filename.ends_with("jsonl") else read_json(directory.path_join(filename))
		if not result.success: return result
		loaded[filename] = result.details.value
	var configuration: Array = []
	if manifest.player_observation_enabled:
		for filename in ["player_observer_config.json", "player_observation_events.jsonl", "final_player_observer.json"]:
			var result := read_lines(directory.path_join(filename)) if filename.ends_with("jsonl") else read_json(directory.path_join(filename))
			if not result.success: return result
			loaded[filename] = result.details.value
		if not loaded["player_observer_config.json"].get("strategic_areas") is Dictionary: return R.fail("INVALID_OBSERVER_PACKAGE")
		for id in loaded["player_observer_config.json"].strategic_areas:
			var area: Variant = loaded["player_observer_config.json"].strategic_areas[id]
			if not area is Dictionary or area.get("id") != id: return R.fail("INVALID_OBSERVER_PACKAGE")
		configuration = loaded["player_observer_config.json"].strategic_areas.values()
		if configuration.is_empty(): return R.fail("INVALID_OBSERVER_PACKAGE")
		var streams: Variant = manifest.get("streams")
		if not streams is Dictionary: return R.fail("INVALID_OBSERVER_PACKAGE")
		for pair in [["authoritative", "events.jsonl", Definition.SCHEMA_VERSION], ["player_observation", "player_observation_events.jsonl", "2C.1.player-observation.1"]]:
			if not streams.get(pair[0]) is Dictionary or streams[pair[0]].get("file") != pair[1] or streams[pair[0]].get("schema_version") != pair[2] or streams[pair[0]].get("sha256") != FileAccess.get_sha256(directory.path_join(pair[1])): return R.fail("OBSERVER_PACKAGE_HASH_MISMATCH")
		if manifest.get("observer_configuration_sha256") != FileAccess.get_sha256(directory.path_join("player_observer_config.json")) or manifest.get("observer_projection_sha256") != FileAccess.get_sha256(directory.path_join("final_player_observer.json")): return R.fail("OBSERVER_PACKAGE_HASH_MISMATCH")
	var replayed := replay(loaded["initial_world.json"], loaded["inputs.jsonl"], manifest.end_tick, configuration, evaluation_configuration.details.value.commands, requirement_configuration.commands)
	if not replayed.success:
		return replayed
	var sim: RefCounted = replayed.details.simulation
	if not observer_equivalent(sim.inputs, loaded["inputs.jsonl"]): return R.fail("PROMPT_INPUT_HISTORY_MISMATCH")
	if not observer_equivalent(sim.player_prompts.events(), loaded["player_prompt_events.jsonl"]) or not observer_equivalent(prompt_projection(sim), loaded["final_player_prompts.json"]): return R.fail("PLAYER_PROMPT_REPLAY_MISMATCH")
	var rebuilt := Prompts.new(sim.player_observer.configuration())
	for event in loaded["player_prompt_events.jsonl"]:
		if not rebuilt.apply_event(event).success: return R.fail("INVALID_PROMPT_EVENT")
	if not observer_equivalent(rebuilt.snapshot(), sim.player_prompts.snapshot()) or not observer_equivalent(rebuilt.view().snapshot(), sim.player_prompt_view().snapshot()): return R.fail("PLAYER_PROMPT_RECONSTRUCTION_MISMATCH")
	if not observer_equivalent(sim.information_requirements.events(), loaded["information_requirement_events.jsonl"]) or not observer_equivalent(requirement_projection(sim), loaded["final_information_requirements.json"]): return R.fail("INFORMATION_REQUIREMENT_REPLAY_MISMATCH")
	var owner_ids: Array = sim.world.ids("commands").filter(func(id): return sim.world.get_command(id).command_level == "OPERATIONAL")
	var rebuilt_requirements := Requirements.new(sim.player_observer.configuration(), owner_ids, sim.information_requirement_configuration(), rebuilt.snapshot().evaluations)
	for event in loaded["information_requirement_events.jsonl"]:
		if not rebuilt_requirements.apply_event(event).success: return R.fail("INVALID_REQUIREMENT_EVENT")
	if not observer_equivalent(rebuilt_requirements.snapshot(), sim.information_requirements.snapshot()): return R.fail("INFORMATION_REQUIREMENT_RECONSTRUCTION_MISMATCH")
	for id in owner_ids:
		if not observer_equivalent(rebuilt_requirements.view(id).snapshot(), sim.information_requirement_view(id).snapshot()): return R.fail("INFORMATION_REQUIREMENT_RECONSTRUCTION_MISMATCH")
	var state_match := equivalent(sim.snapshot(), loaded["final_world.json"])
	var events_match := equivalent(sim.events.all(), loaded["events.jsonl"])
	if not state_match or not events_match:
		var actual_events: Array = sim.events.all()
		var expected_events: Array = loaded["events.jsonl"]
		for index in range(mini(actual_events.size(), expected_events.size())):
			if not equivalent(actual_events[index], expected_events[index]):
				return R.fail("REPLAY_MISMATCH", {"state_match": state_match, "events_match": events_match, "first_event_index": index, "actual_normalized": JSON.stringify(normalize(actual_events[index]), "", true, true), "expected_normalized": JSON.stringify(normalize(expected_events[index]), "", true, true)})
		return R.fail("REPLAY_MISMATCH", {"state_match": state_match, "events_match": events_match, "actual_event_count": actual_events.size(), "expected_event_count": expected_events.size()})
	var details := {"state_match": true, "events_match": true, "event_count": sim.events.count(), "end_tick": manifest.end_tick}
	details.prompt_events_match = true
	details.prompt_projection_match = true
	details.prompt_inputs_match = true
	details.prompt_event_count = sim.player_prompts.events().size()
	details.prompt_evaluation_count = sim.player_prompts.snapshot().evaluations.size()
	details.requirement_events_match = true
	details.requirement_projection_match = true
	details.requirement_count = sim.information_requirements.snapshot().requirements.size()
	details.requirement_event_count = sim.information_requirements.events().size()
	if manifest.player_observation_enabled:
		var observed := {"state": sim.player_observer.snapshot(), "view": sim.player_view().snapshot()}
		if not observer_equivalent(sim.player_observer.events(), loaded["player_observation_events.jsonl"]) or not observer_equivalent(observed, loaded["final_player_observer.json"]): return R.fail("PLAYER_OBSERVATION_REPLAY_MISMATCH")
		var reconstructed := reconstruct_player(loaded["initial_world.json"], configuration, loaded["events.jsonl"])
		if not reconstructed.success or not observer_equivalent(reconstructed.details.events, sim.player_observer.events()) or not observer_equivalent(reconstructed.details.projection, observed): return R.fail("PLAYER_OBSERVATION_RECONSTRUCTION_MISMATCH")
		details.player_events_match = true
		details.player_projection_match = true
		details.player_event_count = sim.player_observer.events().size()
	return R.ok(null, details)

static func reconstruct_player(initial: Dictionary, configuration: Variant, world_events: Array) -> Dictionary:
	var valid := Areas.normalize(configuration, initial.locations, initial.fronts, {})
	if not valid.success: return valid
	var world := World.new(initial)
	var observer := Observer.new(valid.details.areas)
	for event in world_events:
		world.apply_event(event)
		observer.observe(event, world)
	return R.ok(null, {"events": observer.events(), "projection": {"state": observer.snapshot(), "view": observer.view().snapshot()}, "world": world.snapshot()})
