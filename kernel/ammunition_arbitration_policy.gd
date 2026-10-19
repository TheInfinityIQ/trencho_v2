extends RefCounted
# Pure report/own-stock policy. Continued fractions compare ratios without products.
const THRESHOLDS = [5000, 15000, 20000]
const MAX_SAFE = 9007199254740991

static func required_stock(rate: int, milliseconds: int) -> int:
	return (rate * milliseconds + 999999) / 1000000

static func ratio_compare(a: int, b: int, c: int, d: int) -> int:
	var direction := 1
	while true:
		var qa: int = a / b
		var qc: int = c / d
		if qa != qc: return direction * (-1 if qa < qc else 1)
		var ra := a % b
		var rc := c % d
		if ra == 0 or rc == 0:
			return 0 if ra == rc else direction * (-1 if ra == 0 else 1)
		a = b
		b = ra
		c = d
		d = rc
		direction = -direction
	return 0

static func urgency(value: String) -> int:
	return {"CRITICAL": 2, "CONSTRAINED": 1, "REFILL": 0}.get(value, -1)

static func before(a: Dictionary, b: Dictionary) -> bool:
	var ua := urgency(a.get("urgency", "REFILL"))
	var ub := urgency(b.get("urgency", "REFILL"))
	if ua != ub: return ua > ub
	var ar := int(a.get("reported_planning_rate_milli", 0))
	var br := int(b.get("reported_planning_rate_milli", 0))
	if ar > 0 and br > 0:
		var comparison := ratio_compare(int(a.projected_stock), ar, int(b.projected_stock), br)
		if comparison != 0: return comparison < 0
	if a.requesting_command_id != b.requesting_command_id: return a.requesting_command_id < b.requesting_command_id
	return a.need_id < b.need_id
