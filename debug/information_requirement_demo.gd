extends RefCounted
const Simulation = preload("res://kernel/simulation.gd")
const Base = preload("res://debug/prompt_evaluation_demo.gd")

static func definition(requirements_enabled := true, evaluation_enabled := true, integrated := false) -> Dictionary:
	var data := Base.definition(evaluation_enabled, 0.1, integrated)
	data.id = "step112"
	data.commands[0].strategic_information_requirements_enabled = requirements_enabled
	return data

static func fresh(requirements_enabled := true, evaluation_enabled := true, integrated := false) -> RefCounted:
	var sim := Simulation.new()
	var initialized: Dictionary = sim.initialize(definition(requirements_enabled, evaluation_enabled, integrated), 112, "step112")
	assert(initialized.success, JSON.stringify(initialized))
	return sim
