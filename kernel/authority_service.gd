extends "res://kernel/service.gd"

func can_dispatch(command_id: String, stockpile_id: String) -> bool:
	var command: Dictionary = world.get_command(command_id)
	return not command.is_empty() and command.enabled and stockpile_id in command.directly_controlled_stockpile_ids

