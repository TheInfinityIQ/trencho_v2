extends RefCounted
const Base = preload("res://kernel/prompt_evaluation_config.gd")
const FIELD = "strategic_information_requirements_enabled"
const SCHEMA = "2C.4.information-requirement-config.1"

static func extract(definition: Dictionary) -> Dictionary:
	return Base.extract(definition, FIELD)

static func normalize(configuration: Variant, commands: Dictionary) -> Dictionary:
	# No independent cadence:112 can only follow an actual111 evaluation.
	return Base.normalize(configuration, commands, 1.0)
