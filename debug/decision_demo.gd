extends RefCounted
const Simulation = preload("res://kernel/simulation.gd")
const FrontDemo = preload("res://debug/front_demo.gd")
const R = preload("res://kernel/result.gd")

static func definition(scenario := "A", autonomous := true) -> Dictionary:
	var data: Dictionary = FrontDemo.definition()
	data.id = "trencho_step104_" + scenario
	if autonomous:
		data.commands[1].local_decision_front_id = "FRONT_A"
	data.stockpiles[1].quantities.AMMUNITION = 200 if scenario in ["A", "B"] else 2
	if scenario == "A":
		data.fronts[0].friendly_strength = 80
		data.fronts[0].enemy_pressure = 40
		data.fronts[0].base_ammo_demand_per_second = 10
	return data

static func run(scenario := "A", seed := 104, run_id := "step104") -> Dictionary:
	var sim := Simulation.new()
	var result: Dictionary = sim.initialize(definition(scenario), seed, run_id)
	if not result.success:
		return result
	sim.advance(10)
	if scenario == "D":
		result = sim.execute({"type": "CreateResource", "stockpile_id": "A_STOCK", "resource_type_id": "AMMUNITION", "quantity": 200}, true)
		if not result.success:
			return result
	sim.advance(20)
	result = sim.execute({"type": "EndRun"}, true)
	if not result.success:
		return result
	return R.ok(null, {"simulation": sim, "journal": sim.decision_journal("LOCAL_A")})
