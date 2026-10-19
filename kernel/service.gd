extends RefCounted

const R = preload("res://kernel/result.gd")
var sim: RefCounted
var world: RefCounted

func _init(context: RefCounted) -> void:
	sim = context
	world = sim.world

func change(table: String, value: Dictionary) -> Dictionary:
	return {"table": table, "id": value.id, "value": value}

func enabled_stockpile(id: String) -> Dictionary:
	var s: Dictionary = world.get_stockpile(id)
	if s.is_empty():
		return {}
	var location: Dictionary = world.get_location(s.location_id)
	if not s.enabled or location.is_empty() or not location.enabled:
		return {}
	return s

func quantity_valid(resource_id: String, quantity: Variant) -> bool:
	if not (quantity is int or quantity is float):
		return false
	var resource: Dictionary = world.get_entity("resource_types", resource_id)
	if resource.is_empty() or not is_finite(float(quantity)) or quantity <= 0:
		return false
	if quantity > 9007199254740991:
		return false
	return resource.allow_fractional_quantity or quantity == floor(quantity)

func available(s: Dictionary, resource: String) -> float:
	return s.quantities.get(resource, 0) - s.reserved.get(resource, 0)

func ledger(resource: String) -> Dictionary:
	return world.get_entity("ledger", resource)

