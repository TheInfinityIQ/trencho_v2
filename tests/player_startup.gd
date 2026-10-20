extends SceneTree
func _initialize() -> void:
	call_deferred("verify")
func verify() -> void:
	assert(ProjectSettings.get_setting("application/run/main_scene") == "res://player/battlefield.tscn")
	var packed: PackedScene = load(ProjectSettings.get_setting("application/run/main_scene"))
	var player: Node = packed.instantiate()
	root.add_child(player)
	var started := Time.get_ticks_msec()
	while player.simulation.world.clock().tick_index < 3:
		await process_frame
		assert(Time.get_ticks_msec() - started < 10000)
	assert(Engine.max_fps == 30 and OS.low_processor_usage_mode)
	assert(player.simulation.inputs.is_empty() and player.simulation.player_prompts.events().is_empty())
	var before: int = player.simulation.world.clock().tick_index
	player._process(1000.0)
	assert(player.simulation.world.clock().tick_index == before + 1)
	player._process(0.0)
	assert(player.simulation.world.clock().tick_index == before + 1)
	player.autonomous = false
	print("STEP115 STARTUP: actual F5 scene autonomous, zero inputs,30FPS,low-processor,one exact tick per stalled frame and no debt burst passed")
	quit()
