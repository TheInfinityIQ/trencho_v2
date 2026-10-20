extends RefCounted
const Base = preload("res://kernel/prompt_evaluation_config.gd")
const FIELD = "strategic_subordinate_reporting_enabled"
const SCHEMA = "2C.5.information-collection-config.1"

static func extract(definition: Dictionary) -> Dictionary:
	return Base.extract(definition, FIELD)

static func normalize(configuration: Variant, commands: Dictionary) -> Dictionary:
	return Base.normalize(configuration, commands, 1.0)
