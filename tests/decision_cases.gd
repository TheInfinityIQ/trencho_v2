extends RefCounted
const Simulation = preload("res://kernel/simulation.gd")
const Demo = preload("res://debug/decision_demo.gd")
const Policy = preload("res://kernel/decision_policy_104.gd")
const Planner = preload("res://kernel/local_command_planner.gd")
const Exporter = preload("res://kernel/run_exporter.gd")
const World = preload("res://kernel/world_state.gd")
const Authority = preload("res://kernel/authority_service.gd")

static func check(checks: Array, condition: bool, name: String) -> void:
	checks.append({"name": "104 / " + name, "passed": condition})

static func fresh(scenario := "A", autonomous := true) -> RefCounted:
	var sim := Simulation.new()
	var initialized: Dictionary = sim.initialize(Demo.definition(scenario, autonomous), 104, "decision-tests")
	assert(initialized.success, JSON.stringify(initialized))
	return sim

static func events(sim: RefCounted, type: String) -> Array:
	return sim.events.all().filter(func(event): return event.event_type == type)

static func run() -> Dictionary:
	var checks: Array = []
	var scenarios: Dictionary = {}
	_scenarios(checks, scenarios)
	_policy(checks)
	_information(checks)
	_authority(checks)
	_journal_and_replay(checks)
	var failures: Array = []
	for item in checks:
		if not item.passed: failures.append(item.name)
	return {"success": failures.is_empty(), "checks": checks, "failures": failures, "scenarios": scenarios}

static func _scenarios(checks: Array, summaries: Dictionary) -> void:
	for scenario in ["A", "B", "C", "D"]:
		var completed: Dictionary = Demo.run(scenario)
		check(checks, completed.success, "scenario " + scenario + " completes")
		if not completed.success: continue
		var sim: RefCounted = completed.details.simulation
		var journal: Array = sim.decision_journal("LOCAL_A")
		var first: Dictionary = journal[0]
		var chosen := "PRESS" if scenario == "A" else ("HOLD" if scenario == "B" else "REDUCE_ACTIVITY")
		var score := 110 if scenario == "A" else (80 if scenario == "B" else 180)
		check(checks, journal.size() == 3 and first.selected_action == chosen and first.selected_score == score, "scenario " + scenario + " exact first selection and score")
		check(checks, first.outcome_attached and first.outcome.interval_demand == (6 if scenario == "A" else (4 if scenario == "B" else 2)), "scenario " + scenario + " next-interval observed demand")
		check(checks, sim.audit().AMMUNITION.valid and sim.audit().AMMUNITION.destroyed == 0, "scenario " + scenario + " conservation")
		check(checks, sim.command_view("ARMY_COMMAND").information().is_empty() and sim.command_view("LOCAL_B").information().is_empty() and sim.world.ids("messages").is_empty(), "scenario " + scenario + " information privacy and no communication")
		check(checks, sim.world.ids("shipments").is_empty() and sim.world.ids("resource_reservations").is_empty(), "scenario " + scenario + " no automatic logistics or reservations")
		var press: Dictionary = sim.world.get_entity("decision_candidates", first.candidate_ids[2])
		check(checks, press.eligible == (scenario == "A") and (press.score == 110 if scenario == "A" else press.score == null), "scenario " + scenario + " PRESS eligibility/null score")
		if scenario == "B":
			check(checks, press.rejection_reasons == ["INSUFFICIENT_STRENGTH_MARGIN"] and not first.action_required and events(sim, "FRONT_POSTURE_CHANGED").is_empty(), "ordinary HOLD records rejection and avoids fake mutation")
		if scenario in ["C", "D"]:
			check(checks, press.rejection_reasons.has("RECENT_AMMO_SHORTAGE") and press.rejection_reasons.has("SUPPLY_NOT_SECURE") and first.outcome.interval_shortage == (2 if scenario == "C" else 0), "shortage rejection and observed conservation consequence")
		if scenario == "D":
			check(checks, journal[1].selected_action == "HOLD" and journal[1].action_changed and journal[1].selected_score == 80, "recovery returns autonomously to HOLD")
			check(checks, sim.audit().AMMUNITION.created == 202 and sim.audit().AMMUNITION.consumed == 8 and sim.audit().AMMUNITION.stockpiles == 194, "recovery exact resource totals")
			check(checks, first.outcome.starting_ammo_available == 0 and first.outcome.ending_ammo_available == 198, "descriptive outcome includes scripted resupply without reward grading")
		check(checks, Exporter.export_run(sim, "res://artifacts/run_step104_" + scenario).success and Exporter.replay_package("res://artifacts/run_step104_" + scenario).success, "scenario " + scenario + " strict file replay")
		summaries[scenario] = {"decision_ids": journal.map(func(d): return d.id), "actions": journal.map(func(d): return d.selected_action), "scores": journal.map(func(d): return d.selected_score), "event_count": sim.events.count(), "end_tick": sim.world.clock().tick_index, "ledger": sim.audit(), "outcomes": journal.filter(func(d): return d.outcome_attached).size()}

