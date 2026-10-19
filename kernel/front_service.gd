extends "res://kernel/service.gd"

const Definition = preload("res://kernel/front_definition.gd")
const Clock = preload("res://kernel/clock.gd")
const Resources = preload("res://kernel/resource_service.gd")
const Information = preload("res://kernel/information_service.gd")
const Authority = preload("res://kernel/authority_service.gd")
const Journal = preload("res://kernel/decision_journal.gd")

func create(data: Dictionary) -> Dictionary:
	if not sim.privileged():
		return R.fail("UNAUTHORIZED")
	if not Definition.tick_compatible(world.clock().tick_duration):
		return R.fail("INVALID_FRONT", {"reason": "UNSUPPORTED_FRONT_TICK_DURATION"})
	if not R.json_compatible(data):
		return R.fail("INVALID_FRONT")
	for key in ["id", "responsible_command_id", "location_id", "supply_stockpile_id"]:
		if not data.get(key) is String:
			return R.fail("INVALID_FRONT", {"field": key})
	if world.has_id(data.id) or ":" in data.id:
		return R.fail("INVALID_FRONT", {"reason": "INVALID_OR_DUPLICATE_ID"})
	var ammo: Dictionary = world.get_entity("resource_types", "AMMUNITION")
	if ammo.is_empty() or ammo.allow_fractional_quantity:
		return R.fail("RESOURCE_TYPE_MISMATCH")
	var result: Dictionary = Definition.make(data, world.get_command(data.responsible_command_id), world.get_location(data.location_id), world.get_stockpile(data.supply_stockpile_id), sim.time())
	if not result.success:
		return result
	sim.commit("FRONT_CREATED", [change("fronts", result.details.front)], {}, data.id)
	return R.ok(data.id)

func set_field(id: String, field: String, value: Variant) -> Dictionary:
	if not sim.privileged():
		if field != "posture" or not sim.actor() is String or not Authority.new(sim).can_set_front_posture(sim.actor(), id):
			return R.fail("UNAUTHORIZED")
		var decision: Dictionary = world.get_entity("decisions", sim.context.get("decision_id", ""))
		if sim.context.get("source_system") != "AUTONOMOUS_COMMAND_DECISION" or decision.is_empty() or decision.command_id != sim.actor() or decision.front_id != id or decision.selected_action != value or decision.state != "SELECTED":
			return R.fail("UNAUTHORIZED")
	var front: Dictionary = world.get_front(id)
	if front.is_empty():
		return R.fail("INVALID_ENTITY")
	var types := {"enemy_pressure": "FRONT_ENEMY_PRESSURE_CHANGED", "friendly_strength": "FRONT_FRIENDLY_STRENGTH_CHANGED", "posture": "FRONT_POSTURE_CHANGED", "enabled": "FRONT_ENABLED_CHANGED"}
	if not types.has(field):
		return R.fail("INVALID_FRONT")
	if field in ["enemy_pressure", "friendly_strength"] and not Definition.number(value, 0, 100):
		return R.fail("INVALID_FRONT", {"field": field})
	if field == "posture" and (not value is String or not Definition.MULTIPLIERS.has(value)):
		return R.fail("INVALID_FRONT", {"field": field})
	if field == "enabled" and not value is bool:
		return R.fail("INVALID_FRONT", {"field": field})
	if field in ["enemy_pressure", "friendly_strength"]:
		value = Definition.quantize(value, 100)
		field += "_centi"
	var event_type: String = types.get(field.trim_suffix("_centi"))
	var previous: Variant = front[field]
	front[field] = value
	if not sim.privileged() and previous == value:
		return R.ok(id, {"changed": false})
	var payload := {"previous": previous, "value": value}
	if not sim.privileged():
		payload.actor_command_id = sim.actor()
		payload.decision_id = sim.context.decision_id
		payload.source_system = "AUTONOMOUS_COMMAND_DECISION"
		payload.reason_code = "AUTONOMOUS_COMMAND_DECISION"
	var event: String = sim.commit(event_type, [change("fronts", front)], payload, id)
	return R.ok(id) if sim.privileged() else R.ok(id, {"changed": true, "event_id": event})

func operational(front: Dictionary) -> bool:
	return front.enabled and world.get_command(front.responsible_command_id).enabled and world.get_location(front.location_id).enabled and not enabled_stockpile(front.supply_stockpile_id).is_empty()

# Pure tick preparation: no persistent mutation occurs before TICK_ADVANCED applies it.
# Integer micro-ammunition accumulates exact quantized demand.
func prepare_tick(duration: float) -> Dictionary:
	var changes: Array = []
	var demands: Dictionary = {}
	for id in world.active_ids("fronts"):
		var front: Dictionary = world.get_front(id)
		if not operational(front):
			continue
		@warning_ignore("integer_division")
		var duration_ms: int = Clock.units(duration) / 1000
		var total: int = front.ammo_demand_accumulator_micro + Definition.desired_rate(front) * duration_ms
		@warning_ignore("integer_division")
		var demanded: int = total / 1000000
		front.ammo_demand_accumulator_micro = total % 1000000
		changes.append(change("fronts", front))
		demands[id] = demanded
	return {"changes": changes, "demands": demands}

