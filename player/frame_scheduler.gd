extends RefCounted
# Wall time is scheduling only. The deterministic kernel still advances exactly
# one0.1s tick. Long frames discard debt; there is never a catch-up loop.
const STEP = 0.1
var _elapsed := 0.0

func due(delta: float) -> bool:
	if not is_finite(delta) or delta < 0: return false
	_elapsed += delta
	if _elapsed < STEP: return false
	_elapsed = fmod(_elapsed, STEP) if delta < STEP else 0.0
	return true
