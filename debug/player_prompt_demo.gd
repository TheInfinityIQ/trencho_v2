extends RefCounted
const Simulation = preload("res://kernel/simulation.gd")
const Observation = preload("res://debug/player_observation_demo.gd")

static func definition() -> Dictionary:
	return Observation.definition("D")

static func fresh() -> RefCounted:
	var sim := Simulation.new()
	var initialized: Dictionary = sim.initialize(definition(), 110, "step110")
	assert(initialized.success)
	return sim

static func input(type := "DIRECT_ATTENTION", area := "AREA_FRONT_C", recipient := "OPERATIONAL_COMMAND") -> Dictionary:
	return {"type": "SubmitPlayerPrompt", "prompt_type": type, "area_id": area, "recipient_command_id": recipient}
