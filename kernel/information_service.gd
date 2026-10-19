extends "res://kernel/service.gd"

func validate_fact(fact: Dictionary) -> Dictionary:
	for key in ["subject_entity_id", "fact_key", "value", "observed_at", "confidence"]:
		if not fact.has(key):
			return R.fail("INVALID_INFORMATION", {"missing": key})
	if not fact.subject_entity_id is String or fact.subject_entity_id.is_empty() or not fact.fact_key is String or fact.fact_key.is_empty():
		return R.fail("INVALID_INFORMATION")
	for key in ["observed_at", "confidence"]:
		if not (fact[key] is int or fact[key] is float) or not is_finite(float(fact[key])):
			return R.fail("INVALID_INFORMATION")
	if fact.confidence < 0 or fact.confidence > 1 or fact.observed_at < 0 or fact.observed_at > sim.time():
		return R.fail("INVALID_INFORMATION")
	var expiry: Variant = fact.get("expires_at")
	if expiry != null and (not (expiry is int or expiry is float) or not is_finite(float(expiry)) or expiry < 0):
		return R.fail("INVALID_INFORMATION")
	return R.ok()

func ingest(owner: String, fact: Dictionary, source: String, message_id: Variant = null, cause: Variant = null) -> Dictionary:
	var validation := validate_fact(fact)
	if not validation.success:
		return validation
	if world.get_command(owner).is_empty():
		return R.fail("INVALID_ENTITY")
	var id: String = sim.entity_id("information")
	var record := {"id": id, "owner_command_id": owner, "subject_entity_id": fact.subject_entity_id, "fact_key": fact.fact_key, "value": fact.value, "source_command_id": source if message_id != null else null, "source_system": source if message_id == null else null, "observed_at": fact.observed_at, "received_at": sim.time(), "confidence": fact.confidence, "expires_at": fact.get("expires_at"), "source_message_id": message_id, "causation_event_id": cause}
	sim.commit("INFORMATION_INGESTED", [change("information_records", record)], {}, id, cause)
	return R.ok(id)

func get_current_belief(owner: String, subject: String, key: String, at_time: float) -> Dictionary:
	var best: Dictionary = {}
	for id in world.belief_ids(owner, subject, key):
		var record: Dictionary = world.get_entity("information_records", id)
		if record.received_at > at_time or record.observed_at > at_time or (record.expires_at != null and record.expires_at <= at_time):
			continue
		if best.is_empty() or record.observed_at > best.observed_at or (record.observed_at == best.observed_at and record.received_at > best.received_at) or (record.observed_at == best.observed_at and record.received_at == best.received_at and record.id < best.id):
			best = record
	return best
