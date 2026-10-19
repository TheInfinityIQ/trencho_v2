extends RefCounted
const R = preload("res://kernel/result.gd")

static func normalize(definitions: Variant, locations: Dictionary, fronts: Dictionary, used: Dictionary) -> Dictionary:
	if not definitions is Array or not R.json_compatible(definitions): return R.fail("INVALID_STRATEGIC_AREA")
	var areas: Dictionary = {}
	var enabled_membership: Dictionary = {}
	for source in definitions:
		if not source is Dictionary or not source.get("id") is String or source.id.is_empty() or ":" in source.id or used.has(source.id) or areas.has(source.id): return R.fail("INVALID_STRATEGIC_AREA", {"reason": "INVALID_OR_DUPLICATE_ID"})
		var area: Dictionary = source.duplicate(true)
		area.display_name = area.get("display_name", area.id)
		area.enabled = area.get("enabled", true)
		area.front_id = area.get("front_id")
		area.metadata = area.get("metadata", {})
		if not area.display_name is String or not area.enabled is bool or not area.metadata is Dictionary or not area.get("location_ids") is Array or area.location_ids.is_empty(): return R.fail("INVALID_STRATEGIC_AREA")
		if area.front_id != null and (not area.front_id is String or not fronts.has(area.front_id)): return R.fail("INVALID_STRATEGIC_AREA", {"reason": "INVALID_FRONT"})
		var seen: Dictionary = {}
		for id in area.location_ids:
			if not id is String or not locations.has(id) or seen.has(id): return R.fail("INVALID_STRATEGIC_AREA", {"reason": "INVALID_LOCATION"})
			seen[id] = true
			if area.enabled:
				if enabled_membership.has(id): return R.fail("INVALID_STRATEGIC_AREA", {"reason": "OVERLAPPING_ENABLED_AREAS"})
				enabled_membership[id] = area.id
		area.location_ids.sort()
		areas[area.id] = area
	return R.ok(null, {"areas": areas})
