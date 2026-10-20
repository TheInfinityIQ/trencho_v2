extends SceneTree
# Run with the normal GL renderer for screenshots and real GUI event dispatch.
const Session = preload("res://player/game_session.gd")
const Fixture = preload("res://player/battlefield_fixture.gd")
const Demo = preload("res://debug/prompt_follow_up_demo.gd")
const Evaluation = preload("res://debug/prompt_evaluation_demo.gd")
const Simulation = preload("res://kernel/simulation.gd")
const Exporter = preload("res://kernel/run_exporter.gd")
const Scheduler = preload("res://player/frame_scheduler.gd")
const Routing = preload("res://player/prompt_routing.gd")
const Needs = preload("res://tests/resource_resolution_cases.gd")
var checks: Array = []
var evidence: Dictionary = {}
var host: Node
var graphical := false
var viewport_size := Vector2i(1280, 720)

func _initialize() -> void:
	graphical = DisplayServer.get_name() != "headless"
	for argument in OS.get_cmdline_user_args():
		if argument == "1080": viewport_size = Vector2i(1920, 1080)
	root.size = viewport_size
	call_deferred("run")

func check(value: bool, label: String) -> void:
	checks.append({"name": label, "passed": value})
	if not value: print("FAIL115: ", label)

func make_sim(data: Dictionary) -> RefCounted:
	var sim := Simulation.new()
	var result: Dictionary = sim.initialize(data, 115, "step115")
	assert(result.success, JSON.stringify(result))
	return sim

func attach(sim: RefCounted, replay := false) -> void:
	if host != null:
		host.free()
	host = Session.new()
	host.simulation = sim
	host.autonomous = false
	host.replay_mode = replay
	root.add_child(host)
	await process_frame
	await process_frame

func text_tree(node: Node) -> String:
	var result := ""
	if node is Label or node is Button or node is LinkButton: result += node.text + "\n"
	if node is Control: result += node.tooltip_text + "\n"
	for child in node.get_children(): result += text_tree(child)
	return result

func click(button: Button) -> void:
	await process_frame
	if graphical:
		var position := button.get_global_rect().get_center()
		for pressed in [true, false]:
			var event := InputEventMouseButton.new()
			event.position = position
			event.global_position = position
			event.button_index = MOUSE_BUTTON_LEFT
			event.pressed = pressed
			Input.parse_input_event(event)
			await process_frame
	else:
		button.pressed.emit()
	await process_frame

func capture(name: String) -> void:
	await process_frame
	await process_frame
	if graphical:
		# Low-processor mode may have no next redraw while the fixture is paused.
		# Force one real GPU frame for this screenshot, without changing runtime settings.
		RenderingServer.force_draw(false)
		var path := "res://artifacts/115_%s_%d.png" % [name, viewport_size.y]
		var rendered := root.get_texture().get_image()
		check(rendered.get_size() == viewport_size, "actual render dimensions " + name)
		check(rendered.save_png(path) == OK, "render capture " + name)
		evidence[name + "_screenshot"] = path

func record(name: String) -> void:
	var sim: RefCounted = host.simulation
	evidence[name] = {"prompts": sim.player_prompt_view().current(), "visible_text": text_tree(host.screen), "tick": sim.world.clock().tick_index, "audit": sim.audit()}
	check(Exporter.export_run(sim, "res://artifacts/run_step115_" + name).success, name + " exports accepted replay package")
	check(Needs.conserved_prefixes(sim), name + " conservation at all prefixes")

