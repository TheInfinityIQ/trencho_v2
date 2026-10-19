extends RefCounted

const Simulation = preload("res://kernel/simulation.gd")
const Fixture = preload("res://debug/front_demo.gd")
const Exporter = preload("res://kernel/run_exporter.gd")
const World = preload("res://kernel/world_state.gd")
const FrontService = preload("res://kernel/front_service.gd")
const FrontDefinition = preload("res://kernel/front_definition.gd")
const ExactJSONCases = preload("res://tests/exact_json_cases.gd")
const Resources = preload("res://kernel/resource_service.gd")

static func run() -> Dictionary:
	var checks: Array = []
	for item in ExactJSONCases.run():
		check(checks, item.passed, item.name)
	_coverage_bounds(checks)
	_precision(checks)
	_validation(checks)
	_consumption(checks)
	_privacy_and_intervals(checks)
	_replay(checks)
	var failures: Array = []
	for item in checks:
		if not item.passed:
			failures.append(item.name)
	return {"checks": checks, "failures": failures, "success": failures.is_empty()}

static func check(checks: Array, condition: bool, name: String) -> void:
	checks.append({"name": "103 / " + name, "passed": condition})

static func fresh(data: Dictionary = {}) -> RefCounted:
	var sim := Simulation.new()
	var initialized: Dictionary = sim.initialize(Fixture.definition() if data.is_empty() else data, 103, "front-test")
	assert(initialized.success, JSON.stringify(initialized))
	return sim

static func front_data() -> Dictionary:
	return Fixture.definition().fronts[0].duplicate(true)

static func set_front(sim: RefCounted, type: String, value: Variant, id := "FRONT_A") -> Dictionary:
	return sim.execute({"type": type, "front_id": id, "value": value}, true)

static func events(sim: RefCounted, type: String) -> Array:
	return sim.events.all().filter(func(event): return event.event_type == type)

static func _validation(checks: Array) -> void:
	var data: Dictionary = Fixture.definition()
	data.fronts = []
	var sim := fresh(data)
	for mutation in [["responsible_command_id", "MISSING"], ["location_id", "MISSING"], ["supply_stockpile_id", "MISSING"], ["friendly_strength", -1], ["friendly_strength", 101], ["enemy_pressure", -1], ["enemy_pressure", 101], ["base_ammo_demand_per_second", -1], ["posture", "ATTACK"], ["enabled", "yes"], ["supply_stockpile_id", "B_STOCK"], ["id", "LOCAL_A"]]:
		var front := front_data()
		front[mutation[0]] = mutation[1]
		var result: Dictionary = sim.execute({"type": "CreateFront", "front": front}, true)
		check(checks, not result.success and result.error_code in ["INVALID_FRONT", "INVALID_ENTITY"], "reject invalid front " + str(mutation))
	check(checks, sim.world.ids("fronts").is_empty(), "failed creation leaves no front")
	var created: Dictionary = sim.execute({"type": "CreateFront", "front": front_data()}, true)
	check(checks, created.success and sim.events.all().back().event_type == "FRONT_CREATED", "validated runtime creation emits event")
	check(checks, not sim.execute({"type": "CreateFront", "front": front_data()}, true).success, "duplicate front ID rejected")
	check(checks, not sim.execute({"type": "SetFrontEnemyPressure", "front_id": "FRONT_A", "value": 30}, false).success, "debug pressure input requires privilege")
	for mutation in [["SetFrontEnemyPressure", -1], ["SetFrontFriendlyStrength", 101], ["SetFrontPosture", "INVALID"], ["SetFrontEnabled", "true"]]:
		check(checks, not set_front(sim, mutation[0], mutation[1]).success, "invalid setter rejected " + str(mutation))
	for mutation in [["SetFrontEnemyPressure", 100, "FRONT_ENEMY_PRESSURE_CHANGED"], ["SetFrontFriendlyStrength", 80, "FRONT_FRIENDLY_STRENGTH_CHANGED"], ["SetFrontPosture", "WITHDRAW", "FRONT_POSTURE_CHANGED"], ["SetFrontEnabled", false, "FRONT_ENABLED_CHANGED"]]:
		check(checks, set_front(sim, mutation[0], mutation[1]).success and sim.events.all().back().event_type == mutation[2], "setter emits " + mutation[2])
	sim.advance(10)
	check(checks, sim.audit().AMMUNITION.consumed == 0 and sim.command_view("LOCAL_A").information().is_empty(), "disabled front neither burns nor observes")
	check(checks, set_front(sim, "SetFrontEnabled", true).success, "front can be re-enabled")
	check(checks, not Resources.new(sim).consume_for_front("FRONT_A", 1).success, "front consumption capability unavailable outside simulation context")
	check(checks, not sim.execute({"type": "ConsumeResource", "actor_entity_id": "FRONT_A", "stockpile_id": "A_STOCK", "resource_type_id": "AMMUNITION", "quantity": 1, "reason_code": "FRONT_COMBAT_CONSUMPTION"}, false).success, "front ID cannot impersonate command authority")
	var detached: Dictionary = sim.world.get_front("FRONT_A")
	detached.enemy_pressure_centi = 0
	check(checks, sim.world.get_front("FRONT_A").enemy_pressure_centi == 10000, "front queries return detached copies")
	data = Fixture.definition()
	data.locations.append({"id": "BACK_DEPOT"})
	data.stockpiles.append({"id": "BACK_STOCK", "location_id": "BACK_DEPOT", "owner_command_id": "LOCAL_A"})
	data.commands[1].directly_controlled_location_ids.append("BACK_DEPOT")
	data.commands[1].directly_controlled_stockpile_ids.append("BACK_STOCK")
	data.fronts[0].supply_stockpile_id = "BACK_STOCK"
	var associated := Simulation.new()
	check(checks, associated.initialize(data).success, "explicit command-associated external supply location accepted")

