extends "res://kernel/service.gd"

func reparent(id: String, parent: Variant) -> Dictionary:
	if not sim.privileged():
		return R.fail("UNAUTHORIZED")
	var command: Dictionary = world.get_command(id)
	if command.is_empty() or (parent != null and world.get_command(parent).is_empty()):
		return R.fail("INVALID_ENTITY")
	var cursor: Variant = parent
	while cursor != null:
		if cursor == id:
			return R.fail("HIERARCHY_CYCLE")
		cursor = world.get_command(cursor).superior_command_id
	var old: Variant = command.superior_command_id
	var patches: Array = []
	if old == parent:
		return R.ok(id)
	if old != null:
		var previous: Dictionary = world.get_command(old)
		previous.subordinate_command_ids.erase(id)
		patches.append(change("commands", previous))
	if parent != null:
		var next: Dictionary = world.get_command(parent)
		next.subordinate_command_ids.append(id)
		next.subordinate_command_ids.sort()
		patches.append(change("commands", next))
	command.superior_command_id = parent
	patches.append(change("commands", command))
	sim.commit("COMMAND_REPARENTED", patches, {"old_superior_id": old, "new_superior_id": parent}, id)
	return R.ok(id)