static func values() -> Dictionary:
	return {"FRONT_FRIENDLY_STRENGTH": 6000, "FRONT_ENEMY_PRESSURE": 5000, "FRONT_POSTURE": "HOLD", "FRONT_AMMO_AVAILABLE": 100, "FRONT_AMMO_DEMAND_RATE": 4000, "FRONT_AMMO_COVERAGE_MILLISECONDS": 25000, "FRONT_AMMO_COVERAGE_STATUS": "FINITE", "FRONT_LAST_SHORTAGE": 0, "FRONT_AMMO_ON_HAND": 100, "FRONT_INTERVAL_DEMAND": 4, "FRONT_INTERVAL_CONSUMED": 4}

static func _policy(checks: Array) -> void:
	for item in [[4999, "CRITICAL", "REDUCE_ACTIVITY"], [5000, "CONSTRAINED", "HOLD"], [14999, "CONSTRAINED", "HOLD"], [15000, "SECURE", "HOLD"]]:
		var data := values()
		data.FRONT_AMMO_COVERAGE_MILLISECONDS = item[0]
		var result := Policy.evaluate(data)
		check(checks, result.classifications.supply_state == item[1] and result.selected_action == item[2], "coverage threshold " + str(item[0]))
	for item in [[1999, "CONTESTED", false, null], [2000, "STRONG_ADVANTAGE", true, 90], [4000, "STRONG_ADVANTAGE", true, 110], [-2000, "STRONG_DISADVANTAGE", false, null]]:
		var data := values()
		data.FRONT_FRIENDLY_STRENGTH = data.FRONT_ENEMY_PRESSURE + item[0]
		var result := Policy.evaluate(data)
		check(checks, result.classifications.strength_state == item[1] and result.candidates[2].eligible == item[2] and result.candidates[2].score == item[3], "strength threshold " + str(item[0]))
	var data := values()
	data.FRONT_AMMO_COVERAGE_STATUS = "ZERO_DEMAND"
	data.FRONT_AMMO_COVERAGE_MILLISECONDS = null
	check(checks, Policy.evaluate(data).classifications.supply_state == "NO_ACTIVE_DEMAND" and not Policy.evaluate(data).candidates[2].eligible, "zero demand does not justify PRESS")
	data.FRONT_LAST_SHORTAGE = 2
	check(checks, Policy.evaluate(data).classifications.supply_state == "CRITICAL" and Policy.evaluate(data).candidates[1].score == 180, "recent shortage takes precedence over zero demand")
	data.FRONT_LAST_SHORTAGE = 0
	data.FRONT_AMMO_COVERAGE_STATUS = "OUT_OF_RANGE"
	data.FRONT_FRIENDLY_STRENGTH = 9000
	check(checks, Policy.evaluate(data).classifications.supply_state == "SECURE" and Policy.evaluate(data).selected_action == "PRESS", "out of range coverage means secure")
	var tied := Policy.select([{"action": "PRESS", "eligible": true, "score": 80}, {"action": "REDUCE_ACTIVITY", "eligible": true, "score": 80}, {"action": "HOLD", "eligible": true, "score": 80}])
	check(checks, tied.action == "HOLD" and tied.tie_break, "fixed tie preference independent of candidate array order")
	check(checks, Policy.ORDER == ["HOLD", "REDUCE_ACTIVITY", "PRESS"] and not Policy.ORDER.has("WITHDRAW"), "withdraw excluded from autonomous candidate set")
	var result := Policy.evaluate(values())
	check(checks, result.candidates.all(func(c): return c.score == null or (c.score is int and c.score == c.factor_contributions.values().reduce(func(sum, v): return sum + v, 0))), "scores are exact sum of recorded integer factors")