static func _consumption(checks: Array) -> void:
	for posture in [["HOLD", 4], ["PRESS", 6], ["REDUCE_ACTIVITY", 2], ["WITHDRAW", 1]]:
		var sim := fresh()
		set_front(sim, "SetFrontPosture", posture[0])
		sim.advance(10)
		check(checks, sim.front_metrics("FRONT_A").last_interval_demand == posture[1] and sim.audit().AMMUNITION.consumed == posture[1], "correct posture burn " + posture[0])
		check(checks, events(sim, "FRONT_AMMO_SHORTAGE").is_empty(), "satisfied demand produces no shortage " + posture[0])
	var sim := fresh()
	set_front(sim, "SetFrontEnemyPressure", 0)
	sim.advance(20)
	check(checks, sim.audit().AMMUNITION.consumed == 0 and sim.front_metrics("FRONT_A").current_desired_ammo_rate_milli == 0, "zero pressure has no minimum burn")
	check(checks, sim.front_metrics("FRONT_A").ammo_coverage_milliseconds == null and sim.command_view("LOCAL_A").current_belief("FRONT_A", "FRONT_AMMO_COVERAGE_MILLISECONDS", sim.time()).value == null and JSON.parse_string(JSON.stringify(sim.snapshot())) is Dictionary, "zero burn coverage exports as null")
	var data: Dictionary = Fixture.definition()
	data.fronts[0].enemy_pressure = 100
	data.fronts[0].base_ammo_demand_per_second = 1
	sim = fresh(data)
	sim.advance(9)
	check(checks, sim.audit().AMMUNITION.consumed == 0 and sim.world.get_front("FRONT_A").ammo_demand_accumulator_micro == 900000, "fractional demand persists without early spending")
	sim.advance()
	check(checks, sim.audit().AMMUNITION.consumed == 1 and sim.world.get_front("FRONT_A").ammo_demand_accumulator_micro == 0, "fractional demand resolves at integer boundary")
	check(checks, events(sim, "FRONT_AMMO_ACCUMULATOR_CHANGED").is_empty() and events(sim, "TICK_ADVANCED").size() == 10, "no per-front fractional accumulator event")
	var tick_events := events(sim, "TICK_ADVANCED")
	check(checks, tick_events[0].payload.changes.any(func(c): return c.table == "fronts"), "existing tick carries accumulator projection")
	sim = fresh()
	var reservation: Dictionary = sim.execute({"type": "ReserveResource", "stockpile_id": "A_STOCK", "resource_type_id": "AMMUNITION", "quantity": 8}, true)
	check(checks, reservation.success, "reserve front stock before combat")
	sim.advance(10)
	var metrics: Dictionary = sim.front_metrics("FRONT_A")
	check(checks, metrics.current_ammo_on_hand == 8 and metrics.current_available_ammo == 0 and sim.world.get_stockpile("A_STOCK").reserved.AMMUNITION == 8, "consumption protects reserved stock")
	check(checks, metrics.last_interval_demand == 4 and metrics.last_interval_consumed == 2 and metrics.last_interval_shortage == 2, "shortage equals demand minus consumption")
	check(checks, sim.audit().AMMUNITION.consumed == 2 and sim.audit().AMMUNITION.valid, "shortage does not enter consumed ledger")
	var shortages := events(sim, "FRONT_AMMO_SHORTAGE")
	check(checks, shortages.size() == 2 and shortages.all(func(e): return e.payload.front_id == "FRONT_A" and e.payload.resource_type_id == "AMMUNITION" and e.payload.demanded == 1 and e.payload.consumed == 0 and e.payload.shortage == 1 and e.payload.available_before_consumption == 0 and e.payload.changes.is_empty()), "shortage events have exact operational diagnostics and no ledger changes")
	check(checks, events(sim, "RESOURCE_CONSUMED").all(func(e): return e.actor_entity_id == "FRONT_A" and e.payload.reason_code == "FRONT_COMBAT_CONSUMPTION" and not e.payload.privileged), "resource service identifies nonprivileged front consumption")
	sim.advance(20)
	check(checks, sim.world.get_stockpile("A_STOCK").quantities.AMMUNITION == 8 and sim.world.get_front("FRONT_A").ammo_demand_accumulator_micro < 1000000, "unmet integer demand does not accumulate as debt")
	sim = fresh()
	sim.advance(5)
	set_front(sim, "SetFrontEnemyPressure", 100)
	sim.advance(5)
	check(checks, sim.front_metrics("FRONT_A").last_interval_demand == 6, "mid-interval pressure change does not rewrite earlier demand")
	sim = fresh()
	sim.advance(5)
	set_front(sim, "SetFrontPosture", "REDUCE_ACTIVITY")
	sim.advance(5)
	check(checks, sim.front_metrics("FRONT_A").last_interval_demand == 3, "mid-interval posture change does not rewrite earlier demand")
	data = Fixture.definition()
	data.fronts.append(front_data())
	data.fronts[1].id = "FRONT_C"
	sim = fresh(data)
	sim.advance(20)
	check(checks, sim.audit().AMMUNITION.consumed == 10 and sim.audit().AMMUNITION.stockpiles == 0 and sim.audit().AMMUNITION.valid, "fronts sharing one stockpile resolve sequentially without double spending")
	data = Fixture.definition()
	data.stockpiles[0].quantities = {"AMMUNITION": 100}
	data.logistics_edges = [{"id": "hq_a", "from_location_id": "ARMY_HQ", "to_location_id": "DEPOT_A", "travel_time_seconds": 10}]
	sim = fresh(data)
	var shipment: Dictionary = sim.execute({"type": "CreateShipment", "origin_stockpile_id": "HQ_STOCK", "destination_stockpile_id": "A_STOCK", "resource_type_id": "AMMUNITION", "quantity": 100}, true)
	sim.execute({"type": "DispatchShipment", "shipment_id": shipment.entity_id}, true)
	check(checks, sim.front_metrics("FRONT_A").ammo_coverage_milliseconds == 2500, "coverage excludes incoming cargo until physical arrival")