func run() -> void:
	# Main-window defaults are applied after SceneTree._initialize.
	root.size = viewport_size
	await process_frame
	await process_frame
	var scheduler := Scheduler.new()
	check(scheduler.due(1000) and not scheduler.due(0) and not scheduler.due(0.01), "long frame yields one tick and discards stall debt")
	check(not scheduler.due(-1) and not scheduler.due(INF), "invalid frame deltas do not accumulate")
	var data := Fixture.definition()
	await attach(make_sim(data))
	check(host.screen.area_buttons.keys() == ["AREA_FRONT_A", "AREA_FRONT_B", "AREA_FRONT_C", "AREA_HQ"], "A all four enabled strategic areas represented")
	check(host.simulation.inputs.is_empty() and host.simulation.player_prompts.events().is_empty(), "A scene creation does not submit inputs or prompts")
	check(host.screen.attention.disabled and host.screen.inquiry.disabled, "A no selection disables both interactions")
	await capture("initial")
	await click(host.screen.area_buttons.AREA_FRONT_C)
	check(host.screen.selected_title.text != "Select an area" and host.screen.area_buttons.AREA_FRONT_C.text.begins_with("[Selected]"), "A mouse selects with textual selection indicator")
	check(host.simulation.inputs.is_empty(), "selection creates no gameplay input")
	await capture("selected")
	var core_before: String = JSON.stringify(host.simulation.snapshot(), "", true, true)
	await click(host.screen.attention)
	check(host.simulation.player_prompt_view().current().size() == 1 and host.simulation.player_prompt_view().current()[0].prompt_type == "DIRECT_ATTENTION", "B one real attention submission from button")
	check(core_before == JSON.stringify(host.simulation.snapshot(), "", true, true), "B prompt submission does not directly mutate authoritative state")
	for unused in range(4): host.refresh()
	check(host.simulation.player_prompt_view().current().size() == 1, "B refresh does not duplicate callbacks or resubmit")
	record("B")
	await attach(make_sim(Demo.definition()))
	await click(host.screen.area_buttons.AREA_FRONT_C)
	await click(host.screen.inquiry)
	check(text_tree(host.screen).contains("Command reply pending"), "D submitted request has distinct pending feedback")
	await capture("pending")
	host.advance_ticks(10)
	check(text_tree(host.screen).contains("does not currently have enough information") and not text_tree(host.screen).contains("Command: Assessment available"), "D insufficient information displayed before acquisition")
	await capture("insufficient")
	host.advance_ticks(5)
	check(text_tree(host.screen).contains("Command: Assessment available") and text_tree(host.screen).contains("Based on a report observed at 00:01"), "D live legitimate follow-up shows observed time and assessment")
	check(host.simulation.player_prompt_view().current().size() == 1, "D live follow-up does not create another prompt")
	await capture("follow_up")
	record("D")
	var stale := Demo.definition(true, false, 0.5, 0.3)
	stale.fronts[2].enemy_pressure = 50
	await attach(make_sim(stale))
	await click(host.screen.area_buttons.AREA_FRONT_C)
	await click(host.screen.inquiry)
	host.advance_ticks(11)
	check(host.simulation.execute({"type": "SetFrontEnemyPressure", "front_id": "FRONT_C", "value": 90}, true).success, "E controlled fixture pressure change accepted")
	host.advance_ticks(7)
	check(host.screen.selected_observer.text.contains("Enemy activity: HIGH") and text_tree(host.screen.history).contains("Enemy activity: MEDIUM"), "E current HIGH and command MEDIUM remain distinct")
	await capture("disagreement")
	record("E")
	var failed := make_sim(Demo.definition())
	check(failed.execute({"type": "SetEnabled", "table": "communication_edges", "entity_id": "OPERATIONAL_COMMAND_to_LOCAL_C", "enabled": false}, true).success, "F controlled unavailable report route")
	await attach(failed)
	await click(host.screen.area_buttons.AREA_FRONT_C)
	await click(host.screen.inquiry)
	host.advance_ticks(20)
	check(text_tree(host.screen).contains("does not currently have enough information") and not text_tree(host.screen).contains("Command: Assessment available"), "F failed acquisition never fabricates available assessment")
	record("F")
	await attach(make_sim(Demo.definition()))
	await click(host.screen.area_buttons.AREA_FRONT_C)
	await click(host.screen.attention)
	host.advance_ticks(15)
	check(host.simulation.information_collections.records()[0].state == "COMPLETED" and host.simulation.player_prompts.snapshot().follow_ups.is_empty(), "G completed attention acquisition has no inquiry-style answer")
	check(text_tree(host.screen.history).contains("You requested attention.") and not text_tree(host.screen.history).contains("You asked:"), "G histories distinguish attention from inquiry")
	record("G")
	var known := Demo.definition()
	known.commands[0].ammunition_arbitration_enabled = true
	var immediate := make_sim(known)
	check(Evaluation.send(immediate, Evaluation.report()).success, "C accepted scripted knowledge fixture sends actual escalation")
	immediate.advance(2)
	await attach(immediate)
	await click(host.screen.area_buttons.AREA_FRONT_C)
	await click(host.screen.inquiry)
	host.advance_ticks(8)
	check(text_tree(host.screen).contains("active ammunition supply problem") and immediate.information_requirements.snapshot().requirements.is_empty() and immediate.information_collections.records().is_empty(), "C supported111 immediate assessment without new acquisition")
	record("C")
	# Variants, selection and rendering are compared using identical run/seed/input.
	var baseline := make_sim(data)
	baseline.advance(250)
	check(Exporter.export_run(baseline, "res://artifacts/run_step115_I_baseline").success, "I untouched baseline exports for exact artifact comparison")
	await attach(make_sim(data))
	host.set_variant(host.screen.ATTENTION_ONLY)
	check(not host.screen.inquiry.visible and host.screen.attention.visible, "I attention-only exposes one strategic action")
	for id in host.screen.area_buttons: host.screen.select_area(id)
	host.screen.select_area("")
	host.advance_ticks(250)
	check(Exporter.observer_equivalent(baseline.snapshot(), host.simulation.snapshot()) and Exporter.observer_equivalent(baseline.events.all(), host.simulation.events.all()) and Exporter.observer_equivalent(baseline.inputs, host.simulation.inputs) and Exporter.observer_equivalent(baseline.player_observer.events(), host.simulation.player_observer.events()) and host.simulation.player_prompts.events().is_empty(), "I selected attention-only250 ticks exactly equals untouched baseline")
	record("I_attention")
	host.set_variant(host.screen.ATTENTION_AND_INQUIRY)
	check(host.screen.inquiry.visible, "I two-action variant exposes inquiry")
	# Real scheduler drives an untouched graphical scene to250 sequential ticks.
	await attach(make_sim(data))
	var started := Time.get_ticks_msec()
	if graphical:
		host.tick_advanced.connect(func(tick):
			if tick == 250: host.autonomous = false)
		host.autonomous = true
		while host.simulation.world.clock().tick_index < 250:
			await process_frame
			if Time.get_ticks_msec() - started > 180000:
				check(false, "K graphical250 ticks timed out")
				break
	else: host.advance_ticks(250)
	check(host.simulation.world.clock().tick_index == 250 and Exporter.observer_equivalent(baseline.snapshot(), host.simulation.snapshot()) and Exporter.observer_equivalent(baseline.events.all(), host.simulation.events.all()) and host.simulation.player_prompts.events().is_empty(), "K untouched scheduler/two-action250 ticks exactly equals deterministic baseline")
	evidence.autonomous_wall_milliseconds = Time.get_ticks_msec() - started
	evidence.renderer = RenderingServer.get_video_adapter_name() if graphical else "headless"
	evidence.rendering_method = RenderingServer.get_current_rendering_method()
	evidence.graphical = graphical
	evidence.viewport = [viewport_size.x, viewport_size.y]
	record("K")
	await click(host.screen.area_buttons.AREA_FRONT_C)
	check(text_tree(host.screen).contains("Supply "), "A visible qualitative logistics after autonomous run")
	await capture("logistics")
	# Automated normal-text/tooltip scan; private exact values and IDs are forbidden.
	var visible := text_tree(host.screen)
	var forbidden := ["OPERATIONAL_COMMAND", "LOCAL_C", "FRONT_C", "information-record:", "shipment:", "coverage_milliseconds", "friendly_strength_centi", "enemy_pressure_centi", "stockpile", "322", "368"]
	for item in forbidden: check(not visible.contains(item), "H normal UI and tooltips hide " + item)
	# Bounds of all strategic controls at the requested viewport.
	for button in host.screen.area_buttons.values() + [host.screen.attention, host.screen.inquiry]:
		check(Rect2(Vector2.ZERO, Vector2(viewport_size)).encloses(button.get_global_rect()), "layout critical button inside viewport: " + button.text.get_slice("\n", 0))
	# Route choice is a trusted, detached projection using110's exact validator.
	var routing_data := Demo.definition()
	var superior: Dictionary = routing_data.commands[0].duplicate(true)
	superior.id = "HIGHER_OPERATIONAL"
	superior.superior_command_id = null
	superior.directly_controlled_stockpile_ids = []
	superior.directly_controlled_location_ids = []
	routing_data.commands[0].superior_command_id = superior.id
	routing_data.commands.append(superior)
	var routed := make_sim(routing_data)
	var routes := Routing.routes(routed.world, routed.player_observer.configuration())
	check(routes.AREA_FRONT_C.recipient_command_id == "OPERATIONAL_COMMAND", "routing selects nearest eligible Operational ancestor")
	check(not routes.AREA_HQ.available, "routing ambiguous frontless scope unavailable")
	routed.execute({"type": "SetEnabled", "table": "commands", "entity_id": "OPERATIONAL_COMMAND", "enabled": false}, true)
	routes = Routing.routes(routed.world, routed.player_observer.configuration())
	check(routes.AREA_FRONT_C.recipient_command_id == "HIGHER_OPERATIONAL", "routing skips disabled nearest Operational for eligible ancestor")
	routed.execute({"type": "SetEnabled", "table": "commands", "entity_id": "HIGHER_OPERATIONAL", "enabled": false}, true)
	await attach(routed)
	host.screen.select_area("AREA_FRONT_C")
	check(host.screen.attention.disabled and host.screen.inquiry.disabled and host.screen.acknowledgement.text == "Command channel unavailable", "routing no eligible command disables both controls and provides plain feedback")
	# Large, distinct private sentinels never cross into ordinary visible text.
	var sentinel_data := Demo.definition()
	sentinel_data.fronts[2].friendly_strength = 57.31
	sentinel_data.fronts[2].enemy_pressure = 61.87
	sentinel_data.fronts[2].base_ammo_demand_per_second = 1337
	sentinel_data.stockpiles[2].quantities.AMMUNITION = 123457
	sentinel_data.stockpiles[4].quantities.AMMUNITION = 0
	sentinel_data.initial_in_transit_shipments[0].quantity = 12347
	var sentinel := make_sim(sentinel_data)
	await attach(sentinel)
	host.screen.select_area("AREA_FRONT_C")
	await click(host.screen.inquiry)
	host.advance_ticks(15)
	var sentinel_text := text_tree(host.screen)
	for forbidden_value in ["5731", "6187", "57.31", "61.87", "1337"]:
		check(not sentinel_text.contains(forbidden_value), "H hidden strength/pressure/demand sentinel " + forbidden_value)
	var private_values: Array = []
	for record_id in sentinel.world.ids("information_records"):
		var information: Dictionary = sentinel.world.get_entity("information_records", record_id)
		if information.fact_key in ["FRONT_AMMO_COVERAGE_MILLISECONDS", "FRONT_LAST_SHORTAGE"] and information.value is int and information.value > 100: private_values.append(information.value)
	for front_id in sentinel.world.ids("fronts"):
		var front: Dictionary = sentinel.world.get_front(front_id)
		for key in ["ammo_coverage_milliseconds", "last_interval_shortage"]:
			if front.get(key) is int and front[key] > 100: private_values.append(front[key])
	for stock_id in sentinel.world.ids("stockpiles"):
		for value in sentinel.world.get_stockpile(stock_id).quantities.values():
			if value > 100: private_values.append(value)
	for shipment_id in sentinel.world.ids("shipments"):
		var quantity: int = sentinel.world.get_entity("shipments", shipment_id).get("quantity", 0)
		if quantity > 100: private_values.append(quantity)
	for value in private_values: check(not sentinel_text.contains(str(value)), "H exact private coverage/shortage/stock/shipment quantity hidden: " + str(value))
	evidence.sentinel_scan = {"distinct_fixture_values": [5731, 6187, 1337], "additional_private_values": private_values}
	Exporter.write_json("res://artifacts/step115_results_%d.json" % viewport_size.y, {"checks": checks, "evidence": evidence, "failures": checks.filter(func(item): return not item.passed)})
	print("STEP115: %d checks, %d failed; graphical=%s" % [checks.size(), checks.filter(func(item): return not item.passed).size(), graphical])
	quit(0 if checks.all(func(item): return item.passed) else 1)
