extends RefCounted

# Integer microseconds define supported time precision; ticks own authoritative time.
static func units(seconds: float) -> int:
	return roundi(seconds * 1000000.0)

static func seconds(tick: int, duration: float) -> float:
	return tick * units(duration) / 1000000.0

