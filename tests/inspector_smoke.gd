extends SceneTree

func _initialize() -> void:
	call_deferred("_capture")

func _capture() -> void:
	var scene: PackedScene = load("res://debug/inspector.tscn")
	var inspector: Control = scene.instantiate()
	root.add_child(inspector)
	await process_frame
	await process_frame
	if inspector.sim != null or not inspector.status.text.begins_with("Ready"):
		print("INSPECTOR SMOKE: startup unexpectedly ran the simulation")
		quit(1)
		return
	inspector._run()
	if inspector.sim == null or not inspector.status.text.begins_with("Demonstration passed"):
		print("INSPECTOR SMOKE: failed initialization")
		quit(1)
		return
	inspector._export()
	if not inspector.status.text.begins_with("Export + replay passed"):
		print("INSPECTOR SMOKE: failed export/replay")
		quit(1)
		return
	await process_frame
	var image: Image = root.get_texture().get_image()
	var result: int = image.save_png("res://artifacts/inspector.png")
	print("INSPECTOR SMOKE: initialization, demonstration, export, replay and screenshot ", "passed" if result == OK else "failed")
	quit(0 if result == OK else 1)