func resolve_tick(demands: Dictionary, tick_event: String) -> void:
	for id in demands:
		var demanded: int = demands[id]
		var front: Dictionary = world.get_front(id)
		var previous_context: Dictionary = sim.context
		sim.context = {"actor_entity_id": id, "source_system": "FRONT_SIMULATION", "input_id": "front-tick:%s:%d" % [id, world.clock().tick_index], "causation_event_id": tick_event, "privileged": false}
		if demanded > 0:
			var stock: Dictionary = world.get_stockpile(front.supply_stockpile_id)
			var before := int(available(stock, "AMMUNITION"))
			var consumed := mini(demanded, before)
			if consumed > 0:
				var result: Dictionary = Resources.new(sim).consume_for_front(id, consumed)
				assert(result.success, "Validated front consumption unexpectedly failed")
			var shortage := demanded - consumed
			if shortage > 0:
				sim.commit("FRONT_AMMO_SHORTAGE", [], {"front_id": id, "resource_type_id": "AMMUNITION", "demanded": demanded, "consumed": consumed, "shortage": shortage, "available_before_consumption": before}, id)
			front.current_interval_demand += demanded
			front.current_interval_consumed += consumed
			front.current_interval_shortage += shortage
			# An integer demand resolution is meaningful; fractional-only ticks add no event.
			sim.commit("FRONT_AMMO_DEMAND_RESOLVED", [change("fronts", front)], {"demanded": demanded, "consumed": consumed, "shortage": shortage}, id)
		if Clock.units(sim.time()) >= int(front.next_observation_time_micro):
			_observe(front)
		sim.context = previous_context

func _observe(front: Dictionary) -> void:
	front.last_interval_demand = front.current_interval_demand
	front.last_interval_consumed = front.current_interval_consumed
	front.last_interval_shortage = front.current_interval_shortage
	front.current_interval_demand = 0
	front.current_interval_consumed = 0
	front.current_interval_shortage = 0
	while int(front.next_observation_time_micro) <= Clock.units(sim.time()):
		front.next_observation_time_micro += 1000000
	var cause: String = sim.commit("FRONT_OBSERVED", [change("fronts", front)], {"observed_at": sim.time()}, front.id)
	var state := metrics(front.id)
	var facts := {"FRONT_FRIENDLY_STRENGTH": front.friendly_strength_centi, "FRONT_ENEMY_PRESSURE": front.enemy_pressure_centi, "FRONT_POSTURE": front.posture, "FRONT_AMMO_ON_HAND": state.current_ammo_on_hand, "FRONT_AMMO_AVAILABLE": state.current_available_ammo, "FRONT_AMMO_DEMAND_RATE": state.current_desired_ammo_rate_milli, "FRONT_AMMO_COVERAGE_MILLISECONDS": state.ammo_coverage_milliseconds, "FRONT_AMMO_COVERAGE_STATUS": state.ammo_coverage_status, "FRONT_LAST_SHORTAGE": front.last_interval_shortage}
	var autonomous: bool = world.get_command(front.responsible_command_id).get("local_decision_front_id") == front.id
	if autonomous:
		facts["FRONT_INTERVAL_DEMAND"] = front.last_interval_demand
		facts["FRONT_INTERVAL_CONSUMED"] = front.last_interval_consumed
	var records: Dictionary = {}
	for key in facts:
		var fact := {"subject_entity_id": front.id, "fact_key": key, "value": facts[key], "observed_at": sim.time(), "confidence": 1.0}
		var ingested: Dictionary = Information.new(sim).ingest(front.responsible_command_id, fact, "FRONT_OBSERVATION", null, cause)
		assert(ingested.success, JSON.stringify({"fact": fact, "result": ingested}))
		records[key] = ingested.entity_id
	if autonomous:
		var batch := {"id": "observation:" + cause, "command_id": front.responsible_command_id, "front_id": front.id, "record_ids": records, "observed_at_micro": Clock.units(sim.time()), "complete": records.size() == 11, "expected_fact_keys": facts.keys()}
		var completed: String = sim.commit("FRONT_OBSERVATION_COMPLETE", [change("observation_batches", batch)], {"observation_batch_id": batch.id}, batch.id, cause)
		Journal.new(sim).on_complete(batch, completed)

func metrics(id: String) -> Dictionary:
	var front: Dictionary = world.get_front(id)
	if front.is_empty():
		return {}
	var stock: Dictionary = world.get_stockpile(front.supply_stockpile_id)
	var rate := Definition.desired_rate(front)
	var remaining := int(available(stock, "AMMUNITION"))
	var coverage := coverage_ms(remaining, rate)
	return {"current_ammo_on_hand": stock.quantities.get("AMMUNITION", 0), "current_available_ammo": remaining, "current_desired_ammo_rate_milli": rate, "ammo_coverage_milliseconds": coverage.milliseconds, "ammo_coverage_status": coverage.status, "last_interval_demand": front.last_interval_demand, "last_interval_consumed": front.last_interval_consumed, "last_interval_shortage": front.last_interval_shortage}

# Quotient/remainder decomposition avoids overflowing available * 1,000,000.
# Null conditions are distinguished by status; no arithmetic overflows or saturation.
func coverage_ms(ammo: int, rate: int) -> Dictionary:
	if rate == 0:
		return {"milliseconds": null, "status": "ZERO_DEMAND"}
	@warning_ignore("integer_division")
	var whole: int = ammo / rate
	if whole > 9007199254:
		return {"milliseconds": null, "status": "OUT_OF_RANGE"}
	@warning_ignore("integer_division")
	var remainder_ms: int = (ammo % rate) * 1000000 / rate
	var base_ms := whole * 1000000
	if remainder_ms > 9007199254740991 - base_ms:
		return {"milliseconds": null, "status": "OUT_OF_RANGE"}
	return {"milliseconds": base_ms + remainder_ms, "status": "FINITE"}
