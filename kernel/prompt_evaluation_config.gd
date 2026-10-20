extends RefCounted
const R = preload("res://kernel/result.gd")
const Clock = preload("res://kernel/clock.gd")
const FIELD = "strategic_prompt_evaluation_enabled"
const SCHEMA = "2C.3.prompt-evaluation-config.1"

static func extract(definition: Dictionary) -> Dictionary:
	if not R.json_compatible(definition) or not definition.get("commands", []) is Array: return R.fail("INVALID_WORLD_DEFINITION")
	var canonical := definition.duplicate(true)
	var configuration: Array = []
	for command in canonical.get("commands", []):
		if not command is Dictionary: return R.fail("INVALID_WORLD_DEFINITION")
		if command.has(FIELD):
			configuration.append({"operational_command_id": command.get("id"), "enabled": command[FIELD]})
			command.erase(FIELD)
	return R.ok(null, {"definition": canonical, "configuration": configuration})

static func normalize(configuration: Variant, commands: Dictionary, tick_duration: float) -> Dictionary:
	if not configuration is Array: return R.fail("INVALID_PROMPT_EVALUATION_CONFIGURATION")
	var seen: Dictionary = {}
	var result: Array = []
	for entry in configuration:
		if not entry is Dictionary or entry.size() != 2 or entry.keys().any(func(k): return k not in ["operational_command_id", "enabled"]): return R.fail("INVALID_PROMPT_EVALUATION_CONFIGURATION")
		var id: Variant = entry.get("operational_command_id")
		if not id is String or not commands.has(id): return R.fail("UNKNOWN_COMMAND")
		if seen.has(id): return R.fail("DUPLICATE_COMMAND_CONFIG")
		if commands[id].command_level != "OPERATIONAL": return R.fail("COMMAND_NOT_OPERATIONAL")
		if not entry.get("enabled") is bool: return R.fail("INVALID_ENABLED_VALUE")
		if entry.enabled and (Clock.units(tick_duration) <= 0 or 1000000 % Clock.units(tick_duration) != 0): return R.fail("INVALID_PROMPT_EVALUATION_TICK_PRECISION")
		seen[id] = true
		result.append(entry.duplicate(true))
	result.sort_custom(func(a, b): return a.operational_command_id < b.operational_command_id)
	return R.ok(null, {"configuration": result})
