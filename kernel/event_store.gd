extends RefCounted

var _events: Array = []

func append(event: Dictionary) -> void:
	_events.append(event.duplicate(true))

func all() -> Array:
	return _events.duplicate(true)

func count() -> int:
	return _events.size()

