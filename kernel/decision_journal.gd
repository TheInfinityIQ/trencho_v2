extends "res://kernel/service.gd"
# Trusted coordinator/projection writer, separate from belief-only reasoning.
const Planner = preload("res://kernel/local_command_planner.gd")
const Clock = preload("res://kernel/clock.gd")
const Fronts = preload("res://kernel/front_service.gd")

func debug_evaluate(input: Dictionary) -> Dictionary:
	if not sim.privileged():
		return R.fail("UNAUTHORIZED")
	if not input.get("record_ids") is Dictionary or not input.get("complete") is bool or not input.get("observed_at_micro") is int and not input.get("observed_at_micro") is float:
		return R.fail("INVALID_INPUT")
	if input.observed_at_micro < 0 or input.observed_at_micro != floor(input.observed_at_micro) or input.observed_at_micro > Clock.units(sim.time()):
		return R.fail("INVALID_INPUT")
	if world.get_command(input.command_id).is_empty() or world.get_front(input.front_id).is_empty():
		return R.fail("INVALID_ENTITY")
	if world.get_command(input.command_id).command_level != "LOCAL":
		return R.fail("UNSUPPORTED_COMMAND_LEVEL")
	var batch := {"id": sim.entity_id("observation"), "command_id": input.command_id, "front_id": input.front_id, "record_ids": input.record_ids.duplicate(true), "observed_at_micro": int(input.observed_at_micro), "complete": input.complete}
	var cause: String = sim.commit("OBSERVATION_BATCH_RECORDED", [change("observation_batches", batch)], {"debug": true}, batch.id)
	return evaluate(batch, cause)

func on_complete(batch: Dictionary, cause: String) -> void:
	var command: Dictionary = world.get_command(batch.command_id)
	if command.get("local_decision_front_id") == batch.front_id and command.enabled:
		evaluate(batch, cause)

func evaluate(batch: Dictionary, cause: String) -> Dictionary:
	var prior_context: Dictionary = sim.context
	var view: RefCounted = sim.command_view(batch.command_id)
	var now := Clock.units(sim.time())
	var observed := Planner.evaluate(view, batch.front_id, batch, now)
	if observed.success and observed.outcome_values.size() == 2:
		_attach_outcome(batch, observed, cause, now)
	var id: String = sim.entity_id("decision")
	sim.context = {"actor_entity_id": batch.command_id, "source_system": "AUTONOMOUS_COMMAND_DECISION", "input_id": id, "decision_id": id, "causation_event_id": cause, "privileged": false}
	var decision := {"id": id, "decision_id": id, "command_id": batch.command_id, "front_id": batch.front_id, "trigger_event_id": cause, "observation_batch_id": batch.id, "started_at_micro": now, "selected_at_micro": null, "state": "STARTED", "belief_record_ids": observed.belief_record_ids, "beliefs": observed.values, "candidate_ids": [], "selected_candidate_id": null, "selected_action": null, "outcome_attached": false, "outcome_event_id": null, "action_required": false, "action_success": false}
	decision.belief_record_ids_by_fact = _provenance(observed.records)
	var start: String = sim.commit("DECISION_STARTED", [change("decisions", decision)], {}, id, cause, id)
	if not observed.success:
		decision.state = "SKIPPED"
		decision.skip_reasons = observed.reasons
		decision.missing_keys = observed.missing_keys
		decision.stale_keys = observed.stale_keys
		decision.inconsistent_keys = observed.inconsistent_keys
		decision.invalid_keys = observed.invalid_keys
		sim.commit("DECISION_SKIPPED", [change("decisions", decision)], {"reasons": observed.reasons}, id, start, id)
		sim.context = prior_context
		return R.ok(id)
	var selected: Dictionary = {}
	var candidate_events: Dictionary = {}
	for item in observed.policy.candidates:
		var candidate: Dictionary = item.duplicate(true)
		candidate.id = sim.entity_id("candidate")
		candidate.candidate_id = candidate.id
		candidate.decision_id = id
		candidate.belief_record_ids = observed.belief_record_ids.duplicate()
		candidate.belief_record_ids_by_fact = decision.belief_record_ids_by_fact.duplicate()
		decision.candidate_ids.append(candidate.id)
		var event: String = sim.commit("DECISION_CANDIDATE_RECORDED", [change("decision_candidates", candidate)], {"decision_id": id}, candidate.id, start, id)
		candidate_events[candidate.id] = event
		if candidate.action == observed.policy.selected_action:
			selected = candidate
	decision.state = "SELECTED"
	decision.selected_at_micro = now
	decision.selected_candidate_id = selected.id
	decision.selected_action = selected.action
	decision.selected_score = selected.score
	decision.classifications = observed.policy.classifications
	decision.tie_break = observed.policy.tie_break
	decision.action_required = selected.action != observed.values.FRONT_POSTURE
	var selection: String = sim.commit("DECISION_SELECTED", [change("decisions", decision)], {"tie_break": decision.tie_break, "action_required": decision.action_required}, id, candidate_events[selected.id], id)
	sim.context.causation_event_id = selection
	var applied: Dictionary = R.ok(null, {"changed": false})
	if decision.action_required:
		applied = Fronts.new(sim).set_field(batch.front_id, "posture", selected.action)
	decision.action_success = applied.success
	decision.action_error_code = applied.error_code
	decision.action_changed = applied.details.get("changed", false)
	decision.action_event_id = applied.details.get("event_id")
	sim.commit("DECISION_ACTION_RESOLVED" if applied.success else "DECISION_ACTION_FAILED", [change("decisions", decision)], {"action_success": applied.success, "error_code": applied.error_code}, id, decision.action_event_id if decision.action_event_id != null else selection, id)
	sim.context = prior_context
	return R.ok(id)

func _attach_outcome(batch: Dictionary, observed: Dictionary, cause: String, now: int) -> void:
	for id in world.ids("decisions"):
		var decision: Dictionary = world.get_entity("decisions", id)
		if decision.command_id != batch.command_id or decision.front_id != batch.front_id or decision.state != "SELECTED" or not decision.action_success or decision.outcome_attached or now < int(decision.selected_at_micro) + 1000000:
			continue
		var prior_context: Dictionary = sim.context
		sim.context = {"actor_entity_id": decision.command_id, "source_system": "AUTONOMOUS_COMMAND_DECISION", "input_id": id, "decision_id": id, "causation_event_id": cause, "privileged": false}
		var outcome := Planner.outcome(decision.beliefs, observed.values, observed.outcome_values, decision, now)
		outcome.observation_batch_id = batch.id
		outcome.belief_record_ids = observed.belief_record_ids.duplicate()
		outcome.belief_record_ids_by_fact = _provenance(observed.records)
		decision.outcome = outcome
		decision.state = "OUTCOME_ATTACHED"
		decision.outcome_attached = true
		decision.outcome_event_id = "event:%010d" % (world.sequence() + 1)
		sim.commit("DECISION_OUTCOME_ATTACHED", [change("decisions", decision)], {"outcome": outcome}, id, cause, id)
		sim.context = prior_context

func _provenance(records: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for key in records:
		result[key] = records[key].id
	return result