static func _privacy_and_intervals(checks: Array) -> void:
	var sim := fresh()
	sim.advance(9)
	check(checks, sim.command_view("LOCAL_A").information().is_empty(), "no local observation before one second")
	sim.advance()
	var view: RefCounted = sim.command_view("LOCAL_A")
	check(checks, view.information().size() == 9, "responsible command receives all nine local facts")
	var ammo: Dictionary = view.current_belief("FRONT_A", "FRONT_AMMO_ON_HAND", sim.time())
	check(checks, ammo.value == 6 and ammo.observed_at == 1 and ammo.received_at == 1 and ammo.confidence == 1 and ammo.source_system == "FRONT_OBSERVATION", "observation samples post-consumption state with exact provenance")
	check(checks, sim.command_view("ARMY_COMMAND").information().is_empty() and sim.command_view("LOCAL_B").information().is_empty(), "superior and peer do not learn front facts")
	check(checks, not view.has_method("get_front") and not view.has_method("front_metrics") and not view.has_method("get_entity"), "CommandView exposes no front truth escape hatch")
	check(checks, sim.world.ids("messages").is_empty(), "no automatic communication or request policy")
	check(checks, sim.front_metrics("FRONT_A").last_interval_demand == 4 and sim.front_metrics("FRONT_A").last_interval_consumed == 4 and sim.front_metrics("FRONT_A").last_interval_shortage == 0, "first complete interval is 4/4/0")
	sim.advance(10)
	check(checks, sim.front_metrics("FRONT_A").current_ammo_on_hand == 2 and sim.front_metrics("FRONT_A").last_interval_consumed == 4, "second complete interval is 4/4/0")
	sim.advance(10)
	var front: Dictionary = sim.world.get_front("FRONT_A")
	check(checks, front.last_interval_demand == 4 and front.last_interval_consumed == 2 and front.last_interval_shortage == 2, "third complete interval is 4/2/2")
	check(checks, front.current_interval_demand == 0 and front.current_interval_consumed == 0 and front.current_interval_shortage == 0, "completed interval counters reset")
	check(checks, sim.command_view("LOCAL_A").current_belief("FRONT_A", "FRONT_LAST_SHORTAGE", sim.time()).value == 2, "third observation reports full interval shortage")
	check(checks, sim.audit().AMMUNITION.stockpiles == 0 and sim.audit().AMMUNITION.consumed == 10 and sim.audit().AMMUNITION.valid, "stock never negative and all actual consumption conserved")
	var boundary_events: Array = sim.events.all().filter(func(e): return e.tick_index == 30)
	var resolution := -1
	var observation := -1
	var information := -1
	for i in range(boundary_events.size()):
		if boundary_events[i].event_type == "FRONT_AMMO_DEMAND_RESOLVED":
			resolution = i
		if boundary_events[i].event_type == "FRONT_OBSERVED":
			observation = i
		if boundary_events[i].event_type == "INFORMATION_INGESTED":
			information = i
	check(checks, resolution >= 0 and observation > resolution and information > observation, "boundary resolves demand before finalization and ingestion")
	var shortage_index := -1
	for i in range(boundary_events.size()):
		if boundary_events[i].event_type == "FRONT_AMMO_SHORTAGE":
			shortage_index = i
	check(checks, shortage_index >= 0 and resolution > shortage_index, "unmet demand is recorded before interval counters finalize")
	set_front(sim, "SetFrontEnemyPressure", 100)
	check(checks, sim.front_metrics("FRONT_A").current_desired_ammo_rate_milli == 8000 and sim.command_view("LOCAL_A").current_belief("FRONT_A", "FRONT_ENEMY_PRESSURE", sim.time()).value == 5000, "pressure truth changes immediately but belief waits for next sample")
	set_front(sim, "SetFrontPosture", "REDUCE_ACTIVITY")
	check(checks, sim.front_metrics("FRONT_A").current_desired_ammo_rate_milli == 4000, "pressure and posture formula combines correctly")
	sim.advance(10)
	check(checks, sim.command_view("LOCAL_A").current_belief("FRONT_A", "FRONT_ENEMY_PRESSURE", sim.time()).value == 10000 and sim.command_view("LOCAL_A").current_belief("FRONT_A", "FRONT_POSTURE", sim.time()).value == "REDUCE_ACTIVITY", "next sample updates changed conditions")

