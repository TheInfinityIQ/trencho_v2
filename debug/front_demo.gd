extends RefCounted

const Simulation = preload("res://kernel/simulation.gd")
const R = preload("res://kernel/result.gd")

static func definition() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string("res://data/front_world.json"))

static func run(seed := 103, run_id := "step103") -> Dictionary:
	var sim := Simulation.new()
	var result: Dictionary = sim.initialize(definition(), seed, run_id)
	if not result.success:
		return result
	var intervals: Array = []
	for expected in [[4, 4, 0, 6], [4, 4, 0, 2], [4, 2, 2, 0]]:
		sim.advance(10)
		var metrics: Dictionary = sim.front_metrics("FRONT_A")
		intervals.append(metrics)
		if metrics.last_interval_demand != expected[0] or metrics.last_interval_consumed != expected[1] or metrics.last_interval_shortage != expected[2] or metrics.current_ammo_on_hand != expected[3]:
			return R.fail("FRONT_DEMO_INTERVAL_MISMATCH", {"metrics": metrics, "expected": expected})
	result = sim.execute({"type": "SetFrontEnemyPressure", "front_id": "FRONT_A", "value": 100}, true)
	if not result.success or sim.front_metrics("FRONT_A").current_desired_ammo_rate_milli != 8000:
		return R.fail("FRONT_DEMO_PRESSURE_RATE")
	result = sim.execute({"type": "CreateResource", "stockpile_id": "A_STOCK", "resource_type_id": "AMMUNITION", "quantity": 12}, true)
	if not result.success:
		return result
	result = sim.execute({"type": "SetFrontPosture", "front_id": "FRONT_A", "value": "REDUCE_ACTIVITY"}, true)
	if not result.success or sim.front_metrics("FRONT_A").current_desired_ammo_rate_milli != 4000:
		return R.fail("FRONT_DEMO_POSTURE_RATE")
	sim.advance(10)
	if sim.front_metrics("FRONT_A").current_ammo_on_hand != 8 or not sim.command_view("ARMY_COMMAND").information().is_empty() or not sim.command_view("LOCAL_B").information().is_empty() or not sim.world.ids("messages").is_empty():
		return R.fail("FRONT_DEMO_RESULT_OR_PRIVACY")
	result = sim.execute({"type": "EndRun"}, true)
	if not result.success:
		return result
	return R.ok(null, {"simulation": sim, "intervals": intervals, "final_metrics": sim.front_metrics("FRONT_A")})
