extends SceneTree

# No graphics device or editor embedding is initialized by this test.
func _initialize() -> void:
	call_deferred("_verify")

func _verify() -> void:
	var scene: PackedScene = load("res://debug/inspector.tscn")
	var inspector: Control = scene.instantiate()
	root.add_child(inspector)
	await process_frame
	if Engine.max_fps != 30 or not OS.low_processor_usage_mode or inspector.sim != null or not inspector.status.text.begins_with("Ready"):
		print("HEADLESS INSPECTOR: startup bounds failed")
		quit(1)
		return
	inspector._export()
	if not inspector.status.text.begins_with("Run the demonstration"):
		print("HEADLESS INSPECTOR: export-before-run feedback failed")
		quit(1)
		return
	inspector._run()
	if inspector.sim == null or inspector.sim.world.clock().tick_index != 17 or not inspector.status.text.begins_with("Demonstration passed"):
		print("HEADLESS INSPECTOR: manual demonstration failed")
		quit(1)
		return
	inspector._export()
	if not inspector.status.text.begins_with("Export + replay passed"):
		print("HEADLESS INSPECTOR: replay failed")
		quit(1)
		return
	print("HEADLESS INSPECTOR: idle startup, 30 FPS cap, low-processor mode, manual demonstration and replay passed")
	quit(0)
