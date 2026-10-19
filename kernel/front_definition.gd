extends RefCounted

const R = preload("res://kernel/result.gd")
const Clock = preload("res://kernel/clock.gd")
const MULTIPLIERS = {"HOLD": 1000, "PRESS": 1500, "REDUCE_ACTIVITY": 500, "WITHDRAW": 250}
# Combined numerator stays below the exact JSON integer limit.
const MAX_RATE_MILLI = 600000000

static func tick_compatible(duration: float) -> bool:
	var micros := roundi(duration * 1000000.0)
	return micros > 0 and micros <= 1000000 and micros % 1000 == 0 and 1000000 % micros == 0

static func number(value: Variant, minimum: float, maximum: float) -> bool:
	return (value is int or value is float) and is_finite(float(value)) and value >= minimum and value <= maximum

# Nonnegative input: nearest unit, exact halves away from zero.
static func quantize(value: Variant, scale: int) -> int:
	return floori(float(value) * scale + 0.5)

static func canonical(data: Dictionary, decimal_key: String, integer_key: String, scale: int, maximum: int) -> int:
	if data.has(integer_key):
		if data.has(decimal_key):
			return -1
		var value: Variant = data[integer_key]
		if not number(value, 0, maximum) or value != floor(value):
			return -1
		return int(value)
	if not number(data.get(decimal_key), 0, float(maximum) / scale):
		return -1
	return quantize(data[decimal_key], scale)

static func make(data: Dictionary, command: Dictionary, location: Dictionary, stockpile: Dictionary, at_time: float) -> Dictionary:
	for key in ["id", "location_id", "responsible_command_id", "supply_stockpile_id"]:
		if not data.get(key) is String or data[key].is_empty():
			return R.fail("INVALID_FRONT", {"field": key})
	if command.is_empty() or location.is_empty() or stockpile.is_empty():
		return R.fail("INVALID_ENTITY")
	if stockpile.location_id != location.id and stockpile.location_id not in command.directly_controlled_location_ids:
		return R.fail("INVALID_FRONT", {"reason": "UNASSOCIATED_SUPPLY_LOCATION"})
	var strength := canonical(data, "friendly_strength", "friendly_strength_centi", 100, 10000)
	var pressure := canonical(data, "enemy_pressure", "enemy_pressure_centi", 100, 10000)
	var rate := canonical(data, "base_ammo_demand_per_second", "base_ammo_rate_milli", 1000, MAX_RATE_MILLI)
	if strength < 0 or pressure < 0 or rate < 0:
		return R.fail("INVALID_FRONT", {"reason": "INVALID_FIXED_POINT_QUANTITY"})
	if not data.get("posture", "HOLD") is String or not MULTIPLIERS.has(data.get("posture", "HOLD")):
		return R.fail("INVALID_FRONT", {"field": "posture"})
	if not data.get("enabled", true) is bool or not data.get("metadata", {}) is Dictionary or not data.get("display_name", data.id) is String:
		return R.fail("INVALID_FRONT")
	var accumulator := canonical(data if data.has("ammo_demand_accumulator_micro") else {"ammo_demand_accumulator": data.get("ammo_demand_accumulator", 0)}, "ammo_demand_accumulator", "ammo_demand_accumulator_micro", 1000000, 999999)
	if accumulator < 0 or accumulator >= 1000000:
		return R.fail("INVALID_FRONT", {"field": "ammo_demand_accumulator_micro"})
	var front := {"id": data.id, "display_name": data.get("display_name", data.id), "location_id": data.location_id, "responsible_command_id": data.responsible_command_id, "supply_stockpile_id": data.supply_stockpile_id, "friendly_strength_centi": strength, "enemy_pressure_centi": pressure, "posture": data.get("posture", "HOLD"), "base_ammo_rate_milli": rate, "ammo_demand_accumulator_micro": accumulator, "enabled": data.get("enabled", true), "metadata": data.get("metadata", {}).duplicate(true), "created_at_micro": Clock.units(at_time), "next_observation_time_micro": Clock.units(at_time) + 1000000, "current_interval_demand": 0, "current_interval_consumed": 0, "current_interval_shortage": 0, "last_interval_demand": 0, "last_interval_consumed": 0, "last_interval_shortage": 0}
	return R.ok(data.id, {"front": front})

static func desired_rate(front: Dictionary) -> int:
	var numerator: int = front.base_ammo_rate_milli * front.enemy_pressure_centi * MULTIPLIERS[front.posture]
	@warning_ignore("integer_division")
	return (numerator + 5000000) / 10000000
