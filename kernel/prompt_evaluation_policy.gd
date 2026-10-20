extends RefCounted
# Pure interpretation of delivered recipient report copies. No world, observer,
# service, message transport, stock or subordinate-belief capability is accepted.
const REPORT_FIELDS = ["id", "superior_command_id", "front_id", "report_state", "need_id", "need_revision", "report_message_id", "source_observed_at_micro", "report_received_at_micro"]
const RESULTS = ["KNOWN_CONCERN_PRESENT", "ASSESSMENT_AVAILABLE", "NO_ACTIVE_KNOWN_CONCERN", "FURTHER_INFORMATION_REQUIRED"]

static func knowledge(reports: Array) -> Array:
	var result: Array = []
	for report in reports:
		var copy: Dictionary = {}
		for key in REPORT_FIELDS: copy[key] = report.get(key)
		result.append(copy)
	return result

static func primary_before(a: Dictionary, b: Dictionary) -> bool:
	if a.report_state != b.report_state: return a.report_state == "ACTIVE"
	if a.report_received_at_micro != b.report_received_at_micro: return a.report_received_at_micro > b.report_received_at_micro
	if a.need_id != b.need_id: return a.need_id < b.need_id
	return a.id < b.id

static func evaluate(prompt: Dictionary, area: Dictionary, reports: Array) -> Dictionary:
	var considered: Array = []
	if area.get("front_id") != null:
		for report in knowledge(reports):
			if report.superior_command_id == prompt.recipient_command_id and report.front_id == area.front_id and report.report_state in ["ACTIVE", "RESOLVED"]: considered.append(report)
	considered.sort_custom(func(a, b): return a.id < b.id)
	var primary: Array = considered.duplicate(true)
	primary.sort_custom(primary_before)
	var result := "FURTHER_INFORMATION_REQUIRED"
	var code := "NO_SUPPORTED_AREA_INFORMATION"
	if not primary.is_empty():
		var active: bool = primary[0].report_state == "ACTIVE"
		if prompt.prompt_type == "DIRECT_ATTENTION":
			result = "KNOWN_CONCERN_PRESENT" if active else "NO_ACTIVE_KNOWN_CONCERN"
			code = "ACTIVE_AMMO_SUPPLY_CONCERN" if active else "LAST_KNOWN_AMMO_NEED_RESOLVED"
		else:
			result = "ASSESSMENT_AVAILABLE"
			code = "ACTIVE_AMMO_SUPPLY_PROBLEM" if active else "KNOWN_AMMO_NEED_RESOLVED"
	var message_ids: Array = []
	for report in considered:
		if report.report_message_id not in message_ids: message_ids.append(report.report_message_id)
	message_ids.sort()
	return {"result": result, "assessment_code": code, "primary_report_id": null if primary.is_empty() else primary[0].id, "knowledge_report_ids": considered.map(func(r): return r.id), "knowledge_message_ids": message_ids, "knowledge_reports": considered}
