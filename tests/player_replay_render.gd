extends SceneTree
const Exporter = preload("res://kernel/run_exporter.gd")
const Session = preload("res://player/game_session.gd")
func _initialize() -> void:
	call_deferred("verify")
func verify() -> void:
	var directory := "res://artifacts/run_step115_D"
	var verified := Exporter.replay_package(directory)
	assert(verified.success, JSON.stringify(verified))
	var initial: Dictionary = Exporter.read_json(directory.path_join("initial_world.json")).details.value
	var inputs: Array = Exporter.read_lines(directory.path_join("inputs.jsonl")).details.value
	var manifest: Dictionary = Exporter.read_json(directory.path_join("manifest.json")).details.value
	var areas: Dictionary = Exporter.read_json(directory.path_join("player_observer_config.json")).details.value.strategic_areas
	var configurations: Array = []
	for file in ["player_prompt_evaluation_config.json", "player_prompt_information_requirement_config.json", "information_collection_config.json", "player_prompt_follow_up_config.json"]:
		configurations.append(Exporter.read_json(directory.path_join(file)).details.value.commands)
	var result := Exporter.replay(initial, inputs, manifest.end_tick, areas.values(), configurations[0], configurations[1], configurations[2], configurations[3])
	assert(result.success, JSON.stringify(result))
	var host := Session.new()
	host.simulation = result.details.simulation
	host.replay_mode = true
	host.autonomous = false
	root.add_child(host)
	host.screen.select_area("AREA_FRONT_C")
	var before := JSON.stringify(host.simulation.inputs, "", true, true)
	for unused in range(5):
		host.refresh()
		await process_frame
	assert(host.screen.attention.disabled and host.screen.inquiry.disabled)
	assert(host.simulation.player_prompt_view().current()[0].latest_follow_up.enemy_activity == "HIGH")
	var visible := ""
	for child in host.screen.history.get_children(): visible += child.text
	assert(visible.contains("Command: Assessment available") and visible.contains("Based on a report observed at 00:01"))
	assert(before == JSON.stringify(host.simulation.inputs, "", true, true))
	if DisplayServer.get_name() != "headless":
		RenderingServer.force_draw(false)
		assert(root.get_texture().get_image().save_png("res://artifacts/115_replay_720.png") == OK)
	Exporter.write_json("res://artifacts/step115_replay_render.json", {"strict_replay": verified, "no_new_inputs": true, "requests_disabled": true, "rendered_follow_up": host.simulation.player_prompt_view().current()})
	print("STEP115 J: fresh-process strict replay, qualitative history rendering, disabled requests and no new inputs passed")
	quit()
