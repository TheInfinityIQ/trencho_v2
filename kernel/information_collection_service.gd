extends "res://kernel/service.gd"
# Trusted orchestration. Local response reasoning receives only detached own beliefs.
const Clock = preload("res://kernel/clock.gd")
const Communication = preload("res://kernel/communication_service.gd")
const Router = preload("res://kernel/router.gd")
const Policy = preload("res://kernel/subordinate_report_policy.gd")
const Fronts = preload("res://kernel/front_service.gd")

func _emit(type: String, item: Dictionary, cause: Variant = null) -> void:
	# Anchor each projection update to the actual current authoritative prefix.
	var anchor: String = sim.events.all().back().event_id
	var result: Dictionary = sim.information_collections.emit_record("INFORMATION_COLLECTION_" + type, item, sim.time(), anchor)
	assert(result.success, JSON.stringify(result))

func _unavailable(item: Dictionary, reason: String, cause: Variant = null) -> void:
	item.state = "UNAVAILABLE"
	item.result_code = reason
	item.completed_at = sim.time()
	item.failure_event_id = cause if reason in ["REQUEST_MESSAGE_FAILED", "RESPONSE_MESSAGE_FAILED"] else null
	_emit("UNAVAILABLE", item, cause)

func _send(item: Dictionary, sender: String, recipient: String, payload: Dictionary) -> Dictionary:
	var prior: Dictionary = sim.context
	sim.context = {"actor_entity_id": sender, "input_id": item.collection_id, "source_system": "SUBORDINATE_SITUATION_REPORT", "privileged": false}
	var result: Dictionary = Communication.new(sim).send(sender, recipient, "REPORT", payload)
	sim.context = prior
	return result

func start_boundary() -> void:
	if Clock.units(sim.time()) % 1000000 != 0: return
	var enabled: Dictionary = {}
	for entry in sim.information_collection_configuration(): enabled[entry.operational_command_id] = entry.enabled
	var areas: Dictionary = sim.player_observer.configuration()
	for requirement in sim.information_requirements.snapshot().requirements:
		if requirement.state != "OPEN" or not enabled.get(requirement.owner_command_id, false) or not sim.information_collections.for_requirement(requirement.requirement_id).is_empty(): continue
		var area: Dictionary = areas.get(requirement.area_id, {})
		var front: Dictionary = world.get_front(area.get("front_id", "") if area.get("front_id") is String else "")
		if front.is_empty(): continue
		var collector: Dictionary = world.get_command(front.responsible_command_id)
		if collector.is_empty() or collector.command_level != "LOCAL" or not _descendant(collector.id, requirement.owner_command_id): continue
		var item := {"collection_id": "information-collection:%010d" % (sim.information_collections.records().size() + 1), "requirement_id": requirement.requirement_id, "owner_command_id": requirement.owner_command_id, "collector_command_id": collector.id, "area_id": area.id, "front_id": front.id, "method": "SUBORDINATE_SITUATION_REPORT", "state": "REQUEST_PENDING", "created_at": sim.time(), "completed_at": null, "request_message_id": null, "response_message_id": null, "source_observation_batch_id": null, "source_information_record_ids": [], "information_record_ids": [], "result_code": null, "failure_event_id": null}
		_emit("STARTED", item)
		if not _observing(item):
			_unavailable(item, "LOCAL_OBSERVATION_UNAVAILABLE")
			continue
		var payload := {"subtype": "AREA_SITUATION_REPORT_REQUEST", "collection_id": item.collection_id, "requirement_id": item.requirement_id, "area_id": item.area_id, "front_id": item.front_id, "requesting_command_id": item.owner_command_id, "collector_command_id": item.collector_command_id}
		var sent := _send(item, item.owner_command_id, item.collector_command_id, payload)
		if not sent.success:
			_unavailable(item, "NO_COMMUNICATION_ROUTE")
			continue
		item.request_message_id = sent.entity_id
		item.state = "REQUEST_IN_TRANSIT"
		_emit("REQUEST_SENT", item, world.last_event(sent.entity_id))
	drain()