static func inject(sim: RefCounted, data: Dictionary, owner := "LOCAL_A", observed_micro := 0, expiry: Variant = null) -> Dictionary:
	var ids: Dictionary = {}
	for key in data:
		var fact := {"subject_entity_id": "FRONT_A", "fact_key": String(key), "value": data[key], "observed_at": observed_micro / 1000000.0, "confidence": 1.0, "expires_at": expiry}
		var result: Dictionary = sim.execute({"type": "IngestInformation", "owner_command_id": owner, "fact": fact}, true)
		assert(result.success)
		ids[key] = result.entity_id
	return ids

static func evaluate(sim: RefCounted, ids: Dictionary, complete := true, observed_micro := 0, owner := "LOCAL_A") -> Dictionary:
	return sim.execute({"type": "EvaluateLocalDecision", "command_id": owner, "front_id": "FRONT_A", "record_ids": ids, "complete": complete, "observed_at_micro": observed_micro}, true)

static func _information(checks: Array) -> void:
	var sim := fresh()
	sim.advance(9)
	check(checks, sim.decision_journal("LOCAL_A").is_empty(), "no decision before first complete second")
	sim.advance()
	check(checks, sim.decision_journal("LOCAL_A").size() == 1 and sim.command_view("LOCAL_A").information().size() == 11, "eleven-fact batch triggers exactly one cycle")
	var stream: Array = sim.events.all()
	var complete: int = events(sim, "FRONT_OBSERVATION_COMPLETE")[0].event_id.get_slice(":", 1).to_int()
	check(checks, events(sim, "INFORMATION_INGESTED").filter(func(e): return e.event_id.get_slice(":", 1).to_int() < complete).size() == 11, "all eleven records precede complete signal")
	for variant in ["missing", "partial", "old-nine", "expired", "stale", "mixed"]:
		sim = fresh("B", false)
		var data := values()
		if variant == "missing": data.erase("FRONT_AMMO_AVAILABLE")
		if variant == "old-nine":
			data.erase("FRONT_INTERVAL_DEMAND")
			data.erase("FRONT_INTERVAL_CONSUMED")
		var ids := inject(sim, data, "LOCAL_A", 0, 0.5 if variant == "expired" else null)
		if variant in ["expired", "stale"]:
			sim.execute({"type": "SetFrontEnabled", "front_id": "FRONT_A", "value": false}, true)
			sim.advance(6 if variant == "expired" else 16)
		if variant == "mixed":
			var replacement := inject(sim, {"FRONT_ENEMY_PRESSURE": 4000})
			ids.FRONT_ENEMY_PRESSURE = "wrong-record"
		var result := evaluate(sim, ids, variant != "partial")
		var decision: Dictionary = sim.world.get_entity("decisions", result.entity_id)
		check(checks, decision.state == "SKIPPED" and decision.candidate_ids.is_empty() and events(sim, "FRONT_POSTURE_CHANGED").is_empty(), "abstain on " + variant + " information")
		if variant == "stale":
			check(checks, decision.skip_reasons.has("STALE_REQUIRED_BELIEF") and decision.stale_keys.size() == 11, "stale fact keys journaled without world fallback")
		if variant in ["partial", "old-nine", "mixed"]:
			check(checks, decision.skip_reasons.has("INCOMPLETE_OBSERVATION_BATCH"), "batch consistency reason " + variant)
	sim = fresh()
	sim.execute({"type": "SetFrontFriendlyStrength", "front_id": "FRONT_A", "value": 90}, true)
	var data := values()
	data.FRONT_FRIENDLY_STRENGTH = 5000
	var ids := inject(sim, data)
	var result := evaluate(sim, ids)
	check(checks, sim.world.get_entity("decisions", result.entity_id).selected_action == "HOLD" and sim.world.get_front("FRONT_A").friendly_strength_centi == 9000, "authoritative advantage cannot override weaker private belief")
	sim.advance(10)
	check(checks, sim.decision_journal("LOCAL_A").back().selected_action == "PRESS", "later real observation enables PRESS")
	sim = fresh("B", false)
	ids = inject(sim, values())
	sim.execute({"type": "SetFrontEnabled", "front_id": "FRONT_A", "value": false}, true)
	sim.advance(15)
	result = evaluate(sim, ids)
	check(checks, sim.world.get_entity("decisions", result.entity_id).state == "SELECTED", "freshness accepts exactly 1.5 seconds")
	check(checks, not sim.command_view("LOCAL_A").has_method("get_front") and not sim.command_view("LOCAL_A").has_method("snapshot"), "planner boundary remains detached without truth methods")

	sim = fresh("B", false)
	ids = inject(sim, values())
	result = evaluate(sim, ids)
	var original_decision_id: String = result.entity_id
	sim.execute({"type": "SetFrontEnabled", "front_id": "FRONT_A", "value": false}, true)
	sim.execute({"type": "CreateResource", "stockpile_id": "A_STOCK", "resource_type_id": "AMMUNITION", "quantity": 500}, true)
	sim.advance(10)
	data = values()
	data.FRONT_AMMO_AVAILABLE = 99
	data.FRONT_INTERVAL_DEMAND = 4
	data.FRONT_INTERVAL_CONSUMED = 1
	data.FRONT_LAST_SHORTAGE = 3
	ids = inject(sim, data, "LOCAL_A", 1000000)
	evaluate(sim, ids, true, 1000000)
	var outcome: Dictionary = sim.world.get_entity("decisions", original_decision_id).outcome
	check(checks, outcome.ending_ammo_available == 99 and outcome.interval_consumed == 1 and outcome.interval_shortage == 3 and sim.front_metrics("FRONT_A").current_available_ammo == 700, "outcome uses subsequent observation records rather than current world truth")
	check(checks, outcome.belief_record_ids_by_fact.FRONT_INTERVAL_CONSUMED == ids.FRONT_INTERVAL_CONSUMED, "outcome consumption provenance names the actual observed record")
