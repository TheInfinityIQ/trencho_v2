extends RefCounted
# Uses the accepted autonomous prototype without any115 intelligence changes.
const Base = preload("res://debug/prompt_follow_up_demo.gd")

static func definition() -> Dictionary:
	var data := Base.definition(true, true)
	data.id = "step115"
	return data