func _descendant(command: String, owner: String) -> bool:
	var current: Dictionary = world.get_command(command)
	while not current.is_empty() and current.superior_command_id != null:
		if current.superior_command_id == owner: return true
		current = world.get_command(current.superior_command_id)
	return false

func _observing(item: Dictionary) -> bool:
	var front: Dictionary = world.get_front(item.front_id)
	var command: Dictionary = world.get_command(item.collector_command_id)
	return not front.is_empty() and not command.is_empty() and command.get("local_decision_front_id") == item.front_id and Fronts.new(sim).operational(front)

func _sample(item: Dictionary) -> Dictionary:
	var records: Array = sim.command_view(item.collector_command_id).information()
	var candidates: Array = []
	for id in world.ids("observation_batches"):
		var batch: Dictionary = world.get_entity("observation_batches", id)
		if batch.command_id == item.collector_command_id and batch.front_id == item.front_id: candidates.append(batch)
	candidates.sort_custom(func(a, b): return a.observed_at_micro > b.observed_at_micro or a.observed_at_micro == b.observed_at_micro and a.id < b.id)
	if candidates.is_empty(): return {}
	return Policy.sample(item.collector_command_id, item.front_id, records, candidates[0], Clock.units(sim.time()))

func drain() -> void:
	# A zero-latency request and report can finish in this call, without recursion.
	for unused in range(3):
		var changed := false
		for item in sim.information_collections.records():
			if item.state in ["COMPLETED", "UNAVAILABLE", "REQUEST_PENDING"]: continue
			var request: Dictionary = world.get_entity("messages", item.request_message_id)
			if request.state == "FAILED":
				_unavailable(item, "REQUEST_MESSAGE_FAILED", world.last_event(request.id))
				changed = true
				continue
			if item.state in ["REQUEST_IN_TRANSIT", "WAITING_FOR_LOCAL_OBSERVATION"]:
				if request.state != "DELIVERED": continue
				if not _observing(item):
					_unavailable(item, "LOCAL_OBSERVATION_UNAVAILABLE", world.last_event(request.id))
					changed = true
					continue
				var sampled := _sample(item)
				if sampled.is_empty():
					if item.state != "WAITING_FOR_LOCAL_OBSERVATION":
						item.state = "WAITING_FOR_LOCAL_OBSERVATION"
						_emit("WAITING", item, world.last_event(request.id))
					continue
				var response := _send(item, item.collector_command_id, item.owner_command_id, Policy.payload(item, sampled))
				if not response.success:
					_unavailable(item, "NO_RETURN_COMMUNICATION_ROUTE", world.last_event(request.id))
					changed = true
					continue
				item.state = "REPORT_IN_TRANSIT"
				item.response_message_id = response.entity_id
				item.source_observation_batch_id = sampled.observation_batch_id
				item.source_information_record_ids = sampled.source_information_record_ids
				_emit("REPORT_SENT", item, world.last_event(response.entity_id))
				changed = true
			elif item.state == "REPORT_IN_TRANSIT":
				var response: Dictionary = world.get_entity("messages", item.response_message_id)
				if response.state == "FAILED":
					_unavailable(item, "RESPONSE_MESSAGE_FAILED", world.last_event(response.id))
					changed = true
				elif response.state == "DELIVERED":
					var ingested: Array = []
					for key in Policy.KEYS:
						for record in sim.command_view(item.owner_command_id).information():
							if record.source_message_id == response.id and record.fact_key == "REPORTED_" + key: ingested.append(record.id)
					assert(ingested.size() == 6)
					item.information_record_ids = ingested
					item.state = "COMPLETED"
					item.completed_at = sim.time()
					item.result_code = "REPORT_DELIVERED"
					_emit("COMPLETED", item, world.last_event(ingested.back()))
					sim.information_requirements.register_completion(item)
					var satisfied: Dictionary = sim.information_requirements.satisfy(item)
					assert(satisfied.success, JSON.stringify(satisfied))
					changed = true
		if not changed: break