static func _authority(checks: Array) -> void:
	var sim := fresh("A", false)
	var data := values()
	data.FRONT_FRIENDLY_STRENGTH = 9000
	var ids := inject(sim, data, "LOCAL_B")
	var result := evaluate(sim, ids, true, 0, "LOCAL_B")
	var decision: Dictionary = sim.world.get_entity("decisions", result.entity_id)
	check(checks, decision.selected_action == "PRESS" and not decision.action_success and decision.action_error_code == "UNAUTHORIZED" and events(sim, "DECISION_ACTION_FAILED").size() == 1, "unrelated command action failure recorded")
	check(checks, sim.world.get_front("FRONT_A").posture == "HOLD" and events(sim, "FRONT_POSTURE_CHANGED").is_empty(), "authority failure cannot change posture")
	check(checks, Authority.new(sim).can_set_front_posture("LOCAL_A", "FRONT_A") and not Authority.new(sim).can_set_front_posture("LOCAL_B", "FRONT_A"), "AuthorityService enforces direct front responsibility")
	check(checks, not sim.execute({"type": "SetFrontPosture", "front_id": "FRONT_A", "value": "PRESS", "actor_entity_id": "LOCAL_B"}, false).success, "external actor cannot spoof autonomous pathway")
	check(checks, not sim.execute({"type": "EvaluateLocalDecision", "command_id": "LOCAL_A", "front_id": "FRONT_A", "record_ids": {}, "complete": false, "observed_at_micro": 0}, false).success, "explicit diagnostic evaluation requires privilege")
	for bad in ["MISSING", "wrong-owner", "operational"]:
		data = Demo.definition()
		if bad == "MISSING": data.commands[1].local_decision_front_id = "MISSING"
		if bad == "wrong-owner": data.commands[2].local_decision_front_id = "FRONT_A"
		if bad == "operational": data.commands[1].command_level = "OPERATIONAL"
		check(checks, not Simulation.new().initialize(data).success, "invalid planner assignment rejected " + bad)

	sim = fresh("A", false)
	sim.execute({"type": "SetFrontPosture", "front_id": "FRONT_A", "value": "PRESS"}, true)
	data = values()
	data.FRONT_FRIENDLY_STRENGTH = 9000
	ids = inject(sim, data)
	var before: int = events(sim, "FRONT_POSTURE_CHANGED").size()
	result = evaluate(sim, ids)
	decision = sim.world.get_entity("decisions", result.entity_id)
	check(checks, decision.action_required and decision.action_success and not decision.action_changed and events(sim, "FRONT_POSTURE_CHANGED").size() == before, "actual already-selected posture avoids redundant mutation despite older posture belief")
	check(checks, Exporter.export_run(sim, "res://artifacts/run_step104_action_noop").success and Exporter.replay_package("res://artifacts/run_step104_action_noop").success, "explicit belief evaluation and no-op authority pathway replay")
	sim = fresh("A", false)
	ids = inject(sim, data, "LOCAL_B")
	result = evaluate(sim, ids, true, 0, "LOCAL_B")
	sim.advance(10)
	ids = inject(sim, data, "LOCAL_B", 1000000)
	evaluate(sim, ids, true, 1000000, "LOCAL_B")
	check(checks, not sim.world.get_entity("decisions", result.entity_id).outcome_attached, "failed unauthorized action never receives a successful-action outcome")
	check(checks, Exporter.export_run(sim, "res://artifacts/run_step104_authority_fail").success and Exporter.replay_package("res://artifacts/run_step104_authority_fail").success, "authority failure and decision journal strict replay")
