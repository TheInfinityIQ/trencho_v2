extends "res://kernel/service.gd"

func can_dispatch(command_id: String, stockpile_id: String) -> bool:
	var command: Dictionary = world.get_command(command_id)
	return not command.is_empty() and command.enabled and stockpile_id in command.directly_controlled_stockpile_ids


func can_set_front_posture(command_id: String, front_id: String) -> bool:
	var command: Dictionary = world.get_command(command_id)
	var front: Dictionary = world.get_front(front_id)
	return not command.is_empty() and command.enabled and command.command_level == "LOCAL" and not front.is_empty() and front.enabled and front.responsible_command_id == command_id
