extends RefCounted
const Base = preload("res://kernel/prompt_evaluation_config.gd")
const FIELD = "strategic_prompt_follow_up_enabled"
const SCHEMA = "2C.6.prompt-follow-up-config.1"

static func extract(definition: Dictionary) -> Dictionary:
	return Base.extract(definition, FIELD)

static func normalize(configuration: Variant, commands: Dictionary) -> Dictionary:
	return Base.normalize(configuration, commands, 1.0)