static func _journal_and_replay(checks: Array) -> void:
	var first: Dictionary = Demo.run("A")
	var sim: RefCounted = first.details.simulation
	var journal: Array = sim.decision_journal("LOCAL_A")
	var decisions := events(sim, "DECISION_STARTED")
	check(checks, journal.size() == 3 and journal.map(func(d): return d.id).size() == 3 and journal[0].id != journal[1].id and journal[1].id != journal[2].id, "stable unique decision IDs independent of display names")
	check(checks, journal.all(func(d): return d.belief_record_ids.size() == 11 and d.candidate_ids.size() == 3), "belief and candidate IDs retained in each decision")
	check(checks, journal.all(func(d): return d.belief_record_ids_by_fact.FRONT_ENEMY_PRESSURE in d.belief_record_ids and sim.world.get_entity("information_records", d.belief_record_ids_by_fact.FRONT_ENEMY_PRESSURE).fact_key == "FRONT_ENEMY_PRESSURE"), "every belief value maps directly to its information record")
	check(checks, sim.world.ids("decision_candidates").size() == 9, "all candidate projections queryable")
	var by_id: Dictionary = {}
	for event in sim.events.all(): by_id[event.event_id] = event
	check(checks, sim.events.all().filter(func(e): return e.event_type.begins_with("DECISION_")).all(func(e): return e.correlation_id is String and e.correlation_id.begins_with("decision:") and by_id.has(e.causation_event_id)), "decision correlation and causation resolve")
	check(checks, events(sim, "DECISION_CANDIDATE_RECORDED").all(func(e): return by_id[e.causation_event_id].event_type == "DECISION_STARTED") and events(sim, "DECISION_SELECTED").all(func(e): return by_id[e.causation_event_id].event_type == "DECISION_CANDIDATE_RECORDED"), "candidate and selection immediate parents correct")
	check(checks, events(sim, "FRONT_POSTURE_CHANGED").size() == 1 and events(sim, "FRONT_POSTURE_CHANGED")[0].actor_entity_id == "LOCAL_A" and events(sim, "FRONT_POSTURE_CHANGED")[0].payload.source_system == "AUTONOMOUS_COMMAND_DECISION" and by_id[events(sim, "FRONT_POSTURE_CHANGED")[0].causation_event_id].event_type == "DECISION_SELECTED", "authorized posture change carries actor source and decision causation")
	check(checks, journal[0].beliefs.FRONT_INTERVAL_DEMAND == 4 and journal[0].outcome.interval_demand == 6 and journal[0].outcome.interval_consumed == 6, "PRESS affects following interval only")
	check(checks, journal[0].outcome.evaluation_start_time_micro == 1000000 and journal[0].outcome.evaluation_end_time_micro == 2000000 and journal[0].outcome.belief_record_ids.size() == 11, "outcome interval and observation provenance exact")
	check(checks, journal[0].outcome_attached and journal[1].outcome_attached and not journal[2].outcome_attached, "prior outcomes close before final pending cycle")
	var boundary: Array = sim.events.all().filter(func(e): return e.tick_index == 20)
	var order: Array = boundary.map(func(e): return e.event_type)
	check(checks, order.find("FRONT_OBSERVATION_COMPLETE") < order.find("DECISION_OUTCOME_ATTACHED") and order.find("DECISION_OUTCOME_ATTACHED") < order.find("DECISION_STARTED"), "outcome closes before new decision at same boundary")
	check(checks, journal.all(func(d): return not d.get("outcome", {}).has("reward") and not d.get("outcome", {}).has("fitness") and not d.has("random_roll")), "outcomes descriptive with no rewards or randomness")
	var detached: Array = sim.decision_journal("LOCAL_A")
	detached[0].selected_action = "WITHDRAW"
	check(checks, sim.decision_journal("LOCAL_A")[0].selected_action == "PRESS", "journal queries detached")
	var projection := World.new(sim.initial_world)
	var conserved := true
	for event in sim.events.all():
		projection.apply_event(event)
		var state: Dictionary = projection.snapshot()
		var physical := 0
		for stock in state.stockpiles.values():
			physical += int(stock.quantities.get("AMMUNITION", 0))
		conserved = conserved and state.ledger.AMMUNITION.created == physical + state.ledger.AMMUNITION.consumed + state.ledger.AMMUNITION.destroyed
	check(checks, conserved and Exporter.equivalent(projection.snapshot(), sim.snapshot()), "event-only journal reconstruction and every-prefix conservation")
	var second: Dictionary = Demo.run("A", 104, "other-run")
	check(checks, Exporter.equivalent(sim.snapshot(), second.details.simulation.snapshot()) and Exporter.equivalent(sim.events.all(), second.details.simulation.events.all()), "independent runs reproduce all decisions outcomes and ordered events")
	var other_seed: Dictionary = Demo.run("A", 888)
	check(checks, Exporter.equivalent(journal, other_seed.details.simulation.decision_journal("LOCAL_A")), "seed unused by deterministic local policy")
	check(checks, Exporter.export_run(sim, "res://artifacts/run_step104").success and Exporter.replay_package("res://artifacts/run_step104").success, "decision package strict replay")
