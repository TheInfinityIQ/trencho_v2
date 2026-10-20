extends RefCounted
const Base = preload("res://debug/information_collection_demo.gd")
const Simulation = preload("res://kernel/simulation.gd")

static func definition(enabled := true, integrated := false, outbound := 0.2, inbound := 0.3) -> Dictionary:
	var data := Base.definition(true, integrated, outbound, inbound)
	data.id = "step114"
	data.commands[0].strategic_prompt_follow_up_enabled = enabled
	return data

static func start(data: Dictionary) -> RefCounted:
	var sim := Simulation.new()
	var result: Dictionary = sim.initialize(data, 114, "step114")
	assert(result.success, JSON.stringify(result))
	return sim

static func fresh(enabled := true, integrated := false, outbound := 0.2, inbound := 0.3) -> RefCounted:
	return start(definition(enabled, integrated, outbound, inbound))
