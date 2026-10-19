extends RefCounted

const R = preload("res://kernel/result.gd")
const Simulation = preload("res://kernel/simulation.gd")
const Definition = preload("res://kernel/world_definition.gd")
const ExactJSON = preload("res://kernel/authoritative_json.gd")

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
	for pair in [["manifest.json", manifest, false], ["initial_world.json", sim.initial_world, false], ["final_world.json", state, false], ["events.jsonl", sim.events.all(), true], ["inputs.jsonl", sim.inputs, true]]:
		if not write_json(directory.path_join(pair[0]), pair[1], pair[2]):
			return R.fail("EXPORT_FAILED", {"file": pair[0]})
	return R.ok(null, {"directory": directory})

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

static func replay(initial: Dictionary, recorded_inputs: Array, end_tick: int) -> Dictionary:
	var sim := Simulation.new()
	var initialized := sim.initialize_snapshot(initial)
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
	var replayed := replay(loaded["initial_world.json"], loaded["inputs.jsonl"], manifest.end_tick)
	if not replayed.success:
		return replayed
	var sim: RefCounted = replayed.details.simulation
	var state_match := equivalent(sim.snapshot(), loaded["final_world.json"])
	var events_match := equivalent(sim.events.all(), loaded["events.jsonl"])
	if not state_match or not events_match:
		var actual_events: Array = sim.events.all()
		var expected_events: Array = loaded["events.jsonl"]
		for index in range(mini(actual_events.size(), expected_events.size())):
			if not equivalent(actual_events[index], expected_events[index]):
				return R.fail("REPLAY_MISMATCH", {"state_match": state_match, "events_match": events_match, "first_event_index": index, "actual_normalized": JSON.stringify(normalize(actual_events[index]), "", true, true), "expected_normalized": JSON.stringify(normalize(expected_events[index]), "", true, true)})
		return R.fail("REPLAY_MISMATCH", {"state_match": state_match, "events_match": events_match, "actual_event_count": actual_events.size(), "expected_event_count": expected_events.size()})
	return R.ok(null, {"state_match": true, "events_match": true, "event_count": sim.events.count(), "end_tick": manifest.end_tick})
