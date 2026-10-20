extends RefCounted
# Trusted routing projection. Only availability reaches player controls; command
# identities remain here/session-side and never enter visible UI text or tooltips.
const Prompts = preload("res://kernel/player_prompt_service.gd")

static func routes(world: RefCounted, areas: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for id in areas:
		var area: Dictionary = areas[id]
		var recipients: Array = []
		if area.enabled and area.front_id != null:
			var command: Dictionary = world.get_command(world.get_front(area.front_id).get("responsible_command_id", ""))
			while not command.is_empty():
				if eligible(world, areas, id, command.id):
					recipients.append(command.id)
					break
				command = world.get_command(command.superior_command_id) if command.superior_command_id is String else {}
		elif area.enabled:
			for command_id in world.ids("commands"):
				if eligible(world, areas, id, command_id): recipients.append(command_id)
		result[id] = {"available": recipients.size() == 1, "recipient_command_id": recipients[0] if recipients.size() == 1 else null}
	return result

static func eligible(world: RefCounted, areas: Dictionary, area: String, command: String) -> bool:
	return Prompts.validate({"type": "SubmitPlayerPrompt", "prompt_type": "DIRECT_ATTENTION", "area_id": area, "recipient_command_id": command}, areas, world).success

static func availability(routing: Dictionary) -> Dictionary:
	var result: Dictionary = {}
	for id in routing: result[id] = routing[id].available
	return result
