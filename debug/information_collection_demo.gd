extends RefCounted
const Base = preload("res://debug/information_requirement_demo.gd")
const Simulation = preload("res://kernel/simulation.gd")

static func definition(enabled := true, integrated := false, outbound := 0.2, inbound := 0.3) -> Dictionary:
	var data := Base.definition(true, true, integrated)
	data.id = "step113"
	data.commands[0].strategic_subordinate_reporting_enabled = enabled
	if not integrated:
		data.commands[0].ammunition_arbitration_enabled = false
		data.commands[3].local_decision_front_id = "FRONT_C"
		data.communication_edges[0].latency_seconds = inbound
		data.communication_edges[1].latency_seconds = outbound
	return data

static func fresh(enabled := true, integrated := false, outbound := 0.2, inbound := 0.3) -> RefCounted:
	var sim := Simulation.new()
	var result: Dictionary = sim.initialize(definition(enabled, integrated, outbound, inbound), 113, "step113")
	assert(result.success, JSON.stringify(result))
	return sim
