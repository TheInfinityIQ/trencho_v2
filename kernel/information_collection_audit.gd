extends RefCounted
# Independent event-only reconstruction checks typed links against their historical
# authoritative prefix, including original Local facts and actual delivered reports.
const R = preload("res://kernel/result.gd")
const World = preload("res://kernel/world_state.gd")
const State = preload("res://kernel/information_collection_state.gd")
const Policy = preload("res://kernel/subordinate_report_policy.gd")
const Clock = preload("res://kernel/clock.gd")
const Router = preload("res://kernel/router.gd")

static func exact(a: Variant, b: Variant) -> bool:
	return JSON.stringify(a, "", true, true) == JSON.stringify(b, "", true, true)

static func reconstruct(initial: Dictionary, configuration: Array, areas: Dictionary, requirements: Array, collection_events: Array, core_events: Array) -> Dictionary:
	var state := State.new()
	var world := World.new(initial)
	var enabled: Dictionary = {}
	for entry in configuration: enabled[entry.operational_command_id] = entry.enabled
	var by_requirement: Dictionary = {}
	for item in requirements: by_requirement[item.requirement_id] = item
	var position := 0
	var current_anchor: Variant = null
	for event in collection_events:
		var applied := state.apply_event(event)
		if not applied.success: return applied
		var anchor: Variant = event.get("source_authoritative_event_id")
		if not anchor is String: return R.fail("INVALID_COLLECTION_PROVENANCE")
		while current_anchor != anchor and position < core_events.size():
			world.apply_event(core_events[position])
			current_anchor = core_events[position].event_id
			position += 1
		if current_anchor != anchor or event.get("at") != world.clock().simulation_time_seconds or not event.get("record") is Dictionary: return R.fail("INVALID_COLLECTION_PROVENANCE")
		var item: Dictionary = event.record
		var requirement: Dictionary = by_requirement.get(item.get("requirement_id"), {})
		var area: Dictionary = areas.get(item.get("area_id"), {})
		var front: Dictionary = world.get_front(item.get("front_id", ""))
		var owner: Dictionary = world.get_command(item.get("owner_command_id", ""))
		var local: Dictionary = world.get_command(item.get("collector_command_id", ""))
		if requirement.is_empty() or area.is_empty() or front.is_empty() or local.is_empty() or owner.is_empty() or not enabled.get(owner.id, false) or owner.command_level != "OPERATIONAL" or local.command_level != "LOCAL" or requirement.owner_command_id != owner.id or requirement.area_id != area.id or area.front_id != front.id or front.responsible_command_id != local.id or item.created_at < requirement.created_at: return R.fail("INVALID_COLLECTION_PROVENANCE")
		var parent: Variant = local.superior_command_id
		while parent != null and parent != owner.id: parent = world.get_command(parent).get("superior_command_id")
		if parent != owner.id: return R.fail("INVALID_COLLECTION_PROVENANCE")
		var request: Dictionary = world.get_entity("messages", item.get("request_message_id", "") if item.get("request_message_id") is String else "")
		if item.get("request_message_id") != null:
			var expected := {"subtype": "AREA_SITUATION_REPORT_REQUEST", "collection_id": item.collection_id, "requirement_id": item.requirement_id, "area_id": item.area_id, "front_id": item.front_id, "requesting_command_id": item.owner_command_id, "collector_command_id": item.collector_command_id}
			if request.is_empty() or request.sender_command_id != owner.id or request.recipient_command_id != local.id or request.message_type != "REPORT" or request.correlation_id != item.collection_id or not exact(request.payload, expected): return R.fail("INVALID_COLLECTION_REQUEST")
		var response: Dictionary = world.get_entity("messages", item.get("response_message_id", "") if item.get("response_message_id") is String else "")
		if item.get("response_message_id") != null:
			if request.get("state") != "DELIVERED" or response.is_empty() or response.sender_command_id != local.id or response.recipient_command_id != owner.id or response.message_type != "REPORT" or response.correlation_id != item.collection_id: return R.fail("INVALID_COLLECTION_REPORT")
			var own_records: Array = []
			for id in world.information_for(local.id): own_records.append(world.get_entity("information_records", id))
			var batch: Dictionary = world.get_entity("observation_batches", item.get("source_observation_batch_id", "") if item.get("source_observation_batch_id") is String else "")
			var sample_data := Policy.sample(local.id, front.id, own_records, batch, Clock.units(response.sent_at))
			if sample_data.is_empty() or item.source_information_record_ids != sample_data.source_information_record_ids or not exact(response.payload, Policy.payload(item, sample_data)): return R.fail("INVALID_COLLECTION_LOCAL_SOURCE")
		if event.event_type == "INFORMATION_COLLECTION_WAITING":
			if request.get("state") != "DELIVERED": return R.fail("INVALID_COLLECTION_WAIT")
			var own_records: Array = []
			for id in world.information_for(local.id): own_records.append(world.get_entity("information_records", id))
			var latest: Dictionary = {}
			for id in world.ids("observation_batches"):
				var batch: Dictionary = world.get_entity("observation_batches", id)
				if batch.command_id == local.id and batch.front_id == front.id and (latest.is_empty() or batch.observed_at_micro > latest.observed_at_micro or batch.observed_at_micro == latest.observed_at_micro and batch.id < latest.id): latest = batch
			if not latest.is_empty() and not Policy.sample(local.id, front.id, own_records, latest, Clock.units(event.at)).is_empty(): return R.fail("INVALID_COLLECTION_WAIT")
		if event.event_type == "INFORMATION_COLLECTION_COMPLETED":
			if response.get("state") != "DELIVERED" or item.completed_at != response.delivery_time or item.information_record_ids.size() != 6: return R.fail("INVALID_COLLECTION_COMPLETION")
			for index in range(6):
				var record: Dictionary = world.get_entity("information_records", item.information_record_ids[index])
				var fact: Dictionary = Policy.facts(response.payload)[index]
				if record.is_empty() or record.owner_command_id != owner.id or record.source_command_id != local.id or record.source_system != null or record.source_message_id != response.id or record.subject_entity_id != front.id or record.fact_key != fact.fact_key or not exact(record.value, fact.value) or record.observed_at != fact.observed_at or record.received_at != event.at or record.confidence != 1: return R.fail("INVALID_COLLECTION_INGESTION")
		if event.event_type == "INFORMATION_COLLECTION_UNAVAILABLE":
			match item.result_code:
				"NO_COMMUNICATION_ROUTE":
					if Router.find(world, owner.id, local.id, true).success or not request.is_empty(): return R.fail("INVALID_COLLECTION_FAILURE")
				"NO_RETURN_COMMUNICATION_ROUTE":
					if request.get("state") != "DELIVERED" or Router.find(world, local.id, owner.id, true).success or not response.is_empty(): return R.fail("INVALID_COLLECTION_FAILURE")
				"REQUEST_MESSAGE_FAILED", "RESPONSE_MESSAGE_FAILED":
					var failed: Dictionary = request if item.result_code == "REQUEST_MESSAGE_FAILED" else response
					if failed.get("state") != "FAILED" or item.failure_event_id != world.last_event(failed.id): return R.fail("INVALID_COLLECTION_FAILURE")
				"LOCAL_OBSERVATION_UNAVAILABLE":
					var stock: Dictionary = world.get_stockpile(front.supply_stockpile_id)
					if local.enabled and front.enabled and world.get_location(front.location_id).enabled and not stock.is_empty() and stock.enabled and world.get_location(stock.location_id).enabled and local.get("local_decision_front_id") == front.id: return R.fail("INVALID_COLLECTION_FAILURE")
	return R.ok(null, {"state": state})