static func _replay(checks: Array) -> void:
	var first: Dictionary = Fixture.run(103, "first")
	var second: Dictionary = Fixture.run(103, "second")
	check(checks, first.success and second.success, "required demonstration completes twice")
	if not first.success or not second.success:
		return
	var sim: RefCounted = first.details.simulation
	check(checks, Exporter.equivalent(sim.snapshot(), second.details.simulation.snapshot()) and Exporter.equivalent(sim.events.all(), second.details.simulation.events.all()), "independent front runs match state, accumulator, beliefs and ordered events")
	check(checks, sim.front_metrics("FRONT_A").current_ammo_on_hand == 8 and sim.audit().AMMUNITION.created == 22 and sim.audit().AMMUNITION.consumed == 14, "demonstration final resource totals")
	check(checks, sim.world.clock().tick_index == 40 and sim.command_view("LOCAL_A").information().size() == 36, "demonstration completes four one-second local observations")
	check(checks, Exporter.export_run(sim, "res://artifacts/run_step103").success, "front package exports through existing exporter")
	var replayed: Dictionary = Exporter.replay_package("res://artifacts/run_step103")
	check(checks, replayed.success and replayed.details.state_match and replayed.details.events_match, "file replay matches front state and all semantic/authoritative events")
	var projection := World.new(sim.initial_world)
	var conservative := true
	for event in sim.events.all():
		projection.apply_event(event)
		var state: Dictionary = projection.snapshot()
		var physical := 0.0
		for stockpile in state.stockpiles.values():
			physical += stockpile.quantities.get("AMMUNITION", 0)
			conservative = conservative and stockpile.quantities.get("AMMUNITION", 0) >= stockpile.reserved.get("AMMUNITION", 0)
		conservative = conservative and state.ledger.AMMUNITION.created == physical + state.ledger.AMMUNITION.consumed + state.ledger.AMMUNITION.destroyed
	check(checks, conservative, "every front event prefix preserves resource conservation")
	check(checks, Exporter.equivalent(projection.snapshot(), sim.snapshot()), "event-only reconstruction retains accumulator, interval counters and observations")
	var dynamic_data: Dictionary = Fixture.definition()
	dynamic_data.fronts = []
	var dynamic := fresh(dynamic_data)
	dynamic.execute({"type": "CreateFront", "front": front_data()}, true)
	dynamic.advance(7)
	var replay: Dictionary = Exporter.replay(dynamic.initial_world, dynamic.inputs, 7)
	check(checks, replay.success and Exporter.equivalent(replay.details.simulation.snapshot(), dynamic.snapshot()), "runtime front creation and partial interval replay")


