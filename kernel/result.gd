extends RefCounted

static func ok(entity_id: Variant = null, details: Dictionary = {}) -> Dictionary:
	return {"success": true, "error_code": "", "entity_id": entity_id, "details": details}

static func fail(code: String, details: Dictionary = {}) -> Dictionary:
	return {"success": false, "error_code": code, "entity_id": null, "details": details}

# Godot JSON parses numbers as doubles. Reject values that cannot round-trip safely.
static func json_compatible(value: Variant) -> bool:
	if value == null or value is bool or value is String or value is StringName:
		return true
	if value is int:
		return value >= -9007199254740991 and value <= 9007199254740991
	if value is float:
		return is_finite(value) and absf(value) <= 9007199254740991.0
	if value is Array:
		for item in value:
			if not json_compatible(item):
				return false
		return true
	if value is Dictionary:
		for key in value:
			if not (key is String or key is StringName) or not json_compatible(value[key]):
				return false
		return true
	return false