static func _precision(checks: Array) -> void:
	var sim := fresh()
	var front: Dictionary = sim.world.get_front("FRONT_A")
	check(checks, front.friendly_strength_centi == 6000 and front.enemy_pressure_centi == 5000 and front.base_ammo_rate_milli == 8000, "normal inputs canonicalize to centi-strength/pressure and milli-rate")
	check(checks, not front.has("enemy_pressure") and not front.has("base_ammo_demand_per_second") and not front.has("ammo_demand_compensation"), "front retains only canonical numeric fields")
	for expected in [400000, 800000, 200000]:
		sim.advance()
		check(checks, sim.world.get_front("FRONT_A").ammo_demand_accumulator_micro == expected, "exact fixture remainder " + str(expected))
	check(checks, sim.audit().AMMUNITION.consumed == 1, "tick three consumes exact integer part")
	set_front(sim, "SetFrontEnemyPressure", 33.333)
	check(checks, sim.world.get_front("FRONT_A").enemy_pressure_centi == 3333 and sim.front_metrics("FRONT_A").current_desired_ammo_rate_milli == 2666, "awkward pressure explicitly quantized before combined rate rounding")
	set_front(sim, "SetFrontEnemyPressure", 50.005)
	check(checks, sim.world.get_front("FRONT_A").enemy_pressure_centi == 5001, "half-centi pressure rounds away from zero")
	set_front(sim, "SetFrontFriendlyStrength", 60.125)
	check(checks, sim.world.get_front("FRONT_A").friendly_strength_centi == 6013, "half-centi strength rounds away from zero")
	var data: Dictionary = Fixture.definition()
	data.fronts[0].base_ammo_demand_per_second = 8.0005
	var half_rate := fresh(data)
	check(checks, half_rate.world.get_front("FRONT_A").base_ammo_rate_milli == 8001, "half-milli base rate rounds away from zero")
	data.fronts[0].base_ammo_demand_per_second = 0.001
	var tiny := fresh(data)
	check(checks, tiny.front_metrics("FRONT_A").current_desired_ammo_rate_milli == 1, "combined effective rate half-unit rounds away from zero")
	for bad in [NAN, INF, -1, 600000.001, 1e30]:
		data = Fixture.definition()
		data.fronts[0].base_ammo_demand_per_second = bad
		check(checks, not Simulation.new().initialize(data).success, "reject nonfinite negative or overflowing rate " + str(bad))
	sim = fresh()
	check(checks, sim.front_metrics("FRONT_A").ammo_coverage_milliseconds == 2500, "coverage uses integer floor milliseconds")
	set_front(sim, "SetFrontEnemyPressure", 33.333)
	check(checks, sim.front_metrics("FRONT_A").ammo_coverage_milliseconds == 3750, "awkward coverage floors integer quotient")
	sim.advance(3)
	front = sim.world.get_front("FRONT_A")
	check(checks, Exporter.equivalent(front, JSON.parse_string(JSON.stringify(front, "", true, true))), "canonical front state survives exact JSON roundtrip")
	check(checks, not Exporter.equivalent({"n": 0.2}, {"n": 0.2 + pow(2.0, -55)}), "replay comparator retains strict float difference")
	var restored := Simulation.new()
	check(checks, restored.initialize_snapshot(JSON.parse_string(JSON.stringify(sim.initial_world, "", true, true))).success and restored.world.get_front("FRONT_A").enemy_pressure_centi is int, "parsed initial front restored to integer runtime representation")
	for duration in [0.0001, 0.15, 2.0]:
		data = Fixture.definition()
		data.tick_duration = duration
		check(checks, not Simulation.new().initialize(data).success, "front rejects tick duration without exact one-second boundaries " + str(duration))
		data.fronts = []
		var empty := fresh(data)
		check(checks, not empty.execute({"type": "CreateFront", "front": front_data()}, true).success, "runtime front enforces same tick precision")


static func _coverage_bounds(checks: Array) -> void:
	var sim := fresh()
	var service := FrontService.new(sim)
	var maximum: Dictionary = service.coverage_ms(9007199254740991, 1000000)
	check(checks, maximum.milliseconds == 9007199254740991 and maximum.status == "FINITE", "coverage at max exact JSON integer")
	var first_over: Dictionary = service.coverage_ms(4503599627370496, 500000)
	check(checks, first_over.milliseconds == null and first_over.status == "OUT_OF_RANGE", "coverage one millisecond above bound rejected without saturation")
	check(checks, service.coverage_ms(9007199254740991, 1).status == "OUT_OF_RANGE", "huge stock tiny rate cannot overflow coverage arithmetic")
	check(checks, service.coverage_ms(0, 1).milliseconds == 0 and service.coverage_ms(0, 1).status == "FINITE", "empty stock with positive rate has finite zero coverage")
	set_front(sim, "SetFrontEnemyPressure", 0)
	sim.advance(10)
	check(checks, sim.front_metrics("FRONT_A").ammo_coverage_status == "ZERO_DEMAND" and sim.command_view("LOCAL_A").current_belief("FRONT_A", "FRONT_AMMO_COVERAGE_STATUS", sim.time()).value == "ZERO_DEMAND", "zero demand coverage status reaches local belief")
	var data: Dictionary = Fixture.definition()
	for stock in data.stockpiles:
		if stock.id == "A_STOCK":
			stock.quantities.AMMUNITION = 9007199254740991
	data.fronts[0].enemy_pressure = 100
	data.fronts[0].base_ammo_demand_per_second = 0.001
	sim = fresh(data)
	sim.advance(10)
	check(checks, sim.front_metrics("FRONT_A").ammo_coverage_milliseconds == null and sim.command_view("LOCAL_A").current_belief("FRONT_A", "FRONT_AMMO_COVERAGE_STATUS", sim.time()).value == "OUT_OF_RANGE", "out of range local observation remains distinct from zero demand")
	check(checks, sim.command_view("LOCAL_A").current_belief("FRONT_A", "FRONT_AMMO_COVERAGE_MILLISECONDS", sim.time()).value == null, "out of range milliseconds serialize as null")
	check(checks, Exporter.export_run(sim, "res://artifacts/run_coverage_bound").success and Exporter.replay_package("res://artifacts/run_coverage_bound").success, "huge stock out of range observation strictly replays")
	data = Fixture.definition()
	data.fronts[0].base_ammo_demand_per_second = 600000
	sim = fresh(data)
	set_front(sim, "SetFrontEnemyPressure", 100)
	set_front(sim, "SetFrontPosture", "PRESS")
	check(checks, sim.front_metrics("FRONT_A").current_desired_ammo_rate_milli == 900000000, "max base rate and posture combined numerator exact")
	sim.advance()
	check(checks, sim.world.get_front("FRONT_A").ammo_demand_accumulator_micro == 0 and sim.front_metrics("FRONT_A").current_ammo_on_hand == 0, "max rate tick remains exact without negative stock")
	check(checks, FrontDefinition.tick_compatible(0.1), "100 millisecond tick accepted")
